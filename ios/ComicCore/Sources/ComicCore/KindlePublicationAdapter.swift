import Foundation

public enum KindlePublicationAdapter {
    /// Synchronous work intended for a background task. Only a verified EPUB is published.
    public static func convert(source: URL, to destination: URL) throws -> EpubPublication {
        try Task.checkCancellation()
        let manager = FileManager.default
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL
        guard source != destination.resolvingSymlinksInPath(), !manager.fileExists(atPath: destination.path) else {
            throw EpubError.invalid("Kindle 转换目标已存在或与原书相同")
        }
        let detection = try KindleFormatDetector.detect(source)
        guard detection.isReadable else { throw EpubError.invalid(detection.unsupportedReason ?? "该 Kindle 电子书不受支持") }
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let scratch = parent.appendingPathComponent(".kindle-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: scratch, withIntermediateDirectories: false)
        // Only this successfully created, direct child is ever recursively removed.
        defer {
            if scratch.deletingLastPathComponent() == parent, scratch.lastPathComponent.hasPrefix(".kindle-") {
                try? manager.removeItem(at: scratch)
            }
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let fileSize = try input.seekToEnd()
        func read(_ offset: UInt64, _ size: Int) throws -> Data {
            guard offset <= fileSize, size >= 0, UInt64(size) <= fileSize - offset else { throw EpubError.invalid("Kindle 记录越界") }
            try input.seek(toOffset: offset)
            var data = Data()
            while data.count < size {
                try Task.checkCancellation()
                let count = min(65536, size - data.count)
                guard let block = try input.read(upToCount: count), block.count == count else { throw EpubError.invalid("Kindle 记录截断") }
                data.append(block)
            }
            return data
        }
        let pdb = try read(0, 78), count = Int(pdb[76]) << 8 | Int(pdb[77])
        guard count > 0, count == detection.recordCount else { throw EpubError.invalid("Kindle 记录表为空或已变化") }
        let tableEnd = 78 + count * 8, table = try read(78, count * 8)
        var offsets: [UInt64] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let offset = UInt64(uint32(table, index * 8))
            guard offset >= UInt64(tableEnd), offset < fileSize, offsets.last.map({ offset > $0 }) ?? true else {
                throw EpubError.invalid("Kindle 记录偏移无效")
            }
            offsets.append(offset)
        }
        offsets.append(fileSize)
        guard offsets[1] - offsets[0] >= 16 else { throw EpubError.invalid("Kindle PalmDOC 头部截断") }
        let doc = try read(offsets[0], 16), compression = Int(doc[0]) << 8 | Int(doc[1])
        guard doc[12] == 0, doc[13] == 0 else { throw EpubError.invalid("该电子书受 DRM 加密保护") }
        guard [1, 2].contains(compression), compression == detection.compression else { throw EpubError.invalid("Kindle 压缩方式不受支持或已变化") }
        let declared = uint32(doc, 4), textCount = Int(doc[8]) << 8 | Int(doc[9])
        guard textCount <= count - 1 else { throw EpubError.invalid("Kindle 正文记录缺失") }
        let lastText = detection.kf8BoundaryRecord > 0 && detection.kf8BoundaryRecord < textCount ? detection.kf8BoundaryRecord - 1 : textCount
        let textLimit = declared > 0 && declared < Int32.max ? min(Int(declared), 8 * 1024 * 1024) : 8 * 1024 * 1024
        var text = Data(), compressedBytes = 0
        if lastText > 0 {
            for index in 1...lastText {
                try Task.checkCancellation()
                let size = Int(offsets[index + 1] - offsets[index])
                guard size <= 8 * 1024 * 1024 else { throw EpubError.limitExceeded("Kindle 单条正文超过 8 MiB") }
                if compression == 2 {
                    compressedBytes += size
                    guard compressedBytes <= 16 * 1024 * 1024 else { throw EpubError.limitExceeded("Kindle 压缩正文超过 16 MiB") }
                    text.append(try read(offsets[index], size))
                } else if text.count < textLimit {
                    text.append(try read(offsets[index], min(size, textLimit - text.count)))
                }
            }
        }
        if compression == 2 { text = try PalmDoc.decompress(text, maximumOutputBytes: textLimit) }
        try Task.checkCancellation()
        let encoding: String.Encoding = detection.encoding == "Windows-1252" ? .windowsCP1252 : .utf8
        guard let html = String(data: text, encoding: encoding) else { throw EpubError.invalid("Kindle 正文编码损坏，无法无损解码") }
        var images: [KindleEpubWriter.Image] = [], imageBytes: UInt64 = 0
        if detection.firstImageRecord > 0, detection.firstImageRecord < count {
            // Count control records too, before spending time copying hundreds of MiB.
            for index in detection.firstImageRecord..<count {
                try Task.checkCancellation()
                let size = offsets[index + 1] - offsets[index]
                imageBytes += size
                guard size <= 16 * 1024 * 1024, imageBytes <= 512 * 1024 * 1024 else {
                    throw EpubError.limitExceeded("Kindle 图片记录超过单条 16 MiB 或累计 512 MiB")
                }
            }
            for index in detection.firstImageRecord..<count {
                try Task.checkCancellation()
                let size = Int(offsets[index + 1] - offsets[index])
                guard let ext = imageExtension(try read(offsets[index], min(size, 12))) else { continue }
                let relative = index - detection.firstImageRecord + 1
                let image = KindleEpubWriter.Image(index: relative, file: scratch.appendingPathComponent("img_\(relative).\(ext)"),
                                                  size: size, ext: ext, cover: index == detection.coverRecordIndex)
                guard manager.createFile(atPath: image.file.path, contents: nil) else { throw EpubError.invalid("无法暂存 Kindle 图片") }
                let output = try FileHandle(forWritingTo: image.file)
                do {
                    defer { try? output.close() }
                    var position = 0
                    while position < size {
                        let block = try read(offsets[index] + UInt64(position), min(65536, size - position))
                        try output.write(contentsOf: block)
                        position += block.count
                    }
                }
                images.append(image)
            }
        }
        let derived = scratch.appendingPathComponent("derived.epub")
        try KindleEpubWriter.write(to: derived, detection: detection, html: html, images: images)
        let publication = try EpubParser.parse(archive: derived)
        try Task.checkCancellation()
        // FileManager's move refuses an existing destination, including one created during conversion.
        try manager.moveItem(at: derived, to: destination)
        return publication
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private static func imageExtension(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x89, 80, 78, 71]) { return "png" }
        if data.starts(with: "GIF8".utf8) { return "gif" }
        if data.count >= 12, data.starts(with: "RIFF".utf8), data[8..<12].elementsEqual("WEBP".utf8) { return "webp" }
        if data.starts(with: "BM".utf8) { return "bmp" }
        return nil
    }
}
