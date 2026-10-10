import Foundation

/// Public Zaimanhua endpoints (1:1 with Android ZaimanhuaComicSource.java). Restricted chapters remain restricted.
public final class ZaimanhuaComicSource: ComicSource, @unchecked Sendable {
    public let id: String
    public let name: String
    public let domain: String
    public let referer: String
    private let baseURL: String
    private let config: SourceConfigItem
    private let transport: any HTTPTransport

    private let cacheLock = NSLock()
    private var directoryOrder: [String] = []
    private var directoryCache: [String: [String: Any]] = [:]
    private var imageOrder: [String] = []
    private var imageEntries: [String: ImageEntry] = [:]

    private static let imageTTLMs: Int64 = 120_000
    private static let ua = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

    private struct ImageEntry {
        let images: [String]
        let createdMs: Int64
    }

    public init(
        config: SourceConfigItem = SourceConfigDefaults.zaimanhua(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25)
    ) {
        self.config = config
        self.id = config.id.isEmpty ? "zaimanhua" : config.id
        self.name = config.name.isEmpty ? "再漫画" : config.name
        self.domain = config.domain.isEmpty ? "manhua.zaimanhua.com" : config.domain
        let rawBase = config.baseUrl.isEmpty ? "https://v4api.zaimanhua.com" : config.baseUrl
        let cleanBase = rawBase.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        self.baseURL = cleanBase
        self.referer = config.referer.isEmpty ? "https://manhua.zaimanhua.com/" : config.referer
        self.transport = transport
    }

    public var categories: [String] {
        ["冒险", "爱情", "校园", "热血", "治愈", "日常"]
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let route = config.route("latest").isEmpty ? "/app/v1/comic/update/list/0/{page}" : config.route("latest")
        let path = route.replacingOccurrences(of: "{page}", with: Self.page(page))
        return try Self.parseList(try await get(absolute(path)), sourceId: id)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let trimmed = SearchRules.trim(keyword)
        guard !trimmed.isEmpty else { return [] }
        let route = config.route("search").isEmpty ? "/app/v1/search/index?source=0&size=20&page={page}&keyword={keyword}" : config.route("search")
        let path = route
            .replacingOccurrences(of: "{keyword}", with: Self.formEncode(trimmed))
            .replacingOccurrences(of: "{page}", with: Self.page(page))
        return try Self.parseList(try await get(absolute(path)), sourceId: id)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        Self.staticFilterGroups()
    }

    private static func staticFilterGroups() -> [SourceFilterGroup] {
        [
            group("zone", "地区", "全部", "0", "日本", "2304", "韩国", "2305", "欧美", "2306", "港台", "2307", "内地", "2308"),
            group("theme", "题材", "全部", "0", "冒险", "4", "欢乐向", "5", "格斗", "6", "科幻", "7", "爱情", "8", "侦探", "9", "竞技", "10", "魔法", "11", "校园", "13", "悬疑", "3245", "热血", "3248", "历史", "3250", "治愈", "3254", "美食", "3327", "奇幻", "5848", "搞笑", "7568", "日常", "30788"),
            group("status", "状态", "全部", "0", "连载中", "2309", "已完结", "2310", "短篇", "29205"),
            group("cate", "读者", "全部", "0", "少年", "3262", "少女", "3263", "青年", "3264", "女青", "13626"),
            group("sortType", "排序", "更新", "1", "人气", "2")
        ]
    }

    private static func group(_ key: String, _ title: String, _ pairs: String...) -> SourceFilterGroup {
        var list: [SourceFilterOption] = []
        var i = 0
        while i + 1 < pairs.count {
            list.append(.init(label: pairs[i], value: pairs[i + 1]))
            i += 2
        }
        return .init(key: key, label: title, options: list)
    }

