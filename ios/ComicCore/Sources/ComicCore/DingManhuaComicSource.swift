import Foundation

/// HTML and form API adapter for 顶漫画 (dingmanhua), 1:1 with Android DingManhuaComicSource.java.
public struct DingManhuaComicSource: ComicSource {
    public let id: String
    public let name: String
    public let domain: String
    public let referer: String
    private let baseURL: String
    private let config: SourceConfigItem
    private let transport: any HTTPTransport
    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:10.0) Gecko/20100101 Firefox/10.0"
    private static let orderedTags = [
        "悬疑", "欢乐", "搞笑", "玄幻", "冒险", "爱情", "百合", "推理", "热血", "异界",
        "轻改", "奇幻", "校园", "妹控", "生活", "竞技", "同人", "伪娘", "东方", "美食",
        "格斗", "战争", "舰娘", "治愈", "魔幻", "职场", "性转", "萌系", "后宫", "节操",
        "魔法", "科幻", "穿越", "仙侠", "都市", "异能", "网游", "短篇", "女主", "恐怖",
        "重生", "日常", "侦探", "言情", "生存", "武侠", "系统", "励志", "末世", "转生",
        "长篇", "修仙", "末日", "灵异", "游戏", "音乐", "爆笑", "机战", "复仇", "舞蹈"
    ]

    public init(
        config: SourceConfigItem = SourceConfigDefaults.dingmanhua(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25)
    ) {
        self.config = config
        self.id = config.id.isEmpty ? "dingmanhua" : config.id
        self.name = config.name.isEmpty ? "顶漫画" : config.name
        self.domain = config.domain.isEmpty ? "www.dingmanhua.com" : config.domain
        let rawBase = config.baseUrl.isEmpty ? "https://www.dingmanhua.com" : config.baseUrl
        let cleanBase = rawBase.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        self.baseURL = cleanBase
        self.referer = config.referer.isEmpty ? (cleanBase + "/") : config.referer
        self.transport = transport
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let route = config.route("latest").isEmpty ? "/sort/?category=&tag=&page={page}" : config.route("latest")
        let path = route.replacingOccurrences(of: "{page}", with: String(max(1, page)))
        return Self.parseCards(try await get(absolute(path)), sourceId: id, baseURL: baseURL)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let trimmed = SearchRules.trim(keyword)
        guard !trimmed.isEmpty else { return [] }
        let route = config.route("search").isEmpty ? "/search/?query={keyword}&page={page}" : config.route("search")
        let path = route
            .replacingOccurrences(of: "{keyword}", with: Self.formEncode(trimmed))
            .replacingOccurrences(of: "{page}", with: String(max(1, page)))
        return Self.parseCards(try await get(absolute(path)), sourceId: id, baseURL: baseURL)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let regions: [SourceFilterOption] = [
            .init(label: "全部地区", value: "all"),
            .init(label: "日本", value: "jp"),
            .init(label: "大陆", value: "cn"),
            .init(label: "韩国", value: "kr")
        ]
        let tags: [SourceFilterOption] = [.init(label: "全部题材", value: "all")] + Self.orderedTags.map { .init(label: $0, value: $0) }
        return [
            .init(key: "region", label: "地区", options: regions),
            .init(key: "tag", label: "题材", options: tags)
        ]
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let region = Self.selected(filters, key: "region", fallback: "all")
        let tag = Self.selected(filters, key: "tag", fallback: "all")
        var regionId = config.filter("region." + region)
        if regionId.isEmpty && region != "all" { regionId = Self.safeNumber(region) }
        var tagId = config.filter("tag." + tag)
        if tagId.isEmpty && tag != "all" { tagId = Self.safeNumber(tag) }
        let route = config.route("category").isEmpty ? "/sort/?category={category}&tag={tag}&page={page}" : config.route("category")
        let path = route
            .replacingOccurrences(of: "{category}", with: regionId)
            .replacingOccurrences(of: "{tag}", with: tagId)
            .replacingOccurrences(of: "{page}", with: String(max(1, page)))
        return Self.parseCards(try await get(absolute(path)), sourceId: id, baseURL: baseURL)
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let raw = Self.rawID(comicId, sourceId: id)
        guard !raw.isEmpty, raw.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw error("漫画 ID 无效")
        }
        let route = config.route("detail").isEmpty ? "/comic/{comicId}.html" : config.route("detail")
        let html = try await get(absolute(route.replacingOccurrences(of: "{comicId}", with: raw)))
        let summary = Self.parseDetailSummary(id: raw, html: html, sourceId: id, baseURL: baseURL)
        var author = Self.clean(Self.first(html, #"<div[^>]*class=["'][^"']*author[^"']*["'][^>]*>([\s\S]*?)</div>"#))
        var status = Self.clean(Self.first(html, #"<div[^>]*class=["'][^"']*status[^"']*["'][^>]*>([\s\S]*?)</div>"#))
        var description = Self.clean(Self.first(html, #"<p[^>]*class=["']description["'][^>]*>([\s\S]*?)</p>"#))
        var latest = Self.clean(Self.first(html, #"<div[^>]*class=["'][^"']*author[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#))
        author = Self.firstNonEmpty(Self.clean(Self.first(html, #"<span[^>]*id=["']mangaAuthor["'][^>]*>([\s\S]*?)</span>"#)), author)
        description = Self.firstNonEmpty(Self.clean(Self.first(html, #"<p[^>]*id=["']mangaDescription["'][^>]*>([\s\S]*?)</p>"#)), description)
        status = status.replacingOccurrences(of: #"^状态[:：]\s*"#, with: "", options: .regularExpression)
        latest = Self.firstNonEmpty(Self.clean(Self.first(html, #"class=["'][^"']*meta-latest[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#)), latest)
        return .init(summary: summary, author: author, status: status, description: description, latestChapter: latest, chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let raw = Self.rawID(comicId, sourceId: id)
        guard !raw.isEmpty, raw.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw error("漫画 ID 无效")
        }
        let chaptersRoute = config.route("chapters").isEmpty ? "/comic/{comicId}" : config.route("chapters")
        let url = absolute(chaptersRoute.replacingOccurrences(of: "{comicId}", with: raw))
        let bodyText = try await post(url, body: "form=form", referer: referer, json: true)
        guard let data = bodyText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw error("目录响应格式错误")
        }
        let code = Self.intValue(root["code"], default: -1)
        if code != 0 {
            throw error("目录接口返回失败：" + Self.stringValue(root["message"]))
        }
        guard let payload = root["data"] as? [String: Any],
              let list = payload["chapters"] as? [Any] else {
            throw error("目录缺少章节列表")
        }
        var result: [Chapter] = []
        var seen = Set<String>()
        let chapterRoute = config.route("chapter").isEmpty ? "/chapter/{contentId}-{chapterId}.html" : config.route("chapter")
        for (i, rawItem) in list.enumerated() {
            guard let item = rawItem as? [String: Any] else { continue }
            let chapterId = Self.stringValue(item["id"])
            let contentId = Self.stringValue(item["contentId"])
            let title = Self.stringValue(item["chapterName"])
            guard !chapterId.isEmpty, !contentId.isEmpty, !title.isEmpty, seen.insert(chapterId).inserted else { continue }
            let chapterUrl = absolute(chapterRoute
                .replacingOccurrences(of: "{contentId}", with: contentId)
                .replacingOccurrences(of: "{chapterId}", with: chapterId))
            result.append(.init(chapterId: chapterId, title: title, url: chapterUrl, chapterSlot: i))
        }
        guard !result.isEmpty else { throw error("目录未返回有效章节") }
        result.reverse()
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        guard let match = Self.matches(url, #"/chapter/([A-Za-z0-9_-]+)-([A-Za-z0-9_-]+)(?:\.html)?(?:[?#].*)?$"#).first else {
            throw error("章节地址无效")
        }
        let contentId = match[1], chapterId = match[2]
        let chapterRoute = config.route("chapter").isEmpty ? "/chapter/{contentId}-{chapterId}.html" : config.route("chapter")
        let resolvedURL = absolute(chapterRoute
            .replacingOccurrences(of: "{contentId}", with: contentId)
            .replacingOccurrences(of: "{chapterId}", with: chapterId))
        let html = try await get(resolvedURL, referer: referer)
        var title = Self.clean(Self.first(html, #"<title[^>]*>([\s\S]*?)</title>"#))
        if let r = title.range(of: " - ") { title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let r = title.range(of: " | ") { title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        let images = try Self.readerImages(html: html, url: resolvedURL)
        guard !images.isEmpty else { throw error("章节未返回图片：" + chapterId) }
        return .init(chapterId: chapterId, title: title.isEmpty ? chapterId : title, nextPageUrl: "", imageUrls: images)
    }

    static func parseCards(_ html: String, sourceId: String = "dingmanhua", baseURL: String = "https://www.dingmanhua.com") -> [ComicSummary] {
        var result: [ComicSummary] = []
        var seen = Set<String>()
        var cards = elementsByClass(html, tag: "div", cssClass: "manga-card")
        cards.append(contentsOf: elementsByClass(html, tag: "article", cssClass: "manga-card"))
        cards.append(contentsOf: elementsByClass(html, tag: "div", cssClass: "card-content"))
        let prefix = sourceId + ":"
        for card in cards {
            let href = first(card, #"<a[^>]*href=["']([^"']*?/comic/([^/?#]+)\.html[^"']*)["']"#)
            guard let idMatch = matches(href, #"/comic/([^/?#]+)\.html"#).first else { continue }
            let rawId = idMatch[1]
            guard seen.insert(rawId).inserted else { continue }
            var title = clean(first(card, #"<h3[^>]*>([\s\S]*?)</h3>"#))
            if title.isEmpty { title = clean(first(card, #"<div[^>]*class=["']manga-title["'][^>]*>([\s\S]*?)</div>"#)) }
            let img = firstTagOpening(card, tag: "img")
            if title.isEmpty { title = clean(attribute(img, name: "alt")) }
            guard !title.isEmpty else { continue }
            let cover = firstNonEmpty(attribute(img, name: "data-src"), attribute(img, name: "data-original"), attribute(img, name: "src"))
            let latest = clean(first(card, #"<[^>]*class=["'][^"']*(?:latest|chapter|update)[^"']*["'][^>]*>([\s\S]*?)</[^>]+>"#))
            result.append(.init(sourceId: sourceId, comicId: prefix + rawId, title: title, coverUrl: absoluteCover(cover, baseURL: baseURL), subtitle: latest, tags: []))
        }
        return result
    }

    static func readerImages(html: String, url: String) throws -> [String] {
        let base = first(html, #"(?:var|let|const)\s+pasd\s*=\s*["']([^"']+)["']"#)
        let count = first(html, #"(?:var|let|const)\s+num\s*=\s*(?:eval\(\s*["']?)?([0-9]+)"#)
        if !base.isEmpty && !count.isEmpty {
            guard let size = Int(count) else { throw sourceError("图片数量错误") }
            guard (1...10000).contains(size) else { throw sourceError("图片数量超出范围") }
            let ext = first(html, #"pasd\s*\+\s*i\s*\+\s*["'](\.[A-Za-z0-9]+)["']"#)
            guard !ext.isEmpty else { throw sourceError("图片格式未识别") }
            let resolvedBase = resolveRelative(HTML4EntityDecoder.decode(base), against: url)
            return (1...size).map { "\(resolvedBase)\($0)\(ext)" }
        }
        var images: [String] = []
        for tag in elementsByClass(html, tag: "img", cssClass: "comic-image") {
            images.append(contentsOf: imageUrls(tag, baseURL: url))
        }
        return images
    }

    static func parseDetailSummary(id: String, html: String, sourceId: String = "dingmanhua", baseURL: String = "https://www.dingmanhua.com") -> ComicSummary {
        var title = clean(first(html, #"<h1[^>]*>([\s\S]*?)</h1>"#))
        if title.isEmpty { title = clean(first(html, #"<title[^>]*>([\s\S]*?)</title>"#)) }
        if let r = title.range(of: " - ") { title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        let meta = first(html, #"<meta[^>]*(?:property|name)=["']og:image["'][^>]*content=["']([^"']+)"#)
        let img = firstTagOpening(html, tag: "img")
        let cover = absoluteCover(firstNonEmpty(meta, attribute(img, name: "data-src"), attribute(img, name: "src")), baseURL: baseURL)
        let author = clean(first(html, #"<div[^>]*class=["'][^"']*author[^"']*["'][^>]*>([\s\S]*?)</div>"#))
        return .init(sourceId: sourceId, comicId: sourceId + ":" + id, title: title.isEmpty ? id : title, coverUrl: cover, subtitle: author, tags: [])
    }

    // MARK: - HTTP & HTML Helpers (matching HttpComicSourceBase)

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
            "User-Agent": Self.ua,
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
            throw error("请求失败（HTTP \(response.statusCode)）")
        }
        return String(data: response.data, encoding: .utf8) ?? String(decoding: response.data, as: UTF8.self)
    }

    private func absolute(_ value: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "&amp;", with: "&")
        guard !raw.isEmpty else { return "" }
        if raw.hasPrefix("//") { return "https:" + raw }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        return Self.resolveRelative(raw, against: baseURL + "/")
    }

    private static func resolveRelative(_ relative: String, against base: String) -> String {
        if relative.hasPrefix("http://") || relative.hasPrefix("https://") { return relative }
        if relative.hasPrefix("//") { return "https:" + relative }
        if let baseURL = URL(string: base), let resolved = URL(string: relative, relativeTo: baseURL)?.absoluteURL {
            return resolved.absoluteString
        }
        let cleanBase = base.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        return cleanBase + (relative.hasPrefix("/") ? relative : "/" + relative)
    }

    private static func absoluteCover(_ value: String, baseURL: String) -> String {
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("//") { return "https:" + value }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        return resolveRelative(value, against: baseURL.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression) + "/")
    }

    private static func rawID(_ value: String, sourceId: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = sourceId + ":"
        return trimmed.hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
    }

    private static func selected(_ filters: [String: String], key: String, fallback: String) -> String {
        guard let v = filters[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return fallback }
        return v
    }

    private static func safeNumber(_ value: String) -> String {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil ? value : ""
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

    private static func firstTagOpening(_ html: String, tag: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<" + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else { return "" }
        return String(html[range])
    }

    private static func attribute(_ tag: String, name: String) -> String {
        guard !tag.isEmpty else { return "" }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        if let quoted = matches(tag, "(?:^|\\s)" + escaped + #"\s*=\s*([\"'])([\s\S]*?)\1"#).first {
            return HTML4EntityDecoder.decode(quoted[2].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let unquoted = matches(tag, "(?:^|\\s)" + escaped + #"\s*=\s*([^\s>]+)"#).first {
            return HTML4EntityDecoder.decode(unquoted[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ""
    }

    private static func elementsByClass(_ html: String, tag: String, cssClass: String) -> [String] {
        guard !html.isEmpty,
              let openingRegex = try? NSRegularExpression(pattern: "<" + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#, options: .caseInsensitive) else {
            return []
        }
        var result: [String] = []
        let nsRange = NSRange(html.startIndex..., in: html)
        for match in openingRegex.matches(in: html, range: nsRange) {
            guard let openRange = Range(match.range, in: html) else { continue }
            let openTag = String(html[openRange])
            let classes = attribute(openTag, name: "class").split(whereSeparator: \.isWhitespace).map(String.init)
            guard classes.contains(cssClass) else { continue }
            let selfClosing = openTag.hasSuffix("/>") || tag.caseInsensitiveCompare("img") == .orderedSame
            if selfClosing {
                result.append(openTag)
                continue
            }
            if let end = matchingElementEnd(html, tag: tag, from: openRange.upperBound) {
                result.append(String(html[openRange.lowerBound..<end]))
            }
        }
        return result
    }

    private static func matchingElementEnd(_ html: String, tag: String, from contentStart: String.Index) -> String.Index? {
        guard let tokenRegex = try? NSRegularExpression(pattern: "</?" + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#, options: .caseInsensitive) else {
            return nil
        }
        var depth = 1
        let searchRange = NSRange(contentStart..., in: html)
        for match in tokenRegex.matches(in: html, range: searchRange) {
            guard let range = Range(match.range, in: html) else { continue }
            let token = html[range]
            if token.hasPrefix("</") {
                depth -= 1
            } else if !token.hasSuffix("/>") {
                depth += 1
            }
            if depth == 0 {
                return range.upperBound
            }
        }
        return nil
    }

    private static func imageUrls(_ html: String, baseURL: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<(?:img|amp-img)\b[^>]*>"#, options: .caseInsensitive) else { return [] }
        var result: [String] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            var url = firstNonEmpty(attribute(tag, name: "data-src"), attribute(tag, name: "data-original"), attribute(tag, name: "data-lazy-src"), attribute(tag, name: "src"))
            if url.isEmpty || url.hasPrefix("data:") || url.contains("loading.svg") || url.contains("placeholder") { continue }
            url = resolveRelative(url, against: baseURL)
            if (url.hasPrefix("http://") || url.hasPrefix("https://")), seen.insert(url).inserted {
                result.append(url)
            }
        }
        return result
    }

    private static func clean(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        let stripped = value
            .replacingOccurrences(of: #"<script\b[^>]*>[\s\S]*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style\b[^>]*>[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return HTML4EntityDecoder.decode(stripped)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: #"[\t\r\n ]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ text: String, _ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { idx in
                Range(match.range(at: idx), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func first(_ text: String, _ pattern: String) -> String {
        matches(text, pattern).first.flatMap { $0.count > 1 ? $0[1] : nil } ?? ""
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "DingManhuaComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: name + message])
    }

    private static func sourceError(_ message: String) -> NSError {
        NSError(domain: "DingManhuaComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: "顶漫画" + message])
    }
}
