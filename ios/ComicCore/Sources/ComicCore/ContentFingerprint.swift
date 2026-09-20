import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Hash owned, stable copies before publishing their identity. Metadata checks do not
/// promise detection of hostile replacements that preserve size and timestamps.
public enum ContentFingerprint {
    public static func file(_ url: URL, maximumBytes: Int64 = 20 * 1024 * 1024 * 1024) throws -> String {
        try file(url, maximumBytes: maximumBytes, readChunk: { try $0.read(upToCount: $1) })
    }

    public static func folder(_ root: URL, relativeImagePaths: [String]) throws -> String {
        try Task.checkCancellation()
        guard root.isFileURL, relativeImagePaths.count <= 50_000 else { throw Failure.invalidInput }
        try requireDirectory(root)
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        // Swift String equality folds canonical Unicode equivalents; identity uses raw UTF-8.
        var seen = Set<Data>()
        for path in relativeImagePaths {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.contains("\\"), !path.contains("\0"),
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  seen.insert(Data(path.utf8)).inserted else { throw Failure.invalidInput }
        }
        var totalBytes: Int64 = 0
        return try digest { feed in
            for path in relativeImagePaths.sorted(by: NaturalPathOrder.less) {
                try Task.checkCancellation()
                try requireDirectory(root)
                var url = root
                let parts = path.split(separator: "/")
                for (index, part) in parts.enumerated() {
                    url.appendPathComponent(String(part))
                    if index < parts.count - 1 { try requireDirectory(url) }
                }
                let resolved = url.resolvingSymlinksInPath().standardizedFileURL
                let prefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
                guard resolved.path.hasPrefix(prefix) else { throw Failure.invalidInput }
                let result = try hashFile(url, maximumBytes: min(128 * 1024 * 1024, 20 * 1024 * 1024 * 1024 - totalBytes),
                                          readChunk: { try $0.read(upToCount: $1) })
                totalBytes += result.bytes
                try feed(Data((path + ":" + result.hash + "\n").utf8))
            }
        }
    }

    // Narrow read seam permits deterministic cancellation and real descriptor failures.
    static func file(_ url: URL, maximumBytes: Int64, readChunk: (FileHandle, Int) throws -> Data?) throws -> String {
        try hashFile(url, maximumBytes: maximumBytes, readChunk: readChunk).hash
    }

    private static func hashFile(_ url: URL, maximumBytes: Int64,
                                 readChunk: (FileHandle, Int) throws -> Data?) throws -> (hash: String, bytes: Int64) {
        try Task.checkCancellation()
        guard url.isFileURL, maximumBytes >= 0 else { throw Failure.invalidInput }
        let before = try regularFileAttributes(url)
        guard let initialSize = (before[.size] as? NSNumber)?.int64Value, initialSize >= 0 else { throw Failure.invalidInput }
        guard initialSize <= maximumBytes else { throw Failure.limitExceeded }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes: Int64 = 0
        let hash = try digest { feed in
            while true {
                try Task.checkCancellation()
                let chunk = try readChunk(handle, 256 * 1024) ?? Data()
                try Task.checkCancellation()
                guard Int64(chunk.count) <= maximumBytes - bytes else { throw Failure.limitExceeded }
                if chunk.isEmpty { break }
                bytes += Int64(chunk.count)
                try feed(chunk)
                try Task.checkCancellation()
            }
            let after = try regularFileAttributes(url)
            guard bytes == initialSize, (after[.size] as? NSNumber)?.int64Value == bytes,
                  before[.modificationDate] as? Date == after[.modificationDate] as? Date,
                  before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber,
                  before[.systemNumber] as? NSNumber == after[.systemNumber] as? NSNumber else { throw Failure.changedDuringRead }
        }
        return (hash, bytes)
    }

    private static func regularFileAttributes(_ url: URL) throws -> [FileAttributeKey: Any] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure.invalidInput }
        return attributes
    }

    private static func requireDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw Failure.invalidInput }
    }

    private static func digest(_ produce: (_ feed: (Data) throws -> Void) throws -> Void) throws -> String {
        try Task.checkCancellation()
#if canImport(CryptoKit)
        var sha256 = SHA256()
        try produce { data in
            try Task.checkCancellation()
            sha256.update(data: data)
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
        let result = Data(sha256.finalize())
#elseif os(Linux)
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["dgst", "-sha256", "-binary"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        try process.run()
        try produce { data in
            try Task.checkCancellation()
            try input.fileHandleForWriting.write(contentsOf: data)
            try Task.checkCancellation()
        }
        try input.fileHandleForWriting.close()
        let result = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0, result.count == 32 else { throw Failure.digestFailed }
#else
        throw Failure.digestFailed
#endif
#if canImport(CryptoKit) || os(Linux)
        try Task.checkCancellation()
        return result.map { String(format: "%02x", $0) }.joined()
#endif
    }

    private enum Failure: Error { case invalidInput, limitExceeded, changedDuringRead, digestFailed }
}
