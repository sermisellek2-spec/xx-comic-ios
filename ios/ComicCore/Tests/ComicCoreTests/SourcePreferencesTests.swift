import XCTest
@testable import ComicCore

final class SourcePreferencesTests: XCTestCase {
    func testOrderDropsRemovedAndDuplicatesAndAppendsNewSources() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set(#"[null,42,{},"","b","b","removed"]"#, forKey: "source.order")
        let store = SourcePreferences(defaults: defaults, defaultIDs: ["a", "b", "c"])
        XCTAssertEqual(store.orderedIDs, ["b", "a", "c"])
        store.setOrder(["c", "b", "a"])
        XCTAssertEqual(SourcePreferences(defaults: defaults, defaultIDs: ["a", "b", "c", "d"]).orderedIDs, ["c", "b", "a", "d"])
        XCTAssertEqual(SourcePreferences(defaults: defaults, defaultIDs: ["a", "c"]).orderedIDs, ["c", "a"])
    }
    func testDisablingPreservesPositionAcrossReloadAndResetLeavesSwitchesUnchanged() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = SourcePreferences(defaults: defaults, defaultIDs: ["a", "b", "c"])
        store.setOrder(["c", "b", "a"])
        store.setEnabled(false, id: "b")
        XCTAssertEqual(store.enabledIDs, ["c", "a"])
        let reopened = SourcePreferences(defaults: defaults, defaultIDs: ["a", "b", "c"])
        XCTAssertEqual(reopened.orderedIDs, ["c", "b", "a"])
        XCTAssertEqual(reopened.enabledIDs, ["c", "a"])
        reopened.setEnabled(true, id: "b")
        XCTAssertEqual(reopened.enabledIDs, ["c", "b", "a"])
        for id in ["a", "b", "c"] { reopened.setEnabled(false, id: id) }
        XCTAssertEqual(reopened.enabledIDs, [])
        reopened.resetOrder()
        XCTAssertEqual(reopened.orderedIDs, ["a", "b", "c"])
        XCTAssertEqual(reopened.enabledIDs, [])
    }
    func testInvalidPreferencesKeepDefaultsAndCannotCreatePhantomSource() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set("broken", forKey: "source.order")
        let store = SourcePreferences(defaults: defaults, defaultIDs: ["a", "b"])
        XCTAssertEqual(store.enabledIDs, ["a", "b"])
        store.setOrder(["deleted", "b", "b"])
        store.setEnabled(true, id: "deleted")
        XCTAssertEqual(store.enabledIDs, ["b", "a"])
        XCTAssertNil(defaults.object(forKey: "source.deleted.enabled"))
    }

    func testExportAndImportConfigJson() throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = SourcePreferences(defaults: defaults, defaultIDs: ["baozimh", "mh160", "gmh"])
        store.setOrder(["mh160", "baozimh", "gmh"])
        store.setEnabled(false, id: "gmh")

        let json = store.exportConfig(sources: [
            (id: "baozimh", name: "包子漫画", domain: "cn.dzmanga.com", referer: "https://cn.dzmanga.com/"),
            (id: "mh160", name: "漫画160", domain: "www.mh160mh.com", referer: "https://www.mh160mh.com/"),
            (id: "gmh", name: "G社漫画", domain: "m.g-mh.org", referer: "https://m.g-mh.org/")
        ])

        XCTAssertTrue(json.contains("\"schema\" : \"xx-comic.sources\""))
        XCTAssertTrue(json.contains("\"version\" : 2"))

        // 测试在新 store 中导入
        let newDefaults = UserDefaults(suiteName: defaultsName + ".new")!
        defer { newDefaults.removePersistentDomain(forName: defaultsName + ".new") }
        let newStore = SourcePreferences(defaults: newDefaults, defaultIDs: ["baozimh", "mh160", "gmh"])

        let result = try newStore.importConfig(jsonString: json)
        XCTAssertEqual(result.totalSources, 3)
        XCTAssertEqual(result.enabledCount, 2)
        XCTAssertEqual(result.disabledCount, 1)
        XCTAssertTrue(result.orderUpdated)

        XCTAssertEqual(newStore.orderedIDs, ["mh160", "baozimh", "gmh"])
        XCTAssertEqual(newStore.enabledIDs, ["mh160", "baozimh"])
        XCTAssertFalse(newStore.isEnabled("gmh"))

        // 校验非法 schema
        XCTAssertThrowsError(try newStore.importConfig(jsonString: #"{"schema": "unknown"}"#)) { error in
            XCTAssertEqual(error as? SourceConfigError, .invalidSchema)
        }
    }

    func testImportedConfigUpdatesSourceEndpointsAndHeaders() async throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = SourcePreferences(defaults: defaults, defaultIDs: ["baozimh", "mh160", "gmh", "mkzhan", "manwa", "mh18"])

        let customPackage = SourceExportPackage(
            sourceOrder: ["baozimh", "mh160", "gmh", "mkzhan", "manwa", "mh18"],
            sources: [
                SourceConfigItem(
                    id: "baozimh",
                    name: "自定义包子",
                    domain: "custom-baozi.test",
                    baseUrl: "https://custom-baozi.test",
                    referer: "https://custom-baozi.test/custom-referer/",
                    routes: [
                        "latest": "/custom-latest{pagePath}",
                        "search": "/custom-search?query={keyword}{pageQuery}",
                        "category": "/custom-classify?reg={region}",
                        "categoryApi": "/api/custom-classify?reg={region}&p={page}",
                        "detail": "/custom-comic/{comicId}"
                    ],
                    filters: [
                        "region.cn": "custom_cn",
                        "state.serial": "custom_serial"
                    ]
                ),
                SourceConfigItem(
                    id: "mh160",
                    name: "自定义160",
                    domain: "custom-160.test",
                    baseUrl: "https://custom-160.test",
                    referer: "https://custom-160.test/ref/",
                    routes: [
                        "latest": "/custom-all/{pagePath}",
                        "search": "/custom-search.aspx?k={keyword}{pageQuery}",
                        "category": "/custom-category/{filterPath}/{pagePath}",
                        "detail": "/custom-detail/{comicId}/"
                    ]
                ),
                SourceConfigItem(
                    id: "gmh",
                    name: "自定义G社",
                    domain: "custom-gmh.test",
                    baseUrl: "https://custom-gmh.test",
                    referer: "https://custom-gmh.test/ref/",
                    routes: [
                        "latest": "/custom-manga{pagePath}",
                        "search": "/custom-s/{keyword}",
                        "category": "/custom-manga{genrePath}{pagePath}",
                        "detail": "/custom-manga/{comicId}",
                        "chapter": "/custom-manga/{comicId}/{chapterSlug}",
                        "mangaApi": "https://api.custom-gmh.test/manga/{mid}",
                        "chapterApi": "https://api.custom-gmh.test/chapter/{mid}/{chapterId}"
                    ],
                    filters: [
                        "genre.kr": "custom_kr"
                    ]
                ),
                SourceConfigItem(
                    id: "mkzhan",
                    name: "自定义漫客栈",
                    domain: "custom-mkzhan.test",
                    baseUrl: "https://custom-mkzhan.test",
                    referer: "https://custom-mkzhan.test/ref/",
                    routes: [
                        "latest": "/custom-category{query}",
                        "search": "/custom-find/?keyword={keyword}",
                        "category": "/custom-category{query}",
                        "detail": "/custom-comic/{comicId}/",
                        "chapterApi": "https://api.custom-mkzhan.test/chapter?cid={comicId}&chid={chapterId}"
                    ]
                ),
                SourceConfigItem(
                    id: "manwa",
                    name: "自定义漫蛙",
                    domain: "custom-manwa.test",
                    baseUrl: "https://custom-manwa.test",
                    referer: "https://custom-manwa.test/ref/",
                    routes: [
                        "search": "/api/custom-search?keyword={keyword}&page={page}",
                        "category": "/api/custom-cate",
                        "detail": "/custom-comic/{comicId}",
                        "chapters": "/api/custom-comic/{comicId}/chapters",
                        "chapterInfo": "/api/custom-comic/chapter/{chapterId}",
                        "images": "/api/custom-comic/images/{chapterId}?page={page}&image_source={imageSource}",
                        "imageSource": "https://cdn.custom-manwa.test"
                    ]
                ),
                SourceConfigItem(
                    id: "mh18",
                    name: "自定义18",
                    domain: "custom-18.test",
                    baseUrl: "https://custom-18.test",
                    referer: "https://custom-18.test/ref/",
                    routes: [
                        "search": "/custom-s/{keyword}{pageQuery}",
                        "category": "/custom-manga{genrePath}{pagePath}",
                        "detail": "/custom-manga/{comicId}"
                    ],
                    filters: [
                        "genre.kr": "custom_hanman"
                    ]
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let json = String(data: try encoder.encode(customPackage), encoding: .utf8)!
        let importResult = try store.importConfig(jsonString: json)
        XCTAssertEqual(importResult.totalSources, 6)

        // 1. Baozi verifies custom baseUrl, referer, search route, categoryApi route & filter
        let baoziConfig = try XCTUnwrap(store.config(for: "baozimh"))
        let baoziTransport = RecordingTransport(responseBody: #"<div class="comics-list"></div>"#)
        let baoziSource = BaoziComicSource(config: baoziConfig, transport: baoziTransport)
        _ = try? await baoziSource.search(keyword: "naruto", page: 2)
        let baoziURLs = await baoziTransport.requestedURLs
        let baoziHeaders = await baoziTransport.requestedHeaders
        XCTAssertEqual(baoziURLs.first?.absoluteString, "https://custom-baozi.test/custom-search?query=naruto&page=2")
        XCTAssertEqual(baoziHeaders.first?["Referer"], "https://custom-baozi.test/custom-referer/")

        let baoziCatTransport = RecordingTransport(responseBody: #"{"items":[]}"#)
        let baoziCatSource = BaoziComicSource(config: baoziConfig, transport: baoziCatTransport)
        _ = try? await baoziCatSource.category(filters: ["region": "cn"], page: 2)
        let baoziCatURLs = await baoziCatTransport.requestedURLs
        XCTAssertTrue(baoziCatURLs.first?.absoluteString.contains("/api/custom-classify?reg=custom_cn&p=2") == true)

        // 2. Mh160 verifies custom baseUrl, referer, latest & search routes
        let mh160Config = try XCTUnwrap(store.config(for: "mh160"))
        let mh160Transport = RecordingTransport(responseBody: #"<ul class="mh-search-list"></ul>"#)
        let mh160Source = Mh160ComicSource(config: mh160Config, transport: mh160Transport)
        _ = try? await mh160Source.latest(page: 3)
        let mh160URLs = await mh160Transport.requestedURLs
        let mh160Headers = await mh160Transport.requestedHeaders
        XCTAssertEqual(mh160URLs.first?.absoluteString, "https://custom-160.test/custom-all/3.html")
        XCTAssertEqual(mh160Headers.first?["Referer"], "https://custom-160.test/ref/")

        // 3. Gmh verifies custom baseUrl, search & category routes with filter
        let gmhConfig = try XCTUnwrap(store.config(for: "gmh"))
        let gmhTransport = RecordingTransport(responseBody: #"<div></div>"#)
        let gmhSource = GmhComicSource(config: gmhConfig, transport: gmhTransport)
        _ = try? await gmhSource.latest(page: 2)
        let gmhURLs = await gmhTransport.requestedURLs
        let gmhHeaders = await gmhTransport.requestedHeaders
        XCTAssertEqual(gmhURLs.first?.absoluteString, "https://custom-gmh.test/custom-manga/page/2")
        XCTAssertEqual(gmhHeaders.first?["Referer"], "https://custom-gmh.test/ref/")

        // 4. Mkzhan verifies custom category & search routes
        let mkzhanConfig = try XCTUnwrap(store.config(for: "mkzhan"))
        let mkzhanTransport = RecordingTransport(responseBody: #"<div class="cate-comic-list"></div>"#)
        let mkzhanSource = MkzhanComicSource(config: mkzhanConfig, transport: mkzhanTransport)
        _ = try? await mkzhanSource.search(keyword: "hero", page: 1)
        let mkzhanURLs = await mkzhanTransport.requestedURLs
        let mkzhanHeaders = await mkzhanTransport.requestedHeaders
        XCTAssertEqual(mkzhanURLs.first?.absoluteString, "https://custom-mkzhan.test/custom-find/?keyword=hero")
        XCTAssertEqual(mkzhanHeaders.first?["Referer"], "https://custom-mkzhan.test/ref/")

        // 5. Manwa verifies custom search route & baseUrl
        let manwaConfig = try XCTUnwrap(store.config(for: "manwa"))
        let manwaTransport = RecordingTransport(responseBody: #"{"data":{"list":[]}}"#)
        let manwaSource = ManwaComicSource(config: manwaConfig, transport: manwaTransport)
        _ = try? await manwaSource.search(keyword: "dragon", page: 2)
        let manwaURLs = await manwaTransport.requestedURLs
        let manwaHeaders = await manwaTransport.requestedHeaders
        XCTAssertEqual(manwaURLs.first?.absoluteString, "https://custom-manwa.test/api/custom-search?keyword=dragon&page=2")
        XCTAssertEqual(manwaHeaders.first?["Referer"], "https://custom-manwa.test/ref/")

        // 6. Mh18 verifies custom search route & category with genre filter
        let mh18Config = try XCTUnwrap(store.config(for: "mh18"))
        let mh18Transport = RecordingTransport(responseBody: #"<div class="manga-list"></div>"#)
        let mh18Source = Mh18ComicSource(config: mh18Config, transport: mh18Transport)
        _ = try? await mh18Source.category(filters: ["genre": "kr"], page: 2)
        let mh18URLs = await mh18Transport.requestedURLs
        let mh18Headers = await mh18Transport.requestedHeaders
        XCTAssertEqual(mh18URLs.first?.absoluteString, "https://custom-18.test/custom-manga-genre/custom_hanman/page/2")
        XCTAssertEqual(mh18Headers.first?["Referer"], "https://custom-18.test/ref/")
    }

    private let defaultsName = "SourcePreferencesTests." + UUID().uuidString
    private func makeDefaults() -> UserDefaults { UserDefaults(suiteName: defaultsName)! }
}

private actor RecordingTransport: HTTPTransport {
    var requestedURLs: [URL] = []
    var requestedHeaders: [[String: String]] = []
    let responseBody: String

    init(responseBody: String = "<html><body></body></html>") {
        self.responseBody = responseBody
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requestedURLs.append(url)
        requestedHeaders.append(headers)
        return HTTPResponse(data: Data(responseBody.utf8), statusCode: 200, headers: ["Content-Type": "text/html"])
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
        requestedURLs.append(url)
        requestedHeaders.append(headers)
        return HTTPResponse(data: Data(responseBody.utf8), statusCode: 200, headers: ["Content-Type": "text/html"])
    }
}

