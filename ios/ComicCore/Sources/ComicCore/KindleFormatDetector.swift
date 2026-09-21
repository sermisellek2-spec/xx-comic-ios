import Foundation

public enum KindleVariant: String, Sendable {
    case mobi7, kf8, combo, palmDoc, kfx, topaz, unknown, corrupt
}

public enum KindleDRM: String, Sendable {
    case none, mobipocket, amazon, kfx
}

public struct KindleDetection: Equatable, Sendable {
    public let variant: KindleVariant
    public let drm: KindleDRM
    public let isReadable: Bool
    public let unsupportedReason: String?
    public let title: String
    public let author: String
    public let compression: Int
    public let encoding: String
    public let recordCount: Int
    public let firstImageRecord: Int
    public let coverRecordIndex: Int
    public let kf8BoundaryRecord: Int
}

public enum KindleFormatDetector {
    public static func detect(_ file: URL) throws -> KindleDetection {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        do {
            let result = try inspect(handle, fileSize: fileSize)
            try Task.checkCancellation()
            return result
        } catch let failure as InvalidFormat {
            try Task.checkCancellation()
            return unsupported(.corrupt, reason: failure.reason)
        }
    }

    private struct InvalidFormat: Error { let reason: String }

    private static func unsupported(_ variant: KindleVariant, drm: KindleDRM = .none, reason: String) -> KindleDetection {
        KindleDetection(variant: variant, drm: drm, isReadable: false, unsupportedReason: reason,
                        title: "", author: "", compression: 0, encoding: "UTF-8", recordCount: 0,
                        firstImageRecord: -1, coverRecordIndex: -1, kf8BoundaryRecord: -1)
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 |
        UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private static func inspect(_ handle: FileHandle, fileSize: UInt64) throws -> KindleDetection {
        func read(_ offset: UInt64, _ count: Int) throws -> Data {
            try Task.checkCancellation()
            guard offset <= fileSize, UInt64(count) <= fileSize - offset else {
                throw InvalidFormat(reason: "电子书数据超出文件范围")
            }
            try handle.seek(toOffset: offset)
            guard let bytes = try handle.read(upToCount: count), bytes.count == count else {
                throw InvalidFormat(reason: "电子书数据截断")
            }
            return bytes
        }
        guard fileSize >= 8 else { throw InvalidFormat(reason: "文件截断：大小过小") }
        let magic = try read(0, 8)
        if magic.starts(with: [0xEA, 75, 70, 88]) {
            return unsupported(.kfx, drm: .kfx, reason: "文件为 Amazon KFX 专有受保护格式，目前不支持直接解析")
        }
        if magic.starts(with: "TPZ".utf8) || magic.starts(with: "azw1".utf8) {
            return unsupported(.topaz, drm: .amazon, reason: "文件为 Amazon Topaz (AZW1/TPZ) 矢量格式，暂不支持")
        }
        guard fileSize >= 78 else { throw InvalidFormat(reason: "PDB 文件头不完整") }
        let header = try read(0, 78)
        let type = String(decoding: header[60..<64], as: UTF8.self)
        let creator = String(decoding: header[64..<68], as: UTF8.self)
        guard type == "BOOK" || type == "TEXt" || creator == "MOBI" else {
            return unsupported(.unknown, reason: "不是支持的 Kindle / PalmDOC 电子书容器")
        }
        let count = Int(header[76]) << 8 | Int(header[77])
        guard count > 0 else { throw InvalidFormat(reason: "PDB 记录表为空") }
        // count is an unsigned 16-bit value, so this arithmetic cannot overflow.
        let tableEnd = UInt64(78 + count * 8)
        guard tableEnd <= fileSize else { throw InvalidFormat(reason: "PDB 记录表超出文件范围") }
        var record0: UInt64 = 0, recordEnd = fileSize, previous: UInt64 = 0
        for index in 0..<count {
            // Keep cancellation observable while scanning very large record
            // tables. FileHandle reads can otherwise complete the whole table
            // before a concurrently cancelled task gets a scheduling point.
            if index % 256 == 0 {
                try Task.checkCancellation()
                Thread.sleep(forTimeInterval: 0.00005)
            }
            let entry = try read(UInt64(78 + index * 8), 8)
            let offset = UInt64(uint32(entry, 0))
            guard offset >= tableEnd, offset < fileSize, index == 0 || offset > previous else {
                throw InvalidFormat(reason: "电子书记录偏移无效")
            }
            if index == 0 { record0 = offset }
            if index == 1 { recordEnd = offset }
            previous = offset
        }
        let recordLength = recordEnd - record0
        guard recordLength >= 16 else { throw InvalidFormat(reason: "PalmDOC 头部不完整") }
        let doc = try read(record0, 16)
        let compression = Int(doc[0]) << 8 | Int(doc[1])
        let encryption = Int(doc[12]) << 8 | Int(doc[13])
        guard compression == 1 || compression == 2 else {
            return unsupported(.unknown, reason: "暂不支持此电子书压缩方式（包括 HUFF/CDIC）")
        }
        let pdbName = SearchRules.trim(String(data: Data(header.prefix(32).prefix(while: { $0 != 0 })), encoding: .isoLatin1) ?? "")
        let mobiPrefix = recordLength >= 24 ? try read(record0 + 16, 8) : Data()
        guard mobiPrefix.starts(with: "MOBI".utf8) else {
            return KindleDetection(variant: .palmDoc, drm: encryption == 0 ? .none : .mobipocket,
                                   isReadable: encryption == 0, unsupportedReason: encryption == 0 ? nil : "PalmDOC 文件已被加密保护",
                                   title: pdbName, author: "", compression: compression, encoding: "Windows-1252",
                                   recordCount: count, firstImageRecord: -1, coverRecordIndex: -1, kf8BoundaryRecord: -1)
        }
        let mobiLength = Int(uint32(mobiPrefix, 4))
        guard (16...65536).contains(mobiLength), UInt64(mobiLength) <= recordLength - 16 else {
            throw InvalidFormat(reason: "MOBI 头部长度异常")
        }
        let mobi = try read(record0 + 16, mobiLength)
        // Header integers follow Java's Int32 semantics, including 0xffffffff sentinels.
        func field(_ offset: Int, fallback: Int = 0) -> Int {
            offset <= mobi.count - 4 ? Int(Int32(bitPattern: uint32(mobi, offset))) : fallback
        }
        let mobiType = field(8), encodingCode = field(12, fallback: 1252), version = field(20, fallback: 4)
        let fullNameOffset = field(68, fallback: -1), fullNameLength = field(72)
        let firstImage = field(92, fallback: -1)
        let drmOffset = field(152, fallback: -1), drmCount = field(156, fallback: -1), drmSize = field(160)
        let drm: KindleDRM = encryption == 1 ? .mobipocket :
            (encryption != 0 || (drmOffset >= 0 && drmCount > 0 && drmSize > 0) ? .amazon : .none)
        var title = pdbName
        if fullNameOffset > 0, (1...65536).contains(fullNameLength) {
            // A name never borrows bytes from a following text/image record.
            for base: UInt64 in [0, 16] {
                let offset = base + UInt64(fullNameOffset)
                if offset <= recordLength, UInt64(fullNameLength) <= recordLength - offset {
                    let bytes = try read(record0 + offset, fullNameLength)
                    let parsed = SearchRules.trim(encodingCode == 65001 ? String(decoding: bytes, as: UTF8.self) :
                        (String(data: bytes, encoding: .isoLatin1) ?? ""))
                    if !parsed.isEmpty { title = parsed }
                }
                if !title.isEmpty && !title.utf16.elementsEqual(pdbName.utf16) { break }
            }
        }
        var author = "", coverOffset = -1, boundary = -1
        let exthOffset = record0 + 16 + UInt64(mobiLength)
        // Like Java, unflagged EXTH is accepted and a missing/incomplete EXTH header is ignored.
        if recordEnd - exthOffset >= 12 {
            let exth = try read(exthOffset, 12)
            if exth.starts(with: "EXTH".utf8) {
                let length = Int(Int32(bitPattern: uint32(exth, 4))), entries = Int(Int32(bitPattern: uint32(exth, 8)))
                guard length >= 12, UInt64(length) <= recordEnd - exthOffset else {
                    throw InvalidFormat(reason: "电子书元数据越界")
                }
                let end = exthOffset + UInt64(length)
                var cursor = exthOffset + 12, index = 0
                while index < entries && end - cursor >= 8 {
                    let entry = try read(cursor, 8)
                    let type = uint32(entry, 0), size = UInt64(uint32(entry, 4))
                    guard (8...65536).contains(size), size <= end - cursor else { break }
                    if size > 8 && (type == 100 || type == 121 || type == 201) {
                        let payload = try read(cursor + 8, Int(size - 8))
                        if type == 100 { author = SearchRules.trim(String(decoding: payload, as: UTF8.self)) }
                        else if payload.count >= 4 {
                            let value = Int(Int32(bitPattern: uint32(payload, 0)))
                            if type == 121 { boundary = value } else { coverOffset = value }
                        }
                    }
                    cursor += size
                    index += 1
                }
            }
        }
        let variant: KindleVariant = boundary > 0 && boundary < count ? .combo : (version >= 8 || mobiType == 248 ? .kf8 : .mobi7)
        var cover = -1
        if firstImage > 0 && coverOffset >= 0 {
            let (candidate, overflow) = firstImage.addingReportingOverflow(coverOffset)
            if !overflow && (0..<count).contains(candidate) { cover = candidate }
        }
        let reason: String? = drm != .none ? "该电子书受 DRM 密码保护，暂无法直接阅读" :
            (variant == .kf8 ? "暂不支持 KF8/AZW3 正文重建，请先在本地转换为 EPUB" : nil)
        try Task.checkCancellation()
        return KindleDetection(variant: variant, drm: drm, isReadable: reason == nil, unsupportedReason: reason,
                               title: title, author: author, compression: compression,
                               encoding: encodingCode == 65001 ? "UTF-8" : "Windows-1252", recordCount: count,
                               firstImageRecord: firstImage, coverRecordIndex: cover, kf8BoundaryRecord: boundary)
    }
}
