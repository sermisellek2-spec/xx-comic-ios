import Foundation

public enum BaoziSourceError: Error, Equatable, Sendable {
    case invalidURL(String)
    case invalidResponse(String)
}

public actor BaoziComicSource: ComicSource {
    public nonisolated let id = "baozimh"
    public nonisolated let name = "包子漫画"
    public nonisolated let referer = "https://cn.dzmanga.com/"

    private static let baseURL = "https://cn.dzmanga.com"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private static let categoryAPI = "/api/bzmhq/amp_comic_list?type={type}&region={region}&state={state}&filter={filter}&page={page}&limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.dzmanga.com"
    private static let cardPattern = #"<div class="comics-card[\s\S]*?<a href="([^"]+)" title="([^"]+)"[\s\S]*?src="([^"]+)"[\s\S]*?<small class="tags text-truncate">([\s\S]*?)</small>"#
    private static let metaPattern = #"<meta[^>]+(?:name|property|data-hid)="([^"]+)"[^>]+content="([^"]*)""#
    private static let chapterPattern = #"<a href="([^"]*page_direct[^"]*)"[^>]*class="comics-chapters__item"[\s\S]*?<span[^>]*>([\s\S]*?)</span>"#
    private static let imagePattern = #"<amp-img[^>]+(?:data-src|src)="(https://[^"]+?\.(?:jpg|jpeg|png|webp)[^"]*)"#
    private static let nextPagePattern = #"<div class="next_chapter">[\s\S]*?<a href="([^"]+)""#

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let path = page <= 1 ? "/list/new" : "/list/new/\(page)"
        return try parseCards(await fetch(absolute(path)))
    }

    public func search(keyword: String, page _: Int) async throws -> [ComicSummary] {
        try parseCards(await fetch(absolute("/search?q=\(formEncode(keyword))")))
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let html = try await fetch(absolute("/comic/\(comicId)"))
        try requireHTML(html, context: "包子漫画详情解析失败")
        let title = meta("og:novel:book_name", in: html)
        guard !title.isEmpty else { throw BaoziSourceError.invalidResponse("包子漫画详情解析失败") }
        let author = meta("og:novel:author", in: html)
        let status = meta("og:novel:status", in: html)
        let description = meta("og:description", in: html)
        let latest = meta("og:novel:latest_chapter_name", in: html)
        let cover = cleanURL(meta("og:image", in: html))
        let tags = meta("og:novel:category", in: html).split(separator: ",").compactMap { raw -> String? in
            let tag = clean(String(raw))
            return tag.isEmpty || tag.hasPrefix("types.") ? nil : tag
        }
        return ComicDetail(
            summary: ComicSummary(sourceId: id, comicId: comicId, title: title, coverUrl: cover, subtitle: latest, tags: tags),
            author: author, status: status, description: description, latestChapter: latest, chapters: []
        )
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let html = try await fetch(absolute("/comic/\(comicId)"))
        let chapterMatches = matches(Self.chapterPattern, in: html)
        guard !chapterMatches.isEmpty || hasClass("comics-chapters", in: html) else {
            throw BaoziSourceError.invalidResponse("包子漫画目录解析失败")
        }
        return chapterMatches.map { match in
            let url = absolute(htmlDecode(match[1]))
            let section = queryInt("section_slot", in: url)
            let chapter = queryInt("chapter_slot", in: url)
            return Chapter(chapterId: "\(section)_\(chapter)", title: clean(match[2]), url: url, sectionSlot: section, chapterSlot: chapter)
        }.sorted {
            $0.sectionSlot == $1.sectionSlot ? $0.chapterSlot < $1.chapterSlot : $0.sectionSlot < $1.sectionSlot
        }
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let requestURL = absolute(url)
        let html = try await fetch(requestURL)
        let imageMatches = matches(Self.imagePattern, in: html)
        var imageURLs: [String] = []
        var seen = Set<String>()
        for match in imageMatches {
            let imageURL = cleanURL(match[1])
            if imageURL.contains("/scomic/"), seen.insert(imageURL).inserted { imageURLs.append(imageURL) }
        }
        guard !imageURLs.isEmpty || hasClass("comic-contain", in: html) else {
            throw BaoziSourceError.invalidResponse("包子漫画图片解析失败")
        }
        let title = firstMatch(#"<title>([\s\S]*?)</title>"#, in: html).map(clean) ?? ""
        let nextPage = firstMatch(Self.nextPagePattern, in: html).map { absolute(htmlDecode($0)) } ?? ""
        return ChapterPage(chapterId: url, title: title, nextPageUrl: nextPage, imageUrls: imageURLs)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        [
            group("region", "地区", [("全部", "all"), ("国漫", "cn"), ("日本", "jp"), ("韩国", "kr"), ("欧美", "en")]),
            group("state", "状态", [("全部", "all"), ("连载中", "serial"), ("已完结", "pub")]),
            group("type", "题材", [
                ("全部", "all"), ("恋爱", "lianai"), ("纯爱", "chunai"), ("古风", "gufeng"),
                ("异能", "yineng"), ("悬疑", "xuanyi"), ("剧情", "juqing"), ("科幻", "kehuan"),
                ("奇幻", "qihuan"), ("玄幻", "xuanhuan"), ("穿越", "chuanyue"), ("冒险", "mouxian"),
                ("推理", "tuili"), ("武侠", "wuxia"), ("格斗", "gedou"), ("战争", "zhanzheng"),
                ("热血", "rexie"), ("搞笑", "gaoxiao"), ("大女主", "danuzhu"), ("都市", "dushi"),
                ("总裁", "zongcai"), ("后宫", "hougong"), ("日常", "richang"), ("韩漫", "hanman"),
                ("少年", "shaonian"), ("其它", "qita")
            ]),
            group("filter", "字母", [
                ("全部", "*"), ("ABCD", "ABCD"), ("EFGH", "EFGH"), ("IJKL", "IJKL"),
                ("MNOP", "MNOP"), ("QRST", "QRST"), ("UVW", "UVW"), ("XYZ", "XYZ"), ("0-9", "0-9")
            ])
        ]
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let type = filter(filters["type"], default: "all")
        let region = filter(filters["region"], default: "all")
        let state = filter(filters["state"], default: "all")
        let letter = filter(filters["filter"], default: "*")
        let route = page > 1 ? Self.categoryAPI : "/classify?type={type}&region={region}&state={state}&filter={filter}{pageQuery}"
        var path = route
            .replacingOccurrences(of: "{type}", with: type)
            .replacingOccurrences(of: "{region}", with: region)
            .replacingOccurrences(of: "{state}", with: state)
            .replacingOccurrences(of: "{filter}", with: letter)
            .replacingOccurrences(of: "{page}", with: String(page))
            .replacingOccurrences(of: "{pageQuery}", with: page > 1 ? "&page=\(page)" : "")
        path = withCategoryFilters(absolute(path), type: type, region: region, state: state, filter: letter, page: page)
        let body = try await fetch(path)
        return page > 1 ? try parseAPICards(body) : try parseCards(body)
    }

    private func parseCards(_ html: String) throws -> [ComicSummary] {
        let cardMatches = matches(Self.cardPattern, in: html)
        guard !cardMatches.isEmpty || hasClass("comics-list", in: html) else {
            throw BaoziSourceError.invalidResponse("包子漫画列表解析失败")
        }
        return cardMatches.map { match in
            let subtitle = clean(match[4])
            return ComicSummary(
                sourceId: id,
                comicId: comicID(from: htmlDecode(match[1])),
                title: clean(match[2]),
                coverUrl: cleanURL(match[3]),
                subtitle: subtitle,
                tags: parseTags(subtitle)
            )
        }
    }

    private func parseAPICards(_ json: String) throws -> [ComicSummary] {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
            let root = object as? [String: Any],
            let items = root["items"] as? [Any]
        else { throw BaoziSourceError.invalidResponse("包子漫画分类解析失败") }
        return try items.compactMap { raw in
            guard let item = raw as? [String: Any] else { throw BaoziSourceError.invalidResponse("包子漫画分类解析失败") }
            let comicID = string(item["comic_id"])
            guard !comicID.isEmpty else { return nil }
            var tags: [String] = []
            var seen = Set<String>()
            if let typeNames = item["type_names"] as? [Any] {
                for value in typeNames {
                    let tag = clean(string(value))
                    if !tag.isEmpty, seen.insert(tag).inserted { tags.append(tag) }
                }
            } else if item["type_names"] != nil {
                throw BaoziSourceError.invalidResponse("包子漫画分类解析失败")
            }
            return ComicSummary(
                sourceId: id, comicId: comicID, title: clean(string(item["name"])),
                coverUrl: coverURL(string(item["topic_img"])), subtitle: clean(string(item["author"])), tags: tags
            )
        }
    }

    private func fetch(_ urlString: String) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: urlString) else { throw BaoziSourceError.invalidURL(urlString) }
        let response = try await transport.get(url, headers: ["User-Agent": Self.userAgent, "Referer": referer])
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard let text = String(data: response.data, encoding: .utf8) else { throw BaoziSourceError.invalidResponse("响应不是 UTF-8") }
        return text
    }

    private func withCategoryFilters(_ url: String, type: String, region: String, state: String, filter: String, page: Int) -> String {
        let fragmentParts = url.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let fragment = fragmentParts.count == 2 ? "#\(fragmentParts[1])" : ""
        let queryParts = fragmentParts[0].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let base = String(queryParts[0])
        let replaced = Set(["type", "region", "state", "filter", "page"])
        var parts = queryParts.count == 2 ? queryParts[1].split(separator: "&").map(String.init).filter {
            !replaced.contains($0.split(separator: "=", maxSplits: 1).first.map(String.init) ?? $0)
        } : []
        parts += ["type=\(type)", "region=\(region)", "state=\(state)", "filter=\(filter)"]
        if page > 1 { parts.append("page=\(page)") }
        return "\(base)?\(parts.joined(separator: "&"))\(fragment)"
    }

    private func absolute(_ rawValue: String) -> String {
        let value = rawValue.replacingOccurrences(
            of: #"^(?:https?:)?//(?:cn\.bzmgcn\.com|www\.baozimh\.com|www\.twmanga\.com)(?=[/:?#]|$)"#,
            with: Self.baseURL,
            options: .regularExpression
        )
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        if value.hasPrefix("//") { return "https:\(value)" }
        return Self.baseURL + (value.hasPrefix("/") ? value : "/\(value)")
    }

    private func comicID(from href: String) -> String {
        guard let range = href.range(of: "/comic/", options: .backwards) else {
            return href.replacingOccurrences(of: "/comic/", with: "")
        }
        return String(href[range.upperBound...])
    }

    private func queryInt(_ key: String, in url: String) -> Int {
        guard let components = URLComponents(string: url) else { return 0 }
        return Int(components.queryItems?.first(where: { $0.name == key })?.value ?? "") ?? 0
    }

    private func meta(_ key: String, in html: String) -> String {
        matches(Self.metaPattern, in: html).first(where: { $0[1] == key }).map { clean($0[2]) } ?? ""
    }

    private func parseTags(_ value: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for part in value.components(separatedBy: CharacterSet(charactersIn: ",，/|· \t\r\n")) {
            let tag = clean(part)
            if !tag.isEmpty, !tag.contains("最新"), !tag.contains("更新"), seen.insert(tag).inserted { result.append(tag) }
        }
        return result
    }

    private func clean(_ value: String) -> String {
        htmlDecode(value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func htmlDecode(_ value: String) -> String { HTML4EntityDecoder.decode(value) }

    private func cleanURL(_ value: String) -> String {
        let decoded = htmlDecode(value).replacingOccurrences(of: "\\/", with: "/")
        return decoded.firstIndex(of: "&").map { String(decoded[..<$0]) } ?? decoded
    }

    private func coverURL(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        return "https://static-tw.baozimh.com/cover/\(value)?w=285&h=375&q=100"
    }

    private func formEncode(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        return value.utf8.map { byte -> String in
            let scalar = Character(UnicodeScalar(byte))
            if scalar == " " { return "+" }
            if allowed.contains(scalar) { return String(scalar) }
            return String(format: "%%%02X", byte)
        }.joined()
    }

    private func requireHTML(_ value: String, context: String) throws {
        guard value.range(of: #"<(?:!doctype|html|head|body|main|section|article|div)\b"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            throw BaoziSourceError.invalidResponse(context)
        }
    }

    private func hasClass(_ name: String, in html: String) -> Bool {
        matches(#"class\s*=\s*["']([^"']*)["']"#, in: html).contains { match in
            match[1].split(whereSeparator: \.isWhitespace).contains(Substring(name))
        }
    }

    private func filter(_ value: String?, default fallback: String) -> String {
        guard let value, !value.isEmpty else { return fallback }
        return value
    }

    private func group(_ key: String, _ label: String, _ options: [(String, String)]) -> SourceFilterGroup {
        SourceFilterGroup(key: key, label: label, options: options.map { SourceFilterOption(label: $0.0, value: $0.1) })
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { result in
            (0..<result.numberOfRanges).map { index in
                guard result.range(at: index).location != NSNotFound, let range = Range(result.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let match = matches(pattern, in: text).first, match.count > 1 else { return nil }
        return match[1]
    }

    private func string(_ value: Any?) -> String {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return ""
        }
    }
}
