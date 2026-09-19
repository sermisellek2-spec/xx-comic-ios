import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ComicCore

final class GmhSourceTests: XCTestCase {
    func testSearchParsesCardsInOrderAndDeduplicatesComicIDs() async throws {
        let html = """
        <a href="/manga/first-comic"><img data-src="https://img.example/first.webp&amp;x=1"><h3 class="cardtitle"> First &amp; Best </h3></a>
        <a href="/manga/first-comic"><img src="ignored.webp"><h3 class="cardtitle">Duplicate</h3></a>
        <a href="https://m.g-mh.org/manga/second-comic"><img src="//img.example/second.webp"><h3 class="cardtitle">second-comic</h3></a>
        """
        let transport = StubTransport(responses: [
            "https://m.g-mh.org/s/hero+name": response(html)
        ])
        let source = GmhComicSource(transport: transport)

        let comics = try await source.search(keyword: " hero name ", page: 4)

        XCTAssertEqual(comics, [
            ComicSummary(sourceId: "gmh", comicId: "gmh:first-comic", title: "First & Best", coverUrl: "https://img.example/first.webp"),
            ComicSummary(sourceId: "gmh", comicId: "gmh:second-comic", title: "second comic", coverUrl: "//img.example/second.webp")
        ])
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["Referer"], "https://m.g-mh.org/")
        XCTAssertEqual(request.headers["User-Agent"], "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
    }

    func testLatestAndCategoryUseAndroidRoutesAndTagTakesPriority() async throws {
        let emptyPage = "<html></html>"
        let transport = StubTransport(responses: [
            "https://m.g-mh.org/manga/page/2": response(emptyPage),
            "https://m.g-mh.org/manga-tag/fuchou/page/3": response(emptyPage)
        ])
        let source = GmhComicSource(transport: transport)

        _ = try await source.latest(page: 2)
        _ = try await source.category(filters: ["genre": "kr", "tag": "fuchou"], page: 3)

        let urls = await transport.requests().map(\.url)
        XCTAssertEqual(urls, [
            "https://m.g-mh.org/manga/page/2",
            "https://m.g-mh.org/manga-tag/fuchou/page/3"
        ])
    }

    func testFilterGroupsPreserveWebsiteOrderAndStripTagHash() async throws {
        let html = """
        <a href="/manga-genre/kr"><button>韩漫</button></a>
        <a href="/manga-genre/jp"><button>日漫</button></a>
        <a href="/manga-tag/fuchou"><button>#复仇</button></a>
        <a href="/manga-tag/nixi"><button>#逆袭</button></a>
        """
        let source = GmhComicSource(transport: StubTransport(responses: [
            "https://m.g-mh.org/manga": response(html)
        ]))

        let groups = try await source.filterGroups()

        XCTAssertEqual(groups, [
            SourceFilterGroup(key: "genre", label: "漫画类型", options: [
                SourceFilterOption(label: "全部", value: "all"),
                SourceFilterOption(label: "韩漫", value: "kr"),
                SourceFilterOption(label: "日漫", value: "jp")
            ]),
            SourceFilterGroup(key: "tag", label: "热门标签", options: [
                SourceFilterOption(label: "全部", value: "all"),
                SourceFilterOption(label: "复仇", value: "fuchou"),
                SourceFilterOption(label: "逆袭", value: "nixi")
            ])
        ])
    }

    func testFilterGroupsThrowWhenEitherGroupCannotBeParsed() async {
        let source = GmhComicSource(transport: StubTransport(responses: [
            "https://m.g-mh.org/manga": response("<a href=\"/manga-genre/kr\"><button>韩漫</button></a>")
        ]))

        await XCTAssertAsyncThrowsError(try await source.filterGroups())
    }

