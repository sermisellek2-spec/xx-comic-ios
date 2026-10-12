import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ComicCore

final class CacheBackendContinuityTests: XCTestCase {
    func testCleanupRemovesResponsesBeforeALookupReopensTheOriginalBackingStore() async throws {
        let cache = ReopeningBackingCache(memoryCapacity: 1024 * 1024, diskCapacity: 8 * 1024 * 1024, diskPath: nil)
        let requests = (0..<2).map { URLRequest(url: URL(string: "https://fixture.invalid/cache-backend-\($0)")!) }
        for (index, request) in requests.enumerated() {
            let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=3600"]))
            let data = Data(repeating: UInt8(index + 1), count: index == 0 ? 2048 : 256 * 1024)
            cache.storeCachedResponse(CachedURLResponse(response: response, data: data, storagePolicy: .allowed), for: request)
            XCTAssertNotNil(cache.cachedResponse(for: request))
        }
        let remaining = try await HTTPResponseCache(cache: cache).clear()
        for request in requests {
            XCTAssertNil(cache.cachedResponse(for: request), "A lookup must not bring back responses hidden by a storage-limit reset")
        }
        XCTAssertEqual(remaining.diskBytes, Int64(cache.currentDiskUsage))
        XCTAssertEqual(cache.memoryCapacity, 1024 * 1024)
        XCTAssertEqual(cache.diskCapacity, 8 * 1024 * 1024)
    }
}

/// Models an asynchronous removal invalidated by a backing-store reset, followed
/// by lookup reactivation. Native cache tests remain necessary; this model does
/// not claim to implement Apple's private cache internals.
private final class ReopeningBackingCache: URLCache, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [URL: CachedURLResponse] = [:]
    private var originalStoreIsActive = true
    private var removalIsPending = false

    override var diskCapacity: Int {
        didSet {
            guard oldValue > 0, diskCapacity == 0 else { return }
            lock.lock(); defer { lock.unlock() }
            originalStoreIsActive = false
            removalIsPending = false
        }
    }
    override var currentMemoryUsage: Int { 0 }
    override var currentDiskUsage: Int {
        lock.lock(); defer { lock.unlock() }
        guard originalStoreIsActive else { return 0 }
        if removalIsPending { responses.removeAll(); removalIsPending = false }
        return responses.values.reduce(0) { $0 + $1.data.count }
    }
    override func storeCachedResponse(_ cachedResponse: CachedURLResponse, for request: URLRequest) {
        guard let url = request.url else { return }
        lock.lock(); defer { lock.unlock() }
        responses[url] = cachedResponse
    }
    override func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        guard diskCapacity > 0, let url = request.url else { return nil }
        lock.lock(); defer { lock.unlock() }
        originalStoreIsActive = true
        return responses[url]
    }
    override func removeAllCachedResponses() {
        lock.lock(); defer { lock.unlock() }
        if originalStoreIsActive { removalIsPending = true }
    }
}
