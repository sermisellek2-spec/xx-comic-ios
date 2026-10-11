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
        // Give framework disk accounting a bounded opportunity to settle without
        // blocking the UI. Remaining bytes still produce an honest retry result.
        for _ in 0..<40 {
            try Task.checkCancellation()
            if cache.currentMemoryUsage == 0, cache.currentDiskUsage == 0 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        // Report remaining usage instead of claiming success if the framework retained data.
        return HTTPResponseCacheUsage(memoryBytes: Int64(cache.currentMemoryUsage), diskBytes: Int64(cache.currentDiskUsage))
    }
}
