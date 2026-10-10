import Foundation
#if os(macOS) || os(iOS)
import CoreFoundation
#endif

public enum Hanman18SourceError: Error, Equatable, Sendable {
    case invalidURL(String)
    case invalidResponse(String)
}

extension Hanman18SourceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url): return "无效地址: \(url)"
        case let .invalidResponse(msg): return msg
        }
    }
}

public struct Hanman18ComicSource: ComicSource {
    public let id = "hanman18"
    public let name: String
    public let referer: String
    public let domain: String

    private static let sourceID = "hanman18"
    private static let prefix = "hanman18:"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    private static let cardPattern = #"<a[^>]+href=[\"']([^\"']*/manhwa/[^\"']+)[\"'][\s\S]{0,900}?<img([^>]*)>[\s\S]{0,900}?(?:<h[23][^>]*>|class=[\"'][^\"']*(?:title|name)[^\"']*[\"'][^>]*>)([\s\S]*?)(?:</h[23]>|</[^>]+>)"#
    private static let metaPattern = #"<meta[^>]+(?:property|name)=[\"']([^\"']+)[\"'][^>]+content=[\"']([^\"']*)[\"']"#
    private static let chapterPattern = #"<a[^>]+href=[\"']([^\"']*/manhwa/[^\"']+)[\"'][^>]*class=[\"']chapter_num[\"'][^>]*>([\s\S]*?)</a>"#
    private static let imgTagPattern = #"<img\b[^>]*>"#
    private static let slidesArrayPattern = #"slides_p_path\s*=\s*\[([\s\S]*?)\]"#
    private static let slidesTokenPattern = #"[\"']([A-Za-z0-9+/=]+)[\"']"#

    private let config: SourceConfigItem
    private let transport: any HTTPTransport

