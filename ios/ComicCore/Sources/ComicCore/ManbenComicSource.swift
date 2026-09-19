import Foundation
import CoreFoundation

public actor ManbenComicSource: ComicSource {
    public nonisolated let id = "manben"
    public nonisolated let name = "漫本"
    public nonisolated let referer = "https://www.manben.com/"
    private let transport: any HTTPTransport
    private let chapterTransport: any HTTPTransport
    public init(transport: (any HTTPTransport)? = nil) {
        self.transport = transport ?? URLSessionHTTPTransport(timeoutInterval: 20)
        chapterTransport = transport ?? URLSessionHTTPTransport(timeoutInterval: 30)
    }

    public func latest(page: Int) async throws -> [ComicSummary] { try await category(filters: [:], page: page) }
    public func category(filters: [String:String], page: Int) async throws -> [ComicSummary] {
        func value(_ key: String, fallback: String = "0") -> String {
            let v = SearchRules.trim(filters[key] ?? "all")
            return v.isEmpty || v == "all" ? fallback : v
        }
        let fields = [("t","2"), ("pageindex",String(max(1,page))), ("sc","1"), ("tsort","2"),
                      ("tagid",value("tag")), ("tst",value("state")), ("tarea",value("region")),
                      ("tgroup",value("audience")), ("tnm",value("letter",fallback: ""))]
        let body = Data(fields.map { form($0.0) + "=" + form($0.1) }.joined(separator: "&").utf8)
        let json = try await fetch("/mh-list/pagerdata.ashx", body: body)
        guard let array = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else { throw error("分类 JSON 非数组") }
        var seen = Set<String>()
        return array.compactMap { entry in
            guard let item = entry as? [String:Any] else { return nil }
            let rawID = rawComicID(item["Url"] as? String ?? "")
            let title = clean(item["Title"] as? String ?? "")
            guard !rawID.isEmpty, seen.insert(rawID).inserted, !title.isEmpty else { return nil }
            let author = clean((item["Author"] as? [String])?.first ?? "")
            var tags = Set<String>()
            return .init(sourceId: id, comicId: id + ":" + rawID, title: title,
                         coverUrl: absolute(item["BigPic"] as? String ?? ""),
                         subtitle: author.isEmpty ? clean(item["LastPartShowName"] as? String ?? "") : author,
                         tags: ((item["TagList"] as? [String]) ?? []).map(clean).filter { !$0.isEmpty && tags.insert($0).inserted })
        }
    }
    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        let html = try await fetch("/search?page=\(max(1,page))&title=\(form(SearchRules.trim(keyword)))&language=1")
        guard !matches(#"class=["'][^"']*\b(?:item|pager)\b[^"']*["']"#, html).isEmpty else { throw error("搜索列表解析失败") }
        var seen = Set<String>()
        return matches(#"class=["'][^"']*\bitem\b[^"']*["'][^>]*>([\s\S]*?)(?=class=["'][^"']*\b(?:item|pager)\b[^"']*["']|$)"#, html).compactMap { match in
            let block = match[1], rawID = first(#"/mh-([^/"'\?]+)/"#, match[1])
            guard !rawID.isEmpty, seen.insert(rawID).inserted else { return nil }
            var title = clean(first(#"class=["']title["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)</a>"#, block))
            if title.isEmpty { title = clean(first(#"class=["']title["'][^>]*>([\s\S]*?)</div>"#, block)) }
            guard !title.isEmpty else { return nil }
            let image = matches(#"<img\b[^>]*>"#, block).map { $0[0] }
            let cover = image.first(where: { attribute("class",$0).contains("cover") }) ?? image.first ?? ""
            return .init(sourceId: id, comicId: id + ":" + rawID, title: title, coverUrl: absolute(imageURL(cover)),
                         subtitle: clean(first(#"class=["']tip["'][^>]*>([\s\S]*?)</(?:div|p)>"#, block)))
        }
    }
    public func filterGroups() async throws -> [SourceFilterGroup] {
        let html = try await fetch("/mh-list/")
        let keys = ["进度":"state", "标签":"tag", "受众":"audience", "地区":"region", "字母":"letter"]
        let groups: [SourceFilterGroup] = matches(#"<li>\s*<div[^>]*class=["']title["'][^>]*>([\s\S]*?)</div>\s*<div[^>]*class=["']list["'][^>]*>([\s\S]*?)</div>\s*</li>"#, html).compactMap { section in
            let label = clean(section[1])
            guard let key = keys[label] else { return nil }
            let options: [SourceFilterOption] = matches(#"<a\b((?:[^"'>]|"[^"]*"|'[^']*')*)>([\s\S]*?)</a>"#, section[2]).compactMap { link in
                let onclick = attribute("onclick",link[1]), label = clean(link[2])
                guard !onclick.isEmpty, !label.isEmpty else { return nil }
                let value = first(#"tagClick\(\s*\d+\s*,\s*['"]?([^,'")\s]+)"#, onclick)
                return .init(label: label, value: value.isEmpty ? "all" : value)
            }
            return options.isEmpty ? nil : .init(key: key, label: label, options: options)
        }
        guard !groups.isEmpty else { throw error("分类解析失败") }
        return groups
    }
    public func detail(comicId: String) async throws -> ComicDetail {
        let rawID = rawComicID(comicId), html = try await fetch("/mh-\(rawComicID(comicId))/")
        guard let info = div(attribute: "class", value: "comicInfo", in: html) else { throw error("详情解析失败") }
        let titleHTML = first(#"<p[^>]*class=["']title["'][^>]*>([\s\S]*?)</p>"#, info)
        let tail = titleHTML.range(of: "</span>", options: [.backwards,.caseInsensitive]).map { String(titleHTML[$0.upperBound...]) } ?? titleHTML
        var title = clean(tail)
        if title.isEmpty { title = clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#,info)) }
        if title.isEmpty { title = clean(first(#"<title>([\s\S]*?)</title>"#,html)).components(separatedBy: " - ").first?.components(separatedBy: "_").first ?? "" }
        guard !title.isEmpty else { throw error("详情标题为空") }
        let coverBlock = div(attribute: "class",value: "cover",in: info) ?? ""
        var cover = absolute(imageURL(matches(#"<img\b[^>]*>"#,coverBlock).first?[0] ?? ""))
        if cover.isEmpty { cover = absolute(meta("og:image",html)) }
        if cover.isEmpty {
            let image = matches(#"<img\b[^>]*>"#, info).map { $0[0] }.first { attribute("alt",$0).contains(title) || attribute("title",$0).contains(title) } ?? ""
            cover = absolute(imageURL(image))
        }
        let links = matches(#"<a\b((?:[^"'>]++|"[^"]*"|'[^']*')*+)>([\s\S]*?)</a>"#,info)
        var author = clean(links.first { attribute("class",$0[1]).split(whereSeparator: \.isWhitespace).contains("avatar") }?[2] ?? "")
        if author.isEmpty { author = clean(first(#"作\s*者[：:]?\s*<a[^>]*>([\s\S]*?)</a>"#,info)) }
        let status = clean(first(#"状\s*态[：:]?\s*([^<]+)"#,info))
        var description = clean(first(#"<p[^>]*class=["']content["'][^>]*>([\s\S]*?)</p>"#,info))
        if description.isEmpty { description = clean(meta("Description",html)) }
        let shortcuts = links.filter { attribute("class",$0[1]).split(whereSeparator: \.isWhitespace).contains("op") }
        let latest = clean((shortcuts.first { !first(#"/m(\d+)/"#,attribute("href",$0[1])).isEmpty } ?? shortcuts.first)?[2] ?? "")
        let tags = clean(first(#"类\s*别[：:]?\s*([^<]+)"#,info)).components(separatedBy: CharacterSet(charactersIn: "/／")).map(clean).filter { !$0.isEmpty }
        return .init(summary: .init(sourceId: id,comicId: id + ":" + rawID,title: title,coverUrl: cover,subtitle: author,tags: tags),author: author,status: status,description: description,latestChapter: latest,chapters: [])
    }
    public func chapters(comicId: String) async throws -> [Chapter] {
        let html = try await fetch("/mh-\(rawComicID(comicId))/")
        guard let block = div(attribute: "id",value: "chapterlistload",in: html) else { throw error("目录解析失败") }
        let starts = matches(#"<div\b[^>]*class=["'][^"']*\blist\b[^"']*["'][^>]*>[\s\S]*?(?=<div\b[^>]*class=["'][^"']*\blist\b|$)"#, block).map { $0[0] }
        let groups = starts.isEmpty ? [block] : starts
        var seen = Set<String>(), result: [Chapter] = []
        for (section, group) in groups.enumerated() {
            let chapters: [Chapter] = matches(#"<a[^>]*href=["'][^"']*/m(\d+)/?[^"']*["'][^>]*>([\s\S]*?)</a>"#,group).compactMap { link in
                guard seen.insert(link[1]).inserted else { return nil }
                let title = clean(link[2])
                return .init(chapterId: link[1], title: title.isEmpty ? "第\(link[1])话" : title,url: absolute("/m\(link[1])/"),sectionSlot: section)
            }.sorted { (Int64($0.chapterId) ?? 0) < (Int64($1.chapterId) ?? 0) }
            for chapter in chapters { result.append(.init(chapterId: chapter.chapterId,title: chapter.title,url: chapter.url,sectionSlot: section,chapterSlot: result.count)) }
        }
        return result
    }
    public func chapter(url: String) async throws -> ChapterPage {
        let url = absolute(url), html = try await fetch(url, isChapter: true)
        var title = clean(first(#"<title>([\s\S]*?)</title>"#,html)).components(separatedBy: " - ").first ?? ""
        if title.isEmpty { title = clean(first(#"<h1[^>]*>([\s\S]*?)</h1>"#,html)) }
        if (html.contains("屏蔽") || html.contains("章节数据缺少")) && !html.contains("class=\"myview\"") && !html.contains("class=\"pageItem\"") && !html.contains("imageshow.ashx") { throw error("章节已被站点屏蔽：" + title) }
        let chapterID = first(#"/m(\d+)/?"#,url)
        guard !chapterID.isEmpty else { throw error("章节 ID 解析失败") }
        var images: [String] = [], seen = Set<String>(), emptyCount = 0
        for page in 1...1000 {
            let script = try await fetch("/imageshow.ashx?cid=\(chapterID)&page=\(page)&showtype=1&ispre=0", referer: url)
            guard script.contains("chapterimage"), let begin = script.firstIndex(of: "{"), let end = script.lastIndex(of: "}"), begin < end,
                  let root = try? JSONSerialization.jsonObject(with: Data(script[begin...end].utf8)) as? [String:Any],
                  let prefix = root["ImagePix"] as? String, !prefix.isEmpty,
                  let paths = root["Images"] as? [String], !paths.isEmpty else { throw error("图片数据格式异常") }
            let previous = images.count
            for path in paths where !path.isEmpty {
                let image = path.hasPrefix("https://") || path.hasPrefix("http://") ? path : prefix + path
                if (image.hasPrefix("https://") || image.hasPrefix("http://")) && image.hasPrefix(prefix) && seen.insert(image).inserted { images.append(image) }
            }
            if (root["IsEnd"] as? Bool) == true || (root["IsEnd"] as? String)?.lowercased() == "true" {
                guard !images.isEmpty else { throw error("图片数据为空") }
                return .init(chapterId: url,title: title,nextPageUrl: "",imageUrls: images)
            }
            emptyCount = images.count == previous ? emptyCount + 1 : 0
            if emptyCount >= 2 { throw error("图片循环无新增") }
        }
        throw error("图片数据未正常结束")
    }
    private func fetch(_ path: String, referer: String? = nil, body: Data? = nil, isChapter: Bool = false) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: absolute(path)) else { throw URLError(.badURL) }
        var headers = ["Referer": referer ?? self.referer,
                       "User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                       "Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
                       "Accept-Language":"zh-CN,zh;q=0.9", "Accept-Encoding":"gzip"]
        let response: HTTPResponse
        if let body {
            headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
            response = try await transport.post(url,headers: headers,body: body)
        } else { response = try await (isChapter ? chapterTransport : transport).get(url,headers: headers) }
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        var encoding = String.Encoding.utf8
        if let name = response.textEncodingName, !name.isEmpty,
           let charset = CFStringCreateWithCString(nil, name, CFStringBuiltInEncodings.UTF8.rawValue) {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset)
            guard cfEncoding != kCFStringEncodingInvalidId else { throw error("响应字符集不支持：" + name) }
            encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        }
        guard let text = String(data: response.data,encoding: encoding) else { throw error("响应文字解码失败") }
        return text
    }
    private func div(attribute key: String, value: String, in html: String) -> String? {
        let tags = matches(#"</?div\b(?:[^"'>]|"[^"]*"|'[^']*')*>"#,html)
        guard let start = tags.first(where: { tag in
            let found = attribute(key,tag[0]); return key == "class" ? found.split(whereSeparator: \.isWhitespace).contains(Substring(value)) : found == value
        }), let startRange = html.range(of: start[0]) else { return nil }
        let tail = String(html[startRange.lowerBound...])
        let regex = try! NSRegularExpression(pattern: #"</?div\b(?:[^"'>]|"[^"]*"|'[^']*')*>"#,options: .caseInsensitive)
        var depth = 0
        for tag in regex.matches(in: tail,range: NSRange(tail.startIndex...,in: tail)) {
            guard let range = Range(tag.range,in: tail) else { continue }
            depth += tail[range].hasPrefix("</") ? -1 : 1
            if depth == 0 { return String(tail[..<range.upperBound]) }
        }
        return nil
    }
    private func rawComicID(_ value: String) -> String {
        let value = value.hasPrefix("manben:") ? String(value.dropFirst(7)) : value
        let matched = first(#"/mh-([^/"'\?]+)/"#,value)
        return matched.isEmpty ? SearchRules.trim(value.replacingOccurrences(of: "/+$",with: "",options: .regularExpression)) : matched
    }
    private func absolute(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        if value.hasPrefix("//") { return "https:" + value }
        return referer + (value.hasPrefix("/") ? String(value.dropFirst()) : value)
    }
    private func imageURL(_ tag: String) -> String {
        for key in ["data-src","data-original","src"] {
            let value = attribute(key,tag).replacingOccurrences(of: "&amp;",with: "&").replacingOccurrences(of: #"\/"#,with: "/")
            if !value.isEmpty { return SearchRules.trim(value).components(separatedBy: "\"").first?.components(separatedBy: " ").first ?? "" }
        }
        return ""
    }
    private func meta(_ key: String, _ html: String) -> String {
        for tag in matches(#"<meta\b[^>]*>"#,html) where attribute("property",tag[0]) == key || attribute("name",tag[0]) == key { return attribute("content",tag[0]) }
        return ""
    }
    private func form(_ text: String) -> String {
        text.utf8.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45,46,95,42].contains(byte) { return String(UnicodeScalar(byte)) }
            return byte == 32 ? "+" : String(format: "%%%02X",byte)
        }.joined()
    }
    private func clean(_ value: String) -> String {
        let text = value.replacingOccurrences(of: #"<br\b[^>]*>|</?(?:p|div)\b[^>]*>"#,with: " ",options: [.regularExpression,.caseInsensitive]).replacingOccurrences(of: #"<[^>]*>"#,with: "",options: .regularExpression)
        return SearchRules.trim(HTML4EntityDecoder.decode(text).replacingOccurrences(of: #"\s+"#,with: " ",options: .regularExpression))
    }
    private func attribute(_ key: String, _ html: String) -> String {
        matches(#"(?:^|\s)([\w:-]+)\s*=\s*(["'])([\s\S]*?)\2"#,html).first { $0[1].lowercased() == key.lowercased() }?[3] ?? ""
    }
    private func matches(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern,options: .caseInsensitive) else { return [] }
        return regex.matches(in: value,range: NSRange(value.startIndex...,in: value)).map { m in (0..<m.numberOfRanges).map { Range(m.range(at: $0),in: value).map { String(value[$0]) } ?? "" } }
    }
    private func first(_ pattern: String, _ value: String) -> String { matches(pattern,value).first?[1] ?? "" }
    private func error(_ message: String) -> NSError { NSError(domain: "ManbenComicSource",code: 1,userInfo: [NSLocalizedDescriptionKey:name + " " + message]) }
}
