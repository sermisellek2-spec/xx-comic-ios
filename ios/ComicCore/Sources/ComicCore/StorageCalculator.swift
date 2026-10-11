import Foundation

public enum StorageCalculator {
    /// Synchronous I/O: call from a worker, never from the UI actor.
    public static func directorySize(at url: URL) throws -> Int64 {
        try Task.checkCancellation()
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return 0 }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        let root = try url.resourceValues(forKeys: keys)
        guard root.isSymbolicLink != true else { return 0 }
        guard root.isDirectory == true else { return Int64(root.fileSize ?? 0) }
        var enumerationError: Error?
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in enumerationError = error; return false }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isDirectory == false { total += Int64(values.fileSize ?? 0) }
        }
        if let enumerationError { throw enumerationError }
        try Task.checkCancellation()
        return total
    }

    public static func usableSpace() -> Int64 {
        #if canImport(Darwin)
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        #endif
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSize = attrs[.systemFreeSize] as? NSNumber {
            return freeSize.int64Value
        }
        return 0
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024.0 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.1f GB", gb)
    }
}
