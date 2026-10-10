import Foundation

public enum AntbywSourceError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse(String)
    public var errorDescription: String? { if case .invalidResponse(let message) = self { return message }; return nil }
}

public struct AntbywComicSource: ComicSource {
    public let id = "antbyw"
    public let name: String
    public let referer: String
    public let config: SourceConfigItem?
    private let base: String
    private let transport: any HTTPTransport
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let libraryPath: String

    public init(config: SourceConfigItem? = nil, transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25)) {
        self.config = config
        self.name = config?.name ?? "tapmanga搬运"
        let baseCandidate = config?.baseUrl ?? "https://www.antbyw.com"
        let trimmedBase = baseCandidate.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        self.base = trimmedBase.isEmpty ? "https://www.antbyw.com" : trimmedBase
        self.referer = config?.referer ?? (self.base + "/")
        self.libraryPath = config?.route("latest") ?? "/plugin.php?id=jameson_manhua&c=index&a=ku"
        self.transport = transport
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let path = (config?.route("latest") ?? libraryPath) + "&odfie=addtime&order=desc&page=\(max(1, page))"
        return try cards(await fetch(path))
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        guard page <= 1 else { return [] }
        let searchTemplate = config?.route("search") ?? "/plugin.php?id=jameson_manhua&a=search&c=index&keyword={keyword}"
        let path = searchTemplate.replacingOccurrences(of: "{keyword}", with: formEncode(SearchRules.trim(keyword)))
        return try cards(await fetch(path))
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let path = config?.route("categoryIndex") ?? "/plugin.php?id=jameson_manhua&a=ku"
        let html = try await fetch(path)
        let keyMap = ["分类": ("category_id", "题材"), "进度": ("jindu", "进度"), "地区": ("region", "地区"), "首字母": ("letter", "字母"), "年份": ("search_age", "年份"), "受众": ("shouzhong", "受众")]
        var groups: [SourceFilterGroup] = []
        for section in matches(#"<strong[^>]*>([^<]+)</strong>([\s\S]*?)(?=<div[^>]*class=[\"'][^\"']*\bcl\b|</div>\s*</div>|$)"#, html) {
            let siteLabel = clean(section[1])
            guard let (key, label) = keyMap[siteLabel] else { continue }
            var options: [SourceFilterOption] = []
            let pattern = #"<a[^>]*data-field=[\"']"# + NSRegularExpression.escapedPattern(for: key) + #"[\"'][^>]*>[\s\S]*?</a>"#
            for link in matches(pattern, section[2]) {
                let tag = link[0], optionLabel = clean(first(#">([\s\S]*?)</a>"#, tag))
                var value = attribute("data-value", tag)
                if value == "empty" { value = "all" }
                if !optionLabel.isEmpty, !value.isEmpty { options.append(.init(label: optionLabel, value: value)) }
            }
            if !options.isEmpty { groups.append(.init(key: key, label: label, options: options)) }
        }
        groups.append(.init(key: "sort", label: "排序", options: [.init(label: "上架时间", value: "addtime:asc"), .init(label: "更新时间", value: "edittime:desc"), .init(label: "阅读量", value: "views:desc"), .init(label: "收藏量", value: "favores:desc")]))
        guard groups.count > 1 else { throw parseError("分类解析失败") }
        return groups
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var path = config?.route("category") ?? libraryPath
        for key in ["category_id", "jindu", "region", "letter", "search_age", "shouzhong"] {
            if let value = filters[key], !value.isEmpty, value != "all" { path += "&\(key)=\(value)" }
        }
        let order = (filters["sort"].flatMap { $0.isEmpty ? nil : $0 } ?? "addtime:asc").split(separator: ":", maxSplits: 1).map(String.init)
        path += "&odfie=\(order[0])&order=\(order.count > 1 ? order[1] : "desc")&page=\(max(1, page))"
        return try cards(await fetch(path))
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = rawComicID(comicId), html = try await fetch(detailPath(rawID))
        let info = first(#"<!--\s*作品信息 内容栏(?:\s*开始)?\s*-->([\s\S]*?)<!--\s*作品信息 内容栏\s*结束\s*-->"#, html)
        let title = clean(first(#"<h3[^>]*class=[\"'][^\"']*\buk-heading-line\b[^\"']*[\"'][^>]*>([\s\S]*?)</h3>"#, info))
        guard !title.isEmpty else { throw parseError("详情解析失败：缺少标题") }
        let author = clean(first(#"漫畫作者\s*:\s*([\s\S]*?)(?=</div>)"#, info))
        let status = clean(first(#"<a[^>]+(?:[?&]|&amp;)jindu=\d+[^>]*>([\s\S]*?)</a>"#, info))
        let description = clean(first(#"<div[^>]*class=[\"'][^\"']*\buk-alert\b[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#, info))
        let latest = clean(first(#"更新到\s*:\s*([^<]+)"#, info))
        let summary = ComicSummary(sourceId: id, comicId: "antbyw:\(rawID)", title: title, coverUrl: absolute(imageURL(raw(#"<img[^>]+(?:mh_cover|/mh_cover/)[^>]*>"#, html))), subtitle: author, tags: tags(info))
        return .init(summary: summary, author: author, status: status, description: description, latestChapter: latest, chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let rawID = rawComicID(comicId), result = catalog(try await fetch(detailPath(rawID)))
        guard !result.isEmpty else { throw parseError("目录解析失败") }
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let baseURL = withoutPage(absolute(url)), firstHTML = try await fetch(pageURL(baseURL, 1))
        var seen = Set<String>(), images: [String] = []
        try addImages(firstHTML, to: &images, seen: &seen)
        let count = pageCount(firstHTML)
        if count > 1 { for page in 2...count { try addImages(await fetch(pageURL(baseURL, page)), to: &images, seen: &seen) } }
        guard !images.isEmpty else { throw parseError("章节解析失败：缺少正文图片") }
        let title = clean(first(#"<h3[^>]*class=[\"'][^\"']*\buk-heading-line\b[^\"']*[\"'][^>]*>[\s\S]*?<span[^>]*>([\s\S]*?)</span>"#, firstHTML))
        return .init(chapterId: baseURL, title: title, nextPageUrl: "", imageUrls: images)
    }

    private func fetch(_ value: String) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: absolute(value)) else { throw URLError(.badURL) }
        let response = try await transport.get(url, headers: ["User-Agent": Self.userAgent, "Referer": referer, "Accept-Language": "zh-CN,zh;q=0.9"])
        try Task.checkCancellation()
        guard (200..<400).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard let html = String(data: response.data, encoding: .utf8) else { throw parseError("响应不是 UTF-8") }
        return html
    }

    private func cards(_ html: String) throws -> [ComicSummary] {
        var seen = Set<String>(), result: [ComicSummary] = []
        for match in matches(#"<div[^>]*class=[\"'][^\"']*\buk-card\b[^\"']*\buk-text-center\b[^\"']*[\"'][^>]*>([\s\S]*?)(?=<div[^>]*class=[\"'][^\"']*\buk-card\b[^\"']*\buk-text-center\b|$)"#, html) {
            let card = match[1], href = decode(first(#"<a[^>]+href=[\"']([^\"']*a=bofang[^\"']*kuid=\d+[^\"']*)[\"']"#, card)), rawID = rawComicID(href)
            guard !rawID.isEmpty, seen.insert(rawID).inserted else { continue }
            let title = clean(first(#"<p[^>]*>[\s\S]*?<a[^>]+a=bofang[^>]*>([\s\S]*?)</a>"#, card))
            guard !title.isEmpty else { continue }
            let reads = clean(first(#"<a[^>]+a=bofang[^>]*>\s*(阅读\s*\d+)\s*</a>"#, card))
            result.append(.init(sourceId: id, comicId: "antbyw:\(rawID)", title: title, coverUrl: absolute(imageURL(raw(#"<img[^>]*>"#, card))), subtitle: reads))
        }
        guard !result.isEmpty || html.range(of: #"shaixuancont|class=[\"'][^\"']*\buk-grid\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { throw parseError("列表解析失败") }
        return result
    }

    private func catalog(_ html: String) -> [Chapter] {
        var seen = Set<String>()
        var regularHTML = first(#"<!--\s*单话内容 开始\s*-->([\s\S]*?)<!--\s*单话内容 结束\s*-->"#, html)
        if regularHTML.isEmpty { regularHTML = first(#"<!--\s*单话 展示栏 开始\s*-->([\s\S]*?)<!--\s*单话 展示栏 结束\s*-->"#, html) }
        var regular = chapterSection(regularHTML, slot: 0, seen: &seen)
        var extras = chapterSection(first(#"<!--\s*番外篇 展示栏 开始\s*-->([\s\S]*?)<!--\s*番外篇 展示栏 结束\s*-->"#, html), slot: 1, seen: &seen)
        regular.reverse(); extras.reverse()
        return (regular + extras).enumerated().map { .init(chapterId: $0.element.chapterId, title: $0.element.title, url: $0.element.url, sectionSlot: $0.element.sectionSlot, chapterSlot: $0.offset) }
    }

    private func chapterSection(_ html: String, slot: Int, seen: inout Set<String>) -> [Chapter] {
        var result: [Chapter] = []
        for match in matches(#"<a[^>]+href=[\"']([^\"']*a=read[^\"']*kuid=(\d+)[^\"']*zjid=(\d+)[^\"']*)[\"'][^>]*class=[\"'][^\"']*\bzj-container\b[^\"']*[\"'][^>]*>([\s\S]*?)</a>"#, html) {
            let chapterID = match[3], title = clean(match[4])
            if !title.isEmpty, seen.insert(chapterID).inserted { result.append(.init(chapterId: chapterID, title: title, url: absolute(decode(match[1])), sectionSlot: slot, chapterSlot: result.count)) }
        }
        return result
    }

    private func addImages(_ html: String, to images: inout [String], seen: inout Set<String>) throws {
        guard let json = matches(#"(?:let|var|const)\s+urls\s*=\s*(\[[\s\S]*?\])\s*;"#, html).first?[1] else { return }
        guard let data = json.data(using: .utf8), let values = try? JSONSerialization.jsonObject(with: data) as? [String] else { throw parseError("图片列表解析失败") }
        for value in values { let image = absolute(value); if !image.isEmpty, seen.insert(image).inserted { images.append(image) } }
    }

    private func tags(_ html: String) -> [String] { var seen = Set<String>(); return matches(#"<a[^>]+a=ku[^>]*>([\s\S]*?)</a>"#, html).map { clean($0[1]) }.filter { !$0.isEmpty && seen.insert($0).inserted } }
    private func detailPath(_ rawID: String) -> String {
        let detailTemplate = config?.route("detail") ?? "/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid={comicId}"
        return detailTemplate.replacingOccurrences(of: "{comicId}", with: rawID)
    }
    private func rawComicID(_ input: String) -> String { var value = input; if value.hasPrefix("antbyw:") { value.removeFirst(7) }; let found = first(#"[?&](?:amp;)?kuid=(\d+)"#, value); return found.isEmpty ? value.filter(\.isNumber) : found }
    private func withoutPage(_ input: String) -> String { input.replacingOccurrences(of: #"([?&])page=\d+&?"#, with: "$1", options: .regularExpression).replacingOccurrences(of: #"[?&]+$"#, with: "", options: .regularExpression) }
    private func pageURL(_ input: String, _ page: Int) -> String { input + (input.contains("?") ? "&" : "?") + "page=\(page)" }
    private func pageCount(_ html: String) -> Int { matches(#"[?&](?:amp;)?page=(\d+)"#, html).compactMap { Int($0[1]) }.max() ?? 1 }
    private func imageURL(_ tag: String) -> String { for key in ["data-src", "data-original", "src"] { let value = attribute(key, tag); if !value.isEmpty { return value.trimmingCharacters(in: .whitespacesAndNewlines) } }; return "" }
    private func absolute(_ input: String) -> String { var value = decode(input).trimmingCharacters(in: .whitespacesAndNewlines); if value.isEmpty { return "" }; if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }; if value.hasPrefix("//") { return "https:" + value }; if value.hasPrefix("./") { value.removeFirst() }; return base + (value.hasPrefix("/") ? value : "/" + value) }
    private func attribute(_ name: String, _ html: String) -> String { decode(first(#"\b"# + NSRegularExpression.escapedPattern(for: name) + #"=[\"']([^\"']*)[\"']"#, html)) }
    private func decode(_ value: String) -> String { HTML4EntityDecoder.decode(value) }
    private func clean(_ value: String) -> String { decode(value.replacingOccurrences(of: #"<br\b[^>]*>|</?(?:p|div)\b[^>]*>"#, with: " ", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func formEncode(_ value: String) -> String { value.utf8.map { byte in byte == 32 ? "+" : ((65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45,46,95,42].contains(byte)) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte) }.joined() }
    private func matches(_ pattern: String, _ value: String) -> [[String]] { guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }; return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" } } }
    private func first(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[1] ?? "" }
    private func raw(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[0] ?? "" }
    private func parseError(_ message: String) -> AntbywSourceError { .invalidResponse("tapmanga搬运\(message)") }
}
