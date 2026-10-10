import Foundation
import ZIPFoundation

enum KindleEpubWriter {
    struct Image {
        let index: Int
        let file: URL
        let size: Int
        let ext: String
        let cover: Bool
        var name: String { "img_\(index).\(ext)" }
        var mime: String { "image/" + (ext == "jpg" ? "jpeg" : ext) }
    }
    private struct Page {
        let title: String
        let body: String
        let path: String
    }

    static func write(to url: URL, detection: KindleDetection, html: String, images: [Image]) throws {
        let scan = HTMLScan()
        let plain = try scan.replace(#"<[^>]+>"#, in: html) { _ in "" }
        let visible: String
        let comic: Bool
        if images.count >= 3 {
            visible = try scan.replace(#"&(?:nbsp|#0*160|#x0*a0);|[ \t\n\x0B\f\r\u00a0\u3000]+"#, in: plain) { _ in "" }
            comic = visible.utf16.count < 300
        } else {
            let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.contains("&") {
                visible = try scan.replace(#"&(?:nbsp|#0*160|#x0*a0);|[ \t\n\x0B\f\r\u00a0\u3000]+"#, in: plain) { _ in "" }
            } else {
                visible = trimmed
            }
            comic = false
        }
        var pages: [Page] = []
        let imageMap = Dictionary(uniqueKeysWithValues: images.map { ($0.index, $0) })
        if comic {
            for (index, image) in images.enumerated() {
                try Task.checkCancellation()
                pages.append(Page(title: "Page \(index + 1)", body: "<img src=\"../images/\(image.name)\" style=\"max-width:100%;max-height:100%;\"/>", path: "text/page_\(index + 1).xhtml"))
            }
        } else {
            let parts = try scan.split(#"<(?:mbp:pagebreak|pagebreak)[^>]*>"#, in: html, maximum: 50_000 - images.count - 1)
            for part in parts {
                try Task.checkCancellation()
                let body = try scan.replace(#"<(?:img|image)[^>]*recindex=["']?([0-9]+)["']?[^>]*>"#, in: part) { groups in
                    guard let index = Int(groups[1]), let image = imageMap[index] else { return "" }
                    return "<p style=\"text-align:center;\"><img src=\"../images/\(image.name)\" style=\"max-width:100%;\"/></p>"
                }
                let number = pages.count + 1
                var title = "第 \(number) 章"
                if let heading = try scan.first(#"<(?:h1|h2|h3|h4)[^>]*>(.*?)</(?:h1|h2|h3|h4)>"#, in: body) {
                    let candidate = SearchRules.trim(try scan.replace(#"<[^>]+>"#, in: heading) { _ in "" })
                    if !candidate.isEmpty && candidate.utf16.count < 50 { title = candidate }
                }
                pages.append(Page(title: title, body: body, path: "text/chapter_\(number).xhtml"))
            }
            guard !visible.isEmpty || pages.contains(where: { $0.body.contains("../images/") }) else {
                throw EpubError.invalid("Kindle 没有可阅读的正文或漫画内容")
            }
        }
        guard !pages.isEmpty else { throw EpubError.invalid("Kindle 没有可阅读的正文或漫画内容") }
        guard pages.count <= 100_000, 1 + pages.count + images.count <= 50_000 else { throw EpubError.limitExceeded("Kindle 派生 EPUB manifest 超过 50000 或 spine 超过 100000") }
        try scan.check()
        let title = detection.title.isEmpty ? "未命名电子书" : detection.title
        let escapedTitle = try xml(title), escapedAuthor = try xml(detection.author)
        let cover = images.first(where: \.cover) ?? images.first
        let archive = try Archive(url: url, accessMode: .create)
        func write(_ path: String, _ value: String) throws {
            try Task.checkCancellation()
            let bytes = Data(value.utf8)
            guard !path.hasSuffix(".xhtml") || bytes.count <= 8 * 1024 * 1024 else {
                throw EpubError.limitExceeded("Kindle 派生正文资源超过 8 MiB，阅读器无法读取")
            }
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count), compressionMethod: .none, bufferSize: 65536) { position, size in
                try Task.checkCancellation()
                return bytes.subdata(in: Int(position)..<min(Int(position) + size, bytes.count))
            }
        }
        try write("mimetype", "application/epub+zip")
        try write("META-INF/container.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>")
        for image in images {
            try Task.checkCancellation()
            let input = try FileHandle(forReadingFrom: image.file)
            defer { try? input.close() }
            try archive.addEntry(with: "OEBPS/images/" + image.name, type: .file, uncompressedSize: Int64(image.size), compressionMethod: .none, bufferSize: 65536) { position, size in
                try Task.checkCancellation()
                try input.seek(toOffset: UInt64(position))
                guard let block = try input.read(upToCount: size), block.count == size else { throw EpubError.invalid("Kindle 暂存图片截断") }
                return block
            }
        }
        var manifest = "<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>", spine = "", nav = ""
        for image in images {
            try Task.checkCancellation()
            let selected = image.index == cover?.index
            manifest += "<item id=\"\(selected ? "cover-image" : "img_\(image.index)")\" href=\"images/\(image.name)\" media-type=\"\(image.mime)\"\(selected ? " properties=\"cover-image\"" : "")/>"
        }
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let escaped = try xml(page.title), id = "page_\(index + 1)"
            try write("OEBPS/" + page.path, "<?xml version=\"1.0\" encoding=\"UTF-8\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>\(escaped)</title><meta charset=\"utf-8\"/></head><body>\(page.body)</body></html>")
            manifest += "<item id=\"\(id)\" href=\"\(page.path)\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"\(id)\"/>"
            nav += "<navPoint id=\"nav_\(index + 1)\" playOrder=\"\(index + 1)\"><navLabel><text>\(escaped)</text></navLabel><content src=\"\(page.path)\"/></navPoint>"
        }
        let identifier = "urn:uuid:" + UUID().uuidString
        try write("OEBPS/toc.ncx", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\"><head><meta name=\"dtb:uid\" content=\"\(identifier)\"/></head><docTitle><text>\(escapedTitle)</text></docTitle><navMap>\(nav)</navMap></ncx>")
        let coverMeta = cover == nil ? "" : "<meta name=\"cover\" content=\"cover-image\"/>"
        try write("OEBPS/content.opf", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"BookId\" version=\"2.0\"><metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\(escapedTitle)</dc:title><dc:creator>\(escapedAuthor)</dc:creator><dc:identifier id=\"BookId\">\(identifier)</dc:identifier><dc:language>zh</dc:language>\(coverMeta)</metadata><manifest>\(manifest)</manifest><spine toc=\"ncx\">\(spine)</spine></package>")
        try Task.checkCancellation()
    }

    private static func xml(_ value: String) throws -> String {
        var result = ""
        for (index, scalar) in value.unicodeScalars.enumerated() {
            if index % 4096 == 0 { try Task.checkCancellation() }
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Every untrusted HTML regex shares this one monotonic deadline. ICU's progress
    /// callback can interrupt backtracking even when there has not been a match yet.
    private final class HTMLScan {
        private let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        func check() throws {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw EpubError.limitExceeded("Kindle HTML 扫描超过 2 秒") }
        }
        private func matches(_ pattern: String, _ text: String, _ visit: (NSTextCheckingResult, NSString) throws -> Bool) throws {
            try check()
            // Every tag pattern requires '<'. Foundation's literal search avoids invoking
            // ICU progress callbacks over a multi-MiB plain-text PalmDOC body.
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive), ns = text as NSString
            var range = NSRange(location: 0, length: ns.length)
            if pattern.hasPrefix("<") {
                let first = ns.range(of: "<", options: .literal)
                guard first.location != NSNotFound else { try check(); return }
                range = NSRange(location: first.location, length: ns.length - first.location)
            }
            var failure: Error?, callbacks = 0
            withoutActuallyEscaping(visit) { visit in
                regex.enumerateMatches(in: text, options: .reportProgress, range: range) { match, _, stop in
                    do {
                        callbacks += 1
                        try Task.checkCancellation()
                        if match != nil || callbacks % 128 == 0 { try self.check() }
                        if let match, try !visit(match, ns) { stop.pointee = true }
                    } catch { failure = error; stop.pointee = true }
                }
            }
            if let failure { throw failure }
            try check()
        }
        private func append(_ ns: NSString, _ range: NSRange, to output: NSMutableString) throws {
            var offset = range.location
            while offset < NSMaxRange(range) {
                try check()
                var size = min(32768, NSMaxRange(range) - offset)
                // NSString ranges are UTF-16; never bridge half a surrogate pair to Swift.
                if offset + size < NSMaxRange(range), (0xD800...0xDBFF).contains(ns.character(at: offset + size - 1)) { size += 1 }
                output.append(ns.substring(with: NSRange(location: offset, length: size)))
                offset += size
            }
        }
        func replace(_ pattern: String, in text: String, transform: ([String]) throws -> String) throws -> String {
            let result = NSMutableString(capacity: text.utf16.count)
            var end = 0
            try matches(pattern, text) { match, ns in
                try append(ns, NSRange(location: end, length: match.range.location - end), to: result)
                let groups = (0..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
                result.append(try transform(groups)); end = NSMaxRange(match.range)
                return true
            }
            // No match means no transformation. Avoid copying multi-MiB novels on every scan.
            if end == 0 { return text }
            let ns = text as NSString
            try append(ns, NSRange(location: end, length: ns.length - end), to: result)
            return result as String
        }
        func first(_ pattern: String, in text: String) throws -> String? {
            var result: String?
            try matches(pattern, text) { match, ns in result = ns.substring(with: match.range(at: 1)); return false }
            return result
        }
        func split(_ pattern: String, in text: String, maximum: Int) throws -> [String] {
            var result: [String] = [], end = 0
            func add(_ ns: NSString, _ range: NSRange) throws {
                try check()
                let part = ns.substring(with: range)
                if part.unicodeScalars.contains(where: { $0.value > 32 }) {
                    guard result.count < maximum else { throw EpubError.limitExceeded("Kindle 派生 EPUB manifest 超过 50000") }
                    result.append(part)
                }
            }
            try matches(pattern, text) { match, ns in
                try add(ns, NSRange(location: end, length: match.range.location - end)); end = NSMaxRange(match.range)
                return true
            }
            try add(text as NSString, NSRange(location: end, length: (text as NSString).length - end))
            return result
        }
    }
}
