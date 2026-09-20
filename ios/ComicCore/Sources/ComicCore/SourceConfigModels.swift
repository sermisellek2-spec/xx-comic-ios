import Foundation

public struct SourceConfigItem: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let domain: String
    public let baseUrl: String
    public let referer: String
    public let latestPath: String
    public let searchPath: String
    public let categoryPath: String
    public let detailPath: String
    public let enabled: Bool
    public let routes: [String: String]?
    public let filters: [String: String]?

    public init(id: String,
                name: String,
                domain: String = "",
                baseUrl: String = "",
                referer: String = "",
                latestPath: String = "",
                searchPath: String = "",
                categoryPath: String = "",
                detailPath: String = "",
                enabled: Bool = true,
                routes: [String: String]? = nil,
                filters: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.domain = domain
        self.baseUrl = baseUrl
        self.referer = referer
        self.latestPath = latestPath
        self.searchPath = searchPath
        self.categoryPath = categoryPath
        self.detailPath = detailPath
        self.enabled = enabled
        self.routes = routes
        self.filters = filters
    }
}

public struct SourceExportPackage: Codable, Equatable, Sendable {
    public let schema: String
    public let version: Int
    public let exportedAt: Int64
    public let sourceOrder: [String]
    public let sources: [SourceConfigItem]
    public let custom: [SourceConfigItem]

    public init(schema: String = "xx-comic.sources",
                version: Int = 2,
                exportedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                sourceOrder: [String],
                sources: [SourceConfigItem],
                custom: [SourceConfigItem] = []) {
        self.schema = schema
        self.version = version
        self.exportedAt = exportedAt
        self.sourceOrder = sourceOrder
        self.sources = sources
        self.custom = custom
    }
}

public enum SourceConfigError: LocalizedError, Equatable {
    case invalidSchema
    case invalidJSON
    case emptyPackage

    public var errorDescription: String? {
        switch self {
        case .invalidSchema:
            return "不是 XX Comic 站源配置"
        case .invalidJSON:
            return "无效的 JSON 格式"
        case .emptyPackage:
            return "站源配置文件为空"
        }
    }
}

public struct SourceImportResult: Equatable, Sendable {
    public let totalSources: Int
    public let enabledCount: Int
    public let disabledCount: Int
    public let orderUpdated: Bool

    public init(totalSources: Int, enabledCount: Int, disabledCount: Int, orderUpdated: Bool) {
        self.totalSources = totalSources
        self.enabledCount = enabledCount
        self.disabledCount = disabledCount
        self.orderUpdated = orderUpdated
    }
}

extension SourceConfigItem {
    public func route(_ key: String) -> String {
        if let v = routes?[key], !v.isEmpty { return v }
        if key == "latest" && !latestPath.isEmpty { return latestPath }
        if key == "search" && !searchPath.isEmpty { return searchPath }
        if key == "category" && !categoryPath.isEmpty { return categoryPath }
        if key == "detail" && !detailPath.isEmpty { return detailPath }
        return ""
    }

    public func filter(_ key: String) -> String {
        filters?[key] ?? ""
    }
}

