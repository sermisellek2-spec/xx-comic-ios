import XCTest
@testable import ComicCore

private let copySlug = "bajiaolongdediwang"
private let copyChapter = "4cdb2472-697a-11ed-a96e-024352452ce0"
private let copyURL = "https://old.example/comic/\(copySlug)/chapter/\(copyChapter)"

private func copyFixture(_ name: String) throws -> String {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "copy4000"))
    return try String(contentsOf: url, encoding: .utf8)
}

private actor CopyTransport: HTTPTransport {
    var requests: [(URL, [String:String])] = []
    let handler: @Sendable (URL, Int) throws -> HTTPResponse
    init(_ handler: @escaping @Sendable (URL, Int) throws -> HTTPResponse) { self.handler = handler }
    init(body: String, status: Int = 200) { handler = { _,_ in HTTPResponse(data: Data(body.utf8), statusCode: status) } }
    func get(_ url: URL, headers: [String:String]) async throws -> HTTPResponse {
        requests.append((url,headers)); return try handler(url,requests.count)
    }
    func captured() -> [(URL,[String:String])] { requests }
}
private func copyResponse(_ body: String) -> HTTPResponse { .init(data: Data(body.utf8), statusCode: 200) }
private func copyJSON(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
private func copyMutate(_ name: String, _ change: (inout [String:Any]) -> Void) throws -> String {
    var root = try JSONSerialization.jsonObject(with: Data(copyFixture(name).utf8)) as! [String:Any]
    var results = root["results"] as! [String:Any]
    change(&results); root["results"] = results
    return try copyJSON(root)
}
private func copyFails(_ block: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do { try await block(); XCTFail("Expected rejection",file:file,line:line) } catch { }
}

final class CopyMangaTests: XCTestCase {
    func testCapturedSearchPagesAndQueryHeaders() async throws {
        let t = CopyTransport { url,_ in copyResponse(try copyFixture(url.query!.contains("offset=12") ? "search-page2.json" : "search-page1.json")) }
        let source = CopyMangaComicSource(transport:t)
        let first = try await source.search(keyword:" 海 & 空 ",page:1)
        let second = try await source.search(keyword:"海",page:2)
        XCTAssertEqual(first.count,12); XCTAssertEqual(second.count,12)
        XCTAssertEqual(first[0].comicId,"copy4000:haiwuyu"); XCTAssertEqual(first[0].subtitle,"葛城彰")
        XCTAssertTrue(Set(first.map(\.comicId)).isDisjoint(with: second.map(\.comicId)))
        let requests = await t.captured()
        XCTAssertEqual(requests[0].0.absoluteString,"https://www.copy4000.com/api/kb/web/searchci/comics?offset=0&platform=2&limit=12&q=%E6%B5%B7%20%26%20%E7%A9%BA&q_type=")
        XCTAssertEqual(requests[0].1["Referer"],"https://www.copy4000.com/")
        XCTAssertTrue(requests[0].1["User-Agent"]!.contains("Chrome/140.0.0.0"))
        XCTAssertTrue(requests[0].1["Accept"]!.hasPrefix("application/json")); XCTAssertNil(requests[0].1["dnts"])
    }
    func testEmptySearchSkipsNetworkAndInvalidPagesReject() async throws {
        let t = CopyTransport(body:"bad")
        let s = CopyMangaComicSource(transport:t)
        let empty = try await s.search(keyword:" \n ",page:0)
        XCTAssertEqual(empty,[])
        await copyFails { _ = try await s.search(keyword:"a",page:0) }
        await copyFails { _ = try await s.latest(page:0) }
        await copyFails { _ = try await s.latest(page:Int.max) }
        let requests = await t.captured(); XCTAssertEqual(requests.count,0)
    }
    func testCapturedCategoryAndOrderedFilters() async throws {
        let t = CopyTransport(body:try copyFixture("category.html"))
        let s = CopyMangaComicSource(transport:t)
        let cards = try await s.category(filters:["status":"0","theme":"COLOR","region":"0"],page:2)
        XCTAssertEqual(cards.count,50); XCTAssertEqual(cards.first?.comicId,"copy4000:renzhehejidao")
        _ = try await s.category(filters:["theme":"all","ordering":"all","region":"all","status":"all"],page:1)
        let requests = await t.captured()
        XCTAssertEqual(requests[0].0.absoluteString,"https://www.copy4000.com/comics?limit=50&offset=50&ordering=-datetime_updated&theme=COLOR&region=0&status=0")
        XCTAssertEqual(requests[1].0.query,"limit=50&offset=0&ordering=-datetime_updated")
        for filters in [["ordering":"bogus"],["region":"3"],["status":"-1"]] {
            await copyFails { _ = try await s.category(filters:filters,page:1) }
        }
    }
    func testCapturedFiltersAndDeduplication() async throws {
        let s = CopyMangaComicSource(transport:CopyTransport(body:try copyFixture("filters.html")))
        let groups = try await s.filterGroups()
        XCTAssertEqual(groups.map(\.key),["ordering","theme","region","status"])
        XCTAssertEqual(groups[0].options.map(\.value),["-datetime_updated","datetime_updated","-popular","popular"])
        XCTAssertEqual(groups[1].options.count,66)
        XCTAssertTrue(groups[1].options.contains { $0.value == "COLOR" })
        XCTAssertEqual(groups[2].options.map(\.value),["all","0","1","2"])
        let duplicate = CopyMangaComicSource(transport:CopyTransport(body:"<a href='/comics?theme=A'>冒险 (123)</a><a href='/comics?theme=A'>重复</a>"))
        let dedup = try await duplicate.filterGroups()
        XCTAssertEqual(dedup[1].options,[.init(label:"全部",value:"all"),.init(label:"冒险",value:"A")])
    }
    func testLiteralQuotesEscapesEntitiesAndTrailingCommas() async throws {
        let body = #"<div class="exemptComic-box" list="[{'path_word':'a','name':&quot;Don&#x27;t &amp; &#x4f60; \x21 \uD83D\uDE00&quot;,'flag':True,'nil':None,'false':False,'author':[{'name':'甲'},{'name':'乙'},],},]"></div>"#
        let cards = try await CopyMangaComicSource(transport:CopyTransport(body:body)).latest(page:1)
        XCTAssertEqual(cards[0].title,"Don't & 你 ! 😀"); XCTAssertEqual(cards[0].subtitle,"甲 / 乙")
        let escaped = #"<div class="exemptComic-box" list="[{'path_word':'b','name':'Don\'t \&quot;replace\&quot; &amp;quot; True None',},]"></div>"#
        let second = try await CopyMangaComicSource(transport:CopyTransport(body:escaped)).latest(page:1)
        XCTAssertEqual(second[0].title,#"Don't "replace" &quot; True None"#)
    }
    func testLiteralRejectsExpressionsNumbersAndExcessDepth() async {
        for literal in ["[alert('x')]","[]; document.cookie","['unterminated]","[{1:2}]","[1e999]","[01]","[+1]","['\\q']",String(repeating:"[",count:66)+"0"+String(repeating:"]",count:66)] {
            let embedded = "[{'path_word':'a','name':'A','extra':\(literal)}]"
            let escaped = embedded.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"\"",with:"&quot;")
            let s = CopyMangaComicSource(transport:CopyTransport(body:"<div class=\"exemptComic-box\" list=\"\(escaped)\"></div>"))
            await copyFails { _ = try await s.latest(page:1) }
        }
    }
    func testEmptyListsDedupAndMalformedSearch() async throws {
        let empty = CopyMangaComicSource(transport:CopyTransport(body:#"{"code":200,"results":{"list":[]}}"#))
        let cards = try await empty.search(keyword:"a",page:1); XCTAssertEqual(cards,[])
        let category = CopyMangaComicSource(transport:CopyTransport(body:"<div class='exemptComic-box' list='[]'></div>"))
        let categories = try await category.latest(page:1); XCTAssertEqual(categories,[])
        let duplicate = CopyMangaComicSource(transport:CopyTransport(body:#"{"code":200,"results":{"list":[{"path_word":"a","name":"A"},{"path_word":"a","name":"B"}]}}"#))
        let unique = try await duplicate.search(keyword:"a",page:1); XCTAssertEqual(unique.map(\.title),["A"])
        for body in ["<html>error</html>",#"{"code":403}"#,#"{"code":200,"results":null}"#,#"{"code":200,"results":{"list":[{}]}}"#] {
            await copyFails { _ = try await CopyMangaComicSource(transport:CopyTransport(body:body)).search(keyword:"a",page:1) }
        }
    }
    func testDetailKeepsDirectoryLazy() async throws {
        let html = "<title>测试漫画-测试漫畫-第192話-已完結</title><div class='comicParticulars-left-img'><img data-src='/cover.jpg'></div><div class='comicParticulars-title-right'><div><h6>测试漫画</h6></div><ul><li><span>狀態：</span><span>已完結</span></li><li><a href='/author/a/comics'>作者A</a><a href='/author/b/comics'>作者B</a></li><li><a href='/comics?theme=rexue'>#热血</a></li></ul></div><p class='intro'>简介&lt;文字&gt; &amp; 其他</p>"
        let t = CopyTransport(body:html), s = CopyMangaComicSource(transport:t)
        let d = try await s.detail(comicId:"copy4000:sample")
        XCTAssertEqual(d.summary.title,"测试漫画"); XCTAssertEqual(d.summary.coverUrl,"https://www.copy4000.com/cover.jpg")
        XCTAssertEqual(d.author,"作者A / 作者B"); XCTAssertEqual(d.status,"已完結")
        XCTAssertEqual(d.description,"简介<文字> & 其他"); XCTAssertEqual(d.latestChapter,"第192話")
        XCTAssertEqual(d.summary.tags,["热血"]); XCTAssertEqual(d.chapters,[])
        let requests = await t.captured(); XCTAssertEqual(requests.count,1)
        await copyFails { _ = try await CopyMangaComicSource(transport:CopyTransport(body:"<h6>Wrong structure</h6>")).detail(comicId:"a") }
    }
    func testCapturedDirectoryIgnoresCountAndReads190() async throws {
        let t = CopyTransport { url,_ in copyResponse(try copyFixture(url.path.contains("comic2") ? "api-detail.json" : url.query!.contains("offset=100") ? "api-chapters-page2.json" : "api-chapters-page1.json")) }
        let result = try await CopyMangaComicSource(transport:t).chapters(comicId:"copy4000:"+copySlug)
        XCTAssertEqual(result.count,190); XCTAssertEqual(result.first?.chapterId,copyChapter)
        XCTAssertEqual(result.last?.title,"第192話"); XCTAssertEqual(result.last?.chapterSlot,189)
        XCTAssertEqual(result.first?.url,"https://www.copy4000.com/comic/\(copySlug)/chapter/\(copyChapter)")
        let requests = await t.captured(); XCTAssertEqual(requests.count,3)
        XCTAssertEqual(requests[0].0.absoluteString,"https://api.manga2026.xyz/api/v3/comic2/\(copySlug)?platform=3")
        XCTAssertEqual(requests[2].0.query,"limit=100&offset=100")
    }
    func testGroupsKeepWireOrderIncludingZeroCountAndCrossGroupDedup() async throws {
        let t = CopyTransport { url,_ in
            if url.path.contains("comic2") { return copyResponse(#"{"code":200,"results":{"comic":{"path_word":"a"},"groups":{"z":{"count":0},"a":{"path_word":"extra","count":0}}}}"#) }
            let group = url.path.contains("/z/") ? "z" : "extra"
            let entries: [[String:Any]] = group == "z" ? [["uuid":"same","name":"Z","comic_path_word":"a","group_path_word":group]] : [["uuid":"same","name":"duplicate","comic_path_word":"a","group_path_word":group],["uuid":"extra","name":"Extra","comic_path_word":"a","group_path_word":group]]
            return copyResponse(try copyJSON(["code":200,"results":["offset":0,"total":entries.count,"list":entries]]))
        }
        let result = try await CopyMangaComicSource(transport:t).chapters(comicId:"a")
        XCTAssertEqual(result.map(\.title),["Z","Extra"]); XCTAssertEqual(result.map(\.sectionSlot),[0,1]); XCTAssertEqual(result.map(\.chapterSlot),[0,1])
    }
    func testDirectoryRejectsMissingPartialRepeatedAndMismatchedPages() async throws {
        var bad = [#"{"code":200,"results":null}"#]
        bad.append(try copyMutate("api-chapters-page2.json") { $0["list"] = [] })
        bad.append(try copyMutate("api-chapters-page1.json") { $0["offset"] = 100 })
        bad.append(try copyMutate("api-chapters-page2.json") { $0["offset"] = 0 })
        bad.append(try copyMutate("api-chapters-page2.json") { $0["total"] = -1 })
        bad.append(try copyMutate("api-chapters-page2.json") { $0.removeValue(forKey:"list") })
        for field in ["comic_path_word","group_path_word","uuid","name"] {
            bad.append(try copyMutate("api-chapters-page2.json") { data in
                var list = data["list"] as! [[String:Any]]; list[0][field] = ""; data["list"] = list
            })
        }
        for body in bad {
            let t = CopyTransport { url,_ in copyResponse(try url.path.contains("comic2") ? copyFixture("api-detail.json") : url.query!.contains("offset=100") ? body : copyFixture("api-chapters-page1.json")) }
            await copyFails { _ = try await CopyMangaComicSource(transport:t).chapters(comicId:copySlug) }
        }
    }
    func testReaderPreservesAll86ImagesAndCanonicalURLAndAPIHeaders() async throws {
        let body = try copyFixture("api-reader.json"), t = CopyTransport(body:body)
        let page = try await CopyMangaComicSource(transport:t).chapter(url:copyURL+"?ignored=1#saved")
        let root = try JSONSerialization.jsonObject(with:Data(body.utf8)) as! [String:Any]
        let chapter = (root["results"] as! [String:Any])["chapter"] as! [String:Any]
        XCTAssertEqual(page.imageUrls,(chapter["contents"] as! [[String:Any]]).map { $0["url"] as! String })
        XCTAssertEqual(page.imageUrls.count,86); XCTAssertEqual(page.nextPageUrl,"")
        XCTAssertEqual(page.chapterId,"https://www.copy4000.com/comic/\(copySlug)/chapter/\(copyChapter)")
        let requests = await t.captured()
        XCTAssertEqual(requests[0].0.absoluteString,"https://api.manga2026.xyz/api/v3/comic/\(copySlug)/chapter/\(copyChapter)?platform=3")
        for (key,value) in ["User-Agent":"COPY/3.0.9","Accept":"application/json","platform":"3","version":"3.0.9","region":"1","webp":"1","Referer":"https://www.copy4000.com/"] { XCTAssertEqual(requests[0].1[key],value) }
        XCTAssertNil(requests[0].1["dnts"])
    }
    func testReaderRejectsLockedNullWrongIdentitySizeAndImageURLs() async throws {
        var bad = [#"{"code":200,"results":null}"#]
        for mutation in ["lock","comic","uuid","owner","size","empty","image"] {
            bad.append(try copyMutate("api-reader.json") { data in
                var chapter = data["chapter"] as! [String:Any]
                switch mutation {
                case "lock": data["is_lock"] = true
                case "comic": data["comic"] = ["path_word":"wrong"]
                case "uuid": chapter["uuid"] = "wrong"
                case "owner": chapter["comic_path_word"] = "wrong"
                case "size": chapter["size"] = 999
                case "empty": chapter["contents"] = []; chapter["size"] = 0
                default: var contents = chapter["contents"] as! [[String:Any]]; contents[0]["url"] = "javascript:alert(1)"; chapter["contents"] = contents
                }
                data["chapter"] = chapter
            })
        }
        for body in bad { await copyFails { _ = try await CopyMangaComicSource(transport:CopyTransport(body:body)).chapter(url:copyURL) } }
    }
    func testBooleanAndStringLockFlagsRejectWithoutFallbackAndFalseRemainsReadable() async throws {
        for flag: Any in [true, "true", "TRUE", "TrUe"] {
            let body = try copyMutate("api-reader.json") { $0["is_lock"] = flag }
            let transport = CopyTransport(body:body)
            do {
                _ = try await CopyMangaComicSource(transport:transport).chapter(url:copyURL)
                XCTFail("Locked content must be rejected for flag \(flag)")
            } catch { XCTAssertTrue(error.localizedDescription.contains("当前内容不可访问")) }
            let calls = await transport.captured()
            XCTAssertEqual(calls.count,1,"Locked content must not trigger fallback")
        }
        for flag: Any in [false, "false", "FALSE"] {
            let body = try copyMutate("api-reader.json") { $0["is_lock"] = flag }
            let transport = CopyTransport(body:body)
            let page = try await CopyMangaComicSource(transport:transport).chapter(url:copyURL)
            XCTAssertEqual(page.imageUrls.count,86)
            let calls = await transport.captured(); XCTAssertEqual(calls.count,1)
        }
    }
    func testConnectionFallbackRemembersAndRecoversAfterNetworkChange() async throws {
        let body = try copyFixture("api-reader.json")
        let t = CopyTransport { url,n in
            if n == 1 || n == 3 { throw URLError(.networkConnectionLost) }
            return copyResponse(body)
        }
        let s = CopyMangaComicSource(transport:t)
        for _ in 0..<3 { _ = try await s.chapter(url:copyURL) }
        let requests = await t.captured()
        XCTAssertEqual(requests.map { $0.0.host! },["api.manga2026.xyz","mapi.elfgjfghkk.club","mapi.elfgjfghkk.club","api.manga2026.xyz","api.manga2026.xyz"])
        XCTAssertTrue(requests.allSatisfy { $0.0.path == "/api/v3/comic/\(copySlug)/chapter/\(copyChapter)" && $0.0.query == "platform=3" })
    }
    func testAllConnectionFailuresAreBoundedAndReportHosts() async {
        let t = CopyTransport { _,n in throw URLError(n == 1 ? .cannotFindHost : n == 2 ? .cannotConnectToHost : .timedOut) }
        do { _ = try await CopyMangaComicSource(transport:t).chapter(url:copyURL); XCTFail("Must fail") }
        catch { for host in ["api.manga2026.xyz","mapi.elfgjfghkk.club","mapi.fgjfghkkcenter.club"] { XCTAssertTrue(error.localizedDescription.contains(host)) } }
        let requests = await t.captured(); XCTAssertEqual(requests.count,3)
    }
    func testHTTPJSONLockCertificateAndCancellationNeverFailOver() async throws {
        for body in ["<html>blocked</html>",#"{"code":403}"#,#"{"code":200,"results":null}"#,#"{"code":200,"results":{"is_lock":true}}"#] {
            let t = CopyTransport(body:body)
            await copyFails { _ = try await CopyMangaComicSource(transport:t).chapter(url:copyURL) }
            let calls = await t.captured(); XCTAssertEqual(calls.count,1)
        }
        for code in [URLError.Code.cancelled,.serverCertificateUntrusted,.serverCertificateHasBadDate,.serverCertificateHasUnknownRoot,.serverCertificateNotYetValid,.clientCertificateRejected,.secureConnectionFailed] {
            let t = CopyTransport { _,_ in throw URLError(code) }
            await copyFails { _ = try await CopyMangaComicSource(transport:t).chapter(url:copyURL) }
            let calls = await t.captured(); XCTAssertEqual(calls.count,1)
        }
        let http = CopyTransport(body:"oops",status:429)
        await copyFails { _ = try await CopyMangaComicSource(transport:http).chapter(url:copyURL) }
        let calls = await http.captured(); XCTAssertEqual(calls.count,1)
    }
    func testCustomOriginNeverUsesBuiltinFallbacksAndExplicitListIsBounded() async throws {
        let t = CopyTransport { _,_ in throw URLError(.cannotConnectToHost) }
        await copyFails { _ = try await CopyMangaComicSource(transport:t,apiOrigin:"https://custom.example").chapter(url:copyURL) }
        let calls = await t.captured(); XCTAssertEqual(calls.map { $0.0.host! },["custom.example"])
        let explicit = CopyTransport { _,_ in throw URLError(.timedOut) }
        await copyFails { _ = try await CopyMangaComicSource(transport:explicit,apiFallbackOrigins:["https://a.test","https://b.test","https://c.test"]).chapter(url:copyURL) }
        let bounded = await explicit.captured(); XCTAssertEqual(bounded.map { $0.0.host! },["api.manga2026.xyz","a.test","b.test"])
    }
    func testWrappedCertificateAndCancellationCannotTriggerFallback() async {
        for underlying in [URLError.Code.serverCertificateUntrusted,.cancelled] {
            let t = CopyTransport { _,_ in
                throw NSError(domain:NSURLErrorDomain,code:URLError.networkConnectionLost.rawValue,userInfo:[NSUnderlyingErrorKey:URLError(underlying)])
            }
            await copyFails { _ = try await CopyMangaComicSource(transport:t).chapter(url:copyURL) }
            let calls = await t.captured(); XCTAssertEqual(calls.count,1)
        }
    }
    func testChapterURLDecodesOnceAndRebasesSavedDomain() async throws {
        let body = #"{"code":200,"results":{"comic":{"path_word":"a b"},"chapter":{"uuid":"b+1","comic_path_word":"a b","name":"Test","size":1,"contents":[{"url":"https://img.test/a.jpg"}]}}}"#
        let t = CopyTransport(body:body)
        let s = CopyMangaComicSource(transport:t,baseURL:"https://mirror.test/")
        let page = try await s.chapter(url:"https://old.example/comic/a%20b/chapter/b%2B1?old=1")
        XCTAssertEqual(page.chapterId,"https://mirror.test/comic/a%20b/chapter/b%2B1")
        let calls = await t.captured()
        XCTAssertEqual(calls[0].0.absoluteString,"https://api.manga2026.xyz/api/v3/comic/a%20b/chapter/b%2B1?platform=3")
        XCTAssertEqual(calls[0].1["Referer"],"https://mirror.test/")
        for bad in ["https://old.example/nope","/comic/a%ZZ/chapter/b","/comic/a%2Fb/chapter/b","/comic/a/chapter/b%ZZ"] {
            await copyFails { _ = try await s.chapter(url:bad) }
        }
        let after = await t.captured(); XCTAssertEqual(after.count,1)
    }
    func testFallbackCanBeDisabledAndInvalidFallbackRejectedBeforeNetwork() async {
        let disabled = CopyTransport { _,_ in throw URLError(.cannotFindHost) }
        await copyFails { _ = try await CopyMangaComicSource(transport:disabled,apiFallbackOrigins:[]).chapter(url:copyURL) }
        let calls = await disabled.captured(); XCTAssertEqual(calls.count,1)
        for invalid in ["http://a.test","https://user@a.test","https://a.test/path","https://a.test?q=1","https://a.test#fragment"] {
            let t = CopyTransport(body:"bad")
            await copyFails { _ = try await CopyMangaComicSource(transport:t,apiFallbackOrigins:[invalid]).chapter(url:copyURL) }
            let calls = await t.captured(); XCTAssertEqual(calls.count,0)
        }
    }
    func testDirectoryStopsAfter1000IncompletePages() async throws {
        let t = CopyTransport { url,n in
            if n == 1 { return copyResponse(#"{"code":200,"results":{"comic":{"path_word":"a"},"groups":{"default":{}}}}"#) }
            let offset = n-2
            return copyResponse("{\"code\":200,\"results\":{\"offset\":\(offset),\"total\":1001,\"list\":[{\"uuid\":\"\(offset)\",\"name\":\"Chapter\",\"comic_path_word\":\"a\",\"group_path_word\":\"default\"}]}}")
        }
        do { _ = try await CopyMangaComicSource(transport:t).chapters(comicId:"a"); XCTFail("Must reject incomplete directory") }
        catch { XCTAssertTrue(error.localizedDescription.contains("页数超出限制")) }
        let calls = await t.captured(); XCTAssertEqual(calls.count,1001)
    }
    func testPreCancelledTaskDoesNotConnect() async {
        let t = CopyTransport(body:"bad"), s = CopyMangaComicSource(transport:t)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await s.chapter(url:copyURL)
        }
        do { _ = try await task.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await t.captured(); XCTAssertEqual(calls.count,0)
    }
    func testOversizeAndInvalidUTF8NeverFailOver() async {
        for data in [Data(repeating:65,count:16*1024*1024+1),Data([0xFF,0xFF])] {
            let t = CopyTransport { _,_ in HTTPResponse(data:data,statusCode:200) }
            await copyFails { _ = try await CopyMangaComicSource(transport:t).chapter(url:copyURL) }
            let calls = await t.captured(); XCTAssertEqual(calls.count,1)
        }
    }
}
