import Foundation

public struct FiveUmComicSource: ComicSource {
    public enum Site: String, Sendable { case manhuazhan, bbyin }
    public let id: String
    public let name: String
    public let referer: String
    private let base: String
    private let transport: any HTTPTransport

    public init(site: Site = .manhuazhan, transport: any HTTPTransport = URLSessionHTTPTransport()) {
        id = site.rawValue
        name = site == .manhuazhan ? "漫画栈" : "比卡漫画"
        base = site == .manhuazhan ? "https://www.60ti.com" : "https://bbyin.com"
        referer = base + "/"
        self.transport = transport
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        try await category(filters: [:], page: page)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        guard page <= 1 else { return [] }
        let trimmed = SearchRules.trim(keyword)
        return try cards(await fetch("/search?key=" + formEncode(trimmed)))
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var path = filters["category"].flatMap { $0.isEmpty || $0 == "all" ? nil : $0 } ?? "/category"
        if let state = filters["state"], !state.isEmpty, state != "all" { path += "/finish/" + state }
        if page > 1 { path += "/page/\(page)" }
        return try cards(await fetch(path))
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let html = try await fetch("/category/")
        let sections = matches(#"<div[^>]*class=["'][^"']*\bfilter-section\b[^"']*["'][^>]*>([\s\S]*?)(?=<div[^>]*class=["'][^"']*\bfilter-section\b|<div[^>]*class=["'][^"']*\bcomic-list\b|$)"#, html)
        var seen = Set<String>()
        var options: [SourceFilterOption] = []
        if let section = sections.first(where: { clean($0[1]).contains("漫画类型") }) {
            for link in matches(#"<a[^>]+href=["']([^"']*/category/tags/\d+)/?["'][^>]*>([\s\S]*?)</a>"#, section[1]) {
                let title = clean(link[2])
                guard !title.isEmpty, seen.insert(title).inserted else { continue }
                options.append(.init(label: title, value: decode(link[1])))
            }
        }
        guard !options.isEmpty else { throw parseError("分类解析失败：缺少漫画类型标签") }
        return [
            .init(key: "category", label: "题材", options: [.init(label: "全部", value: "all")] + options.filter { $0.label != "全部" }),
            .init(key: "state", label: "状态", options: [.init(label: "全部", value: "all"), .init(label: "连载中", value: "1"), .init(label: "已完结", value: "2")])
        ]
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = rawComicID(comicId)
        let html = try await fetch("/comic_\(rawID).html")
        let title = bookTitle(clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#, html)))
        guard !title.isEmpty else { throw parseError("详情解析失败：缺少标题") }
        let info = raw(#"<div[^>]*class=["'][^"']*\bcomic-main-info\b[^"']*["'][^>]*>[\s\S]*?(?=<div[^>]*class=["'][^"']*\bcomic-description\b|$)"#, html)
        let coverBlock = raw(#"<div[^>]*class=["'][^"']*\bcomic-cover-large\b[^"']*["'][^>]*>[\s\S]*?</div>"#, html)
        var cover = imageURL(raw(#"<img[^>]*>"#, coverBlock))
        if cover.isEmpty { cover = attribute("content", raw(#"<meta[^>]+(?:property|name)=["']og:image["'][^>]*>"#, html)) }
        var author = clean(first(#"作者[：:]\s*([^<]*?)</span>"#, info))
        if author.isEmpty { author = clean(first(#"由\s*([^，。<]+?)\s*创作"#, info)) }
        let description = clean(first(#"<div[^>]*class=["'][^"']*\bcomic-description\b[^"']*["'][^>]*>[\s\S]*?<p[^>]*>([\s\S]*?)</p>"#, html))
        let tagBlock = raw(#"<div[^>]*class=["'][^"']*\bcomic-tags\b[^"']*["'][^>]*>[\s\S]*?</div>"#, info)
        var seen = Set<String>()
        let tags = matches(#"<span[^>]*class=["'][^"']*\btag\b[^"']*["'][^>]*>([\s\S]*?)</span>"#, tagBlock).map { clean($0[1]) }.filter { !$0.isEmpty && seen.insert($0).inserted }
        var status = ""
        for tag in tags {
            if tag.contains("完结") || tag.contains("完成") { status = "已完结"; break }
            if tag.contains("连载") { status = "连载中"; break }
        }
        return ComicDetail(summary: .init(sourceId: id, comicId: id + ":" + rawID, title: title, coverUrl: absolute(cover), subtitle: author, tags: tags), author: author, status: status, description: description, latestChapter: catalog(html).last?.title ?? "", chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let html = try await fetch("/comic_\(rawComicID(comicId)).html")
        guard !first(#"<h1[^>]*>([\s\S]*?)</h1>"#, html).isEmpty else { throw parseError("目录解析失败：缺少标题") }
        return catalog(html)
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let url = absolute(url)
        let html = try await fetch(url)
        let content = first(#"<div[^>]*class=["'][^"']*\bcomic-content\b[^"']*["'][^>]*>([\s\S]*?)</div>"#, html)
        var seen = Set<String>()
        let images = matches(#"<img[^>]*>"#, content).compactMap { match -> String? in
            guard attribute("class", match[0]).split(whereSeparator: \.isWhitespace).contains("comic-image") else { return nil }
            let image = absolute(imageURL(match[0]))
            return !image.isEmpty && seen.insert(image).inserted ? image : nil
        }
        guard !images.isEmpty else { throw parseError("章节解析失败：缺少正文图片") }
        return ChapterPage(chapterId: url, title: bookTitle(clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#, html))), nextPageUrl: "", imageUrls: images)
    }

    private func cards(_ html: String) throws -> [ComicSummary] {
        let blocks = matches(#"<div[^>]*class=["'][^"']*\bcomic-item\b[^"']*["'][^>]*>([\s\S]*?)</div>"#, html)
        guard !blocks.isEmpty || !raw(#"class=["'][^"']*\bcomic-list\b[^"']*["']"#, html).isEmpty else { throw parseError("列表解析失败：缺少漫画列表") }
        var seen = Set<String>()
        return blocks.compactMap { block in
            let card = block[1]
            let href = decode(first(#"<a[^>]+href=["']([^"']*/comic_[^"']+\.html)["'][^>]*>"#, card))
            let rawID = rawComicID(href)
            guard !rawID.isEmpty, seen.insert(absolute(href)).inserted else { return nil }
            let image = raw(#"<img[^>]*>"#, card)
            var title = clean(attribute("alt", image))
            if title.isEmpty { title = clean(attribute("title", card)) }
            guard !title.isEmpty else { return nil }
            let author = clean(first(#"<p[^>]*class=["'][^"']*\bcomic-author\b[^"']*["'][^>]*>([\s\S]*?)</p>"#, card))
            return ComicSummary(sourceId: id, comicId: id + ":" + rawID, title: title, coverUrl: absolute(imageURL(image)), subtitle: author)
        }
    }

    private func catalog(_ html: String) -> [Chapter] {
        var seen = Set<String>()
        var result: [Chapter] = []
        for match in matches(#"<a[^>]+href=["']([^"']*/chapter_(\d+)_(\d+)\.html)["'][^>]*>([\s\S]*?)</a>"#, html) {
            let url = absolute(match[1]), title = clean(match[4])
            guard !title.isEmpty, seen.insert(url).inserted else { continue }
            result.append(.init(chapterId: match[3], title: title, url: url, chapterSlot: result.count))
        }
        return result
    }

    private func fetch(_ path: String) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: absolute(path)), ["http", "https"].contains(url.scheme ?? "") else { throw URLError(.badURL) }
        let response = try await transport.get(url, headers: ["User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", "Referer": referer, "Accept-Language": "zh-CN,zh;q=0.9"])
        try Task.checkCancellation()
        guard (200..<400).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        return String(decoding: response.data, as: UTF8.self)
    }

    private func rawComicID(_ value: String) -> String {
        let value = value.hasPrefix(id + ":") ? String(value.dropFirst(id.count + 1)) : value
        let extracted = first(#"(?:^|/)comic_([^/"'?]+)\.html"#, value)
        return extracted.isEmpty ? value.replacingOccurrences(of: #"^comic_|\.html$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) : extracted
    }

    private func imageURL(_ tag: String) -> String {
        for key in ["data-src", "data-original", "src"] {
            let value = attribute(key, tag)
            if !value.isEmpty { return value.replacingOccurrences(of: #"\/"#, with: "/").trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return ""
    }
    private func absolute(_ value: String) -> String {
        let value = decode(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        if value.hasPrefix("//") { return "https:" + value }
        return base + (value.hasPrefix("/") ? value : "/" + value)
    }
    private func attribute(_ name: String, _ html: String) -> String {
        decode(first("\\b" + NSRegularExpression.escapedPattern(for: name) + #"=["']([^"']*)["']"#, html))
    }
    private func decode(_ value: String) -> String { value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"") }
    private func clean(_ value: String) -> String {
        let text = value.replacingOccurrences(of: #"<br\b[^>]*>|</?(?:p|div)\b[^>]*>"#, with: " ", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return HTML4EntityDecoder.decode(text).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func bookTitle(_ value: String) -> String {
        value.hasPrefix("《") && value.hasSuffix("》") && value.count > 2 ? String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) : value
    }
    private func formEncode(_ value: String) -> String {
        value.utf8.map { byte in
            if byte == 32 { return "+" }
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 46, 95, 42].contains(byte) { return String(UnicodeScalar(byte)) }
            return String(format: "%%%02X", byte)
        }.joined()
    }
    private func matches(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" }
        }
    }
    private func first(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[1] ?? "" }
    private func raw(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[0] ?? "" }
    private func parseError(_ message: String) -> NSError { NSError(domain: "FiveUmComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: name + " " + message]) }
}
