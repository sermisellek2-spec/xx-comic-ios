import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Atomic file write, move-replace, and copy helpers shared by persistent rule/failover stores.
public enum AtomicFileOps {
    /// Writes `data` to a same-directory temporary file, flushes/fsyncs it, and atomically replaces `targetURL`.
    public static func writeAtomically(_ data: Data, to targetURL: URL) throws {
        let parentURL = targetURL.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentURL.path) {
            try fm.createDirectory(at: parentURL, withIntermediateDirectories: true, attributes: nil)
        }

        let tempName = ".\(targetURL.lastPathComponent).\(UUID().uuidString).tmp"
        let tempURL = parentURL.appendingPathComponent(tempName, isDirectory: false)
        var tempRemoved = false
        defer {
            if !tempRemoved && fm.fileExists(atPath: tempURL.path) {
                try? fm.removeItem(at: tempURL)
            }
        }

        try writeAndSync(data, to: tempURL)
        try moveReplace(from: tempURL, to: targetURL)
        tempRemoved = true
    }

    /// Atomically replaces `targetURL` with `sourceURL` where supported, falling back cleanly across filesystems.
    public static func moveReplace(from sourceURL: URL, to targetURL: URL) throws {
        let fm = FileManager.default
        if sourceURL.isFileURL && targetURL.isFileURL {
            #if canImport(Darwin)
            if Darwin.rename(sourceURL.path, targetURL.path) == 0 {
                return
            }
            #elseif canImport(Glibc)
            if Glibc.rename(sourceURL.path, targetURL.path) == 0 {
                return
            }
            #endif
        }

        #if !os(Linux)
        if fm.fileExists(atPath: targetURL.path) {
            _ = try fm.replaceItemAt(targetURL, withItemAt: sourceURL)
            return
        }
        #endif

        if fm.fileExists(atPath: targetURL.path) {
            try copyFile(from: sourceURL, to: targetURL)
            try fm.removeItem(at: sourceURL)
            return
        }
        try fm.moveItem(at: sourceURL, to: targetURL)
    }

    /// Copies `sourceURL` to `targetURL`, flushing and syncing the destination file descriptor.
    public static func copyFile(from sourceURL: URL, to targetURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        try writeAndSync(data, to: targetURL)
    }

    private static func writeAndSync(_ data: Data, to fileURL: URL) throws {
        let fm = FileManager.default
        if !fm.createFile(atPath: fileURL.path, contents: nil, attributes: nil) {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        do {
            try handle.write(contentsOf: data)
            #if canImport(Darwin)
            _ = Darwin.fsync(handle.fileDescriptor)
            #elseif canImport(Glibc)
            _ = Glibc.fsync(handle.fileDescriptor)
            #else
            try handle.synchronize()
            #endif
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }
}

/// Cross-platform (Darwin + Linux Swift 5.10) helpers to distinguish JSON booleans from numeric `0`/`1`.
public enum JsonValueHelper {
    public static func isJsonBoolean(_ value: Any) -> Bool {
        if let num = value as? NSNumber {
            #if canImport(Darwin)
            return CFGetTypeID(num) == CFBooleanGetTypeID()
            #else
            return type(of: value as AnyObject) === type(of: NSNumber(value: true) as AnyObject)
                || String(describing: type(of: value as AnyObject)).contains("Boolean")
            #endif
        }
        return value is Bool
    }

    public static func strictInt(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull), !isJsonBoolean(value) else { return nil }
        if let i = value as? Int { return i }
        if let num = value as? NSNumber {
            let d = num.doubleValue
            let i = num.intValue
            return Double(i) == d ? i : nil
        }
        return nil
    }
}
