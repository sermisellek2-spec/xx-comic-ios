import Foundation

/// Guazi's public desktop pages (1:1 with Android GuaziComicSource.java), with reader images scoped to the article body.
public final class GuaziComicSource: ComicSource, @unchecked Sendable {
    public let id: String
    public let name: String
    public let domain: String
    public let referer: String
    private let baseURL: String
    private let config: SourceConfigItem
    private let transport: any HTTPTransport

    private let cacheLock = NSLock()
    private var directoryOrder: [String] = []
    private var directoryCache: [String: String] = [:]

    private static let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    public init(
        config: SourceConfigItem = SourceConfigDefaults.guazi(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25)
    ) {
        self.config = config
        self.id = config.id.isEmpty ? "guazi" : config.id
        self.name = config.name.isEmpty ? "瓜子漫画" : config.name
        self.domain = config.domain.isEmpty ? "www.guazimanhua.com" : config.domain
        let rawBase = config.baseUrl.isEmpty ? "https://www.guazimanhua.com" : config.baseUrl
        let cleanBase = rawBase.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        self.baseURL = cleanBase
        self.referer = config.referer.isEmpty ? (cleanBase + "/") : config.referer
        self.transport = transport
    }

    public func userAgent() -> String {
        Self.desktopUA
    }

    public var categories: [String] {
        ["恋爱", "校园", "都市", "玄幻", "冒险", "热血"]
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let route = config.route("latest").isEmpty ? "/category.php?sort=update&page={page}" : config.route("latest")
        let path = route.replacingOccurrences(of: "{page}", with: Self.page(page))
        return try parseCards(try await get(absolute(path)))
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let trimmed = SearchRules.trim(keyword)
        guard !trimmed.isEmpty else { return [] }
        let route = config.route("search").isEmpty ? "/category.php?keyword={keyword}&page={page}" : config.route("search")
        let path = route
            .replacingOccurrences(of: "{keyword}", with: Self.formEncode(trimmed))
            .replacingOccurrences(of: "{page}", with: Self.page(page))
        return try parseCards(try await get(absolute(path)))
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        Self.staticFilterGroups()
    }

    private static func staticFilterGroups() -> [SourceFilterGroup] {
        [
            group("city", "地区", "全部", "0", "大陆", "42", "欧美", "43", "港台", "77", "日韩", "78", "国漫", "338"),
            group("cid", "题材", "全部", "0", "耽美", "41", "恋爱", "9", "校园", "29", "霸总", "5", "都市", "42", "穿越", "8", "古风", "23", "玄幻", "25", "奇幻", "31", "科幻", "22", "灵异", "21", "动作", "54", "悬疑", "11", "冒险", "30", "搞笑", "15", "热血", "13", "恐怖", "14", "系统", "148", "逆袭", "97", "脑洞", "55", "复仇", "61"),
            group("audience", "受众", "全部", "0", "男频", "1", "女频", "2"),
            group("is_end", "状态", "全部", "0", "连载中", "2", "已完结", "1"),
            group("sort", "排序", "更新", "update", "人气", "hits", "今日热门", "daily", "评分", "score")
        ]
    }

    private static func group(_ key: String, _ title: String, _ pairs: String...) -> SourceFilterGroup {
        var list: [SourceFilterOption] = []
        var i = 0
        while i + 1 < pairs.count {
            list.append(.init(label: pairs[i], value: pairs[i + 1]))
            i += 2
        }
        return .init(key: key, label: title, options: list)
    }