    public init(
        config: SourceConfigItem = SourceConfigDefaults.hanman18(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 20)
    ) {
        self.config = config
        self.name = config.name
        self.domain = config.domain.isEmpty ? "hanman18.com" : config.domain
        self.referer = config.referer.isEmpty ? "https://hanman18.com/" : config.referer
        self.transport = transport
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let url = listUrl(page)
        let html = try await fetch(url)
        return try requireCards(Self.parseCards(html))
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        guard page <= 1 else { return [] }
        let trimmed = SearchRules.trim(keyword)
        guard !trimmed.isEmpty else { return [] }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let path = config.route("search").replacingOccurrences(of: "{keyword}", with: encoded)
        let jsonString = try await fetch(absolute(path))
        guard let data = jsonString.data(using: .utf8) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["data"] as? [[String: Any]] else {
            return Self.parseCards(jsonString)
        }
        var result: [ComicSummary] = []
        var seen = Set<String>()
        for item in list {
            let name = item["name"] as? String ?? ""
            let title = clean(name)
            guard !title.isEmpty else { continue }
            var primary = Self.rawComicId(item["slug"] as? String ?? "")
            let pinyin = Self.pinyinSlug(name)
            if primary.isEmpty { primary = pinyin }
            guard !primary.isEmpty, seen.insert(primary).inserted else { continue }
            let rawId = (!pinyin.isEmpty && pinyin.caseInsensitiveCompare(primary) != .orderedSame)
                ? primary + "|" + pinyin : primary
            let other = clean(item["otherNames"] as? String ?? "")
            result.append(ComicSummary(
                sourceId: Self.sourceID,
                comicId: Self.prefix + rawId,
                title: title,
                coverUrl: "",
                subtitle: other,
                tags: []
            ))
        }
        return result
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        [
            SourceFilterGroup(
                key: "audience",
                label: "受众",
                options: [
                    SourceFilterOption(label: "全部", value: "all"),
                    SourceFilterOption(label: "受欢迎的", value: "popular")
                ]
            )
        ]
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        if filters["audience"] == "popular" {
            guard page <= 1 else { return [] }
            let homeRoute = config.route("home").isEmpty ? "/" : config.route("home")
            let html = try await fetch(absolute(homeRoute))
            return Self.parsePopular(html)
        }
        return try await latest(page: page)
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        try Task.checkCancellation()
        let rawId = Self.rawComicId(comicId)
        let html = try await fetchDetailHtml(rawId)
        var title = clean(Self.meta(html, key: "og:title"))
        if title.isEmpty { title = clean(Self.firstMatch(#"<h1[^>]*>([\s\S]*?)</h1>"#, in: html)) }
        guard !title.isEmpty else { throw Hanman18SourceError.invalidResponse("Hanman18 详情解析失败：缺少标题") }
        var cover = cleanUrl(Self.meta(html, key: "og:image"))
        if cover.isEmpty { cover = Self.imageUrlFromTag(Self.firstRaw(#"<img\b[^>]*>"#, in: html)) }
        var description = clean(Self.meta(html, key: "og:description"))
        if description.isEmpty {
            description = clean(Self.firstMatch(#"<div[^>]+class=[\"'][^\"']*(?:summary|desc|intro)[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#, in: html))
        }
        let summary = ComicSummary(
            sourceId: Self.sourceID,
            comicId: Self.prefix + rawId,
            title: title,
            coverUrl: cover,
            subtitle: "",
            tags: []
        )
        return ComicDetail(summary: summary, author: "", status: "", description: description, latestChapter: "", chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        try Task.checkCancellation()
        let primary = Self.rawComicId(comicId)
        var chs = try await parseChapters(primary)
        if chs.isEmpty {
            let fallback = pinyinFallbackSlug(comicId)
            if !fallback.isEmpty && fallback.caseInsensitiveCompare(primary) != .orderedSame {
                chs = try await parseChapters(fallback)
            }
        }
        return chs
    }

    public func chapter(url: String) async throws -> ChapterPage {
        try Task.checkCancellation()
        let absoluteUrl = absolute(url)
        let html = try await fetch(absoluteUrl)
        let title = clean(Self.firstMatch(#"<h1[^>]*>([\s\S]*?)</h1>"#, in: html))
        var images = Self.extractSlideImages(html)
        if images.isEmpty {
            var seen = Set<String>()
            let tags = Self.matches(Self.imgTagPattern, in: html)
            for tagMatch in tags {
                guard let tag = tagMatch.first else { continue }
                let imgUrl = Self.imageUrlFromTag(tag)
                if Self.isReaderImage(imgUrl) && seen.insert(imgUrl).inserted {
                    images.append(imgUrl)
                }
            }
        }
        guard !images.isEmpty else {
            throw Hanman18SourceError.invalidResponse("Hanman18 章节图片列表为空: \(url)")
        }
        return ChapterPage(chapterId: absoluteUrl, title: title, nextPageUrl: "", imageUrls: images)
    }

    public func healthCheck() async -> Bool {
        do {
            let list = try await latest(page: 1)
            return !list.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Parsing & Static Helpers

    public static func parseCards(_ html: String) -> [ComicSummary] {
        var result: [ComicSummary] = []
        var seen = Set<String>()
        let cardMatches = matches(cardPattern, in: html)
        for m in cardMatches {
            guard m.count > 3 else { continue }
            let href = cleanUrl(m[1])
            let rawId = rawComicId(href)
            let title = clean(m[3])
            guard !rawId.isEmpty, !title.isEmpty, seen.insert(rawId).inserted else { continue }
            let cover = imageUrlFromTag("<img " + m[2] + ">")
            result.append(ComicSummary(
                sourceId: sourceID,
                comicId: prefix + rawId,
                title: title,
                coverUrl: cover,
                subtitle: "",
                tags: []
            ))
        }
        return result
    }

    public static func parsePopular(_ html: String) -> [ComicSummary] {
        let body = html.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: " ", options: .regularExpression)
        guard let section = firstMatch(#"<h5[^>]*>受欢迎的</h5>([\s\S]*?)(?=<h5[^>]*>|$)"#, in: body).nilIfEmpty else {
            return parseStoryItems(body)
        }
        return parseStoryItems(section)
    }

    private static func parseStoryItems(_ scope: String) -> [ComicSummary] {
        var result: [ComicSummary] = []
        var seen = Set<String>()
        let items = matches(#"<div class=\"story_item\"[\s\S]*?(?=<div class=\"story_item\"|$)"#, in: scope)
        for itemMatch in items {
            guard let block = itemMatch.first else { continue }
            let aMatch = matches(#"<a[^>]+href=[\"']([^\"']*/manhwa/[^\"']+)[\"'][^>]*title=[\"']([^\"']*)[\"']"#, in: block)
            guard let firstA = aMatch.first, firstA.count > 2 else { continue }
            let title = clean(firstA[2])
            guard !title.isEmpty else { continue }
            var primary = rawComicId(firstA[1])
            let pinyin = pinyinSlug(firstA[2])
            if primary.isEmpty { primary = pinyin }
            guard !primary.isEmpty, seen.insert(primary).inserted else { continue }
            let rawId = (!pinyin.isEmpty && pinyin.caseInsensitiveCompare(primary) != .orderedSame) ? primary + "|" + pinyin : primary
            let cover = imageUrlFromTag(firstRaw(#"<img\b[^>]*>"#, in: block))
            let time = clean(firstMatch(#"<span>([^<]+)</span>"#, in: block))
            result.append(ComicSummary(
                sourceId: sourceID,
                comicId: prefix + rawId,
                title: title,
                coverUrl: cover,
                subtitle: time,
                tags: []
            ))
        }
        return result
    }

    public static func extractSlideImages(_ html: String) -> [String] {
        let arrayMatches = matches(slidesArrayPattern, in: html)
        for arrMatch in arrayMatches {
            guard arrMatch.count > 1 else { continue }
            var images: [String] = []
            var seen = Set<String>()
            let tokens = matches(slidesTokenPattern, in: arrMatch[1])
            for tokenMatch in tokens {
                guard tokenMatch.count > 1 else { continue }
                let image = decodeBase64(tokenMatch[1])
                if !image.isEmpty, image.hasPrefix("http"), seen.insert(image).inserted {
                    images.append(image)
                }
            }
            if !images.isEmpty { return images }
        }
        return []
    }

    private func requireCards(_ cards: [ComicSummary]) throws -> [ComicSummary] {
        guard !cards.isEmpty else {
            throw Hanman18SourceError.invalidResponse(name + " 漫画列表解析失败")
        }
        return cards
    }

    private func fetchDetailHtml(_ rawId: String) async throws -> String {
        let url = absolute(config.route("detail").replacingOccurrences(of: "{comicId}", with: rawId))
        let html = try await fetch(url)
        let canonical = Self.resolveCanonicalSlug(html)
        if canonical.isEmpty || canonical.caseInsensitiveCompare(rawId) == .orderedSame {
            return html
        }
        let resolvedUrl = absolute(config.route("detail").replacingOccurrences(of: "{comicId}", with: canonical))
        if resolvedUrl == url { return html }
        return try await fetch(resolvedUrl)
    }

    private static func resolveCanonicalSlug(_ html: String) -> String {
        let ogUrl = slugFromUrl(meta(html, key: "og:url"))
        if !ogUrl.isEmpty { return ogUrl }
        let canonicalLink = firstRaw(#"<link[^>]+rel=[\"']canonical[\"'][^>]*>"#, in: html)
        let href = attr("href", in: canonicalLink)
        let slug = slugFromUrl(href)
        if !slug.isEmpty { return slug }
        let refresh = firstRaw(#"<meta[^>]+http-equiv=[\"']refresh[\"'][^>]*>"#, in: html)
        let content = attr("content", in: refresh)
        if !content.isEmpty {
            let m = firstMatch(#"url=([^\"'\s]+)"#, in: content)
            let s = slugFromUrl(m)
            if !s.isEmpty { return s }
        }
        let loc = firstMatch(#"location(?:\.href|\.replace)?\s*[=(]\s*[\"']([^\"']+)[\"']"#, in: html)
        if !loc.isEmpty {
            let s = slugFromUrl(loc)
            if !s.isEmpty { return s }
        }
        return ""
    }

    private static func slugFromUrl(_ url: String) -> String {
        guard let range = url.range(of: "/manhwa/") else { return "" }
        var tail = String(url[range.upperBound...])
        if let idx = tail.firstIndex(of: "?") { tail = String(tail[..<idx]) }
        if let idx = tail.firstIndex(of: "#") { tail = String(tail[..<idx]) }
        if let idx = tail.firstIndex(of: "/") { tail = String(tail[..<idx]) }
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseChapters(_ slug: String) async throws -> [Chapter] {
        let html = try await fetchDetailHtml(slug)
        var block = Self.firstRaw(#"<div[^>]+class=[\"']chapter_box[\"'][\s\S]*?</ul>\s*</div>"#, in: html)
        if block.isEmpty { block = html }
        var chapters: [Chapter] = []
        var seen = Set<String>()
        let chapterMatches = Self.matches(Self.chapterPattern, in: block)
        var index = 0
        for m in chapterMatches {
            guard m.count > 2 else { continue }
            let href = Self.cleanUrl(m[1])
            let title = Self.clean(m[2])
            guard !href.isEmpty, !title.isEmpty, seen.insert(href).inserted else { continue }
            chapters.append(Chapter(
                chapterId: Self.rawChapterId(href),
                title: title,
                url: absolute(href),
                sectionSlot: 0,
                chapterSlot: index
            ))
            index += 1
        }
        return chapters
    }

    private func pinyinFallbackSlug(_ value: String) -> String {
        var raw = Self.decode(value)
        if raw.hasPrefix(Self.prefix) { raw = String(raw.dropFirst(Self.prefix.count)) }
        guard let pipeIdx = raw.firstIndex(of: "|") else { return "" }
        var fallback = String(raw[raw.index(after: pipeIdx)...])
        if let slashIdx = fallback.firstIndex(of: "/") { fallback = String(fallback[..<slashIdx]) }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rawComicId(_ value: String) -> String {
        var raw = decode(value)
        if raw.hasPrefix(prefix) { raw = String(raw.dropFirst(prefix.count)) }
        if let manhwa = raw.range(of: "/manhwa/") { raw = String(raw[manhwa.upperBound...]) }
        if let slash = raw.firstIndex(of: "/") { raw = String(raw[..<slash]) }
        if let pipe = raw.firstIndex(of: "|") { raw = String(raw[..<pipe]) }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rawChapterId(_ value: String) -> String {
        var raw = decode(value)
        if let q = raw.firstIndex(of: "?") { raw = String(raw[..<q]) }
        while raw.hasSuffix("/") { raw.removeLast() }
        if let lastSlash = raw.lastIndex(of: "/") {
            return String(raw[raw.index(after: lastSlash)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pinyinSlug(_ name: String) -> String {
        #if os(macOS) || os(iOS)
        let mutable = NSMutableString(string: name) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let str = (mutable as String).lowercased()
        return str.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
        #else
        return name.lowercased().filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
        #endif
    }

    private static func imageUrlFromTag(_ tag: String) -> String {
        var url = attr("data-src", in: tag)
        if url.isEmpty { url = attr("data-original", in: tag) }
        if url.isEmpty { url = attr("data-lazy-src", in: tag) }
        if url.isEmpty { url = attr("src", in: tag) }
        return cleanUrl(url)
    }

    private static func isReaderImage(_ url: String) -> Bool {
        guard !url.isEmpty else { return false }
        let lower = url.lowercased()
        guard lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") || lower.contains(".webp") else {
            return false
        }
        return !lower.contains("logo") && !lower.contains("avatar") && !lower.contains("cover") && !lower.contains("banner")
    }

    private func listUrl(_ page: Int) -> String {
        let pagePath = page <= 1 ? "" : "/\(page)"
        let route = config.route("latest")
            .replacingOccurrences(of: "{pagePath}", with: pagePath)
            .replacingOccurrences(of: "{page}", with: String(page))
        return absolute(route)
    }

    private func fetch(_ urlString: String) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: urlString) else {
            throw Hanman18SourceError.invalidURL(urlString)
        }
        let response = try await transport.get(url, headers: [
            "User-Agent": Self.userAgent,
            "Referer": referer,
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ])
        try Task.checkCancellation()
        guard (200..<400).contains(response.statusCode) else {
            throw HTTPTransportError.invalidStatusCode(response.statusCode)
        }
        guard let body = String(data: response.data, encoding: .utf8) else {
            throw Hanman18SourceError.invalidResponse("响应不是有效 UTF-8")
        }
        return body
    }

    private func absolute(_ value: String) -> String {
        let trimmed = Self.decode(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.hasPrefix("//") { return "https:" + trimmed }
        let cleanBase = config.baseUrl.hasSuffix("/") ? String(config.baseUrl.dropLast()) : config.baseUrl
        return cleanBase + (trimmed.hasPrefix("/") ? trimmed : "/" + trimmed)
    }

    private func clean(_ value: String) -> String {
        Self.clean(value)
    }

    private static func clean(_ value: String) -> String {
        let stripped = value.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decode(stripped).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\/", with: "/")
    }

    private func cleanUrl(_ value: String) -> String {
        Self.cleanUrl(value)
    }

    private static func cleanUrl(_ value: String) -> String {
        var str = decode(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = str.firstIndex(of: "\"") { str = String(str[..<q]) }
        if let s = str.firstIndex(of: " ") { str = String(str[..<s]) }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeBase64(_ value: String) -> String {
        guard let data = Data(base64Encoded: value) else { return "" }
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func meta(_ html: String, key: String) -> String {
        let tags = matches(metaPattern, in: html)
        for tagMatch in tags {
            guard tagMatch.count > 2 else { continue }
            if tagMatch[1].caseInsensitiveCompare(key) == .orderedSame {
                return clean(tagMatch[2])
            }
        }
        return ""
    }

    private static func attr(_ name: String, in html: String) -> String {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*[\"']([^\"']*)[\"']"#
        return firstMatch(pattern, in: html)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return "" }
        let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard targetRange.location != NSNotFound, let r = Range(targetRange, in: text) else { return "" }
        return String(text[r])
    }

    private static func firstRaw(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(match.range(at: 0), in: text) else { return "" }
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
