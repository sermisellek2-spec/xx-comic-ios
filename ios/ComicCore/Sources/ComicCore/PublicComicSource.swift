import Foundation

public struct PublicHTTPResponse: Sendable {
    public let body: String
    public let url: String
    public let statusCode: Int

    public init(body: String, url: String, statusCode: Int) {
        self.body = body
        self.url = url
        self.statusCode = statusCode
    }
}

open class PublicComicSource: ComicSource, @unchecked Sendable {
    public typealias RequestOverride = (_ url: String, _ method: String, _ body: String?, _ referer: String?, _ json: Bool) async throws -> PublicHTTPResponse

    public let config: SourceConfigItem
    public let profile: PublicSourceProfile
    public let family: String
    private let transport: any HTTPTransport
    public var requestOverride: RequestOverride?

    private let lock = NSLock()
    private var cookies: [String: String] = [:]
    private var csrf: String = ""
    private var cursorPages: [String: String] = [:]
    private var firstSearchPages: [String: Set<String>] = [:]
    private var firstSearchOrder: [String] = []
    private var searchNextPages: [String: String] = [:]
    private var imageLists: [String: CachedChapter] = [:]
    private var imageListOrder: [String] = []
    private var cachedLaimanFilters: [SourceFilterGroup]?

    private static let favAuthLock = NSLock()
    private static var favAuthCookieValue: String = ""
    private static var favAuthExpiresAt: Int64 = 0

    private static func withFavAuthLock<T>(_ body: () -> T) -> T {
        favAuthLock.lock()
        defer { favAuthLock.unlock() }
        return body()
    }

    private struct CachedChapter {
        let urls: [String]
        let at: Int64
    }

    public var id: String { config.id }
    public var name: String { config.name }
    public var referer: String { config.referer }
    public var supportsSearch: Bool { !profile.search.isEmpty }

    private let userAgent = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

