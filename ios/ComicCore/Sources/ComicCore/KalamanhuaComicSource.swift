import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Kalamanhua's public HTML protocol. Never evaluates page scripts or combines different chapter lines.
open class KalamanhuaComicSource: ComicSource, @unchecked Sendable {
    public static let imageOrigin = "https://image.kalaimg.top"
    private static let bodyLimit = 4 * 1024 * 1024

    public let config: SourceConfigItem
    public let id: String
    public let name: String
    public let referer: String
    public var supportsSearch: Bool { true }

    private let transport: any HTTPTransport
    public var requestOverride: ((_ url: String, _ method: String, _ body: String?, _ referer: String?, _ json: Bool) async throws -> PublicHTTPResponse)?
    public var fetchPageOverride: ((_ url: String, _ referer: String?, _ cookies: [String: String]) async throws -> PublicHTTPResponse)?

    private let sessionLock = NSLock()
    private var sessions: [String: [String: String]] = [:]

    private let imageLock = NSLock()
    private var images: [String: ImageList] = [:]
    private var imageOrder: [String] = []

    private let filterLock = NSLock()
    private var cachedFilters: [SourceFilterGroup]?

    private let moreLock = NSLock()
    private var lastListingMore: Bool = false

    private struct ImageList {
        let urls: [String]
        let at: Int64
    }

    public static func defaultConfig(enabled: Bool = true) -> SourceConfigItem {
        SourceConfigItem(
            id: "kalamanhua",
            name: "卡拉漫画",
            domain: "www.kalamanhua.com",
            baseUrl: "https://www.kalamanhua.com",
            referer: "https://www.kalamanhua.com/",
            latestPath: "",
            searchPath: "",
            categoryPath: "",
            detailPath: "",
            enabled: enabled,
            routes: nil,
            filters: nil
        )
    }