    func testFilterGroupsDeduplicateByLabelLikeAndroidLinkedHashMap() async throws {
        let html = """
        <a href="/manga-genre/kr"><button>韩漫</button></a>
        <a href="/manga-genre/all"><button>全部</button></a>
        <a href="/manga-genre/korean-new"><button>韩漫</button></a>
        <a href="/manga-genre/jp"><button>日漫</button></a>
        <a href="/manga-tag/fuchou"><button>#复仇</button></a>
        <a href="/manga-tag/all"><button>#全部</button></a>
        <a href="/manga-tag/revenge-new"><button>#复仇</button></a>
        <a href="/manga-tag/nixi"><button>#逆袭</button></a>
        """
        let source = GmhComicSource(transport: StubTransport(responses: [
            "https://m.g-mh.org/manga": response(html)
        ]))

        let groups = try await source.filterGroups()

        XCTAssertEqual(groups, [
            SourceFilterGroup(key: "genre", label: "漫画类型", options: [
                SourceFilterOption(label: "全部", value: "all"),
                SourceFilterOption(label: "韩漫", value: "korean-new"),
                SourceFilterOption(label: "日漫", value: "jp")
            ]),
            SourceFilterGroup(key: "tag", label: "热门标签", options: [
                SourceFilterOption(label: "全部", value: "all"),
                SourceFilterOption(label: "复仇", value: "revenge-new"),
                SourceFilterOption(label: "逆袭", value: "nixi")
            ])
        ])
    }

    func testDetailUsesMangaAPIDataAndMapsStatus() async throws {
        let transport = StubTransport(responses: [
            "https://m.g-mh.org/manga/demo": response("<main data-mid=\"42\"></main>"),
            "https://v2.apikk.top/api/v2/manga/get?mid=42&mode=all": jsonResponse("""
            {"code":200,"data":{"title":" Demo &amp; One ","slug":"demo","status":"1","cover":"https://img.example/cover.webp","desc":" Line&nbsp; one "}}
            """)
        ])
        let source = GmhComicSource(transport: transport)

        let detail = try await source.detail(comicId: "gmh:demo")

        XCTAssertEqual(detail, ComicDetail(
            summary: ComicSummary(sourceId: "gmh", comicId: "gmh:demo", title: "Demo & One", coverUrl: "https://img.example/cover.webp"),
            author: "",
            status: "连载中",
            description: "Line one",
            latestChapter: "",
            chapters: []
        ))
    }

    func testChaptersDiscardAdsWhenVisibleChaptersExistWithoutChangingOrder() async throws {
        let source = GmhComicSource(transport: catalogTransport(chapters: """
        [
          {"id":"1","attributes":{"title":"Ad","slug":"ad","order":9,"isAd":1}},
          {"id":"2","attributes":{"title":" First ","slug":"first","order":3,"isAd":0}},
          {"id":"3","attributes":{"title":"Second","slug":"second","order":1,"isAd":0}}
        ]
        """))

        let chapters = try await source.chapters(comicId: "gmh:demo")

        XCTAssertEqual(chapters, [
            Chapter(chapterId: "2", title: "First", url: "https://m.g-mh.org/manga/demo/first", chapterSlot: 3),
            Chapter(chapterId: "3", title: "Second", url: "https://m.g-mh.org/manga/demo/second", chapterSlot: 1)
        ])
    }

    func testChaptersFallBackToAdsWhenNoVisibleChapterExists() async throws {
        let source = GmhComicSource(transport: catalogTransport(chapters: """
        [
          {"id":"1","attributes":{"title":"First ad","slug":"first","order":4,"isAd":1}},
          {"id":"2","attributes":{"title":"Second ad","slug":"second","order":5,"isAd":1}}
        ]
        """))

        let chapters = try await source.chapters(comicId: "demo")

        XCTAssertEqual(chapters.map(\.chapterId), ["1", "2"])
    }

    func testChaptersAcceptExplicitEmptyArray() async throws {
        let source = GmhComicSource(transport: catalogTransport(chapters: "[]"))

        let chapters = try await source.chapters(comicId: "demo")

        XCTAssertEqual(chapters, [])
    }

    func testChaptersRejectMissingOrWrongTypedArray() async {
        for data in ["{\"slug\":\"demo\"}", "{\"slug\":\"demo\",\"chapters\":{}}"] {
            let source = GmhComicSource(transport: mangaDataTransport(data))

            await XCTAssertAsyncThrowsError(try await source.chapters(comicId: "demo")) { error in
                XCTAssertEqual(error as? GmhSourceError, .invalidResponse("G社漫画目录解析失败"))
            }
        }
    }

