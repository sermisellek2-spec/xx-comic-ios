import Foundation

/// JSON:API adapter for 新漫画-A (xapi.xinmanhua.net), 1:1 with Android XinmanhuaComicSource.java.
public final class XinmanhuaComicSource: ComicSource, @unchecked Sendable {
    public let id: String
    public let name: String
    public let domain: String
    public let referer: String
    private let baseURL: String
    private let config: SourceConfigItem
    private let transport: any HTTPTransport

    private static let ua = "okhttp/3.10.0"
    private static let genres: [(String, String)] = [
        ("全部", "all"), ("治愈", "治愈"), ("日常", "日常"), ("都市", "都市"), ("悬疑", "悬疑"),
        ("科幻", "科幻"), ("奇幻", "奇幻"), ("热血", "热血"), ("武侠", "武侠"), ("古风", "古风"),
        ("恋爱", "恋爱"), ("少年", "少年"), ("日漫", "日漫"), ("原创", "原创")
    ]

    public init(
        config: SourceConfigItem = SourceConfigDefaults.xinmanhua(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25)
    ) {
        self.config = config
        self.id = config.id.isEmpty ? "xinmanhua" : config.id
        self.name = config.name.isEmpty ? "新漫画-A" : config.name
        self.domain = config.domain.isEmpty ? "xapi.xinmanhua.net" : config.domain
        let rawBase = config.baseUrl.isEmpty ? "https://xapi.xinmanhua.net" : config.baseUrl
        let cleanBase = rawBase.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        self.baseURL = cleanBase
        self.referer = config.referer.isEmpty ? (cleanBase + "/") : config.referer
        self.transport = transport
    }

    public func userAgent() -> String {
        Self.ua
    }

    public var categories: [String] {
        Self.genres.dropFirst().map(\.0)
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let route = config.route("latest").isEmpty ? "/search/catalog?keyword=all&ischarge=2&isfinish=2&order=0&page={page}" : config.route("latest")
        let path = route.replacingOccurrences(of: "{page}", with: String(max(1, page)))
        return try Self.parseSummaries(try await get(absolute(path)), sourceId: id)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let trimmed = SearchRules.trim(keyword)
        guard !trimmed.isEmpty else { return [] }
        let p = max(1, page)
        let body = "keyword=\(Self.formEncode(trimmed))&page=\(p)"
        let route = config.route("search").isEmpty ? "/search/selfdefine" : config.route("search")
        var url = absolute(route)
        url += (url.contains("?") ? "&" : "?") + "page=\(p)"
        return try Self.parseSummaries(try await post(url, body: body, referer: referer, json: true), sourceId: id)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let genreOptions = Self.genres.map { SourceFilterOption(label: $0.0, value: $0.1) }
        let charges = [
            SourceFilterOption(label: "全部", value: "2"),
            SourceFilterOption(label: "免费", value: "0"),
            SourceFilterOption(label: "付费", value: "1")
        ]
        let states = [
            SourceFilterOption(label: "全部", value: "2"),
            SourceFilterOption(label: "连载", value: "0"),
            SourceFilterOption(label: "完结", value: "1")
        ]
        let orders = [
            SourceFilterOption(label: "更新时间", value: "0"),
            SourceFilterOption(label: "人气", value: "1")
        ]
        return [
            .init(key: "genre", label: "题材", options: genreOptions),
            .init(key: "ischarge", label: "收费", options: charges),
            .init(key: "isfinish", label: "状态", options: states),
            .init(key: "order", label: "排序", options: orders)
        ]
    }

