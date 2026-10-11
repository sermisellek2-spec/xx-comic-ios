import Foundation
import XCTest
@testable import ComicCore

private actor GuiTransport: HTTPTransport {
    var requests: [(URL,[String:String])] = []
    let response: @Sendable (Int) -> HTTPResponse
    init(_ body: String) { response = { _ in .init(data:Data(body.utf8),statusCode:200) } }
    init(response: @escaping @Sendable (Int) -> HTTPResponse) { self.response = response }
    func get(_ url: URL, headers: [String:String]) async throws -> HTTPResponse {
        requests.append((url,headers)); return response(requests.count)
    }
    func captured() -> [(URL,[String:String])] { requests }
}

final class ManhuaguiTests: XCTestCase {
    private let cards = #"<a class="bcover" href="/comic/60397/" title="comic a"><img src="//cf.mhgui.com/cpic/b/60397.jpg"></a><a href="/comic/60398/" title="comic b" class="bcover"><img data-original="//cf.mhgui.com/cpic/b/60398.jpg"></a><a href="/comic/60399/" class="bcover"><img alt="comic c" data-src="//cf.mhgui.com/cpic/b/60399.jpg"></a>"#
    private func page(_ body: String) async throws -> ChapterPage {
        try await ManhuaguiComicSource(transport:GuiTransport(body)).chapter(url:"/comic/67890/111.html")
    }
    func testImportedNameBaseRefererAndRoutesReachActualRequestConsumers() async throws {
        let suite = "gui-config-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs)
        _ = try preferences.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"manhuagui","name":"本机漫画柜","baseUrl":"https://fixture.invalid","referer":"https://fixture.invalid/ref/","routes":{"search":"/lookup?q={keyword}","category":"/browse/{obsolete}/","detail":"/book/{comicId}/"}}]}"#)
        let body = cards + "<div class='filter area'><a href='/list/japan'>日本</a></div><h1>作品</h1><a href='/comic/42/11.html'>第1话</a>"
        let transport = GuiTransport(body), source = ManhuaguiComicSource(config: try XCTUnwrap(preferences.config(for: "manhuagui")), transport: transport)
        XCTAssertEqual(source.name, "本机漫画柜")
        _ = try await source.search(keyword: " 标题 ", page: 1)
        _ = try await source.latest(page: 2)
        _ = try await source.category(filters: ["region": "japan", "state": "wanjie"], page: 3)
        _ = try await source.filterGroups()
        _ = try await source.detail(comicId: "manhuagui:42")
        _ = try await source.chapters(comicId: "manhuagui:42")
        let calls = await transport.captured()
        XCTAssertEqual(calls.map { $0.0.host }, Array(repeating: "fixture.invalid", count: 6))
        XCTAssertEqual(calls.map { $0.0.path }, ["/lookup", "/browse/index_p2.html", "/browse/japan-wanjie/index_p3.html", "/browse", "/book/42", "/book/42"])
        XCTAssertEqual(URLComponents(url: calls[0].0, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "标题")
        XCTAssertTrue(calls.allSatisfy { $0.1["Referer"] == "https://fixture.invalid/ref/" })
    }
    func testCardsPathsHeadersAndSearchPagination() async throws {
        let t = GuiTransport(cards+cards), s = ManhuaguiComicSource(transport:t)
        let result = try await s.latest(page:1)
        XCTAssertEqual(result.map(\.comicId),["manhuagui:60397","manhuagui:60398","manhuagui:60399"])
        XCTAssertEqual(result.map(\.title),["comic a","comic b","comic c"])
        XCTAssertEqual(result[1].coverUrl,"https://cf.mhgui.com/cpic/b/60398.jpg")
        _ = try await s.category(filters:["state":"wanjie","letter":"a","year":"2026","audience":"shaonian","genre":"rexue","region":"japan"],page:3)
        _ = try await s.search(keyword:" 中 文+~* ",page:1)
        let empty = try await s.search(keyword:"x",page:2); XCTAssertEqual(empty,[])
        let calls = await t.captured()
        XCTAssertEqual(calls.map { $0.0.absoluteString },["https://www.manhuagui.com/list","https://www.manhuagui.com/list/japan-rexue-shaonian-2026-a-wanjie/index_p3.html","https://www.manhuagui.com/s/%E4%B8%AD+%E6%96%87%2B%7E*.html"])
        for (key,value) in ["Referer":"https://www.manhuagui.com/","Accept-Language":"zh-CN,zh;q=0.9","Accept-Encoding":"gzip","Upgrade-Insecure-Requests":"1","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","sec-ch-ua-mobile":"?0","sec-ch-ua-platform":"\"Windows\""] { XCTAssertEqual(calls[0].1[key],value) }
        XCTAssertTrue(calls[0].1["User-Agent"]!.contains("Chrome/150.0.0.0"))
        do { _ = try await ManhuaguiComicSource(transport:GuiTransport("<html></html>")).latest(page:1); XCTFail("Empty cards must fail") } catch {}
    }
    func testFiltersAndDetailCoverAndLazyDirectory() async throws {
        let html = zip(["area","genre","age","year","letter","status"],["japan","rexue","shaonian","2026","a","wanjie"]).map { "<div class='filter \($0)'><a href='/list'>全部</a><a href='/list/\($1)/'>\($1)</a></div>" }.joined()
        let groups = try await ManhuaguiComicSource(transport:GuiTransport(html)).filterGroups()
        XCTAssertEqual(groups.map(\.key),["region","genre","audience","year","letter","state"])
        XCTAssertEqual(groups.map(\.label),["地区","剧情","受众","年份","字母","状态"])
        XCTAssertEqual(groups[0].options.map(\.value),["all","japan"])
        for (cover,want) in [("<meta property='og:image' content='//img.test/og.jpg'>","https://img.test/og.jpg"),("<a class='bcover'><img data-src='/a.jpg' src='/wrong.jpg'></a>","https://www.manhuagui.com/a.jpg"),("<div class='book-cover'><img data-original='//cf.mhgui.com/cpic/b/12345.jpg'></div>","https://cf.mhgui.com/cpic/b/12345.jpg"),("","https://cf.mhgui.com/cpic/b/67890.jpg")] {
            let t = GuiTransport("<h1>标题 &amp; 测试</h1>"+cover+"漫画作者：</strong><a>作者</a>漫画状态:</strong><span>连载</span><div id='intro-cut'>简介</div>更新至 [<a>第二回</a>]<a href='/comic/67890/111.html'>chapter</a>")
            let detail = try await ManhuaguiComicSource(transport:t).detail(comicId:"manhuagui:67890")
            XCTAssertEqual(detail.summary.coverUrl,want); XCTAssertEqual(detail.summary.title,"标题 & 测试")
            XCTAssertEqual(detail.author,"作者"); XCTAssertEqual(detail.status,"连载"); XCTAssertEqual(detail.description,"简介"); XCTAssertEqual(detail.latestChapter,"第二回"); XCTAssertEqual(detail.chapters,[])
            let calls = await t.captured(); XCTAssertEqual(calls.count,1); XCTAssertEqual(calls[0].0.path,"/comic/67890")
        }
    }
    func testDirectoryOwnershipDedupTitleAndInt32Fallback() async throws {
        let html = #"<div class="links"><a href="/comic/67890/112.html">chapter 2</a></div><ul class="chapter-list-1"><li><a href="/comic/67890/111.html" title="chapter 1"></a></li></ul><a href='/comic/123/1.html'>wrong</a><a href='/comic/67890/111.html'>dup</a><a href='/comic/67890/2147483648.html'>overflow</a>"#
        let chapters = try await ManhuaguiComicSource(transport:GuiTransport(html)).chapters(comicId:"67890")
        XCTAssertEqual(chapters.map(\.chapterId),["2147483648","111","112"])
        XCTAssertEqual(chapters.map(\.chapterSlot),[2,111,112]); XCTAssertEqual(chapters[1].title,"chapter 1")
    }
    func testDirectLooseBracketsAndInvalidTokenSkip() async throws {
        for marker in ["SMH.imgData","SMH[\"imgData\"]","SMH['imgData']"] {
            let result = try await page("SMH.imgData({\"K\":f,\"J\":\"r r w\",\"X\":[\"W 2 3\"]});"+marker+"({bid:1,path:\"/ps3/c/\",files:[\"003.jpg\",\"003.jpg\"],sl:{e:1784381031,m:abc123}})")
            XCTAssertEqual(result.imageUrls,["https://eu2.hamreus.com/ps3/c/003.jpg?e=1784381031&m=abc123"])
        }
        let direct = try await page(#"<h2>chapter &amp; one</h2>SMH.imgData({"bid":1,"path":"/ps3/a/","files":["001.jpg"],"sl":{"e":"x","m":"y"}}).preInit();"#)
        XCTAssertEqual(direct.title,"chapter & one"); XCTAssertEqual(direct.imageUrls,["https://eu2.hamreus.com/ps3/a/001.jpg?e=x&m=y"])
    }
    func testLooseModeDoesNotRewriteQuotedTextOrRelaxStrictDefault() throws {
        let input = #"{path:'/a/{key:word}/',files:['a.jpg'],sl:{e:123abc,m:token},label:'x,unquoted:value'}"#
        XCTAssertThrowsError(try parseCopyMangaLiteral(input))
        let parsed = try parseCopyMangaLiteral(input,loose:true)
        XCTAssertEqual(parsed["path"].string,"/a/{key:word}/"); XCTAssertEqual(parsed["sl"]["e"].string,"123abc")
        XCTAssertEqual(parsed["label"].string,"x,unquoted:value")
        for expression in ["{x:alert(1)}","{x:a.b}","{x:1+2}","{x:1e999}","{x:9999999999999999999999999}"] { XCTAssertThrowsError(try parseCopyMangaLiteral(expression,loose:true)) }
        for expression in ["{\"x\":word}","{\"x\":alert(1)}","{\"x\":1+2}"] { XCTAssertThrowsError(try parseCopyMangaLiteral(expression)) }
    }
    private func packed(_ payload: String, radix: String = "62", count: String = "0", dictionary: String = "", separator: String = "|") -> String {
        func quote(_ value: String) -> String { "\""+value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")+"\"" }
        return "(function(p,a,c,k,e,d){return p}(\(quote(payload)),\(radix),\(count),\(quote(dictionary)).split(\(quote(separator))),0,{}))"
    }
    func testNestedDoubleQuotedPackerAndSinglePassSparseDictionary() async throws {
        let config = #"SMH.imgData({bid:1,path:"/ps3/d/",files:["004.jpg"],sl:{e:"x",m:"y"}}).preInit();"#
        for body in [packed(config),packed(packed(config)),packed(packed(packed(packed(config))))] {
            let result = try await page(body)
            XCTAssertEqual(result.imageUrls,["https://eu2.hamreus.com/ps3/d/004.jpg?e=x&m=y"])
        }
        var dictionary = Array(repeating:"",count:198)
        for (index,value) in [(77,"path"),(78,"files"),(79,"sl"),(106,"imgData"),(197,"SMH")] { dictionary[index] = value }
        let sparse = packed(#"3b.1I({"1f":"/ps3/f/","1g":["006.jpg"],"1h":{"e":"x","m":"y"}}).preInit();"#,count:"2",dictionary:dictionary.joined(separator:"|"))
        let result = try await page(sparse); XCTAssertEqual(result.imageUrls,["https://eu2.hamreus.com/ps3/f/006.jpg?e=x&m=y"])
        let once = packed(#"0.1({"2":"/a/","3":["004.jpg"],sl:{e:"x",m:"y"}})"#,count:"4",dictionary:"SMH|imgData|path|files",separator:"")
        let fallback = try await page(once); XCTAssertEqual(fallback.imageUrls,["https://eu2.hamreus.com/a/004.jpg?e=x&m=y"])
    }
    func testShapeFallbackUsesInputOrderAndJavaPercentEncoding() async throws {
        let result = try await page(#"anything({z:"/中 文%20/~!*()/",a:"/wrong/",pictures:["one.jpg","two.png"],ignored:["wrong.jpg"],signature:{e:123,m:"x"}})"#)
        XCTAssertEqual(result.imageUrls,["https://eu2.hamreus.com/%E4%B8%AD%20%E6%96%87%2520/%7E%21*%28%29/one.jpg?e=123&m=x","https://eu2.hamreus.com/%E4%B8%AD%20%E6%96%87%2520/%7E%21*%28%29/two.png?e=123&m=x"])
        let defaultSignature = try await page(#"anything({z:"/a/",pictures:["one.jpg"]})"#)
        XCTAssertEqual(defaultSignature.imageUrls,["https://eu2.hamreus.com/a/one.jpg?e=&m="])
    }
    func testFullRecordedLZDictionaryProducesAll29Images() async throws {
        let result = try await page(guiLZPacked)
        XCTAssertEqual(result.imageUrls.count,29)
        XCTAssertEqual(result.imageUrls[2],"https://eu2.hamreus.com/ps3/23/09/49571/%E7%AC%AC1%E5%9B%9E%20%E8%8A%B1%E9%83%BD%E5%88%BA%E5%AE%A2%20%E5%85%B6%E4%B8%80/004.jpg.webp?e=1784381031&m=nA8eG8hox4OGHMC5cpvgTw")
        XCTAssertTrue(result.imageUrls.first!.contains("/001.jpg.webp?"))
        XCTAssertTrue(result.imageUrls.last!.contains("/030.jpg.webp?"))
    }
    func testMalformedPackedParametersDepthBudgetAndCancellationFail() async throws {
        let config = #"SMH.imgData({path:'/a/',files:['one.jpg'],sl:{}})"#
        for body in [packed(config,radix:"1"),packed(config,radix:"63"),packed(config,radix:"999999999999999999999"),packed(config,count:"9999999999999999999"),packed(config,count:"262145"),packed(packed(packed(packed(packed(config))))),packed("0",count:"100",dictionary:String(guiLZDictionary.prefix(40))),String(repeating:"x",count:32*1024*1024+1),packed(String(repeating:"0 ",count:10000),count:"2",dictionary:String(repeating:"a",count:4000)+"|b")] {
            do { _ = try ManhuaguiReader.images(body); XCTFail("Malformed/oversize packed input must fail") } catch {}
        }
        let t = GuiTransport(config), source = ManhuaguiComicSource(transport:t)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await source.chapter(url:"/comic/1/2.html") }
        do { _ = try await task.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await t.captured(); XCTAssertEqual(calls.count,0)
    }
    func testRedirectsUpgradeMainDomainAndStopAfterFive() async throws {
        let body = cards
        let t = GuiTransport(response:{ n in n == 1 ? .init(data:Data(),statusCode:302,headers:["lOcAtIoN":"http://www.manhuagui.com/list/index_p2.html"]) : .init(data:Data(body.utf8),statusCode:200) })
        _ = try await ManhuaguiComicSource(transport:t).latest(page:1)
        let calls = await t.captured(); XCTAssertEqual(calls[1].0.absoluteString,"https://www.manhuagui.com/list/index_p2.html")
        let loop = GuiTransport(response:{ _ in .init(data:Data(),statusCode:302,headers:["Location":"/list"]) })
        do { _ = try await ManhuaguiComicSource(transport:loop).latest(page:1); XCTFail("Redirect loop must stop") } catch {}
        let bounded = await loop.captured(); XCTAssertEqual(bounded.count,6)
    }
    func testOrdinaryHTMLQuotesDoNotHideReaderConfiguration() async throws {
        let result = try await page(#"<h2>Don't stop</h2><script>SMH.imgData({path:'/a/',files:['one.jpg'],sl:{}})</script>"#)
        XCTAssertEqual(result.imageUrls,["https://eu2.hamreus.com/a/one.jpg?e=&m="])
    }
    func testPrecedingJavaScriptStringCannotPolluteObjectBoundary() async throws {
        let result = try await page(#"<script>var label = "{don't"; SMH.imgData({path:"/a/",files:["one.jpg"],sl:{}})</script>"#)
        XCTAssertEqual(result.imageUrls,["https://eu2.hamreus.com/a/one.jpg?e=&m="])
    }
    func testRepeatedInvalidMarkersExhaustSharedScanBudget() throws {
        for marker in ["function(p,a,c,k,e,d)","SMH.imgData"] {
            do { _ = try ManhuaguiReader.images(String(repeating:marker,count:6000)); XCTFail("Missing targets must not permit unbounded suffix scans") }
            catch { XCTAssertTrue(error.localizedDescription.contains("扫描预算"),error.localizedDescription) }
        }
    }
    func testRepeatedInvalidMarkerScanCanBeCancelled() async throws {
        let input = String(repeating:"function(p,a,c,k,e,d)",count:6000)
        let task = Task.detached { try ManhuaguiReader.images(input) }
        try await Task.sleep(nanoseconds:100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel candidate scanning") }
        catch { XCTAssertTrue(error is CancellationError,error.localizedDescription) }
    }
    func testCleanedEmptyCardAndChapterTitlesFallBack() async throws {
        for title in ["   ","&lt;b&gt;&lt;/b&gt;"] {
            let card = "<a class='bcover' href='/comic/1/' title='"+title+"'><img alt='有效标题' src='/a.jpg'></a>"
            let cards = try await ManhuaguiComicSource(transport:GuiTransport(card)).latest(page:1)
            XCTAssertEqual(cards.map(\.title),["有效标题"])
            let directory = "<a href='/comic/1/111.html' title='"+title+"'><span>有效章节</span></a>"
            let chapters = try await ManhuaguiComicSource(transport:GuiTransport(directory)).chapters(comicId:"1")
            XCTAssertEqual(chapters.map(\.title),["有效章节"])
        }
    }
    func testSearchTrimsOnlyJavaControlAndASCIISpaces() async throws {
        let t = GuiTransport(cards)
        _ = try await ManhuaguiComicSource(transport:t).search(keyword:" \t\u{00A0}书\u{3000}\n ",page:1)
        let calls = await t.captured()
        XCTAssertEqual(calls[0].0.absoluteString,"https://www.manhuagui.com/s/%C2%A0%E4%B9%A6%E3%80%80.html")
    }
    func testCoverURLCleanupAndImageAttributePriority() async throws {
        let html = #"<a class='bcover' href='/comic/1/' title='Title'><img alt='wrong' data-src='/right.jpg&quot; ignored' data-original='/wrong.jpg' src='/wrong2.jpg'></a>"#
        let source = ManhuaguiComicSource(transport:GuiTransport(html))
        let result = try await source.latest(page:1)
        XCTAssertEqual(result[0].title,"Title"); XCTAssertEqual(result[0].coverUrl,"https://www.manhuagui.com/right.jpg")
        let detail = try await ManhuaguiComicSource(transport:GuiTransport("<h1>x</h1><meta property='og:image' content='/cover.jpg ignored'>")).detail(comicId:"1")
        XCTAssertEqual(detail.summary.coverUrl,"https://www.manhuagui.com/cover.jpg")
    }
    func testChapterRequestKeepsCanonicalPathAndNavigationHeaders() async throws {
        let t = GuiTransport(#"SMH.imgData({path:'/a/',files:['one.jpg'],sl:{}})"#)
        let result = try await ManhuaguiComicSource(transport:t,baseURL:"https://mirror.test/").chapter(url:"/comic/67890/111.html")
        XCTAssertEqual(result.chapterId,"https://mirror.test/comic/67890/111.html"); XCTAssertEqual(result.nextPageUrl,"")
        let calls = await t.captured()
        XCTAssertEqual(calls[0].0.absoluteString,result.chapterId)
        XCTAssertEqual(calls[0].1["Referer"],"https://mirror.test/")
        XCTAssertEqual(calls[0].1["Accept"],"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7")
        XCTAssertEqual(calls[0].1["sec-ch-ua"],"\"Not;A=Brand\";v=\"8\", \"Chromium\";v=\"150\", \"Google Chrome\";v=\"150\"")
    }
    func testValidImageListExpansionIsBoundedBeforePublishing() throws {
        let files = (0..<1000).map { "'\($0).jpg'" }.joined(separator:",")
        let body = "SMH.imgData({path:'/"+String(repeating:"a",count:40000)+"/',files:["+files+"],sl:{}})"
        do { _ = try ManhuaguiReader.images(body); XCTFail("A valid but oversized URL list must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("32MiB")) }
    }
    func testPackerSelectionSinglePassAndRawSeparatorPriority() async throws {
        let payload = #"0.1({"2":"/4/","3":["one.jpg"],sl:{}})"#
        for (separator,count) in [("|","5"),("","999")] {
            let result = try await page(packed(payload,count:count,dictionary:"SMH|imgData|path|files|0",separator:separator))
            XCTAssertEqual(result.imageUrls,["https://eu2.hamreus.com/0/one.jpg?e=&m="])
        }
        let config = #"SMH.imgData({path:'/preferred/',files:['one.jpg'],sl:{}})"#
        let body = #"SMH.imgData({path:'/wrong/',files:['one.jpg'],sl:{}});"# + packed(config,count:"2",dictionary:"first|second,third,fourth")
        let result = try await page(body); XCTAssertEqual(result.imageUrls,["https://eu2.hamreus.com/preferred/one.jpg?e=&m="])
    }
    func testReaderRejectsPartialBadURLsAndPreservesEscapedData() async throws {
        for files in ["['good.jpg','bad file.jpg']","['good.jpg','bad%ZZ.jpg']","[]"] {
            do { _ = try await page("SMH.imgData({path:'/a/',files:"+files+",sl:{}})"); XCTFail("Must reject incomplete image list") } catch {}
        }
        let escaped = try await page(packed(#"SMH.imgData({path:'/a/\u4e2d/\x25/',files:['one.jpg'],sl:{e:'x',m:'a\'b'}})"#))
        XCTAssertEqual(escaped.imageUrls,["https://eu2.hamreus.com/a/%E4%B8%AD/%25/one.jpg?e=x&m=a'b"])
    }
    func testActualDictionaryAndValidPayloadExpansionBudgets() throws {
        let config = #"SMH.imgData({path:'/a/',files:['one.jpg'],sl:{}})"#
        do {
            _ = try ManhuaguiReader.images(packed(config,count:"2",dictionary:String(repeating:"|",count:262144)))
            XCTFail("Actual dictionary entries, not just declared count, must be bounded")
        } catch { XCTAssertTrue(error.localizedDescription.contains("字典条目")) }
        let payload = "SMH.imgData({path:'/"+String(repeating:"0 ",count:10000)+"/',files:['one.jpg'],sl:{}})"
        do {
            _ = try ManhuaguiReader.images(packed(payload,count:"2",dictionary:String(repeating:"a",count:4000)+"|b"))
            XCTFail("A valid expanded image configuration must be bounded")
        } catch { XCTAssertTrue(error.localizedDescription.contains("展开超过32MiB")) }
    }
    func testLegacyInvocationFallbackWithoutFunctionMarker() async throws {
        let body = #"('SMH.imgData({path:"/legacy/",files:["one.jpg"],sl:{}})',62,0,''.split('|'),0,{})"#
        let result = try await page(body)
        XCTAssertEqual(result.imageUrls,["https://eu2.hamreus.com/legacy/one.jpg?e=&m="])
    }
    func testSourceConfigDefaultsAndConfiguredSource() async throws {
        let def = SourceConfigDefaults.manhuagui()
        XCTAssertEqual(def.id, "manhuagui")
        XCTAssertEqual(def.name, "漫画柜")
        XCTAssertEqual(def.domain, "www.manhuagui.com")
        XCTAssertEqual(def.baseUrl, "https://www.manhuagui.com")
        XCTAssertEqual(def.referer, "https://www.manhuagui.com/")
        XCTAssertEqual(def.route("latest"), "/list")
        XCTAssertEqual(def.route("search"), "/s/{keyword}.html")
        XCTAssertEqual(def.filter("region.jp"), "japan")
        XCTAssertEqual(SourceConfigDefaults.defaultConfig(for: "manhuagui")?.id, "manhuagui")

        let custom = SourceConfigItem(
            id: "manhuagui",
            name: "漫画柜镜像",
            domain: "mirror.manhuagui.com",
            baseUrl: "https://mirror.manhuagui.com",
            referer: "https://mirror.manhuagui.com/",
            latestPath: "/list",
            searchPath: "/s/{keyword}.html",
            categoryPath: "/list",
            detailPath: "/comic/{comicId}",
            enabled: true,
            routes: ["latest": "/list"],
            filters: [:]
        )
        let t = GuiTransport(cards)
        let customSource = ManhuaguiComicSource(config: custom, transport: t)
        XCTAssertEqual(customSource.referer, "https://mirror.manhuagui.com/")
        _ = try await customSource.latest(page: 1)
        let calls = await t.captured()
        XCTAssertEqual(calls[0].0.absoluteString, "https://mirror.manhuagui.com/list")
        XCTAssertEqual(calls[0].1["Referer"], "https://mirror.manhuagui.com/")
    }
    func testLiveChapter61808UnpackYields33Images() async throws {
        let packed = #"(function(p,a,c,k,e,d){return p}('R.h({"D":c,"C":"B\uFF0CA","z":"c.a","y":x,"w":"g","v":["1.a.b","2.a.b","3.a.b","4.a.b","5.a.b","6.a.b","7.a.b","8.a.b","9.a.b","10.a.b","11.a.b","12.a.b","u.a.b","t.a.b","s.a.b","q.a.b","p.a.b","o.a.b","n.a.b","l.a.b","k.a.b","j.a.b","i.a.b","G.a.b","E.a.b","f.a.b","F.a.b","O.a.b","H.a.b","T.a.b","U.a.b","W.a.b","d.a.b"],"X":Y,"Z":d,"V":"/S/f/10/c/g/","Q":1,"P":"","N":0,"M":0,"L":{"e":K,"m":"J-I"}}).r();',62,65,'"# + "D41hWAODmwO4FMBGlgDYCMAOADF4AzASAExrCA03jhoLvRgXOaDf/sAJYC20AIgIYAuXwJYiRICMAnCAwBOYNlkB2WeUgAnBAEkAdsx6yArLIAss4gDNmAGwQBnYAGNNXVgmBSMhnJnvMAJsBTMdsCAYvKA+K6A3LaA6fqAEfqAvprAgNURgG6xgF+KgGFygG3agBep/o7O/r4CBiSKJMYkMlIcAJ5wABbyAOqwPtUAajgqAMpSAG7QAPIAWpDMClIkuER6YtYWwKoIvep+mggAHjwrAvhIFgD2dgDWAPp2QdZ8PACutl0AsgASC9bEBBIEYpC8dYQi5tprHUEH5TFwLNYXFZNKAgA==" + #"'['split']('|'),0,{}))"#
        let images = try ManhuaguiReader.images(packed)
        XCTAssertEqual(images.count, 33)
        XCTAssertTrue(images[0].hasPrefix("https://eu2.hamreus.com/ps3/26/10/61808/"))
        XCTAssertTrue(images[0].contains("/1.jpg.webp?e=1792803351&m=dyV0rS9vgOZpi-9Dywh7Wg"))
        XCTAssertTrue(images[32].contains("/33.jpg.webp?e=1792803351&m=dyV0rS9vgOZpi-9Dywh7Wg"))
    }
}

// Verbatim compressed dictionary and full 29-file packed payload from tools/check-manhuagui-parser.js.
// Stored in Swift so the existing package resource declaration remains untouched.
private let guiLZDictionary = "D4KwDg5sDuCmBGZgBYCcBWA7ARmIGm9tA9tWEEagwX4TAuJUCLtYQN0VAAOWAAYnVnsn3cwAnWASQB2ASwAu7AEzsAzO2TB26dgDZ2mdgA5mTLS3Ut52pU2xsJAIRayWUlrgBmwgDawAzsADGggIYBbWMA4EhLKSh7CACbAiMIewIDRzoC45sDUgIfygIbm0T7+0ZHaqkwSnIXyhVKCAIIasADiGgAWAPYAHsgA8jUAEgCyAMLoHmAAbhAAKtDA2JgayNIaHNK4rk6B2MHK8rywQ/xRQSGqgrDNorvRTo0eANYA+h5xrqLeogCu7qzMEtyushK/bIVZMJfBAACLPbyfYwhYBgZ71T66CT6aScRwiVz1WBRUQ8F4BFyCT5sADK3U6QA=="
private var guiLZPacked: String {
    #"(function(p,a,c,k,e,d){return p}('15.U({"A":3,"z":"y：x","w":"3.1","v":u,"t":"4 5 6","s":["r.1.2","q%p.1.2","l.1.2","n.1.2","B.1.2","k.1.2","j.1.2","7.1.2","8.1.2","9.1.2","b.1.2","c.1.2","d.1.2","f.1.2","g.1.2","h.1.2","i.1.2","o.1.2","C.1.2","P.1.2","E.1.2","T.1.2","D.1.2","V.1.2","W.1.2","Z.1.2","Y.1.2","14.1.2","10.1.2"],"11":12,"13":S,"X":"/Q/R/O/3/4 5 6/","N":0,"M":"","L":K,"J":I,"H":{"e":G,"m":"F"}}).a();',62,68,'"# + guiLZDictionary + #"'['split']('|'),0,{}))"#
}
