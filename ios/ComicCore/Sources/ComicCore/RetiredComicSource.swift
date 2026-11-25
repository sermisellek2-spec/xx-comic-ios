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
    public static let builtinRetiredSources: [String: String] = [
        // Historical retired sources (7)
        "baozimh": "包子漫画",
        "mhua5": "漫画屋",
        "duya": "毒牙漫画",
        "xcomic": "XCOMIC",
        "mh250": "250漫画",
        "xiuxiu": "羞羞漫画",
        "aimi": "艾米漫画",
        // Current batch retired sources (9)
        "comic51": "51漫画",
        "favcomic": "喜漫漫画",
        "waiwai": "歪歪漫画",
        "hiperdex": "HiperDEX",
        "momic": "MOMIC",
        "jcomic": "JComic",
        "fuman": "腐漫",
        "pipigou_bika": "哔咔庇护所",
        "cl1024_pic": "1024图区"
    ]

    public static func isBuiltinRetired(_ sourceId: String?) -> Bool {
        guard let sourceId, !sourceId.isEmpty else { return false }
        return builtinRetiredSources[sourceId] != nil
    }

    public static func builtinRetiredName(for sourceId: String?) -> String? {
        guard let sourceId, !sourceId.isEmpty else { return nil }
        return builtinRetiredSources[sourceId]
    }

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
