import Foundation

public actor CopyMangaComicSource: ComicSource {
    public nonisolated let id = "copy4000"
    public nonisolated let name = "拷贝漫画"
    public nonisolated let referer: String
    private let base: String
    private let transport: any HTTPTransport
    private let apiTransport: any HTTPTransport
    private let apiOrigin: String
    private let apiFallbackOrigins: [String]
    private var workingOrigin: String?

    public init(transport: (any HTTPTransport)? = nil, baseURL: String = "https://www.copy4000.com",
                apiOrigin: String = "https://api.manga2026.xyz", apiFallbackOrigins: [String]? = nil) {
        self.transport = transport ?? URLSessionHTTPTransport(timeoutInterval:20)
        self.apiTransport = transport ?? URLSessionHTTPTransport(timeoutInterval:12)
        self.base = baseURL.replacingOccurrences(of:#"/+$"#,with:"",options:.regularExpression)
        self.referer = self.base + "/"
        self.apiOrigin = apiOrigin
        self.apiFallbackOrigins = apiFallbackOrigins ?? (apiOrigin == "https://api.manga2026.xyz" ? ["https://mapi.elfgjfghkk.club","https://mapi.fgjfghkkcenter.club"] : [])
    }
    public func latest(page: Int) async throws -> [ComicSummary] { try await category(filters:[:],page:page) }
    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let keyword = keyword.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        let path = "/api/kb/web/searchci/comics?offset=\(try offset(page,12))&platform=2&limit=12&q=\(encode(keyword))&q_type="
        let data = try results(await request(base+path,api:false))
        guard let list = data["list"].array else { throw error("搜索响应缺少列表") }
        return try summaries(list)
    }
    public func category(filters: [String:String], page: Int) async throws -> [ComicSummary] {
        func selected(_ key: String) -> String { let value = filters[key] ?? ""; return value == "all" ? "" : value }
        let ordering = selected("ordering").isEmpty ? "-datetime_updated" : selected("ordering")
        guard ["-datetime_updated","datetime_updated","-popular","popular"].contains(ordering) else { throw error("排序参数无效") }
        var path = "/comics?limit=50&offset=\(try offset(page,50))&ordering=\(ordering)"
        for key in ["theme","region","status"] {
            let value = selected(key)
            guard !value.isEmpty else { continue }
            guard key == "theme" || ["0","1","2"].contains(value) else { throw error("筛选参数无效："+key) }
            path += "&\(key)=\(encode(value))"
        }
        let html = try await request(base+path,api:false)
        let literal = attribute("list",opening("exemptComic-box",html))
        guard !literal.isEmpty, let list = try parseCopyMangaLiteral(literal).array else { throw error("分类响应缺少列表数据") }
        return try summaries(list)
    }
    public func filterGroups() async throws -> [SourceFilterGroup] {
        let html = try await request(base+"/filter",api:false)
        var themes: [(String,String)] = [], seen = Set<String>()
        for link in matches(#"<a\b([^>]*)>([\s\S]*?)</a>"#,html) {
            let href = attribute("href",link[1])
            guard let url = URLComponents(string:absolute(href)), url.path == "/comics" else { continue }
            let raw = href.components(separatedBy:"?").dropFirst().joined(separator:"?")
                .components(separatedBy:"&").first { $0.hasPrefix("theme=") }
            guard let raw else { continue }
            guard let value = String(raw.dropFirst(6)).replacingOccurrences(of:"+",with:" ").removingPercentEncoding else { throw error("分类链接编码错误") }
            let label = clean(link[2]).replacingOccurrences(of:#"\s*\([0-9]+\)\s*$"#,with:"",options:.regularExpression)
            if !value.isEmpty && !label.isEmpty && seen.insert(value).inserted { themes.append((label,value)) }
        }
        guard !themes.isEmpty else { throw error("分类字典不可用，请重试") }
        func group(_ key: String, _ label: String, _ pairs: [(String,String)]) -> SourceFilterGroup {
            .init(key:key,label:label,options:pairs.map { .init(label:$0.0,value:$0.1) })
        }
        return [group("ordering","排序",[("最近更新","-datetime_updated"),("较早更新","datetime_updated"),("热门优先","-popular"),("热度升序","popular")]),
                group("theme","题材",[("全部","all")]+themes),group("region","地区",[("全部","all"),("日漫","0"),("韩漫","1"),("美漫","2")]),
                group("status","状态",[("全部","all"),("连载中","0"),("已完结","1"),("短篇","2")])]
    }
    public func detail(comicId: String) async throws -> ComicDetail {
        let raw = try rawID(comicId)
        let html = try await request(base+"/comic/"+encode(raw),api:false)
        let info = content("comicParticulars-title-right",html)
        let title = clean(first(#"<h6\b[^>]*>([\s\S]*?)</h6>"#,info))
        guard !title.isEmpty else { throw error("详情不可用：缺少标题") }
        let image = first(#"(<img\b[^>]*>)"#,content("comicParticulars-left-img",html))
        let cover = attribute("data-src",image).isEmpty ? attribute("src",image) : attribute("data-src",image)
        var authors: [String] = [], themes: [String] = []
        for link in matches(#"<a\b([^>]*)>([\s\S]*?)</a>"#,info) {
            let href = attribute("href",link[1]), label = clean(link[2])
            if href.contains("/author/") { authors.append(label) }
            if href.contains("theme=") { themes.append(label.hasPrefix("#") ? String(label.dropFirst()) : label) }
        }
        let status = matches(#"<li\b[^>]*>([\s\S]*?)</li>"#,info).map { clean($0[1]) }
            .first { $0.hasPrefix("狀態：") || $0.hasPrefix("狀態:") }.map { String($0.dropFirst(3)).trimmingCharacters(in:.whitespacesAndNewlines) } ?? ""
        let latest = first(#"[-－](第[^-－]*?[話话卷回章])(?=[-－])"#,clean(first(#"<title\b[^>]*>([\s\S]*?)</title>"#,html)))
        return .init(summary:.init(sourceId:id,comicId:id+":"+raw,title:title,coverUrl:absolute(cover),subtitle:status,tags:themes),
                     author:authors.joined(separator:" / "),status:status,description:clean(content("intro",html)),latestChapter:latest,chapters:[])
    }
    public func chapters(comicId: String) async throws -> [Chapter] {
        let raw = try rawID(comicId)
        let detail = try await api("/api/v3/comic2/\(encode(raw))?platform=3")
        try checkComic(detail,raw)
        guard let groups = detail["groups"].object else { throw error("目录缺少分组") }
        var chapters: [Chapter] = [], seen = Set<String>()
        for (section, pair) in groups.enumerated() {
            guard pair.1.object != nil else { throw error("目录分组格式错误") }
            let group = pair.1["path_word"].string.isEmpty ? pair.0 : pair.1["path_word"].string
            var offset = 0, complete = false
            for _ in 0..<1000 {
                let data = try await api("/api/v3/comic/\(encode(raw))/group/\(encode(group))/chapters?limit=100&offset=\(offset)")
                guard let list = data["list"].array, let total = data["total"].integer, total >= 0,
                      data["offset"].integer == offset else { throw error("目录分页响应错误") }
                if list.isEmpty {
                    guard offset >= total else { throw error("目录未完整返回，请重试") }
                    complete = true; break
                }
                let before = chapters.count
                for (index,item) in list.enumerated() {
                    guard item["comic_path_word"].string == raw, item["group_path_word"].string == group else { throw error("目录与漫画或分组不匹配") }
                    let chapter = item["uuid"].string, title = item["name"].string
                    guard !chapter.isEmpty, !title.isEmpty else { throw error("目录项缺少标识或标题") }
                    if seen.insert(chapter).inserted {
                        chapters.append(.init(chapterId:chapter,title:title,url:base+"/comic/\(encode(raw))/chapter/\(encode(chapter))",sectionSlot:section,chapterSlot:offset+index))
                    }
                }
                guard chapters.count > before else { throw error("目录重复返回同一页，请重试") }
                offset += list.count
                if offset >= total { complete = true; break }
            }
            guard complete else { throw error("目录页数超出限制") }
        }
        guard !chapters.isEmpty else { throw error("返回空目录，请稍后重试或检查站点访问状态") }
        return chapters
    }
    public func chapter(url: String) async throws -> ChapterPage {
        guard let ids = matches(#"/comic/([^/?#]+)/chapter/([^/?#]+)(?:[?#].*)?$"#,url).first,
              let comic = ids[1].replacingOccurrences(of:"+",with:" ").removingPercentEncoding,
              let chapterID = ids[2].replacingOccurrences(of:"+",with:" ").removingPercentEncoding else { throw error("章节地址无效或编码错误") }
        let raw = try rawID(comic)
        guard !chapterID.isEmpty else { throw error("章节标识为空") }
        let data = try await api("/api/v3/comic/\(encode(raw))/chapter/\(encode(chapterID))?platform=3")
        try checkComic(data,raw)
        let chapter = data["chapter"]
        guard chapter["uuid"].string == chapterID, chapter["comic_path_word"].string == raw else { throw error("阅读数据与章节不匹配") }
        guard let contents = chapter["contents"].array, !contents.isEmpty, chapter["size"].integer == contents.count else { throw error("章节图片未完整返回，请重试") }
        let images = try contents.map { item -> String in
            let image = item["url"].string
            guard let url = URL(string:image), ["http","https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { throw error("图片地址无效") }
            return image
        }
        return .init(chapterId:base+"/comic/\(encode(raw))/chapter/\(encode(chapterID))",title:chapter["name"].string,nextPageUrl:"",imageUrls:images)
    }
    private func api(_ path: String) async throws -> CopyMangaValue {
        var origins = [try origin(apiOrigin,fallback:false)]
        for candidate in apiFallbackOrigins {
            if origins.count == 3 { break }
            let candidate = try origin(candidate,fallback:true)
            if !origins.contains(candidate) { origins.append(candidate) }
        }
        if let workingOrigin, let index = origins.firstIndex(of:workingOrigin) { origins.remove(at:index); origins.insert(workingOrigin,at:0) }
        var failures: [String] = []
        for origin in origins {
            try Task.checkCancellation()
            do {
                let data = try results(await request(origin+path,api:true))
                workingOrigin = origin
                return data
            } catch {
                try Task.checkCancellation()
                let failure = error as NSError
                let connectionCodes: [URLError.Code] = [.timedOut,.cannotFindHost,.cannotConnectToHost,.dnsLookupFailed,.networkConnectionLost,.notConnectedToInternet]
                guard failure.domain == NSURLErrorDomain,
                      connectionCodes.contains(where: { $0.rawValue == failure.code }) else { throw error }
                var cause = failure.userInfo[NSUnderlyingErrorKey] as? Error
                var visited = Set<ObjectIdentifier>()
                while let underlying = cause {
                    let nested = underlying as NSError
                    guard visited.insert(ObjectIdentifier(nested)).inserted,
                          !(underlying is CancellationError), nested.domain != NSOSStatusErrorDomain,
                          nested.domain != NSURLErrorDomain || connectionCodes.contains(where: { $0.rawValue == nested.code }) else { throw error }
                    cause = nested.userInfo[NSUnderlyingErrorKey] as? Error
                }
                failures.append("\(URL(string:origin)?.host ?? origin)：\(error.localizedDescription)")
            }
        }
        throw error("API 网络连接失败（已尝试 \(failures.joined(separator:" / "))），请切换网络后重试")
    }
    private func origin(_ value: String, fallback: Bool) throws -> String {
        guard let url = URLComponents(string:value), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty,
              (fallback ? scheme == "https" : ["http","https"].contains(scheme)), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { throw error("API 必须为有效域名地址，备用线路必须使用 HTTPS") }
        return scheme+"://"+host.lowercased()+(url.port.map { ":\($0)" } ?? "")
    }
    private func request(_ address: String, api: Bool) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string:address), ["http","https"].contains(url.scheme ?? ""), url.host?.isEmpty == false else { throw error("请求地址无效") }
        var headers = ["Referer":referer,"User-Agent":api ? "COPY/3.0.9" : "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                       "Accept":api ? "application/json" : "application/json, text/html;q=0.9, */*;q=0.8"]
        if api { headers.merge(["platform":"3","version":"3.0.9","region":"1","webp":"1"]) { _,value in value } }
        let response = try await (api ? apiTransport : transport).get(url,headers:headers)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else { throw error("请求失败：HTTP \(response.statusCode)") }
        // Shared transport buffers the body; this cap is checked after receipt.
        guard response.data.count <= 16*1024*1024 else { throw error("响应过大") }
        guard let text = String(data:response.data,encoding:.utf8) else { throw error("响应文字解码失败") }
        return text
    }
    private func results(_ text: String) throws -> CopyMangaValue {
        // Foundation enforces JSON syntax; the second parse preserves object member order.
        guard (try? JSONSerialization.jsonObject(with:Data(text.utf8))) is [String:Any] else { throw error("接口未返回有效 JSON") }
        let json = try parseCopyMangaLiteral(text)
        guard json["code"].integer == 200 else { throw error("接口返回错误：\(json["code"].integer ?? -1)") }
        let data = json["results"]
        guard data.object != nil else { throw error("接口未返回有效数据，请重试") }
        guard !data["is_lock"].isTrue else { throw error("当前内容不可访问") }
        return data
    }
    private func checkComic(_ data: CopyMangaValue, _ raw: String) throws {
        guard data["comic"]["path_word"].string == raw else { throw error("响应与漫画标识不匹配") }
    }
    private func summaries(_ list: [CopyMangaValue]) throws -> [ComicSummary] {
        var seen = Set<String>(), result: [ComicSummary] = []
        func names(_ value: CopyMangaValue) -> [String] { (value.array ?? []).map { $0["name"].string }.filter { !$0.isEmpty } }
        for item in list {
            let raw = item["path_word"].string, title = item["name"].string
            guard !raw.isEmpty, !title.isEmpty else { throw error("列表缺少漫画标识或标题") }
            if seen.insert(raw).inserted {
                result.append(.init(sourceId:id,comicId:id+":"+raw,title:title,coverUrl:absolute(item["cover"].string),subtitle:names(item["author"]).joined(separator:" / "),tags:names(item["theme"])))
            }
        }
        return result
    }
    private func rawID(_ value: String) throws -> String {
        let value = value.hasPrefix(id+":") ? String(value.dropFirst(id.count+1)) : value
        guard !value.isEmpty, !value.contains(where: { "/?#".contains($0) }) else { throw error("漫画标识无效") }
        return value
    }
    private func offset(_ page: Int, _ limit: Int) throws -> Int {
        guard page > 0 else { throw error("页码必须大于零") }
        let result = (page-1).multipliedReportingOverflow(by:limit)
        guard !result.overflow else { throw error("页码超出范围") }
        return result.partialValue
    }
    private func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters:CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*"))! }
    private func absolute(_ value: String) -> String {
        if value.isEmpty || value.hasPrefix("https://") || value.hasPrefix("http://") { return value }
        if value.hasPrefix("//") { return "https:"+value }
        return base+(value.hasPrefix("/") ? "" : "/")+value
    }
    private func error(_ message: String) -> Error { NSError(domain:"CopyManga",code:1,userInfo:[NSLocalizedDescriptionKey:"拷贝漫画"+message]) }
    private func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive) else { return [] }
        return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at:$0),in:text).map { String(text[$0]) } ?? "" }
        }
    }
    private func first(_ pattern: String, _ text: String) -> String { matches(pattern,text).first?.dropFirst().first(where: { !$0.isEmpty }) ?? "" }
    private func attribute(_ name: String, _ tag: String) -> String {
        HTML4EntityDecoder.decode(first("(?:^|\\s)"+NSRegularExpression.escapedPattern(for:name)+#"\s*=\s*(?:"([^"]*)"|'([^']*)')"#,tag))
    }
    private func opening(_ cls: String, _ html: String) -> String {
        matches(#"<[a-z][a-z0-9]*\b(?:[^"'<>]|"[^"]*"|'[^']*')*>"#,html).map { $0[0] }.first {
            attribute("class",$0).split(whereSeparator:\.isWhitespace).contains(Substring(cls))
        } ?? ""
    }
    private func content(_ cls: String, _ html: String) -> String {
        let tag = opening(cls,html)
        guard !tag.isEmpty, let start = html.range(of:tag)?.upperBound else { return "" }
        let name = first(#"^<([a-z0-9]+)"#,tag)
        guard let regex = try? NSRegularExpression(pattern:"</?"+name+#"\b[^>]*>"#,options:.caseInsensitive) else { return "" }
        var depth = 1
        for match in regex.matches(in:html,range:NSRange(start...,in:html)) {
            guard let range = Range(match.range,in:html) else { continue }
            let element = html[range]
            if element.hasPrefix("</") { depth -= 1 } else if !element.hasSuffix("/>") { depth += 1 }
            if depth == 0 { return String(html[start..<range.lowerBound]) }
        }
        return ""
    }
    private func clean(_ html: String) -> String {
        HTML4EntityDecoder.decode(html.replacingOccurrences(of:#"<[^>]*>"#,with:" ",options:.regularExpression))
            .replacingOccurrences(of:#"\s+"#,with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
