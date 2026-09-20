import Foundation

public struct ManhuaguiComicSource: ComicSource {
    public let id = "manhuagui"
    public let name = "漫画柜"
    public let referer: String
    private let base: String
    private let transport: any HTTPTransport
    private let readerTransport: any HTTPTransport
    public init(transport: (any HTTPTransport)? = nil, baseURL: String = "https://www.manhuagui.com") {
        base = baseURL.replacingOccurrences(of:#"/+$"#,with:"",options:.regularExpression)
        referer = base + "/"
        self.transport = transport ?? URLSessionHTTPTransport(timeoutInterval:15)
        readerTransport = transport ?? URLSessionHTTPTransport(timeoutInterval:30)
    }
    public func latest(page: Int) async throws -> [ComicSummary] { try await category(filters:[:],page:page) }
    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        if page > 1 { return [] }
        return try cards(await fetch("/s/"+guiEncode(SearchRules.trim(keyword))+".html"))
    }
    public func category(filters: [String:String], page: Int) async throws -> [ComicSummary] {
        let segment = ["region","genre","audience","year","letter","state"].compactMap { key -> String? in
            let value = filters[key] ?? "all"; return value.isEmpty || value == "all" ? nil : value
        }.joined(separator:"-")
        return try cards(await fetch("/list"+(segment.isEmpty ? "" : "/"+segment)+(page > 1 ? "/index_p\(page).html" : "")))
    }
    public func filterGroups() async throws -> [SourceFilterGroup] {
        let html = try await fetch("/list")
        var result: [SourceFilterGroup] = []
        for (kind,key,label) in [("area","region","地区"),("genre","genre","剧情"),("age","audience","受众"),("year","year","年份"),("letter","letter","字母"),("status","state","状态")] {
            let block = guiFirst("<div[^>]*class=[\"'][^\"']*\\bfilter\\b[^\"']*\\b"+kind+"\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",html)
            var options: [SourceFilterOption] = []
            for link in guiMatches(#"<a\b[^>]*href=["']([^"']*/list(?:/[^"']*)?)["'][^>]*>([\s\S]*?)</a>"#,block) {
                let label = guiClean(link[2]), slug = guiFirst(#"/list/([^/]+)/?"#,link[1])
                guard !label.isEmpty, label != "全部" else { continue }
                let option = SourceFilterOption(label:label,value:slug.isEmpty ? "all" : slug)
                if let index = options.firstIndex(where: { $0.label == label }) { options[index] = option } else { options.append(option) }
            }
            if !options.isEmpty { result.append(.init(key:key,label:label,options:[.init(label:"全部",value:"all")]+options)) }
        }
        guard !result.isEmpty else { throw guiError("分类解析失败") }; return result
    }
    public func detail(comicId: String) async throws -> ComicDetail {
        let raw = rawID(comicId), html = try await fetch("/comic/"+raw)
        var cover = cleanURL(guiFirst(#"<meta[^>]+(?:property|name)=["']og:image["'][^>]+content=["']([^"']*)["']"#,html))
        if cover.isEmpty { cover = image(guiFirst(#"(<a[^>]+class=["'][^"']*bcover[^"']*["'][\s\S]*?<img[^>]+>)"#,html)) }
        if cover.isEmpty { cover = image(guiFirst(#"(<div[^>]+class=["'][^"']*(?:cover|thumb|book)[^"']*["'][\s\S]*?<img\b[^>]*>)"#,html)) }
        if cover.isEmpty { cover = "https://cf.mhgui.com/cpic/b/\(raw).jpg" }
        return .init(summary:.init(sourceId:id,comicId:id+":"+raw,title:guiClean(guiFirst(#"<h1[^>]*>([\s\S]*?)</h1>"#,html)),coverUrl:absolute(cover)),
                     author:guiClean(guiFirst(#"漫画作者[：:]?</strong>\s*<a[^>]*>([\s\S]*?)</a>"#,html)),
                     status:guiClean(guiFirst(#"漫画状态[：:]?</strong>\s*<span[^>]*>([\s\S]*?)</span>"#,html)),
                     description:guiClean(guiFirst(#"<div[^>]+id=["']intro-cut["'][^>]*>([\s\S]*?)</div>"#,html)),
                     latestChapter:guiClean(guiFirst(#"更新至\s*\[\s*<a[^>]*>([\s\S]*?)</a>"#,html)),chapters:[])
    }
    public func chapters(comicId: String) async throws -> [Chapter] {
        let raw = rawID(comicId), html = try await fetch("/comic/"+raw)
        var result: [Chapter] = [], seen = Set<String>()
        for link in guiMatches(#"<a[^>]*href=["'](/comic/(\d+)/(\d+)\.html)["'][^>]*>([\s\S]*?)</a>"#,html) {
            try Task.checkCancellation()
            guard link[2] == raw, seen.insert(link[1]).inserted else { continue }
            let title = guiAttribute("title",link[0])
            result.append(.init(chapterId:link[3],title:guiClean(title.isEmpty ? link[4] : title),url:absolute(link[1]),chapterSlot:Int32(link[3]).map(Int.init) ?? result.count))
        }
        return result.sorted { $0.chapterSlot < $1.chapterSlot }
    }
    public func chapter(url: String) async throws -> ChapterPage {
        let target = absolute(url), html = try await fetch(target,reader:true)
        let images = try ManhuaguiReader.images(html)
        return .init(chapterId:target,title:guiClean(guiFirst(#"<h2[^>]*>([\s\S]*?)</h2>"#,html)),nextPageUrl:"",imageUrls:images)
    }
    private func cards(_ html: String) throws -> [ComicSummary] {
        var result: [ComicSummary] = [], seen = Set<String>()
        for block in guiMatches(#"<a\b(?=[^>]*\bclass=["'][^"']*\bbcover\b)[^>]*>[\s\S]*?</a>"#,html) {
            try Task.checkCancellation()
            let raw = rawID(guiAttribute("href",block[0])), tag = guiFirst(#"(<img\b[^>]*>)"#,block[0])
            let attrTitle = guiAttribute("title",block[0]), title = guiClean(attrTitle.isEmpty ? guiAttribute("alt",tag) : attrTitle)
            guard !raw.isEmpty, !title.isEmpty, seen.insert(raw).inserted else { continue }
            result.append(.init(sourceId:id,comicId:id+":"+raw,title:title,coverUrl:absolute(image(tag))))
        }
        guard !result.isEmpty else { throw guiError("列表解析为空") }; return result
    }
    private func fetch(_ path: String, reader: Bool = false, redirects: Int = 0) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string:absolute(path)), ["http","https"].contains(url.scheme), url.host != nil else { throw guiError("网址无效") }
        let response = try await (reader ? readerTransport : transport).get(url,headers:[
            "User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36",
            "Referer":referer,"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
            "Accept-Language":"zh-CN,zh;q=0.9","Accept-Encoding":"gzip","Upgrade-Insecure-Requests":"1","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1",
            "sec-ch-ua":"\"Not;A=Brand\";v=\"8\", \"Chromium\";v=\"150\", \"Google Chrome\";v=\"150\"","sec-ch-ua-mobile":"?0","sec-ch-ua-platform":"\"Windows\""])
        if (300..<400).contains(response.statusCode), redirects < 5, let location = response.headerValue(for:"Location"), !location.isEmpty {
            var target = absolute(location)
            if var components = URLComponents(string:target), components.scheme == "http", components.host == URL(string:base)?.host {
                components.scheme = "https"; target = components.string ?? target
            }
            return try await fetch(target,reader:reader,redirects:redirects+1)
        }
        guard (200..<300).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard response.data.count <= 32*1024*1024, let html = String(data:response.data,encoding:.utf8) else { throw guiError("响应过大或编码无效") }
        try Task.checkCancellation(); return html
    }
    private func rawID(_ value: String) -> String {
        let value = HTML4EntityDecoder.decode(value).replacingOccurrences(of:"manhuagui:",with:"")
        let pathID = guiFirst(#"/comic/(\d+)/?"#,value)
        return pathID.isEmpty ? guiFirst(#"(\d+)"#,value) : pathID
    }
    private func image(_ tag: String) -> String {
        cleanURL(["data-src","data-original","src"].map { guiAttribute($0,tag) }.first { !$0.isEmpty } ?? "")
    }
    private func cleanURL(_ text: String) -> String {
        let value = SearchRules.trim(HTML4EntityDecoder.decode(text).replacingOccurrences(of:#"\/"#,with:"/"))
        return String(value.prefix { $0 != "\"" && $0 != " " })
    }
    private func absolute(_ value: String) -> String {
        let value = HTML4EntityDecoder.decode(value).replacingOccurrences(of:#"\/"#,with:"/").trimmingCharacters(in:.whitespacesAndNewlines)
        if value.isEmpty { return "" }; if value.hasPrefix("//") { return "https:"+value }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        return base + (value.hasPrefix("/") ? "" : "/") + value
    }
}
func guiError(_ message: String = "数据格式错误") -> Error { NSError(domain:"Manhuagui",code:1,userInfo:[NSLocalizedDescriptionKey:"漫画柜："+message]) }
func guiMatches(_ pattern: String, _ text: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive) else { return [] }
    return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).map { match in
        (0..<match.numberOfRanges).map { Range(match.range(at:$0),in:text).map { String(text[$0]) } ?? "" }
    }
}
func guiFirst(_ pattern: String, _ text: String) -> String { guiMatches(pattern,text).first?.dropFirst().first ?? "" }
private func guiAttribute(_ name: String, _ text: String) -> String { HTML4EntityDecoder.decode(guiFirst("\\b"+name+"=[\"']([^\"']*)[\"']",text)) }
private func guiClean(_ value: String) -> String {
    HTML4EntityDecoder.decode(value.replacingOccurrences(of:#"(?is)<(?:script|style)\b[^>]*>[\s\S]*?</(?:script|style)>"#,with:" ",options:.regularExpression).replacingOccurrences(of:#"<[^>]*>"#,with:" ",options:.regularExpression)).replacingOccurrences(of:#"\s+"#,with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
}
func guiEncode(_ value: String) -> String {
    (value.addingPercentEncoding(withAllowedCharacters:CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.*")) ?? "").replacingOccurrences(of:"%20",with:"+")
}
