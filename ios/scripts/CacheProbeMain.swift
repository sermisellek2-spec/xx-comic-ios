import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offline evidence only. All requests and files are created by this process;
/// the probe never makes a network request or deletes a cache database.
@main
struct CacheProbeMain {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw ProbeError.missingOutputDirectory }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("XXComic-cache-probe-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let original = root.appendingPathComponent("original.cbz"), bytes = Data([3, 4, 5])
        try bytes.write(to: original)
        let requests = (0..<4).map { URLRequest(url: URL(string: "https://cache-probe.invalid/page-\($0)")!) }
        var results: [[String: Any]] = []
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        let legacy = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 8 * 1024 * 1024, diskPath: legacyDirectory.path)
        results += try await measure(cache: legacy, directory: legacyDirectory, name: "diskPath", requests: requests, output: output)
        #if !canImport(FoundationNetworking)
        let modernDirectory = root.appendingPathComponent("directory", isDirectory: true)
        let modern = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 8 * 1024 * 1024, directory: modernDirectory)
        results += try await measure(cache: modern, directory: modernDirectory, name: "directory", requests: requests, output: output)
        #endif
        guard try Data(contentsOf: original) == bytes else { throw ProbeError.originalChanged }
        let report: [String: Any] = [
            "platform": ProcessInfo.processInfo.operatingSystemVersionString,
            "networkRequests": 0,
            "directWritesOrDeletesToCacheDatabaseByProbe": 0,
            "originalPreserved": true,
            "productionClearImplementation": "ComicCore/Sources/ComicCore/HTTPResponseCache.swift",
            "observations": results
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("cache-probe.json"), options: .atomic)
    }

    private static func measure(cache: URLCache, directory: URL, name: String, requests: [URLRequest], output: URL) async throws -> [[String: Any]] {
        var results = [try snapshot(cache: cache, directory: directory, name: name, stage: "fresh", requests: requests, output: output)]
        for (index, request) in requests.enumerated() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=3600", "Content-Type": "application/octet-stream"])!
            cache.storeCachedResponse(CachedURLResponse(response: response, data: Data(repeating: UInt8(index + 1), count: 256 * 1024), storagePolicy: .allowed), for: request)
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        results.append(try snapshot(cache: cache, directory: directory, name: name, stage: "stored", requests: requests, output: output))
        let remaining = try await HTTPResponseCache(cache: cache).clear()
        var cleared = try snapshot(cache: cache, directory: directory, name: name, stage: "cleared", requests: requests, output: output)
        cleared["clearReturnedMemoryBytes"] = remaining.memoryBytes
        cleared["clearReturnedDiskBytes"] = remaining.diskBytes
        cleared["clearReturnedIsEmpty"] = remaining.isEmpty
        results.append(cleared)
        for sample in 1...4 {
            try await Task.sleep(nanoseconds: 500_000_000)
            results.append(try snapshot(cache: cache, directory: directory, name: name, stage: "settled-\(sample)", requests: requests, output: output))
        }
        return results
    }

    private static func snapshot(cache: URLCache, directory: URL, name: String, stage: String, requests: [URLRequest], output: URL) throws -> [String: Any] {
        let responses = requests.compactMap { cache.cachedResponse(for: $0) }
        let destination = output.appendingPathComponent(name + "-" + stage, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let fm = FileManager.default
        var files: [[String: Any]] = []
        if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey], options: []) {
            let prefix = directory.standardizedFileURL.path + "/"
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isRegularFile == true, url.standardizedFileURL.path.hasPrefix(prefix) else { continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(prefix.count))
                var record: [String: Any] = ["file": relative, "bytes": values.fileSize ?? 0]
                let target = destination.appendingPathComponent(relative)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                do { try fm.copyItem(at: url, to: target) }
                catch { record["snapshotCopyFailed"] = true }
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    record["sqliteDatabase"] = try handle.read(upToCount: 16) == Data("SQLite format 3\0".utf8)
                } catch { record["snapshotReadFailed"] = true }
                files.append(record)
            }
        }
        // Read only the copied fixture databases after all sidecars were copied.
        // This is a non-atomic snapshot; query failures stay explicit evidence.
        for index in files.indices where files[index]["sqliteDatabase"] as? Bool == true {
            let target = destination.appendingPathComponent(files[index]["file"] as! String)
            if fm.fileExists(atPath: target.path) {
                files[index]["sqliteReadOnlyCopiedSnapshot"] = sqliteCounts(at: target)
                files[index]["snapshotIsAtomic"] = false
            }
        }
        let observation: [String: Any] = [
            "initializer": name, "stage": stage,
            "memoryBytes": cache.currentMemoryUsage, "diskBytes": cache.currentDiskUsage,
            "memoryCapacity": cache.memoryCapacity, "diskCapacity": cache.diskCapacity,
            "knownResponsesHit": responses.count, "knownResponseBytes": responses.reduce(0) { $0 + $1.data.count },
            "ownedDirectoryExists": fm.fileExists(atPath: directory.path), "files": files.sorted { ($0["file"] as! String) < ($1["file"] as! String) }
        ]
        print("CACHE_DISK_PROBE initializer=\(name) stage=\(stage) memory=\(cache.currentMemoryUsage) disk=\(cache.currentDiskUsage) knownHits=\(responses.count) ownedFiles=\(files.count)")
        return observation
    }

    private static func sqliteCounts(at url: URL) -> [String: Any] {
        let executable = "/usr/bin/sqlite3"
        guard FileManager.default.isExecutableFile(atPath: executable) else { return ["available": false] }
        do {
            let tables = try query(executable: executable, database: url.path, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
            guard tables.status == 0 else { return ["available": true, "tableQueryExitCode": tables.status] }
            let statements = tables.output.split(separator: "\n").map { table -> String in
                let name = String(table), literal = name.replacingOccurrences(of: "'", with: "''"), identifier = name.replacingOccurrences(of: "\"", with: "\"\"")
                return "SELECT '\(literal)', COUNT(*) FROM \"\(identifier)\";"
            }.joined(separator: "\n")
            let counts = try query(executable: executable, database: url.path, sql: statements)
            let pages = try query(executable: executable, database: url.path, sql: "PRAGMA page_count; PRAGMA freelist_count; PRAGMA page_size;")
            return ["available": true, "readOnly": true, "exitCode": counts.status, "tableRowCounts": counts.status == 0 ? counts.output : "query failed", "tableNames": tables.output, "pageCountFreeCountAndSize": pages.status == 0 ? pages.output : "query failed"]
        } catch { return ["available": true, "launchFailed": true] }
    }

    private static func query(executable: String, database: String, sql: String) throws -> (status: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-readonly", "-batch", database, sql]
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private enum ProbeError: Error { case missingOutputDirectory, originalChanged }
}