    public init(
        config: SourceConfigItem = KalamanhuaComicSource.defaultConfig(),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 22)
    ) {
        self.config = config
        self.id = config.id.isEmpty ? "kalamanhua" : config.id
        self.name = config.name.isEmpty ? "卡拉漫画" : config.name
        self.referer = config.referer.isEmpty ? "https://www.kalamanhua.com/" : config.referer
        self.transport = transport
    }

    public func userAgent() -> String {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    }

    public func absolute(_ pathOrUrl: String) -> String {
        PublicSourceImages.resolve(config.baseUrl, pathOrUrl)
    }

    open func request(_ url: String, method: String = "GET", body: String? = nil, referer: String? = nil, json: Bool = false) async throws -> PublicHTTPResponse {
        if let override = requestOverride {
            return try await override(url, method, body, referer, json)
        }
        guard method == "GET" else {
            throw Self.ioError("卡拉漫画不支持此请求")
        }
        var current = url
        for _ in 0..<3 {
            try Task.checkCancellation()
            guard let currentURL = URL(string: current), let host = currentURL.host else {
                throw Self.ioError("卡拉漫画返回了不支持的页面地址")
            }
            let cookies = getSessionCookies(for: host)
            let response = try await fetchPage(current, referer: referer, cookies: cookies)
            try Task.checkCancellation()

            let imageHost: Bool
            if let targetHost = URL(string: Self.imageOrigin)?.host {
                imageHost = targetHost.caseInsensitiveCompare(host) == .orderedSame
            } else {
                imageHost = false
            }

            let token: String
            if imageHost {
                token = PublicSourceImages.match(response.body, #"var\s+token\s*=\s*['"]([A-Za-z0-9_-]{8,256})['"]"#)
            } else {
                token = PublicSourceImages.match(response.body, #"k\s*=\s*['"]([a-fA-F0-9]{8,128})['"]"#)
            }

            if !token.isEmpty && response.body.contains("omo_token") {
                setSessionCookie(token, forKey: "omo_token", host: host)
                if imageHost {
                    current = Self.withVerification(url, token: token)
                }
                continue
            }

            if response.statusCode < 200 || response.statusCode >= 300 {
                throw Self.ioError("卡拉漫画请求失败（HTTP \(response.statusCode)），请重试")
            }
            if response.body.contains("cf-chl-")
                || response.body.contains("Just a moment...")
                || response.body.contains("Checking your browser")
                || (response.body.contains("cf_verify") && response.body.contains("var token")) {
                throw Self.ioError("卡拉漫画验证未通过，请稍后重试")
            }
            return response
        }
        throw Self.ioError("卡拉漫画验证未通过，请稍后重试")
    }

    open func fetchPage(_ url: String, referer: String?, cookies: [String: String]) async throws -> PublicHTTPResponse {
        if let override = fetchPageOverride {
            return try await override(url, referer, cookies)
        }
        var current = url
        var currentCookies = cookies
        for _ in 0..<5 {
            try Task.checkCancellation()
            guard let target = URL(string: current),
                  target.scheme?.lowercased() == "https",
                  let host = target.host,
                  allowedHost(host) else {
                throw Self.ioError("卡拉漫画返回了不支持的页面地址")
            }
            var headers: [String: String] = [
                "User-Agent": userAgent(),
                "Accept-Language": "zh-CN,zh;q=0.9"
            ]
            if let referer, !referer.isEmpty {
                headers["Referer"] = referer
            }
            if !currentCookies.isEmpty {
                headers["Cookie"] = currentCookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            }

            let response = try await transport.get(target, headers: headers)
            if let setCookie = response.headerValue(for: "Set-Cookie") {
                storeCookies(from: setCookie, host: host)
            }
            let status = response.statusCode
            if status >= 300 && status < 400 {
                guard let location = response.headerValue(for: "Location") else {
                    throw Self.ioError("卡拉漫画跳转地址缺失")
                }
                guard let next = URL(string: location, relativeTo: target)?.absoluteURL else {
                    throw Self.ioError("卡拉漫画跳转地址无效")
                }
                if let nextHost = next.host {
                    currentCookies = getSessionCookies(for: nextHost)
                }
                current = next.absoluteString
                continue
            }
            if response.data.count >= Self.bodyLimit {
                throw Self.ioError("卡拉漫画响应过大")
            }
            let text = String(data: response.data, encoding: .utf8) ?? String(decoding: response.data, as: UTF8.self)
            return PublicHTTPResponse(body: text, url: current, statusCode: status)
        }
        throw Self.ioError("卡拉漫画跳转次数过多")
    }

    public func get(_ url: String, referer: String? = nil) async throws -> PublicHTTPResponse {
        try await request(url, method: "GET", body: nil, referer: referer, json: false)
    }

    private func allowedHost(_ host: String) -> Bool {
        guard let baseHost = URL(string: config.baseUrl)?.host,
              let imageHost = URL(string: Self.imageOrigin)?.host else {
            return false
        }
        return host.caseInsensitiveCompare(baseHost) == .orderedSame || host.caseInsensitiveCompare(imageHost) == .orderedSame
    }

    public static func withVerification(_ url: String, token: String) -> String {
        guard let parsed = URL(string: url) else { return url }
        let basePart = url.components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
        var keptParams: [String] = []
        if let query = parsed.query {
            for entry in query.components(separatedBy: "&") where !entry.isEmpty {
                if !entry.hasPrefix("cf_verify=") {
                    keptParams.append(entry)
                }
            }
        }
        keptParams.append("cf_verify=" + PublicSourceImages.formURLEncode(token))
        return basePart + "?" + keptParams.joined(separator: "&")
    }

    private static func pathPart(_ value: String) -> String {
        PublicSourceImages.formURLEncode(value).replacingOccurrences(of: "+", with: "%20")
    }

    public static func categoryPath(filters: [String: String], page: Int) throws -> String {
        let region = value(filters, key: "region", fallback: "All")
        let state = value(filters, key: "state", fallback: "")
        let type = value(filters, key: "type", fallback: "")
        let order = value(filters, key: "order", fallback: "time")

        let allowedRegions = ["All", "Kc", "Jc", "Cc", "Ec", "Oc"]
        guard allowedRegions.contains(region) else {
            throw ioError("地区筛选无效")
        }
        let allowedOrders = ["time", "hits", "score"]
        guard allowedOrders.contains(order) else {
            throw ioError("排序筛选无效")
        }
        return "/type/\(region)-\(pathPart(state))-\(pathPart(type))---/by/\(order)\(page > 1 ? "/page/\(page)" : "").html"
    }

    private static func value(_ filters: [String: String]?, key: String, fallback: String) -> String {
        guard let filters, let v = filters[key], !v.isEmpty, v.lowercased() != "all" else {
            return fallback
        }
        return v
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        try await category(filters: [:], page: page)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let p = max(1, page)
        let pageSegment = p > 1 ? "page/\(p)/" : ""
        let route = "/search/\(pageSegment)wd/\(Self.pathPart(trimmed)).html"
        return try await listing(absolute(route), page: p)
    }

    public func hasMoreCategoryPage(_ results: [ComicSummary]) -> Bool {
        moreLock.lock()
        defer { moreLock.unlock() }
        return lastListingMore
    }

    public func categories() async throws -> [String] {
        var result: [String] = []
        for group in try await filterGroups() where group.key == "type" {
            for option in group.options {
                result.append(option.label)
            }
        }
        return result
    }

    private static func group(_ key: String, _ label: String, _ pairs: String...) -> SourceFilterGroup {
        var options: [SourceFilterOption] = []
        var i = 0
        while i + 1 < pairs.count {
            options.append(SourceFilterOption(label: pairs[i], value: pairs[i + 1]))
            i += 2
        }
        return SourceFilterGroup(key: key, label: label, options: options)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        filterLock.lock()
        if let cached = cachedFilters {
            filterLock.unlock()
            return cached
        }
        filterLock.unlock()

        let r = try await get(absolute("/type/26-----.html"))
        let d = PublicHTMLDocument.parse(r.body, baseUri: r.url)
        var types: [SourceFilterOption] = [SourceFilterOption(label: "全部", value: "all")]
        var seen = Set<String>(["all"])

        for list in d.select("ul.clearfix") {
            let first = list.selectFirst("li")
            guard let first, first.text().contains("类型") else { continue }
            for a in list.select("a[href]") {
                let rawValue = PublicSourceImages.match(a.attr("href"), #"/type/[^/]*?--(.*?)---(?:[./]|$)"#)
                let decoded = rawValue.removingPercentEncoding ?? rawValue
                let label = a.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty && seen.insert(decoded).inserted {
                    types.append(SourceFilterOption(label: label, value: decoded))
                }
            }
        }
        guard types.count >= 2 else {
            throw Self.ioError("卡拉漫画分类未解析成功，请重试")
        }
        let groups: [SourceFilterGroup] = [
            Self.group("region", "地区", "全部", "all", "韩漫", "Kc", "日漫", "Jc", "国漫", "Cc", "欧美", "Ec", "其他", "Oc"),
            SourceFilterGroup(key: "type", label: "类型", options: types),
            Self.group("state", "状态", "全部", "all", "连载中", "连载中", "完结", "完结"),
            Self.group("order", "排序", "更新", "time", "人气", "hits", "评分", "score")
        ]

        filterLock.lock()
        cachedFilters = groups
        filterLock.unlock()
        return groups
    }

    public func category(region: String, state: String, page: Int) async throws -> [ComicSummary] {
        try await category(filters: ["region": region, "state": state], page: page)
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let path = try Self.categoryPath(filters: filters, page: max(1, page))
        return try await listing(absolute(path), page: max(1, page))
    }

    private func listing(_ url: String, page: Int) async throws -> [ComicSummary] {
        let r = try await get(url)
        let d = PublicHTMLDocument.parse(r.body, baseUri: r.url)
        guard let primaryList = d.selectFirst(".stui-vodlist") else {
            throw Self.ioError("卡拉漫画列表解析失败，请重试")
        }
        let pageItemText = d.selectFirst(".stui-page__item")?.text() ?? ""
        let totals = PublicSourceImages.match(pageItemText, #"(\d+)\s*/\s*(\d+)"#)
        let totalPages: Int?
        if !totals.isEmpty {
            let fullMatch = PublicSourceImages.match(pageItemText, #"\d+\s*/\s*(\d+)"#)
            totalPages = Int(fullMatch)
        } else {
            totalPages = nil
        }
        if let totalPages, page > totalPages {
            setMore(false)
            return []
        }

        var result: [ComicSummary] = []
        var ids = Set<String>()

        for card in primaryList.select("li") {
            guard let a = card.selectFirst("h4 a[href]") else { continue }
            let link = a.absUrl("href")
            guard let parsedLink = URL(string: link),
                  parsedLink.path.range(of: #"^/comic/\d+\.html$"#, options: .regularExpression) != nil else {
                continue
            }
            let cid = comicIdForUrl(link)
            guard ids.insert(cid).inserted else { continue }
            let cover = card.selectFirst(".stui-vodlist__thumb")
            let image = cover?.absUrl("data-original") ?? ""
            let subtitle = card.selectFirst(".stui-vodlist__detail p")?.text() ?? ""
            let latest = card.selectFirst(".pic-text")?.text() ?? ""
            result.append(
                ComicSummary(
                    sourceId: id,
                    comicId: cid,
                    title: a.text().trimmingCharacters(in: .whitespacesAndNewlines),
                    coverUrl: tagCover(image: image, comic: link),
                    subtitle: subtitle,
                    tags: [],
                    latestChapter: latest
                )
            )
        }

        var more = false
        for a in d.select(".stui-page__item a[href]") {
            let number = PublicSourceImages.match(a.attr("href"), #"/page/(\d+)"#)
            if let num = Int(number), num > page {
                more = true
                break
            }
        }
        setMore(more)
        return result
    }

    private func setMore(_ value: Bool) {
        moreLock.lock()
        lastListingMore = value
        moreLock.unlock()
    }

    private func tagCover(image: String, comic: String) -> String {
        image.isEmpty ? "" : PublicSourceImages.tag(image, id, comic, -1)
    }

    public func comicIdForUrl(_ url: String) -> String {
        if let u = URL(string: url) {
            return "\(id):\(u.path)"
        }
        return "\(id):\(url)"
    }

    private func comicUrl(_ comicId: String) throws -> String {
        let raw: String
        let prefix = id + ":"
        if comicId.hasPrefix(prefix) {
            raw = String(comicId.dropFirst(prefix.count))
        } else {
            raw = comicId
        }
        let url = absolute(raw)
        guard let parsed = URL(string: url),
              let baseHost = URL(string: config.baseUrl)?.host,
              let host = parsed.host,
              host.caseInsensitiveCompare(baseHost) == .orderedSame,
              parsed.path.range(of: #"^/comic/\d+\.html$"#, options: .regularExpression) != nil else {
            throw Self.ioError("卡拉漫画作品地址无效")
        }
        return url
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let url = try comicUrl(comicId)
        let r = try await get(url)
        let d = PublicHTMLDocument.parse(r.body, baseUri: r.url)
        guard let heading = d.selectFirst(".stui-content__detail h1.title"),
              !heading.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Self.ioError("卡拉漫画详情解析失败，请重试")
        }
        let author = data(d, label: "作者")
        let status = data(d, label: "状态")
        let latest: String
        if let commaIdx = status.firstIndex(of: ",") {
            latest = String(status[status.index(after: commaIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            latest = ""
        }
        let cover = d.selectFirst(".stui-content__thumb img")
        let coverUrl = cover?.absUrl("data-original") ?? ""
        let chapters = try parseChapters(d)
        let summary = ComicSummary(
            sourceId: id,
            comicId: comicIdForUrl(r.url),
            title: heading.text().trimmingCharacters(in: .whitespacesAndNewlines),
            coverUrl: tagCover(image: coverUrl, comic: r.url),
            subtitle: author,
            tags: [],
            latestChapter: latest
        )
        let desc = d.selectFirst(".detail-content")?.text() ?? ""
        return ComicDetail(
            summary: summary,
            author: author,
            status: status,
            description: desc,
            latestChapter: latest,
            chapters: chapters
        )
    }

    private func data(_ d: PublicHTMLDocument, label: String) -> String {
        let prefix = label + "："
        for p in d.select(".stui-content__detail p.data") {
            let t = p.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix(prefix) {
                return String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private func parseChapters(_ d: PublicHTMLDocument) throws -> [Chapter] {
        for line in ["playlist2", "playlist3", "playlist4", "playlist1"] {
            guard let parent = d.selectFirst("#\(line)") else { continue }
            var result: [Chapter] = []
            var seen = Set<String>()
            for a in parent.select(".stui-content__playlist a[href]") {
                let url = a.absUrl("href")
                guard let parsed = URL(string: url),
                      parsed.path.range(of: #"^/chapter/\d+-\d+-\d+\.html$"#, options: .regularExpression) != nil,
                      seen.insert(url).inserted else {
                    continue
                }
                result.append(Chapter(chapterId: url, title: a.text().trimmingCharacters(in: .whitespacesAndNewlines), url: url, sectionSlot: 0, chapterSlot: result.count))
            }
            if !result.isEmpty {
                return result
            }
        }
        throw Self.ioError("卡拉漫画目录为空或未解析成功，请重试")
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        try await detail(comicId: comicId).chapters
    }

    public func chapter(url chapterUrl: String) async throws -> ChapterPage {
        guard let url = URL(string: chapterUrl),
              let baseHost = URL(string: config.baseUrl)?.host,
              let host = url.host,
              host.caseInsensitiveCompare(baseHost) == .orderedSame,
              url.path.range(of: #"^/chapter/\d+-\d+-\d+\.html$"#, options: .regularExpression) != nil else {
            throw Self.ioError("卡拉漫画章节地址无效")
        }
        let r = try await get(chapterUrl)
        let player = PublicSourceImages.match(r.body, #"(?s)\bplayer_aaaa\s*=\s*(\{.*?极?\}?)\s*;"#).isEmpty
            ? PublicSourceImages.match(r.body, #"(?s)\bplayer_aaaa\s*=\s*(\{.*?\})\s*;"#)
            : PublicSourceImages.match(r.body, #"(?s)\bplayer_aaaa\s*=\s*(\{.*?极?\}?)\s*;"#)

        guard let data = player.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = obj["url"] as? String else {
            throw Self.ioError("卡拉漫画章节数据无效，请重试")
        }
        guard token.range(of: #"^[a-fA-F0-9]{8,32768}$"#, options: .regularExpression) != nil else {
            throw Self.ioError("卡拉漫画章节图片地址缺失，请重试")
        }
        let reader = try await get(Self.imageOrigin + "/play/min/" + token, referer: r.url)
        let d = PublicHTMLDocument.parse(reader.body, baseUri: reader.url)
        var urls: [String] = []

        for img in d.select(".comic-container img.comic-img[data-src]") {
            let image = img.absUrl("data-src")
            guard let parsed = URL(string: image),
                  parsed.scheme?.lowercased() == "https",
                  let imgHost = URL(string: Self.imageOrigin)?.host,
                  let host = parsed.host,
                  host.caseInsensitiveCompare(imgHost) == .orderedSame,
                  parsed.path.hasPrefix("/image/") else {
                throw Self.ioError("卡拉漫画正文图片地址无效")
            }
            urls.append(image)
        }
        guard !urls.isEmpty else {
            throw Self.ioError("卡拉漫画正文图片未解析成功，请重试")
        }

        imageLock.lock()
        images[chapterUrl] = ImageList(urls: urls, at: Int64(Date().timeIntervalSince1970 * 1000))
        imageOrder.removeAll { $0 == chapterUrl }
        imageOrder.append(chapterUrl)
        while imageOrder.count > 16 {
            let oldKey = imageOrder.removeFirst()
            images.removeValue(forKey: oldKey)
        }
        imageLock.unlock()

        var tagged: [String] = []
        for (i, u) in urls.enumerated() {
            tagged.append(PublicSourceImages.tag(u, id, chapterUrl, i))
        }
        let pageTitle = PublicHTMLDocument.parse(r.body).title()
        return ChapterPage(chapterId: chapterUrl, title: pageTitle, imageUrls: tagged)
    }

    open func resolveImageUrl(_ tagged: String, force: Bool) async throws -> String {
        let meta = PublicSourceImages.metadata(tagged)
        guard meta.count == 3, meta[0] == id else {
            return PublicSourceImages.strip(tagged)
        }
        guard let index = Int(meta[2]) else {
            throw Self.ioError("图片索引无效")
        }
        if index < 0 {
            return PublicSourceImages.strip(tagged)
        }

        imageLock.lock()
        var cached = images[meta[1]]
        imageLock.unlock()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if force || cached == nil || (now - (cached?.at ?? 0)) > 180000 {
            _ = try await chapter(url: meta[1])
            imageLock.lock()
            cached = images[meta[1]]
            imageLock.unlock()
        }

        guard let cachedList = cached, index < cachedList.urls.count else {
            throw Self.ioError("章节页数变更，请重新打开章节")
        }
        return cachedList.urls[index]
    }

    private func getSessionCookies(for host: String) -> [String: String] {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return sessions[host] ?? [:]
    }

    private func setSessionCookie(_ value: String, forKey key: String, host: String) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        var map = sessions[host] ?? [:]
        map[key] = value
        sessions[host] = map
    }

    private func storeCookies(from setCookieHeader: String, host: String) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        var map = sessions[host] ?? [:]
        for part in setCookieHeader.components(separatedBy: ",") {
            let firstSegment = part.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if let eq = firstSegment.firstIndex(of: "=") {
                let k = String(firstSegment[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
                let v = String(firstSegment[firstSegment.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty && !k.lowercased().contains("expires") {
                    map[k] = v
                }
            }
        }
        sessions[host] = map
    }

    private static func ioError(_ message: String) -> NSError {
        NSError(domain: "KalamanhuaComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
