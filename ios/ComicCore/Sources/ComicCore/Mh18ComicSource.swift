import Foundation

public enum Mh18SourceError: Error, Equatable, Sendable {
    case verificationRequired
    case invalidResponse(String)
}

extension Mh18SourceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .verificationRequired: return "18漫画需要浏览器验证，请前往站源管理完成验证。"
        case .invalidResponse(let message): return message
        }
    }
}

public actor Mh18ComicSource: ComicSource {
    public nonisolated let id = "mh18"
    public nonisolated let name: String
    public nonisolated let referer: String
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let browserSession: (any ComicBrowserSession)?
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private static let cardPattern = #"<a[^>]+href="([^"]*?/manga/[^"]+)"[\s\S]{0,900}?<img[^>]+(?:src|data-src)="([^"]+)"[\s\S]{0,900}?<h3[^>]*class="[^"]*cardtitle[^"]*"[^>]*>([\s\S]*?)</h3>"#

    public init(baseURL: URL = URL(string: "https://18mh.org")!, name: String = "18漫画", transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 15), browserSession: (any ComicBrowserSession)? = nil) {
        self.name = name
        self.baseURL = baseURL
        self.transport = transport
        self.browserSession = browserSession
        referer = baseURL.absoluteString.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression) + "/"
    }

    public static func hasCatalogMarker(_ html: String) -> Bool { !matches(cardPattern, in: html).isEmpty }

    public func verifyAccess() async throws {
        let html = try await fetch("/manga", interactive: true)
        guard Self.hasCatalogMarker(html) else { throw Mh18SourceError.invalidResponse(name + " 页面未就绪") }
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        try await category(filters: [:], page: page)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        let encoded = keyword.trimmingCharacters(in: .whitespacesAndNewlines).utf8.map { byte -> String in
            let character = Character(UnicodeScalar(byte))
            if character == " " { return "+" }
            return allowed.contains(character) ? String(character) : String(format: "%%%02X", byte)
        }.joined()
        return try parseCards(await fetch("/s/" + encoded + (page > 1 ? "/page/\(page)" : "")))
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let tag = filters["tag"].flatMap { $0.isEmpty ? nil : $0 } ?? "all"
        let genre = filters["genre"].flatMap { $0.isEmpty ? nil : $0 } ?? "all"
        let path = tag != "all" ? "/manga-tag/" + tag : genre != "all" ? "/manga-genre/" + genre : "/manga"
        return try parseCards(await fetch(path + (page > 1 ? "/page/\(page)" : "")))
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let html = try await fetch("/manga")
        var options: [String: [SourceFilterOption]] = ["genre": [], "tag": []]
        for link in Self.matches(#"<a[^>]+href=["']/(manga-(genre|tag)/([^/"']+))["'][^>]*>[\s\S]*?<button[^>]*>([\s\S]*?)</button>[\s\S]*?</a>"#, in: html) {
            let label = Self.clean(link[4]).replacingOccurrences(of: "^#", with: "", options: .regularExpression)
            guard !label.isEmpty else { continue }
            let key = link[2].lowercased()
            let option = SourceFilterOption(label: label, value: link[3])
            if let index = options[key]?.firstIndex(where: { $0.label == label }) { options[key]?[index] = option }
            else { options[key]?.append(option) }
        }
        guard options["genre"]?.isEmpty == false, options["tag"]?.isEmpty == false else {
            throw Mh18SourceError.invalidResponse(name + " 分类解析失败")
        }
        return [("genre", "漫画类型"), ("tag", "热门标签")].map { key, label in
            .init(key: key, label: label, options: [.init(label: "全部", value: "all")] + (options[key] ?? []).filter { $0.label != "全部" })
        }
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = Self.rawComicID(comicId)
        let html = try await fetch("/manga/" + rawID)
        var data: [String: Any] = [:]
        for script in Self.matches(#"<script\b([^>]*)>([\s\S]*?)</script>"#, in: html) {
            guard Self.attribute("type", in: script[1]).lowercased() == "application/ld+json",
                  let parsed = try? JSONSerialization.jsonObject(with: Data(script[2].utf8)),
                  let comic = Self.structuredComic(parsed) else { continue }
            data = comic
            break
        }
        var title = Self.clean(data["name"] as? String ?? "")
        if title.isEmpty { title = Self.meta("og:title", in: html).replacingOccurrences(of: #"-18漫畫\s*-?\s*18漫畫$"#, with: "", options: .regularExpression) }
        guard !title.isEmpty else { throw Mh18SourceError.invalidResponse("18漫画详情解析失败") }
        let image = data["image"] as? [String: Any]
        var cover = Self.clean(image?["url"] as? String ?? data["image"] as? String ?? "")
        if cover.isEmpty { cover = Self.meta("og:image", in: html) }
        var description = Self.clean(data["description"] as? String ?? "")
        if description.isEmpty { description = Self.meta("description", in: html) }
        var tags = Self.strings(data["genre"])
        if tags.isEmpty {
            for link in Self.matches(#"<a[^>]+href=["']/manga-tag/[^"']+["'][^>]*>([\s\S]*?)</a>"#, in: html) {
                let tag = Self.clean(link[1]).replacingOccurrences(of: "^#", with: "", options: .regularExpression)
                if !tag.isEmpty && !tags.contains(tag) { tags.append(tag) }
            }
        }
        let authors = (data["author"] as? [Any] ?? data["author"].map { [$0] } ?? []).compactMap { value -> String? in
            let name = Self.clean((value as? [String: Any])?["name"] as? String ?? value as? String ?? "")
            return name.isEmpty ? nil : name
        }
        return .init(summary: .init(sourceId: id, comicId: "mh18:" + rawID, title: title, coverUrl: Self.cleanURL(cover), tags: tags),
                     author: authors.joined(separator: " / "),
                     status: Self.clean(data["creativeWorkStatus"] as? String ?? "").replacingOccurrences(of: "連載中", with: "连载中").replacingOccurrences(of: "完結", with: "已完结"),
                     description: description, latestChapter: Self.clean((data["hasPart"] as? [String: Any])?["name"] as? String ?? ""), chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let rawID = Self.rawComicID(comicId)
        let catalog = try await fetch("/chapterlist/" + rawID)
        let holder = Self.tag(id: "allchapters", in: catalog)
        let mangaID = Self.attribute("data-mid", in: holder)
        let error = "18漫画目录参数解析失败"
        guard Self.isNumeric(mangaID) else { throw Mh18SourceError.invalidResponse(error) }
        let api = try trustedAPIBase(holder, error: error)
        let html = try await fetch(api + "/manga/get?mid=\(mangaID)&mode=all")
        var result: [Chapter] = []
        var seen = Set<String>()
        let route = #"^(?:https?://[^/]+)?/manga/"# + NSRegularExpression.escapedPattern(for: rawID) + #"/[^/?#]+$"#
        for anchor in Self.matches(#"<a\b[^>]*>"#, in: html) {
            let href = Self.attribute("href", in: anchor[0])
            guard href.range(of: route, options: .regularExpression) != nil, seen.insert(href).inserted else { continue }
            let chapterID = Self.attribute("data-cs", in: anchor[0])
            let title = Self.clean(Self.attribute("data-ct", in: anchor[0]))
            guard !chapterID.isEmpty, !title.isEmpty else { continue }
            result.append(.init(chapterId: chapterID, title: title, url: try absolute(href).absoluteString, chapterSlot: result.count))
        }
        guard !result.isEmpty else { throw Mh18SourceError.invalidResponse("18漫画目录解析失败") }
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let html = try await fetch(url)
        let holder = Self.tag(id: "chapterContent", in: html)
        let mangaID = Self.attribute("data-ms", in: holder)
        let chapterID = Self.attribute("data-cs", in: holder)
        let error = "18漫画章节参数解析失败"
        guard Self.isNumeric(mangaID), Self.isNumeric(chapterID) else { throw Mh18SourceError.invalidResponse(error) }
        let api = try trustedAPIBase(holder, error: error)
        let content = try await fetch(api + "/chapter/getcontent?m=\(mangaID)&c=\(chapterID)")
        var images: [String] = []
        var seen = Set<String>()
        for image in Self.matches(#"<img\b[^>]*>"#, in: content) {
            var value = Self.attribute("data-src", in: image[0])
            if value.isEmpty { value = Self.attribute("src", in: image[0]) }
            value = Self.cleanURL(value)
            if (value.hasPrefix("http://") || value.hasPrefix("https://")), seen.insert(value).inserted { images.append(value) }
        }
        guard !images.isEmpty else { throw Mh18SourceError.invalidResponse("18漫画正文图片解析失败") }
        return .init(chapterId: url, title: Self.clean(Self.attribute("data-ct", in: holder)), nextPageUrl: "", imageUrls: images)
    }

    private func fetch(_ value: String, interactive: Bool = false) async throws -> String {
        try Task.checkCancellation()
        let url = try absolute(value)
        let html: String
        if let browserSession, isMainSite(url) {
            html = try await (interactive ? browserSession.fetchInteractive(url) : browserSession.fetch(url))
            try Task.checkCancellation()
            if Mh18VerificationRules.isChallenge(body: html) { throw Mh18SourceError.verificationRequired }
        } else {
            let response = try await transport.get(url, headers: ["User-Agent": Self.userAgent, "Referer": referer])
            try Task.checkCancellation()
            let mitigated = response.headerValue(for: "cf-mitigated")
            if response.statusCode == 403 && mitigated?.lowercased() == "challenge" { throw Mh18SourceError.verificationRequired }
            guard let body = String(data: response.data, encoding: .utf8) else {
                if !(200..<400).contains(response.statusCode) { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
                throw Mh18SourceError.invalidResponse("响应不是 UTF-8")
            }
            switch Mh18VerificationRules.httpAction(statusCode: response.statusCode, mitigated: mitigated, body: body) {
            case .verificationRequired: throw Mh18SourceError.verificationRequired
            case .fail: throw HTTPTransportError.invalidStatusCode(response.statusCode)
            case .returnBody: html = body
            }
        }
        return html
    }

    private func parseCards(_ html: String) throws -> [ComicSummary] {
        var seen = Set<String>()
        let cards = Self.matches(Self.cardPattern, in: html).compactMap { match -> ComicSummary? in
            let rawID = Self.rawComicID(HTML4EntityDecoder.decode(match[1]))
            guard !rawID.isEmpty, seen.insert(rawID).inserted else { return nil }
            var title = Self.clean(match[3])
            if title.range(of: #"^[a-z0-9\-]+$"#, options: .regularExpression) != nil { title = rawID.replacingOccurrences(of: "-", with: " ") }
            return .init(sourceId: id, comicId: "mh18:" + rawID, title: title, coverUrl: Self.cleanURL(match[2]))
        }
        guard !cards.isEmpty else { throw Mh18SourceError.invalidResponse("18漫画列表解析失败") }
        return cards
    }

    private func trustedAPIBase(_ tag: String, error: String) throws -> String {
        guard let url = URL(string: Self.attribute("data-host", in: tag)), url.scheme?.lowercased() == "https",
              isMainSite(url), url.port == nil || url.port == 443, let host = url.host?.lowercased() else {
            throw Mh18SourceError.invalidResponse(error)
        }
        return "https://" + host
    }

    private func isMainSite(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), let root = baseURL.host?.lowercased(), !root.isEmpty else { return false }
        return host == root || host.hasSuffix("." + root)
    }

    private func absolute(_ value: String) throws -> URL {
        let string: String
        if value.hasPrefix("http://") || value.hasPrefix("https://") { string = value }
        else if value.hasPrefix("//") { string = "https:" + value }
        else { string = referer + (value.hasPrefix("/") ? String(value.dropFirst()) : value) }
        guard let url = URL(string: string) else { throw Mh18SourceError.invalidResponse("18漫画链接无效") }
        return url
    }

    private static func structuredComic(_ value: Any) -> [String: Any]? {
        if let object = value as? [String: Any] {
            let types = object["@type"] as? [String] ?? (object["@type"] as? String).map { [$0] } ?? []
            if types.contains(where: { $0.lowercased() == "comicseries" }) { return object }
            if let graph = object["@graph"] { return structuredComic(graph) }
        } else if let array = value as? [Any] {
            for element in array { if let result = structuredComic(element) { return result } }
        }
        return nil
    }

    private static func strings(_ value: Any?) -> [String] {
        let values = value as? [String] ?? (value as? String).map { [$0] } ?? []
        return values.map(clean).filter { !$0.isEmpty }
    }

    private static func meta(_ key: String, in html: String) -> String {
        for tag in matches(#"<meta\b[^>]*>"#, in: html) {
            if attribute("property", in: tag[0]).lowercased() == key.lowercased() || attribute("name", in: tag[0]).lowercased() == key.lowercased() {
                return clean(attribute("content", in: tag[0]))
            }
        }
        return ""
    }

    private static func rawComicID(_ value: String) -> String {
        var value = value.hasPrefix("mh18:") ? String(value.dropFirst(5)) : value
        if let manga = value.range(of: "/manga/") { value = String(value[manga.upperBound...]) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tag(id: String, in html: String) -> String {
        matches(#"<[^>]+>"#, in: html).first { attribute("id", in: $0[0]) == id }?.first ?? ""
    }

    private static func attribute(_ name: String, in tag: String) -> String {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(["'])([\s\S]*?)\1"#
        return HTML4EntityDecoder.decode(matches(pattern, in: tag).first?[2] ?? "")
    }

    private static func isNumeric(_ value: String) -> Bool { value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil }
    private static func cleanURL(_ value: String) -> String { HTML4EntityDecoder.decode(value).replacingOccurrences(of: #"\/"#, with: "/").trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func clean(_ value: String) -> String {
        HTML4EntityDecoder.decode(value).replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ pattern: String, in html: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: html).map { String(html[$0]) } ?? ""
            }
        }
    }
}
