import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// VPN requirement metadata and helpers aligned with Android 2.0.44~2.0.45 `SourceVpnBadge` & `RuleDefinition`.
public enum SourceVpnPolicy {
    public static let defaultVpnSourceIds: Set<String> = [
        "mangadex", "xcomic", "nhentai", "wnacg", "hiperdex", "copy4000", "jm", "mh18", "hanman18"
    ]

    public static func requiresVpn(sourceId: String, ruleCatalog: RuleCatalog? = nil) -> Bool {
        if let catalog = ruleCatalog, let entry = catalog.entries().first(where: { $0.rule.id == sourceId && !$0.removed }) {
            return entry.rule.requiresVpn
        }
        return defaultVpnSourceIds.contains(sourceId)
    }
}

/// Native public protocols with bounded responses, cancellation and expiring image lists (`ReviewedComicSource.java`).
open class ReviewedComicSource: ComicSource, @unchecked Sendable {
    public typealias RequestOverride = (_ url: String, _ method: String, _ body: String?, _ referer: String?, _ json: Bool) async throws -> PublicHTTPResponse

    public let config: SourceConfigItem
    private let transport: any HTTPTransport
    public var requestOverride: RequestOverride?

    private let pageLock = NSLock()
    private var pages: [String: (urls: [String], at: TimeInterval)] = [:]
    private var pageOrder: [String] = []
    private var lastMoreFlag: Bool = false

    public var id: String { config.id }
    public var name: String { config.name }
    public var referer: String { config.referer }
    public var supportsSearch: Bool { true }
    public var hasMoreLastListing: Bool {
        pageLock.lock()
        defer { pageLock.unlock() }
        return lastMoreFlag
    }

