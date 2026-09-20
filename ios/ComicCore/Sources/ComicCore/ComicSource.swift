import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ComicSource: Sendable {
    var id: String { get }
    var name: String { get }
    var referer: String { get }
    var supportsSearch: Bool { get }

    func latest(page: Int) async throws -> [ComicSummary]
    func search(keyword: String, page: Int) async throws -> [ComicSummary]
    func detail(comicId: String) async throws -> ComicDetail
    func chapters(comicId: String) async throws -> [Chapter]
    func chapter(url: String) async throws -> ChapterPage
    func filterGroups() async throws -> [SourceFilterGroup]
    func category(filters: [String: String], page: Int) async throws -> [ComicSummary]
}

public extension ComicSource {
    var supportsSearch: Bool { true }
}

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let textEncodingName: String?

    public init(data: Data, statusCode: Int, textEncodingName: String? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.textEncodingName = textEncodingName
    }
}

public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse
}

public extension HTTPTransport {
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
        throw HTTPTransportError.unsupportedMethod
    }
}

public enum HTTPTransportError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidStatusCode(Int)
    case unsupportedMethod
}

public struct URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let timeoutInterval: TimeInterval

    public init(session: URLSession = .shared, timeoutInterval: TimeInterval = 15) {
        self.session = session
        self.timeoutInterval = timeoutInterval
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await send(url, headers: headers, body: nil)
    }

    public func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
        try await send(url, headers: headers, body: body)
    }

    private func send(_ url: URL, headers: [String: String], body: Data?) async throws -> HTTPResponse {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        if let body { request.httpMethod = "POST"; request.httpBody = body }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
#if canImport(FoundationNetworking)
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
#else
        let (data, response) = try await session.data(for: request)
#endif
        guard let response = response as? HTTPURLResponse else { throw HTTPTransportError.invalidResponse }
        return HTTPResponse(data: data, statusCode: response.statusCode, textEncodingName: response.textEncodingName)
    }
}

#if canImport(FoundationNetworking)
private final class URLSessionTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCancelled = false

    func set(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}
#endif
