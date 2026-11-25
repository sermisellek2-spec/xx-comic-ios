import Foundation
import CoreFoundation

public struct FatalManwaError: LocalizedError, CustomNSError, Sendable {
    public static var errorDomain: String { "ManwaComicSource" }
    public let errorCode: Int = 1
    public let message: String

    public var errorDescription: String? { message }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: message] }

    public init(_ message: String) {
        self.message = message
    }
}

public struct ManwaComicSource: ComicSource {
    public static let mirrors: [String] = [
        "https://manwadz.cc",
        "https://www.manwacn.cc",
        "https://manwayy.cc",
        "https://manwaxu.cc",
        "https://www.manwapp.cc",
        "https://manwadh.cc",
        "https://manwarr.cc",
        "https://mwmwff.cc",
        "https://manwahh.cc",
        "https://manwadj.cc",
        "https://manwabb.cc",
        "https://manwazz.cc",
        "https://manwakk.cc",
        "https://manwann.cc",
        "https://manwaqq.cc",
        "https://mwmwbu.cc",
        "https://manwapp.cc",
        "https://manwacn.cc"
    ]

    public static let publishRouters: [String] = [
        "https://mwmw.cc",
        "https://mwmw1.cc",
        "https://mwmw2.cc",
        "https://manwami.cc",
        "https://manwaha.cc",
        "https://manwala.cc"
    ]

