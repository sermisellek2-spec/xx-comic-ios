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

    public func withEnabled(_ value: Bool) -> SourceConfigItem {
        SourceConfigItem(
            id: id,
            name: name,
            domain: domain,
            baseUrl: baseUrl,
            referer: referer,
            latestPath: latestPath,
            searchPath: searchPath,
            categoryPath: categoryPath,
            detailPath: detailPath,
            enabled: value,
            routes: routes,
            filters: filters
        )
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

    public static func manhuazhan(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "manhuazhan",
            name: "漫画栈",
            domain: "www.60ti.com",
            baseUrl: "https://www.60ti.com",
            referer: "https://www.60ti.com/",
            latestPath: "/category{pagePath}",
            searchPath: "/search?key={keyword}",
            categoryPath: "/category{pagePath}",
            detailPath: "/comic_{comicId}.html",
            enabled: enabled,
            routes: [
                "latest": "/category{pagePath}",
                "search": "/search?key={keyword}",
                "categoryIndex": "/category/",
                "category": "/category{pagePath}",
                "detail": "/comic_{comicId}.html",
                "chapter": "{chapterUrl}"
            ],
            filters: [:]
        )
    }

    public static func bbyin(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "bbyin",
            name: "比卡漫画",
            domain: "bbyin.com",
            baseUrl: "https://bbyin.com",
            referer: "https://bbyin.com/",
            latestPath: "/category{pagePath}",
            searchPath: "/search?key={keyword}",
            categoryPath: "/category{pagePath}",
            detailPath: "/comic_{comicId}.html",
            enabled: enabled,
            routes: [
                "latest": "/category{pagePath}",
                "search": "/search?key={keyword}",
                "categoryIndex": "/category/",
                "category": "/category{pagePath}",
                "detail": "/comic_{comicId}.html",
                "chapter": "{chapterUrl}"
            ],
            filters: [:]
        )
    }

    public static func antbyw(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "antbyw",
            name: "tapmanga搬运",
            domain: "www.antbyw.com",
            baseUrl: "https://www.antbyw.com",
            referer: "https://www.antbyw.com/",
            latestPath: "/plugin.php?id=jameson_manhua&c=index&a=ku",
            searchPath: "/plugin.php?id=jameson_manhua&a=search&c=index&keyword={keyword}",
            categoryPath: "/plugin.php?id=jameson_manhua&c=index&a=ku",
            detailPath: "/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid={comicId}",
            enabled: enabled,
            routes: [
                "latest": "/plugin.php?id=jameson_manhua&c=index&a=ku",
                "search": "/plugin.php?id=jameson_manhua&a=search&c=index&keyword={keyword}",
                "categoryIndex": "/plugin.php?id=jameson_manhua&a=ku",
                "category": "/plugin.php?id=jameson_manhua&c=index&a=ku",
                "detail": "/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid={comicId}",
                "chapter": "{chapterUrl}"
            ],
            filters: [:]
        )
    }

    public static func cuimh(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "cuimh",
            name: "催漫画",
            domain: "www.cuimh.com",
            baseUrl: "https://www.cuimh.com",
            referer: "https://www.cuimh.com/",
            latestPath: "/category{pagePath}",
            searchPath: "",
            categoryPath: "/category{filterPath}{pagePath}",
            detailPath: "/{comicId}",
            enabled: enabled,
            routes: [
                "latest": "/category{pagePath}",
                "search": "",
                "category": "/category{filterPath}{pagePath}",
                "detail": "/{comicId}",
                "chapter": "{chapterUrl}"
            ],
            filters: [:]
        )
    }

    public static func copy4000(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "copy4000",
            name: "拷贝漫画",
            domain: "www.copy4000.com",
            baseUrl: "https://www.copy4000.com",
            referer: "https://www.copy4000.com/",
            latestPath: "",
            searchPath: "/api/kb/web/searchci/comics?offset={offset}&platform=2&limit={limit}&q={keyword}&q_type=",
            categoryPath: "/comics?limit={limit}&offset={offset}&ordering={ordering}{filters}",
            detailPath: "/comic/{comicId}",
            enabled: enabled,
            routes: [
                "apiBaseUrl": "https://api.manga2026.xyz",
                "apiFallbackUrls": "https://mapi.elfgjfghkk.club,https://mapi.fgjfghkkcenter.club",
                "apiDetail": "/api/v3/comic2/{comicId}?platform=3",
                "apiChapters": "/api/v3/comic/{comicId}/group/{group}/chapters?limit=100&offset={offset}",
                "apiChapter": "/api/v3/comic/{comicId}/chapter/{chapterId}?platform=3",
                "search": "/api/kb/web/searchci/comics?offset={offset}&platform=2&limit={limit}&q={keyword}&q_type=",
                "categoryIndex": "/filter",
                "category": "/comics?limit={limit}&offset={offset}&ordering={ordering}{filters}",
                "detail": "/comic/{comicId}",
                "chapters": "/comicdetail/{comicId}/chapters",
                "chapter": "{chapterUrl}"
            ],
            filters: [:]
        )
    }

    public static func jmcomic(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "jmcomic",
            name: "禁漫天堂",
            domain: "18comic.vip",
            baseUrl: "https://18comic.vip",
            referer: "https://18comic.vip/",
            latestPath: "/albums?o=mr",
            searchPath: "/search/photos?main_tag=0&search_query={keyword}",
            categoryPath: "/theme/",
            detailPath: "/album/{comicId}",
            enabled: enabled,
            routes: [
                "latest": "/albums?o=mr",
                "search": "/search/photos?main_tag=0&search_query={keyword}",
                "categoryIndex": "/theme/",
                "detail": "/album/{comicId}",
                "chapter": "/photo/{chapterId}"
            ],
            filters: [:]
        )
    }

    public static func hanman18(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "hanman18",
            name: "Hanman18",
            domain: "hanman18.com",
            baseUrl: "https://hanman18.com",
            referer: "https://hanman18.com/",
            latestPath: "/list-manga{pagePath}",
            searchPath: "/search?search={keyword}",
            categoryPath: "/list-manga{pagePath}",
            detailPath: "/manhwa/{comicId}",
            enabled: enabled,
            routes: [
                "latest": "/list-manga{pagePath}",
                "search": "/search?search={keyword}",
                "category": "/list-manga{pagePath}",
                "detail": "/manhwa/{comicId}",
                "chapter": "/manhwa/{comicId}/{chapterId}",
                "home": "/"
            ],
            filters: ["category.all": ""]
        )
    }

    public static func manhuagui(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "manhuagui",
            name: "漫画柜",
            domain: "www.manhuagui.com",
            baseUrl: "https://www.manhuagui.com",
            referer: "https://www.manhuagui.com/",
            latestPath: "/list",
            searchPath: "/s/{keyword}.html",
            categoryPath: "/list",
            detailPath: "/comic/{comicId}",
            enabled: enabled,
            routes: [
                "latest": "/list",
                "search": "/s/{keyword}.html",
                "category": "/list",
                "detail": "/comic/{comicId}",
                "chapter": "/comic/{comicId}/{chapterId}.html"
            ],
            filters: [
                "region.all": "",
                "region.jp": "japan",
                "region.cn": "china",
                "region.kr": "korea",
                "region.hk": "hongkong",
                "region.en": "europe",
                "region.other": "other",
                "state.all": "",
                "state.serial": "lianzai",
                "state.pub": "wanjie"
            ]
        )
    }

    public static func d5d6(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "d5d6",
            name: "悦看漫画",
            domain: "www.d5d6.com",
            baseUrl: "https://www.d5d6.com",
            referer: "https://www.d5d6.com/",
            latestPath: "/jiujiucate_jiujiuquanbu_allvisit_0_{page}/",
            searchPath: "/search/{keyword}/",
            categoryPath: "/jiujiucate_{slug}_allvisit_{finish}_{page}/",
            detailPath: "/jiujiucomic_{comicId}/",
            enabled: enabled,
            routes: [
                "latest": "/jiujiucate_jiujiuquanbu_allvisit_0_{page}/",
                "search": "/search/{keyword}/",
                "category": "/jiujiucate_{slug}_allvisit_{finish}_{page}/",
                "categoryIndex": "/jiujiucate_quanbu/",
                "detail": "/jiujiucomic_{comicId}/",
                "chapter": "/jiujiucomic_{comicId}/{chapterId}.html"
            ],
            filters: [:]
        )
    }

    public static func manben(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "manben",
            name: "漫本",
            domain: "www.manben.com",
            baseUrl: "https://www.manben.com",
            referer: "https://www.manben.com/",
            latestPath: "/mh-list/pagerdata.ashx",
            searchPath: "/search?page={page}&title={keyword}&language=1",
            categoryPath: "/mh-list/pagerdata.ashx",
            detailPath: "/mh-{comicId}/",
            enabled: enabled,
            routes: [
                "latest": "/mh-list/pagerdata.ashx",
                "categoryIndex": "/mh-list/",
                "category": "/mh-list/pagerdata.ashx",
                "search": "/search?page={page}&title={keyword}&language=1",
                "detail": "/mh-{comicId}/",
                "chapter": "/m{chapterId}/",
                "chapterImages": "/imageshow.ashx?cid={chapterId}&page={page}&showtype=1&ispre=0"
            ],
            filters: [
                "sort.latest": "2",
                "sort.popular": "4",
                "state.all": "0",
                "state.serial": "1",
                "state.pub": "2",
                "category.全部": "",
                "category.题材·搞笑": "tagid:37",
                "category.题材·奇幻": "tagid:14",
                "category.题材·热血": "tagid:31",
                "category.题材·悬疑": "tagid:17",
                "category.题材·格斗": "tagid:28",
                "category.题材·科幻": "tagid:25",
                "category.题材·励志": "tagid:10",
                "category.题材·校园": "tagid:1",
                "category.题材·爱情": "tagid:26",
                "category.题材·日常": "tagid:7",
                "category.题材·战争": "tagid:12",
                "category.题材·其他": "tagid:3",
                "category.受众·少年向": "tgroup:1",
                "category.受众·少女向": "tgroup:2",
                "category.受众·青年向": "tgroup:3",
                "category.地区·港台": "tarea:35",
                "category.地区·日韩": "tarea:36",
                "category.地区·大陆": "tarea:37",
                "category.地区·欧美": "tarea:52"
            ]
        )
    }

    public static func liumanhua(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "liumanhua",
            name: "六漫画",
            domain: "www.liumanhua.com",
            baseUrl: "https://www.liumanhua.com",
            referer: "https://www.liumanhua.com/",
            latestPath: "/category",
            searchPath: "",
            categoryPath: "/category{filterPath}{pagePath}",
            detailPath: "/{comicId}",
            enabled: enabled,
            routes: [
                "latest": "/category",
                "categoryIndex": "/category",
                "category": "/category{filterPath}{pagePath}",
                "detail": "/{comicId}",
                "chapter": "{chapterUrl}"
            ],
            filters: [:]
        )
    }

    public static func dingmanhua(enabled: Bool = true) -> SourceConfigItem {
        let tags = ["悬疑", "欢乐", "搞笑", "玄幻", "冒险", "爱情", "百合", "推理", "热血", "异界", "轻改", "奇幻", "校园", "妹控", "生活", "竞技", "同人", "伪娘", "东方", "美食", "格斗", "战争", "舰娘", "治愈", "魔幻", "职场", "性转", "萌系", "后宫", "节操", "魔法", "科幻", "穿越", "仙侠", "都市", "异能", "网游", "短篇", "女主", "恐怖", "重生", "日常", "侦探", "言情", "生存", "武侠", "系统", "励志", "末世", "转生", "长篇", "修仙", "末日", "灵异", "游戏", "爱倩", "销毁", "病娇", "音乐", "爆笑", "机战", "复仇", "舞蹈"]
        var filters: [String: String] = [
            "region.all": "",
            "region.jp": "1",
            "region.cn": "3",
            "region.kr": "4"
        ]
        for (i, tag) in tags.enumerated() {
            filters["tag." + tag] = String(i + 1)
        }
        return SourceConfigItem(
            id: "dingmanhua",
            name: "顶漫画",
            domain: "www.dingmanhua.com",
            baseUrl: "https://www.dingmanhua.com",
            referer: "https://www.dingmanhua.com/",
            latestPath: "",
            searchPath: "",
            categoryPath: "",
            detailPath: "",
            enabled: enabled,
            routes: [
                "latest": "/sort/?category=&tag=&page={page}",
                "search": "/search/?query={keyword}&page={page}",
                "category": "/sort/?category={category}&tag={tag}&page={page}",
                "detail": "/comic/{comicId}.html",
                "chapters": "/comic/{comicId}",
                "chapter": "/chapter/{contentId}-{chapterId}.html"
            ],
            filters: filters
        )
    }

    public static func dongmanla(enabled: Bool = true) -> SourceConfigItem {
        var filters: [String: String] = [
            "category.all": "/manhua/",
            "category.jp": "/manhua/japan/",
            "category.hk": "/manhua/hongkongtaiwan/",
            "category.west": "/manhua/oumei/",
            "category.cn": "/manhua/guochan/",
            "category.kr": "/manhua/hanguo/",
            "category.finish": "/manhua/finish/",
            "category.serial": "/manhua/serial/"
        ]
        let genres = [83, 82, 81, 62, 56, 53, 52, 49, 48, 47, 46, 45, 44, 43, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16]
        for g in genres {
            filters["category.genre.\(g)"] = "/manhua/class/\(g)/"
        }
        return SourceConfigItem(
            id: "dongmanla",
            name: "动漫啦",
            domain: "www.dongman.la",
            baseUrl: "https://www.dongman.la",
            referer: "https://www.dongman.la/",
            latestPath: "",
            searchPath: "",
            categoryPath: "",
            detailPath: "",
            enabled: enabled,
            routes: [
                "latest": "/manhua/",
                "search": "/manhua/so/{keyword}/{page}.html",
                "category": "{categoryPath}",
                "detail": "/manhua/detail/{comicId}/",
                "chapter": "{chapterUrl}"
            ],
            filters: filters
        )
    }

    public static func zaimanhua(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "zaimanhua",
            name: "再漫画",
            domain: "manhua.zaimanhua.com",
            baseUrl: "https://v4api.zaimanhua.com",
            referer: "https://manhua.zaimanhua.com/",
            latestPath: "",
            searchPath: "",
            categoryPath: "",
            detailPath: "",
            enabled: enabled,
            routes: [
                "latest": "/app/v1/comic/update/list/0/{page}",
                "search": "/app/v1/search/index?source=0&size=20&page={page}&keyword={keyword}",
                "category": "/app/v1/comic/filter/list?size=20&page={page}",
                "detail": "/app/v1/comic/detail/{comicId}?_v=2.2.5",
                "chapter": "/app/v1/comic/chapter/{comicId}/{chapterId}?_v=2.2.5"
            ],
            filters: [:]
        )
    }

    public static func guazi(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "guazi",
            name: "瓜子漫画",
            domain: "www.guazimanhua.com",
            baseUrl: "https://www.guazimanhua.com",
            referer: "https://www.guazimanhua.com/",
            latestPath: "",
            searchPath: "",
            categoryPath: "",
            detailPath: "",
            enabled: enabled,
            routes: [
                "latest": "/category.php?sort=update&page={page}",
                "search": "/category.php?keyword={keyword}&page={page}",
                "category": "/category.php?page={page}",
                "detail": "/comic.php?id={comicId}",
                "chapter": "/chapter.php?id={chapterId}"
            ],
            filters: [:]
        )
    }

    public static func xinmanhua(enabled: Bool = true) -> SourceConfigItem {
        let genres = [
            "全部:all", "治愈:治愈", "日常:日常", "都市:都市", "悬疑:悬疑",
            "科幻:科幻", "奇幻:奇幻", "热血:热血", "武侠:武侠", "古风:古风",
            "恋爱:恋爱", "少年:少年", "日漫:日漫", "原创:原创"
        ]
        var filters: [String: String] = [
            "ischarge.all": "2",
            "ischarge.free": "0",
            "ischarge.paid": "1",
            "isfinish.all": "2",
            "isfinish.serial": "0",
            "isfinish.finished": "1",
            "order.update": "0",
            "order.popular": "1"
        ]
        for item in genres {
            let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                filters["genre." + parts[0]] = parts[1]
            }
        }
        return SourceConfigItem(
            id: "xinmanhua",
            name: "新漫画-A",
            domain: "xapi.xinmanhua.net",
            baseUrl: "https://xapi.xinmanhua.net",
            referer: "https://xapi.xinmanhua.net/",
            latestPath: "",
            searchPath: "",
            categoryPath: "",
            detailPath: "",
            enabled: enabled,
            routes: [
                "latest": "/search/catalog?keyword=all&ischarge=2&isfinish=2&order=0&page={page}",
                "search": "/search/selfdefine",
                "category": "/search/catalog?keyword={keyword}&ischarge={ischarge}&isfinish={isfinish}&order={order}&page={page}",
                "detail": "/worksinfos/{wid}",
                "chapters": "/worksinfos/{wid}/chapters",
                "chapter": "/chapters/{chapterId}/qualitywebs"
            ],
            filters: filters
        )
    }

    public static func defaultConfig(for id: String) -> SourceConfigItem? {
        switch id {
        case "baozimh": return baozi()
        case "mh160": return mh160()
        case "gmh": return gmh()
        case "mh18": return mh18()
        case "jmcomic": return jmcomic()
        case "mkzhan": return mkzhan()
        case "hanman18": return hanman18()
        case "manhuagui": return manhuagui()
        case "d5d6": return d5d6()
        case "manben": return manben()
        case "manwa": return manwa()
        case "copy4000", "copymanga": return copy4000()
        case "manhuazhan", "five_um": return manhuazhan()
        case "bbyin": return bbyin()
        case "antbyw": return antbyw()
        case "cuimh": return cuimh()
        case "liumanhua": return liumanhua()
        case "dingmanhua": return dingmanhua()
        case "dongmanla": return dongmanla()
        case "zaimanhua": return zaimanhua()
        case "guazi": return guazi()
        case "xinmanhua": return xinmanhua()
        default:
            return PublicSourceRegistry.contains(id) ? PublicSourceRegistry.config(id) : nil
        }
    }
}
