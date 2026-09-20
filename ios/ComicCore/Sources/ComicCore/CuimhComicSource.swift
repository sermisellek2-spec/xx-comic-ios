import Foundation

public actor CuimhComicSource: ComicSource {
    public nonisolated let id = "cuimh"
    public nonisolated let name = "催漫画"
    public nonisolated let referer = "https://www.cuimh.com/"
    public nonisolated let supportsSearch = false

    private let baseURL = "https://www.cuimh.com"
    private let transport: any HTTPTransport
    private let nowMilliseconds: @Sendable () -> Int64
    private let sleepMilliseconds: @Sendable (Int64) async throws -> Void
    private let gate = CuimhRequestGate()
    private var cache: [String: CachedDocument] = [:]
    private var recency: [String] = []
    private var lastRequestStartedAt: Int64?
    private var forbiddenUntil: Int64 = 0

    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 30),
        nowMilliseconds: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
        sleepMilliseconds: @escaping @Sendable (Int64) async throws -> Void = { milliseconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
        }
    ) {
        self.transport = transport
        self.nowMilliseconds = nowMilliseconds
        self.sleepMilliseconds = sleepMilliseconds
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        try parseCards(await fetchCategory(buildCategoryPath(filters: [:], page: page)))
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        throw error("暂不支持搜索")
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        let groups = parseFilterGroups(try await fetchCategory("/category/"))
        guard !groups.isEmpty else { throw error("分类解析失败") }
        return groups
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        try parseCards(await fetchCategory(buildCategoryPath(filters: filters, page: page)))
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
        let chapters = parseChapters(try await fetch("/" + rawID))
        guard !chapters.isEmpty else { throw error("目录解析失败") }
        return chapters
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let absoluteURL = absolute(url)
        let html = try await fetch(absoluteURL)
        let encoded = first(#"\bparams\s*=\s*["']([^"']+)["']"#, html)
        guard let payload = Data(base64Encoded: decode(encoded), options: .ignoreUnknownCharacters), !encoded.isEmpty else {
            throw error("章节解析失败：阅读参数格式错误")
        }
        let images = try await Self.decryptPayload(payload)
        var title = clean(first(#"<title[^>]*>([\s\S]*?)</title>"#, html))
        if let range = title.range(of: "-下拉式") { title = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        return .init(chapterId: absoluteURL, title: title, nextPageUrl: "", imageUrls: images)
    }

    static func decryptPayload(_ payload: Data) async throws -> [String] {
        guard payload.count > 16 else { throw sourceError("章节解析失败：阅读参数过短") }
        let plain: Data
        do {
            plain = try SourceAES.decrypt(payload.dropFirst(16), key: Data("9S8$vJnU2ANeSRoF".utf8), iv: payload.prefix(16))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw sourceError("章节解析失败：无法解密阅读参数")
        }
        guard let json = try? JSONSerialization.jsonObject(with: plain) as? [String: Any] else {
            throw sourceError("章节解析失败：阅读参数 JSON 无效")
        }
        guard json["host"] as? String == "www.cuimh.com" else { throw sourceError("章节解析失败：阅读参数域名不匹配") }
        guard let values = json["images"] as? [Any], !values.isEmpty else { throw sourceError("章节解析失败：缺少正文图片") }
        var seen = Set<String>()
        let images = values.compactMap { item -> String? in
            guard let item = item as? String else { return nil }
            let value = item.replacingOccurrences(of: #"\/"#, with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
            let url = value.hasPrefix("/") ? "https://img1.baipiaoguai.org" + value : value
            return !url.isEmpty && seen.insert(url).inserted ? url : nil
        }
        guard !images.isEmpty else { throw sourceError("章节解析失败：缺少正文图片") }
        return images
    }

    private func fetchCategory(_ path: String) async throws -> String {
        var url = absolute(path)
        if url == baseURL + "/category" { url += "/" }
        return try await fetch(url, cacheable: true)
    }

    private func fetch(_ path: String, cacheable: Bool = false) async throws -> String {
        try Task.checkCancellation()
        try await gate.acquire()
        do {
            let result = try await fetchLocked(absolute(path), cacheable: cacheable)
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }

    private func fetchLocked(_ urlString: String, cacheable: Bool) async throws -> String {
        try Task.checkCancellation()
        var now = nowMilliseconds()
        guard now >= forbiddenUntil else { throw error("暂时访问受限，请稍后再试") }
        if cacheable, let cached = cache[urlString] {
            if now - cached.savedAt < 300_000 {
                touch(urlString)
                return cached.html
            }
            removeCached(urlString)
        }
        if let lastRequestStartedAt {
            let wait = 1_000 - (now - lastRequestStartedAt)
            if wait > 0 { try await sleepMilliseconds(wait) }
        }
        try Task.checkCancellation()
        now = nowMilliseconds()
        lastRequestStartedAt = now
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme ?? "") else { throw URLError(.badURL) }
        let response = try await transport.get(url, headers: [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Referer": referer,
            "Accept-Language": "zh-CN,zh;q=0.9"
        ])
        try Task.checkCancellation()
        if response.statusCode == 403 { forbiddenUntil = nowMilliseconds() + 1_800_000 }
        guard (200..<400).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard let html = String(data: response.data, encoding: .utf8) else { throw error("响应文字解码失败") }
        forbiddenUntil = 0
        if cacheable { store(html, for: urlString, at: nowMilliseconds()) }
        return html
    }

    private func store(_ html: String, for key: String, at time: Int64) {
        cache[key] = .init(html: html, savedAt: time)
        touch(key)
        while recency.count > 8, let oldest = recency.first { removeCached(oldest) }
    }

    private func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func removeCached(_ key: String) {
        cache.removeValue(forKey: key)
        recency.removeAll { $0 == key }
    }

    private func parseCards(_ html: String) throws -> [ComicSummary] {
        let lists = matches(#"<div[^>]*class=["'][^"']*\bcy_list_mh\b[^"']*["'][^>]*>([\s\S]*?)</div>"#, html)
        guard !lists.isEmpty else { throw error("列表解析失败") }
        var seen = Set<String>(), result: [ComicSummary] = []
        for list in lists.prefix(1) {
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
                result.append(.init(sourceId: id, comicId: id + ":" + rawID, title: title, coverUrl: absolute(imageURL(image)), subtitle: status, tags: linkTexts(first(#"<li[^>]*class=["'][^"']*\bbiaoqian\b[^"']*["'][^>]*>([\s\S]*?)</li>"#, card))))
            }
        }
        return result
    }

    private func parseFilterGroups(_ html: String) -> [SourceFilterGroup] {
        matches(#"<div[^>]*class=["'][^"']*\bcy_tag\b[^"']*["'][^>]*>([\s\S]*?)</div>"#, html).compactMap { match in
            let block = match[1], original = clean(first(#"<span[^>]*>([\s\S]*?)</span>"#, block))
            guard let key = ["分类": "classification", "标签": "subject", "类型": "type", "品质": "quality", "地区": "region", "版权": "copyright", "进度": "state"][original] else { return nil }
            var seen = Set(["全部"]), options = [SourceFilterOption(label: "全部", value: "all")]
            for link in matches(#"<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#, block) {
                let label = clean(link[2]), value = categorySegment(decode(link[1]))
                if !label.isEmpty, label != "全部", value != "all", seen.insert(label).inserted { options.append(.init(label: label, value: value)) }
            }
            return .init(key: key, label: original == "标签" ? "题材" : original == "进度" ? "状态" : original, options: options)
        }
    }

    private func buildCategoryPath(filters: [String: String], page: Int) -> String {
        let pairs = [("classification", "/list/"), ("subject", "/tags/"), ("type", "/theme/"), ("quality", "/quality/"), ("region", "/city/"), ("copyright", "/copyright/"), ("state", "/finish/")]
        var path = "/category"
        for (key, prefix) in pairs {
            if let selected = filters[key], selected.hasPrefix(prefix) { path += selected }
        }
        if page > 1 { path += "/page/\(page)" }
        return path
    }

    private func parseDetail(rawID: String, html: String, includeChapters: Bool) throws -> ComicDetail {
        guard html.range(of: #"class=["'][^"']*\bcy_title\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { throw error("详情解析失败：缺少站点结构") }
        let title = clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#, html))
        guard !title.isEmpty else { throw error("详情解析失败：缺少标题") }
        let coverBlock = first(#"<div[^>]*class=["'][^"']*\bcy_info_cover\b[^"']*["'][^>]*>([\s\S]*?)</div>"#, html)
        let author = labelled(html, className: "cy_author", label: "作者")
        let status = labelled(html, className: "cy_serialize", label: "状态")
        let latest = labelled(html, className: "cy_newpic", label: "最新话")
        let tags = linkTexts(first(#"<span[^>]*class=["'][^"']*\bcy_type\b[^"']*["'][^>]*>([\s\S]*?)</span>"#, html))
        return .init(summary: .init(sourceId: id, comicId: id + ":" + rawID, title: title, coverUrl: absolute(imageURL(raw(#"<img[^>]*>"#, coverBlock))), subtitle: author, tags: tags), author: author, status: status, description: clean(first(#"<p[^>]*id=["']comic-description["'][^>]*>([\s\S]*?)</p>"#, html)), latestChapter: latest, chapters: includeChapters ? parseChapters(html) : [])
    }

    private func parseChapters(_ html: String) -> [Chapter] {
        var seen = Set<String>(), result: [Chapter] = []
        for match in matches(#"<li[^>]*class=["'][^"']*\bchapter__item\b[^"']*["'][^>]*>[\s\S]*?<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>[\s\S]*?</li>"#, html) {
            let href = decode(match[1])
            guard href.range(of: #"/?\d+-\d+\.html(?:[?#].*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil else { continue }
            let url = absolute(href), title = clean(match[2])
            guard !title.isEmpty, seen.insert(url).inserted else { continue }
            result.append(.init(chapterId: chapterID(url), title: title, url: url, chapterSlot: result.count))
        }
        return result
    }

    private func labelled(_ html: String, className: String, label: String) -> String {
        clean(first("<span[^>]*class=[\"'][^\"']*\\b" + NSRegularExpression.escapedPattern(for: className) + #"\b[^"']*["'][^>]*>([\s\S]*?)</span>"#, html)).replacingOccurrences(of: "^" + NSRegularExpression.escapedPattern(for: label) + #"[：:]\s*"#, with: "", options: .regularExpression)
    }

    private func categorySegment(_ href: String) -> String {
        guard let range = href.range(of: "/category") else { return "all" }
        var path = String(href[range.upperBound...]).components(separatedBy: "?")[0]
        while path.hasSuffix("/") { path.removeLast() }
        return path.isEmpty ? "all" : path
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
        let value = input.components(separatedBy: "?")[0]
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
    private static func sourceError(_ message: String) -> NSError { NSError(domain: "CuimhComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey: "催漫画" + message]) }
    private struct CachedDocument { let html: String; let savedAt: Int64 }
}

private actor CuimhRequestGate {
    private struct Waiter { let id: UUID; let continuation: CheckedContinuation<Void, Error> }
    private var isLocked = false
    private var waiters: [Waiter] = []

    func acquire() async throws {
        try Task.checkCancellation()
        guard isLocked else { isLocked = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append(.init(id: id, continuation: continuation)) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func release() {
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume()
            return
        }
        isLocked = false
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
