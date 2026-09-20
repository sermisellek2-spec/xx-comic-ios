import Foundation
import XCTest
@testable import ComicCore

final class ManwaSourceTests: XCTestCase {
    private let chapterURL = "https://manwace.cc/comic/163037/2161449"
    private let empty = #"{"code":200,"data":{"list":[]}}"#
    private let info = #"{"code":200,"data":{"current":{"comicId":163037,"id":2161449,"title":"第01话"}}}"#

    func testAndroidRecordedFixturesIncludingThirtyEightImages() async throws {
        let names = ["search.json","cate.json","detail.html","chapters.json","chapter-info.json","images.json"]
        let fixtures = try names.map { name in
            try String(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "manwa")), encoding: .utf8)
        }
        let source = ManwaComicSource(transport: ManwaTransport(fixtures))
        let search = try await source.search(keyword: "史莱姆", page: 1)
        XCTAssertEqual(search.count, 2)
        XCTAssertEqual(search.first?.comicId, "manwa:10395")
        let category = try await source.latest(page: 1)
        XCTAssertFalse(category.isEmpty)
        let detail = try await source.detail(comicId: "163037")
        XCTAssertEqual(detail.summary.title, "最速进化的史莱姆无双")
        XCTAssertEqual(detail.author, "艇駆いいじ，野口祥汰")
        XCTAssertTrue(detail.chapters.isEmpty)
        let chapters = try await source.chapters(comicId: "163037")
        XCTAssertEqual(chapters.map(\.chapterId), ["2161449"])
        let page = try await source.chapter(url: chapterURL)
        XCTAssertEqual(page.imageUrls.count, 38)
        XCTAssertTrue(page.imageUrls.first?.hasSuffix("f74f09d566f4404ba555fd441345c358.jpg") == true)
        XCTAssertTrue(page.imageUrls.last?.hasSuffix("e60030a3d4754da590fd46060eb94dc1.jpg") == true)
    }

    func testCategoryPostsDefaultsAndCookieDoesNotLeakToSearch() async throws {
        let transport = ManwaTransport([empty, empty, empty])
        let source = ManwaComicSource(transport: transport)
        _ = try await source.category(filters: ["type":"2"], page: 2)
        _ = try await source.latest(page: 1)
        _ = try await source.search(keyword: "  史莱姆 & A  ", page: 2)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "GET"])
        XCTAssertEqual(requests.map { $0.headers["Cookie"] }, ["typeId=2", "typeId=0", nil])
        XCTAssertEqual(requests[0].url, "https://manwace.cc/api/cate")
        XCTAssertEqual(requests[0].headers["Referer"], "https://manwace.cc/cate")
        XCTAssertEqual(requests[0].headers["Origin"], "https://manwace.cc")
        XCTAssertEqual(requests[0].headers["Content-Type"], "application/json; charset=UTF-8")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].body!) as? [String:Any])
        XCTAssertEqual(body["category"] as? String, "comic")
        XCTAssertEqual(body["page"] as? [String:Int], ["page":2,"pageSize":36])
        let comic = try XCTUnwrap(body["comic"] as? [String:Any])
        XCTAssertEqual(comic["level"] as? Int, 1)
        XCTAssertEqual(comic["typeId"] as? Int, 2)
        XCTAssertEqual(comic["status"] as? Int, -1)
        XCTAssertEqual((body["novel"] as? [String:Int])?["status"], -1)
        XCTAssertEqual(requests[2].url, "https://manwace.cc/api/search?type=mh&page=2&pageSize=20&keyword=%E5%8F%B2%E8%8E%B1%E5%A7%86+%26+A")
        _ = try await source.search(keyword: " ", page: 1)
        let count = await transport.requests.count
        XCTAssertEqual(count, 3)
    }

    func testAllTagRoutesAndCombinedFilterValues() async throws {
        let slugs = ["hotblooded","xuanhuan","romance","adventure","historical","urban","transmigration","fantasy","comedy","shounen","action","rebirth","counterattack","hilarious","youth","harem","system","bl","manhwa","fullversion","19plus","taiwanver"]
        let transport = ManwaTransport(Array(repeating: empty, count: 23))
        let source = ManwaComicSource(transport: transport)
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups.map(\.key), ["level","type","tag","region","state","day","sort"])
        XCTAssertEqual(groups[2].options.count, 23)
        for option in groups[2].options.dropFirst() { _ = try await source.category(filters: ["tag":option.value], page: 1) }
        _ = try await source.category(filters: ["level":"0","type":"1","region":"3","state":"0","day":"2","tag":"冒险","sort":"3"], page: 3)
        let requests = await transport.requests
        XCTAssertEqual(Array(requests.prefix(22)).map(\.url), slugs.map { "https://manwace.cc/api/cate/" + $0 })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[22].body!) as? [String:Any])
        let comic = try XCTUnwrap(body["comic"] as? [String:Any])
        XCTAssertEqual(comic["level"] as? Int, 0)
        XCTAssertEqual(comic["areaId"] as? Int, 3)
        XCTAssertEqual(comic["day"] as? Int, 2)
        XCTAssertEqual(comic["tag"] as? String, "冒险")
        XCTAssertEqual(body["sort"] as? Int, 3)
        do { _ = try await source.category(filters: ["tag":"unknown"], page: 1); XCTFail("未知标签必须拒绝") } catch {}
    }

    func testListDecodesIDsImagesTagsAndDeduplicates() async throws {
        let json = #"{"code":200,"data":{"list":[{"url":"/comic/10395","title":"史莱姆&amp;圣女","pic":"//mwtuwu.cc/a.jpg","author":"作者","tags":"魔幻，冒险/热血|恋爱"},{"id":10395,"title":"重复"},{"id":2,"title":"第二本","cover":"/b.jpg"}]}}"#
        let result = try await ManwaComicSource(transport: ManwaTransport([json])).search(keyword: "史莱姆", page: 1)
        XCTAssertEqual(result.map(\.comicId), ["manwa:10395","manwa:2"])
        XCTAssertEqual(result[0].title, "史莱姆&圣女")
        XCTAssertEqual(result[0].coverUrl, "https://mwtuwu.cc/a.jpg")
        XCTAssertEqual(result[0].tags, ["魔幻","冒险","热血","恋爱"])
        XCTAssertEqual(result[1].coverUrl, "https://manwace.cc/b.jpg")
    }

    func testDetailIsOnDemandAndUsesRealCoverAndNestedTags() async throws {
        let html = #"<h2 id="page-title">最速&#x8FDB;化</h2><span id="author-container"><a>甲</a> ， <a>乙</a></span><span id="status">连载中</span><a id="newch">第01话</a><div id="tagsContainer"><a><span>魔幻</span></a><a>冒险</a></div><img class="comic-cover lazy" data-original-cover="/real.jpg" src="/placeholder.jpg"><p class="comic-desc">简介&amp;内容</p>"#
        let transport = ManwaTransport([html])
        let detail = try await ManwaComicSource(transport: transport).detail(comicId: "manwa:163037")
        XCTAssertEqual(detail.summary.title, "最速进化")
        XCTAssertEqual(detail.author, "甲，乙")
        XCTAssertEqual(detail.summary.coverUrl, "https://manwace.cc/real.jpg")
        XCTAssertEqual(detail.summary.tags, ["魔幻","冒险"])
        XCTAssertEqual(detail.description, "简介&内容")
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.latestChapter, "第01话")
        XCTAssertTrue(detail.chapters.isEmpty)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url), ["https://manwace.cc/comic/163037"])
    }

    func testDirectoryPreservesFractionalStableOrderAndAll878Chapters() async throws {
        let rows: [[String:Any]] = [["id":90,"sortId":2],["id":500,"sortId":1],["id":3,"sortId":1.5],["id":4,"sortId":1.5],["id":90,"sortId":2]]
        let full = (1...878).map { ["id":$0,"sortId":$0] }
        let transport = ManwaTransport([try response(["list":rows]), try response(["list":full])])
        let source = ManwaComicSource(transport: transport)
        let chapters = try await source.chapters(comicId: "manwa:163037")
        XCTAssertEqual(chapters.map(\.chapterId), ["500","3","4","90"])
        XCTAssertEqual(chapters.map(\.chapterSlot), [0,1,2,3])
        XCTAssertEqual(chapters[0].url, "https://manwace.cc/comic/163037/500")
        let large = try await source.chapters(comicId: "7751")
        XCTAssertEqual(large.count, 878)
        XCTAssertEqual(large.last?.chapterId, "878")
    }

    func testChapterFetchesAllPagesInOrder() async throws {
        let transport = ManwaTransport([info, try page(1, pages: 2, total: 3, ["/a.jpg","//tu.mwzu.cc/b.jpg"]), try page(2, pages: 2, total: 3, ["https://tu.mwzu.cc/c.jpg"])])
        let result = try await ManwaComicSource(transport: transport).chapter(url: chapterURL)
        XCTAssertEqual(result.chapterId, chapterURL)
        XCTAssertEqual(result.title, "第01话")
        XCTAssertEqual(result.nextPageUrl, "")
        XCTAssertEqual(result.imageUrls, ["https://manwace.cc/a.jpg","https://tu.mwzu.cc/b.jpg","https://tu.mwzu.cc/c.jpg"])
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url), ["https://manwace.cc/api/comic/chapter/info/2161449", "https://manwace.cc/api/comic/image/2161449?page=1&page_size=100&image_source=https%3A%2F%2Ftu.mwzu.cc", "https://manwace.cc/api/comic/image/2161449?page=2&page_size=100&image_source=https%3A%2F%2Ftu.mwzu.cc"])
        XCTAssertTrue(requests.allSatisfy { $0.headers["Referer"] == chapterURL })
    }

    func testIncompleteDuplicateChangingAndMalformedPagesNeverReturnPartialChapter() async throws {
        let first = try page(1, pages: 2, total: 2, ["/a.jpg"])
        let cases = [
            [first, try page(2, pages: 2, total: 2, ["/a.jpg"])],
            [first, try page(1, pages: 2, total: 2, ["/b.jpg"])],
            [first, try page(2, pages: 2, total: 3, ["/b.jpg"])],
            [try page(1, pages: 1, total: 2, ["/a.jpg"])],
            [try page(1, pages: 1, total: 1, [])],
            [try page(1, pages: 1, total: 1, ["javascript:alert(1)"])],
            [#"{"code":200,"data":{"images":[]}}"#],
            [#"{"code":403}"#]
        ]
        for pages in cases {
            do { _ = try await ManwaComicSource(transport: ManwaTransport([info] + pages)).chapter(url: chapterURL); XCTFail("不完整章节必须拒绝") } catch {}
        }
    }

    func testErrorShellIDsAndAccessRestrictionsFailClearly() async throws {
        for json in [#"{"code":403}"#, #"{"code":200,"data":{}}"#, #"{"code":200,"data":{"list":[null]}}"#, #"{"code":200,"data":{"list":[{"id":"abc"}]}}"#, "<h1>404</h1>"] {
            do { _ = try await ManwaComicSource(transport: ManwaTransport([json])).latest(page: 1); XCTFail("错误响应不能伪装空列表") } catch {}
        }
        let transport = ManwaTransport([info])
        let source = ManwaComicSource(transport: transport)
        do { _ = try await source.detail(comicId: "bad"); XCTFail() } catch {}
        do { _ = try await source.chapter(url: "/search"); XCTFail() } catch {}
        do { _ = try await source.chapter(url: "https://manwace.cc/comic/123/2161449"); XCTFail() } catch {}
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
        do { _ = try await ManwaComicSource(transport: ManwaTransport([""], status: 401)).latest(page: 1); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("访问受限")) }
    }

    func testCancellationDuringChapterStopsFurtherImageRequests() async throws {
        let transport = ManwaTransport([info], cancelAt: 1)
        do { _ = try await ManwaComicSource(transport: transport).chapter(url: chapterURL); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
    }

    private func response(_ data: [String:Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["code":200,"data":data]), as: UTF8.self)
    }
    private func page(_ page: Int, pages: Int, total: Int, _ urls: [String]) throws -> String {
        try response(["images":urls.map { ["url":$0] },"pagination":["current_page":page,"total_pages":pages,"total":total]])
    }
}

private actor ManwaTransport: HTTPTransport {
    struct Request { let method: String; let url: String; let headers: [String:String]; let body: Data? }
    var requests: [Request] = []
    var responses: [String]
    let status: Int
    let cancelAt: Int?
    init(_ responses: [String], status: Int = 200, cancelAt: Int? = nil) { self.responses = responses; self.status = status; self.cancelAt = cancelAt }
    func get(_ url: URL, headers: [String:String]) async throws -> HTTPResponse { try send("GET", url, headers, nil) }
    func post(_ url: URL, headers: [String:String], body: Data) async throws -> HTTPResponse { try send("POST", url, headers, body) }
    private func send(_ method: String, _ url: URL, _ headers: [String:String], _ body: Data?) throws -> HTTPResponse {
        requests.append(.init(method: method, url: url.absoluteString, headers: headers, body: body))
        if requests.count == cancelAt { throw CancellationError() }
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return .init(data: Data(responses.removeFirst().utf8), statusCode: status)
    }
}
