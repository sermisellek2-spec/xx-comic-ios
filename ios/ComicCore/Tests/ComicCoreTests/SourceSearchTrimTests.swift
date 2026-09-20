import Foundation
import XCTest
@testable import ComicCore

final class SourceSearchTrimTests: XCTestCase {
    private let keyword = " \t\u{00A0}词\u{3000}\r\n"
    private let copyBody = #"{"code":200,"results":{"list":[{"path_word":"sample","name":"Sample"}]}}"#

    func testCopySearchPreservesNonASCIIWhitespace() async throws {
        let transport = SearchTrimTransport(body: copyBody)
        try await assertSearch(CopyMangaComicSource(transport: transport), transport,
            url: "https://www.copy4000.com/api/kb/web/searchci/comics?offset=0&platform=2&limit=12&q=%C2%A0%E8%AF%8D%E3%80%80&q_type=")
    }

    func testD5d6SearchPreservesNonASCIIWhitespace() async throws {
        let transport = SearchTrimTransport(body: #"<ul class="cart-list"><li><div class="cart-item"><a href="/jiujiucomic_42/"><img alt="Sample"></a></div></li></ul>"#)
        try await assertSearch(D5d6ComicSource(transport: transport), transport,
            url: "https://www.d5d6.com/search/%C2%A0%E8%AF%8D%E3%80%80/")
    }

    func testGmhSearchPreservesNonASCIIWhitespace() async throws {
        let transport = SearchTrimTransport(body: #"<a href="/manga/sample"><img src="https://img.example/cover.webp"><h3 class="cardtitle">Sample</h3></a>"#)
        try await assertSearch(GmhComicSource(transport: transport), transport,
            url: "https://m.g-mh.org/s/%C2%A0%E8%AF%8D%E3%80%80")
    }

    func testAntbywSearchPreservesNonASCIIWhitespace() async throws {
        let transport = SearchTrimTransport(body: #"<div class="uk-card uk-text-center"><a href="plugin.php?a=bofang&amp;kuid=42"><img src="/cover.jpg"></a><p><a href="plugin.php?a=bofang&amp;kuid=42">Sample</a></p></div>"#)
        try await assertSearch(AntbywComicSource(transport: transport), transport,
            url: "https://www.antbyw.com/plugin.php?id=jameson_manhua&a=search&c=index&keyword=%C2%A0%E8%AF%8D%E3%80%80")
    }

    func testMh160SearchPreservesNonASCIIWhitespace() async throws {
        let transport = SearchTrimTransport(body: #"<ul class="mh-search-list"><li><a href="/kanmanhua/42/"><img alt="Sample"></a></li></ul>"#)
        try await assertSearch(Mh160ComicSource(transport: transport), transport,
            url: "https://www.mh160mh.com/statics/searchelxt1e1.aspx?key=%C2%A0%E8%AF%8D%E3%80%80")
    }

    func testHiperdexSearchPreservesNonASCIIWhitespace() async throws {
        let transport = SearchTrimTransport(body: #"<main><div class="manga-item"><a href="/manga/sample/"><img alt="Sample"></a><h3><a>Sample</a></h3></div></main>"#)
        try await assertSearch(HiperdexComicSource(transport: transport), transport,
            url: "https://hiperdex.com/?s=%C2%A0%E8%AF%8D%E3%80%80&post_type=wp-manga")
    }

    func testMh18SearchPreservesNonASCIIWhitespace() async throws {
        let transport = SearchTrimTransport(body: #"<a href="/manga/sample/1"><img src="https://img.18mh.org/cover.webp"><h3 class="cardtitle">Sample</h3></a>"#)
        try await assertSearch(Mh18ComicSource(transport: transport), transport,
            url: "https://18mh.org/s/%C2%A0%E8%AF%8D%E3%80%80")
    }

    func testCopySearchWithOnlyNBSPStillSendsRequest() async throws {
        let transport = SearchTrimTransport(body: copyBody)
        let result = try await CopyMangaComicSource(transport: transport).search(keyword: "\u{00A0}", page: 1)
        let requests = await transport.requests
        XCTAssertEqual(requests, ["https://www.copy4000.com/api/kb/web/searchci/comics?offset=0&platform=2&limit=12&q=%C2%A0&q_type="])
        XCTAssertEqual(result.map(\.title), ["Sample"])
    }

    func testCopySearchWithOnlyASCIIWhitespaceReturnsEmptyWithoutRequest() async throws {
        let transport = SearchTrimTransport(body: copyBody)
        let result = try await CopyMangaComicSource(transport: transport).search(keyword: " \t\r\n", page: 1)
        let requests = await transport.requests
        XCTAssertEqual(result, [])
        XCTAssertEqual(requests, [])
    }

    private func assertSearch(_ source: any ComicSource, _ transport: SearchTrimTransport,
                              url: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let result = try await source.search(keyword: keyword, page: 1)
        let requests = await transport.requests
        XCTAssertEqual(requests, [url], file: file, line: line)
        XCTAssertEqual(result.map(\.title), ["Sample"], file: file, line: line)
    }
}

private actor SearchTrimTransport: HTTPTransport {
    let body: String
    var requests: [String] = []

    init(body: String) { self.body = body }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(url.absoluteString)
        return HTTPResponse(data: Data(body.utf8), statusCode: 200)
    }
}
