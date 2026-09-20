import Foundation

public enum GmhSourceError: Error, Equatable, Sendable {
    case invalidURL(String)
    case invalidResponse(String)
    case missingMangaID(String)
    case chapterNotFound(String)
    case imageDecryptionFailed
}

public actor GmhComicSource: ComicSource {
    public nonisolated let id = "gmh"
    public nonisolated let name = "G社漫画"
    public nonisolated let referer = "https://m.g-mh.org/"

    private static let baseURL = "https://m.g-mh.org"
    private static let mangaAPI = "https://v2.apikk.top/api/v2/manga/get?mid=%@&mode=all"
    private static let chapterAPI = "https://v2.apikk.top/api/v2/chapter/getinfo?m=%@&c=%@"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private static let cardPattern = #"<a[^>]+href="([^"]*?/manga/[^"]+)"[\s\S]{0,900}?<img[^>]+(?:src|data-src)="([^"]+)"[\s\S]{0,900}?<h3[^>]*class="[^"]*cardtitle[^"]*"[^>]*>([\s\S]*?)</h3>"#
    private static let filterPattern = #"<a[^>]+href=["']/(manga-(genre|tag)/([^/"']+))["'][^>]*>[\s\S]*?<button[^>]*>([\s\S]*?)</button>[\s\S]*?</a>"#
    private static let sourceAlphabet = "_-9876543210abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let targetAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    private let transport: any HTTPTransport
    private var midCache: [String: String] = [:]
    private var mangaCache: [String: [String: Any]] = [:]

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        try await parseCards(fetch(categoryURL(region: "all", page: page)))
    }

    public func search(keyword: String, page _: Int) async throws -> [ComicSummary] {
        let keyword = formEncode(SearchRules.trim(keyword))
        return try await parseCards(fetch(absolute("/s/\(keyword)")))
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = rawComicID(comicId)
        let html = try await fetchDetailHTML(rawID)
        let mid = firstMatch(#"data-mid="(\d+)""#, in: html)
        let data = mid.isEmpty ? nil : try await mangaData(mid)
        let title = data?["title"] as? String ?? meta("og:title", in: html).replacingOccurrences(of: "-G社漫畫 - G社漫畫", with: "")
        let cover = data?["cover"] as? String ?? meta("og:image", in: html)
        let description = data?["desc"] as? String ?? meta("description", in: html)
        let status = data.map { string($0["status"]) == "1" ? "连载中" : "已完结" } ?? ""
        let summary = ComicSummary(sourceId: id, comicId: "gmh:\(rawID)", title: clean(title), coverUrl: cleanURL(cover))
        return ComicDetail(summary: summary, author: "", status: status, description: clean(description), latestChapter: "", chapters: [])
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let rawID = rawComicID(comicId)
        let mid = try await mangaID(for: rawID)
        let items = try chapterItems(in: await mangaData(mid))
        var all: [Chapter] = []
        var visible: [Chapter] = []
        for (index, item) in items.enumerated() {
            guard let attributes = item["attributes"] as? [String: Any] else { continue }
            let chapterID = string(item["id"])
            let title = clean(string(attributes["title"]))
            let slug = string(attributes["slug"])
            guard !chapterID.isEmpty, !title.isEmpty, !slug.isEmpty else { continue }
            let chapter = Chapter(
                chapterId: chapterID,
                title: title,
                url: absolute("/manga/\(rawID)/\(slug)"),
                chapterSlot: int(attributes["order"], default: index)
            )
            all.append(chapter)
            if int(attributes["isAd"]) == 0 { visible.append(chapter) }
        }
        return visible.isEmpty ? all : visible
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let rawID = rawComicID(url)
        let slug = rawChapterSlug(url)
        let mid = try await mangaID(for: rawID)
        let items = try chapterItems(in: await mangaData(mid))
        guard let item = items.first(where: { item in
            guard let attributes = item["attributes"] as? [String: Any] else { return false }
            return string(attributes["slug"]) == slug
        }), let attributes = item["attributes"] as? [String: Any] else {
            throw GmhSourceError.chapterNotFound(slug)
        }
        let chapterID = string(item["id"])
        guard !chapterID.isEmpty else { throw GmhSourceError.chapterNotFound(slug) }
        let root = try await jsonObject(fetch(String(format: Self.chapterAPI, mid, chapterID)))
        guard
            let data = root["data"] as? [String: Any],
            let info = data["info"] as? [String: Any]
        else { throw GmhSourceError.invalidResponse("G社漫画章节解析失败") }
        let title = clean(string(info["title"], default: string(attributes["title"])))
        guard let imagesObject = info["images"] as? [String: Any] else {
            throw GmhSourceError.invalidResponse("G社漫画图片解析失败")
        }
        let images = try decodeChapterImages(imagesObject)
        return ChapterPage(chapterId: url, title: title, nextPageUrl: "", imageUrls: images)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let html = try await fetch(categoryURL(region: "all", page: 1))
        var genres: [SourceFilterOption] = []
        var tags: [SourceFilterOption] = []
        var genreIndexes: [String: Int] = [:]
        var tagIndexes: [String: Int] = [:]
        for match in matches(Self.filterPattern, in: html) {
            let value = match[3]
            let label = clean(match[4]).replacingOccurrences(of: "^#", with: "", options: .regularExpression)
            guard !label.isEmpty, label != "全部" else { continue }
            if match[2].lowercased() == "genre" {
                upsert(SourceFilterOption(label: label, value: value), in: &genres, indexes: &genreIndexes)
            } else if match[2].lowercased() == "tag" {
                upsert(SourceFilterOption(label: label, value: value), in: &tags, indexes: &tagIndexes)
            }
        }
        guard !genres.isEmpty, !tags.isEmpty else { throw GmhSourceError.invalidResponse("G社漫画分类解析失败") }
        genres.insert(SourceFilterOption(label: "全部", value: "all"), at: 0)
        tags.insert(SourceFilterOption(label: "全部", value: "all"), at: 0)
        return [
            SourceFilterGroup(key: "genre", label: "漫画类型", options: genres),
            SourceFilterGroup(key: "tag", label: "热门标签", options: tags)
        ]
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let tag = filterValue(filters["tag"])
        let genre = filterValue(filters["genre"])
        var path = tag != "all" ? "/manga-tag/\(tag)" : genre != "all" ? "/manga-genre/\(genre)" : "/manga"
        if page > 1 { path += "/page/\(page)" }
        return try await parseCards(fetch(absolute(path)))
    }

    public nonisolated static func migrateImageURL(_ url: String) -> String {
        url
            .replacingOccurrences(of: #"^https://f40-1-4\.g-mh\.online(?=[/?#]|$)"#, with: "https://c-nd2-1.6wm.top", options: .regularExpression)
            .replacingOccurrences(of: #"^https://t40-1-4\.g-mh\.online(?=[/?#]|$)"#, with: "https://c-nd3-1.6wm.top", options: .regularExpression)
    }

    private func parseCards(_ html: String) -> [ComicSummary] {
        var comics: [ComicSummary] = []
        var seen = Set<String>()
        for match in matches(Self.cardPattern, in: html) {
            let rawID = rawComicID(htmlDecode(match[1]))
            guard !rawID.isEmpty, seen.insert(rawID).inserted else { continue }
            var title = clean(match[3])
            if title.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil {
                title = rawID.replacingOccurrences(of: "-", with: " ")
            }
            comics.append(ComicSummary(sourceId: id, comicId: "gmh:\(rawID)", title: title, coverUrl: cleanURL(match[2])))
        }
        return comics
    }

    private func categoryURL(region: String, page: Int) -> String {
        let genres = ["kr": "kr", "hots": "hots", "cn": "cn", "jp": "jp"]
        let genre = genres[region] ?? ""
        let pagePath = page <= 1 ? "" : "/page/\(page)"
        return absolute("/manga\(genre.isEmpty ? "" : "-genre/\(genre)")\(pagePath)")
    }

    private func fetch(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw GmhSourceError.invalidURL(urlString) }
        let response = try await transport.get(url, headers: ["User-Agent": Self.userAgent, "Referer": referer])
        guard (200..<300).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard let text = String(data: response.data, encoding: .utf8) else { throw GmhSourceError.invalidResponse("响应不是 UTF-8") }
        return text
    }

    private func fetchDetailHTML(_ rawID: String) async throws -> String {
        let html = try await fetch(absolute("/manga/\(rawID)"))
        let mid = firstMatch(#"data-mid="(\d+)""#, in: html)
        if !mid.isEmpty { midCache[rawID] = mid }
        return html
    }

    private func mangaID(for rawID: String) async throws -> String {
        if let cached = midCache[rawID], !cached.isEmpty { return cached }
        let html = try await fetchDetailHTML(rawID)
        let mid = firstMatch(#"data-mid="(\d+)""#, in: html)
        guard !mid.isEmpty else { throw GmhSourceError.missingMangaID(rawID) }
        midCache[rawID] = mid
        return mid
    }

    private func mangaData(_ mid: String) async throws -> [String: Any] {
        if let cached = mangaCache[mid] { return cached }
        let root = try await jsonObject(fetch(String(format: Self.mangaAPI, mid)))
        guard let data = root["data"] as? [String: Any] else { throw GmhSourceError.invalidResponse("G社漫画详情解析失败") }
        if let slug = data["slug"] as? String, !slug.isEmpty { midCache[slug] = mid }
        mangaCache[mid] = data
        return data
    }

    private func jsonObject(_ json: String) throws -> [String: Any] {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
            let dictionary = object as? [String: Any]
        else { throw GmhSourceError.invalidResponse("JSON 解析失败") }
        return dictionary
    }

    private func chapterItems(in data: [String: Any]) throws -> [[String: Any]] {
        guard let rawItems = data["chapters"] as? [Any] else {
            throw GmhSourceError.invalidResponse("G社漫画目录解析失败")
        }
        return try rawItems.map { item in
            guard let item = item as? [String: Any] else {
                throw GmhSourceError.invalidResponse("G社漫画目录解析失败")
            }
            return item
        }
    }

    private func decodeChapterImages(_ object: [String: Any]) throws -> [String] {
        let rawItems: [Any]
        if let plain = object["images"] as? [Any] {
            rawItems = plain
        } else if let encrypted = object["images"] as? String, !encrypted.isEmpty {
            let json = try decodeEncryptedImages(encrypted)
            guard let items = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else {
                throw GmhSourceError.imageDecryptionFailed
            }
            rawItems = items
        } else {
            throw GmhSourceError.invalidResponse("G社漫画图片解析失败")
        }

        let host = cleanURL(string(object["host"])).isEmpty ? hostForLine(int(object["line"], default: 1)) : cleanURL(string(object["host"]))
        var urls: [String] = []
        var seen = Set<String>()
        for item in rawItems {
            let value = item as? String ?? string((item as? [String: Any])?["url"])
            var url = cleanURL(value)
            guard !url.isEmpty else { continue }
            if !url.hasPrefix("http://"), !url.hasPrefix("https://") {
                url = host + (url.hasPrefix("/") ? url : "/\(url)")
            }
            url = Self.migrateImageURL(url)
            if seen.insert(url).inserted { urls.append(url) }
        }
        return urls
    }

    private func upsert(_ option: SourceFilterOption, in options: inout [SourceFilterOption], indexes: inout [String: Int]) {
        if let index = indexes[option.label] {
            options[index] = option
        } else {
            indexes[option.label] = options.count
            options.append(option)
        }
    }

    private func decodeEncryptedImages(_ encrypted: String) throws -> String {
        guard encrypted.hasPrefix("J7r"), encrypted.hasSuffix("nQ"), encrypted.count >= 9 else {
            throw GmhSourceError.imageDecryptionFailed
        }
        let body = String(encrypted.dropFirst(3).dropLast(2))
        let payloadLength = body.count - 5
        guard payloadLength >= 0 else { throw GmhSourceError.imageDecryptionFailed }
        let tailLength = payloadLength / 3
        let headLength = (payloadLength - tailLength) / 2
        let middleLength = payloadLength - tailLength - headLength
        let chars = Array(body)
        let markerOneStart = headLength
        let middleStart = markerOneStart + 2
        let markerTwoStart = middleStart + middleLength
        let tailStart = markerTwoStart + 3
        guard tailStart <= chars.count,
              String(chars[markerOneStart..<middleStart]) == "kD",
              String(chars[markerTwoStart..<tailStart]) == "W4s" else {
            throw GmhSourceError.imageDecryptionFailed
        }
        let mixed = Array(chars[tailStart...] + chars[..<markerOneStart] + chars[middleStart..<markerTwoStart])
        var restored: [Character] = []
        for start in stride(from: 0, to: mixed.count, by: 7) {
            let chunk = Array(mixed[start..<min(start + 7, mixed.count)])
            restored += (start / 7).isMultiple(of: 2) ? chunk : chunk.reversed()
        }
        var base64URL = ""
        for character in restored {
            guard let index = Self.sourceAlphabet.firstIndex(of: character) else { throw GmhSourceError.imageDecryptionFailed }
            let offset = Self.sourceAlphabet.distance(from: Self.sourceAlphabet.startIndex, to: index)
            let targetIndex = Self.targetAlphabet.index(Self.targetAlphabet.startIndex, offsetBy: offset)
            base64URL.append(Self.targetAlphabet[targetIndex])
        }
        var base64 = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let decoded = String(data: data, encoding: .utf8) else {
            throw GmhSourceError.imageDecryptionFailed
        }
        return decoded
    }

    private func hostForLine(_ line: Int) -> String {
        line == 2 ? "https://c-nd2-1.6wm.top" : "https://c-nd3-1.6wm.top"
    }

    private func rawComicID(_ value: String) -> String {
        var value = value
        if value.hasPrefix("gmh:") { value.removeFirst(4) }
        if let range = value.range(of: "/manga/") { value = String(value[range.upperBound...]) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rawChapterSlug(_ value: String) -> String {
        let withoutQuery = value.split(separator: "?", maxSplits: 1).first.map(String.init) ?? value
        return withoutQuery.split(separator: "/").last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func absolute(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        if value.hasPrefix("//") { return "https:\(value)" }
        return Self.baseURL + (value.hasPrefix("/") ? value : "/\(value)")
    }

    private func formEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._* "))
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?.replacingOccurrences(of: " ", with: "+") ?? ""
    }

    private func filterValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "all" }
        return value
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { result in
            (0..<result.numberOfRanges).map { index in
                let range = result.range(at: index)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
                return String(text[swiftRange])
            }
        }
    }

    private func firstMatch(_ pattern: String, in text: String) -> String {
        matches(pattern, in: text).first?[safe: 1] ?? ""
    }

    private func meta(_ key: String, in html: String) -> String {
        let pattern = #"<meta[^>]+(?:property|name)="([^"]+)"[^>]+content="([^"]*)""#
        return matches(pattern, in: html).first(where: { $0[safe: 1] == key })?[safe: 2].map(clean) ?? ""
    }

    private func clean(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return htmlDecode(withoutTags).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func htmlDecode(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private func cleanURL(_ value: String) -> String {
        let decoded = htmlDecode(value).replacingOccurrences(of: "\\/", with: "/")
        return decoded.firstIndex(of: "&").map { String(decoded[..<$0]) } ?? decoded
    }

    private func string(_ value: Any?, default defaultValue: String = "") -> String {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return defaultValue
        }
    }

    private func int(_ value: Any?, default defaultValue: Int = 0) -> Int {
        switch value {
        case let value as Int: return value
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value) ?? defaultValue
        default: return defaultValue
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