    private static let directCcUrlRegex = try! NSRegularExpression(
        pattern: #"https://([a-z0-9-]+\.)*[a-z0-9-]+\.cc\b"#,
        options: [.caseInsensitive]
    )
    private static let b64TokenRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9+/]{28,}={0,2}"#,
        options: []
    )

    private final class FailoverState: @unchecked Sendable {
        private let lock = NSLock()
        var activeBaseUrl: String
        var failedMirrors = Set<String>()
        var discoveredMirrors = [String]()

        init(initialBaseUrl: String) {
            self.activeBaseUrl = initialBaseUrl
        }

        func snapshotBaseUrl() -> String {
            lock.lock()
            defer { lock.unlock() }
            return activeBaseUrl
        }

        func markSuccess(_ base: String) {
            lock.lock()
            activeBaseUrl = base
            failedMirrors.remove(base)
            lock.unlock()
        }

        func markFailed(_ base: String) {
            lock.lock()
            failedMirrors.insert(base)
            lock.unlock()
        }

        func candidateMirrors(configuredBase: String) -> [String] {
            lock.lock()
            let currentActive = activeBaseUrl
            let failed = failedMirrors
            let discovered = discoveredMirrors
            lock.unlock()

            if ManwaComicSource.isLocalHost(configuredBase) {
                return [configuredBase]
            }
            var healthy = [String]()
            var degraded = [String]()
            var seen = Set<String>()

            func appendCandidate(_ raw: String) {
                let base = ManwaComicSource.trimSlash(raw)
                guard !base.isEmpty, seen.insert(base).inserted else { return }
                if failed.contains(base) {
                    degraded.append(base)
                } else {
                    healthy.append(base)
                }
            }

            appendCandidate(currentActive)
            appendCandidate(configuredBase)
            for d in discovered { appendCandidate(d) }
            for m in ManwaComicSource.mirrors { appendCandidate(m) }
            return healthy + degraded
        }

        func recordDiscovered(_ candidates: Set<String>) {
            lock.lock()
            defer { lock.unlock() }
            for c in candidates {
                if !discoveredMirrors.contains(c) && discoveredMirrors.count < 24 {
                    discoveredMirrors.append(c)
                }
            }
        }
    }

    public let id = "manwa"
    public let name: String
    public let referer: String
    private let base: String
    private let config: SourceConfigItem
    private let transport: any HTTPTransport
    private let state: FailoverState
    private let tags = ["热血","玄幻","恋爱","冒险","古风","都市","穿越","奇幻","搞笑","少男","战斗","重生","逆袭","爆笑","少年","后宫","系统","BL","韩漫","完整版","19r","台版"]
    private let slugs = ["hotblooded","xuanhuan","romance","adventure","historical","urban","transmigration","fantasy","comedy","shounen","action","rebirth","counterattack","hilarious","youth","harem","system","bl","manhwa","fullversion","19plus","taiwanver"]

    public init(
        config: SourceConfigItem = SourceConfigDefaults.manwa(enabled: true),
        transport: any HTTPTransport = URLSessionHTTPTransport(timeoutInterval: 25)
    ) {
        self.config = config
        self.name = config.name
        let trimmedBase = Self.trimSlash(config.baseUrl)
        self.base = trimmedBase
        self.referer = config.referer.isEmpty ? "\(trimmedBase)/" : config.referer
        self.transport = transport
        self.state = FailoverState(initialBaseUrl: trimmedBase)
    }

    public var activeBaseUrl: String {
        state.snapshotBaseUrl()
    }

    public var domain: String {
        URL(string: state.snapshotBaseUrl())?.host ?? config.domain
    }

    public static func isManwaChapterUrl(_ url: String) -> Bool {
        guard !url.isEmpty,
              let parsed = URL(string: url),
              parsed.path.range(of: #"^/comic/\d+/\d+/?$"#, options: .regularExpression) != nil,
              let host = parsed.host?.lowercased(), !host.isEmpty else {
            return false
        }
        if ManwaImageDecoder.usesImageHost(url) { return true }
        for mirror in mirrors {
            if let mirrorHost = URL(string: mirror)?.host,
               host.caseInsensitiveCompare(mirrorHost) == .orderedSame {
                return true
            }
        }
        return false
    }

    public static func extractMirrorCandidates(_ body: String) -> [String] {
        var out = [String]()
        var seen = Set<String>()
        extractMirrorCandidates(body, into: &seen)
        for candidate in seen {
            out.append(candidate)
        }
        return out
    }

    public static func extractMirrorCandidates(_ body: String, into out: inout Set<String>) {
        guard !body.isEmpty else { return }
        collectHttpsCcOrigins(body, into: &out)
        let fullRange = NSRange(body.startIndex..., in: body)
        let matches = b64TokenRegex.matches(in: body, options: [], range: fullRange)
        var count = 0
        for match in matches {
            if count >= 32 { break }
            count += 1
            guard let range = Range(match.range, in: body) else { continue }
            let token = String(body[range])
            if token.count % 4 != 0 { continue }
            if let decodedData = Data(base64Encoded: token),
               let decoded = String(data: decodedData, encoding: .utf8),
               decoded.contains("https://") {
                collectHttpsCcOrigins(decoded, into: &out)
            }
        }
    }

    private static func collectHttpsCcOrigins(_ text: String, into out: inout Set<String>) {
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = directCcUrlRegex.matches(in: text, options: [], range: fullRange)
        for match in matches {
            if out.count >= 24 { break }
            guard let range = Range(match.range, in: text) else { continue }
            let raw = trimSlash(String(text[range]))
            guard let parsed = URL(string: raw),
                  let scheme = parsed.scheme,
                  let host = parsed.host?.lowercased() else {
                continue
            }
            if host == "manwace.cc" || host == "manwads.cc"
                || host.hasPrefix("mwmw.")
                || host.range(of: #"^mwmw\d+\.cc$"#, options: .regularExpression) != nil
                || host == "manwala.cc" || host == "manwami.cc" || host == "manwaha.cc"
                || ManwaImageDecoder.isOnlyImageDomain(host) {
                continue
            }
            let portSuffix = parsed.port.map { ":\($0)" } ?? ""
            out.insert("\(scheme)://\(host)\(portSuffix)")
        }
    }

    public func latest(page: Int) async throws -> [ComicSummary] { try await category(filters: [:], page: page) }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        let keyword = SearchRules.trim(keyword)
        guard !keyword.isEmpty else { return [] }
        let path = config.route("search")
            .replacingOccurrences(of: "{page}", with: String(max(1, page)))
            .replacingOccurrences(of: "{keyword}", with: form(keyword))
        return try await executeWithFailover(maxStatic: 6, allowDiscovery: false) { currentBase in
            let url = try self.resolveOn(currentBase, path)
            let reqReferer = (currentBase == self.base) ? self.referer : (currentBase + "/")
            return try self.cards(await self.request(url, referer: reqReferer), base: currentBase)
        }
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
        let typeID = number("type")
        return try await executeWithFailover(maxStatic: 10, allowDiscovery: true) { currentBase in
            let reqUrl = try self.resolveOn(currentBase, route + suffix)
            let refUrl = try self.resolveOn(currentBase, "/cate" + suffix)
            return try self.cards(await self.request(reqUrl, referer: refUrl, body: body, typeID: typeID), base: currentBase)
        }
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let raw = try rawID(comicId)
        let path = config.route("detail").replacingOccurrences(of: "{comicId}", with: raw)
        return try await executeWithFailover(maxStatic: 10, allowDiscovery: true) { currentBase in
            let url = try self.resolveOn(currentBase, path)
            let reqReferer = (currentBase == self.base) ? self.referer : (currentBase + "/")
            let data = try await self.request(url, referer: reqReferer)
            guard let html = String(data: data, encoding: .utf8) else { throw self.error("详情文字解码失败") }
            let title = self.clean(self.element("page-title", html))
            guard !title.isEmpty else { throw self.error("详情解析失败，站点可能暂不可用") }
            let image = self.first(#"(<img\b[^>]*class=["'][^"']*\bcomic-cover\b[^"']*["'][^>]*>)"#, html)
            let cover = ["data-src","data-original-cover","src"].map { self.attribute($0,image) }.first { !$0.isEmpty } ?? ""
            let author = self.clean(self.element("author-container",html)).replacingOccurrences(of: #"\s*，\s*"#, with: "，", options: .regularExpression)
            let labels = self.matches(#"<a\b[^>]*>([\s\S]*?)</a>"#, self.element("tagsContainer",html)).map { self.clean($0[1]) }.filter { !$0.isEmpty }
            let summary = ComicSummary(sourceId: self.id, comicId: self.id + ":" + raw, title: title, coverUrl: try self.resolveOn(currentBase, cover), subtitle: author, tags: labels)
            return .init(summary: summary, author: author, status: self.clean(self.element("status",html)), description: self.clean(self.first(#"<p\b[^>]*class=["'][^"']*\bcomic-desc\b[^"']*["'][^>]*>([\s\S]*?)</p>"#,html)), latestChapter: self.clean(self.element("newch",html)), chapters: [])
        }
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let raw = try rawID(comicId)
        let path = config.route("chapters").replacingOccurrences(of: "{comicId}", with: raw)
        return try await executeWithFailover(maxStatic: 10, allowDiscovery: true) { currentBase in
            let detail = try self.detailURL(raw, base: currentBase)
            let url = try self.resolveOn(currentBase, path)
            let payload = try self.json(await self.request(url, referer: detail))
            let rows = try self.array(payload,"list")
            var ordered: [(Int,Double,String,String)] = []
            for (index, value) in rows.enumerated() {
                guard let row = value as? [String:Any] else { throw FatalManwaError("漫蛙目录条目格式错误") }
                let rowId = self.string(row["id"])
                guard self.numeric(rowId), let idVal = UInt64(rowId), idVal > 0 else { throw FatalManwaError("漫蛙目录条目格式错误") }
                let sort = Double(self.string(row["sortId"])) ?? 0
                guard sort.isFinite else { throw FatalManwaError("漫蛙目录排序值无效") }
                ordered.append((index,sort,rowId,self.clean(self.string(row["title"]))))
            }
            ordered.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
            var seen = Set<String>(), chapters: [Chapter] = []
            for row in ordered where seen.insert(row.2).inserted {
                chapters.append(.init(chapterId: row.2, title: row.3, url: detail + "/" + row.2, chapterSlot: chapters.count))
            }
            return chapters
        }
    }

    public func chapter(url: String) async throws -> ChapterPage {
        let canonicalAddress = try resolveOn(state.snapshotBaseUrl(), url)
        guard let path = URL(string: canonicalAddress)?.path,
              let ids = matches(#"^/comic/(\d+)/(\d+)/?$"#,path).first else { throw error("章节链接格式错误") }
        let comic = ids[1], chapter = ids[2]
        return try await executeWithFailover(maxStatic: 10, allowDiscovery: true) { currentBase in
            let referer = try self.detailURL(comic, base: currentBase) + "/" + chapter
            let infoRoute = self.config.route("chapterInfo").replacingOccurrences(of: "{chapterId}", with: chapter)
            let info = try self.json(await self.request(try self.resolveOn(currentBase, infoRoute), referer: referer))
            guard let current = info["current"] as? [String:Any],
                  self.string(current["comicId"]) == comic,
                  self.string(current["id"]) == chapter else {
                throw FatalManwaError("漫蛙章节信息不匹配")
            }
            var images: [String] = [], seen = Set<String>(), expectedTotal = -1, expectedPages = -1
            let imageSource = self.config.route("imageSource").isEmpty ? ManwaImageDecoder.IMAGE_CDNS[0] : self.config.route("imageSource")
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
            let encodedSource = imageSource.addingPercentEncoding(withAllowedCharacters: allowed) ?? imageSource
            let imageRoute = self.config.route("images").isEmpty
                ? "/api/comic/image/{chapterId}?page={page}&page_size=100&image_source={imageSource}"
                : self.config.route("images")
            for page in 1...500 {
                try Task.checkCancellation()
                let pagePath = imageRoute
                    .replacingOccurrences(of: "{chapterId}", with: chapter)
                    .replacingOccurrences(of: "{page}", with: String(page))
                    .replacingOccurrences(of: "{imageSource}", with: encodedSource)
                let payload = try self.json(await self.request(try self.resolveOn(currentBase, pagePath), referer: referer))
                let rows = try self.array(payload,"images")
                guard let pagination = payload["pagination"] as? [String:Any],
                      let total = Int(self.string(pagination["total"])), total > 0,
                      let pages = Int(self.string(pagination["total_pages"])), (1...500).contains(pages),
                      Int(self.string(pagination["current_page"])) == page else {
                    throw FatalManwaError("漫蛙章节暂无可读取图片或分页信息无效")
                }
                if page == 1 { expectedTotal = total; expectedPages = pages }
                guard expectedTotal == total, expectedPages == pages else { throw FatalManwaError("漫蛙章节图片正在变化，请重试") }
                guard !rows.isEmpty else { throw FatalManwaError("图片分页为空") }
                for value in rows {
                    guard let row = value as? [String:Any] else { throw FatalManwaError("图片条目格式错误") }
                    let image = try self.resolveOn(currentBase, self.string(row["url"]))
                    guard !image.isEmpty, seen.insert(image).inserted else { throw FatalManwaError("图片缺失或分页重复") }
                    images.append(image)
                }
                if page == pages {
                    guard images.count == total else { throw FatalManwaError("章节图片不完整，请重试") }
                    return .init(chapterId: canonicalAddress, title: self.clean(self.string(current["title"])), nextPageUrl: "", imageUrls: images)
                }
            }
            throw FatalManwaError("漫蛙图片分页过多")
        }
    }

    private func executeWithFailover<T>(
        maxStatic: Int,
        allowDiscovery: Bool,
        action: (String) async throws -> T
    ) async throws -> T {
        let candidates = state.candidateMirrors(configuredBase: base)
        let limit = min(candidates.count, max(1, maxStatic))
        var tried = Set<String>()
        var lastError: Error?

        for i in 0..<limit {
            try Task.checkCancellation()
            let candidateBase = candidates[i]
            tried.insert(candidateBase)
            do {
                let result = try await action(candidateBase)
                state.markSuccess(candidateBase)
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch let fatal as FatalManwaError {
                throw fatal
            } catch {
                if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled {
                    throw CancellationError()
                }
                lastError = error
                if !Self.isLocalHost(candidateBase) {
                    state.markFailed(candidateBase)
                }
            }
        }

        if allowDiscovery && !Self.isLocalHost(base) {
            let discovered = await discoverMirrorsFromPublishPages(alreadyTried: tried)
            for dynamicBase in discovered {
                try Task.checkCancellation()
                tried.insert(dynamicBase)
                do {
                    let result = try await action(dynamicBase)
                    state.markSuccess(dynamicBase)
                    return result
                } catch is CancellationError {
                    throw CancellationError()
                } catch let fatal as FatalManwaError {
                    throw fatal
                } catch {
                    if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled {
                        throw CancellationError()
                    }
                    lastError = error
                    state.markFailed(dynamicBase)
                }
            }
        }

        if let lastError { throw lastError }
        throw error("所有备用站点均暂不可用，请稍后重试")
    }

    private func discoverMirrorsFromPublishPages(alreadyTried: Set<String>) async -> [String] {
        var seen = Set<String>()
        for router in Self.publishRouters {
            if Task.isCancelled || seen.count >= 8 { break }
            do {
                let data = try await request(router + "/", referer: router + "/")
                if let body = String(data: data, encoding: .utf8) {
                    Self.extractMirrorCandidates(body, into: &seen)
                }
            } catch {
            }
        }
        state.recordDiscovered(seen)
        return seen.filter { !alreadyTried.contains($0) }
    }

    private func request(_ urlString: String, referer: String? = nil, body: [String:Any]? = nil, typeID: Int = 0) async throws -> Data {
        try Task.checkCancellation()
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        if !Self.isLocalHost(base), let host = url.host {
            do {
                try RuleHttp.checkNonLocalHost(host)
            } catch {
                throw self.error("域名解析异常")
            }
        }
        var headers = ["Referer":referer ?? self.referer,
                       "User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                       "Accept":"application/json,text/html;q=0.9,*/*;q=0.8", "Accept-Encoding":"gzip"]
        let response: HTTPResponse
        if let body {
            headers["Content-Type"] = "application/json; charset=UTF-8"
            let originScheme = url.scheme ?? "https"
            let originHost = url.host ?? ""
            let portSuffix = url.port.map { ":\($0)" } ?? ""
            headers["Origin"] = originHost.isEmpty ? base : "\(originScheme)://\(originHost)\(portSuffix)"
            headers["Cookie"] = "typeId=\(typeID)"
            response = try await transport.post(url, headers: headers, body: JSONSerialization.data(withJSONObject: body))
        } else { response = try await transport.get(url, headers: headers) }
        try Task.checkCancellation()
        if [401,403].contains(response.statusCode) { throw error("访问受限，可能需要登录或会员权限") }
        guard (200..<300).contains(response.statusCode) else { throw HTTPTransportError.invalidStatusCode(response.statusCode) }
        guard response.data.count <= 16 * 1024 * 1024 else { throw error("响应过大") }
        if let text = String(data: response.data, encoding: .utf8),
           text.contains("cf-chl-") || text.contains("Just a moment...") {
            throw error("站点触发防护验证")
        }
        return response.data
    }

    private func json(_ data: Data) throws -> [String:Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw error("接口响应格式错误") }
        let code = Int(string(root["code"])) ?? -1
        if [401,403].contains(code) { throw FatalManwaError("漫蛙访问受限，可能需要登录或会员权限") }
        if code != 200 {
            let msg = "漫蛙接口请求失败（\(code)）"
            if code > 0 && code < 500 {
                throw FatalManwaError(msg)
            }
            throw error("接口请求失败（\(code)）")
        }
        guard let data = root["data"] as? [String:Any] else { throw FatalManwaError("漫蛙接口响应格式错误") }
        return data
    }

    private func cards(_ data: Data, base: String) throws -> [ComicSummary] {
        let rows = try array(json(data),"list")
        var seen = Set<String>(), result: [ComicSummary] = []
        for value in rows {
            guard let row = value as? [String:Any] else { throw FatalManwaError("漫蛙列表条目格式错误") }
            var raw = first(#"(?:^|/)comic/(\d+)(?:[/?#]|$)"#,string(row["url"]))
            if raw.isEmpty { raw = string(row["id"]) }
            guard numeric(raw), seen.insert(raw).inserted else { continue }
            let title = clean(string(row["title"]))
            guard !title.isEmpty else { continue }
            let cover = string(row["cover"])
            let tags = clean(string(row["tags"])).components(separatedBy: CharacterSet(charactersIn: ",，/|")).map(SearchRules.trim).filter { !$0.isEmpty }
            result.append(.init(sourceId: id, comicId: id + ":" + raw, title: title, coverUrl: try resolveOn(base, cover.isEmpty ? string(row["pic"]) : cover), subtitle: clean(string(row["author"])), tags: tags))
        }
        guard rows.isEmpty || !result.isEmpty else { throw error("列表解析失败") }
        return result
    }

    private func array(_ json: [String:Any], _ key: String) throws -> [Any] {
        guard let values = json[key] as? [Any] else { throw FatalManwaError("漫蛙接口缺少 " + key) }
        return values
    }

    private func resolveOn(_ baseUrl: String, _ text: String) throws -> String {
        let trimmed = HTML4EntityDecoder.decode(SearchRules.trim(text))
        if trimmed.isEmpty { return "" }
        let baseRoot = Self.trimSlash(baseUrl) + "/"
        guard let url = URL(string: trimmed, relativeTo: URL(string: baseRoot))?.absoluteURL,
              ["http","https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else {
            throw FatalManwaError("漫蛙链接协议或地址无效")
        }
        return url.absoluteString
    }

    private func detailURL(_ comicId: String, base: String) throws -> String {
        let route = config.route("detail").isEmpty ? "/comic/{comicId}" : config.route("detail")
        return try resolveOn(base, route.replacingOccurrences(of: "{comicId}", with: comicId))
    }

    private static func isLocalHost(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }

    private static func trimSlash(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") && trimmed.count > 8 {
            trimmed.removeLast()
        }
        return trimmed
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
