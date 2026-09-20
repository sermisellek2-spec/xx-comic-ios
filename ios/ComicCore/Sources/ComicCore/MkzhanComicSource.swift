import Foundation

public struct MkzhanComicSource: ComicSource {
    public let id = "mkzhan"
    public let name: String
    public let referer: String
    private let baseURL: String
    private let config: SourceConfigItem
    private let transport: any HTTPTransport

    public init(
        config: SourceConfigItem = SourceConfigDefaults.mkzhan(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport()
    ) {
        self.config = config
        self.name = config.name
        self.referer = config.referer.isEmpty ? "\(config.baseUrl)/" : config.referer
        self.baseURL = config.baseUrl
        self.transport = transport
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let pageQuery = page > 1 ? "?page=\(page)" : ""
        let route = config.route("latest").isEmpty ? "/category{pageQuery}" : config.route("latest")
        let path = route
            .replacingOccurrences(of: "{pageQuery}", with: pageQuery)
            .replacingOccurrences(of: "{query}", with: pageQuery)
            .replacingOccurrences(of: "{page}", with: String(page))
        return try cards(await fetch(path))
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var query = "is_free=1"
        for key in ["theme_id", "finish", "audience", "copyright"] {
            if let value = filters[key], !value.isEmpty, value != "all" { query += "&\(key)=\(value)" }
        }
        if page > 1 { query += "&page=\(page)" }
        let route = config.route("category").isEmpty ? "/category?{query}" : config.route("category")
        let path = route
            .replacingOccurrences(of: "{query}", with: query)
            .replacingOccurrences(of: "{page}", with: String(page))
        return try cards(await fetch(path.contains("?") ? path : path + "?" + query))
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        guard page <= 1 else { return [] }
        let encoded = SearchRules.trim(keyword).utf8.map { byte -> String in
            if byte == 32 { return "+" }
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 46, 95, 42].contains(byte) { return String(UnicodeScalar(byte)) }
            return String(format: "%%%02X", byte)
        }.joined()
        let path = config.route("search").replacingOccurrences(of: "{keyword}", with: encoded)
        return try cards(await fetch(path))
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let html = try await fetch("/category")
        let keys = ["题材": "theme_id", "进度": "finish", "受众": "audience", "版权": "copyright"]
        var result: [SourceFilterGroup] = []
        for match in matches(#"<div[^>]*class=["'][^"']*\bcate-col\b[^"']*["'][^>]*>([\s\S]*?)(?=<div[^>]*class=["'][^"']*\bcate-col\b|</div>\s*</div>)"#, html) {
            let label = clean(first(#"<p[^>]*class=["'][^"']*\bcate-title\b[^"']*["'][^>]*>([\s\S]*?)</p>"#, match[1])).replacingOccurrences(of: "：", with: "")
            guard let key = keys[label] else { continue }
            let options = matches(#"<a[^>]*href=["']([^"']*)["'][^>]*>([\s\S]*?)</a>"#, match[1]).compactMap { link -> SourceFilterOption? in
                let title = clean(link[2])
                guard !title.isEmpty else { return nil }
                let value = first("[?&]" + key + "=([^&#]+)", decode(link[1]))
                return .init(label: title, value: value.isEmpty ? "all" : value)
            }
            if !options.isEmpty { result.append(.init(key: key, label: label, options: options)) }
        }
        guard !result.isEmpty else { throw parseError("分类解析失败") }
        return result
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = rawComicID(comicId)
        let path = config.route("detail").replacingOccurrences(of: "{comicId}", with: rawID)
        let html = try await fetch(path)
        guard isDetailPage(html) else { throw parseError("详情解析失败") }
        var title = clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#, html))
        if title.isEmpty { title = clean(first(#"<title>([\s\S]*?)(?:_|-)"#, html)) }
        guard !title.isEmpty else { throw parseError("详情解析失败：缺少标题") }
        var cover = imageURL(raw(#"<div class="de-info__cover">[\s\S]*?<img[^>]+>"#, html))
        if cover.isEmpty { cover = imageURL(raw(#"<img[^>]+(?:data-src|src)="[^"]+"[^>]*>"#, html)) }
        let author = clean(first(#"<span[^>]*>作者[:：]?</span>\s*<[^>]+>([\s\S]*?)</"#, html))
        let status = clean(first(#"<div class="de-chapter__title">\s*<span>([\s\S]*?)</span>"#, html))
        let latest = clean(first(#"<span class="update-time">([\s\S]*?)</span>"#, html))
        var description = clean(first(#"<p class="intro-total">([\s\S]*?)</p>"#, html))
        if description.isEmpty { description = clean(first(#"<p class="intro">([\s\S]*?)</p>"#, html)) }
        return .init(summary: .init(sourceId: id, comicId: id + ":" + rawID, title: title, coverUrl: absolute(cover), subtitle: latest), author: author, status: status, description: description, latestChapter: latest, chapters: catalog(html))
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let rawID = rawComicID(comicId)
        let path = config.route("detail").replacingOccurrences(of: "{comicId}", with: rawID)
        let html = try await fetch(path)
        guard isDetailPage(html) else { throw parseError("目录解析失败") }
        return catalog(html)
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let path = url.hasPrefix("http") ? URL(string: url)?.path ?? url : (url.hasPrefix("/") ? url : "/" + url)
        guard let ids = matches(#"/?(\d+)/(\d+)(?:\.html)?/?"#, decode(path)).first else { throw parseError("章节解析失败：无效地址") }
        let api = config.route("chapterApi")
            .replacingOccurrences(of: "{comicId}", with: ids[1])
            .replacingOccurrences(of: "{chapterId}", with: ids[2])
        let html = try await fetch(api)
        guard let root = try? JSONSerialization.jsonObject(with: Data(html.utf8)) as? [String: Any], let data = root["data"] as? [String: Any], let pages = data["page"] as? [Any] else { throw parseError("章节解析失败：无效图片响应") }
        var seen = Set<String>()
        let images = pages.compactMap { item -> String? in
            guard let value = (item as? [String: Any])?["image"] as? String else { return nil }
            let image = cleanImageURL(value)
            return !image.isEmpty && seen.insert(image).inserted ? image : nil
        }
        return .init(chapterId: absolute(path), title: "", nextPageUrl: "", imageUrls: images)
    }
    private func cards(_ html: String) throws -> [ComicSummary] {
        guard let list = div(withClass: "cate-comic-list", in: html) ?? div(withClass: "search-comic-list", in: html) else {
            throw parseError("列表解析失败")
        }
        let blocks = matches(#"<div class="common-comic-item"[^>]*>[\s\S]*?(?=<div class="common-comic-item"|<div id="Pagination"|$)"#, list)
        var seen = Set<String>()
        return blocks.compactMap { match in
            let block = match[0]
            let link = raw(#"<a[^>]+class="[^"]*cover[^"]*"[^>]*>"#, block)
            var rawID = clean(attribute("data-cid", block))
            if rawID.isEmpty { rawID = rawComicID(attribute("href", link)) }
            guard !rawID.isEmpty, seen.insert(rawID).inserted else { return nil }
            let image = raw(#"<img[^>]+>"#, block)
            var title = clean(first(#"<p class="comic__title">[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#, block))
            if title.isEmpty { title = clean(attribute("alt", image)) }
            var subtitle = clean(first(#"<p class="comic-update">[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#, block))
            if subtitle.isEmpty { subtitle = clean(first(#"<p class="comic-count">([\s\S]*?)</p>"#, block)) }
            return .init(sourceId: id, comicId: id + ":" + rawID, title: title, coverUrl: absolute(imageURL(image)), subtitle: subtitle)
        }
    }
    private func isDetailPage(_ html: String) -> Bool {
        div(withClass: "de-info__cover", in: html) != nil && div(withClass: "de-chapter__title", in: html) != nil
    }
    private func div(withClass className: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: className)
        guard
            let opening = try? NSRegularExpression(pattern: #"<div\b[^>]*class=["'][^"']*\b"# + escaped + #"\b[^"']*["'][^>]*>"#, options: .caseInsensitive),
            let start = opening.firstMatch(in: html, range: NSRange(html.startIndex..., in: html))
        else { return nil }
        let searchRange = NSRange(location: start.range.location, length: html.utf16.count - start.range.location)
        guard let tags = try? NSRegularExpression(pattern: #"</?div\b[^>]*>"#, options: .caseInsensitive) else { return nil }
        var depth = 0
        for tag in tags.matches(in: html, range: searchRange) {
            guard let range = Range(tag.range, in: html) else { continue }
            if html[range].hasPrefix("</") { depth -= 1 } else { depth += 1 }
            if depth == 0 {
                let block = NSRange(location: start.range.location, length: tag.range.location + tag.range.length - start.range.location)
                return Range(block, in: html).map { String(html[$0]) }
            }
        }
        return nil
    }
    private func catalog(_ html: String) -> [Chapter] {
        var result: [Chapter] = [], seen = Set<String>()
        for match in matches(#"<a[^>]+data-hreflink="(/(\d+)/(\d+)\.html)"[^>]*>([\s\S]*?)</a>"#, html) {
            let title = clean(match[4])
            guard !title.isEmpty, !title.contains("开始阅读"), seen.insert(match[1]).inserted else { continue }
            result.append(.init(chapterId: match[2] + "/" + match[3], title: title, url: absolute(match[1]), chapterSlot: result.count))
        }
        return result
    }
    private func fetch(_ path: String) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: absolute(path)) else { throw URLError(.badURL) }
        let response = try await transport.get(url, headers: ["User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", "Referer": referer])
        try Task.checkCancellation()
        guard (200..<400).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        return String(decoding: response.data, as: UTF8.self)
    }
    private func rawComicID(_ value: String) -> String {
        let value = decode(value).replacingOccurrences(of: "^mkzhan:", with: "", options: .regularExpression)
        let extracted = first(#"/(\d+)/?"#, value)
        return extracted.isEmpty ? value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression) : extracted
    }
    private func imageURL(_ html: String) -> String {
        for key in ["data-src", "data-original", "src"] {
            let value = attribute(key, html)
            if !value.isEmpty { return cleanImageURL(value) }
        }
        return ""
    }
    private func cleanImageURL(_ value: String) -> String {
        let value = decode(value)
        return (value.hasPrefix("http://") ? "https://" + value.dropFirst(7) : value).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func absolute(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        if value.hasPrefix("//") { return "https:" + value }
        return baseURL + (value.hasPrefix("/") ? value : "/" + value)
    }
    private func decode(_ value: String) -> String { value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: #"\/"#, with: "/") }
    private func clean(_ value: String) -> String {
        let value = decode(value).replacingOccurrences(of: #"<i[\s\S]*?</i>"#, with: " ", options: .regularExpression).replacingOccurrences(of: #"<br\b[^>]*>|</?(?:p|div)\b[^>]*>"#, with: " ", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return HTML4EntityDecoder.decode(value).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func attribute(_ name: String, _ value: String) -> String { first(NSRegularExpression.escapedPattern(for: name) + #"="([^"]*)""#, value) }
    private func matches(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" }
        }
    }
    private func first(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[1] ?? "" }
    private func raw(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[0] ?? "" }
    private func parseError(_ message: String) -> NSError { NSError(domain: "MkzhanComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: name + " " + message]) }
}
