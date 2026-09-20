import Foundation
import CoreFoundation
import ZIPFoundation

/// Archive paths are used only for grouping. All output names are generated inside staging.
struct LocalArchiveIndex {
    let names: [String]
    let groups: [LocalFolderIndex.Group]

    init(archive url: URL, staging: URL, isReadableImage: (URL) throws -> Bool) throws {
        let directory = try ZIPDirectory(url: url)
        let archive = try Archive(url: url, accessMode: .read)
        var entries: [Entry] = []
        for entry in archive {
            try Task.checkCancellation()
            guard entries.count < directory.records.count else { throw LocalLibraryError.invalidArchive }
            entries.append(entry)
        }
        guard entries.count == directory.records.count else { throw LocalLibraryError.invalidArchive }
        let utf8 = entries.map { $0.path(using: .utf8) }
        let fallback = utf8.contains("")
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        var paths: [String?] = [], seen = Set<String>()
        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            let record = directory.records[index]
            let name = fallback && !record.utf8 ? entry.path(using: gb18030) : utf8[index]
            guard !name.isEmpty, !name.contains("\0"), entry.type != .symlink,
                  entry.uncompressedSize == record.size, entry.compressedSize == record.compressedSize,
                  entry.checksum == record.checksum else { throw LocalLibraryError.invalidArchive }
            if entry.type == .directory { paths.append(nil); continue }
            let slashes = name.replacingOccurrences(of: "\\", with: "/")
            let chars = Array(slashes.prefix(2))
            guard !slashes.hasPrefix("/"), !slashes.contains("../"), !slashes.contains("/.."), slashes != "..",
                  !(chars.count == 2 && chars[0].isLetter && chars[1] == ":") else { throw LocalLibraryError.invalidArchive }
            let normalized = slashes.split(separator: "/").filter { $0 != "." }.joined(separator: "/")
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { throw LocalLibraryError.invalidArchive }
            // Android checks metadata against the original decoded name, before slash normalization.
            let lower = name.lowercased()
            let metadata = lower.contains("__macosx/") || [".ds_store", "thumbs.db", ".nomedia", "desktop.ini"].contains(where: lower.hasSuffix)
            let image = [".jpg", ".jpeg", ".png", ".webp", ".gif"].contains(where: lower.hasSuffix)
            paths.append(!metadata && image ? normalized : nil)
        }
        var valid: [(path: String, name: String)] = [], total: UInt64 = 0
        for (index, entry) in entries.enumerated() where entry.type != .directory {
            try Task.checkCancellation()
            let path = paths[index]
            let name = "\(index)." + ((path ?? "").split(separator: ".").last.map(String.init) ?? "").lowercased()
            let target = staging.appendingPathComponent(name)
            var output: FileHandle?
            if path != nil {
                guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw LocalLibraryError.invalidArchive }
                output = try FileHandle(forWritingTo: target)
            }
            defer { try? output?.close() }
            var actual: UInt64 = 0
            let consume: (Data) throws -> Void = { data in
                try Task.checkCancellation()
                let count = UInt64(data.count)
                guard count <= UInt64(LocalLibrary.maximumImageBytes) - actual,
                      count <= UInt64(LocalLibrary.maximumImportBytes) - total else { throw LocalLibraryError.archiveTooLarge }
                guard count <= entry.uncompressedSize - actual else { throw LocalLibraryError.invalidArchive }
                actual += count; total += count
                try output?.write(contentsOf: data)
            }
            let record = directory.records[index]
            let crc = try entry.isCompressed
                ? ZIPDeflate.extract(url: url, offset: record.dataOffset, compressedSize: record.compressedSize, consumer: consume)
                : archive.extract(entry, bufferSize: 256 * 1024, skipCRC32: false, consumer: consume)
            try output?.close(); output = nil
            try Task.checkCancellation()
            guard actual == entry.uncompressedSize, crc == entry.checksum else { throw LocalLibraryError.invalidArchive }
            if let path {
                if try isReadableImage(target) { valid.append((path, name)) }
                else { try FileManager.default.removeItem(at: target) }
            }
        }
        try Task.checkCancellation()
        guard !valid.isEmpty else { throw LocalLibraryError.emptyImport }
        valid.sort { NaturalPathOrder.less($0.path, $1.path) }
        names = valid.map(\.name)
        groups = LocalFolderIndex.groups(for: valid.map(\.path))
    }
}
