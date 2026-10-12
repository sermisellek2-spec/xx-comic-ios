import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ComicCore

final class CacheLateRestoreTests: XCTestCase {
    func testCleanupRemovesResponsesInAnInactiveDiskBackingStore() async throws {
        let cache = InactiveBackingCache(memoryCapacity: 1024 * 1024, diskCapacity: 8 * 1024 * 1024, diskPath: nil)
        let requests = storeResponses(in: cache)
        let usage = try await HTTPResponseCache(cache: cache).clear()
        for request in requests { XCTAssertNil(cache.cachedResponse(for: request), "Disabling storage must not hide an uncleared backing store") }
        XCTAssertEqual(cache.memoryCapacity, 1024 * 1024)
        XCTAssertEqual(cache.diskCapacity, 8 * 1024 * 1024)
        XCTAssertEqual(usage.diskBytes, Int64(cache.currentDiskUsage))
    }

    func testCleanupAlsoRemovesAWritePublishedWhenDiskStorageReopens() async throws {
        let cache = InactiveBackingCache(memoryCapacity: 1024 * 1024, diskCapacity: 8 * 1024 * 1024, diskPath: nil)
        let requests = storeResponses(in: cache)
        cache.publishStoredResponsesWhenStorageReopens()
        let usage = try await HTTPResponseCache(cache: cache).clear()
        for request in requests { XCTAssertNil(cache.cachedResponse(for: request), "A pending disk write must not undo cleanup when the original capacity returns") }
        XCTAssertEqual(cache.memoryCapacity, 1024 * 1024)
        XCTAssertEqual(cache.diskCapacity, 8 * 1024 * 1024)
        XCTAssertEqual(usage.diskBytes, Int64(cache.currentDiskUsage))
    }

    private func storeResponses(in cache: URLCache) -> [URLRequest] {
        let requests = (0..<2).map { URLRequest(url: URL(string: "https://fixture.invalid/cache-restore-\($0)")!) }
        for (index, request) in requests.enumerated() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=3600"])!
            cache.storeCachedResponse(CachedURLResponse(response: response, data: Data(repeating: UInt8(index + 1), count: index == 0 ? 2048 : 256 * 1024), storagePolicy: .allowed), for: request)
            XCTAssertNotNil(cache.cachedResponse(for: request))
        }
        return requests
    }
}

/// Simulates the observed inactive-store and late-write boundaries without
/// claiming that Linux uses Apple's native cache implementation.
private final class InactiveBackingCache: URLCache, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [URL: CachedURLResponse] = [:]
    private var deferredResponses: [URL: CachedURLResponse]?

    override var diskCapacity: Int {
        didSet {
            guard oldValue == 0, diskCapacity > 0 else { return }
            lock.lock(); defer { lock.unlock() }
            if let deferredResponses { responses = deferredResponses; self.deferredResponses = nil }
        }
    }
    override var currentMemoryUsage: Int { 0 }
    override var currentDiskUsage: Int {
        guard diskCapacity > 0 else { return 0 }
        lock.lock(); defer { lock.unlock() }
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
        return responses[url]
    }
    override func removeAllCachedResponses() {
        guard diskCapacity > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        responses.removeAll()
    }
    func publishStoredResponsesWhenStorageReopens() {
        lock.lock(); defer { lock.unlock() }
        deferredResponses = responses
    }
}
