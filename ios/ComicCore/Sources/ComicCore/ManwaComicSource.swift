import Foundation
import CoreFoundation

public struct ManwaComicSource: ComicSource {
    public let id = "manwa"
    public let name: String
    public let referer: String
    private let base: String
    private let config: SourceConfigItem
    private let transport: any HTTPTransport
    private let tags = ["热血","玄幻","恋爱","冒险","古风","都市","穿越","奇幻","搞笑","少男","战斗","重生","逆袭","爆笑","少年","后宫","系统","BL","韩漫","完整版","19r","台版"]
    private let slugs = ["hotblooded","xuanhuan","romance","adventure","historical","urban","transmigration","fantasy","comedy","shounen","action","rebirth","counterattack","hilarious","youth","harem","system","bl","manhwa","fullversion","19plus","taiwanver"]

    public init(
        config: SourceConfigItem = SourceConfigDefaults.manwa(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25)
    ) {
        self.config = config
        self.name = config.name
        self.referer = config.referer.isEmpty ? "\(config.baseUrl)/" : config.referer
        self.base = config.baseUrl
        self.transport = transport
    }
    public func latest(page: Int) async throws -> [ComicSummary] { try await category(filters: [:], page: page) }
    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let keyword = SearchRules.trim(keyword)
        guard !keyword.isEmpty else { return [] }
        let path = config.route("search")
            .replacingOccurrences(of: "{page}", with: String(max(1, page)))
            .replacingOccurrences(of: "{keyword}", with: form(keyword))
        return try cards(await request(path))
    }
    public func filterGroups() async throws -> [SourceFilterGroup] {
        func group(_ key: String, _ label: String, _ pairs: [(String,String)]) -> SourceFilterGroup {
            .init(key: key, label: label, options: pairs.map { .init(label: $0.0, value: $0.1) })
        }
        return [
            group("level","范围",[("普通","all"),("全部","0"),("VIP無码","2")]),
            group("type","类型",[("全部","all"),("一般向","1"),("BL向","2"),("TL向","3"),("GL向","5"),("禁漫","4")]),
            group("tag","题材",[("全部","all")] + tags.map { ($0,$0) }),
            group("region","地区",[("全部","all"),("韩国","2"),("日漫","3"),("国漫","4"),("台漫","5"),("其他","6"),("未分类","1")]),
            group("state","状态",[("全部","all"),("连载中","0"),("已完结","1")]),
            group("day","星期",[("全部","all"),("周一","1"),("周二","2"),("周三","3"),("周四","4"),("周五","5"),("周六","6"),("周日","7")]),
            group("sort","排序",[("更新","all"),("新作","1"),("热门","3")])
        ]
    }
    public func category(filters: [String:String], page: Int) async throws -> [ComicSummary] {
        func value(_ key: String) -> String { let v = filters[key] ?? ""; return v == "all" ? "" : v }
        func number(_ key: String, _ fallback: Int = 0) -> Int { Int(value(key)) ?? fallback }
        let tag = value("tag")
        var suffix = ""
        if !tag.isEmpty {
            guard let index = tags.firstIndex(of: tag) else { throw error("题材不支持，请重新选择") }
            suffix = "/" + slugs[index]
        }
        let body: [String:Any] = [
            "category":"comic", "sort":number("sort"), "page":["page":max(1,page),"pageSize":36],
            "comic":["level":number("level",1),"typeId":number("type"),"areaId":number("region"),"status":number("state",-1),"day":number("day"),"tag":tag],
            "video":["year":0,"typeId":0,"typeId1":0,"area":"","lang":"","status":-1,"day":0,"level":0],
            "novel":["status":-1,"day":0,"sortId":0,"level":0]
        ]
        let route = config.route("category")
        return try cards(await request(route + suffix, referer: base + "/cate" + suffix, body: body, typeID: number("type")))
    }
    public func detail(comicId: String) async throws -> ComicDetail {
        let raw = try rawID(comicId)
        let path = config.route("detail").replacingOccurrences(of: "{comicId}", with: raw)
        let data = try await request(path)
        guard let html = String(data: data, encoding: .utf8) else { throw error("详情文字解码失败") }
        let title = clean(element("page-title", html))
        guard !title.isEmpty else { throw error("详情解析失败，站点可能暂不可用") }
        let image = first(#"(<img\b[^>]*class=["'][^"']*\bcomic-cover\b[^"']*["'][^>]*>)"#, html)
        let cover = ["data-src","data-original-cover","src"].map { attribute($0,image) }.first { !$0.isEmpty } ?? ""
        let author = clean(element("author-container",html)).replacingOccurrences(of: #"\s*，\s*"#, with: "，", options: .regularExpression)
        let labels = matches(#"<a\b[^>]*>([\s\S]*?)</a>"#, element("tagsContainer",html)).map { clean($0[1]) }.filter { !$0.isEmpty }
        let summary = ComicSummary(sourceId: id, comicId: id + ":" + raw, title: title, coverUrl: try absolute(cover), subtitle: author, tags: labels)
        return .init(summary: summary, author: author, status: clean(element("status",html)), description: clean(first(#"<p\b[^>]*class=["'][^"']*\bcomic-desc\b[^"']*["'][^>]*>([\s\S]*?)</p>"#,html)), latestChapter: clean(element("newch",html)), chapters: [])
    }
    public func chapters(comicId: String) async throws -> [Chapter] {
        let raw = try rawID(comicId), detail = try detailURL(raw)
        let path = config.route("chapters").replacingOccurrences(of: "{comicId}", with: raw)
        let payload = try json(await request(path, referer: detail))
        let rows = try array(payload,"list")
        var ordered: [(Int,Double,String,String)] = []
        for (index, value) in rows.enumerated() {
            guard let row = value as? [String:Any] else { throw error("目录条目格式错误") }
            let raw = string(row["id"])
            guard numeric(raw), let value = UInt64(raw), value > 0 else { throw error("目录条目格式错误") }
            let sort = Double(string(row["sortId"])) ?? 0
            guard sort.isFinite else { throw error("目录排序值无效") }
            ordered.append((index,sort,raw,clean(string(row["title"]))))
        }
        ordered.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
        var seen = Set<String>(), chapters: [Chapter] = []
        for row in ordered where seen.insert(row.2).inserted {
            chapters.append(.init(chapterId: row.2, title: row.3, url: detail + "/" + row.2, chapterSlot: chapters.count))
        }
        return chapters
    }
    public func chapter(url: String) async throws -> ChapterPage {
        let address = try absolute(url)
        guard let path = URL(string: address)?.path,
              let ids = matches(#"^/comic/(\d+)/(\d+)/?$"#,path).first else { throw error("章节链接格式错误") }
        let comic = ids[1], chapter = ids[2], referer = try detailURL(comic) + "/" + chapter
        let infoRoute = config.route("chapterInfo").replacingOccurrences(of: "{chapterId}", with: chapter)
        let info = try json(await request(infoRoute, referer: referer))
        guard let current = info["current"] as? [String:Any], string(current["comicId"]) == comic, string(current["id"]) == chapter else { throw error("章节信息不匹配") }
        var images: [String] = [], seen = Set<String>(), expectedTotal = -1, expectedPages = -1
        let imageSource = config.route("imageSource").isEmpty ? "https://tu.mwzu.cc" : config.route("imageSource")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        let encodedSource = imageSource.addingPercentEncoding(withAllowedCharacters: allowed) ?? imageSource
        let imageRoute = config.route("images").isEmpty
            ? "/api/comic/image/{chapterId}?page={page}&page_size=100&image_source={imageSource}"
            : config.route("images")
        for page in 1...500 {
            let pagePath = imageRoute
                .replacingOccurrences(of: "{chapterId}", with: chapter)
                .replacingOccurrences(of: "{page}", with: String(page))
                .replacingOccurrences(of: "{imageSource}", with: encodedSource)
            let payload = try json(await request(pagePath, referer: referer))
            let rows = try array(payload,"images")
            guard let pagination = payload["pagination"] as? [String:Any],
                  let total = Int(string(pagination["total"])), total > 0,
                  let pages = Int(string(pagination["total_pages"])), (1...500).contains(pages),
                  Int(string(pagination["current_page"])) == page else { throw error("章节暂无可读取图片或分页信息无效") }
            if page == 1 { expectedTotal = total; expectedPages = pages }
            guard expectedTotal == total, expectedPages == pages else { throw error("章节图片正在变化，请重试") }
            guard !rows.isEmpty else { throw error("图片分页为空") }
            for value in rows {
                guard let row = value as? [String:Any] else { throw error("图片条目格式错误") }
                let image = try absolute(string(row["url"]))
                guard !image.isEmpty, seen.insert(image).inserted else { throw error("图片缺失或分页重复") }
                images.append(image)
            }
            if page == pages {
                guard images.count == total else { throw error("章节图片不完整，请重试") }
                return .init(chapterId: referer, title: clean(string(current["title"])), nextPageUrl: "", imageUrls: images)
            }
        }
        throw error("图片分页过多")
    }

    private func request(_ path: String, referer: String? = nil, body: [String:Any]? = nil, typeID: Int = 0) async throws -> Data {
        try Task.checkCancellation()
        guard let url = URL(string: try absolute(path)) else { throw URLError(.badURL) }
        var headers = ["Referer":referer ?? self.referer,
                       "User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                       "Accept":"application/json,text/html;q=0.9,*/*;q=0.8", "Accept-Encoding":"gzip"]
        let response: HTTPResponse
        if let body {
            headers["Content-Type"] = "application/json; charset=UTF-8"
            headers["Origin"] = base
            headers["Cookie"] = "typeId=\(typeID)"
            response = try await transport.post(url, headers: headers, body: JSONSerialization.data(withJSONObject: body))
        } else { response = try await transport.get(url, headers: headers) }
        try Task.checkCancellation()
        if [401,403].contains(response.statusCode) { throw error("访问受限，可能需要登录或会员权限") }
        guard (200..<300).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard response.data.count <= 16 * 1024 * 1024 else { throw error("响应过大") }
        return response.data
    }
    private func json(_ data: Data) throws -> [String:Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw error("接口响应格式错误") }
        let code = Int(string(root["code"])) ?? -1
        if [401,403].contains(code) { throw error("访问受限，可能需要登录或会员权限") }
        guard code == 200 else { throw error("接口请求失败（\(code)）") }
        guard let data = root["data"] as? [String:Any] else { throw error("接口响应格式错误") }
        return data
    }
    private func cards(_ data: Data) throws -> [ComicSummary] {
        let rows = try array(json(data),"list")
        var seen = Set<String>(), result: [ComicSummary] = []
        for value in rows {
            guard let row = value as? [String:Any] else { throw error("列表条目格式错误") }
            var raw = first(#"(?:^|/)comic/(\d+)(?:[/?#]|$)"#,string(row["url"]))
            if raw.isEmpty { raw = string(row["id"]) }
            guard numeric(raw), seen.insert(raw).inserted else { continue }
            let title = clean(string(row["title"]))
            guard !title.isEmpty else { continue }
            let cover = string(row["cover"])
            let tags = clean(string(row["tags"])).components(separatedBy: CharacterSet(charactersIn: ",，/|")).map(SearchRules.trim).filter { !$0.isEmpty }
            result.append(.init(sourceId: id, comicId: id + ":" + raw, title: title, coverUrl: try absolute(cover.isEmpty ? string(row["pic"]) : cover), subtitle: clean(string(row["author"])), tags: tags))
        }
        guard rows.isEmpty || !result.isEmpty else { throw error("列表解析失败") }
        return result
    }
    private func array(_ json: [String:Any], _ key: String) throws -> [Any] {
        guard let values = json[key] as? [Any] else { throw error("接口缺少 " + key) }
        return values
    }
    private func absolute(_ text: String) throws -> String {
        let text = HTML4EntityDecoder.decode(SearchRules.trim(text))
        if text.isEmpty { return "" }
        guard let url = URL(string: text, relativeTo: URL(string: referer))?.absoluteURL,
              ["http","https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else { throw error("链接协议或地址无效") }
        return url.absoluteString
    }
    private func detailURL(_ comicId: String) throws -> String {
        let route = config.route("detail").isEmpty ? "/comic/{comicId}" : config.route("detail")
        return try absolute(route.replacingOccurrences(of: "{comicId}", with: comicId))
    }
    private func rawID(_ text: String) throws -> String {
        let raw = text.hasPrefix(id + ":") ? String(text.dropFirst(id.count + 1)) : text
        guard numeric(raw) else { throw error("漫画 ID 无效") }
        return raw
    }
    private func numeric(_ text: String) -> Bool { !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) } }
    private func string(_ value: Any?) -> String {
        if let text = value as? String { return text }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return "" }
        return number.stringValue
    }
    private func form(_ text: String) -> String {
        text.utf8.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45,46,95,42].contains(byte) { return String(UnicodeScalar(byte)) }
            return byte == 32 ? "+" : String(format: "%%%02X", byte)
        }.joined()
    }
    private func clean(_ text: String) -> String {
        SearchRules.trim(HTML4EntityDecoder.decode(text.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
    }
    private func element(_ id: String, _ html: String) -> String {
        first(#"<([a-z][a-z0-9]*)\b[^>]*\bid=["']"# + NSRegularExpression.escapedPattern(for: id) + #"["'][^>]*>([\s\S]*?)</\1>"#,html, group: 2)
    }
    private func attribute(_ name: String, _ tag: String) -> String {
        HTML4EntityDecoder.decode(first(#"(?:^|\s)"# + NSRegularExpression.escapedPattern(for: name) + #"=["']([^"']*)["']"#,tag))
    }
    private func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex...,in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0),in: text).map { String(text[$0]) } ?? "" }
        }
    }
    private func first(_ pattern: String, _ text: String, group: Int = 1) -> String { matches(pattern,text).first?[group] ?? "" }
    private func error(_ text: String) -> NSError { NSError(domain: "ManwaComicSource", code: 1, userInfo: [NSLocalizedDescriptionKey:"漫蛙" + text]) }
}