    func testChapterDecodesRealWebsiteFixtureAndMigratesLineHost() async throws {
        // Captured read-only from the live chapter API on 2026-09-19 (mid 12, chapter 1376376).
        let encrypted = "J7rbNWM0QaMnhvhmxjAaviRmQ3RaznkbKuxmNbzn5exnQm8bNzy0N6takDOa8aR_hck3QnkfxnA2hcxmPchaPmQ7haTyhbheOaA39qwjQrI2XleW4skRGwpR2xcw3lny7G3BjMpCXw3U39q9XRrkLkoyTkmD6InAjInL3xnQ"
        let transport = StubTransport(responses: [
            "https://m.g-mh.org/manga/demo": response("<main data-mid=\"12\"></main>"),
            "https://v2.apikk.top/api/v2/manga/get?mid=12&mode=all": jsonResponse("""
            {"data":{"slug":"demo","chapters":[{"id":"1376376","attributes":{"title":"Old title","slug":"notice","order":0,"isAd":0}}]}}
            """),
            "https://v2.apikk.top/api/v2/chapter/getinfo?m=12&c=1376376": jsonResponse("""
            {"data":{"info":{"title":"致歉 3","images":{"images":"\(encrypted)","line":2}}}}
            """)
        ])
        let source = GmhComicSource(transport: transport)

        let page = try await source.chapter(url: "https://m.g-mh.org/manga/demo/notice?from=test")

        XCTAssertEqual(page, ChapterPage(
            chapterId: "https://m.g-mh.org/manga/demo/notice?from=test",
            title: "致歉 3",
            nextPageUrl: "",
            imageUrls: ["https://c-nd2-1.6wm.top/hp/wuliandianfeng/3621/c2e8a2eca57cb72805fec3edd3466f9d/1_1070349b6edc92ff65935a991165442b.webp"]
        ))
    }

    func testChapterPreservesPlainImageOrderDeduplicatesAndMigratesOnlyExactLegacyHosts() async throws {
        let transport = StubTransport(responses: [
            "https://m.g-mh.org/manga/demo": response("<main data-mid=\"42\"></main>"),
            "https://v2.apikk.top/api/v2/manga/get?mid=42&mode=all": jsonResponse("""
            {"data":{"chapters":[{"id":"7","attributes":{"title":"Chapter","slug":"plain"}}]}}
            """),
            "https://v2.apikk.top/api/v2/chapter/getinfo?m=42&c=7": jsonResponse("""
            {"data":{"info":{"images":{"images":[
              "https://f40-1-4.g-mh.online/a.webp?x=%2F&n=1",
              {"url":"https://t40-1-4.g-mh.online/b.webp"},
              "https://f40-1-4.g-mh.online/a.webp?x=%2F&n=1",
              "https://f40-1-4.g-mh.online.evil/c.webp"
            ]}}}}
            """)
        ])
        let source = GmhComicSource(transport: transport)

        let page = try await source.chapter(url: "https://m.g-mh.org/manga/demo/plain")

        XCTAssertEqual(page.imageUrls, [
            "https://c-nd2-1.6wm.top/a.webp?x=%2F",
            "https://c-nd3-1.6wm.top/b.webp",
            "https://f40-1-4.g-mh.online.evil/c.webp"
        ])
        XCTAssertEqual(
            GmhComicSource.migrateImageURL("https://f40-1-4.g-mh.online/a.webp?x=%2F&n=1"),
            "https://c-nd2-1.6wm.top/a.webp?x=%2F&n=1"
        )
    }

    func testChapterAcceptsExplicitEmptyImagesArray() async throws {
        let source = chapterSource(imagesJSON: "{\"images\":[]}")

        let page = try await source.chapter(url: "https://m.g-mh.org/manga/demo/plain")

        XCTAssertEqual(page.imageUrls, [])
    }

    func testChapterRejectsMissingOrWrongTypedImagesPayload() async {
        for infoJSON in ["{\"title\":\"Chapter\"}", "{\"title\":\"Chapter\",\"images\":[]}", "{\"title\":\"Chapter\",\"images\":{}}"] {
            let source = chapterSource(infoJSON: infoJSON)

            await XCTAssertAsyncThrowsError(try await source.chapter(url: "https://m.g-mh.org/manga/demo/plain")) { error in
                XCTAssertEqual(error as? GmhSourceError, .invalidResponse("G社漫画图片解析失败"))
            }
        }
    }

