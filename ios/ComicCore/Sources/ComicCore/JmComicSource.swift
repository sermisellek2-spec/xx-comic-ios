import Foundation

public enum JmSourceError: Error, Equatable, Sendable {
    case invalidURL(String)
    case invalidResponse(String)
    case verificationRequired
}

extension JmSourceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "漫画链接无效，请重新打开作品。"
        case let .invalidResponse(msg): return msg
        case .verificationRequired: return "需要安全验证，请完成验证后继续。"
        }
    }
}

public actor JmComicSource: ComicSource {
    public nonisolated let id = "jmcomic"
    public nonisolated let name: String
    public nonisolated let referer: String
    public nonisolated let domain: String

    private static let sourceID = "jmcomic"
    private static let prefix = "jmcomic:"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    private static let albumLinkPattern = #"<a\b([^>]*href\s*=\s*(["'])([^"']*/album/(\d+)[^"']*)\2[^>]*)>([\s\S]*?)</a>"#
    private static let anchorPattern = #"<a\b([^>]*)>([\s\S]*?)</a>"#
    private static let themeSectionPattern = #"<h4[^>]*>([\s\S]*?)</h4>(?:(?!<h4\b)[\s\S]){0,1600}?<ul\b[^>]*class\s*=\s*["'][^"']*\bbtnmg\b[^"']*["'][^>]*>([\s\S]*?)</ul>"#
    private static let imageTagPattern = #"<img\b[^>]*>"#

    private let baseURL: URL
    private let config: SourceConfigItem
    private let transport: any HTTPTransport
    private let browserSession: (any ComicBrowserSession)?

    private var filterGroupsCache: [SourceFilterGroup]?
    private var detailPageId = ""
    private var detailPageHtml = ""

    public init(
        config: SourceConfigItem = SourceConfigDefaults.jmcomic(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25),
        browserSession: (any ComicBrowserSession)? = nil
    ) {
        self.config = config
        self.name = config.name
        let url = URL(string: config.baseUrl) ?? URL(string: "https://18comic.vip")!
        self.baseURL = url
        self.domain = config.domain.isEmpty ? (url.host ?? "18comic.vip") : config.domain
        self.transport = transport
        self.browserSession = browserSession
        self.referer = config.referer.isEmpty ? url.absoluteString.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression) + "/" : config.referer
    }

    public static func hasCatalogMarker(_ html: String) -> Bool {
        for match in matches(albumLinkPattern, in: html) {
            if match.count > 5, !matches(imageTagPattern, in: match[5]).isEmpty {
                return true
            }
        }
        return false
    }

    public func verifyAccess() async throws {
        let path = pageUrl(absolute(config.route("latest")), page: 1)
        let html = try await fetch(path, interactive: true)
        guard Self.hasCatalogMarker(html) else { throw JmSourceError.invalidResponse(config.name + " 页面未就绪") }
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let url = pageUrl(absolute(config.route("latest")), page: page)
        let html = try await fetch(url)
        return try requireCatalogCards(html)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        let encoded = SearchRules.trim(keyword).utf8.map { byte -> String in
            let scalar = UnicodeScalar(byte)
            if allowed.contains(Character(scalar)) { return String(Character(scalar)) }
            if byte == 0x20 { return "+" }
            return String(format: "%%%02X", byte)
        }.joined()
        let path = config.route("search").replacingOccurrences(of: "{keyword}", with: encoded)
        let url = pageUrl(absolute(path), page: page)
        let html = try await fetch(url)
        return parseCards(html)
    }

    public func categories() async throws -> [String] {
        let groups = try await filterGroups()
        return groups.map(\.label)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        if let cached = filterGroupsCache { return cached }
        let url = absolute(config.route("categoryIndex"))
        let html = try await fetch(url)
        let groups = Self.parseFilterGroups(html, baseUrl: config.baseUrl)
        guard !groups.isEmpty else { throw JmSourceError.invalidResponse(config.name + " 分类解析失败") }
        filterGroupsCache = groups
        return groups
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var path = config.route("latest")
        var filtered = false
        for (key, val) in filters {
            if key.hasPrefix("theme_"), isCatalogPath(val) {
                path = val
                filtered = true
                break
            }
        }
        let url = pageUrl(absolute(path), page: page)
        let html = try await fetch(url)
        return (!filtered && page == 1) ? try requireCatalogCards(html) : parseCards(html)
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawId = rawComicId(comicId)
        let html = try await detailPage(rawId)
        var title = clean(firstMatch(#"<[^>]+id=["']book-name["'][^>]*>([\s\S]*?)</[^>]+>"#, in: html))
        if title.isEmpty { title = clean(meta(html, key: "og:title")) }
        let cover = Self.parseCover(html, rawId: rawId)
        var description = clean(firstMatch(#"<h2[^>]*>\s*敘述\s*[:：]([\s\S]*?)</h2>"#, in: html))
        if description.isEmpty { description = clean(meta(html, key: "description")) }
        let scope = detailScope(html)
        let authors = linkTexts(scope, hrefToken: "main_tag=2")
        let tags = tagTexts(scope)
        let status: String
        if tags.contains("完結") || tags.contains("完结") {
            status = "已完结"
        } else if tags.contains("連載中") || tags.contains("连载中") {
            status = "连载中"
        } else {
            status = ""
        }
        let authorText = authors.joined(separator: " / ")
        let summary = ComicSummary(
            sourceId: Self.sourceID,
            comicId: Self.prefix + rawId,
            title: title,
            coverUrl: absolute(cover),
            subtitle: authorText,
            tags: tags
        )
        return ComicDetail(summary: summary, author: authorText, status: status, description: description, latestChapter: "", chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let rawId = rawComicId(comicId)
        let html = try await detailPage(rawId)
        let result = Self.parseChapters(html, baseUrl: config.baseUrl)
        guard !result.isEmpty else { throw JmSourceError.invalidResponse(config.name + " 目录解析失败") }
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let absoluteUrl = absolute(url)
        let html = try await fetch(absoluteUrl)
        let images = try Self.parseChapterImages(html)
        guard !images.isEmpty else { throw JmSourceError.invalidResponse(config.name + " 正文图片解析失败") }
        let title = clean(firstMatch(#"<h3[^>]*class=["'][^"']*h2_series[^"']*["'][^>]*>([\s\S]*?)</h3>"#, in: html))
        return ChapterPage(chapterId: absoluteUrl, title: title, nextPageUrl: "", imageUrls: images)
    }

    public func healthCheck() async -> Bool {
        do {
            let html = try await fetch(absolute(config.route("categoryIndex")))
            return html.contains("btnmg")
        } catch {
            return false
        }
    }

    // MARK: - Internal Parsing Helpers

    public static func parseFilterGroups(_ html: String, baseUrl: String) -> [SourceFilterGroup] {
        var groups: [SourceFilterGroup] = []
        let sections = matches(themeSectionPattern, in: html)
        var index = 0
        for section in sections {
            guard section.count > 2 else { continue }
            let label = normalizeThemeLabel(cleanMarkup(section[1]))
            var options: [SourceFilterOption] = [.init(label: "全部", value: "all")]
            var seen = Set<String>()
            let links = matches(anchorPattern, in: section[2])
            for link in links {
                guard link.count > 2 else { continue }
                let href = decodeEntities(attribute("href", in: link[1])).trimmingCharacters(in: .whitespacesAndNewlines)
                guard isCatalogPath(href, baseUrl: baseUrl), seen.insert(href).inserted else { continue }
                let optionLabel = cleanMarkup(link[2])
                if !optionLabel.isEmpty {
                    options.append(.init(label: optionLabel, value: href))
                }
            }
            if !label.isEmpty, options.count > 1 {
                groups.append(.init(key: "theme_\(index)", label: label, options: options))
                index += 1
            }
        }
        return groups
    }

    public static func parseChapters(_ html: String, baseUrl: String) -> [Chapter] {
        var result: [Chapter] = []
        var seen = Set<String>()
        let scope = episodeScope(html)
        let links = matches(anchorPattern, in: scope)
        let photoRegex = try? NSRegularExpression(pattern: #"(?:https?://[^/]+)?/photo/(\d+)"#, options: .caseInsensitive)
        for link in links {
            guard link.count > 2 else { continue }
            let href = decodeEntities(attribute("href", in: link[1]))
            guard let regex = photoRegex,
                  let match = regex.firstMatch(in: href, range: NSRange(href.startIndex..., in: href)),
                  match.numberOfRanges > 1,
                  let r1 = Range(match.range(at: 1), in: href) else { continue }
            let chapterId = String(href[r1])
            let dataAlbum = attribute("data-album", in: link[1])
            guard !dataAlbum.isEmpty, chapterId == dataAlbum else { continue }
            let title = cleanMarkup(firstMatch(#"<h3[^>]*class=["'][^"']*h2_series[^"']*["'][^>]*>([\s\S]*?)</h3>"#, in: link[2]))
            guard !title.isEmpty, seen.insert(chapterId).inserted else { continue }
            result.append(Chapter(
                chapterId: chapterId,
                title: title,
                url: absolute(baseUrl: baseUrl, value: href),
                chapterSlot: result.count
            ))
        }
        if !result.isEmpty { return result }

        // Fallback: read-block direct read button
        let readBlock = firstMatch(#"<div\b[^>]*class\s*=\s*["'][^"']*\bread-block\b[^"']*["'][^>]*>([\s\S]{0,6000}?)</div>"#, in: html)
        let directLinks = matches(anchorPattern, in: readBlock)
        let directRegex = try? NSRegularExpression(pattern: #"(?:https?://[^/]+)?/photo/(\d+)/?(?:[?#].*)?$"#, options: .caseInsensitive)
        for dLink in directLinks {
            guard dLink.count > 2 else { continue }
            let href = decodeEntities(attribute("href", in: dLink[1])).trimmingCharacters(in: .whitespacesAndNewlines)
            let label = cleanMarkup(dLink[2])
            if href.contains("read_mode=") { continue }
            let directRead = label.contains("开始阅读") || label.contains("開始閱讀")
                || label.contains("继续阅读") || label.contains("繼續閱讀") || label.contains("續看")
            if !directRead { continue }
            guard let regex = directRegex,
                  let match = regex.firstMatch(in: href, range: NSRange(href.startIndex..., in: href)),
                  match.numberOfRanges > 1,
                  let r1 = Range(match.range(at: 1), in: href) else { continue }
            let chapterId = String(href[r1])
            result.append(Chapter(
                chapterId: chapterId,
                title: "第1话",
                url: absolute(baseUrl: baseUrl, value: "/photo/\(chapterId)"),
                chapterSlot: 0
            ))
            break
        }
        return result
    }

    public static func parseChapterImages(_ html: String) throws -> [String] {
        let aid = firstMatch(#"(?:var\s+)?aid\s*=\s*(\d+)"#, in: html)
        let scrambleId = firstMatch(#"(?:var\s+)?scramble_id\s*=\s*(\d+)"#, in: html)
        let cdnHost = decodeEntities(firstMatch(#"(?:var\s+)?cdnImgHost\s*[:=]\s*["']([^"']+)["']"#, in: html))
        let pageArray = firstMatch(#"(?:var\s+)?page_arr\s*=\s*(\[[\s\S]*?\])\s*;?"#, in: html)

        guard aid.allSatisfy({ $0.isNumber }) && !aid.isEmpty,
              scrambleId.allSatisfy({ $0.isNumber }) && !scrambleId.isEmpty,
              !cdnHost.isEmpty, !pageArray.isEmpty else {
            throw JmSourceError.invalidResponse("正文参数解析失败")
        }

        guard let data = pageArray.data(using: .utf8),
              let pages = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw JmSourceError.invalidResponse("图片列表解析失败")
        }

        var images: [String] = []
        let trimmedHost = trimSlash(cdnHost)
        for item in pages {
            let fileName = (item as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileName.isEmpty else { continue }
            let image = (fileName.hasPrefix("http://") || fileName.hasPrefix("https://"))
                ? fileName
                : "\(trimmedHost)/media/photos/\(aid)/\(fileName)"
            let querySep = image.contains("?") ? "&" : "?"
            images.append("\(image)\(querySep)scramble_id=\(scrambleId)")
        }
        return images
    }

    public static func parseCover(_ html: String, rawId: String) -> String {
        var fallback = ""
        let images = matches(imageTagPattern, in: html)
        let escapedId = NSRegularExpression.escapedPattern(for: rawId)
        let albumImageRegex = try? NSRegularExpression(pattern: "/media/albums/" + escapedId + #"(?:[._/?#-]|$)"#, options: .caseInsensitive)
        for img in images {
            guard let tag = img.first else { continue }
            let url = imageUrl(tag)
            guard let regex = albumImageRegex, regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil else { continue }
            if attribute("id", in: tag) == "album_photo_cover" { return url }
            if fallback.isEmpty { fallback = url }
        }
        return fallback
    }

    // MARK: - Private Network & Helpers

    private func detailPage(_ rawId: String) async throws -> String {
        if rawId == detailPageId, !detailPageHtml.isEmpty { return detailPageHtml }
        let path = config.route("detail").replacingOccurrences(of: "{comicId}", with: rawId)
        let html = try await fetch(absolute(path))
        if !html.isEmpty {
            detailPageId = rawId
            detailPageHtml = html
        }
        return html
    }

    private func fetch(_ value: String, interactive: Bool = false) async throws -> String {
        try Task.checkCancellation()
        let url = try toURL(value)
        if let browserSession, isMainSite(url) {
            let html = try await (interactive ? browserSession.fetchInteractive(url) : browserSession.fetch(url))
            try Task.checkCancellation()
            if Mh18VerificationRules.isChallenge(body: html) { throw JmSourceError.verificationRequired }
            return html
        }
        let response = try await transport.get(url, headers: [
            "User-Agent": Self.userAgent,
            "Referer": referer,
            "Accept-Language": "zh-CN,zh;q=0.9"
        ])
        try Task.checkCancellation()
        let mitigated = response.headerValue(for: "cf-mitigated")
        if response.statusCode == 403 && mitigated?.lowercased() == "challenge" { throw JmSourceError.verificationRequired }
        guard let body = String(data: response.data, encoding: .utf8) else {
            if !(200..<400).contains(response.statusCode) { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
            throw JmSourceError.invalidResponse("响应不是 UTF-8")
        }
        if response.statusCode == 403 && Mh18VerificationRules.isChallenge(body: body) {
            throw JmSourceError.verificationRequired
        }
        guard (200..<400).contains(response.statusCode) else {
            throw HTTPTransportError.invalidStatusCode(response.statusCode)
        }
        return body
    }

    private func isMainSite(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let target = domain.lowercased()
        return host == target || host.hasSuffix("." + target)
    }

    private func requireCatalogCards(_ html: String) throws -> [ComicSummary] {
        let cards = parseCards(html)
        guard !cards.isEmpty else { throw JmSourceError.invalidResponse(config.name + " 漫画列表解析失败") }
        return cards
    }

    private func parseCards(_ html: String) -> [ComicSummary] {
        var result: [ComicSummary] = []
        var seen = Set<String>()
        let cards = Self.matches(Self.albumLinkPattern, in: html)
        for card in cards {
            guard card.count > 5 else { continue }
            let rawId = card[4]
            guard seen.insert(rawId).inserted else { continue }
            let imageTag = firstMatch(Self.imageTagPattern, in: card[5])
            var title = cleanMarkup(attribute("title", in: imageTag))
            if title.isEmpty { title = cleanMarkup(attribute("alt", in: imageTag)) }
            guard !title.isEmpty else { continue }
            let cover = Self.imageUrl(imageTag)
            result.append(ComicSummary(
                sourceId: Self.sourceID,
                comicId: Self.prefix + rawId,
                title: title,
                coverUrl: absolute(cover),
                subtitle: "",
                tags: []
            ))
        }
        return result
    }

    private func detailScope(_ html: String) -> String {
        guard let startRange = html.range(of: "book-name") else { return html }
        let start = startRange.lowerBound
        let end: String.Index
        if let episodeRange = html[start...].range(of: #"class="episode""#) {
            end = episodeRange.lowerBound
        } else {
            end = html.index(start, offsetBy: min(50000, html.distance(from: start, to: html.endIndex)))
        }
        return String(html[start..<end])
    }

    private static func episodeScope(_ html: String) -> String {
        guard let openingRange = html.range(of: #"<div\b[^>]*class\s*=\s*(["'])[^"']*\bepisode\b[^"']*\1[^>]*>"#, options: .regularExpression) else {
            return ""
        }
        let remainder = html[openingRange.upperBound...]
        let divRegex = try? NSRegularExpression(pattern: #"</?div\b[^>]*>"#, options: .caseInsensitive)
        guard let regex = divRegex else { return String(remainder) }
        let nsString = String(remainder) as NSString
        let matches = regex.matches(in: String(remainder), range: NSRange(location: 0, length: nsString.length))
        var depth = 0
        for m in matches {
            let tag = nsString.substring(with: m.range)
            if tag.hasPrefix("</") { depth -= 1 }
            else { depth += 1 }
            if depth < 0 {
                return nsString.substring(with: NSRange(location: 0, length: m.range.location))
            }
        }
        return String(remainder)
    }

    private func linkTexts(_ scope: String, hrefToken: String) -> [String] {
        var result: [String] = []
        let links = Self.matches(Self.anchorPattern, in: scope)
        for link in links {
            guard link.count > 2 else { continue }
            let href = Self.decodeEntities(attribute("href", in: link[1]))
            let text = clean(link[2])
            if href.contains(hrefToken), !text.isEmpty, !result.contains(text) {
                result.append(text)
            }
        }
        return result
    }

    private func tagTexts(_ scope: String) -> [String] {
        var result: [String] = []
        let links = Self.matches(Self.anchorPattern, in: scope)
        for link in links {
            guard link.count > 2 else { continue }
            let href = Self.decodeEntities(attribute("href", in: link[1]))
            let classes = attribute("class", in: link[1])
            if !href.contains("/search/photos") || href.contains("main_tag=2")
                || (!classes.contains("tag") && !href.contains("search_query=")) {
                continue
            }
            let text = clean(link[2])
            if !text.isEmpty, !result.contains(text) {
                result.append(text)
            }
        }
        return result
    }

    private static func imageUrl(_ tag: String) -> String {
        var url = attribute("data-original", in: tag)
        if url.isEmpty { url = attribute("data-src", in: tag) }
        if url.isEmpty { url = attribute("src", in: tag) }
        return decodeEntities(url).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pageUrl(_ urlString: String, page: Int) -> String {
        let clean = urlString.replacingOccurrences(of: #"([?&])page=\d+&?"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[?&]+$"#, with: "", options: .regularExpression)
        let sep = clean.contains("?") ? "&" : "?"
        return "\(clean)\(sep)page=\(max(1, page))"
    }

    private func isCatalogPath(_ value: String) -> Bool {
        Self.isCatalogPath(value, baseUrl: config.baseUrl)
    }

    private static func isCatalogPath(_ value: String, baseUrl: String) -> Bool {
        let trimmed = decodeEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "all" { return false }
        return trimmed.hasPrefix("/search/photos") || trimmed.hasPrefix("/albums")
            || trimmed.hasPrefix(baseUrl + "/search/photos")
            || trimmed.hasPrefix(baseUrl + "/albums")
    }

    private static func normalizeThemeLabel(_ value: String) -> String {
        if value.contains("熱門成人主題") || value.contains("热门成人主题") { return "热门" }
        if value.contains("類別") || value.contains("类别") { return "类别" }
        if value.contains("漫畫排行榜") || value.contains("漫画排行榜") { return "排行榜" }
        if value.contains("主題A漫") || value.contains("主题A漫") { return "主题" }
        if value.contains("角色") && value.contains("扮演") { return "角色" }
        if value.uppercased().contains("PLAY") { return "特殊" }
        return value
    }

    private static func cleanMarkup(_ value: String) -> String {
        let stripped = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeEntities(stripped).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rawComicId(_ value: String) -> String {
        var str = value
        if str.hasPrefix(Self.prefix) { str = String(str.dropFirst(Self.prefix.count)) }
        return firstMatch(#"(?:/album/)?(\d+)"#, in: str)
    }

    private func meta(_ html: String, key: String) -> String {
        let tags = Self.matches(#"<meta\b[^>]*>"#, in: html)
        for tagMatch in tags {
            guard let tag = tagMatch.first else { continue }
            if key.caseInsensitiveCompare(attribute("property", in: tag)) == .orderedSame ||
               key.caseInsensitiveCompare(attribute("name", in: tag)) == .orderedSame {
                return clean(attribute("content", in: tag))
            }
        }
        return ""
    }

    private func clean(_ value: String) -> String {
        Self.cleanMarkup(value)
    }

    private func cleanMarkup(_ value: String) -> String {
        Self.cleanMarkup(value)
    }

    private func attribute(_ name: String, in tag: String) -> String {
        Self.attribute(name, in: tag)
    }

    private func absolute(_ value: String) -> String {
        Self.absolute(baseUrl: config.baseUrl, value: value)
    }

    private static func absolute(baseUrl: String, value: String) -> String {
        let trimmed = decodeEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.hasPrefix("//") { return "https:" + trimmed }
        let cleanBase = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        return cleanBase + (trimmed.hasPrefix("/") ? trimmed : "/" + trimmed)
    }

    private func toURL(_ value: String) throws -> URL {
        let abs = absolute(value)
        guard let url = URL(string: abs) else { throw JmSourceError.invalidURL(abs) }
        return url
    }

    private static func trimSlash(_ value: String) -> String {
        var str = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while str.hasSuffix("/") { str.removeLast() }
        return str
    }

    private static func decodeEntities(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func attribute(_ name: String, in tag: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b"# + escaped + #"\s*=\s*(["'])([\s\S]*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              match.numberOfRanges > 2,
              let r2 = Range(match.range(at: 2), in: tag) else { return "" }
        return decodeEntities(String(tag[r2]))
    }

    private func firstMatch(_ pattern: String, in text: String) -> String {
        Self.firstMatch(pattern, in: text)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return "" }
        let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard targetRange.location != NSNotFound, let r = Range(targetRange, in: text) else { return "" }
        return String(text[r])
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let nsText = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return results.map { match in
            (0..<match.numberOfRanges).map { idx in
                let r = match.range(at: idx)
                return r.location != NSNotFound ? nsText.substring(with: r) : ""
            }
        }
    }
}
