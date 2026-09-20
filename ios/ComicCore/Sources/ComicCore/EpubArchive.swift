import Foundation
import CoreFoundation
import ZIPFoundation

/// Read-only, on-demand access. The budget counts full output, including discarded prefixes
/// and repeated reads; opening an EPUB never expands the entire archive.
final class EpubArchive {
    private let url: URL
    private let archive: Archive
    private var entries: [String: (Entry, ZIPDirectory.Record)] = [:]
    private var bytesRead: UInt64 = 0
    private let maximumReadBytes: UInt64 = 256 * 1024 * 1024

    init(url: URL) throws {
        self.url = url
        do {
            try Task.checkCancellation()
            let directory = try ZIPDirectory(url: url)
            archive = try Archive(url: url, accessMode: .read)
            var all: [Entry] = []
            for entry in archive {
                try Task.checkCancellation()
                guard all.count < directory.records.count else { throw EpubError.invalid("ZIP 条目数量不一致") }
                all.append(entry)
            }
            guard all.count == directory.records.count else { throw EpubError.invalid("ZIP 中央目录损坏") }
            let utf8 = all.map { $0.path(using: .utf8) }
            let fallback = utf8.contains("")
            let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            var seen = Set<String>()
            for (index, entry) in all.enumerated() {
                try Task.checkCancellation()
                let record = directory.records[index]
                let name = fallback && !record.utf8 ? entry.path(using: gb18030) : utf8[index]
                guard entry.type != .symlink, entry.uncompressedSize == record.size,
                      entry.compressedSize == record.compressedSize, entry.checksum == record.checksum else {
                    throw EpubError.invalid("ZIP 符号链接或条目信息非法")
                }
                let path = try Self.normalized(name)
                guard seen.insert(path).inserted else { throw EpubError.invalid("ZIP 包含重复规范路径：\(path)") }
                if entry.type != .directory { entries[path] = (entry, record) }
            }
        } catch { throw Self.wrapped(error) }
    }

    func contains(_ path: String) -> Bool { entries[path] != nil }

    func read(_ path: String, maximumBytes: Int = 8 * 1024 * 1024, prefixOnly: Bool = false) throws -> Data {
        do {
            try Task.checkCancellation()
            guard let (entry, record) = entries[path] else { throw EpubError.invalid("缺少资源：\(path)") }
            guard maximumBytes >= 0 else { throw EpubError.limitExceeded("读取大小非法") }
            if !prefixOnly && entry.uncompressedSize > UInt64(maximumBytes) { throw EpubError.limitExceeded("单次 XML 读取超过 8 MiB：\(path)") }
            guard entry.uncompressedSize <= maximumReadBytes - bytesRead else { throw EpubError.limitExceeded("累计解析读取超过 256 MiB") }
            var output = Data(), actual: UInt64 = 0
            let consume: (Data) throws -> Void = { data in
                try Task.checkCancellation()
                let count = UInt64(data.count)
                guard count <= entry.uncompressedSize - actual else { throw EpubError.invalid("ZIP 解压大小不符：\(path)") }
                guard count <= self.maximumReadBytes - self.bytesRead else { throw EpubError.limitExceeded("累计解析读取超过 256 MiB") }
                actual += count
                self.bytesRead += count
                output.append(data.prefix(max(0, maximumBytes - output.count)))
            }
            let crc = try entry.isCompressed
                ? ZIPDeflate.extract(url: url, offset: record.dataOffset, compressedSize: record.compressedSize, consumer: consume)
                : archive.extract(entry, bufferSize: 256 * 1024, skipCRC32: false, consumer: consume)
            try Task.checkCancellation()
            guard actual == entry.uncompressedSize, crc == entry.checksum else { throw EpubError.invalid("ZIP CRC 或解压大小校验失败：\(path)") }
            return output
        } catch { throw Self.wrapped(error) }
    }

    static func resolve(_ raw: String, relativeTo path: String = "") throws -> String {
        let value = SearchRules.trim(raw).replacingOccurrences(of: "+", with: " ")
        guard let decoded = value.removingPercentEncoding else { throw EpubError.invalid("资源路径 URL 编码非法：\(raw)") }
        let stripped = String(decoded.prefix { $0 != "#" }).replacingOccurrences(of: "\\", with: "/")
        guard !stripped.hasPrefix("/"), !stripped.contains("\0"), !(stripped.split(separator: "/").first?.contains(":") ?? false) else {
            throw EpubError.invalid("资源路径非法越界：\(raw)")
        }
        let base = path.lastIndex(of: "/").map { String(path[...$0]) } ?? ""
        return try normalized(base + stripped)
    }

    private static func normalized(_ value: String) throws -> String {
        let path = value.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"),
              !(path.split(separator: "/").first?.contains(":") ?? false) else {
            throw EpubError.invalid("ZIP 路径非法越界：\(value)")
        }
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard !parts.isEmpty else { throw EpubError.invalid("ZIP 路径非法越界：\(value)") }
                parts.removeLast()
            } else { parts.append(part) }
        }
        guard !parts.isEmpty else { throw EpubError.invalid("ZIP 路径为空：\(value)") }
        return parts.joined(separator: "/")
    }

    private static func wrapped(_ error: Error) -> Error {
        if error is CancellationError || error is EpubError { return error }
        if case LocalLibraryError.archiveTooLarge = error { return EpubError.limitExceeded("ZIP 条目数量或大小超限") }
        return EpubError.invalid("ZIP 读取或校验失败：\(error.localizedDescription)")
    }
}