    public init(config: SourceConfigItem, transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25), requestOverride: RequestOverride? = nil) {
        self.config = config
        self.transport = transport
        self.requestOverride = requestOverride
    }

    open func userAgent() -> String {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36"
    }

    open func requestUserAgent(_ url: String) -> String {
        userAgent()
    }

    public func absolute(_ path: String) -> String {
        PublicSourceImages.resolve(config.baseUrl.hasSuffix("/") ? config.baseUrl : config.baseUrl + "/", path)
    }

    open func request(_ url: String, method: String = "GET", body: String? = nil, referer: String? = nil, json: Bool = false) async throws -> PublicHTTPResponse {
        try Task.checkCancellation()
        if let override = requestOverride {
            return try await override(url, method, body, referer, json)
        }
        guard let target = URL(string: url), let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw Self.ioError("请求地址协议无效")
        }
        var headers: [String: String] = [
            "User-Agent": requestUserAgent(url),
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": referer ?? config.referer
        ]
        let response: HTTPResponse
        if method == "POST" {
            headers["Content-Type"] = json ? "application/json" : "application/x-www-form-urlencoded"
            headers["Origin"] = config.baseUrl
            let bodyData = (body ?? "").data(using: .utf8) ?? Data()
            response = try await transport.post(target, headers: headers, body: bodyData)
        } else {
            response = try await transport.get(target, headers: headers)
        }
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            throw Self.ioError("\(name) 请求失败（HTTP \(response.statusCode)），请稍后重试")
        }
        guard response.data.count < 12 * 1024 * 1024 else {
            throw Self.ioError("站点响应过大")
        }
        let text = String(decoding: response.data, as: UTF8.self)
        if text.contains("cf-chl-") || text.contains("Just a moment...") || text.contains("搜索繁忙") {
            throw Self.ioError("\(name) 需要网站验证或请求过于频繁，请稍后重试")
        }
        return PublicHTTPResponse(body: text, url: target.absoluteString, statusCode: response.statusCode)
    }

    func setMore(_ value: Bool) {
        pageLock.lock()
        lastMoreFlag = value
        pageLock.unlock()
    }

    func getJSON(_ url: String) async throws -> [String: Any] {
        let res = try await request(url)
        return try Self.parseJSONObject(res.body)
    }

    static func parseJSONObject(_ text: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ioError("站点返回了无效数据，请重试")
        }
        return obj
    }

    static func str(_ dict: [String: Any]?, _ key: String, _ fallback: String = "") -> String {
        guard let val = dict?[key], !(val is NSNull) else { return fallback }
        if let s = val as? String { return s }
        if let n = val as? NSNumber { return n.stringValue }
        return fallback
    }

    static func array(_ dict: [String: Any]?, _ key: String) throws -> [Any] {
        guard let arr = dict?[key] as? [Any] else {
            throw ioError("接口缺少列表：\(key)")
        }
        return arr
    }

    static func data(_ dict: [String: Any]?, _ key: String) throws -> [String: Any] {
        guard let obj = dict?[key] as? [String: Any] else {
            throw ioError("接口缺少数据：\(key)")
        }
        return obj
    }

    static func imagePath(_ rows: [Any], _ index: Int) throws -> String {
        guard rows.indices.contains(index),
              let s = rows[index] as? String,
              !SearchRules.trim(s).isEmpty,
              s != "null" else {
            throw ioError("正文图片路径缺失")
        }
        return s
    }

    func key(_ comicId: String) throws -> String {
        let prefix = id + ":"
        guard comicId.hasPrefix(prefix) else {
            throw Self.ioError("作品来源不匹配")
        }
        return String(comicId.dropFirst(prefix.count))
    }

    func makeSummary(key: String, title: String, cover: String, subtitle: String) throws -> ComicSummary {
        let cleanTitle = SearchRules.trim(title)
        guard !key.isEmpty, !cleanTitle.isEmpty else {
            throw Self.ioError("作品数据缺少标题或编号")
        }
        var normCover = cover
        if normCover.hasPrefix("///") {
            while normCover.hasPrefix("/") { normCover.removeFirst() }
            normCover = "//" + normCover
        }
        let resolvedCover = normCover.isEmpty ? "" : PublicSourceImages.tag(
            PublicSourceImages.resolve(config.baseUrl + "/", normCover),
            id,
            config.referer,
            -1
        )
        return ComicSummary(sourceId: id, comicId: id + ":" + key, title: cleanTitle, coverUrl: resolvedCover, subtitle: subtitle)
    }

    func makePage(chapterUrl: String, title: String, urls: [String]) throws -> ChapterPage {
        try Task.checkCancellation()
        var safe: [String] = []
        for u in urls {
            let trimmed = SearchRules.trim(u)
            guard !trimmed.isEmpty, trimmed != "null" else {
                throw Self.ioError("正文图片路径缺失")
            }
            let resolved = PublicSourceImages.resolve(chapterUrl, trimmed)
            guard resolved.range(of: #"^https?://[^\s]+$"#, options: .regularExpression) != nil else {
                throw Self.ioError("正文返回了无效图片地址")
            }
            safe.append(resolved)
        }
        guard !safe.isEmpty, safe.count <= 10000 else {
            throw Self.ioError("没有取得可读正文图片")
        }
        pageLock.lock()
        pages[chapterUrl] = (safe, ProcessInfo.processInfo.systemUptime)
        pageOrder.removeAll { $0 == chapterUrl }
        pageOrder.append(chapterUrl)
        while pageOrder.count > 16 {
            let oldest = pageOrder.removeFirst()
            pages.removeValue(forKey: oldest)
        }
        pageLock.unlock()
        let tagged = safe.enumerated().map { idx, u in
            PublicSourceImages.tag(u, id, chapterUrl, idx)
        }
        return ChapterPage(chapterId: chapterUrl, title: title, nextPageUrl: "", imageUrls: tagged)
    }

    public func resolveImageUrl(imageUrl tagged: String, force: Bool) async throws -> String {
        let m = PublicSourceImages.metadata(tagged)
        guard m.count == 3, m[0] == id, let idx = Int(m[2]), idx >= 0 else {
            return PublicSourceImages.strip(tagged)
        }
        let chapterUrl = m[1]
        var cached: (urls: [String], at: TimeInterval)? = {
            pageLock.lock()
            defer { pageLock.unlock() }
            return pages[chapterUrl]
        }()
        if force || cached == nil || (ProcessInfo.processInfo.systemUptime - (cached?.at ?? 0)) > 180 {
            _ = try await chapter(url: chapterUrl)
            pageLock.lock()
            cached = pages[chapterUrl]
            pageLock.unlock()
        }
        guard let valid = cached, valid.urls.indices.contains(idx) else {
            throw Self.ioError("正文页数已变化，请重新打开章节")
        }
        return valid.urls[idx]
    }

    func ownUrl(_ url: String) throws {
        guard let uHost = URL(string: url)?.host?.lowercased(),
              let bHost = URL(string: config.baseUrl)?.host?.lowercased(),
              uHost == bHost else {
            throw Self.ioError("章节来源不匹配")
        }
    }

    static func slots(_ rows: [Chapter]) -> [Chapter] {
        rows.enumerated().map { idx, c in
            Chapter(chapterId: c.chapterId, title: c.title, url: c.url, sectionSlot: 0, chapterSlot: idx)
        }
    }

    static func ioError(_ message: String) -> NSError {
        NSError(domain: "ReviewedComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // Subclasses override:
    open func filterGroups() async throws -> [SourceFilterGroup] { [] }
    open func latest(page: Int) async throws -> [ComicSummary] { try await category(filters: [:], page: page) }
    open func search(keyword: String, page: Int) async throws -> [ComicSummary] { [] }
    open func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { [] }
    open func detail(comicId: String) async throws -> ComicDetail { throw Self.ioError("未实现") }
    open func chapters(comicId: String) async throws -> [Chapter] { [] }
    open func chapter(url: String) async throws -> ChapterPage { throw Self.ioError("未实现") }
}

/// MangaDex Chinese translation adapter (`MangaDexComicSource.java`).
public final class MangaDexComicSource: ReviewedComicSource, @unchecked Sendable {
    public static let api = "https://api.mangadex.org"
    public static let chineseQuery = "&availableTranslatedLanguage[]=zh&availableTranslatedLanguage[]=zh-hk&hasAvailableChapters=true&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&includes[]=cover_art"

    public static func defaultConfig(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(id: "mangadex", name: "MangaDex", domain: "mangadex.org", baseUrl: "https://mangadex.org", referer: "https://mangadex.org/", latestPath: "", searchPath: "", categoryPath: "", detailPath: "", enabled: enabled)
    }

    public override init(config: SourceConfigItem = MangaDexComicSource.defaultConfig(), transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25), requestOverride: RequestOverride? = nil) {
        super.init(config: config, transport: transport, requestOverride: requestOverride)
    }

    private func uuid(_ value: String) throws -> String {
        guard value.range(of: #"^[a-fA-F0-9-]{36}$"#, options: .regularExpression) != nil else {
            throw Self.ioError("作品或章节编号无效")
        }
        return value
    }

    public override func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        let trimmed = SearchRules.trim(keyword)
        guard !trimmed.isEmpty else { setMore(false); return [] }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return try await listing("/manga?limit=20&offset=\((max(1, page) - 1) * 20)&title=\(encoded)\(Self.chineseQuery)")
    }

    public override func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let tag = filters["region"].flatMap { $0 == "all" ? "" : $0 } ?? ""
        let order = filters["order"].flatMap { $0.isEmpty || $0 == "all" ? nil : $0 } ?? "followedCount"
        guard ["followedCount", "latestUploadedChapter", "createdAt"].contains(order) else {
            throw Self.ioError("排序无效")
        }
        let tagParam = tag.isEmpty ? "" : "&includedTags[]=\(try uuid(tag))"
        return try await listing("/manga?limit=20&offset=\((max(1, page) - 1) * 20)&order[\(order)]=desc\(tagParam)\(Self.chineseQuery)")
    }

    private func listing(_ route: String) async throws -> [ComicSummary] {
        let root = try await getJSON(Self.api + route)
        let rows = try Self.array(root, "data")
        var out: [ComicSummary] = []
        for item in rows {
            guard let obj = item as? [String: Any] else { continue }
            out.append(try parseManga(obj))
        }
        let offset = (root["offset"] as? Int) ?? 0
        let total = (root["total"] as? Int) ?? 0
        setMore(offset + rows.count < total)
        return out
    }

    private func parseManga(_ m: [String: Any]) throws -> ComicSummary {
        let a = try Self.data(m, "attributes")
        let t = try Self.data(a, "title")
        var title = [Self.str(t, "zh"), Self.str(t, "zh-hk")].first { !$0.isEmpty } ?? ""
        if title.isEmpty, let alts = a["altTitles"] as? [[String: Any]] {
            for alt in alts {
                title = [Self.str(alt, "zh"), Self.str(alt, "zh-hk")].first { !$0.isEmpty } ?? ""
                if !title.isEmpty { break }
            }
        }
        if title.isEmpty {
            title = [Self.str(t, "en"), Self.str(t, "ja-ro")].first { !$0.isEmpty } ?? (t.values.compactMap { $0 as? String }.first ?? "")
        }
        let mid = try uuid(Self.str(m, "id"))
        var cover = ""
        if let rels = m["relationships"] as? [[String: Any]] {
            for r in rels where Self.str(r, "type") == "cover_art" {
                if let attrs = r["attributes"] as? [String: Any] {
                    let fn = Self.str(attrs, "fileName")
                    if !fn.isEmpty {
                        cover = "https://uploads.mangadex.org/covers/\(mid)/\(fn).256.jpg"
                    }
                }
            }
        }
        return try makeSummary(key: mid, title: title, cover: cover, subtitle: "简体 / 繁体中文译本")
    }

    public override func detail(comicId: String) async throws -> ComicDetail {
        let id = try uuid(key(comicId))
        let root = try await getJSON("\(Self.api)/manga/\(id)?includes[]=cover_art&includes[]=author")
        let m = try Self.data(root, "data")
        let a = try Self.data(m, "attributes")
        let d = a["description"] as? [String: Any]
        var author = ""
        if let rels = m["relationships"] as? [[String: Any]] {
            for r in rels where Self.str(r, "type") == "author" {
                if let attrs = r["attributes"] as? [String: Any] {
                    author = Self.str(attrs, "name")
                }
            }
        }
        let desc = [Self.str(d, "zh"), Self.str(d, "zh-hk"), Self.str(d, "en")].first { !$0.isEmpty } ?? ""
        return ComicDetail(summary: try parseManga(m), author: author, status: Self.str(a, "status"), description: desc, latestChapter: "", chapters: [])
    }

    public override func chapters(comicId: String) async throws -> [Chapter] {
        let id = try uuid(key(comicId))
        var out: [Chapter] = []
        var seen: [String: Int] = [:]
        var offset = 0
        var total = 0
        repeat {
            try Task.checkCancellation()
            let url = "\(Self.api)/manga/\(id)/feed?translatedLanguage[]=zh&translatedLanguage[]=zh-hk&limit=100&offset=\(offset)&order[chapter]=asc&order[volume]=asc&includes[]=scanlation_group&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic"
            let root = try await getJSON(url)
            let rows = try Self.array(root, "data")
            total = (root["total"] as? Int) ?? 0
            if rows.isEmpty && offset < total {
                throw Self.ioError("目录分页中断，请重试")
            }
            for item in rows {
                guard let ch = item as? [String: Any] else { continue }
                let a = try Self.data(ch, "attributes")
                let lang = Self.str(a, "translatedLanguage")
                guard ["zh", "zh-hk"].contains(lang), Self.str(a, "externalUrl").isEmpty else { continue }
                let cid = try uuid(Self.str(ch, "id"))
                let vol = Self.str(a, "volume")
                let chap = Self.str(a, "chapter")
                var title = (vol.isEmpty ? "" : "第\(vol)卷 ") + (chap.isEmpty ? "" : "第\(chap)话 ") + Self.str(a, "title")
                title += " [\(lang == "zh" ? "简中" : "繁中")]"
                if let rels = ch["relationships"] as? [[String: Any]] {
                    for r in rels where Self.str(r, "type") == "scanlation_group" {
                        if let attrs = r["attributes"] as? [String: Any] {
                            let gName = Self.str(attrs, "name")
                            if !gName.isEmpty { title += " · \(gName)" }
                        }
                    }
                }
                let chapterObj = Chapter(chapterId: cid, title: title, url: absolute("/chapter/\(cid)"), sectionSlot: 0, chapterSlot: 0)
                if let existingIdx = seen[cid] {
                    out[existingIdx] = chapterObj
                } else {
                    seen[cid] = out.count
                    out.append(chapterObj)
                }
            }
            offset += rows.count
            if offset > 20000 { throw Self.ioError("目录过大，请检查站点") }
        } while offset < total
        guard !out.isEmpty else {
            throw Self.ioError("此作品没有本站可读的中文章节")
        }
        return Self.slots(out)
    }

    public override func chapter(url: String) async throws -> ChapterPage {
        try ownUrl(url)
        let path = URL(string: url)?.path ?? ""
        let cid = try uuid(PublicSourceImages.match(path, #"^/chapter/([a-fA-F0-9-]{36})$"#))
        let root = try await getJSON("\(Self.api)/at-home/server/\(cid)")
        let c = try Self.data(root, "chapter")
        let rows = try Self.array(c, "data")
        let base = Self.str(root, "baseUrl")
        guard base.hasPrefix("https://") else {
            throw Self.ioError("图片服务地址无效")
        }
        let hash = Self.str(c, "hash")
        var urls: [String] = []
        for idx in 0..<rows.count {
            urls.append("\(base)/data/\(hash)/\(try Self.imagePath(rows, idx))")
        }
        return try makePage(chapterUrl: url, title: "中文章节", urls: urls)
    }
}

/// Xcomic GraphQL Chinese edition adapter (`XcomicComicSource.java`).
public final class XcomicComicSource: ReviewedComicSource, @unchecked Sendable {
    private static let browseQuery = "query get_title_browse_items($select:Title_Browse_Select){items:get_title_browse_items(select:$select){data{name:title urlCover:cover_local_url} comicNodes{data{id name subName urlPath translatedLanguage chaps_normal dbStatus isPublic}}}}"
    private static let comicQuery = "query get_comicNode($id:ID!){get_comicNode(id:$id){data{id name subName urlCover translatedLanguage originalStatus authorNodes{data{name}} summary{text} genres}}}"
    private static let chaptersQuery = "query get_comic_chapterList_uniqList($select:Select_Comic_ChapterList_UniqList){chapterList:get_comic_chapterList_uniqList(select:$select){paging{next total} items{data{id dbStatus serial chaNum volNum dname title urlPath srcName}}}}"
    private static let pagesQuery = "query get_chapterNode($id:ID!){get_chapterNode(id:$id){data{imageUrls}}}"

    public static func defaultConfig(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(id: "xcomic", name: "XCOMIC", domain: "xcomic.com", baseUrl: "https://xcomic.com", referer: "https://xcomic.com/", latestPath: "", searchPath: "", categoryPath: "", detailPath: "", enabled: enabled)
    }

    public override init(config: SourceConfigItem = XcomicComicSource.defaultConfig(), transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25), requestOverride: RequestOverride? = nil) {
        super.init(config: config, transport: transport, requestOverride: requestOverride)
    }

    private func ident(_ id: String) throws -> String {
        guard id.range(of: #"^[A-Za-z0-9_-]{1,100}$"#, options: .regularExpression) != nil else {
            throw Self.ioError("作品或章节编号无效")
        }
        return id
    }

    private func gql(_ query: String, variables: [String: Any]) async throws -> [String: Any] {
        let payload: [String: Any] = ["query": query, "variables": variables]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let bodyString = String(decoding: data, as: UTF8.self)
        let res = try await request(absolute("/query/"), method: "POST", body: bodyString, referer: config.referer, json: true)
        let root = try Self.parseJSONObject(res.body)
        if let errors = root["errors"] as? [Any], !errors.isEmpty {
            throw Self.ioError("XCOMIC接口暂时不可用，请稍后重试")
        }
        return try Self.data(root, "data")
    }

    public override func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        let trimmed = SearchRules.trim(keyword)
        guard !trimmed.isEmpty else { setMore(false); return [] }
        return try await browse(word: trimmed, genre: "", order: "field_score", page: page)
    }

    public override func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let genre = filters["region"].flatMap { $0 == "all" ? "" : $0 } ?? ""
        let order = filters["order"].flatMap { $0.isEmpty || $0 == "all" ? nil : $0 } ?? "field_score"
        return try await browse(word: "", genre: genre, order: order, page: page)
    }

    private func browse(word: String, genre: String, order: String, page: Int) async throws -> [ComicSummary] {
        guard genre.range(of: #"^[a-z_]*$"#, options: .regularExpression) != nil,
              ["field_score", "field_update", "field_create", "field_follow"].contains(order) else {
            throw Self.ioError("分类参数无效")
        }
        var select: [String: Any] = [
            "where": "browse",
            "page": max(1, page),
            "size": 48,
            "sortby": order,
            "incTLangs": ["zh"],
            "incGenres": genre.isEmpty ? [] : [genre],
            "excGenres": [],
            "incGenresMode": "and",
            "excGenresMode": "or",
            "incTypes": [],
            "incDemographics": [],
            "incContentRatings": ["safe", "suggestive", "erotica", "pornographic"],
            "ignoreGlobalULangs": false,
            "ignoreGlobalGenres": false,
            "ignoreGlobalBlocks": false
        ]
        if !word.isEmpty { select["word"] = word }
        let data = try await gql(Self.browseQuery, variables: ["select": select])
        let titles = try Self.array(data, "items")
        var result: [ComicSummary] = []
        var ids = Set<String>()
        for item in titles {
            guard let t = item as? [String: Any] else { continue }
            let a = try Self.data(t, "data")
            let editions = try Self.array(t, "comicNodes")
            for ed in editions {
                guard let edObj = ed as? [String: Any] else { continue }
                let e = try Self.data(edObj, "data")
                let cid = Self.str(e, "id")
                let lang = Self.str(e, "translatedLanguage")
                let dbStatus = Self.str(e, "dbStatus", "normal")
                let isPublic = (e["isPublic"] as? Bool) ?? true
                let chapsNormal = (e["chaps_normal"] as? Int) ?? 0
                guard lang == "zh", dbStatus == "normal", isPublic, chapsNormal > 0, ids.insert(cid).inserted else { continue }
                let title = [Self.str(e, "name"), Self.str(a, "name")].first { !$0.isEmpty } ?? ""
                result.append(try makeSummary(key: try ident(cid), title: title, cover: Self.str(a, "urlCover"), subtitle: Self.str(e, "subName")))
            }
        }
        setMore(titles.count >= 48)
        return result
    }

    public override func detail(comicId: String) async throws -> ComicDetail {
        let cid = try ident(key(comicId))
        let root = try await gql(Self.comicQuery, variables: ["id": cid])
        let node = try Self.data(root, "get_comicNode")
        let a = try Self.data(node, "data")
        guard Self.str(a, "translatedLanguage") == "zh" else {
            throw Self.ioError("此作品没有中文译本")
        }
        var authors: [String] = []
        if let nodes = a["authorNodes"] as? [[String: Any]] {
            for n in nodes {
                if let author = n["data"] as? [String: Any] {
                    let name = Self.str(author, "name")
                    if !name.isEmpty { authors.append(name) }
                }
            }
        }
        let summaryObj = a["summary"] as? [String: Any]
        let desc = Self.str(summaryObj, "text")
        let summary = try makeSummary(key: Self.str(a, "id"), title: Self.str(a, "name"), cover: Self.str(a, "urlCover"), subtitle: Self.str(a, "subName"))
        return ComicDetail(summary: summary, author: authors.joined(separator: " / "), status: Self.str(a, "originalStatus"), description: desc, latestChapter: "", chapters: [])
    }

    public override func chapters(comicId: String) async throws -> [Chapter] {
        let comic = try ident(key(comicId))
        var rows: [Chapter] = []
        var seen: [String: Int] = [:]
        var pg = 1
        while true {
            try Task.checkCancellation()
            let select: [String: Any] = ["comic_id": comic, "page": pg, "size": 1000, "sortby": "chapter_desc"]
            let data = try await gql(Self.chaptersQuery, variables: ["select": select])
            let root = try Self.data(data, "chapterList")
            let items = try Self.array(root, "items")
            let paging = try Self.data(root, "paging")
            let before = rows.count
            for item in items {
                guard let obj = item as? [String: Any] else { continue }
                let c = try Self.data(obj, "data")
                guard Self.str(c, "dbStatus", "normal") == "normal" else { continue }
                let cid = try ident(Self.str(c, "id"))
                var title = [Self.str(c, "dname"), Self.str(c, "title"), "第\(Self.str(c, "chaNum"))话"].first { !$0.isEmpty } ?? ""
                let sub = Self.str(c, "srcName")
                if !sub.isEmpty { title += " · \(sub)" }
                let ch = Chapter(chapterId: cid, title: title, url: absolute("/chapter/\(cid)"), sectionSlot: 0, chapterSlot: 0)
                if let idx = seen[cid] {
                    rows[idx] = ch
                } else {
                    seen[cid] = rows.count
                    rows.append(ch)
                }
            }
            if ((paging["next"] as? Int) ?? 0) == 0 { break }
            pg += 1
            if rows.count == before || pg > 100 {
                throw Self.ioError("目录分页重复或过大，请重试")
            }
        }
        guard !rows.isEmpty else {
            throw Self.ioError("没有取得可读章节")
        }
        rows.reverse()
        return Self.slots(rows)
    }

    public override func chapter(url: String) async throws -> ChapterPage {
        try ownUrl(url)
        let path = URL(string: url)?.path ?? ""
        let cid = try ident(PublicSourceImages.match(path, #"^/chapter/([A-Za-z0-9_-]+)$"#))
        let root = try await gql(Self.pagesQuery, variables: ["id": cid])
        let node = try Self.data(root, "get_chapterNode")
        let data = try Self.data(node, "data")
        let images = try Self.array(data, "imageUrls")
        var urls: [String] = []
        for idx in 0..<images.count {
            urls.append(PublicSourceImages.resolve(config.baseUrl + "/", try Self.imagePath(images, idx)))
        }
        return try makePage(chapterUrl: url, title: "中文章节", urls: urls)
    }
}

/// Hipmh comic source and finite chapter image decoder (`HipmhComicSource.java`).
public final class HipmhComicSource: ReviewedComicSource, @unchecked Sendable {
    public static func defaultConfig(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(id: "hipmh", name: "HIP漫画", domain: "www.hipmh.top", baseUrl: "https://www.hipmh.top", referer: "https://www.hipmh.top/", latestPath: "", searchPath: "", categoryPath: "", detailPath: "", enabled: enabled)
    }

    public override init(config: SourceConfigItem = HipmhComicSource.defaultConfig(), transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25), requestOverride: RequestOverride? = nil) {
        super.init(config: config, transport: transport, requestOverride: requestOverride)
    }

    /// Finite transform used by the site's chapter-decoder: markers, rotation, 7-char chunks, alphabet, Base64.
    public static func decodeImages(_ encoded: String) throws -> [String] {
        let utf16 = Array(encoded.utf16)
        guard utf16.count <= 8 * 1024 * 1024, encoded.hasPrefix("qM9"), encoded.hasSuffix("Z7") else {
            throw ioError("图片数据格式已变化")
        }
        let body = Array(utf16.dropFirst(3).dropLast(2))
        let size = body.count - 5
        guard size > 0 else {
            throw ioError("图片数据校验失败")
        }
        let tail = size / 3
        let head = (size - tail) / 2
        let middle = size - tail - head
        let m1 = head
        let m2 = head + 2 + middle
        let marker1 = String(utf16CodeUnits: Array(body[m1..<(m1 + 2)]), count: 2)
        let marker2 = String(utf16CodeUnits: Array(body[m2..<(m2 + 3)]), count: 3)
        guard marker1 == "Vx", marker2 == "pL0" else {
            throw ioError("图片数据校验失败")
        }
        let mixed = Array(body[(m2 + 3)...]) + Array(body[0..<head]) + Array(body[(head + 2)..<m2])
        var restored: [UInt16] = []
        restored.reserveCapacity(mixed.count)
        var i = 0
        var index = 0
        while i < mixed.count {
            let end = min(i + 7, mixed.count)
            let chunk = Array(mixed[i..<end])
            if index % 2 == 0 {
                restored.append(contentsOf: chunk)
            } else {
                restored.append(contentsOf: chunk.reversed())
            }
            i += 7
            index += 1
        }
        let from = Array("_-9876543210abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".utf16)
        let to = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf16)
        var map = [UInt16: UInt16]()
        for (idx, ch) in from.enumerated() { map[ch] = to[idx] }
        var b64Units: [UInt16] = []
        b64Units.reserveCapacity(restored.count)
        for unit in restored {
            guard let mapped = map[unit] else {
                throw ioError("图片数据字符无效")
            }
            b64Units.append(mapped)
        }
        var b64String = String(utf16CodeUnits: b64Units, count: b64Units.count)
        let rem = b64String.count % 4
        if rem > 0 {
            b64String += String(repeating: "=", count: 4 - rem)
        }
        guard let decodedData = Data(base64Encoded: b64String, options: .ignoreUnknownCharacters),
              let arr = try? JSONSerialization.jsonObject(with: decodedData) as? [String] else {
            throw ioError("图片列表解析失败")
        }
        return arr
    }
}