    public func category(region: String, state: String, page: Int) async throws -> [ComicSummary] {
        try await category(filters: ["zone": region, "status": state], page: page)
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let route = config.route("category").isEmpty ? "/app/v1/comic/filter/list?size=20&page={page}" : config.route("category")
        var path = route.replacingOccurrences(of: "{page}", with: Self.page(page))
        for grp in Self.staticFilterGroups() {
            let value = filters[grp.key]
            var selected = grp.options.first?.value ?? "0"
            if let value, grp.options.contains(where: { $0.value == value }) {
                selected = value
            }
            path += "&\(grp.key)=\(selected)"
        }
        return try Self.parseList(try await get(absolute(path)), sourceId: id)
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let raw = try Self.validateId(comicId, sourceId: id)
        let data = try await detailData(id: raw)
        guard raw == Self.stringValue(data["id"]) else {
            throw Self.sourceError("再漫画详情 ID 不匹配")
        }
        putDirectoryCache(id: raw, data: data)
        return .init(
            summary: Self.summary(data, sourceId: id),
            author: Self.labels(data["authors"] as? [Any]),
            status: Self.labels(data["status"] as? [Any]),
            description: Self.stringValue(data["description"]),
            latestChapter: Self.stringValue(data["last_update_chapter_name"]),
            chapters: []
        )
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let raw = try Self.validateId(comicId, sourceId: id)
        let data: [String: Any]
        if let cached = removeDirectoryCache(id: raw) {
            data = cached
        } else {
            data = try await detailData(id: raw)
        }
        var result: [Chapter] = []
        var seen = Set<String>()
        let chapterRoute = config.route("chapter").isEmpty ? "/app/v1/comic/chapter/{comicId}/{chapterId}?_v=2.2.5" : config.route("chapter")
        if let sections = data["chapters"] as? [Any] {
            for (sectionIndex, rawBlock) in sections.enumerated() {
                guard let block = rawBlock as? [String: Any],
                      let items = block["data"] as? [Any] else { continue }
                var ordered: [Chapter] = []
                for (i, rawItem) in items.enumerated() {
                    guard let item = rawItem as? [String: Any] else { continue }
                    let chapter = Self.stringValue(item["chapter_id"])
                    guard chapter.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
                          seen.insert(chapter).inserted else { continue }
                    if let rawCanRead = item["canRead"], !(rawCanRead is NSNull) {
                        if !Self.boolValue(rawCanRead) { continue }
                    } else if Self.boolValue(item["is_fee"]) || Self.intValue(item["is_fee"], default: 0) > 0 {
                        continue
                    }
                    let title = Self.firstNonEmpty(
                        Self.stringValue(item["chapter_name"]),
                        Self.stringValue(item["chapter_title"]),
                        "章节 " + chapter
                    )
                    let url = absolute(chapterRoute
                        .replacingOccurrences(of: "{comicId}", with: raw)
                        .replacingOccurrences(of: "{chapterId}", with: chapter))
                    let slot = Self.intValue(item["chapter_order"], default: items.count - i)
                    ordered.append(.init(chapterId: chapter, title: title, url: url, sectionSlot: sectionIndex, chapterSlot: slot))
                }
                ordered.sort { $0.chapterSlot < $1.chapterSlot }
                result.append(contentsOf: ordered)
            }
        }
        guard !result.isEmpty else {
            throw Self.sourceError("再漫画暂无公开可读章节，部分内容需要站点账户权限")
        }
        return result
    }

    public func chapter(url: String) async throws -> ChapterPage {
        guard let match = Self.matches(url, #"/comic/chapter/(\d+)/(\d+)(?:[?#].*)?$"#).first else {
            throw Self.sourceError("再漫画章节地址无效")
        }
        let comic = match[1], chapter = match[2]
        let chapterRoute = config.route("chapter").isEmpty ? "/app/v1/comic/chapter/{comicId}/{chapterId}?_v=2.2.5" : config.route("chapter")
        let target = absolute(chapterRoute
            .replacingOccurrences(of: "{comicId}", with: comic)
            .replacingOccurrences(of: "{chapterId}", with: chapter))
        let data = try Self.objectData(try await get(target))
        guard comic == Self.stringValue(data["comic_id"]),
              chapter == Self.stringValue(data["chapter_id"]) else {
            throw Self.sourceError("再漫画章节数据不匹配")
        }
        if let rawCanRead = data["canRead"], !(rawCanRead is NSNull), !Self.boolValue(rawCanRead) {
            throw Self.sourceError("此章节需要站点账户权限，暂不支持阅读")
        }
        var images: [String] = []
        if let pages = data["page_url"] as? [Any] {
            for (i, rawPage) in pages.enumerated() {
                let pageUrl = Self.stringValue(rawPage)
                guard pageUrl.hasPrefix("https://") || pageUrl.hasPrefix("http://") else {
                    throw Self.sourceError("再漫画图片地址无效")
                }
                let base = pageUrl.components(separatedBy: "#")[0]
                images.append("\(base)#xx-zai=\(comic)/\(chapter)/\(i)")
            }
        }
        guard !images.isEmpty else {
            throw Self.sourceError("再漫画章节未返回图片")
        }
        putImageEntry(key: "\(comic)/\(chapter)", entry: ImageEntry(images: images, createdMs: Self.nowMs()))
        return .init(chapterId: chapter, title: Self.stringValue(data["title"]), nextPageUrl: "", imageUrls: images)
    }

