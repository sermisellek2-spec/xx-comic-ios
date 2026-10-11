import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ComicCore

final class CacheMaintenanceTests: XCTestCase {
    func testDiskCleanupRestoresLimitsAndAllowsLaterResponses() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.cbz")
        try Data([3, 4, 5]).write(to: original)
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 8 * 1024 * 1024, diskPath: directory.appendingPathComponent("responses").path)
        let url = URL(string: "https://fixture.invalid/disk-page")!, request = URLRequest(url: URL(string: "https://fixture.invalid/disk-page")!)
        XCTAssertNil(cache.cachedResponse(for: request), "The new cache must start without any responses")
        print("HTTP_CACHE_DIAGNOSTIC stage=fresh memory=\(cache.currentMemoryUsage) disk=\(cache.currentDiskUsage)")
        let response = CachedURLResponse(response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=3600"])!, data: Data(repeating: 7, count: 4096), storagePolicy: .allowed)
        cache.storeCachedResponse(response, for: request)
        XCTAssertNotNil(cache.cachedResponse(for: request))
        print("HTTP_CACHE_DIAGNOSTIC stage=stored memory=\(cache.currentMemoryUsage) disk=\(cache.currentDiskUsage)")
        let remaining = try await HTTPResponseCache(cache: cache).clear()
        print("HTTP_CACHE_DIAGNOSTIC stage=cleared memory=\(remaining.memoryBytes) disk=\(remaining.diskBytes) cached=\(cache.cachedResponse(for: request) != nil)")
        XCTAssertTrue(remaining.isEmpty, "Actual remaining cache: memory=\(remaining.memoryBytes), disk=\(remaining.diskBytes)")
        if !remaining.isEmpty {
            for sample in 1...8 {
                try await Task.sleep(nanoseconds: 500_000_000)
                print("HTTP_CACHE_DIAGNOSTIC stage=settled sample=\(sample) memory=\(cache.currentMemoryUsage) disk=\(cache.currentDiskUsage) cached=\(cache.cachedResponse(for: request) != nil)")
            }
        }
        XCTAssertNil(cache.cachedResponse(for: request))
        XCTAssertEqual(cache.memoryCapacity, 1024 * 1024)
        XCTAssertEqual(cache.diskCapacity, 8 * 1024 * 1024)
        XCTAssertEqual(try Data(contentsOf: original), Data([3, 4, 5]), "Cleanup must leave original files alone")
        cache.storeCachedResponse(response, for: request)
        XCTAssertNotNil(cache.cachedResponse(for: request), "Later browsing can cache responses again")
        print("HTTP_CACHE_DIAGNOSTIC stage=reused memory=\(cache.currentMemoryUsage) disk=\(cache.currentDiskUsage)")
    }

    func testConcurrentCleanupPreservesLimitsForBothCallers() async throws {
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let service = HTTPResponseCache(cache: cache)
        async let first = service.clear()
        async let second = service.clear()
        let (a, b) = try await (first, second)
        XCTAssertTrue(a.isEmpty); XCTAssertTrue(b.isEmpty)
        XCTAssertEqual(cache.memoryCapacity, 1024 * 1024, "Overlapping operations must not restore the temporary zero capacity")
        XCTAssertEqual(cache.diskCapacity, 0)
    }

    func testCancellationAfterCleanupStartsRestoresCapacityAndFinishes() async throws {
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let url = URL(string: "https://fixture.invalid/cancel-after-start")!, request = URLRequest(url: URL(string: "https://fixture.invalid/cancel-after-start")!)
        cache.storeCachedResponse(CachedURLResponse(response: URLResponse(url: url, mimeType: nil, expectedContentLength: 4096, textEncodingName: nil), data: Data(repeating: 1, count: 4096)), for: request)
        let service = HTTPResponseCache(cache: cache), task = Task { try await service.clear() }
        for _ in 0..<40 where cache.memoryCapacity != 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(cache.memoryCapacity, 0, "The operation must actually start before cancellation")
        task.cancel()
        do { _ = try await task.value; XCTFail("The cancelled caller must receive cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(cache.memoryCapacity, 1024 * 1024)
        XCTAssertNil(cache.cachedResponse(for: request))
    }

    func testHTTPResponseCleanupUsesCacheAPIAndReportsRemainingUsage() async throws {
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let url = URL(string: "https://fixture.invalid/page")!
        let request = URLRequest(url: url)
        cache.storeCachedResponse(CachedURLResponse(response: URLResponse(url: url, mimeType: "image/png", expectedContentLength: 4096, textEncodingName: nil), data: Data(repeating: 1, count: 4096)), for: request)
        XCTAssertNotNil(cache.cachedResponse(for: request))
        let service = HTTPResponseCache(cache: cache)
        let before = try await service.usage()
        XCTAssertGreaterThan(before.memoryBytes, 0)
        let after = try await service.clear()
        XCTAssertTrue(after.isEmpty)
        XCTAssertNil(cache.cachedResponse(for: request))
    }

    func testCancelledCleanupDoesNotRemoveCachedResponse() async throws {
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let url = URL(string: "https://fixture.invalid/page")!, request = URLRequest(url: URL(string: "https://fixture.invalid/page")!)
        cache.storeCachedResponse(CachedURLResponse(response: URLResponse(url: url, mimeType: nil, expectedContentLength: 1, textEncodingName: nil), data: Data([1])), for: request)
        let service = HTTPResponseCache(cache: cache)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.clear()
        }
        do { _ = try await task.value; XCTFail("Cancelled cleanup must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNotNil(cache.cachedResponse(for: request))
    }

    func testCleanupRemovesAResponseThatFinishesAfterTheFirstRemoval() async throws {
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let url = URL(string: "https://fixture.invalid/finishing-page")!
        let request = URLRequest(url: url)
        let response = CachedURLResponse(response: URLResponse(url: url, mimeType: "image/png", expectedContentLength: 4096, textEncodingName: nil), data: Data(repeating: 2, count: 4096))
        let writer = Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            cache.storeCachedResponse(response, for: request)
        }
        let remaining = try await HTTPResponseCache(cache: cache).clear()
        try await writer.value
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertNil(cache.cachedResponse(for: request), "A finishing response must not immediately undo cleanup")
    }

    func testDirectorySizeIncludesHiddenFilesAndDoesNotFollowSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try Data(repeating: 1, count: 17).write(to: root.appendingPathComponent(".hidden"))
        try Data(repeating: 1, count: 23).write(to: root.appendingPathComponent("image.png"))
        try Data(repeating: 1, count: 1000).write(to: outside.appendingPathComponent("original.cbz"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("external"), withDestinationURL: outside)
        XCTAssertEqual(try StorageCalculator.directorySize(at: root), 40)
        XCTAssertEqual(try StorageCalculator.directorySize(at: root.appendingPathComponent("external")), 0)
        XCTAssertEqual(try Data(contentsOf: outside.appendingPathComponent("original.cbz")).count, 1000)
    }

    func testCancelledSizeCalculationFailsInsteadOfReportingEmpty() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try StorageCalculator.directorySize(at: FileManager.default.temporaryDirectory)
        }
        do { _ = try await task.value; XCTFail("Cancelled measurement must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testMissingDirectoryHasNoBytes() throws {
        XCTAssertEqual(try StorageCalculator.directorySize(at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), 0)
    }
}
