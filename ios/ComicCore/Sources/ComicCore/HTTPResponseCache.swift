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
        // caller cancels. All callers share one operation and one memory reset.
        let usage = try await operation.task.value
        try Task.checkCancellation()
        return usage
    }

    private static func clear(cache: URLCache) async throws -> HTTPResponseCacheUsage {
        let memoryCapacity = cache.memoryCapacity
        // Keep the disk backend and its capacity intact. Repeatedly truncating
        // or reopening it queues more native database work and can race a later
        // lookup. URLCache alone owns eviction and its management files.
        cache.memoryCapacity = 0
        defer { cache.memoryCapacity = memoryCapacity }
        cache.removeAllCachedResponses()
        try await waitForQuietAccounting(cache)
        // Catch responses already finishing when cleanup began, without issuing
        // a database deletion every time a retained index reports nonzero bytes.
        cache.removeAllCachedResponses()
        try await waitForQuietAccounting(cache)
        cache.memoryCapacity = memoryCapacity
        return HTTPResponseCacheUsage(memoryBytes: Int64(cache.currentMemoryUsage), diskBytes: Int64(cache.currentDiskUsage))
    }

    private static func waitForQuietAccounting(_ cache: URLCache) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var previous: HTTPResponseCacheUsage?
        var stable = 0
        repeat {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000)
            let usage = HTTPResponseCacheUsage(memoryBytes: Int64(cache.currentMemoryUsage), diskBytes: Int64(cache.currentDiskUsage))
            stable = usage == previous ? stable + 1 : 0
            if let previous, usage.memoryBytes > previous.memoryBytes || usage.diskBytes > previous.diskBytes {
                cache.removeAllCachedResponses()
                stable = 0
            }
            previous = usage
            if stable >= 8 { return }
        } while ProcessInfo.processInfo.systemUptime < deadline
    }
}
