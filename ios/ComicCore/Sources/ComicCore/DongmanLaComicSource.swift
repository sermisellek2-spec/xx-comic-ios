import Foundation

/// HTML adapter for 动漫啦 (dongmanla), 1:1 with Android DongmanLaComicSource.java.
/// Chapter URLs use its all.html reader to return every page image.
public actor DongmanLaComicSource: ComicSource {
    public nonisolated let id: String
    public nonisolated let name: String
    public nonisolated let domain: String
    public nonisolated let referer: String
    private let baseURL: String
    private let config: SourceConfigItem
    private let transport: any HTTPTransport
    private var homeSnapshot: [ComicSummary]?
    // Reuse detail HTML for lazy directory parsing without a second network request (bounded to 4 entries).
    private var pendingDirectoryKeys: [String] = []
    private var pendingDirectoryHtml: [String: String] = [:]

    private static let defaultUA = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    private static let categories: [(String, String)] = [
        ("全部", "all"), ("日本漫画", "jp"), ("港台漫画", "hk"), ("欧美漫画", "west"),
        ("国产漫画", "cn"), ("韩国漫画", "kr"), ("完结", "finish"), ("连载中", "serial"),
        ("腐漫", "genre.83"), ("生活", "genre.82"), ("脑洞", "genre.81"), ("扶她", "genre.62"),
        ("武侠", "genre.56"), ("东方", "genre.53"), ("音乐舞蹈", "genre.52"), ("少年", "genre.49"),
        ("青年", "genre.48"), ("机战", "genre.47"), ("侦探", "genre.46"), ("职场", "genre.45"),
        ("颜艺", "genre.44"), ("少女", "genre.43"), ("治愈", "genre.42"), ("性转换", "genre.41"),
        ("亲情", "genre.40"), ("节操", "genre.39"), ("百合", "genre.38"), ("萌系", "genre.37"),
        ("四格", "genre.36"), ("美食", "genre.35"), ("魔幻", "genre.34"), ("后宫", "genre.33"),
        ("热血", "genre.32"), ("宅腐", "genre.31"), ("战争", "genre.30"), ("历史", "genre.29"),
        ("耽美", "genre.27"), ("伪娘", "genre.26"), ("搞笑", "genre.25"), ("爱情", "genre.24"),
        ("神鬼", "genre.23"), ("魔法", "genre.22"), ("奇幻", "genre.21"), ("悬疑", "genre.20"),
        ("恐怖", "genre.19"), ("校园", "genre.18"), ("竞技", "genre.17"), ("格斗", "genre.16")
    ]

    public init(
        config: SourceConfigItem = SourceConfigDefaults.dongmanla(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25)
    ) {
        self.config = config
        self.id = config.id.isEmpty ? "dongmanla" : config.id
        self.name = config.name.isEmpty ? "动漫啦" : config.name
        self.domain = config.domain.isEmpty ? "www.dongman.la" : config.domain
        let rawBase = config.baseUrl.isEmpty ? "https://www.dongman.la" : config.baseUrl
        let cleanBase = rawBase.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        self.baseURL = cleanBase
        self.referer = config.referer.isEmpty ? (cleanBase + "/") : config.referer
        self.transport = transport
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let latestRoute = config.route("latest").isEmpty ? "/manhua/" : config.route("latest")
        if latestRoute == "/manhua/" {
            // The home document contains regional sections, not /manhua/2.html.
            if page <= 1 || homeSnapshot == nil {
                homeSnapshot = Self.parseCards(try await get(absolute(latestRoute)), sourceId: id)
            }
            guard let snap = homeSnapshot else { return [] }
            let start = (max(1, page) - 1) * 24
            guard start < snap.count else { return [] }
            let end = min(start + 24, snap.count)
            return Array(snap[start..<end])
        }
        let url = pageURL(absolute(latestRoute), page: page)
        return Self.parseCards(try await get(url), sourceId: id)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let trimmed = SearchRules.trim(keyword)
        guard !trimmed.isEmpty else { return [] }
        let route = config.route("search").isEmpty ? "/manhua/so/{keyword}/{page}.html" : config.route("search")
        let path = route
            .replacingOccurrences(of: "{keyword}", with: Self.formEncode(trimmed))
            .replacingOccurrences(of: "{page}", with: String(max(1, page)))
        return Self.parseCards(try await get(absolute(path)), sourceId: id)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let options = Self.categories.map { SourceFilterOption(label: $0.0, value: $0.1) }
        return [.init(key: "category", label: "分类", options: options)]
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let selected = Self.firstNonEmpty(filters["category"] ?? "", filters["region"] ?? "", "all")
        if selected == "all" { return try await latest(page: page) }
        var path = config.filter("category." + selected)
        if path.isEmpty {
            if selected.hasPrefix("genre.") {
                path = "/manhua/class/" + String(selected.dropFirst("genre.".count)) + "/"
            } else if selected.hasPrefix("/") {
                path = selected
            } else {
                path = config.filter("category.all").isEmpty ? "/manhua/" : config.filter("category.all")
            }
        }
        return Self.parseCards(try await get(pageURL(absolute(path), page: page)), sourceId: id)
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let raw = Self.rawID(comicId, sourceId: id)
        guard !raw.isEmpty, raw.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            throw error("漫画 ID 无效")
        }
        let route = config.route("detail").isEmpty ? "/manhua/detail/{comicId}/" : config.route("detail")
        let html = try await get(absolute(route.replacingOccurrences(of: "{comicId}", with: raw)))
        let summary = Self.parseDetailSummary(id: raw, html: html, sourceId: id)
        var author = Self.clean(Self.first(html, #"class=["']cy_xinxi["'][^>]*>[\s\S]*?<span[^>]*>([\s\S]*?)</span>"#))
        author = author.replacingOccurrences(of: #"^作者：?\s*"#, with: "", options: .regularExpression)
        var status = Self.clean(Self.first(html, #"class=["']cy_xinxi["'][^>]*>[\s\S]*?<span[^>]*>(?:状态：)?([^<]*)"#))
        if status.hasPrefix("作者") { status = "" }
        var description = Self.clean(Self.first(html, #"id=["']comic-description["'][^>]*>([\s\S]*?)</[^>]+>"#))
        if description.isEmpty {
            description = Self.clean(Self.first(html, #"<p[^>]*itemprop=["']description["'][^>]*>([\s\S]*?)</p>"#))
        }
        if author.isEmpty {
            author = Self.clean(Self.first(html, #"作者[：:]</span>\s*<a[^>]*>\s*<span[^>]*>([\s\S]*?)</span>"#))
        }
        storePendingDirectory(id: raw, html: html)
        return .init(
            summary: summary,
            author: author,
            status: status,
            description: description,
            latestChapter: Self.parseLatestChapter(comicId: raw, html: html),
            chapters: []
        )
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let raw = Self.rawID(comicId, sourceId: id)
        guard !raw.isEmpty, raw.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            throw error("漫画 ID 无效")
        }
        let html: String
        if let cached = takePendingDirectory(id: raw) {
            html = cached
        } else {
            let route = config.route("detail").isEmpty ? "/manhua/detail/{comicId}/" : config.route("detail")
            html = try await get(absolute(route.replacingOccurrences(of: "{comicId}", with: raw)))
        }
        let result = Self.parseChapters(comicId: raw, html: html)
        guard !result.isEmpty else { throw error("目录解析失败") }
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let resolved = absolute(url)
        guard let match = Self.matches(resolved, #"/manhua/chapter/([0-9]+)/([0-9]+)/(?:all\.html)?(?:[?#].*)?$"#).first else {
            throw error("章节地址无效")
        }
        let comicId = match[1], chapterId = match[2]
        let readerUrl = absolute("/manhua/chapter/\(comicId)/\(chapterId)/all.html")
        let html = try await get(readerUrl, referer: referer)
        let images = Self.imageUrls(html, baseURL: readerUrl).filter(Self.isReaderImage)
        guard !images.isEmpty else { throw error("阅读页未返回图片：" + chapterId) }
        var title = Self.clean(Self.first(html, #"<title[^>]*>([\s\S]*?)</title>"#))
        if let r = title.range(of: "动漫啦") { title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if title.isEmpty { title = chapterId }
        return .init(chapterId: chapterId, title: title, nextPageUrl: "", imageUrls: images)
    }

    private func storePendingDirectory(id: String, html: String) {
        pendingDirectoryKeys.removeAll { $0 == id }
        pendingDirectoryKeys.append(id)
        pendingDirectoryHtml[id] = html
        while pendingDirectoryKeys.count > 4 {
            let oldest = pendingDirectoryKeys.removeFirst()
            pendingDirectoryHtml.removeValue(forKey: oldest)
        }
    }

    private func takePendingDirectory(id: String) -> String? {
        pendingDirectoryKeys.removeAll { $0 == id }
        return pendingDirectoryHtml.removeValue(forKey: id)
    }

    private static func isReaderImage(_ image: String) -> Bool {
        guard let url = URL(string: image),
              let host = url.host?.lowercased(),
              host == "img.dongman.la" else { return false }
        let path = url.path
        // Comic paths are grouped by title initial, e.g. /h/hzw/ and /q/qzlr/.
        return path.range(of: #"^/[a-z]/[^/]+/.+\.(?:jpg|jpeg|png|webp|gif)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func parseCards(_ html: String, sourceId: String = "dongmanla") -> [ComicSummary] {
        var result: [ComicSummary] = []
        var seen = Set<String>()
        var cards: [String] = []
        for section in elementsByClass(html, tag: "div", cssClass: "cy_wide_list") {
            cards.append(contentsOf: elements(section, tag: "li"))
        }
        if cards.isEmpty {
            cards = elements(html, tag: "ul")
        }
        let prefix = sourceId + ":"
        for list in cards {
            guard let link = matches(list, #"<a\b[^>]*href=["'](?:https?://www\.dongman\.la)?/manhua/detail/([0-9]+)/[^"']*["'][^>]*>"#).first else { continue }
            let rawId = link[1]
            guard seen.insert(rawId).inserted else { continue }
            var title = clean(first(list, #"<li[^>]*class=["']title["'][^>]*>([\s\S]*?)</li>"#))
            let imgTag = firstTagOpening(list, tag: "img")
            if title.isEmpty {
                title = clean(firstNonEmpty(attribute(imgTag, name: "alt"), attribute(imgTag, name: "title")))
                    .replacingOccurrences(of: #"漫画$"#, with: "", options: .regularExpression)
            }
            guard !title.isEmpty else { continue }
            let cover = firstNonEmpty(attribute(imgTag, name: "data-src"), attribute(imgTag, name: "src"))
            var status = clean(first(list, #"<li[^>]*class=["']zuozhe["'][^>]*>([\s\S]*?)</li>"#))
            let latest = clean(first(list, #"<li[^>]*class=["']updata["'][^>]*>([\s\S]*?)</li>"#))
            var tagsRaw = clean(first(list, #"<li[^>]*class=["']biaoqian["'][^>]*>([\s\S]*?)</li>"#))
            tagsRaw = tagsRaw.replacingOccurrences(of: #"^标签：?\s*"#, with: "", options: .regularExpression)
            let tagList = tagsRaw.components(separatedBy: CharacterSet(charactersIn: ",，/"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            status = status.replacingOccurrences(of: #"^状态：?\s*"#, with: "", options: .regularExpression)
            result.append(.init(sourceId: sourceId, comicId: prefix + rawId, title: title, coverUrl: absoluteImage(cover), subtitle: status.isEmpty ? latest : status, tags: tagList))
        }
        return result
    }

    static func parseDetailSummary(id: String, html: String, sourceId: String = "dongmanla") -> ComicSummary {
        var title = clean(first(html, #"<h1[^>]*class=["']cy_title["'][^>]*>([\s\S]*?)</h1>"#))
        if title.isEmpty { title = clean(first(html, #"<h1[^>]*>([\s\S]*?)</h1>"#)) }
        if title.isEmpty {
            title = clean(first(html, #"<title[^>]*>([\s\S]*?)</title>"#))
            if let r = title.range(of: "漫画") { title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let block = first(html, #"class=["']cy_info_cover["'][^>]*>([\s\S]*?)</div>"#)
        var image = attribute(firstTagOpening(block, tag: "img"), name: "src")
        if image.isEmpty {
            image = first(html, #"<meta[^>]*(?:property|name)=["']og:image["'][^>]*content=["']([^"']+)"#)
        }
        return .init(sourceId: sourceId, comicId: sourceId + ":" + id, title: title.isEmpty ? id : title, coverUrl: absoluteImage(image), subtitle: "", tags: [])
    }

    static func parseLatestChapter(comicId: String, html: String) -> String {
        guard let sectionRegex = try? NSRegularExpression(pattern: #"<div[^>]*(?:class=["'][^"']*cy_plist[^"']*["']|id=["']chapterList["'])[^>]*>"#, options: .caseInsensitive),
              let sectionMatch = sectionRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let sectionRange = Range(sectionMatch.range, in: html) else {
            return ""
        }
        let tail = String(html[sectionRange.upperBound...])
        let pattern = #"<a\b[^>]*href=["'][^"']*/manhua/chapter/"# + NSRegularExpression.escapedPattern(for: comicId) + #"/[0-9]+/[^"']*["'][^>]*>([\s\S]*?)</a>"#
        guard let chMatch = matches(tail, pattern).first else { return "" }
        return firstNonEmpty(clean(chMatch[1]), attribute(firstTagOpening(chMatch[0], tag: "a"), name: "title"))
    }

    static func parseChapters(comicId: String, html: String) -> [Chapter] {
        var result: [Chapter] = []
        var seen = Set<String>()
        var sections = elementsByClass(html, tag: "div", cssClass: "cy_plist")
        if sections.isEmpty {
            let grid = first(html, #"<div[^>]*id=["']chapterList["'][^>]*>([\s\S]*?)</div>"#)
            if !grid.isEmpty { sections.append(grid) }
        }
        let targetHTML = sections.isEmpty ? html : sections.joined(separator: "\n")
        let pattern = #"<a\b[^>]*href=["'](?:https?://www\.dongman\.la)?/manhua/chapter/"# + NSRegularExpression.escapedPattern(for: comicId) + #"/([0-9]+)/[^"']*["'][^>]*>([\s\S]*?)</a>"#
        for m in matches(targetHTML, pattern) {
            let chapterId = m[1]
            guard seen.insert(chapterId).inserted else { continue }
            let anchor = m[0]
            var title = clean(m[2])
            if title.isEmpty { title = clean(attribute(firstTagOpening(anchor, tag: "a"), name: "title")) }
            if title.isEmpty { title = "章节 " + chapterId }
            let url = "https://www.dongman.la/manhua/chapter/\(comicId)/\(chapterId)/all.html"
            result.append(.init(chapterId: chapterId, title: title, url: url, chapterSlot: result.count))
        }
        if !sections.isEmpty { result.reverse() }
        return result
    }

    private func pageURL(_ base: String, page: Int) -> String {
        guard page > 1 else { return base }
        var trimmed = base.replacingOccurrences(of: #"[?#].*$"#, with: "", options: .regularExpression)
        if !trimmed.hasSuffix("/") { trimmed += "/" }
        return "\(trimmed)\(page).html"
    }

    private static func absoluteImage(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("//") { return "https:" + value }
        if value.hasPrefix("http://") { return "https://" + String(value.dropFirst("http://".count)) }
        if value.hasPrefix("https://") { return value }
        return resolveRelative(value, against: "https://www.dongman.la/")
    }

    // MARK: - HTTP & HTML Helpers

    private func get(_ url: String, referer: String? = nil) async throws -> String {
        do {
            return try await performGet(url: url, referer: referer ?? self.referer)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let urlError = error as? URLError,
               [.networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(urlError.code) {
                return try await performGet(url: url, referer: referer ?? self.referer)
            }
            throw error
        }
    }

    private func performGet(url: String, referer: String) async throws -> String {
        try Task.checkCancellation()
        guard let targetURL = URL(string: url), ["http", "https"].contains(targetURL.scheme?.lowercased() ?? "") else {
            throw URLError(.badURL)
        }
        var headers: [String: String] = [
            "User-Agent": Self.defaultUA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.6",
            "Accept-Encoding": "gzip",
            "Connection": "close"
        ]
        if !referer.isEmpty { headers["Referer"] = referer }
        let response = try await transport.get(targetURL, headers: headers)
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

    private static func elements(_ html: String, tag: String) -> [String] {
        guard !html.isEmpty,
              let tokenRegex = try? NSRegularExpression(pattern: "</?" + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#, options: .caseInsensitive) else {
            return []
        }
        var result: [String] = []
        let allMatches = tokenRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var idx = 0
        while idx < allMatches.count {
            guard let openRange = Range(allMatches[idx].range, in: html) else { idx += 1; continue }
            let opening = String(html[openRange])
            if opening.hasPrefix("</") { idx += 1; continue }
            if opening.hasSuffix("/>") {
                result.append(opening)
                idx += 1
                continue
            }
            var depth = 1
            var cursor = idx + 1
            var endBound: String.Index?
            while cursor < allMatches.count {
                if let r = Range(allMatches[cursor].range, in: html) {
                    let current = html[r]
                    if current.hasPrefix("</") { depth -= 1 }
                    else if !current.hasSuffix("/>") { depth += 1 }
                    if depth == 0 {
                        endBound = r.upperBound
                        break
                    }
                }
                cursor += 1
            }
            guard let end = endBound else { break }
            result.append(String(html[openRange.lowerBound..<end]))
            idx = cursor + 1
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
        NSError(domain: "DongmanLaComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: name + message])
    }
}
