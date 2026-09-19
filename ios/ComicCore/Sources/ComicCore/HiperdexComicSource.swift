import Foundation

public enum HiperdexSourceError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse(String)
    public var errorDescription: String? { if case .invalidResponse(let message) = self { return message }; return nil }
}

public struct HiperdexComicSource: ComicSource {
    public let id = "hiperdex"
    public let name = "HiperDEX"
    public let referer = "https://hiperdex.com/"
    private let base = "https://hiperdex.com"
    private let transport: any HTTPTransport
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) { self.transport = transport }

    public func latest(page: Int) async throws -> [ComicSummary] {
        try cards(await fetch("/manga/?m_orderby=latest" + (page > 1 ? "&paged=\(page)" : "")))
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        let query = percentEncode(keyword.trimmingCharacters(in: .whitespacesAndNewlines))
        return try cards(await fetch("/?s=\(query)&post_type=wp-manga" + (page > 1 ? "&paged=\(page)" : "")))
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {[
        .init(key: "region", label: "题材", options: [
            .init(label: "全部", value: "all"), .init(label: "Manhwa", value: "manhwa"),
            .init(label: "Webtoon", value: "webtoon"), .init(label: "Romance", value: "romance"), .init(label: "Drama", value: "drama")
        ])
    ]}

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let selected = normalized(filters["region"]) == "all" ? normalized(filters["state"]) : normalized(filters["region"])
        let genre = ["manhwa", "webtoon", "romance", "drama"].contains(selected) ? selected + "/" : ""
        return try cards(await fetch("/manga/\(genre)" + (page > 1 ? "page/\(page)/" : "")))
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = rawComicID(comicId), html = try await fetch("/manga/\(rawID)/")
        var title = clean(meta("og:title", html)).replacingOccurrences(of: " - HiperDEX", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#, html)) }
        guard !title.isEmpty else { throw parseError("详情解析失败：缺少标题") }
        var description = clean(meta("og:description", html))
        if description.isEmpty { description = clean(first(#"<div[^>]+class=\"[^\"]*summary__[^\"]*\"[^>]*>([\s\S]*?)</div>"#, html)) }
        let latest = clean(first(#"<a[^>]+href=\"[^\"]*/manga/[^\"]+/[^\"]+/\"[^>]*>([\s\S]*?)</a>"#, html))
        let summary = ComicSummary(sourceId: id, comicId: "hiperdex:\(rawID)", title: title, coverUrl: absolute(cleanURL(meta("og:image", html))), subtitle: latest)
        return ComicDetail(summary: summary, author: clean(first(#"(?:Author|Artist)[\s\S]{0,200}?<a[^>]*>([\s\S]*?)</a>"#, html)), status: clean(first(#"Status[\s\S]{0,200}?<a[^>]*>([\s\S]*?)</a>"#, html)), description: description, latestChapter: latest, chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let rawID = rawComicID(comicId), html = try await fetch("/manga/\(rawID)/")
        var seen = Set<String>(), result: [Chapter] = []
        let pattern = #"<a[^>]+href=\"([^\"]*/manga/"# + NSRegularExpression.escapedPattern(for: rawID) + #"/[^\"]+/)\"[^>]*>([\s\S]*?)</a>"#
        for match in matches(pattern, html) {
            let url = absolute(cleanURL(match[1])), slug = url.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").last.map(String.init) ?? "", title = clean(match[2])
            guard !slug.isEmpty, !title.isEmpty, seen.insert(url).inserted else { continue }
            result.append(.init(chapterId: slug, title: title, url: url, chapterSlot: result.count))
        }
        guard !result.isEmpty || html.range(of: #"<meta[^>]+(?:property|name)=\"og:title\"|class=[\"'][^\"']*chapter-list"#, options: [.regularExpression, .caseInsensitive]) != nil else { throw parseError("目录解析失败") }
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let html = try await fetch(url)
        let content = raw(#"<div[^>]+class=\"[^\"]*reading-content[^\"]*\"[\s\S]*?(?=<div[^>]+class=\"[^\"]*comments-area|</body>|$)"#, html)
        let scope = content.isEmpty ? html : content
        var seen = Set<String>(), images: [String] = []
        for match in matches(#"<img\b[^>]*>"#, scope) {
            let image = absolute(imageURL(match[0])), lower = image.lowercased()
            guard lower.range(of: #"\.(?:jpe?g|png|webp)(?:\?|$)"#, options: .regularExpression) != nil,
                  !lower.contains("logo"), !lower.contains("avatar"), !lower.contains("cover"), seen.insert(image).inserted else { continue }
            images.append(image)
        }
        guard !images.isEmpty else { throw parseError("章节解析失败：缺少正文图片") }
        return .init(chapterId: url, title: clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#, html)), nextPageUrl: "", imageUrls: images)
    }

    private func fetch(_ value: String) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: absolute(value)) else { throw URLError(.badURL) }
        let response = try await transport.get(url, headers: ["User-Agent": Self.userAgent, "Referer": referer])
        try Task.checkCancellation()
        guard (200..<400).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard let html = String(data: response.data, encoding: .utf8) else { throw parseError("响应不是 UTF-8") }
        return html
    }

    private func cards(_ html: String) throws -> [ComicSummary] {
        let blocks = matches(#"<div[^>]+class=\"[^\"]*(?:page-listing-item|manga__item|manga-item)[^\"]*\"[\s\S]*?(?=<div[^>]+class=\"[^\"]*(?:page-listing-item|manga__item|manga-item)[^\"]*\"|</main>|</body>|$)"#, html)
        var seen = Set<String>(), result: [ComicSummary] = []
        for match in blocks {
            let block = match[0], href = cleanURL(first(#"<a[^>]+href=\"([^\"]*/manga/[^\"]+/)\""#, block)), rawID = rawComicID(href)
            guard !rawID.isEmpty, seen.insert(rawID).inserted else { continue }
            let image = raw(#"<img[^>]+>"#, block)
            var title = clean(first(#"<h[23][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#, block))
            if title.isEmpty { title = clean(attribute("alt", image)) }
            let latest = clean(first(#"<a[^>]+href=\"[^\"]*/manga/"# + NSRegularExpression.escapedPattern(for: rawID) + #"/[^\"]+/\"[^>]*>(Chapter[^<]*)</a>"#, block))
            result.append(.init(sourceId: id, comicId: "hiperdex:\(rawID)", title: title, coverUrl: absolute(imageURL(image)), subtitle: latest))
        }
        if result.isEmpty, blocks.isEmpty {
            for match in matches(#"<a[^>]+href=\"([^\"]*/manga/[^\"]+/)\"[^>]*>([\s\S]*?)</a>"#, html) {
                let rawID = rawComicID(match[1]), title = clean(match[2])
                if !rawID.isEmpty, !title.isEmpty, seen.insert(rawID).inserted { result.append(.init(sourceId: id, comicId: "hiperdex:\(rawID)", title: title)) }
            }
        }
        guard !result.isEmpty || html.range(of: #"<(?:main|div)[^>]+class=[\"'][^\"']*(?:c-page-content|c-tabs-item__content|manga)[^\"']*[\"']"#, options: [.regularExpression, .caseInsensitive]) != nil else { throw parseError("列表解析失败") }
        return result
    }

    private func normalized(_ value: String?) -> String { guard let value, !value.isEmpty else { return "all" }; return value }
    private func rawComicID(_ input: String) -> String { var value = decode(input); if value.hasPrefix("hiperdex:") { value.removeFirst(9) }; if let range = value.range(of: "/manga/") { value = String(value[range.upperBound...]) }; return value.split(separator: "/").first.map(String.init) ?? value.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func imageURL(_ tag: String) -> String { for key in ["data-src", "data-lazy-src", "src"] { let value = attribute(key, tag); if !value.isEmpty { return cleanURL(value) } }; return "" }
    private func absolute(_ input: String) -> String { let value = decode(input).trimmingCharacters(in: .whitespacesAndNewlines); if value.isEmpty { return "" }; if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }; if value.hasPrefix("//") { return "https:" + value }; return base + (value.hasPrefix("/") ? value : "/" + value) }
    private func meta(_ key: String, _ html: String) -> String { matches(#"<meta[^>]+(?:property|name)=\"([^\"]+)\"[^>]+content=\"([^\"]*)\""#, html).first { $0[1] == key }?[2] ?? "" }
    private func attribute(_ name: String, _ html: String) -> String { decode(first("\\b" + NSRegularExpression.escapedPattern(for: name) + #"=[\"']([^\"']*)[\"']"#, html)) }
    private func cleanURL(_ value: String) -> String { decode(value).replacingOccurrences(of: #"\/"#, with: "/").trimmingCharacters(in: .whitespacesAndNewlines) }
    private func decode(_ value: String) -> String { HTML4EntityDecoder.decode(value).replacingOccurrences(of: #"\/"#, with: "/") }
    private func clean(_ value: String) -> String { decode(value.replacingOccurrences(of: #"<script[\s\S]*?</script>|<style[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func percentEncode(_ value: String) -> String { value.utf8.map { byte in ((65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45,46,95,42].contains(byte)) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte) }.joined() }
    private func matches(_ pattern: String, _ value: String) -> [[String]] { guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }; return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" } } }
    private func first(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[1] ?? "" }
    private func raw(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[0] ?? "" }
    private func parseError(_ message: String) -> HiperdexSourceError { .invalidResponse("HiperDEX \(message)") }
}
