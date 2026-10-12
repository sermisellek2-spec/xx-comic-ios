import Foundation
import XCTest
import ComicCore

final class CacheMaintenanceNativeTests: XCTestCase {
    func testOwnedNativeCacheRemovesSmallAndLargeResponsesAndPreservesOriginal() async throws {
        for initializer in ["diskPath", "directory"] {
            // diskPath is a subdirectory name in iOS, not an absolute path.
            let parent = initializer == "diskPath"
                ? try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
                : FileManager.default.temporaryDirectory
            let root = parent.appendingPathComponent("native-response-cache-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let original = root.appendingPathComponent("original.cbz")
            try Data([3, 4, 5]).write(to: original)
            let directory = root.appendingPathComponent("responses", isDirectory: true)
            let cache = makeCache(initializer: initializer, directory: directory)
            let requests = (0..<4).map { URLRequest(url: URL(string: "https://fixture.invalid/native-cache-\($0)")!) }
            record(cache: cache, initializer: initializer, stage: "fresh", requests: requests, directory: directory)
            XCTAssertTrue(requests.allSatisfy { cache.cachedResponse(for: $0) == nil })
            for (index, request) in requests.enumerated() {
                let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=3600"]))
                let size = index < 2 ? 2048 : 256 * 1024
                cache.storeCachedResponse(CachedURLResponse(response: response, data: Data(repeating: UInt8(index + 1), count: size), storagePolicy: .allowed), for: request)
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            XCTAssertEqual(requests.compactMap { cache.cachedResponse(for: $0) }.count, 4)
            record(cache: cache, initializer: initializer, stage: "stored", requests: requests, directory: directory)
            let remaining = try await HTTPResponseCache(cache: cache).clear()
            XCTAssertEqual(remaining.memoryBytes, Int64(cache.currentMemoryUsage), "Usage must retain the framework's actual byte accounting")
            XCTAssertEqual(remaining.diskBytes, Int64(cache.currentDiskUsage), "Index bytes cannot be hidden or subtracted")
            // Probe lookups can reopen the framework's disk index. Compare the
            // returned snapshot before performing those additional operations.
            record(cache: cache, initializer: initializer, stage: "cleared", requests: requests, directory: directory)
            XCTAssertEqual(cache.memoryCapacity, 1024 * 1024)
            XCTAssertEqual(cache.diskCapacity, 8 * 1024 * 1024)
            for request in requests { XCTAssertNil(cache.cachedResponse(for: request), initializer) }
            let reopened = makeCache(initializer: initializer, directory: directory)
            for request in requests { XCTAssertNil(reopened.cachedResponse(for: request), initializer + " reopened") }
            record(cache: reopened, initializer: initializer, stage: "reopened", requests: requests, directory: directory)
            XCTAssertEqual(try Data(contentsOf: original), Data([3, 4, 5]))
        }
    }

    private func makeCache(initializer: String, directory: URL) -> URLCache {
        if initializer == "directory" {
            return URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 8 * 1024 * 1024, directory: directory)
        }
        let relativePath = directory.deletingLastPathComponent().lastPathComponent + "/" + directory.lastPathComponent
        return URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 8 * 1024 * 1024, diskPath: relativePath)
    }

    private func record(cache: URLCache, initializer: String, stage: String, requests: [URLRequest], directory: URL) {
        let responses = requests.compactMap { cache.cachedResponse(for: $0) }
        var files: [[String: Any]] = []
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) {
            let prefix = directory.standardizedFileURL.path + "/"
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isRegularFile == true, url.standardizedFileURL.path.hasPrefix(prefix) else { continue }
                files.append(["file": String(url.standardizedFileURL.path.dropFirst(prefix.count)), "bytes": values.fileSize ?? 0])
            }
        }
        let observation: [String: Any] = [
            "initializer": initializer, "stage": stage, "memoryBytes": cache.currentMemoryUsage,
            "diskBytes": cache.currentDiskUsage, "memoryCapacity": cache.memoryCapacity, "diskCapacity": cache.diskCapacity,
            "knownResponsesHit": responses.count, "knownResponseBytes": responses.reduce(0) { $0 + $1.data.count },
            "files": files, "networkRequests": 0, "directCacheDatabaseWritesOrDeletesDuringObservation": 0
        ]
        if let data = try? JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
            print("CACHE_NATIVE_PROBE " + text)
        }
    }
}