    /// Called on image workers, including when chapter metadata was restored from disk.
    public func resolveImageUrl(_ imageUrl: String, force: Bool) async throws -> String {
        guard let match = Self.matches(imageUrl, #"#xx-zai=(\d+)/(\d+)/(\d+)$"#).first else {
            return imageUrl
        }
        let comic = match[1], chapterId = match[2]
        let key = "\(comic)/\(chapterId)"
        guard let index = Int(match[3]) else {
            throw Self.sourceError("再漫画页码无效")
        }
        var entry = getImageEntry(key: key)
        if force || entry == nil || (Self.nowMs() - (entry?.createdMs ?? 0) > Self.imageTTLMs) {
            let chapterRoute = config.route("chapter").isEmpty ? "/app/v1/comic/chapter/{comicId}/{chapterId}?_v=2.2.5" : config.route("chapter")
            let chapterUrl = absolute(chapterRoute
                .replacingOccurrences(of: "{comicId}", with: comic)
                .replacingOccurrences(of: "{chapterId}", with: chapterId))
            _ = try await chapter(url: chapterUrl)
            entry = getImageEntry(key: key)
        }
        guard let entry, index >= 0, index < entry.images.count else {
            throw Self.sourceError("再漫画图片页码已变化，请重新打开章节")
        }
        return entry.images[index].components(separatedBy: "#")[0]
    }

    public static func imageCacheIdentity(_ imageUrl: String) -> String {
        guard let match = matches(imageUrl, #"#xx-zai=(\d+)/(\d+)/(\d+)$"#).first else {
            return imageUrl
        }
        return "zaimanhua:\(match[1]):\(match[2]):\(match[3])"
    }