    public func category(region: String, state: String, page: Int) async throws -> [ComicSummary] {
        try await category(filters: ["genre": region], page: page)
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var keyword = Self.selected(filters, key: "genre", fallback: "all")
        if keyword == "all" { keyword = "all" }
        var charge = Self.selected(filters, key: "ischarge", fallback: "2")
        var finish = Self.selected(filters, key: "isfinish", fallback: "2")
        var order = Self.selected(filters, key: "order", fallback: "0")
        if charge.range(of: #"^[012]$"#, options: .regularExpression) == nil { charge = "2" }
        if finish.range(of: #"^[012]$"#, options: .regularExpression) == nil { finish = "2" }
        if order.range(of: #"^[0-9]+$"#, options: .regularExpression) == nil { order = "0" }
        let route = config.route("category").isEmpty ? "/search/catalog?keyword={keyword}&ischarge={ischarge}&isfinish={isfinish}&order={order}&page={page}" : config.route("category")
        let path = route
            .replacingOccurrences(of: "{keyword}", with: Self.formEncode(keyword))
            .replacingOccurrences(of: "{ischarge}", with: charge)
            .replacingOccurrences(of: "{isfinish}", with: finish)
            .replacingOccurrences(of: "{order}", with: order)
            .replacingOccurrences(of: "{page}", with: String(max(1, page)))
        return try Self.parseSummaries(try await get(absolute(path)), sourceId: id)
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let wid = Self.rawID(comicId, sourceId: id)
        guard wid.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            throw Self.sourceError("新漫画漫画 ID 无效")
        }
        let route = config.route("detail").isEmpty ? "/worksinfos/{wid}" : config.route("detail")
        let data = try Self.dataObject(try await get(absolute(route.replacingOccurrences(of: "{wid}", with: Self.formEncode(wid)))))
        let attrs = Self.attributes(data)
        guard wid == Self.stringValue(attrs["wid"]) else {
            throw Self.sourceError("新漫画详情 ID 与请求不匹配")
        }
        let summary = Self.parseSummary(data, sourceId: id)
        let description = Self.firstNonEmpty(Self.stringValue(attrs["description"]), Self.stringValue(attrs["intro"]))
        let latest = Self.stringValue(attrs["lastctitle"])
        return .init(
            summary: summary,
            author: Self.stringValue(attrs["author"]),
            status: Self.status(attrs),
            description: description,
            latestChapter: latest,
            chapters: []
        )
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let wid = Self.rawID(comicId, sourceId: id)
        guard wid.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            throw Self.sourceError("新漫画漫画 ID 无效")
        }
        let route = config.route("chapters").isEmpty ? "/worksinfos/{wid}/chapters" : config.route("chapters")
        let path = route.replacingOccurrences(of: "{wid}", with: Self.formEncode(wid))
        let root = try Self.json(try await get(absolute(path)), label: "新漫画目录")
        guard let list = root["data"] as? [Any] else {
            throw Self.sourceError("新漫画目录缺少章节列表")
        }
        var result: [Chapter] = []
        var seen = Set<String>()
        let chapterRoute = config.route("chapter").isEmpty ? "/chapters/{chapterId}/qualitywebs" : config.route("chapter")
        for (i, rawItem) in list.enumerated() {
            guard let item = rawItem as? [String: Any] else { continue }
            let attrs = Self.attributes(item)
            let cid = Self.stringValue(item["id"])
            guard !cid.isEmpty, seen.insert(cid).inserted, wid == Self.stringValue(attrs["wid"]) else { continue }
            let chapterTitle = Self.stringValue(attrs["title"])
            let intro = Self.stringValue(attrs["intro"])
            var title = chapterTitle.isEmpty ? intro : chapterTitle
            if !chapterTitle.isEmpty && !intro.isEmpty {
                title += " " + intro
            }
            if title.isEmpty {
                title = "章节 " + cid
            }
            let url = absolute(chapterRoute.replacingOccurrences(of: "{chapterId}", with: Self.formEncode(cid)))
                + "#title=" + Self.encodeFragment(title)
            let slot = Self.intValue(attrs["cidx"], default: i + 1)
            result.append(.init(chapterId: cid, title: title, url: url, sectionSlot: 0, chapterSlot: slot))
        }
        guard !result.isEmpty else {
            throw Self.sourceError("新漫画目录未返回有效章节")
        }
        result.sort { $0.chapterSlot < $1.chapterSlot }
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        guard let match = Self.matches(url, #"/chapters/([0-9]+)/qualitywebs(?:[?#].*)?$"#).first else {
            throw Self.sourceError("新漫画章节地址无效")
        }
        let chapterId = match[1]
        let title = Self.fragmentTitle(url)
        let chapterRoute = config.route("chapter").isEmpty ? "/chapters/{chapterId}/qualitywebs" : config.route("chapter")
        let target = absolute(chapterRoute.replacingOccurrences(of: "{chapterId}", with: chapterId))
        let root = try Self.json(try await get(target), label: "新漫画阅读页")
        guard let list = root["data"] as? [Any], !list.isEmpty else {
            throw Self.sourceError("新漫画阅读页没有图片")
        }
        var images: [String] = []
        for rawItem in list {
            let item = rawItem as? [String: Any]
            let attrs = Self.attributes(item)
            guard let rawChapId = attrs["chapid"], !(rawChapId is NSNull),
                  chapterId == Self.stringValue(rawChapId) else {
                throw Self.sourceError("新漫画阅读图片与章节不匹配")
            }
            var image = Self.stringValue(attrs["url"])
            if image.hasPrefix("http://") {
                image = "https://" + String(image.dropFirst("http://".count))
            }
            guard image.hasPrefix("https://") else {
                throw Self.sourceError("新漫画图片地址无效")
            }
            images.append(image)
        }
        guard !images.isEmpty else {
            throw Self.sourceError("新漫画阅读页没有有效图片")
        }
        return .init(chapterId: chapterId, title: title.isEmpty ? chapterId : title, nextPageUrl: "", imageUrls: images)
    }

    public func healthCheck() async -> Bool {
        do {
            return !(try await latest(page: 1)).isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Internal Parsing Helpers

    static func parseSummaries(_ body: String, sourceId: String = "xinmanhua") throws -> [ComicSummary] {
        let root = try json(body, label: "新漫画列表")
        guard let list = root["data"] as? [Any] else {
            throw sourceError("新漫画列表响应缺少 data")
        }
        let prefix = sourceId + ":"
        var result: [ComicSummary] = []
        var seen = Set<String>()
        for rawItem in list {
            guard let item = rawItem as? [String: Any] else { continue }
            let summary = parseSummary(item, sourceId: sourceId)
            if summary.comicId != prefix && seen.insert(summary.comicId).inserted {
                result.append(summary)
            }
        }
        return result
    }

    static func parseSummary(_ item: [String: Any], sourceId: String = "xinmanhua") -> ComicSummary {
        let attrs = attributes(item)
        var wid = stringValue(attrs["wid"])
        if wid.isEmpty { wid = stringValue(item["id"]) }
        var cover = firstNonEmpty(
            stringValue(attrs["logo_detail_thumb"]),
            stringValue(attrs["logo_detail"]),
            stringValue(attrs["logo"])
        )
        if cover.hasPrefix("http://") {
            cover = "https://" + String(cover.dropFirst("http://".count))
        }
        var tags: [String] = []
        if let arr = attrs["workscate"] as? [Any] {
            for rawTag in arr {
                let tag = stringValue(rawTag)
                if !tag.isEmpty { tags.append(tag) }
            }
        } else if let rawCate = attrs["workscate"], !(rawCate is NSNull) {
            let str = stringValue(rawCate)
            for part in str.components(separatedBy: CharacterSet(charactersIn: ",，/|")) {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { tags.append(trimmed) }
            }
        }
        let title = stringValue(attrs["title"])
        return .init(
            sourceId: sourceId,
            comicId: sourceId + ":" + wid,
            title: title.isEmpty ? wid : title,
            coverUrl: cover,
            subtitle: stringValue(attrs["author"]),
            tags: tags,
            latestChapter: stringValue(attrs["lastctitle"])
        )
    }

    private static func dataObject(_ body: String) throws -> [String: Any] {
        let root = try json(body, label: "新漫画详情")
        guard let data = root["data"] as? [String: Any] else {
            throw sourceError("新漫画详情响应缺少 data")
        }
        return data
    }

    private static func attributes(_ item: [String: Any]?) -> [String: Any] {
        (item?["attributes"] as? [String: Any]) ?? [:]
    }

    private static func json(_ body: String, label: String) throws -> [String: Any] {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw sourceError(label + "响应格式错误")
        }
        return obj
    }

    private static func status(_ attrs: [String: Any]) -> String {
        guard let value = attrs["isfinish"], !(value is NSNull) else { return "" }
        return stringValue(value) == "1" ? "完结" : "连载中"
    }

    private static func selected(_ filters: [String: String], key: String, fallback: String) -> String {
        firstNonEmpty(filters[key] ?? "", fallback)
    }

    private static func encodeFragment(_ value: String) -> String {
        formEncode(value).replacingOccurrences(of: "+", with: "%20")
    }

    private static func fragmentTitle(_ url: String) -> String {
        guard let match = matches(url, #"#title=([^&]+)"#).first else { return "" }
        let raw = match[1].replacingOccurrences(of: "+", with: "%20")
        return raw.removingPercentEncoding ?? match[1]
    }

    // MARK: - HTTP & Value Helpers

    private func get(_ url: String, referer: String? = nil) async throws -> String {
        try await readRequest(url: url, method: "GET", body: nil, referer: referer ?? self.referer, json: false)
    }

    private func post(_ url: String, body: String, referer: String? = nil, json: Bool = false) async throws -> String {
        try await readRequest(url: url, method: "POST", body: body, referer: referer ?? self.referer, json: json)
    }

    private func readRequest(url: String, method: String, body: String?, referer: String, json: Bool) async throws -> String {
        do {
            return try await performRequest(url: url, method: method, body: body, referer: referer, json: json)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let urlError = error as? URLError,
               [.networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(urlError.code) {
                return try await performRequest(url: url, method: method, body: body, referer: referer, json: json)
            }
            throw error
        }
    }

    private func performRequest(url: String, method: String, body: String?, referer: String, json: Bool) async throws -> String {
        try Task.checkCancellation()
        guard let targetURL = URL(string: url), ["http", "https"].contains(targetURL.scheme?.lowercased() ?? "") else {
            throw URLError(.badURL)
        }
        var headers: [String: String] = [
            "User-Agent": userAgent(),
            "Accept": json
                ? "application/json, text/plain, */*"
                : "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.6",
            "Accept-Encoding": "gzip",
            "Connection": "close"
        ]
        if !referer.isEmpty { headers["Referer"] = referer }
        let response: HTTPResponse
        if method == "POST" {
            if let scheme = targetURL.scheme, let host = targetURL.host {
                let port = targetURL.port.map { ":\($0)" } ?? ""
                headers["Origin"] = "\(scheme)://\(host)\(port)"
            }
            headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
            response = try await transport.post(targetURL, headers: headers, body: Data((body ?? "").utf8))
        } else {
            response = try await transport.get(targetURL, headers: headers)
        }
        try Task.checkCancellation()
        guard (200..<400).contains(response.statusCode) else {
            throw Self.sourceError("\(name) 请求失败（HTTP \(response.statusCode)）")
        }
        return String(data: response.data, encoding: .utf8) ?? String(decoding: response.data, as: UTF8.self)
    }

    private func absolute(_ value: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "&amp;", with: "&")
        guard !raw.isEmpty else { return "" }
        if raw.hasPrefix("//") { return "https:" + raw }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        if let base = URL(string: baseURL + "/"), let resolved = URL(string: raw, relativeTo: base)?.absoluteURL {
            return resolved.absoluteString
        }
        return baseURL + (raw.hasPrefix("/") ? raw : "/" + raw)
    }

    private static func rawID(_ value: String, sourceId: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = sourceId + ":"
        return trimmed.hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
    }

    private static func formEncode(_ value: String) -> String {
        value.utf8.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 46, 95, 42].contains(byte) {
                return String(UnicodeScalar(byte))
            }
            return byte == 32 ? "+" : String(format: "%%%02X", byte)
        }.joined()
    }

    private static func intValue(_ value: Any?, default fallback: Int) -> Int {
        if let v = value as? Int { return v }
        if let v = value as? NSNumber { return v.intValue }
        if let v = value as? String, let parsed = Int(v) { return parsed }
        return fallback
    }

    private static func stringValue(_ value: Any?) -> String {
        if let v = value as? String { return v }
        if let v = value as? NSNumber { return v.stringValue }
        return ""
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        for v in values {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private static func matches(_ text: String, _ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { idx in
                Range(match.range(at: idx), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func sourceError(_ message: String) -> NSError {
        NSError(domain: "XinmanhuaComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
