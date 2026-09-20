import Foundation

public struct LiumanhuaComicSource: ComicSource {
    public let id = "liumanhua"
    public let name = "六漫画"
    public let referer = "https://www.liumanhua.com/"
    public let supportsSearch = false
    private let baseURL = "https://www.liumanhua.com"
    private let transport: any HTTPTransport
    private let chapterTransport: any HTTPTransport

    public init(transport: (any HTTPTransport)? = nil) {
        self.transport = transport ?? URLSessionHTTPTransport(timeoutInterval: 20)
        chapterTransport = transport ?? URLSessionHTTPTransport(timeoutInterval: 30)
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        try parseCards(await fetch(categoryPath(filters: [:], page: page)))
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        throw error("暂不支持搜索")
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let groups = parseFilterGroups(try await fetch("/category"))
        guard !groups.isEmpty else { throw error("分类解析失败") }
        return groups
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        try parseCards(await fetch(categoryPath(filters: filters, page: page)))
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = rawComicID(comicId)
        guard !rawID.isEmpty else { throw error("详情 ID 为空") }
        let html = try await fetch("/" + rawID)
        return try parseDetail(rawID: rawID, html: html, includeChapters: true)
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let rawID = rawComicID(comicId)
        guard !rawID.isEmpty else { throw error("目录 ID 为空") }
        let chapters = parseChapters(try await fetch("/" + rawID), comicID: rawID)
        guard !chapters.isEmpty else { throw error("目录解析失败") }
        return chapters
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let absoluteURL = absolute(url)
        let html = try await fetch(absoluteURL, chapter: true)
        let encoded = first(#"\bparams\s*=\s*["']([^"']+)["']"#, html)
        guard let payload = Data(base64Encoded: decode(encoded), options: .ignoreUnknownCharacters), !encoded.isEmpty else { throw error("章节解析失败：阅读参数格式错误") }
        let comicID = first(#"/([^/]+)/[^/]+\.html(?:[?#].*)?$"#, absoluteURL)
        let chapterID = self.chapterID(absoluteURL)
        let images = try await Self.decryptPayload(payload, expectedComicId: comicID, expectedChapterId: chapterID)
        var title = clean(first(#"<title[^>]*>([\s\S]*?)</title>"#, html))
        if let range = title.range(of: " - ") { title = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if title.isEmpty { title = chapterID }
        return .init(chapterId: chapterID, title: title, nextPageUrl: "", imageUrls: images)
    }

    static func decryptPayload(_ payload: Data, expectedComicId: String, expectedChapterId: String) async throws -> [String] {
        guard payload.count > 16 else { throw sourceError("章节解析失败：阅读参数过短") }
        let plain: Data
        do {
            plain = try SourceAES.decrypt(Data(payload.dropFirst(16)), key: Data("9S8$vJnU2ANeSRoF".utf8), iv: Data(payload.prefix(16)))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw sourceError("章节解析失败：无法解密阅读参数")
        }
        guard let json = try? JSONSerialization.jsonObject(with: plain) as? [String: Any] else { throw sourceError("章节解析失败：阅读参数 JSON 无效") }
        if intValue(json["comic_down"], default: 0) != 0 { throw sourceError("章节已被站点限制") }
        if intValue(json["source_id"], default: 6) != 6 { throw sourceError("章节来源不匹配") }
        if let host = json["host"] as? String, !host.isEmpty, !host.contains("liumanhua.com") { throw sourceError("章节域名不匹配") }
        try validateID(json, key: "comic_id", expected: expectedComicId, label: "漫画")
        try validateID(json, key: "comicId", expected: expectedComicId, label: "漫画")
        try validateID(json, key: "chapter_id", expected: expectedChapterId, label: "章节")
        try validateID(json, key: "chapterId", expected: expectedChapterId, label: "章节")
        guard let values = json["images"] as? [Any], !values.isEmpty else { throw sourceError("章节解析失败：缺少正文图片") }
        var seen = Set<String>(), images: [String] = []
        for item in values {
            guard let item = item as? String else { throw sourceError("章节解析失败：图片地址无效") }
            let image = item.replacingOccurrences(of: #"\/"#, with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
            guard image.hasPrefix("http://") || image.hasPrefix("https://") else { throw sourceError("章节解析失败：图片地址无效") }
            if seen.insert(image).inserted { images.append(image) }
        }
        guard !images.isEmpty else { throw sourceError("章节解析失败：正文图片为空") }
        return images
    }

    private static func intValue(_ value: Any?, default fallback: Int) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String, let parsed = Int(value) { return parsed }
        return fallback
    }

    private static func validateID(_ json: [String: Any], key: String, expected: String, label: String) throws {
        guard !expected.isEmpty, json.keys.contains(key) else { return }
        let actual = (json[key] as? String) ?? (json[key] as? NSNumber)?.stringValue ?? ""
        if !actual.isEmpty, actual != expected { throw sourceError("章节\(label) ID 不匹配") }
    }

    private func categoryPath(filters: [String: String], page: Int) -> String {
        var selected = ""
        for key in ["classification", "subject", "type", "quality", "region", "copyright", "state"] {
            if let value = filters[key], !value.isEmpty, value != "all" { selected = value; break }
        }
        var path = "/category" + (selected.isEmpty ? "" : selected.hasPrefix("/") ? selected : "/" + selected)
        if page > 1 { path += "/page/\(page)" }
        return path
    }

    private func fetch(_ path: String, chapter: Bool = false) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: absolute(path)), ["http", "https"].contains(url.scheme ?? "") else { throw URLError(.badURL) }
        let response = try await (chapter ? chapterTransport : transport).get(url, headers: [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Referer": referer,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Accept-Encoding": "gzip"
        ])
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard let html = String(data: response.data, encoding: .utf8) else { throw error("响应文字解码失败") }
        return html
    }

    private func parseCards(_ html: String) throws -> [ComicSummary] {
        let lists = matches(#"<div[^>]*class=["'][^"']*\bcy_list_mh\b[^"']*["'][^>]*>([\s\S]*?)</div>"#, html)
        guard !lists.isEmpty else { throw error("列表解析失败") }
        var seen = Set<String>(), result: [ComicSummary] = []
        for list in lists {
            for item in matches(#"<ul[^>]*>([\s\S]*?)</ul>"#, list[1]) {
                let card = item[1]
                let picture = raw(#"<a[^>]*class=["'][^"']*\bpic\b[^"']*["'][^>]*>"#, card)
                let rawID = rawComicID(attribute("href", picture))
                guard !rawID.isEmpty, seen.insert(rawID).inserted else { continue }
                let image = raw(#"<img[^>]*>"#, card)
                let titleBlock = first(#"<li[^>]*class=["'][^"']*\btitle\b[^"']*["'][^>]*>([\s\S]*?)</li>"#, card)
                var title = clean(first(#"<a[^>]*>([\s\S]*?)</a>"#, titleBlock))
                if title.isEmpty { title = clean(attribute("alt", image)).replacingOccurrences(of: #"漫画$"#, with: "", options: .regularExpression) }
                guard !title.isEmpty else { continue }
                let status = clean(first(#"<li[^>]*class=["'][^"']*\bzuozhe\b[^"']*["'][^>]*>([\s\S]*?)</li>"#, card)).replacingOccurrences(of: #"^状态[：:]\s*"#, with: "", options: .regularExpression)
                let latest = clean(first(#"<li[^>]*class=["'][^"']*\bupdata\b[^"']*["'][^>]*>([\s\S]*?)</li>"#, card))
                let description = clean(first(#"<li[^>]*class=["'][^"']*\binfo\b[^"']*["'][^>]*>([\s\S]*?)</li>"#, card))
                let subtitle = !status.isEmpty ? status : !latest.isEmpty ? latest : description
                result.append(.init(sourceId: id, comicId: id + ":" + rawID, title: title, coverUrl: absolute(imageURL(image)), subtitle: subtitle, tags: linkTexts(first(#"<li[^>]*class=["'][^"']*\bbiaoqian\b[^"']*["'][^>]*>([\s\S]*?)</li>"#, card))))
            }
        }
        return result
    }

    private func parseFilterGroups(_ html: String) -> [SourceFilterGroup] {
        matches(#"<div[^>]*class=["'][^"']*\bcy_tag\b[^"']*["'][^>]*>([\s\S]*?)</div>"#, html).compactMap { match in
            let block = match[1], original = clean(first(#"<span[^>]*>([\s\S]*?)</span>"#, block))
            guard let key = ["分类": "classification", "题材": "subject", "标签": "subject", "类型": "type", "品质": "quality", "地区": "region", "版权": "copyright", "进度": "state"][original] else { return nil }
            var seen = Set(["全部"]), options = [SourceFilterOption(label: "全部", value: "all")]
            for link in matches(#"<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#, block) {
                let label = clean(link[2]), value = filterPath(link[1])
                if !label.isEmpty, label != "全部", !value.isEmpty, seen.insert(label).inserted { options.append(.init(label: label, value: value)) }
            }
            return .init(key: key, label: original == "标签" ? "题材" : original == "进度" ? "状态" : original, options: options)
        }
    }

    private func parseDetail(rawID: String, html: String, includeChapters: Bool) throws -> ComicDetail {
        guard html.range(of: #"class=["'][^"']*\bcy_title\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { throw error("详情解析失败：缺少站点结构") }
        let title = clean(first(#"<div[^>]*class=["'][^"']*\bcy_title\b[^"']*["'][^>]*>[\s\S]*?<h1[^>]*>([\s\S]*?)</h1>"#, html))
        guard !title.isEmpty else { throw error("详情解析失败：缺少标题") }
        let coverBlock = first(#"<[^>]*class=["'][^"']*\bcy_info_cover\b[^"']*["'][^>]*>([\s\S]*?)</(?:div|a)>"#, html)
        let author = labelled(html, label: "作者"), status = labelled(html, label: "状态"), latest = labelled(html, label: "最新")
        let tags = linkTexts(first(#"<[^>]*class=["'][^"']*\bcy_type\b[^"']*["'][^>]*>([\s\S]*?)</(?:span|div)>"#, html))
        return .init(summary: .init(sourceId: id, comicId: id + ":" + rawID, title: title, coverUrl: absolute(imageURL(raw(#"<img[^>]*>"#, coverBlock))), subtitle: author, tags: tags), author: author, status: status, description: clean(first(#"<[^>]*id=["']comic-description["'][^>]*>([\s\S]*?)</(?:p|div)>"#, html)), latestChapter: latest, chapters: includeChapters ? parseChapters(html, comicID: rawID) : [])
    }

    private func parseChapters(_ html: String, comicID: String) -> [Chapter] {
        var seen = Set<String>(), result: [Chapter] = []
        if let catalog = elementContentByClass(html, "cy_plist") {
            for match in matches(#"<li[^>]*class=["'][^"']*\bchapter__item\b[^"']*["'][^>]*>[\s\S]*?<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>[\s\S]*?</li>"#, catalog) {
                let href = decode(match[1])
                guard href.range(of: "^/" + NSRegularExpression.escapedPattern(for: comicID) + #"/[^/]+\.html(?:[?#].*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil else { continue }
                let url = absolute(href), title = clean(match[2])
                guard !title.isEmpty, seen.insert(url).inserted else { continue }
                result.append(.init(chapterId: chapterID(url), title: title, url: url, chapterSlot: result.count))
            }
        }
        if !result.isEmpty { return result }
        if let onlineBlock = elementContentByClass(html, "cy_kan") {
            let href = decode(first(#"<a[^>]*href=["']([^"']+)["'][^>]*>"#, onlineBlock))
            if href.range(of: "^/" + NSRegularExpression.escapedPattern(for: comicID) + #"/[^/]+\.html(?:[?#].*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                let url = absolute(href)
                result.append(.init(chapterId: chapterID(url), title: "在线阅读", url: url))
            }
        }
        return result
    }

    private func elementContentByClass(_ html: String, _ className: String) -> String? {
        let openingPattern = "<([a-z0-9]+)[^>]*class=[\"'][^\"']*\\b" + NSRegularExpression.escapedPattern(for: className) + #"\b[^"']*["'][^>]*>"#
        guard let opening = matches(openingPattern, html).first, let openingRange = html.range(of: opening[0]) else { return nil }
        let tag = opening[1], tail = String(html[openingRange.upperBound...])
        guard let regex = try? NSRegularExpression(pattern: "</?" + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#, options: .caseInsensitive) else { return nil }
        var depth = 1
        for match in regex.matches(in: tail, range: NSRange(tail.startIndex..., in: tail)) {
            guard let range = Range(match.range, in: tail) else { continue }
            depth += tail[range].hasPrefix("</") ? -1 : 1
            if depth == 0 { return String(tail[..<range.lowerBound]) }
        }
        return String(tail)
    }

    private func labelled(_ html: String, label: String) -> String {
        clean(first("(?:<span|<p|<li)[^>]*>([\\s\\S]*?" + NSRegularExpression.escapedPattern(for: label) + #"[：:][\s\S]*?)</(?:span|p|li)>"#, html)).replacingOccurrences(of: "^.*?" + NSRegularExpression.escapedPattern(for: label) + #"[：:]\s*"#, with: "", options: .regularExpression)
    }

    private func filterPath(_ href: String) -> String {
        var value = decode(href).trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://www.liumanhua.com", "http://www.liumanhua.com"] where value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
        if value.hasPrefix("/category") { value.removeFirst("/category".count) }
        value = value.components(separatedBy: "?")[0]
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty || value == "/" ? "all" : value
    }

    private func linkTexts(_ html: String) -> [String] {
        var seen = Set<String>()
        return matches(#"<a[^>]*>([\s\S]*?)</a>"#, html).map { clean($0[1]) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private func rawComicID(_ input: String) -> String {
        var value = input.hasPrefix(id + ":") ? String(input.dropFirst(id.count + 1)) : input
        value = decode(value).components(separatedBy: "?")[0]
        while value.hasSuffix("/") { value.removeLast() }
        return value.split(separator: "/").last.map(String.init) ?? value
    }
    private func chapterID(_ input: String) -> String {
        let value = input.components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
        return (value.split(separator: "/").last.map(String.init) ?? value).replacingOccurrences(of: #"\.html$"#, with: "", options: .regularExpression)
    }
    private func imageURL(_ tag: String) -> String {
        for key in ["data-original", "data-src", "src"] { let value = attribute(key, tag); if !value.isEmpty { return value } }
        return ""
    }
    private func absolute(_ input: String) -> String {
        let value = decode(input).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        if value.hasPrefix("//") { return "https:" + value }
        return value.isEmpty ? "" : baseURL + (value.hasPrefix("/") ? value : "/" + value)
    }
    private func attribute(_ name: String, _ html: String) -> String { decode(first("\\b" + NSRegularExpression.escapedPattern(for: name) + #"=["']([^"']*)["']"#, html)) }
    private func clean(_ value: String) -> String {
        HTML4EntityDecoder.decode(value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func decode(_ value: String) -> String { HTML4EntityDecoder.decode(value) }
    private func matches(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" } }
    }
    private func first(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[1] ?? "" }
    private func raw(_ pattern: String, _ value: String) -> String { matches(pattern, value).first?[0] ?? "" }
    private func error(_ message: String) -> NSError { Self.sourceError(message) }
    private static func sourceError(_ message: String) -> NSError { NSError(domain: "LiumanhuaComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: "六漫画" + message]) }
}
