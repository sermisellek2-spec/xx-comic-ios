import Foundation

public enum RetiredSourceError: LocalizedError, Equatable {
    case unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let name): return "\(name)已下线，旧记录与离线内容已保留，请换源阅读。"
        }
    }
}

public struct RetiredComicSource: ComicSource {
    public let id: String
    public let name: String
    public let referer = ""
    public let supportsSearch = false
    public init(id: String, name: String) { self.id = id; self.name = name }
    public func latest(page: Int) async throws -> [ComicSummary] { throw RetiredSourceError.unavailable(name) }
    public func search(keyword: String, page: Int) async throws -> [ComicSummary] { throw RetiredSourceError.unavailable(name) }
    public func detail(comicId: String) async throws -> ComicDetail { throw RetiredSourceError.unavailable(name) }
    public func chapters(comicId: String) async throws -> [Chapter] { throw RetiredSourceError.unavailable(name) }
    public func chapter(url: String) async throws -> ChapterPage { throw RetiredSourceError.unavailable(name) }
    public func filterGroups() async throws -> [SourceFilterGroup] { throw RetiredSourceError.unavailable(name) }
    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { throw RetiredSourceError.unavailable(name) }
    public func healthCheck() async -> Bool { false }
}
