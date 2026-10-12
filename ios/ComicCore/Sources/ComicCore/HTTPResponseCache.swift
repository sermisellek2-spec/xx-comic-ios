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
    private var cleanup: (id: UUID, task: Task<HTTPResponseCacheUsage, Error>)?

    public init(cache: URLCache = .shared) { self.cache = cache }

    public func usage() throws -> HTTPResponseCacheUsage {
        try Task.checkCancellation()
        return HTTPResponseCacheUsage(memoryBytes: Int64(cache.currentMemoryUsage), diskBytes: Int64(cache.currentDiskUsage))
    }

    public func clear() async throws -> HTTPResponseCacheUsage {
        try Task.checkCancellation()
        let operation: (id: UUID, task: Task<HTTPResponseCacheUsage, Error>)
        if let cleanup {
            operation = cleanup
        } else {
            let cache = cache
            operation = (UUID(), Task.detached(priority: .utility) { try await Self.clear(cache: cache) })
            cleanup = operation
        }
        defer { if cleanup?.id == operation.id { cleanup = nil } }
        // Once mutation begins it finishes, even if a page leaves or a second
        // caller cancels. All callers share one operation and one capacity reset.
        let usage = try await operation.task.value
        try Task.checkCancellation()
        return usage
    }

    private static func clear(cache: URLCache) async throws -> HTTPResponseCacheUsage {
        let memoryCapacity = cache.memoryCapacity, diskCapacity = cache.diskCapacity
        // Clear the active backing store before changing its storage limits.
        // A disabled cache can otherwise hide responses until it is reopened.
        cache.removeAllCachedResponses()
        // URLCache owns truncation. Temporarily disable storage as well as
        // removing responses, then restore the application's original limits.
        // No cache database or unrelated directory is deleted by our code.
        cache.memoryCapacity = 0
        cache.diskCapacity = 0
        var limitsRestored = false
        defer {
            if !limitsRestored { cache.memoryCapacity = memoryCapacity; cache.diskCapacity = diskCapacity }
        }
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
        // Restoring disk storage can allocate index files. Measure afterwards,
        // so the result describes the cache the caller can actually use.
        cache.memoryCapacity = memoryCapacity
        cache.diskCapacity = diskCapacity
        limitsRestored = true
        // Reopening storage can publish an already pending disk write. Remove
        // responses again while the original store is active, then wait for
        // stable real accounting without treating retained index bytes as zero.
        var previousUsage: HTTPResponseCacheUsage?
        var stableSamples = 0
        for _ in 0..<40 {
            cache.removeAllCachedResponses()
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000)
            let usage = HTTPResponseCacheUsage(memoryBytes: Int64(cache.currentMemoryUsage), diskBytes: Int64(cache.currentDiskUsage))
            stableSamples = usage == previousUsage ? stableSamples + 1 : 0
            previousUsage = usage
            if stableSamples == 8 { break }
        }
        // Report remaining usage instead of claiming success if the framework retained data.
        return HTTPResponseCacheUsage(memoryBytes: Int64(cache.currentMemoryUsage), diskBytes: Int64(cache.currentDiskUsage))
    }
}
