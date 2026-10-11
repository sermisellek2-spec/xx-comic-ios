import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponseCacheUsage: Equatable, Sendable {
    public let memoryBytes: Int64
    public let diskBytes: Int64
    public var totalBytes: Int64 { memoryBytes + diskBytes }
    public var isEmpty: Bool { totalBytes == 0 }
}

/// URLCache owns its files. Never delete the application's entire Caches directory:
/// it can contain other stores, in-flight downloads, or files not owned by this service.
public actor HTTPResponseCache {
    private let cache: URLCache

    public init(cache: URLCache = .shared) { self.cache = cache }

    public func usage() throws -> HTTPResponseCacheUsage {
        try Task.checkCancellation()
        return HTTPResponseCacheUsage(memoryBytes: Int64(cache.currentMemoryUsage), diskBytes: Int64(cache.currentDiskUsage))
    }

    public func clear() async throws -> HTTPResponseCacheUsage {
        try Task.checkCancellation()
        cache.removeAllCachedResponses()
        // A response that was already finishing can repopulate URLCache after
        // removeAllCachedResponses. Require a short quiet period, removing late
        // entries while framework accounting settles. The entire wait is bounded.
        var emptySamples = 0
        for _ in 0..<40 {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000)
            if cache.currentMemoryUsage == 0, cache.currentDiskUsage == 0 {
                emptySamples += 1
                if emptySamples == 8 { break }
            } else {
                emptySamples = 0
                cache.removeAllCachedResponses()
            }
        }
        // Report remaining usage instead of claiming success if the framework retained data.
        return HTTPResponseCacheUsage(memoryBytes: Int64(cache.currentMemoryUsage), diskBytes: Int64(cache.currentDiskUsage))
    }
}
