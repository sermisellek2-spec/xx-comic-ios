import Foundation
import XCTest
@testable import ComicCore

final class DingManhuaSourceTests: XCTestCase {
    func testSearchFiltersDetailDirectoryAndReaderUseTheObservedRoutes() async throws {
        let transport = DingManhuaFakeTransport()
        let source = DingManhuaComicSource(transport: transport)

        let search = try await source.search(keyword: "海贼王", page: 2)
        XCTAssertEqual(search.first?.comicId, "dingmanhua:1305")
        let searchReq = await transport.lastRequest
        XCTAssertTrue(searchReq?.url.contains("query=%E6%B5%B7%E8%B4%BC%E7%8E%8B&page=2") == true)

        _ = try await source.category(filters: ["region": "jp", "tag": "热血"], page: 3)
        let catReq = await transport.lastRequest
        XCTAssertTrue(catReq?.url.contains("category=1&tag=9&page=3") == true)

        let detail = try await source.detail(comicId: "dingmanhua:1305")
        XCTAssertEqual(detail.summary.title, "测试漫画")
        XCTAssertEqual(detail.author, "作者甲")
        XCTAssertEqual(detail.description, "简介")

        let chapters = try await source.chapters(comicId: detail.summary.comicId)
        XCTAssertEqual(chapters.map(\.title), ["第01话", "第02话"])
        XCTAssertEqual(chapters.first?.url, "https://www.dingmanhua.com/chapter/1305-2372195.html")
        let chReq = await transport.lastRequest
        XCTAssertEqual(chReq?.method, "POST")
        XCTAssertEqual(chReq?.body, "form=form")

        let reader = try await source.chapter(url: chapters[0].url)
        XCTAssertEqual(reader.imageUrls, ["https://image.cdnweb.win/page/01.jpg"])
    }

    func testReaderScriptPasdAndNumGeneratesSequentialImages() async throws {
        let html = """
        <title>第1话 - Junket bank</title>
        <img data-src="/resource/image/loading.svg" class="comic-image lazy" src="/resource/image/loading.svg">
        <script>
        var pasd = "https://image1.dingmanhua.com/mh/89d803513b95472b9eac1070dd5d6f80/6d66d12e-9893-40ee-babc-5aae92a3ed36/";
        var num = eval("3");
        var url = pasd + i + ".webp";
        </script>
        """
        let images = try DingManhuaComicSource.readerImages(html: html, url: "https://www.dingmanhua.com/chapter/10061-2349775.html")
        XCTAssertEqual(images, [
            "https://image1.dingmanhua.com/mh/89d803513b95472b9eac1070dd5d6f80/6d66d12e-9893-40ee-babc-5aae92a3ed36/1.webp",
            "https://image1.dingmanhua.com/mh/89d803513b95472b9eac1070dd5d6f80/6d66d12e-9893-40ee-babc-5aae92a3ed36/2.webp",
            "https://image1.dingmanhua.com/mh/89d803513b95472b9eac1070dd5d6f80/6d66d12e-9893-40ee-babc-5aae92a3ed36/3.webp"
        ])
    }

    func testFilterGroupsAndSourceConfigDefaults() async throws {
        let def = try XCTUnwrap(SourceConfigDefaults.defaultConfig(for: "dingmanhua"))
        XCTAssertEqual(def.id, "dingmanhua")
        XCTAssertEqual(def.name, "顶漫画")
        XCTAssertEqual(def.domain, "www.dingmanhua.com")
        XCTAssertEqual(def.filter("region.jp"), "1")
        XCTAssertEqual(def.filter("tag.热血"), "9")
        XCTAssertEqual(def.filter("tag.舞蹈"), "63")

        let source = DingManhuaComicSource(config: def, transport: DingManhuaFakeTransport())
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups.map(\.key), ["region", "tag"])
        XCTAssertEqual(groups[0].options.count, 4)
        XCTAssertEqual(groups[1].options.count, 61)
        let healthy = await source.healthCheck()
        XCTAssertTrue(healthy)
    }

    func testInvalidIDsAndErrorsThrowClearly() async throws {
        let source = DingManhuaComicSource(transport: DingManhuaFakeTransport())
        do {
            _ = try await source.detail(comicId: "bad/id")
            XCTFail("非法 ID 应报错")
        } catch {}
        do {
            _ = try await source.chapter(url: "https://www.dingmanhua.com/invalid")
            XCTFail("非法章节链接应报错")
        } catch {}
    }
}

private actor DingManhuaFakeTransport: HTTPTransport {
    struct Req { let method: String; let url: String; let body: String? }
    var lastRequest: Req?

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        lastRequest = Req(method: "GET", url: url.absoluteString, body: nil)
        let u = url.absoluteString
        if u.contains("/chapter/") {
            return .html("<title>第01话 - 测试漫画</title><img class=\"comic-image\" data-src=\"https://image.cdnweb.win/page/01.jpg\">")
        }
        if u.contains("/comic/1305.html") {
            return .html("<h1>测试漫画</h1><div class=\"author\">作者甲</div><p class=\"description\">简介</p>")
        }
        return .html("<div class=\" card-content\"><a href=\"/comic/1305.html\"><img data-src=\"/cover.jpg\" alt=\"测试漫画\"></a><h3>测试漫画</h3></div>")
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
        lastRequest = Req(method: "POST", url: url.absoluteString, body: String(data: body, encoding: .utf8))
        return .html(#"{"code":0,"data":{"chapters":[{"id":"2372196","contentId":"1305","chapterName":"第02话"},{"id":"2372195","contentId":"1305","chapterName":"第01话"}]}}"#)
    }
}
