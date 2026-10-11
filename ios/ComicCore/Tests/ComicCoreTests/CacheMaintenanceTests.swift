import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ComicCore

final class CacheMaintenanceTests: XCTestCase {
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