    public func healthCheck() async -> Bool {
        do {
            return !(try await latest(page: 1)).isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Internal Parsing Helpers

    private func detailData(id: String) async throws -> [String: Any] {
        let route = config.route("detail").isEmpty ? "/app/v1/comic/detail/{comicId}?_v=2.2.5" : config.route("detail")
        let path = route.replacingOccurrences(of: "{comicId}", with: id)
        return try Self.objectData(try await get(absolute(path)))
    }

    private static func validateId(_ comicId: String, sourceId: String) throws -> String {
        let value = rawID(comicId, sourceId: sourceId)
        guard value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            throw sourceError("再漫画 ID 无效")
        }
        return value
    }

    static func parseList(_ text: String, sourceId: String = "zaimanhua") throws -> [ComicSummary] {
        let r = try root(text)
        var list = r["data"] as? [Any]
        if list == nil, let data = r["data"] as? [String: Any] {
            list = (data["list"] as? [Any]) ?? (data["comicList"] as? [Any])
        }
        guard let list else {
            throw sourceError("再漫画列表数据缺失")
        }
        var result: [ComicSummary] = []
        var seen = Set<String>()
        for rawItem in list {
            guard let item = rawItem as? [String: Any] else { continue }
            let s = summary(item, sourceId: sourceId)
            if !s.title.isEmpty && !s.comicId.hasSuffix(":0") && seen.insert(s.comicId).inserted {
                result.append(s)
            }
        }
        return result
    }

    private static func summary(_ item: [String: Any], sourceId: String = "zaimanhua") -> ComicSummary {
        let idNum = int64Value(item["id"], default: 0)
        let idStr: String
        if idNum > 0 {
            idStr = stringValue(item["id"])
        } else {
            let cid = stringValue(item["comic_id"])
            idStr = cid.isEmpty ? "0" : cid
        }
        let tagsStr: String
        if let arr = item["types"] as? [Any] {
            tagsStr = labels(arr)
        } else {
            tagsStr = stringValue(item["types"])
        }
        let authors: String
        if let arr = item["authors"] as? [Any] {
            authors = labels(arr)
        } else {
            authors = stringValue(item["authors"])
        }
        let tags = tagsStr.isEmpty ? [] : tagsStr.components(separatedBy: CharacterSet(charactersIn: ",，/"))
        let latest = firstNonEmpty(stringValue(item["last_update_chapter_name"]), stringValue(item["last_name"]))
        return .init(
            sourceId: sourceId,
            comicId: sourceId + ":" + idStr,
            title: firstNonEmpty(stringValue(item["title"]), stringValue(item["name"])),
            coverUrl: stringValue(item["cover"]),
            subtitle: authors,
            tags: tags,
            latestChapter: latest
        )
    }

    private static func labels(_ list: [Any]?) -> String {
        guard let list else { return "" }
        var values: [String] = []
        for raw in list {
            if let dict = raw as? [String: Any] {
                values.append(stringValue(dict["tag_name"]))
            }
        }
        return values.joined(separator: "/")
    }

    private static func root(_ text: String) throws -> [String: Any] {
        guard let obj = parseJSONObject(text) else {
            throw sourceError("再漫画返回数据格式错误")
        }
        let errno = intValue(obj["errno"], default: 0)
        let errmsg = stringValue(obj["errmsg"])
        if errno != 0 || !errmsg.isEmpty {
            throw sourceError("再漫画请求失败：" + (errmsg.isEmpty ? "站点暂不可用" : errmsg))
        }
        return obj
    }

    private static func objectData(_ text: String) throws -> [String: Any] {
        let r = try root(text)
        var data = r["data"] as? [String: Any]
        if let nested = data?["data"] as? [String: Any] {
            data = nested
        }
        guard let data else {
            throw sourceError("再漫画未返回详情数据")
        }
        return data
    }

    private static func parseJSONObject(_ text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        let normalized = normalizeRelaxedJSON(text)
        if let data = normalized.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return nil
    }

    /// Supports org.json-style relaxed JSON used in unit tests (unquoted keys and single-quoted strings).
    private static func normalizeRelaxedJSON(_ input: String) -> String {
        let chars = Array(input)
        var out = ""
        out.reserveCapacity(chars.count + 32)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                out.append(c)
                i += 1
                while i < chars.count {
                    let sc = chars[i]
                    out.append(sc)
                    i += 1
                    if sc == "\\" && i < chars.count {
                        out.append(chars[i])
                        i += 1
                    } else if sc == "\"" {
                        break
                    }
                }
            } else if c == "'" {
                out.append("\"")
                i += 1
                while i < chars.count {
                    let sc = chars[i]
                    i += 1
                    if sc == "\\" && i < chars.count {
                        let next = chars[i]
                        i += 1
                        if next == "'" {
                            out.append("'")
                        } else {
                            out.append("\\")
                            out.append(next)
                        }
                    } else if sc == "\"" {
                        out.append("\\\"")
                    } else if sc == "'" {
                        break
                    } else {
                        out.append(sc)
                    }
                }
                out.append("\"")
            } else if c.isLetter || c == "_" {
                var ident = String(c)
                i += 1
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    ident.append(chars[i])
                    i += 1
                }
                var lookahead = i
                while lookahead < chars.count && chars[lookahead].isWhitespace {
                    lookahead += 1
                }
                if lookahead < chars.count && chars[lookahead] == ":" {
                    out.append("\"\(ident)\"")
                } else {
                    out.append(ident)
                }
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    // MARK: - Cache Helpers

    private func putDirectoryCache(id: String, data: [String: Any]) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let idx = directoryOrder.firstIndex(of: id) {
            directoryOrder.remove(at: idx)
        }
        directoryOrder.append(id)
        directoryCache[id] = data
        while directoryOrder.count > 4 {
            let evicted = directoryOrder.removeFirst()
            directoryCache.removeValue(forKey: evicted)
        }
    }