    public init(config: SourceConfigItem, transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 20), requestOverride: RequestOverride? = nil) {
        self.config = config
        self.profile = try! PublicSourceRegistry.profile(config.id)
        self.family = profile.family
        self.transport = transport
        self.requestOverride = requestOverride
    }

    open func request(_ url: String, method: String = "GET", body: String? = nil, referer: String? = nil, json: Bool = false) async throws -> PublicHTTPResponse {
        if let override = requestOverride {
            return try await override(url, method, body, referer, json)
        }
        let requestUrl = family == "fav" ? Self.favFreeUrl(url) : url
        for attempt in 0..<2 {
            guard let targetURL = PublicSourceImages.parseLenientURL(requestUrl) else {
                throw Self.ioError("无效请求地址: \(requestUrl)")
            }
            var headers: [String: String] = [
                "User-Agent": userAgent,
                "Accept-Language": "zh-CN,zh;q=0.9",
                "Referer": referer ?? config.referer
            ]
            if json {
                headers["Accept"] = "application/json, text/javascript, */*; q=0.01"
            }
            let own = Self.sameHost(requestUrl, config.baseUrl)
            if own {
                let cookieHeader = withLock {
                    cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
                }
                if !cookieHeader.isEmpty {
                    headers["Cookie"] = cookieHeader
                }
            }
            if family == "fav" {
                let authCookie = try await favAuthCookie()
                if !authCookie.isEmpty {
                    headers["Cookie"] = authCookie
                }
            }
            if method == "POST" {
                headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
                headers["Origin"] = config.baseUrl
                let currentCsrf = withLock { csrf }
                if own && !currentCsrf.isEmpty {
                    headers["X-CSRF-TOKEN"] = currentCsrf
                    headers["X-Requested-With"] = "XMLHttpRequest"
                }
            }

            let response: HTTPResponse
            if method == "POST" {
                let bodyData = Data((body ?? "").utf8)
                response = try await transport.post(targetURL, headers: headers, body: bodyData)
            } else {
                response = try await transport.get(targetURL, headers: headers)
            }

            if response.statusCode == 401 || response.statusCode == 403 {
                if family == "fav" && attempt == 0 {
                    Self.clearFavAuth()
                    continue
                }
            }
            guard (200..<300).contains(response.statusCode) else {
                throw Self.ioError("\(name) 请求失败 (HTTP \(response.statusCode))")
            }
            let finalUrl = response.finalURL?.absoluteString ?? targetURL.absoluteString
            if own && Self.sameHost(finalUrl, config.baseUrl) {
                if let setCookie = response.headerValue(for: "Set-Cookie") {
                    storeCookies(from: setCookie)
                }
            }
            let text = String(data: response.data, encoding: .utf8) ?? String(decoding: response.data, as: UTF8.self)
            return PublicHTTPResponse(body: text, url: finalUrl, statusCode: response.statusCode)
        }
        throw Self.ioError("喜漫登录会话失效")
    }

    private func storeCookies(from setCookieHeader: String) {
        withLock {
            for part in setCookieHeader.components(separatedBy: ",") {
                let firstSegment = part.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if let eq = firstSegment.firstIndex(of: "=") {
                    let k = String(firstSegment[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let v = String(firstSegment[firstSegment.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !k.isEmpty && !k.lowercased().contains("expires") {
                        cookies[k] = v
                    }
                }
            }
        }
    }

    private func favAuthCookie() async throws -> String {
        let endpoint = profile.authEndpoint
        guard !endpoint.isEmpty else { return "" }
        let now = Int64(Date().timeIntervalSince1970)
        let cached: String? = Self.withFavAuthLock {
            if !Self.favAuthCookieValue.isEmpty && now < Self.favAuthExpiresAt - 120 {
                return Self.favAuthCookieValue
            }
            return nil
        }
        if let cached { return cached }
        guard let url = URL(string: endpoint) else {
            throw Self.ioError("喜漫登录接口无效")
        }
        let response = try await transport.get(url, headers: [
            "Accept": "application/json",
            "User-Agent": userAgent
        ])
        guard (200..<300).contains(response.statusCode) else {
            throw Self.ioError("喜漫登录接口失败（HTTP \(response.statusCode)）")
        }
        guard response.data.count <= 64 * 1024,
              let text = String(data: response.data, encoding: .utf8),
              let data = try? PublicRelaxedJSON.parse(text) as? [String: Any] else {
            throw Self.ioError("喜漫登录接口响应无效")
        }
        let token = (data["token"] as? String) ?? ""
        var cookie = (data["cookie"] as? String) ?? ""
        let expires = (data["expiresAt"] as? NSNumber)?.int64Value ?? (now + 300)
        guard !token.isEmpty else {
            throw Self.ioError("喜漫登录接口未返回 token")
        }
        if cookie.isEmpty {
            cookie = "token=" + token
        }
        return Self.withFavAuthLock {
            Self.favAuthCookieValue = cookie
            Self.favAuthExpiresAt = max(now + 60, expires)
            return Self.favAuthCookieValue
        }
    }

    private static func clearFavAuth() {
        withFavAuthLock {
            favAuthCookieValue = ""
            favAuthExpiresAt = 0
        }
    }

    public static func favFreeUrl(_ url: String) -> String {
        guard !url.isEmpty else { return url }
        let hashIdx = url.firstIndex(of: "#")
        let fragment = hashIdx.map { String(url[$0...]) } ?? ""
        let raw = hashIdx.map { String(url[..<$0]) } ?? url
        guard let queryIdx = raw.firstIndex(of: "?") else {
            return raw + "?free=1" + fragment
        }
        let base = String(raw[..<queryIdx])
        let query = String(raw[raw.index(after: queryIdx)...])
        var kept: [String] = []
        for item in query.components(separatedBy: "&") where !item.isEmpty {
            let key: String
            if let eq = item.firstIndex(of: "=") {
                key = String(item[..<eq])
            } else {
                key = item
            }
            if key.caseInsensitiveCompare("free") == .orderedSame { continue }
            kept.append(item)
        }
        kept.append("free=1")
        return base + "?" + kept.joined(separator: "&") + fragment
    }

    static func sameHost(_ a: String, _ b: String) -> Bool {
        guard let ua = PublicSourceImages.parseLenientURL(a),
              let ub = PublicSourceImages.parseLenientURL(b),
              let ha = ua.host, let hb = ub.host else {
            return false
        }
        return ha.caseInsensitiveCompare(hb) == .orderedSame
    }

    private func absolute(_ pathOrUrl: String) -> String {
        PublicSourceImages.resolve(config.baseUrl, pathOrUrl)
    }

    private func path(_ template: String, page: Int, word: String) -> String {
        let p = max(1, page)
        let encodedWord = PublicSourceImages.formURLEncode(word).replacingOccurrences(of: "+", with: "%20")
        return template
            .replacingOccurrences(of: "{keyword}", with: encodedWord)
            .replacingOccurrences(of: "{page}", with: String(p))
            .replacingOccurrences(of: "{offset}", with: String((p - 1) * 12))
            .replacingOccurrences(of: "{lelePage}", with: p == 1 ? "" : "_\(p - 1)")
            .replacingOccurrences(of: "{empirePage}", with: p == 1 ? "" : "/index_\(p).html")
            .replacingOccurrences(of: "{mangaPage}", with: p == 1 ? "" : "/page\(p - 1).html")
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        if id == "mh360" { return try await mh360Category([:], page: page) }
        if family == "wd" { return try await wdCategory([:], page: page) }
        return try await listing(profile.latest, page: page)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard supportsSearch, !trimmed.isEmpty else { return [] }
        var url = absolute(path(profile.search, page: page, word: trimmed))
        if id == "mh360" && page > 1 {
            url = absolute(path("/index.php/search/{keyword}/{page}", page: page, word: trimmed))
        }
        let linkedSearch = id == "ycy" || id == "laiman"
        if linkedSearch && page > 1 {
            let key = "\(trimmed)\n\(page - 1)"
            if let nextUrl = withLock({ searchNextPages[key] }) {
                if nextUrl.isEmpty { return [] }
                url = nextUrl
            }
        }

        let r: PublicHTTPResponse
        if id == "dogemanga" {
            r = try await cursorPage(absolute("/?q=" + PublicSourceImages.formURLEncode(trimmed)), page: page)
        } else if family == "dm5" {
            r = try await request(url, method: "POST", body: "t=7&f=1&pageindex=\(max(1, page))&title=\(PublicSourceImages.formURLEncode(trimmed))", referer: config.referer, json: true)
        } else if id == "sisi" {
            r = try await request(url, method: "POST", body: "action=GetWapList&_id=listbody&pagesize=12&order=1&classid1=0&url=%2Fstatics%2Fqingtiancms.ashx&page=\(page)&key=\(PublicSourceImages.formURLEncode(trimmed))", referer: config.referer, json: false)
        } else if family == "mumu" {
            let home = try await request(absolute("/"))
            let token = PublicHTMLDocument.parse(home.body, baseUri: home.url).selectFirst("meta[name=csrf-token]")?.attr("content") ?? ""
            guard !token.isEmpty else {
                throw Self.ioError("匿名搜索会话未建立")
            }
            withLock { csrf = token }
            r = try await request(url, method: "POST", body: "title=\(PublicSourceImages.formURLEncode(trimmed))&page=\(page)", referer: config.referer, json: true)
        } else if family == "empire" {
            let firstResp = try await request(url)
            if page > 1 {
                let next = searchPageLink(firstResp, page: page)
                if next.isEmpty { return [] }
                r = try await request(next, referer: firstResp.url)
            } else {
                r = firstResp
            }
        } else {
            r = try await request(url)
        }

        if id == "sisi" && r.body.trimmingCharacters(in: .whitespacesAndNewlines) == "{err!}" {
            return []
        }
        if r.body.contains("搜索繁忙") {
            throw Self.ioError("站点搜索繁忙，请稍后重试")
        }
        if linkedSearch {
            let doc = PublicHTMLDocument.parse(r.body, baseUri: r.url)
            let next = doc.selectFirst("a:matchesOwn(下一页|下一頁|Next)")
            var target = next?.absUrl("href") ?? ""
            let first = absolute(path(profile.search, page: 1, word: trimmed))
            if !target.isEmpty {
                let decoded = PublicSourceImages.formURLDecode(target).replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
                let firstDecoded = PublicSourceImages.formURLDecode(first).replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
                let firstWithoutOne = firstDecoded.replacingOccurrences(of: #"/1$"#, with: "", options: .regularExpression)
                if decoded == firstDecoded || decoded == firstWithoutOne || !Self.sameHost(target, first) {
                    target = ""
                }
            }
            withLock {
                searchNextPages["\(trimmed)\n\(page)"] = target
                if searchNextPages.count > 64 { searchNextPages.removeAll() }
            }
        }

        var result = try cards(r.body, r.url)
        if family == "dongman" || family == "mumu" {
            let offset = (max(1, page) - 1) * 30
            if offset >= result.count { return [] }
            return Array(result[offset..<min(offset + 30, result.count)])
        }

        withLock {
            if page <= 1 {
                let ids = Set(result.map(\.comicId))
                firstSearchPages[trimmed] = ids
                firstSearchOrder.removeAll { $0 == trimmed }
                firstSearchOrder.append(trimmed)
                while firstSearchOrder.count > 16 {
                    let old = firstSearchOrder.removeFirst()
                    firstSearchPages.removeValue(forKey: old)
                }
            } else if let previous = firstSearchPages[trimmed] {
                result = result.filter { !previous.contains($0.comicId) }
            }
        }
        return result
    }

    private func cursorPage(_ initial: String, page: Int) async throws -> PublicHTTPResponse {
        let targetPage = max(1, page)
        let key = "\(initial)#\(targetPage)"
        if let cachedUrl = withLock({ cursorPages[key] }) {
            return try await request(cachedUrl)
        }
        var response = try await request(initial)
        if targetPage > 1 {
            for current in 1..<targetPage {
                let doc = PublicHTMLDocument.parse(response.body, baseUri: response.url)
                guard let next = doc.selectFirst("a:matchesOwn(下一頁|下一页|Next)") else {
                    return PublicHTTPResponse(body: "<html></html>", url: initial, statusCode: 200)
                }
                let url = next.absUrl("href")
                guard Self.sameHost(url, initial) else {
                    throw Self.ioError("列表分页来源异常")
                }
                withLock { cursorPages["\(initial)#\(current + 1)"] = url }
                response = try await request(url)
            }
        }
        let doc = PublicHTMLDocument.parse(response.body, baseUri: response.url)
        if let next = doc.selectFirst("a:matchesOwn(下一頁|下一页|Next)") {
            let nextUrl = next.absUrl("href")
            withLock {
                cursorPages["\(initial)#\(targetPage + 1)"] = nextUrl
                if cursorPages.count > 200 { cursorPages.removeAll() }
            }
        }
        return response
    }

    private func searchPageLink(_ r: PublicHTTPResponse, page: Int) -> String {
        let doc = PublicHTMLDocument.parse(r.body, baseUri: r.url)
        let targetParam = "page=\(page - 1)"
        for a in doc.select("a[href]") {
            let u = a.absUrl("href")
            if u.contains("searchid=") && (u.contains("\(targetParam)&") || u.hasSuffix(targetParam)) {
                return u
            }
        }
        return ""
    }

    private func listing(_ template: String, page: Int) async throws -> [ComicSummary] {
        let r: PublicHTTPResponse
        if family == "dm5" {
            let sort = PublicSourceImages.match(template, #"[?&]sort=(\d+)"#)
            var status = PublicSourceImages.match(template, #"[?&]status=(\d+)"#)
            var category = "0", tag = "0", area = "0"
            if !template.contains("dm5.ashx") {
                let html = try await request(absolute(template)).body
                category = try Self.numberVariable(html, "categoryid")
                tag = try Self.numberVariable(html, "tagid")
                area = try Self.numberVariable(html, "areaid")
                status = try Self.numberVariable(html, "status")
            }
            let statusVal = status.isEmpty ? "0" : status
            let sortVal = sort.isEmpty ? "10" : sort
            let postBody = "action=getclasscomics&pageindex=\(max(1, page))&pagesize=21&categoryid=\(category)&tagid=\(tag)&status=\(statusVal)&usergroup=0&pay=-1&areaid=\(area)&sort=\(sortVal)&iscopyright=0"
            r = try await request(absolute("/manhua-list/dm5.ashx"), method: "POST", body: postBody, referer: config.referer, json: true)
        } else if id == "dogemanga" {
            r = try await cursorPage(absolute(template), page: page)
        } else {
            r = try await request(absolute(path(template, page: page, word: "")))
        }
        let result = try cards(r.body, r.url)
        if !template.contains("{page}") && !template.contains("{offset}") && !template.contains("{empirePage}") && !template.contains("{lelePage}") && !template.contains("{mangaPage}") && family != "dm5" && id != "dogemanga" {
            let start = (max(1, page) - 1) * 30
            if start >= result.count { return [] }
            return Array(result[start..<min(start + 30, result.count)])
        }
        return result
    }

    private static func numberVariable(_ html: String, _ name: String) throws -> String {
        let value = PublicSourceImages.match(html, "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*['\"]?(\\d+)")
        guard !value.isEmpty else {
            throw ioError("分类参数已变化：\(name)")
        }
        return value
    }

    public func categories() async throws -> [String] {
        let groups = try await filterGroups()
        return groups.flatMap { $0.options.map(\.label) }
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        if id == "ttk" { return try await ttkFilterGroups() }
        if id == "laiman" { return await laimanFilterGroups() }
        if family == "fav" { return filterGroupsForType("all") }
        if let configuredGroups = profile.filterGroups {
            return configuredGroups
        }
        var opts: [SourceFilterOption] = [SourceFilterOption(label: "默认", value: "all")]
        for (idx, f) in profile.filters.enumerated() {
            opts.append(SourceFilterOption(label: f.label, value: String(idx)))
        }
        return [SourceFilterGroup(key: "region", label: "分类 / 栏目", options: opts)]
    }

    public func filterGroupsForType(_ type: String) -> [SourceFilterGroup] {
        let selected = Self.normalizeFavType(type)
        var groups: [SourceFilterGroup] = []
        groups.append(SourceFilterGroup(key: "type", label: "类型", options: [
            SourceFilterOption(label: "全部", value: "all"),
            SourceFilterOption(label: "少男漫画", value: "boy"),
            SourceFilterOption(label: "少女漫画", value: "girl"),
            SourceFilterOption(label: "绅士漫画", value: "r18"),
            SourceFilterOption(label: "图库", value: "picture")
        ]))
        groups.append(SourceFilterGroup(key: "origin", label: "地区", options: [
            SourceFilterOption(label: "全部", value: "all"),
            SourceFilterOption(label: "日本", value: "2"),
            SourceFilterOption(label: "韩国", value: "3"),
            SourceFilterOption(label: "大陆及港台", value: "1"),
            SourceFilterOption(label: "其它", value: "4")
        ]))
        groups.append(SourceFilterGroup(key: "finished", label: "状态", options: [
            SourceFilterOption(label: "全部", value: "all"),
            SourceFilterOption(label: "连载", value: "1"),
            SourceFilterOption(label: "完结", value: "2")
        ]))
        var tags: [SourceFilterOption] = [SourceFilterOption(label: "全部", value: "all")]
        if selected == "all" {
            for kind in ["boy", "girl", "r18", "picture"] {
                for row in Self.favTagRows(kind) {
                    tags.append(SourceFilterOption(label: "\(Self.favTypeLabel(kind)) · \(row.1)", value: "\(kind):\(row.0)"))
                }
            }
        } else {
            for row in Self.favTagRows(selected) {
                tags.append(SourceFilterOption(label: row.1, value: "\(selected):\(row.0)"))
            }
        }
        groups.append(SourceFilterGroup(key: "tag", label: "题材", options: tags))
        groups.append(SourceFilterGroup(key: "order", label: "排序", options: [
            SourceFilterOption(label: "更新时间", value: "latest"),
            SourceFilterOption(label: "人气推荐", value: "popular")
        ]))
        return groups
    }

    private static func normalizeFavType(_ type: String?) -> String {
        guard let type else { return "all" }
        return (type == "boy" || type == "girl" || type == "r18" || type == "picture") ? type : "all"
    }

    private static func favTypeLabel(_ type: String) -> String {
        switch type {
        case "boy": return "少男"
        case "girl": return "少女"
        case "r18": return "绅士"
        default: return "图库"
        }
    }

    private static func favTagRows(_ type: String) -> [(String, String)] {
        switch type {
        case "boy":
            return favRows("1","奇幻","4","冒险","7","异世界","36","爱情","5","鬼神","2","推理悬疑","3","热血","11","恐怖·惊悚","41","节操","34","校园","6","搞笑喜剧","42","科幻","40","后宫","32","格斗","9","运动竞技","88","穿越","80","动作","16","战争","39","音乐","112","轻小说","15","励志","13","武侠","35","短篇","89","修真","118","百合","79","剧情","12","美食家","10","历史","43","职场","45","性转换","83","伪娘","8","黑道","14","其他")
        case "girl":
            return favRows("17","恋爱","33","TL","19","BL","31","欢乐向","18","校园","21","百合","28","后宫·宮廷","44","轻小说","81","剧情","38","美食","26","职场","24","治愈","20","舞蹈音乐","25","性转换","82","伪娘","22","萌系","37","重生","27","生活日常","30","宠物","125","ABO","29","霸道总裁","23","古风","46","短篇","75","其他","129","NTR","131","扶他","122","异世界","132","被NTR")
        case "r18":
            return favRows("48","剧情向","47","无修正","110","同人","49","巨乳","68","制服·JK","52","口交","62","近亲·乱伦","50","熟女","93","伪娘","55","NTR","94","贫乳","108","束缚·捆绑","56","眼镜","63","3P·群交","104","丝袜","111","人外","65","辣妹","64","情趣内衣","78","浪漫爱情","60","兽耳","58","调教","90","百合","51","乳交","91","触手","95","妖精·魅魔","106","重口","109","兔女郎","59","黑肉","57","强暴","101","扶他","54","人妻","70","足交","97","处女","98","痴女","107","痴汉·丑男","61","性玩具","99","颜射","100","泳装","73","出汗","74","多毛","102","舔阴","67","双马尾","69","自慰","96","肛交","53","中出","133","修女","130","furry","72","排尿","128","倒乳头","123","AI生成","117","男娘","134","超乳","124","受孕","121","可爱","105","护士","126","催眠","71","潮吹","120","肉感女","127","女仆","115","双穴","66","长筒袜","119","正太","114","3D","103","露出","113","阿黑颜","116","yaoi")
        case "picture":
            return favRows("76","Cosplay","87","AI生成","85","CG画集","86","写真","77","OnlyFans")
        default:
            return []
        }
    }

    private static func favRows(_ values: String...) -> [(String, String)] {
        var rows: [(String, String)] = []
        var i = 0
        while i + 1 < values.count {
            rows.append((values[i], values[i + 1]))
            i += 2
        }
        return rows
    }

    private func laimanFilterGroups() async -> [SourceFilterGroup] {
        if let cached = withLock({ cachedLaimanFilters }) {
            return cached
        }
        var options: [SourceFilterOption] = [SourceFilterOption(label: "默认", value: "all")]
        var tagPaths = Set<String>()
        var staticTagOptions: [String: Int] = [:]
        for (i, filter) in profile.filters.enumerated() {
            options.append(SourceFilterOption(label: filter.label, value: String(i)))
            let tagPath = filter.path.replacingOccurrences(of: #"/page/\{page\}$"#, with: "", options: .regularExpression)
            if Self.fullMatch(tagPath, #"/category/tags/\d+"#) {
                tagPaths.insert(tagPath)
                staticTagOptions[tagPath] = options.count - 1
            }
        }
        var discovered = 0
        if let response = try? await request(absolute("/")) {
            let document = PublicHTMLDocument.parse(response.body, baseUri: response.url)
            for link in document.select(".home_container .home_browseBox a.home_browseItem[href]") {
                let href = link.absUrl("href")
                guard Self.sameHost(href, config.baseUrl) else { continue }
                let path = Self.urlPath(href)
                guard Self.fullMatch(path, #"/category/tags/\d+"#) else { continue }
                let linkText = link.text()
                if let existing = staticTagOptions[path] {
                    options[existing] = SourceFilterOption(label: linkText, value: String(existing - 1))
                    continue
                }
                if tagPaths.insert(path).inserted {
                    options.append(SourceFilterOption(label: linkText, value: path))
                    discovered += 1
                }
            }
        }
        let groups = [SourceFilterGroup(key: "region", label: "分类 / 栏目", options: options)]
        if discovered > 0 {
            withLock { cachedLaimanFilters = groups }
        }
        return groups
    }

    private func ttkFilterGroups() async throws -> [SourceFilterGroup] {
        var groups: [SourceFilterGroup] = []
        groups.append(SourceFilterGroup(key: "region", label: "地区", options: [
            SourceFilterOption(label: "全部", value: "all"),
            SourceFilterOption(label: "国产", value: "1"),
            SourceFilterOption(label: "日本", value: "2"),
            SourceFilterOption(label: "韩国", value: "3"),
            SourceFilterOption(label: "欧美", value: "4")
        ]))

        let response = try await request(absolute("/category/list/1"))
        let document = PublicHTMLDocument.parse(response.body, baseUri: response.url)
        for row in document.select(".category-box dl") {
            let label = Self.text(row, "dt span")
            let key = label == "标签" ? "tag" : label == "进度" ? "finish" : label == "排序" ? "order" : ""
            if key.isEmpty { continue }
            var options: [SourceFilterOption] = []
            if key != "order" {
                options.append(SourceFilterOption(label: "全部", value: "all"))
            }
            for link in row.select("dd a[href]") {
                let href = link.absUrl("href")
                var value: String
                if key == "tag" {
                    value = PublicSourceImages.match(href, #"/tags/(\d+)(?:/|$)"#)
                } else if key == "finish" {
                    value = PublicSourceImages.match(href, #"/finish/(\d+)(?:/|$)"#)
                } else {
                    value = PublicSourceImages.match(href, #"/order/([A-Za-z0-9_-]+)(?:/|$)"#)
                }
                if value.isEmpty {
                    if key == "order" { continue }
                    value = "all"
                }
                if !options.contains(where: { $0.value == value }) {
                    options.append(SourceFilterOption(label: link.text(), value: value))
                }
            }
            if options.count > 1 {
                groups.append(SourceFilterGroup(key: key, label: label, options: options))
            }
        }
        guard groups.count == 4 else {
            throw Self.ioError("分类筛选项解析不完整")
        }
        return groups
    }

    public func category(region: String?, state: String?, page: Int) async throws -> [ComicSummary] {
        if id == "mh360" {
            var filters: [String: String] = [:]
            if let region { filters["type"] = region }
            if let state { filters["finish"] = state }
            return try await mh360Category(filters, page: page)
        }
        if id == "ttk" {
            return try await category(filters: [
                "region": region ?? "all",
                "finish": state ?? "all"
            ], page: page)
        }
        if family == "fav" {
            return try await category(filters: [
                "type": region ?? "all",
                "tag": state ?? "all"
            ], page: page)
        }
        if family == "wd" {
            var filters: [String: String] = [:]
            if let region { filters["region"] = region }
            if let state { filters["tag"] = state }
            return try await wdCategory(filters, page: page)
        }
        if id == "ciyuan" {
            var filters: [String: String] = [:]
            if let region { filters["tag"] = region }
            return try await ciyuanCategory(filters, page: page)
        }
        if id == "dumanwu" {
            var filters: [String: String] = [:]
            if let region { filters["finish"] = region }
            if let state { filters["tag"] = state }
            return try await dumanwuCategory(filters, page: page)
        }
        if id == "laiman", let region, Self.fullMatch(region, #"/category/tags/\d+"#) {
            return try await listing(region + "/page/{page}", page: page)
        }
        var template = profile.latest
        if let region, Self.fullMatch(region, #"\d+"#), let n = Int(region), n >= 0 && n < profile.filters.count {
            template = profile.filters[n].path
        }
        return try await listing(template, page: page)
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        if id == "mh360" { return try await mh360Category(filters, page: page) }
        if family == "fav" { return try await favCategory(filters, page: page) }
        if family == "wd" { return try await wdCategory(filters, page: page) }
        if id == "ciyuan" { return try await ciyuanCategory(filters, page: page) }
        if id == "dumanwu" { return try await dumanwuCategory(filters, page: page) }
        if id != "ttk" {
            let region = filters["region"] ?? "all"
            let state = filters["state"] ?? "all"
            return try await category(region: region, state: state, page: page)
        }
        var region = filters["region"] ?? "all"
        var tag = filters["tag"] ?? "all"
        var finish = filters["finish"] ?? "all"
        var order = filters["order"] ?? "addtime"
        if !Self.fullMatch(region, "[1-4]") { region = "all" }
        if !Self.fullMatch(tag, #"\d+"#) { tag = "all" }
        if !Self.fullMatch(finish, #"\d+"#) { finish = "all" }
        if !Self.fullMatch(order, "[A-Za-z0-9_-]+") { order = "addtime" }
        var route = "/category"
        if region != "all" { route += "/list/\(region)" }
        if tag != "all" { route += "/tags/\(tag)" }
        if finish != "all" { route += "/finish/\(finish)" }
        route += "/order/\(order)/page/\(max(1, page))"
        return try await listing(route, page: 1)
    }

    private func wdCategory(_ filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var region = filters["region"] ?? "0"
        var tag = filters["tag"] ?? "0"
        if !Self.fullMatch(region, #"\d+"#) { region = "0" }
        if !Self.fullMatch(tag, #"\d+"#) { tag = "0" }
        let route = "/sort?category=\(region)&tag=\(tag)&page=\(max(1, page))"
        return try await listing(route, page: 1)
    }

    private func ciyuanCategory(_ filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let tag = filters["tag"] ?? "all"
        let route: String
        if Self.fullMatch(tag, #"\d+"#) {
            route = "/category/tags/\(tag)/page/\(max(1, page))"
        } else {
            route = "/category/page/\(max(1, page))"
        }
        return try await listing(route, page: 1)
    }

    private func dumanwuCategory(_ filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let finish = filters["finish"] ?? "all"
        let tag = filters["tag"] ?? "all"
        let region = filters["region"] ?? "all"
        var route = "/category"
        if Self.fullMatch(finish, #"\d+"#) { route += "/finish/\(finish)" }
        if Self.fullMatch(tag, #"\d+"#) { route += "/tags/\(tag)" }
        if Self.fullMatch(region, #"\d+"#) { route += "/list/\(region)" }
        route += "/page/\(max(1, page))"
        return try await listing(route, page: 1)
    }

    private func mh360Category(_ filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var route = "/index.php/category"
        let keys = ["type", "tag", "region", "finish"]
        let segments = ["list", "tags", "city", "finish"]
        for i in 0..<keys.count {
            if let value = filters[keys[i]], Self.fullMatch(value, #"\d+"#) {
                route += "/\(segments[i])/\(value)"
            }
        }
        if page > 1 {
            route += "/page/\(page)"
        }
        return try await listing(route, page: 1)
    }

    private func favCategory(_ filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var type = Self.normalizeFavType(filters["type"])
        var tag = filters["tag"] ?? "all"
        if tag.isEmpty { tag = "all" }
        let tagId: String
        if let sep = tag.firstIndex(of: ":"), sep > tag.startIndex {
            if type == "all" {
                type = Self.normalizeFavType(String(tag[..<sep]))
            }
            tagId = String(tag[tag.index(after: sep)...])
        } else {
            tagId = tag
        }
        var route = "/" + (type == "all" ? "boy" : type)
        var first = true
        func appendQuery(_ item: String) {
            route += (first ? "?" : "&") + item
            first = false
        }
        if let origin = filters["origin"], Self.fullMatch(origin, "[1-4]") {
            appendQuery("origin=\(origin)")
        }
        if let finished = filters["finished"], Self.fullMatch(finished, "[12]") {
            appendQuery("finished=\(finished)")
        }
        if Self.fullMatch(tagId, #"\d+"#) {
            appendQuery("tag=\(tagId)")
        }
        if filters["order"] == "popular" {
            appendQuery("sort=1")
        }
        if page > 1 {
            appendQuery("page=\(page)")
        }
        return try await listing(route, page: 1)
    }

    private func isDetail(_ href: String?) -> Bool {
        guard let href, !href.isEmpty else { return false }
        return Self.fullMatch(href, profile.detailPattern)
    }

    private func canonical(_ url: String) -> String {
        guard let u = PublicSourceImages.parseLenientURL(url) else { return "" }
        if family == "dongman" {
            let query = u.query ?? ""
            let number = PublicSourceImages.match(query, #"(?:^|&)(?:title_no|titleNo)=(\d+)"#)
            if !number.isEmpty {
                return "/episodeList?titleNo=\(number)"
            }
        }
        return Self.urlPath(url)
    }

    public func comicIdForUrl(_ url: String) -> String {
        "\(id):\(canonical(url))"
    }

    private func detailUrl(_ comicId: String) throws -> String {
        let p = Self.rawId(comicId, id)
        guard isDetail(p) else {
            throw Self.ioError("\(name) 作品 ID 无效")
        }
        return absolute(p)
    }

    private static func rawId(_ comicId: String, _ sourceId: String) -> String {
        let prefix = sourceId + ":"
        if comicId.hasPrefix(prefix) {
            return String(comicId.dropFirst(prefix.count))
        }
        return comicId
    }

    private static func text(_ parent: PublicHTMLElement, _ css: String) -> String {
        parent.selectFirst(css)?.text() ?? ""
    }

    private static func firstValue(_ item: [String: Any], _ keys: String...) -> String {
        for k in keys {
            if let v = item[k] {
                let s = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty && s != "null" && s != "<null>" {
                    return s
                }
            }
        }
        return ""
    }

    public func cards(_ body: String, _ base: String) throws -> [ComicSummary] {
        var order: [String] = []
        var result: [String: ComicSummary] = [:]
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            let parsed: Any
            do {
                parsed = try PublicRelaxedJSON.parse(trimmed)
            } catch {
                throw Self.ioError("作品 JSON 无效")
            }
            var list: [[String: Any]]? = parsed as? [[String: Any]]
            if list == nil, let root = parsed as? [String: Any] {
                list = (root["UpdateComicItems"] as? [[String: Any]]) ?? (root["data"] as? [[String: Any]])
            }
            guard let items = list else {
                throw Self.ioError("作品接口缺少列表")
            }
            for item in items {
                let title = Self.firstValue(item, "Title", "title", "name")
                var href = Self.firstValue(item, "Url", "url", "UrlKey")
                if family == "mumu" {
                    let itemId = Self.firstValue(item, "id")
                    href = "/detail/\(itemId).html"
                }
                if family == "dm5" && !href.hasPrefix("/") && !href.hasPrefix("http") {
                    href = "/" + (href.hasPrefix("manhua") ? href : "manhua-" + href) + "/"
                }
                let cover = Self.firstValue(item, "Pic", "ShowPicUrlB", "ShowConver", "ShowPicUrl", "cover", "pic")
                addCard(order: &order, out: &result, base: base, href: href, title: title, cover: cover, subtitle: "")
            }
            return order.compactMap { result[$0] }
        }

        let doc = PublicHTMLDocument.parse(body, baseUri: base)
        var containers = profile.cards.isEmpty ? [] : doc.select(profile.cards)
        if family == "dongman" && !doc.select(".card_wrap.search").isEmpty {
            containers = doc.select(".card_wrap.search .card_lst li")
        }
        for box in containers {
            for a in box.select("a[href]") {
                let href = a.absUrl("href")
                if !isDetail(canonical(href)) { continue }
                let image = box.selectFirst("img, mip-img")
                var title = Self.text(box, ".book-list-info-title, .manga-list-2-title, .manga-list-2-title a, .comic-title, .comic-name, .comic__title, .txtA, .title, .subj, .manga-names, .nmain_cl_tit, .cardtitle, .manga-title, .txt-ov, .MTagBookList_bookName, .BrowseList_bookName, .FeaturedList_bookName, h3, h4, h2")
                if title.isEmpty { title = a.attr("title") }
                if title.isEmpty, let image { title = image.attr("alt") }
                if title.isEmpty { title = a.text() }
                var cover = PublicSourceImages.imageAttribute(image)
                if cover.isEmpty, let style = box.selectFirst("[style*=url]") {
                    cover = PublicSourceImages.match(style.attr("style"), #"url\(['"]?([^)'"]+)"#)
                }
                addCard(order: &order, out: &result, base: base, href: href, title: title, cover: cover, subtitle: "")
                break
            }
        }
        if result.isEmpty {
            for a in doc.select("a[href]:has(img), a[href]:has(mip-img)") {
                let image = a.selectFirst("img, mip-img")
                var title = image?.attr("alt") ?? ""
                if title.isEmpty { title = a.attr("title") }
                if title.isEmpty { title = a.text() }
                addCard(order: &order, out: &result, base: base, href: a.absUrl("href"), title: title, cover: PublicSourceImages.imageAttribute(image), subtitle: "")
            }
        }
        return order.compactMap { result[$0] }
    }

    private func addCard(order: inout [String], out: inout [String: ComicSummary], base: String, href: String, title: String, cover: String, subtitle: String) {
        let url = PublicSourceImages.resolve(base, href)
        let path = canonical(url)
        let cleanTitle = PublicHTMLDocument.parse(title).text()
        guard Self.sameHost(url, config.baseUrl), isDetail(path), !cleanTitle.isEmpty else { return }
        let cid = "\(id):\(path)"
        let taggedCover = cover.isEmpty ? "" : PublicSourceImages.tag(PublicSourceImages.resolve(base, cover), id, url, -1)
        if out[cid] == nil {
            order.append(cid)
        }
        out[cid] = ComicSummary(sourceId: id, comicId: cid, title: cleanTitle, coverUrl: taggedCover, subtitle: subtitle, tags: [])
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let url = try detailUrl(comicId)
        let r = try await request(url)
        guard isDetail(canonical(r.url)) else {
            throw Self.ioError("作品页跳转异常")
        }
        let doc = PublicHTMLDocument.parse(r.body, baseUri: r.url)
        var title = Self.text(doc.root, ".vod-info .info h3 a, .ewave-vod-info .info h3 a, .detailTop .content .info .title, .detailTop .content .title, h1, h2.subj, .detail-info-title, .detail-main-info-title")
        if title.isEmpty {
            title = doc.selectFirst("meta[property=og:title]")?.attr("content") ?? ""
        }
        if id == "mh360" {
            title = Self.text(doc.root, "h1.comic-name, .comic-title")
        }
        if title.isEmpty {
            let docTitle = doc.title()
            title = docTitle.components(separatedBy: CharacterSet(charactersIn: "_|")).first ?? ""
        }

        var cover = id == "ttk" ? PublicSourceImages.imageAttribute(doc.selectFirst(".vod-info .pic img, .ewave-vod-info .pic img")) : ""
        if id == "mh360" {
            cover = PublicSourceImages.imageAttribute(doc.selectFirst(".de-info__cover img"))
            if cover.isEmpty, let backdrop = doc.selectFirst(".box-back[style]") {
                cover = PublicSourceImages.match(backdrop.attr("style"), #"url\(['"]?([^)'"]+)"#)
            }
        }
        if cover.isEmpty {
            cover = doc.selectFirst("meta[property=og:image]")?.attr("content") ?? ""
        }
        if cover.isEmpty {
            cover = PublicSourceImages.imageAttribute(doc.selectFirst(".dramaDetail_bookCover img, .detail-info-cover img, img.detail-info-cover, .detailTop img.cover, img.cover, .cover img, .comic-cover img, .book-cover img, .detail-main-cover img, .thumb img"))
        }
        let taggedCover = cover.isEmpty ? "" : PublicSourceImages.tag(PublicSourceImages.resolve(url, cover), id, url, -1)
        let summary = ComicSummary(sourceId: id, comicId: comicIdForUrl(url), title: title, coverUrl: taggedCover, subtitle: "", tags: [])

        var description: String
        if id == "mh360" {
            description = Self.text(doc.root, ".comic-intro > .intro-total")
            if description.isEmpty {
                description = Self.text(doc.root, ".detail-intro > .comic-intro, .comic-intro > .intro")
            }
        } else {
            description = Self.text(doc.root, "#mangaDescription, .description, .detail-info-content, .detail-content, .detailContent > p, .comic-description, .summary")
        }
        if description.isEmpty {
            description = doc.selectFirst("meta[name=description]")?.attr("content") ?? ""
        }
        let author = Self.text(doc.root, "#mangaAuthor, .author")
        let status = Self.text(doc.root, ".status")
        return ComicDetail(summary: summary, author: author, status: status, description: description, latestChapter: "", chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let url = try detailUrl(comicId)
        if family == "wd" { return try await wdChapters(url) }
        var order: [String] = []
        var result: [String: Chapter] = [:]
        var pending: [Int] = [1]
        var visited = Set<Int>()

        while !pending.isEmpty {
            pending.sort()
            let page = pending.removeFirst()
            if !visited.insert(page).inserted { continue }
            if visited.count > 100 {
                throw Self.ioError("目录超过 100 页，请检查站点")
            }
            let pageUrl = url + (page > 1 ? (url.contains("?") ? "&" : "?") + "p=\(page)" : "")
            let r = try await request(pageUrl)
            guard canonical(r.url) == canonical(url) else {
                throw Self.ioError("目录分页跳转到其他作品")
            }
            let doc = PublicHTMLDocument.parse(r.body, baseUri: r.url)
            let before = result.count
            if id == "favcomic" {
                return try favChapters(doc, r.url)
            }
            var chapterLinks = doc.select(profile.catalog)
            if family == "empire" {
                for a in doc.select("a[href]") {
                    if a.absUrl("href") == url + "chapter0.html" {
                        chapterLinks.append(a)
                    }
                }
            }
            for a in chapterLinks {
                let href = a.hasAttr("value") ? a.attr("value") : a.attr("href")
                if href.isEmpty || href.hasPrefix("javascript:") || href.hasPrefix("#") { continue }
                let u = PublicSourceImages.resolve(r.url, href)
                if !Self.sameHost(u, url) || u == url { continue }
                if family == "empire" && !Self.fullMatch(u, NSRegularExpression.escapedPattern(for: url) + #"chapter[^/?]+\.html"#) { continue }
                if family == "fav" && !Self.isFavFreeChapter(a.text()) { continue }
                if family == "dongman" {
                    let expectedTitleNo = PublicSourceImages.match(url, #"(?:title_no|titleNo)=(\d+)"#)
                    if !u.contains("/viewer?") || !u.contains("title_no=\(expectedTitleNo)") { continue }
                }
                var title = Self.text(a, ".subj, .title, .ncp3li_title, .detail-list-2-info-title, .detail-chapters-list-item-bookName")
                if title.isEmpty { title = a.text() }
                if title.isEmpty { continue }
                if family == "empire" && Self.fullMatch(title, #".*(?:开始阅读|開始閱讀|立即阅读).*"#) {
                    title = "起始章"
                }
                if Self.fullMatch(title, #".*(?:展开|收起|倒序|正序|全部章节).*"#) { continue }
                if result[u] == nil || result[u]?.title == "起始章" {
                    if result[u] == nil { order.append(u) }
                    result[u] = Chapter(chapterId: Self.chapterKey(u), title: title, url: u, sectionSlot: 0, chapterSlot: result.count)
                }
            }
            if page > 1 && result.count == before {
                throw Self.ioError("目录分页重复，拒绝返回不完整目录")
            }
            if family == "empire" {
                for a in doc.select("a[href]") {
                    let u = a.absUrl("href")
                    if Self.sameHost(u, url) && canonical(u) == canonical(url) {
                        if let n = Int(PublicSourceImages.match(u, #"[?&]p=(\d+)"#)), !visited.contains(n), !pending.contains(n) {
                            pending.append(n)
                        }
                    }
                }
            }
        }

        var list = order.compactMap { result[$0] }
        guard !list.isEmpty else {
            throw Self.ioError("没有取得本书可读章节")
        }
        if family == "empire" {
            list.sort { Self.empireIndex($0.url) < Self.empireIndex($1.url) }
            return Self.slots(list)
        }
        let first = Self.chapterNumber(list[0].title)
        let last = Self.chapterNumber(list[list.count - 1].title)
        if (first >= 0 && last >= 0 && first > last) || ((first < 0 || last < 0) && profile.reverseCatalog) {
            list.reverse()
        }
        return Self.slots(list)
    }

    private static func chapterNumber(_ title: String) -> Double {
        let n = PublicSourceImages.match(title, #"(?:第)?(\d+(?:\.\d+)?)\s*[话話回卷集章]"#)
        return Double(n) ?? -1
    }

    private static func isFavFreeChapter(_ text: String) -> Bool {
        Self.fullMatch(text, #"[\s\S]*[￥¥]\s*0(?:\.0+)?(?:\s|$)[\s\S]*"#)
    }

    private func favChapters(_ doc: PublicHTMLDocument, _ base: String) throws -> [Chapter] {
        var htmlOrder: [String] = []
        var htmlMap: [String: Chapter] = [:]
        var structuredOrder: [String] = []
        var structuredMap: [String: Chapter] = [:]
        var paid = Set<String>()

        for link in doc.select(profile.catalog) {
            let url = favChapterUrl(base, link.attr("href"))
            if url.isEmpty { continue }
            if Self.favPaidPrice(link.text()) {
                paid.insert(url)
                continue
            }
            var title = Self.text(link, ".title")
            if title.isEmpty { title = link.text() }
            if !title.isEmpty {
                if htmlMap[url] == nil { htmlOrder.append(url) }
                htmlMap[url] = Chapter(chapterId: Self.chapterKey(url), title: title, url: url, sectionSlot: 0, chapterSlot: htmlMap.count)
            }
        }

        for script in doc.select("script[type=application/ld+json]") {
            guard let value = try? PublicRelaxedJSON.parse(script.data()) else { continue }
            collectFavJsonLdChapters(value, base: base, order: &structuredOrder, result: &structuredMap, paid: &paid)
        }

        for url in htmlOrder {
            if structuredMap[url] == nil, let ch = htmlMap[url] {
                structuredOrder.append(url)
                structuredMap[url] = ch
            }
        }
        for url in paid {
            structuredMap.removeValue(forKey: url)
        }
        let finalList = structuredOrder.compactMap { structuredMap[$0] }
        guard !finalList.isEmpty else {
            throw Self.ioError("没有取得本书可读章节")
        }
        return Self.slots(finalList)
    }

    private static func favPaidPrice(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"[￥¥]\s*(\d+(?:\.\d+)?)"#, options: []) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        for m in regex.matches(in: text, options: [], range: range) {
            if let r = Range(m.range(at: 1), in: text),
               let val = Decimal(string: String(text[r])),
               val != 0 {
                return true
            }
        }
        return false
    }

    private func favChapterUrl(_ base: String, _ href: String) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let url = PublicSourceImages.resolve(base, trimmed)
        guard Self.sameHost(url, base),
              let parsed = PublicSourceImages.parseLenientURL(url),
              let scheme = parsed.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return ""
        }
        let path = Self.urlPath(url)
        guard Self.fullMatch(path, #"/comic/chapter/\d+"#) else { return "" }
        return absolute(path)
    }

    private func collectFavJsonLdChapters(_ value: Any?, base: String, order: inout [String], result: inout [String: Chapter], paid: inout Set<String>) {
        guard let value else { return }
        if let array = value as? [Any] {
            for item in array {
                collectFavJsonLdChapters(item, base: base, order: &order, result: &result, paid: &paid)
            }
            return
        }
        guard let object = value as? [String: Any] else { return }
        collectFavJsonLdChapters(object["@graph"], base: base, order: &order, result: &result, paid: &paid)
        guard let typeStr = object["@type"] as? String, typeStr.caseInsensitiveCompare("Book") == .orderedSame else {
            return
        }
        let bookUrl = ((object["url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !bookUrl.isEmpty {
            let resolved = PublicSourceImages.resolve(base, bookUrl)
            if !Self.sameHost(resolved, base) || canonical(resolved) != canonical(base) {
                return
            }
        }
        guard let parts = object["hasPart"] else { return }
        if let partArray = parts as? [[String: Any]] {
            for p in partArray {
                addFavJsonLdPart(p, base: base, order: &order, result: &result, paid: &paid)
            }
        } else if let partObj = parts as? [String: Any] {
            addFavJsonLdPart(partObj, base: base, order: &order, result: &result, paid: &paid)
        }
    }

    private func addFavJsonLdPart(_ part: [String: Any], base: String, order: inout [String], result: inout [String: Chapter], paid: inout Set<String>) {
        let rawUrl = (part["url"] as? String) ?? ""
        let url = favChapterUrl(base, rawUrl)
        let title = ((part["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !title.isEmpty else { return }
        var price = ""
        if let offers = part["offers"] as? [String: Any], let pVal = offers["price"] {
            price = String(describing: pVal).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !price.isEmpty {
            guard let dec = Decimal(string: price), dec == 0 else {
                paid.insert(url)
                return
            }
        }
        if result[url] == nil {
            order.append(url)
            result[url] = Chapter(chapterId: Self.chapterKey(url), title: title, url: url, sectionSlot: 0, chapterSlot: result.count)
        }
    }

    private static func empireIndex(_ url: String) -> Int {
        let n = PublicSourceImages.match(url, #"/chapter(\d+)\.html$"#)
        return Int(n) ?? Int.max
    }

    private func wdChapters(_ url: String) async throws -> [Chapter] {
        let postUrl = url.replacingOccurrences(of: #"\.html$"#, with: "", options: .regularExpression)
        let r = try await request(postUrl, method: "POST", body: "form=form", referer: url, json: true)
        guard let root = try? PublicRelaxedJSON.parse(r.body) as? [String: Any] else {
            throw Self.ioError("完整目录格式错误")
        }
        let code = (root["code"] as? NSNumber)?.intValue ?? -1
        guard code == 0 else {
            throw Self.ioError("完整目录接口失败")
        }
        guard let dataObj = root["data"] as? [String: Any],
              let list = dataObj["chapters"] as? [[String: Any]] else {
            throw Self.ioError("完整目录格式错误")
        }
        var out: [Chapter] = []
        var seen = Set<String>()
        for (i, c) in list.enumerated() {
            let cid = Self.firstValue(c, "id")
            let book = Self.firstValue(c, "contentId")
            let title = Self.firstValue(c, "chapterName")
            guard Self.fullMatch(cid, #"\d+"#), Self.fullMatch(book, #"\d+"#) else {
                throw Self.ioError("目录 ID 无效")
            }
            if seen.insert(cid).inserted {
                out.append(Chapter(chapterId: cid, title: title, url: absolute("/chapter/\(book)-\(cid).html"), sectionSlot: 0, chapterSlot: i))
            }
        }
        guard !out.isEmpty else {
            throw Self.ioError("目录为空")
        }
        out.reverse()
        return Self.slots(out)
    }

    private static func slots(_ list: [Chapter]) -> [Chapter] {
        list.enumerated().map { idx, c in
            Chapter(chapterId: c.chapterId, title: c.title, url: c.url, sectionSlot: 0, chapterSlot: idx)
        }
    }

    private static func chapterKey(_ url: String) -> String {
        let path = urlPath(url)
        guard !path.isEmpty else { return url }
        if let u = PublicSourceImages.parseLenientURL(url), let q = u.query, !q.isEmpty {
            return "\(path)?\(q)"
        }
        return path
    }

    public func chapter(url chapterUrl: String) async throws -> ChapterPage {
        guard Self.sameHost(chapterUrl, config.baseUrl) else {
            throw Self.ioError("章节来源不匹配")
        }
        var images: [String] = []
        var next = chapterUrl
        var title = ""
        var visited = Set<String>()
        while !next.isEmpty {
            if !visited.insert(next).inserted || visited.count > 100 {
                throw Self.ioError("正文分页循环")
            }
            let r = try await request(next, referer: chapterUrl)
            guard Self.urlPath(r.url) == Self.urlPath(next) else {
                throw Self.ioError("章节跳转异常")
            }
            let part = try PublicSourceImages.extract(r.body, r.url, profile)
            guard !part.isEmpty else {
                throw Self.ioError("章节未返回正文图片")
            }
            images.append(contentsOf: part)
            let doc = PublicHTMLDocument.parse(r.body, baseUri: r.url)
            if title.isEmpty {
                title = doc.title()
            }
            next = ""
            if profile.readerPagination {
                let stem = chapterUrl.replacingOccurrences(of: #"(?:_\d+)?\.html$"#, with: "", options: .regularExpression)
                let pattern = NSRegularExpression.escapedPattern(for: stem) + #"_\d+\.html"#
                var best = Int.max
                for a in doc.select("a[href]") {
                    let u = a.absUrl("href")
                    if Self.fullMatch(u, pattern) && !visited.contains(u) {
                        if let n = Int(PublicSourceImages.match(u, #"_(\d+)\.html$"#)), n < best {
                            next = u
                            best = n
                        }
                    }
                }
            }
        }

        var deduped: [String] = []
        var seenImg = Set<String>()
        for img in images where seenImg.insert(img).inserted {
            deduped.append(img)
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        withLock {
            imageLists[chapterUrl] = CachedChapter(urls: deduped, at: now)
            imageListOrder.removeAll { $0 == chapterUrl }
            imageListOrder.append(chapterUrl)
            while imageListOrder.count > 16 {
                let old = imageListOrder.removeFirst()
                imageLists.removeValue(forKey: old)
            }
        }
        let tagged = deduped.enumerated().map { idx, u in
            PublicSourceImages.tag(u, id, chapterUrl, idx)
        }
        return ChapterPage(chapterId: chapterUrl, title: title, nextPageUrl: "", imageUrls: tagged)
    }

    public func resolveImageUrl(_ tagged: String, force: Bool) async throws -> String {
        let m = PublicSourceImages.metadata(tagged)
        guard m.count == 3, m[0] == id, let index = Int(m[2]), index >= 0 else {
            return PublicSourceImages.strip(tagged)
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var cached = withLock { imageLists[m[1]] }
        if force || cached == nil || now - cached!.at > 180_000 {
            _ = try await chapter(url: m[1])
            cached = withLock { imageLists[m[1]] }
        }
        guard let validCached = cached, index < validCached.urls.count else {
            throw Self.ioError("章节页数变更，请重新打开章节")
        }
        return validCached.urls[index]
    }

    static func urlPath(_ urlString: String) -> String {
        guard let schemeRange = urlString.range(of: "://") else {
            let noFrag = urlString.components(separatedBy: "#")[0]
            return noFrag.components(separatedBy: "?")[0]
        }
        let afterScheme = urlString[schemeRange.upperBound...]
        let noFrag = afterScheme.components(separatedBy: "#")[0]
        let noQuery = noFrag.components(separatedBy: "?")[0]
        guard let slashIdx = noQuery.firstIndex(of: "/") else {
            return ""
        }
        return String(noQuery[slashIdx...])
    }

    static func fullMatch(_ text: String, _ pattern: String) -> Bool {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))$", options: [.dotMatchesLineSeparators]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func ioError(_ message: String) -> NSError {
        NSError(domain: "PublicComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
