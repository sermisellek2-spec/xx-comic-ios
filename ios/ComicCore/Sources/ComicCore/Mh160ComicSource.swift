import Foundation

public enum Mh160SourceError: Error, Equatable, Sendable {
    case invalidURL(String)
    case invalidResponse(String)
}

extension Mh160SourceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "漫画链接无效，请重新打开作品。"
        case .invalidResponse: return "站源数据格式发生变化，暂时无法解析。"
        }
    }
}

public actor Mh160ComicSource: ComicSource {
    public nonisolated let id = "mh160"
    public nonisolated let name = "漫画160"
    public nonisolated let referer = "https://www.mh160mh.com/"

    private static let baseURL = "https://www.mh160mh.com"
    private static let imageBaseURL = "http://auto.mangafiles.com:88"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private static let filterPriority = ["state", "subject", "region", "version", "audience", "special", "color", "quality", "letter"]

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let path = "/kanmanhua/all/" + (page > 1 ? "\(page).html" : "")
        return try parseCards(await fetch(absolute(path)))
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        let keyword = formEncode(keyword.trimmingCharacters(in: .whitespacesAndNewlines))
        let pageQuery = page > 1 ? "&page=\(page)" : ""
        return try parseCards(await fetch(absolute("/statics/searchelxt1e1.aspx?key=\(keyword)\(pageQuery)")))
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = rawComicID(comicId)
        let html = try await fetch(absolute("/kanmanhua/\(rawID)/"))
        guard hasAnyClass(["mh-date-info-name", "mh-date-info", "mh-date-bgpic", "mh-cover", "cy_plist"], in: html) else {
            throw Mh160SourceError.invalidResponse("漫画160详情解析失败")
        }
        var detail = try parseDetail(rawID: rawID, html: html)
        detail = ComicDetail(
            summary: detail.summary, author: detail.author, status: detail.status,
            description: detail.description, latestChapter: detail.latestChapter,
            chapters: parseChapters(html, comicID: rawID)
        )
        return detail
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let rawID = rawComicID(comicId)
        let html = try await fetch(absolute("/kanmanhua/\(rawID)/"))
        let result = parseChapters(html, comicID: rawID)
        guard !result.isEmpty || hasClass("cy_plist", in: html) else {
            throw Mh160SourceError.invalidResponse("漫画160目录解析失败")
        }
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let requestURL = absolute(url)
        let html = try await fetch(requestURL)
        guard let encoded = firstMatch(#"qTcms_S_m_murl_e\s*=\s*[\"']([^\"']*)[\"']"#, in: html) else {
            throw Mh160SourceError.invalidResponse("漫画160章节解析失败：缺少正文图片")
        }
        let images = try resolveChapterImages(encoded: encoded, html: html)
        guard !images.isEmpty || encoded.isEmpty else {
            throw Mh160SourceError.invalidResponse("漫画160章节解析失败：缺少正文图片")
        }
        let chapterID = chapterID(from: requestURL)
        let title = clean(firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, in: html) ?? "")
        return ChapterPage(chapterId: chapterID, title: title.isEmpty ? chapterID : title, nextPageUrl: "", imageUrls: images)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let html = try await fetch(absolute("/kanmanhua/all/"))
        let groups = parseFilterGroups(html)
        guard !groups.isEmpty else { throw Mh160SourceError.invalidResponse("漫画160分类解析失败") }
        return groups
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        var filterPath = "all"
        for key in Self.filterPriority {
            guard let value = filters[key], !value.isEmpty, value != "all" else { continue }
            filterPath = value.hasPrefix("/") ? String(value.dropFirst()) : value
            break
        }
        let pagePath = page > 1 ? "\(page).html" : ""
        return try parseCards(await fetch(absolute("/kanmanhua/\(filterPath)/\(pagePath)")))
    }

    private func fetch(_ urlString: String) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: urlString) else { throw Mh160SourceError.invalidURL(urlString) }
        let response = try await transport.get(url, headers: ["User-Agent": Self.userAgent, "Referer": referer])
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard let html = String(data: response.data, encoding: .utf8) else {
            throw Mh160SourceError.invalidResponse("响应不是 UTF-8")
        }
        return html
    }

    private func parseCards(_ html: String) throws -> [ComicSummary] {
        let list = firstMatch(#"<ul[^>]*class=[\"'][^\"']*\bmh-search-list\b[^\"']*[\"'][^>]*>([\s\S]*?)</ul>"#, in: html) ?? html
        var result: [ComicSummary] = []
        var seen = Set<String>()
        for card in matches(#"<li[^>]*>[\s\S]*?</li>"#, in: list).map(\.first!) {
            guard let href = firstMatch(#"<a[^>]+href=[\"']([^\"']*?/kanmanhua/[^\"']+)[\"']"#, in: card) else { continue }
            let rawID = rawComicID(href)
            guard !rawID.isEmpty, seen.insert(rawID).inserted else { continue }
            let imageTag = firstRaw(#"<img[^>]*>"#, in: card) ?? ""
            var title = clean(firstMatch(#"<h[1-6][^>]*>\s*<a[^>]*>([\s\S]*?)</a>"#, in: card) ?? "")
            if title.isEmpty { title = clean(firstMatch(#"<a[^>]*title=[\"']([^\"']+)[\"']"#, in: card) ?? "") }
            if title.isEmpty { title = clean(attribute("alt", in: imageTag)) }
            guard !title.isEmpty else { continue }
            let tagBlock = firstMatch(#"class=[\"'][^\"']*mh-works-tags[^\"']*[\"'][^>]*>([\s\S]*?)</p>"#, in: card) ?? ""
            var subtitle = clean(firstMatch(#"class=[\"'][^\"']*mh-works-author[^\"']*[\"'][^>]*>([\s\S]*?)</p>"#, in: card) ?? "")
            subtitle = subtitle.replacingOccurrences(of: #"^状态[：:]\s*"#, with: "", options: .regularExpression)
            if subtitle.isEmpty {
                subtitle = clean(firstMatch(#"class=[\"'][^\"']*cover-list-updata[^\"']*[\"'][^>]*>([\s\S]*?)</p>"#, in: card) ?? "")
            }
            result.append(ComicSummary(
                sourceId: id, comicId: "mh160:\(rawID)", title: title,
                coverUrl: absoluteImage(imageURL(from: imageTag)), subtitle: subtitle, tags: linkTexts(tagBlock)
            ))
        }
        guard !result.isEmpty || hasClass("mh-search-list", in: html) else {
            throw Mh160SourceError.invalidResponse("漫画160列表解析失败")
        }
        return result
    }

    private func parseFilterGroups(_ html: String) -> [SourceFilterGroup] {
        var result: [SourceFilterGroup] = []
        let pattern = #"<div[^>]*class=[\"'][^\"']*\bmh-tags\b[^\"']*[\"'][^>]*>([\s\S]*?)</div>\s*</div>?"#
        for match in matches(pattern, in: html) {
            let block = match[1]
            var label = clean(firstMatch(#"<h[1-6][^>]*>([\s\S]*?)</h[1-6]>"#, in: block) ?? "")
            if label.isEmpty {
                label = clean(firstMatch(#"class=[\"'][^\"']*mh-tags-lx[^\"']*[\"'][^>]*>([\s\S]*?)<"#, in: block) ?? "")
            }
            guard let key = filterKey(for: label) else { continue }
            var options = [SourceFilterOption(label: "全部", value: "all")]
            var seenLabels = Set(["全部"])
            for link in matches(#"<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>([\s\S]*?)</a>"#, in: block) {
                let text = clean(link[2])
                if !text.isEmpty, seenLabels.insert(text).inserted {
                    options.append(.init(label: text, value: filterPath(from: link[1])))
                }
            }
            result.append(.init(key: key, label: label == "进度" ? "状态" : label, options: options))
        }
        return result
    }

    private func parseDetail(rawID: String, html: String) throws -> ComicDetail {
        var title = clean(firstMatch(#"<div[^>]*class=[\"'][^\"']*mh-date-info-name[^\"']*[\"'][^>]*>[\s\S]*?<h[1-6][^>]*>([\s\S]*?)</h[1-6]>"#, in: html) ?? "")
        if title.isEmpty { title = clean(firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, in: html) ?? "") }
        guard !title.isEmpty else { throw Mh160SourceError.invalidResponse("漫画160详情解析失败：缺少标题") }
        var coverBlock = firstRaw(#"<div[^>]*class=[\"'][^\"']*mh-date-bgpic[^\"']*[\"'][^>]*>[\s\S]*?</div>"#, in: html) ?? ""
        if coverBlock.isEmpty {
            coverBlock = firstRaw(#"<div[^>]*class=[\"'][^\"']*mh-cover[^\"']*[\"'][^>]*>[\s\S]*?</div>"#, in: html) ?? ""
        }
        let author = labelled("作者", in: html)
        let status = labelled("状态", in: html)
        let description = clean(firstMatch(#"class=[\"'][^\"']*(?:work-introd|works-info-intro)[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#, in: html) ?? "")
        let labels = firstMatch(#"class=[\"'][^\"']*mh-label[^\"']*[\"'][^>]*>([\s\S]*?)</div>"#, in: html) ?? ""
        let summary = ComicSummary(
            sourceId: id, comicId: "mh160:\(rawID)", title: title,
            coverUrl: absoluteImage(imageURL(from: firstRaw(#"<img[^>]*>"#, in: coverBlock) ?? "")),
            subtitle: author, tags: linkTexts(labels)
        )
        return ComicDetail(summary: summary, author: author, status: status, description: description, latestChapter: "", chapters: [])
    }

    private func parseChapters(_ html: String, comicID: String) -> [Chapter] {
        var result: [Chapter] = []
        var seen = Set<String>()
        let block = elementContent(withClass: "cy_plist", in: html)
        let escapedID = NSRegularExpression.escapedPattern(for: comicID)
        let route = "(?i)(?:https?://[^/]+)?/kanmanhua/\(escapedID)/[^/]+\\.html(?:[?#].*)?"
        var index = 0
        for match in matches(#"<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>([\s\S]*?)</a>"#, in: block) {
            let href = htmlDecode(match[1])
            guard href.range(of: route, options: .regularExpression) != nil else { continue }
            let url = absolute(href)
            guard seen.insert(url).inserted else { continue }
            let title = clean(match[2])
            if !title.isEmpty {
                result.append(.init(chapterId: chapterID(from: url), title: title, url: url, chapterSlot: index))
                index += 1
            }
        }
        if result.isEmpty {
            let fallback = #"href=[\"']([^\"']*/kanmanhua/"# + escapedID + #"/[^\"']+\.html)[\"']"#
            if let href = firstMatch(fallback, in: html) {
                let url = absolute(href)
                result.append(.init(chapterId: chapterID(from: url), title: "在线阅读", url: url))
            }
        }
        return result.reversed()
    }

    private func resolveChapterImages(encoded: String, html: String) throws -> [String] {
        guard !encoded.isEmpty else { return [] }
        let compact = htmlDecode(encoded).filter { !$0.isWhitespace }
        let padded = compact + String(repeating: "=", count: (4 - compact.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), let payload = String(data: data, encoding: .utf8) else {
            throw Mh160SourceError.invalidResponse("漫画160章节图片载荷无效")
        }
        var images: [String] = []
        var seen = Set<String>()
        for rawPath in payload.components(separatedBy: "$qingtiandy$") {
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, !path.contains("recommend"), !path.contains("tuijian") else { continue }
            let image = path.hasPrefix("http") ? path : Self.imageBaseURL + (path.hasPrefix("/") ? path : "/\(path)")
            if seen.insert(image).inserted { images.append(image) }
        }
        let pageID = Int(firstMatch(#"qTcms_S_p_id\s*=\s*[\"'](\d+)[\"']"#, in: html) ?? "") ?? Int.max
        let host = pageID > 542_724 ? "https://xwdf.tgmhfc.uk" : "https://mhpic6.tgmhfc.uk"
        return images.map { $0.replacingOccurrences(of: Self.imageBaseURL, with: host) }
    }

    private func rawComicID(_ rawValue: String) -> String {
        var value = rawValue.hasPrefix("mh160:") ? String(rawValue.dropFirst(6)) : rawValue
        value = htmlDecode(value)
        if let query = value.firstIndex(of: "?") { value = String(value[..<query]) }
        while value.hasSuffix("/") { value.removeLast() }
        if let slash = value.lastIndex(of: "/") { value = String(value[value.index(after: slash)...]) }
        return value.replacingOccurrences(of: ".html", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chapterID(from url: String) -> String {
        firstMatch(#"/([^/]+)\.html(?:[?#].*)?/?$"#, in: url) ?? url
    }

    private func filterPath(from href: String) -> String {
        var value = htmlDecode(href)
        if let range = value.range(of: "/kanmanhua/") { value = String(value[range.upperBound...]) }
        if let query = value.firstIndex(of: "?") { value = String(value[..<query]) }
        value = value.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        return value.isEmpty || value == "all" ? "all" : "/\(value)"
    }

    private func filterKey(for label: String) -> String? {
        [("进度", "state"), ("题材", "subject"), ("地区", "region"), ("版本", "version"),
         ("读者", "audience"), ("特殊", "special"), ("颜色", "color"), ("品质", "quality"),
         ("字母", "letter")].first(where: { label.contains($0.0) })?.1
    }

    private func labelled(_ label: String, in html: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let value = clean(firstMatch("<(?:p|span|li)[^>]*>([\\s\\S]*?\(escaped)[：:]?[\\s\\S]*?)</(?:p|span|li)>", in: html) ?? "")
        return value.replacingOccurrences(of: "^.*?\(escaped)[：:]?\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func linkTexts(_ html: String) -> [String] {
        var result: [String] = []
        for match in matches(#"<a[^>]*>([\s\S]*?)</a>"#, in: html) {
            let text = clean(match[1])
            if !text.isEmpty, text.count < 12, !result.contains(text) { result.append(text) }
        }
        return result
    }

    private func elementContent(withClass name: String, in html: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let opening = regex(#"<([a-z0-9]+)[^>]*class=[\"'][^\"']*\b"# + escaped + #"\b[^\"']*[\"'][^>]*>"#)?.firstMatch(
            in: html, range: NSRange(html.startIndex..., in: html)
        ), let contentStart = Range(opening.range, in: html)?.upperBound,
          let tagRange = Range(opening.range(at: 1), in: html) else { return "" }
        let tag = String(html[tagRange])
        guard let tags = regex("</?\(tag)\\b[^>]*>") else { return "" }
        var depth = 1
        let searchRange = NSRange(contentStart..., in: html)
        for match in tags.matches(in: html, range: searchRange) {
            guard let range = Range(match.range, in: html) else { continue }
            if html[range].hasPrefix("</") { depth -= 1 } else { depth += 1 }
            if depth == 0 { return String(html[contentStart..<range.lowerBound]) }
        }
        return String(html[contentStart...])
    }

    private func imageURL(from tag: String) -> String {
        for attributeName in ["data-original", "data-src", "src"] {
            let value = attribute(attributeName, in: tag)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private func attribute(_ name: String, in tag: String) -> String {
        firstMatch("\\b\(NSRegularExpression.escapedPattern(for: name))=[\\\"']([^\\\"']*)[\\\"']", in: tag) ?? ""
    }

    private func absolute(_ rawValue: String) -> String {
        let value = htmlDecode(rawValue)
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        if value.hasPrefix("//") { return "https:\(value)" }
        return Self.baseURL + (value.hasPrefix("/") ? value : "/\(value)")
    }

    private func absoluteImage(_ rawValue: String) -> String {
        guard !rawValue.isEmpty else { return "" }
        let value = htmlDecode(rawValue).replacingOccurrences(of: #"(@![^/?]+)+$"#, with: "", options: .regularExpression)
        return absolute(value)
    }

    private func formEncode(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        return value.utf8.map { byte -> String in
            let character = Character(UnicodeScalar(byte))
            if character == " " { return "+" }
            if allowed.contains(character) { return String(character) }
            return String(format: "%%%02X", byte)
        }.joined()
    }

    private func clean(_ value: String) -> String {
        htmlDecode(value).replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func htmlDecode(_ value: String) -> String {
        HTML4EntityDecoder.decode(value)
    }

    private func hasClass(_ name: String, in html: String) -> Bool {
        matches(#"class\s*=\s*[\"']([^\"']*)[\"']"#, in: html).contains {
            $0[1].split(whereSeparator: \.isWhitespace).contains(Substring(name))
        }
    }

    private func hasAnyClass(_ names: [String], in html: String) -> Bool {
        names.contains { hasClass($0, in: html) }
    }

    private func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = regex(pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { result in
            (0..<result.numberOfRanges).map { index in
                guard result.range(at: index).location != NSNotFound, let range = Range(result.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        let match = matches(pattern, in: text).first
        return match.flatMap { $0.count > 1 ? $0[1] : nil }
    }

    private func firstRaw(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first?.first
    }
}