/// Single-gallery sources (`nhentai` / `wnacg`) (`GalleryComicSource.java`).
public final class GalleryComicSource: ReviewedComicSource, @unchecked Sendable {
    private let nh: Bool

    public static func defaultConfig(id: String) -> SourceConfigItem {
        if id == "nhentai" {
            return SourceConfigItem(id: "nhentai", name: "nhentai", domain: "nhentai.net", baseUrl: "https://nhentai.net", referer: "https://nhentai.net/", latestPath: "", searchPath: "", categoryPath: "", detailPath: "", enabled: true)
        }
        return SourceConfigItem(id: "wnacg", name: "绅士漫画", domain: "www.wnacg.com", baseUrl: "https://www.wnacg.com", referer: "https://www.wnacg.com/", latestPath: "", searchPath: "", categoryPath: "", detailPath: "", enabled: true)
    }

    public override init(config: SourceConfigItem, transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25), requestOverride: RequestOverride? = nil) {
        self.nh = (config.id == "nhentai")
        super.init(config: config, transport: transport, requestOverride: requestOverride)
    }

    private func number(_ n: String) throws -> String {
        guard n.range(of: #"^\d{1,12}$"#, options: .regularExpression) != nil else {
            throw Self.ioError("画册编号无效")
        }
        return n
    }

    public override func chapters(comicId: String) async throws -> [Chapter] {
        let cid = try number(key(comicId))
        let path = nh ? "/g/\(cid)/" : "/photos-gallery-aid-\(cid).html"
        return [Chapter(chapterId: cid, title: "完整画册", url: absolute(path), sectionSlot: 0, chapterSlot: 0)]
    }

    public override func detail(comicId: String) async throws -> ComicDetail {
        let cid = try number(key(comicId))
        if nh {
            let c = try await getJSON(absolute("/api/v2/galleries/\(cid)"))
            let t = try Self.data(c, "title")
            let tags = try Self.array(c, "tags")
            var chinese = false
            var authors: [String] = []
            for item in tags {
                guard let tag = item as? [String: Any] else { continue }
                if Self.str(tag, "type") == "language" && Self.str(tag, "name") == "chinese" { chinese = true }
                if Self.str(tag, "type") == "artist" { authors.append(Self.str(tag, "name")) }
            }
            guard chinese else { throw Self.ioError("此画册没有中文版本") }
            var cover = ""
            if let coverObj = c["cover"] as? [String: Any] { cover = Self.str(coverObj, "path") }
            else if let coverStr = c["cover"] as? String { cover = coverStr }
            let resolvedCover = cover.isEmpty ? "" : PublicSourceImages.resolve("https://t.nhentai.net/", cover)
            let title = [Self.str(t, "pretty"), Self.str(t, "english"), Self.str(t, "japanese")].first { !$0.isEmpty } ?? ""
            let numPages = (c["num_pages"] as? Int) ?? 0
            return ComicDetail(
                summary: try makeSummary(key: cid, title: title, cover: resolvedCover, subtitle: "中文画册"),
                author: authors.joined(separator: " / "),
                status: "单册",
                description: "\(numPages)页",
                latestChapter: "",
                chapters: []
            )
        }
        let r = try await request(absolute("/photos-index-aid-\(cid).html"))
        let title = Self.extractFirstText(in: r.body, patterns: [
            #"<[^>]+\bid\s*=\s*['"]comicName['"][^>]*>([\s\S]*?)</[^>]+>"#,
            #"<h2[^>]*>([\s\S]*?)</h2>"#
        ])
        let cover = PublicSourceImages.match(r.body, #"<div[^>]+id\s*=\s*['"]Cover['"][\s\S]*?<img[^>]+src\s*=\s*['"]([^'"]+)['"]"#)
        return ComicDetail(
            summary: try makeSummary(key: cid, title: title, cover: cover, subtitle: "画册"),
            author: "",
            status: "单册",
            description: "",
            latestChapter: "",
            chapters: []
        )
    }

    public static func wnImages(_ html: String) throws -> [String] {
        let array = PublicSourceImages.match(html, #"(?s)var\s+imglist\s*=\s*(\[.*?\]);"#)
        guard !array.isEmpty else {
            throw ioError("画册图片列表缺失")
        }
        let unescaped = array.replacingOccurrences(of: "\\\"", with: "\"")
        let regex = try NSRegularExpression(pattern: #"\burl\s*:\s*(?:fast_img_host\s*\+\s*)?["'](//[^"']+)["']"#, options: [])
        let ns = unescaped as NSString
        let matches = regex.matches(in: unescaped, range: NSRange(location: 0, length: ns.length))
        var urls: [String] = []
        for match in matches {
            if match.numberOfRanges > 1 {
                let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "\\/", with: "/")
                urls.append("https:" + raw)
            }
        }
        return urls
    }

    fileprivate static func extractFirstText(in html: String, patterns: [String]) -> String {
        for p in patterns {
            let m = PublicSourceImages.match(html, p)
            let stripped = m.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let trimmed = SearchRules.trim(HTML4EntityDecoder.decode(stripped))
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
