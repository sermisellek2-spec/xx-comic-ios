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
    // Generated from Python's standard-library HTML 4 name2codepoint table.
    private static let html4Entities: [String: UInt32] = {
        let entries = """
        AElig=C6 Aacute=C1 Acirc=C2 Agrave=C0 Alpha=391 Aring=C5 Atilde=C3 Auml=C4 Beta=392 Ccedil=C7 Chi=3A7 Dagger=2021 Delta=394 ETH=D0 Eacute=C9 Ecirc=CA Egrave=C8 Epsilon=395 Eta=397 Euml=CB Gamma=393 Iacute=CD Icirc=CE Igrave=CC Iota=399 Iuml=CF Kappa=39A Lambda=39B Mu=39C Ntilde=D1 Nu=39D OElig=152 Oacute=D3 Ocirc=D4 Ograve=D2 Omega=3A9 Omicron=39F Oslash=D8 Otilde=D5 Ouml=D6 Phi=3A6 Pi=3A0 Prime=2033 Psi=3A8 Rho=3A1 Scaron=160 Sigma=3A3 THORN=DE Tau=3A4 Theta=398 Uacute=DA Ucirc=DB Ugrave=D9 Upsilon=3A5 Uuml=DC Xi=39E Yacute=DD Yuml=178 Zeta=396
        aacute=E1 acirc=E2 acute=B4 aelig=E6 agrave=E0 alefsym=2135 alpha=3B1 amp=26 and=2227 ang=2220 aring=E5 asymp=2248 atilde=E3 auml=E4 bdquo=201E beta=3B2 brvbar=A6 bull=2022 cap=2229 ccedil=E7 cedil=B8 cent=A2 chi=3C7 circ=2C6 clubs=2663 cong=2245 copy=A9 crarr=21B5 cup=222A curren=A4 dArr=21D3 dagger=2020 darr=2193 deg=B0 delta=3B4 diams=2666 divide=F7 eacute=E9 ecirc=EA egrave=E8 empty=2205 emsp=2003 ensp=2002 epsilon=3B5 equiv=2261 eta=3B7 eth=F0 euml=EB euro=20AC exist=2203 fnof=192 forall=2200 frac12=BD frac14=BC frac34=BE frasl=2044 gamma=3B3 ge=2265 gt=3E hArr=21D4 harr=2194 hearts=2665 hellip=2026 iacute=ED icirc=EE iexcl=A1 igrave=EC image=2111 infin=221E int=222B iota=3B9 iquest=BF isin=2208 iuml=EF kappa=3BA lArr=21D0 lambda=3BB lang=2329 laquo=AB larr=2190 lceil=2308 ldquo=201C le=2264 lfloor=230A lowast=2217 loz=25CA lrm=200E lsaquo=2039 lsquo=2018 lt=3C macr=AF mdash=2014 micro=B5 middot=B7 minus=2212 mu=3BC nabla=2207 nbsp=A0 ndash=2013 ne=2260 ni=220B not=AC notin=2209 nsub=2284 ntilde=F1 nu=3BD
        oacute=F3 ocirc=F4 oelig=153 ograve=F2 oline=203E omega=3C9 omicron=3BF oplus=2295 or=2228 ordf=AA ordm=BA oslash=F8 otilde=F5 otimes=2297 ouml=F6 para=B6 part=2202 permil=2030 perp=22A5 phi=3C6 pi=3C0 piv=3D6 plusmn=B1 pound=A3 prime=2032 prod=220F prop=221D psi=3C8 quot=22 rArr=21D2 radic=221A rang=232A raquo=BB rarr=2192 rceil=2309 rdquo=201D real=211C reg=AE rfloor=230B rho=3C1 rlm=200F rsaquo=203A rsquo=2019 sbquo=201A scaron=161 sdot=22C5 sect=A7 shy=AD sigma=3C3 sigmaf=3C2 sim=223C spades=2660 sub=2282 sube=2286 sum=2211 sup=2283 sup1=B9 sup2=B2 sup3=B3 supe=2287 szlig=DF tau=3C4 there4=2234 theta=3B8 thetasym=3D1 thinsp=2009 thorn=FE tilde=2DC times=D7 trade=2122 uArr=21D1 uacute=FA uarr=2191 ucirc=FB ugrave=F9 uml=A8 upsih=3D2 upsilon=3C5 uuml=FC weierp=2118 xi=3BE yacute=FD yen=A5 yuml=FF zeta=3B6 zwj=200D zwnj=200C apos=27
        """
        return Dictionary(uniqueKeysWithValues: entries.split(whereSeparator: \.isWhitespace).compactMap { entry in
            let pair = entry.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, let value = UInt32(pair[1], radix: 16) else { return nil }
            return (String(pair[0]), value)
        })
    }()

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

    private func htmlDecode(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&(?:#x[0-9a-f]+|#[0-9]+|[a-z][a-z0-9]+);"#, options: .caseInsensitive) else { return value }
        var decoded = value
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: value) else { continue }
            let entity = String(value[range])
            let body = entity.dropFirst().dropLast()
            let lowercased = body.lowercased()
            let replacement: String
            if lowercased.hasPrefix("#x"), let scalar = UInt32(body.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init) {
                replacement = String(Character(scalar))
            } else if body.hasPrefix("#"), let scalar = UInt32(body.dropFirst()).flatMap(UnicodeScalar.init) {
                replacement = String(Character(scalar))
            } else if let codepoint = Self.html4Entities[String(body)], let scalar = UnicodeScalar(codepoint) {
                replacement = String(Character(scalar))
            } else {
                replacement = entity
            }
            if let decodedRange = Range(match.range, in: decoded) { decoded.replaceSubrange(decodedRange, with: replacement) }
        }
        return decoded
    }

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
