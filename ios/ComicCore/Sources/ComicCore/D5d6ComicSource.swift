import Foundation
import CoreFoundation

public enum D5d6SourceError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse(String)
    public var errorDescription: String? { if case .invalidResponse(let message) = self { return message }; return nil }
}

public struct D5d6ComicSource: ComicSource {
    public let id = "d5d6"
    public let name = "悦看漫画"
    public let referer = "https://www.d5d6.com/"
    private let base = "https://www.d5d6.com"
    private let transport: any HTTPTransport
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) { self.transport = transport }

    public func latest(page: Int) async throws -> [ComicSummary] { try cards(await fetch(categoryPath(slug: "jiujiuquanbu", state: "all", page: page))) }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        guard page <= 1 else { return [] }
        let html = try await fetch("/search/\(formEncode(keyword.trimmingCharacters(in: .whitespacesAndNewlines)))/")
        if clean(html).range(of: #"搜索《[^》]+》结果为空，以下是为您推荐的热门作品"#, options: .regularExpression) != nil { return [] }
        return try cards(html)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let categories = categoryOptions(try await fetch("/jiujiucate_quanbu/"))
        guard !categories.isEmpty else { throw parseError("分类解析失败") }
        return [
            .init(key: "category", label: "题材", options: [.init(label: "全部", value: "all")] + categories),
            .init(key: "state", label: "状态", options: [.init(label: "全部", value: "all"), .init(label: "连载中", value: "serial"), .init(label: "已完成", value: "pub")])
        ]
    }

    public func categories() async throws -> [String] {
        let values = categoryOptions(try await fetch("/jiujiucate_quanbu/")).map(\.label)
        return values.isEmpty ? ["大陆", "日本", "韩国", "欧美"] : values
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var slug = filters["category"].flatMap { $0.isEmpty ? nil : $0 } ?? "jiujiuquanbu"
        if slug == "all" { slug = "jiujiuquanbu" }
        return try cards(await fetch(categoryPath(slug: slug, state: filters["state"] ?? "all", page: page)))
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = rawComicID(comicId), html = try await fetch("/jiujiucomic_\(rawID)/")
        guard html.range(of: #"article-info-item|cover-box|chapter-list"#, options: [.regularExpression, .caseInsensitive]) != nil else { throw parseError("详情解析失败") }
        let info = raw(#"<div[^>]+class=[\"'][^\"']*article-info-item[^\"']*[\"'][^>]*>[\s\S]*?<div[^>]+class=[\"'][^\"']*mt20[^\"']*[\"'][^>]*>"#, html).isEmpty ? html : raw(#"<div[^>]+class=[\"'][^\"']*article-info-item[^\"']*[\"'][^>]*>[\s\S]*?<div[^>]+class=[\"'][^\"']*mt20[^\"']*[\"'][^>]*>"#, html)
        var title = clean(first(#"<h1[^>]+class=[\"'][^\"']*title[^\"']*[\"'][^>]*>([\s\S]*?)</h1>"#, info))
        if title.isEmpty { title = clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#, html)) }
        if title.isEmpty { title = clean(first(#"<title>([\s\S]*?)(?:-|_).*?</title>"#, html)) }
        guard !title.isEmpty else { throw parseError("详情解析失败：缺少标题") }
        var cover = imageURL(raw(#"<div[^>]+class=[\"'][^\"']*cover-box[^\"']*[\"'][^>]*>[\s\S]*?<img[^>]+>"#, html))
        if cover.isEmpty { cover = imageURL(raw(#"<div[^>]+class=[\"'][^\"']*(?:cover|book|pic|thumb)[^\"']*[\"'][\s\S]*?<img[^>]+>"#, html)) }
        if cover.isEmpty { cover = imageURL(raw(#"<img[^>]+(?:alt|title)=[\"'][^\"']*"# + NSRegularExpression.escapedPattern(for: title) + #"[^\"']*[\"'][^>]*>"#, html)) }
        let author = labelledText("作者", info), description = labelledParagraph("简介", info), latest = labelledLink("最新章节", info)
        let lower = html.lowercased(), status = lower.range(of: #"tag-serialize[^\"']*(?:done|finish|end|complete)"#, options: .regularExpression) != nil ? "已完成" : lower.range(of: #"tag-serialize[^\"']*(?:doing|serial|ongoing)"#, options: .regularExpression) != nil ? "连载中" : ""
        return .init(summary: .init(sourceId: id, comicId: "d5d6:\(rawID)", title: title, coverUrl: absolute(cover), subtitle: latest), author: author, status: status, description: description, latestChapter: latest, chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let rawID = rawComicID(comicId), html = try await fetch("/jiujiucomic_\(rawID)/")
        var block = raw(#"<ul[^>]+class=[\"'][^\"']*chapter-list[^\"']*[\"'][^>]*>[\s\S]*?</ul>"#, html)
        if block.isEmpty { block = html }
        var seen = Set<String>(), result: [Chapter] = []
        for match in matches(#"<li>\s*<a[^>]+href=[\"']([^\"']+\.html)[\"'][^>]*>([\s\S]*?)</a>\s*</li>"#, block) {
            let href = decode(match[1]), title = clean(match[2]), chapterID = href.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: ".html", with: "") ?? ""
            guard !title.isEmpty, seen.insert(href).inserted else { continue }
            let url = href.hasPrefix("http") || href.hasPrefix("/") ? absolute(href) : absolute("/jiujiucomic_\(rawID)/\(chapterID).html")
            result.append(.init(chapterId: chapterID, title: title, url: url, chapterSlot: result.count))
        }
        guard !result.isEmpty || html.range(of: #"chapter-list|article-info-item"#, options: [.regularExpression, .caseInsensitive]) != nil else { throw parseError("目录解析失败") }
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let absoluteURL = absolute(url), html = try await fetch(absoluteURL)
        var title = clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#, html))
        if title.isEmpty { title = clean(first(#"<title>([\s\S]*?)(?:-|_).*?</title>"#, html)) }
        let found = raw(#"<div[^>]+class=[\"'][^\"']*(?:comicpage|comic-page|read-content|reading|chapter-content|article-content|comic-content|read-img|manga-content)[^\"']*[\"'][^>]*>[\s\S]*?</div>"#, html)
        let scope = found.isEmpty ? html : found
        var seen = Set<String>(), images: [String] = []
        for match in matches(#"<img[^>]+(?:data-original|data-src|src)=[\"']([^\"']+)[\"'][^>]*>"#, scope) {
            let image = absolute(cleanURL(match[1]))
            if readerImage(image), seen.insert(image).inserted { images.append(image) }
        }
        for match in matches(#"[\"'](https?:[^\"']+\.(?:jpg|jpeg|png|webp)(?:\?[^\"']*)?)[\"']"#, scope) {
            let image = absolute(cleanURL(match[1]))
            if readerImage(image), seen.insert(image).inserted { images.append(image) }
        }
        guard !images.isEmpty || !found.isEmpty else { throw parseError("章节解析失败") }
        return .init(chapterId: absoluteURL, title: title, nextPageUrl: "", imageUrls: images)
    }

    private func fetch(_ value: String) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: absolute(value)) else { throw URLError(.badURL) }
        let response = try await transport.get(url, headers: ["User-Agent": Self.userAgent, "Referer": referer])
        try Task.checkCancellation()
        guard (200..<400).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        let declared = response.textEncodingName.flatMap { $0.isEmpty ? nil : $0 } ?? charsetName(in: response.data) ?? "GBK"
        let name = declared.caseInsensitiveCompare("gb2312") == .orderedSame ? "GBK" : declared
        guard let charset = CFStringCreateWithCString(nil, name, CFStringBuiltInEncodings.UTF8.rawValue) else { throw parseError("响应编码无法识别") }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset)
        guard cfEncoding != kCFStringEncodingInvalidId else { throw parseError("响应字符集不支持：\(name)") }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        guard let html = String(data: response.data, encoding: encoding) else { throw parseError("响应编码无法识别") }
        return html
    }

    private func charsetName(in data: Data) -> String? {
        guard let head = String(data: Data(data.prefix(4096)), encoding: .isoLatin1) else { return nil }
        let name = first(#"charset\s*=\s*['\"]?([A-Za-z0-9_\-]+)"#, head)
        return name.isEmpty ? nil : name
    }

    private func cards(_ html: String) throws -> [ComicSummary] {
        var seen = Set<String>(), result: [ComicSummary] = []
        for match in matches(#"<li[^>]*>\s*<div[^>]+class=[\"'][^\"']*cart-item[^\"']*[\"'][^>]*>[\s\S]*?</li>"#, html) {
            let block = match[0]
            var href = first(#"<a[^>]+class=[\"'][^\"']*cart-cover[^\"']*[\"'][^>]+href=[\"']([^\"']+)[\"']"#, block)
            if href.isEmpty { href = first(#"<a[^>]+href=[\"']([^\"']*jiujiucomic_\d+/?)[\"']"#, block) }
            let rawID = rawComicID(href)
            guard !rawID.isEmpty, seen.insert(rawID).inserted else { continue }
            let image = raw(#"<img[^>]+>"#, block), info = raw(#"<div[^>]+class=[\"'][^\"']*cart-info[^\"']*[\"'][^>]*>[\s\S]*?</div>"#, block)
            var title = clean(first(#"<p[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#, info))
            if title.isEmpty { title = clean(attribute("alt", image)) }
            if title.isEmpty { title = clean(attribute("title", block)) }
            guard !title.isEmpty else { continue }
            result.append(.init(sourceId: id, comicId: "d5d6:\(rawID)", title: title, coverUrl: absolute(imageURL(image)), subtitle: clean(first(#"<span[^>]+class=[\"'][^\"']*new-chapter[^\"']*[\"'][^>]*>([\s\S]*?)</span>"#, block))))
        }
        guard !result.isEmpty || html.range(of: #"class=[\"'][^\"']*(?:cart-list|comic-list)[^\"']*[\"']"#, options: [.regularExpression, .caseInsensitive]) != nil else { throw parseError("列表解析失败") }
        return result
    }

    private func categoryOptions(_ html: String) -> [SourceFilterOption] { var seen = Set<String>(); return matches(#"href=[\"'](?:https?://www\.d5d6\.com)?/jiujiucate_(jiujiu[^_/]+)_allvisit_\d+_\d+/?[\"'][^>]*>([\s\S]*?)</a>"#, html).compactMap { let slug = $0[1], title = clean($0[2]); guard slug != "jiujiuquanbu", !title.isEmpty, seen.insert(title).inserted else { return nil }; return .init(label: title, value: slug) } }
    private func categoryPath(slug: String, state: String, page: Int) -> String { let finish = state == "serial" ? "1" : state == "pub" ? "2" : "0"; return "/jiujiucate_\(slug)_allvisit_\(finish)_\(max(1, page))/" }
    private func rawComicID(_ input: String) -> String { var value = input; if value.hasPrefix("d5d6:") { value.removeFirst(5) }; let found = first(#"jiujiucomic_(\d+)"#, value); return found.isEmpty ? value.filter(\.isNumber) : found }
    private func imageURL(_ tag: String) -> String { for key in ["data-original", "data-src", "src"] { let value = attribute(key, tag); if !value.isEmpty { return cleanURL(value) } }; return "" }
    private func readerImage(_ value: String) -> Bool { let lower = value.lowercased(); return lower.range(of: #"\.(?:jpe?g|png|webp)(?:\?|$)"#, options: .regularExpression) != nil && !lower.contains("logo") && !lower.contains("avatar") && !lower.contains("icon") }
    private func labelledText(_ label: String, _ html: String) -> String { clean(first(#"<span[^>]+class=[\"'][^\"']*tag[^\"']*[\"'][^>]*>\s*"# + label + #"[：:]\s*</span>\s*([^<\r\n]+)"#, html)) }
    private func labelledParagraph(_ label: String, _ html: String) -> String { clean(first(#"<span[^>]+class=[\"'][^\"']*tag[^\"']*[\"'][^>]*>\s*"# + label + #"[：:]\s*</span>\s*([\s\S]*?)</p>"#, html)) }
    private func labelledLink(_ label: String, _ html: String) -> String { clean(first(#"<span[^>]+class=[\"'][^\"']*tag[^\"']*[\"'][^>]*>\s*"# + label + #"[：:]\s*</span>\s*<a[^>]*>([\s\S]*?)</a>"#, html)) }
    private func absolute(_ input: String) -> String { let value = decode(input).trimmingCharacters(in: .whitespacesAndNewlines); if value.isEmpty { return "" }; if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }; if value.hasPrefix("//") { return "https:" + value }; return base + (value.hasPrefix("/") ? value : "/" + value) }
    private func attribute(_ name: String, _ html: String) -> String { decode(first("\\b" + NSRegularExpression.escapedPattern(for: name) + #"=[\"']([^\"']*)[\"']"#, html)) }
    private func cleanURL(_ value: String) -> String { let value = decode(value).replacingOccurrences(of: #"\/"#, with: "/").trimmingCharacters(in: .whitespacesAndNewlines); return value.firstIndex(of: "&").map { String(value[..<$0]) } ?? value }
    private func decode(_ value: String) -> String { HTML4EntityDecoder.decode(value) }
    private func clean(_ value: String) -> String { decode(value.replacingOccurrences(of: #"<br\b[^>]*>|</?(?:p|div)\b[^>]*>"#, with: " ", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func formEncode(_ value: String) -> String { value.utf8.map { byte in byte == 32 ? "+" : ((65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45,46,95,42].contains(byte)) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte) }.joined() }
    private func matches(_ pattern: String, _ value: String) -> [[String]] { guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }; return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" } } }
    private func first(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[1] ?? "" }
    private func raw(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[0] ?? "" }
    private func parseError(_ message: String) -> D5d6SourceError { .invalidResponse("悦看漫画\(message)") }
}