    func testInvalidEncryptedImagesThrow() async {
        let source = chapterSource(imagesJSON: "{\"images\":\"not-encrypted\"}")

        await XCTAssertAsyncThrowsError(try await source.chapter(url: "https://m.g-mh.org/manga/demo/plain")) { error in
            XCTAssertEqual(error as? GmhSourceError, .imageDecryptionFailed)
        }
    }

    func testMissingMangaIDThrows() async {
        let source = GmhComicSource(transport: StubTransport(responses: [
            "https://m.g-mh.org/manga/demo": response("<html></html>")
        ]))

        await XCTAssertAsyncThrowsError(try await source.chapters(comicId: "demo")) { error in
            XCTAssertEqual(error as? GmhSourceError, .missingMangaID("demo"))
        }
    }

    func testUnknownChapterSlugThrows() async {
        let source = GmhComicSource(transport: catalogTransport(chapters: "[]"))

        await XCTAssertAsyncThrowsError(try await source.chapter(url: "https://m.g-mh.org/manga/demo/missing")) { error in
            XCTAssertEqual(error as? GmhSourceError, .chapterNotFound("missing"))
        }
    }

    func testInvalidJSONThrows() async {
        let source = GmhComicSource(transport: StubTransport(responses: [
            "https://m.g-mh.org/manga/demo": response("<main data-mid=\"42\"></main>"),
            "https://v2.apikk.top/api/v2/manga/get?mid=42&mode=all": jsonResponse("not-json")
        ]))

        await XCTAssertAsyncThrowsError(try await source.detail(comicId: "demo")) { error in
            XCTAssertEqual(error as? GmhSourceError, .invalidResponse("JSON 解析失败"))
        }
    }

    func testInvalidUTF8Throws() async {
        let source = GmhComicSource(transport: StubTransport(responses: [
            "https://m.g-mh.org/manga": HTTPResponse(data: Data([0xff]), statusCode: 200)
        ]))

        await XCTAssertAsyncThrowsError(try await source.latest(page: 1)) { error in
            XCTAssertEqual(error as? GmhSourceError, .invalidResponse("响应不是 UTF-8"))
        }
    }

    func testHTTPStatusFailureThrowsInsteadOfReturningEmptyResults() async {
        let source = GmhComicSource(transport: StubTransport(responses: [
            "https://m.g-mh.org/s/test": response("server error", statusCode: 503)
        ]))

        await XCTAssertAsyncThrowsError(try await source.search(keyword: "test", page: 1)) { error in
            XCTAssertEqual(error as? HTTPTransportError, .invalidStatusCode(503))
        }
    }

    func testTransportFailureIsPropagatedInsteadOfReturningEmptyResults() async {
        let source = GmhComicSource(transport: StubTransport(responses: [:], failingURLs: [
            "https://m.g-mh.org/manga"
        ]))

        await XCTAssertAsyncThrowsError(try await source.latest(page: 1)) { error in
            XCTAssertEqual(error as? StubError, .offline)
        }
    }

    func testURLSessionTransportDoesNotStartPreCancelledRequest() async {
        TestURLProtocol.configure(.succeed)
        defer { TestURLProtocol.reset() }
        let session = makeTestURLSession()
        let transport = URLSessionHTTPTransport(session: session)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.get(URL(string: "https://example.test/pre-cancelled")!, headers: [:])
        }

        let result = await task.result

        assertCancellation(result)
        XCTAssertEqual(TestURLProtocol.startedRequests().count, 0)
    }

    func testURLSessionTransportCancelsInFlightDataTask() async {
        let started = expectation(description: "request started")
        let stopped = expectation(description: "request stopped")
        TestURLProtocol.configure(.block, onStart: { started.fulfill() }, onStop: { stopped.fulfill() })
        defer { TestURLProtocol.reset() }
        let session = makeTestURLSession()
        let transport = URLSessionHTTPTransport(session: session)
        let task = Task {
            try await transport.get(URL(string: "https://example.test/in-flight")!, headers: [:])
        }
        await fulfillment(of: [started], timeout: 1)

        task.cancel()
        let result = await task.result

        assertCancellation(result)
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testURLSessionTransportUsesAndroidReadTimeout() async throws {
        TestURLProtocol.configure(.succeed)
        defer { TestURLProtocol.reset() }
        let session = makeTestURLSession()
        let transport = URLSessionHTTPTransport(session: session)

        _ = try await transport.get(URL(string: "https://example.test/timeout")!, headers: [:])

        XCTAssertEqual(try XCTUnwrap(TestURLProtocol.startedRequests().first).timeoutInterval, 15)
    }
}