public enum SourceConfigDefaults {
    public static func baozi(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "baozimh",
            name: "包子漫画",
            domain: "cn.dzmanga.com",
            baseUrl: "https://cn.dzmanga.com",
            referer: "https://cn.dzmanga.com/",
            latestPath: "/list/new{pagePath}",
            searchPath: "/search?q={keyword}",
            categoryPath: "/classify?type={type}&region={region}&state={state}&filter={filter}{pageQuery}",
            detailPath: "/comic/{comicId}",
            enabled: enabled,
            routes: [
                "latest": "/list/new{pagePath}",
                "search": "/search?q={keyword}",
                "category": "/classify?type={type}&region={region}&state={state}&filter={filter}{pageQuery}",
                "categoryApi": "/api/bzmhq/amp_comic_list?type={type}&region={region}&state={state}&filter={filter}&page={page}&limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.dzmanga.com",
                "detail": "/comic/{comicId}",
                "chapter": "{chapterUrl}"
            ],
            filters: [
                "region.cn": "cn",
                "region.jp": "jp",
                "region.kr": "kr",
                "region.en": "en",
                "region.all": "all",
                "state.serial": "serial",
                "state.pub": "pub",
                "state.all": "all"
            ]
        )
    }

    public static func mh160(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "mh160",
            name: "漫画160",
            domain: "www.mh160mh.com",
            baseUrl: "https://www.mh160mh.com",
            referer: "https://www.mh160mh.com/",
            latestPath: "/kanmanhua/all/{pagePath}",
            searchPath: "/statics/searchelxt1e1.aspx?key={keyword}{pageQuery}",
            categoryPath: "/kanmanhua/{filterPath}/{pagePath}",
            detailPath: "/kanmanhua/{comicId}/",
            enabled: enabled,
            routes: [
                "latest": "/kanmanhua/all/{pagePath}",
                "search": "/statics/searchelxt1e1.aspx?key={keyword}{pageQuery}",
                "category": "/kanmanhua/{filterPath}/{pagePath}",
                "detail": "/kanmanhua/{comicId}/",
                "chapter": "{chapterUrl}"
            ],
            filters: [:]
        )
    }

    public static func gmh(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "gmh",
            name: "G社漫画",
            domain: "m.g-mh.org",
            baseUrl: "https://m.g-mh.org",
            referer: "https://m.g-mh.org/",
            latestPath: "/manga{pagePath}",
            searchPath: "/s/{keyword}",
            categoryPath: "/manga{genrePath}{pagePath}",
            detailPath: "/manga/{comicId}",
            enabled: enabled,
            routes: [
                "latest": "/manga{pagePath}",
                "search": "/s/{keyword}",
                "category": "/manga{genrePath}{pagePath}",
                "detail": "/manga/{comicId}",
                "chapter": "/manga/{comicId}/{chapterSlug}",
                "mangaApi": "https://v2.apikk.top/api/v2/manga/get?mid={mid}&mode=all",
                "chapterApi": "https://v2.apikk.top/api/v2/chapter/getinfo?m={mid}&c={chapterId}"
            ],
            filters: [
                "genre.kr": "kr",
                "genre.hots": "hots",
                "genre.cn": "cn",
                "genre.jp": "jp",
                "genre.all": ""
            ]
        )
    }

    public static func mh18(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "mh18",
            name: "18漫画",
            domain: "18mh.org",
            baseUrl: "https://18mh.org",
            referer: "https://18mh.org/",
            latestPath: "/manga{pagePath}",
            searchPath: "/s/{keyword}",
            categoryPath: "/manga{genrePath}{pagePath}",
            detailPath: "/manga/{comicId}",
            enabled: enabled,
            routes: [
                "latest": "/manga{pagePath}",
                "search": "/s/{keyword}",
                "category": "/manga{genrePath}{pagePath}",
                "detail": "/manga/{comicId}",
                "chapter": "/manga/{comicId}/{chapterSlug}"
            ],
            filters: [
                "genre.kr": "hanman",
                "genre.hots": "hots",
                "genre.jp": "riman",
                "genre.hanman": "hanman",
                "genre.zhenrenxiezhen": "zhenrenxiezhen",
                "genre.riman": "riman",
                "genre.aixiezhen": "aixiezhen",
                "genre.all": ""
            ]
        )
    }

    public static func mkzhan(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "mkzhan",
            name: "漫客栈",
            domain: "www.mkzhan.com",
            baseUrl: "https://www.mkzhan.com",
            referer: "https://www.mkzhan.com/",
            latestPath: "/category{pageQuery}",
            searchPath: "/search/?keyword={keyword}",
            categoryPath: "/category?{query}",
            detailPath: "/{comicId}/",
            enabled: enabled,
            routes: [
                "latest": "/category{pageQuery}",
                "search": "/search/?keyword={keyword}",
                "category": "/category?{query}",
                "detail": "/{comicId}/",
                "chapter": "/{comicId}/{chapterId}.html",
                "chapterApi": "https://comic.mkzcdn.com/chapter/content/v1/?chapter_id={chapterId}&comic_id={comicId}&quality=1&type=1&format=0&uid=&sign="
            ],
            filters: [
                "filter.serial": "finish=1",
                "filter.pub": "finish=2",
                "filter.free": "is_free=1",
                "filter.fee": "is_fee=1",
                "filter.vip": "is_vip=1",
                "filter.all": ""
            ]
        )
    }

    public static func manwa(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "manwa",
            name: "漫蛙",
            domain: "manwace.cc",
            baseUrl: "https://manwace.cc",
            referer: "https://manwace.cc/",
            latestPath: "",
            searchPath: "/api/search?type=mh&page={page}&pageSize=20&keyword={keyword}",
            categoryPath: "/api/cate",
            detailPath: "/comic/{comicId}",
            enabled: enabled,
            routes: [
                "search": "/api/search?type=mh&page={page}&pageSize=20&keyword={keyword}",
                "category": "/api/cate",
                "detail": "/comic/{comicId}",
                "chapters": "/api/comic/{comicId}/chapters",
                "chapterInfo": "/api/comic/chapter/info/{chapterId}",
                "images": "/api/comic/image/{chapterId}?page={page}&page_size=100&image_source={imageSource}",
                "imageSource": "https://tu.mwzu.cc",
                "imageKey": "0B6666A0-BB59-1381-B746-a0E4C9AC"
            ],
            filters: [:]
        )
    }

    public static func defaultConfig(for id: String) -> SourceConfigItem? {
        switch id {
        case "baozimh": return baozi()
        case "mh160": return mh160()
        case "gmh": return gmh()
        case "mh18": return mh18()
        case "mkzhan": return mkzhan()
        case "manwa": return manwa()
        default: return nil
        }
    }
}