    public func category(region: String, state: String, page: Int) async throws -> [ComicSummary] {
        try await category(filters: ["city": region, "is_end": state], page: page)
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let route = config.route("category").isEmpty ? "/category.php?page={page}" : config.route("category")
        var path = route.replacingOccurrences(of: "{page}", with: Self.page(page))
        for grp in Self.staticFilterGroups() {
            let value = filters[grp.key]
            var selected = grp.options.first?.value ?? "0"
            if let value, grp.options.contains(where: { $0.value == value }) {
                selected = value
            }
            path += "&\(grp.key)=\(Self.formEncode(selected))"
        }
        return try parseCards(try await get(absolute(path)))
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let raw = try Self.validateId(comicId, sourceId: id)
        let route = config.route("detail").isEmpty ? "/comic.php?id={comicId}" : config.route("detail")
        let html = try await get(absolute(route.replacingOccurrences(of: "{comicId}", with: raw)))
        let title = Self.textClass(html, tag: "div", cssClass: "mobile-comic-title")
        guard !title.isEmpty else {
            throw Self.sourceError("瓜子漫画详情未返回漫画信息")
        }
        let cover = Self.imageClass(html, cssClass: "mobile-comic-cover")
        let author = Self.stripValue(html, label: "作者")
        let latest = Self.stripValue(html, label: "最新")
        let tagsStr = Self.textClass(html, tag: "p", cssClass: "mobile-comic-tags")
        let meta = Self.textClass(html, tag: "p", cssClass: "mobile-comic-meta")
        let status = meta.contains("完结") ? "完结" : meta.contains("连载") ? "连载中" : ""
        let tags = tagsStr.isEmpty ? [] : tagsStr.components(separatedBy: CharacterSet(charactersIn: "/·"))
        let summary = ComicSummary(
            sourceId: id,
            comicId: id + ":" + raw,
            title: title,
            coverUrl: absolute(cover),
            subtitle: author,
            tags: tags,
            latestChapter: latest
        )
        putDirectoryCache(id: raw, html: html)
        return .init(
            summary: summary,
            author: author,
            status: status,
            description: Self.textClass(html, tag: "p", cssClass: "mobile-comic-desc"),
            latestChapter: latest,
            chapters: []
        )
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let raw = try Self.validateId(comicId, sourceId: id)
        let html: String
        if let cached = removeDirectoryCache(id: raw) {
            html = cached
        } else {
            let route = config.route("detail").isEmpty ? "/comic.php?id={comicId}" : config.route("detail")
            html = try await get(absolute(route.replacingOccurrences(of: "{comicId}", with: raw)))
        }
        var result: [Chapter] = []
        var seen = Set<String>()
        let chapterRoute = config.route("chapter").isEmpty ? "/chapter.php?id={chapterId}" : config.route("chapter")
        for section in Self.elementsByClass(html, tag: "section", cssClass: "mobile-comic-all-chapters") {
            for grid in Self.elementsByClass(section, tag: "div", cssClass: "mobile-chapter-grid") {
                for a in Self.elements(grid, tag: "a") {
                    let href = Self.attribute(Self.firstTagOpening(a, tag: "a"), name: "href")
                    let chapter = Self.queryId(href, page: "chapter")
                    guard !chapter.isEmpty, seen.insert(chapter).inserted else { continue }
                    let chapterUrl = absolute(chapterRoute.replacingOccurrences(of: "{chapterId}", with: chapter))
                    result.append(.init(
                        chapterId: chapter,
                        title: Self.clean(a),
                        url: chapterUrl,
                        sectionSlot: 0,
                        chapterSlot: result.count
                    ))
                }
            }
        }
        guard !result.isEmpty else {
            throw Self.sourceError("瓜子漫画暂无可读章节，可能是新上架的空目录条目")
        }
        result.reverse()
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let chapterId = Self.queryId(url, page: "chapter")
        guard !chapterId.isEmpty else {
            throw Self.sourceError("瓜子漫画章节地址无效")
        }
        let chapterRoute = config.route("chapter").isEmpty ? "/chapter.php?id={chapterId}" : config.route("chapter")
        let resolvedUrl = absolute(chapterRoute.replacingOccurrences(of: "{chapterId}", with: chapterId))
        let html = try await get(resolvedUrl, referer: referer)
        var images: [String] = []
        var seen = Set<String>()
        for section in Self.elementsByClass(html, tag: "section", cssClass: "reader-images") {
            for img in Self.imageUrls(section, baseURL: resolvedUrl) {
                if seen.insert(img).inserted {
                    images.append(img)
                }
            }
        }
        guard !images.isEmpty else {
            throw Self.sourceError("瓜子漫画章节未返回正文图片，请稍后重试")
        }
        let title = Self.clean(Self.first(html, #"<title[^>]*>([\s\S]*?)</title>"#))
        return .init(chapterId: chapterId, title: title, nextPageUrl: "", imageUrls: images)
    }

    public func healthCheck() async -> Bool {
        do {
            return !(try await latest(page: 1)).isEmpty
        } catch {
            return false
        }
    }

    func parseCards(_ html: String) throws -> [ComicSummary] {
        var result: [ComicSummary] = []
        var seen = Set<String>()
        for card in Self.elementsByClass(html, tag: "article", cssClass: "card") {
            let heading = Self.firstTag(card, tag: "h3")
            let href = Self.attribute(Self.firstTagOpening(heading, tag: "a"), name: "href")
            let cid = Self.queryId(href, page: "comic")
            guard !cid.isEmpty, seen.insert(cid).inserted else { continue }
            let title = Self.clean(heading)
            let cover = Self.imageClass(card, cssClass: "cover")
            let meta = Self.textClass(card, tag: "div", cssClass: "meta")
            guard !title.isEmpty else { continue }
            result.append(.init(
                sourceId: id,
                comicId: id + ":" + cid,
                title: title,
                coverUrl: cover.isEmpty ? "" : absolute(cover),
                subtitle: meta,
                tags: []
            ))
        }
        if result.isEmpty && !html.contains("category") && !html.contains("暂无") && !html.contains("没有") {
            throw Self.sourceError("瓜子漫画列表未返回有效页面")
        }
        return result
    }

    // MARK: - Cache Helpers

    private func putDirectoryCache(id: String, html: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let idx = directoryOrder.firstIndex(of: id) {
            directoryOrder.remove(at: idx)
        }
        directoryOrder.append(id)
        directoryCache[id] = html
        while directoryOrder.count > 4 {
            let evicted = directoryOrder.removeFirst()
            directoryCache.removeValue(forKey: evicted)
        }
    }

    private func removeDirectoryCache(id: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let idx = directoryOrder.firstIndex(of: id) {
            directoryOrder.remove(at: idx)
        }
        return directoryCache.removeValue(forKey: id)
    }

    // MARK: - HTTP & HTML Helpers

    private func get(_ url: String, referer: String? = nil) async throws -> String {
        try await readRequest(url: url, referer: referer ?? self.referer)
    }

    private func readRequest(url: String, referer: String) async throws -> String {
        do {
            return try await performRequest(url: url, referer: referer)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let urlError = error as? URLError,
               [.networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(urlError.code) {
                return try await performRequest(url: url, referer: referer)
            }
            throw error
        }
    }

    private func performRequest(url: String, referer: String) async throws -> String {
        try Task.checkCancellation()
        guard let targetURL = URL(string: url), ["http", "https"].contains(targetURL.scheme?.lowercased() ?? "") else {
            throw URLError(.badURL)
        }
        var headers: [String: String] = [
            "User-Agent": userAgent(),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.6",
            "Accept-Encoding": "gzip",
            "Connection": "close"
        ]
        if !referer.isEmpty { headers["Referer"] = referer }
        let response = try await transport.get(targetURL, headers: headers)
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

    private static func validateId(_ comicId: String, sourceId: String) throws -> String {
        let trimmed = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = sourceId + ":"
        let raw = trimmed.hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
        guard raw.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            throw sourceError("瓜子漫画 ID 无效")
        }
        return raw
    }

    private static func page(_ page: Int) -> String {
        String(max(1, page))
    }

    private static func queryId(_ url: String, page: String) -> String {
        let normalized = url.replacingOccurrences(of: "&amp;", with: "&")
        let pattern = "(?:^|/)" + NSRegularExpression.escapedPattern(for: page) + #"\.php\?[^#]*?\bid=([0-9]+)(?:[&#]|$)"#
        return first(normalized, pattern)
    }

    private static func textClass(_ html: String, tag: String, cssClass: String) -> String {
        let elements = elementsByClass(html, tag: tag, cssClass: cssClass)
        return elements.first.map(clean) ?? ""
    }

    private static func imageClass(_ html: String, cssClass: String) -> String {
        let elements = elementsByClass(html, tag: "img", cssClass: cssClass)
        guard let firstImg = elements.first else { return "" }
        return firstNonEmpty(attribute(firstImg, name: "data-src"), attribute(firstImg, name: "src"))
    }

    private static func stripValue(_ html: String, label: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"<span[^>]*>\s*"# + escaped + #"\s*</span>\s*<b[^>]*>([\s\S]*?)</b>"#
        for strip in elementsByClass(html, tag: "div", cssClass: "cinema-strip") {
            let value = first(strip, pattern)
            if !value.isEmpty {
                return clean(value)
            }
        }
        return ""
    }

    private static func firstTag(_ source: String, tag: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        return first(source, "<" + escaped + #"\b[^>]*>([\s\S]*?)</"# + escaped + #"\s*>"#)
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

    private static func elements(_ html: String, tag: String) -> [String] {
        guard !html.isEmpty,
              let tokenRegex = try? NSRegularExpression(pattern: "</?" + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#, options: .caseInsensitive) else {
            return []
        }
        var result: [String] = []
        let allMatches = tokenRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var idx = 0
        while idx < allMatches.count {
            guard let openRange = Range(allMatches[idx].range, in: html) else {
                idx += 1
                continue
            }
            let opening = String(html[openRange])
            if opening.hasPrefix("</") {
                idx += 1
                continue
            }
            if opening.hasSuffix("/>") {
                result.append(opening)
                idx += 1
                continue
            }
            var depth = 1
            var j = idx + 1
            var endIdx: String.Index?
            while j < allMatches.count {
                if let tokenRange = Range(allMatches[j].range, in: html) {
                    let current = html[tokenRange]
                    if current.hasPrefix("</") {
                        depth -= 1
                    } else if !current.hasSuffix("/>") {
                        depth += 1
                    }
                    if depth == 0 {
                        endIdx = tokenRange.upperBound
                        break
                    }
                }
                j += 1
            }
            guard let end = endIdx else { break }
            result.append(String(html[openRange.lowerBound..<end]))
            idx = j + 1
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
            if url.hasPrefix("//") {
                url = "https:" + url
            } else if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                if let base = URL(string: baseURL), let resolved = URL(string: url, relativeTo: base)?.absoluteURL {
                    url = resolved.absoluteString
                }
            }
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

    private static func firstNonEmpty(_ values: String...) -> String {
        for v in values {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private static func formEncode(_ value: String) -> String {
        value.utf8.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 46, 95, 42].contains(byte) {
                return String(UnicodeScalar(byte))
            }
            return byte == 32 ? "+" : String(format: "%%%02X", byte)
        }.joined()
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

    private static func sourceError(_ message: String) -> NSError {
        NSError(domain: "GuaziComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
