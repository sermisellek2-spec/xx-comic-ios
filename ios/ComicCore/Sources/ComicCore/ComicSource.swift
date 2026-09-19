import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ComicSource: Sendable {
    var id: String { get }
    var name: String { get }
    var referer: String { get }

    func latest(page: Int) async throws -> [ComicSummary]
    func search(keyword: String, page: Int) async throws -> [ComicSummary]
    func detail(comicId: String) async throws -> ComicDetail
    func chapters(comicId: String) async throws -> [Chapter]
    func chapter(url: String) async throws -> ChapterPage
    func filterGroups() async throws -> [SourceFilterGroup]
    func category(filters: [String: String], page: Int) async throws -> [ComicSummary]
}

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

public enum HTTPTransportError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidStatusCode(Int)
}

public struct URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let box = URLSessionTaskBox()
        let (data, response): (Data, URLResponse) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error { return continuation.resume(throwing: error) }
                    guard let data, let response else { return continuation.resume(throwing: HTTPTransportError.invalidResponse) }
                    continuation.resume(returning: (data, response))
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
        guard let response = response as? HTTPURLResponse else { throw HTTPTransportError.invalidResponse }
        return HTTPResponse(data: data, statusCode: response.statusCode)
    }
}

private final class URLSessionTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?

    func set(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        task?.cancel()
        lock.unlock()
    }
}