private func catalogTransport(chapters: String) -> StubTransport {
    StubTransport(responses: [
        "https://m.g-mh.org/manga/demo": response("<main data-mid=\"42\"></main>"),
        "https://v2.apikk.top/api/v2/manga/get?mid=42&mode=all": jsonResponse("{\"data\":{\"slug\":\"demo\",\"chapters\":\(chapters)}}")
    ])
}

private func mangaDataTransport(_ data: String) -> StubTransport {
    StubTransport(responses: [
        "https://m.g-mh.org/manga/demo": response("<main data-mid=\"42\"></main>"),
        "https://v2.apikk.top/api/v2/manga/get?mid=42&mode=all": jsonResponse("{\"data\":\(data)}")
    ])
}

private func chapterSource(imagesJSON: String) -> GmhComicSource {
    chapterSource(infoJSON: "{\"title\":\"Chapter\",\"images\":\(imagesJSON)}")
}

private func chapterSource(infoJSON: String) -> GmhComicSource {
    GmhComicSource(transport: StubTransport(responses: [
        "https://m.g-mh.org/manga/demo": response("<main data-mid=\"42\"></main>"),
        "https://v2.apikk.top/api/v2/manga/get?mid=42&mode=all": jsonResponse("{\"data\":{\"chapters\":[{\"id\":\"7\",\"attributes\":{\"title\":\"Chapter\",\"slug\":\"plain\"}}]}}"),
        "https://v2.apikk.top/api/v2/chapter/getinfo?m=42&c=7": jsonResponse("{\"data\":{\"info\":\(infoJSON)}}")
    ]))
}

private func response(_ body: String, statusCode: Int = 200) -> HTTPResponse {
    HTTPResponse(data: Data(body.utf8), statusCode: statusCode)
}

private func jsonResponse(_ body: String, statusCode: Int = 200) -> HTTPResponse {
    response(body, statusCode: statusCode)
}

private struct CapturedRequest: Sendable {
    let url: String
    let headers: [String: String]
}

private enum StubError: Error, Equatable {
    case offline
    case missingResponse(String)
}

private actor StubTransport: HTTPTransport {
    private let responses: [String: HTTPResponse]
    private let failingURLs: Set<String>
    private var capturedRequests: [CapturedRequest] = []

    init(responses: [String: HTTPResponse], failingURLs: Set<String> = []) {
        self.responses = responses
        self.failingURLs = failingURLs
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let key = url.absoluteString
        capturedRequests.append(CapturedRequest(url: key, headers: headers))
        if failingURLs.contains(key) { throw StubError.offline }
        guard let response = responses[key] else { throw StubError.missingResponse(key) }
        return response
    }

    func requests() -> [CapturedRequest] {
        capturedRequests
    }
}

private func XCTAssertAsyncThrowsError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

private func makeTestURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TestURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func assertCancellation(
    _ result: Result<HTTPResponse, Error>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .failure(let error) = result else {
        return XCTFail("Expected cancellation", file: file, line: line)
    }
    let isCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
    XCTAssertTrue(isCancelled, "Unexpected error: \(error)", file: file, line: line)
}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    enum Behavior {
        case succeed
        case block
    }

    private static let lock = NSLock()
    private static var behavior = Behavior.succeed
    private static var requests: [URLRequest] = []
    private static var onStart: () -> Void = {}
    private static var onStop: () -> Void = {}

    static func configure(_ behavior: Behavior, onStart: @escaping () -> Void = {}, onStop: @escaping () -> Void = {}) {
        lock.lock()
        self.behavior = behavior
        self.onStart = onStart
        self.onStop = onStop
        requests = []
        lock.unlock()
    }

    static func reset() {
        configure(.succeed)
    }

    static func startedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let behavior = Self.behavior
        let onStart = Self.onStart
        Self.lock.unlock()
        onStart()

        guard behavior == .succeed else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        Self.lock.lock()
        let onStop = Self.onStop
        Self.lock.unlock()
        onStop()
    }
}