    private func removeDirectoryCache(id: String) -> [String: Any]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let idx = directoryOrder.firstIndex(of: id) {
            directoryOrder.remove(at: idx)
        }
        return directoryCache.removeValue(forKey: id)
    }

    private func putImageEntry(key: String, entry: ImageEntry) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let idx = imageOrder.firstIndex(of: key) {
            imageOrder.remove(at: idx)
        }
        imageOrder.append(key)
        imageEntries[key] = entry
        while imageOrder.count > 12 {
            let evicted = imageOrder.removeFirst()
            imageEntries.removeValue(forKey: evicted)
        }
    }

    private func getImageEntry(key: String) -> ImageEntry? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return imageEntries[key]
    }

    // MARK: - HTTP & Value Helpers

    private func get(_ url: String, referer: String? = nil) async throws -> String {
        try await readRequest(url: url, method: "GET", body: nil, referer: referer ?? self.referer, json: false)
    }

    private func readRequest(url: String, method: String, body: String?, referer: String, json: Bool) async throws -> String {
        do {
            return try await performRequest(url: url, method: method, body: body, referer: referer, json: json)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let urlError = error as? URLError,
               [.networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(urlError.code) {
                return try await performRequest(url: url, method: method, body: body, referer: referer, json: json)
            }
            throw error
        }
    }

    private func performRequest(url: String, method: String, body: String?, referer: String, json: Bool) async throws -> String {
        try Task.checkCancellation()
        guard let targetURL = URL(string: url), ["http", "https"].contains(targetURL.scheme?.lowercased() ?? "") else {
            throw URLError(.badURL)
        }
        var headers: [String: String] = [
            "User-Agent": Self.ua,
            "Accept": json
                ? "application/json, text/plain, */*"
                : "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.6",
            "Accept-Encoding": "gzip",
            "Connection": "close"
        ]
        if !referer.isEmpty { headers["Referer"] = referer }
        let response = try await transport.get(targetURL, headers: headers)
        try Task.checkCancellation()
        guard (200..<400).contains(response.statusCode) else {
            throw Self.sourceError("\(name) 请求失败（HTTP \(response.statusCode)）")
        }
        return String(data: response.data, encoding: .utf8) ?? String(decoding: response.data, as: UTF8.self)
    }

    private func absolute(_ value: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "&amp;", with: "&")
        guard !raw.isEmpty else { return "" }
        if raw.hasPrefix("//") { return "https:" + raw }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        if let base = URL(string: baseURL + "/"), let resolved = URL(string: raw, relativeTo: base)?.absoluteURL {
            return resolved.absoluteString
        }
        return baseURL + (raw.hasPrefix("/") ? raw : "/" + raw)
    }

    private static func page(_ page: Int) -> String {
        String(max(1, page))
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func rawID(_ value: String, sourceId: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = sourceId + ":"
        return trimmed.hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
    }

    private static func formEncode(_ value: String) -> String {
        value.utf8.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 46, 95, 42].contains(byte) {
                return String(UnicodeScalar(byte))
            }
            return byte == 32 ? "+" : String(format: "%%%02X", byte)
        }.joined()
    }

    private static func boolValue(_ value: Any?, default fallback: Bool = false) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber {
            // In org.json, optBoolean only treats Boolean.TRUE or "true" as true, unless used on a boolean field
            return n.boolValue
        }
        if let s = value as? String {
            if s.caseInsensitiveCompare("true") == .orderedSame { return true }
            if s.caseInsensitiveCompare("false") == .orderedSame { return false }
        }
        return fallback
    }

    private static func intValue(_ value: Any?, default fallback: Int) -> Int {
        if let v = value as? Int { return v }
        if let v = value as? NSNumber { return v.intValue }
        if let v = value as? String, let parsed = Int(v) { return parsed }
        return fallback
    }

    private static func int64Value(_ value: Any?, default fallback: Int64) -> Int64 {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? NSNumber { return v.int64Value }
        if let v = value as? String, let parsed = Int64(v) { return parsed }
        return fallback
    }

    private static func stringValue(_ value: Any?) -> String {
        if let v = value as? String { return v }
        if let v = value as? NSNumber { return v.stringValue }
        return ""
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        for v in values {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private static func matches(_ text: String, _ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { idx in
                Range(match.range(at: idx), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func sourceError(_ message: String) -> NSError {
        NSError(domain: "ZaimanhuaComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
