import Foundation
import XCTest
@testable import ComicCore

final class LiumanhuaSourceTests: XCTestCase {
    private let cards = """
    <div class="cy_list_mh"><ul><li><a href="/302262" class="pic"><img src="https://img.test/cover.jpg" alt="错误标题"></a></li><li class="title"><a href="/302262">可爱&amp;过敏原</a></li><li class="zuozhe">状态：连载中</li><li class="biaoqian"><a>恋爱</a></li></ul></div>
    <div class="rd-guess__comic"><a href="/999">推荐漫画</a></div>
    """

    func testLatestParsesOnlyScopedCardsAndUsesCategoryPagination() async throws {
        let transport = LiumanhuaTransport(["https://www.liumanhua.com/category/page/2": .html(cards)])
        let source = LiumanhuaComicSource(transport: transport)

        let comics = try await source.latest(page: 2)

        XCTAssertEqual(comics, [.init(sourceId: "liumanhua", comicId: "liumanhua:302262", title: "可爱&过敏原", coverUrl: "https://img.test/cover.jpg", subtitle: "连载中", tags: ["恋爱"])])
        let recorded = await transport.requests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.1["Referer"], "https://www.liumanhua.com/")
        XCTAssertEqual(request.1["Accept-Encoding"], "gzip")
    }

    func testFiltersSkipPaidGroupAndCategoryUsesFirstSupportedSelection() async throws {
        let html = filter("分类", "国产漫画", "/category/list/1") + filter("标签", "热血", "/category/tags/2572") + filter("资费", "免费", "/category/pay/1") + filter("进度", "完结", "/category/finish/2") + "<div class='cy_list_mh'></div>"
        let transport = LiumanhuaTransport([
            "https://www.liumanhua.com/category": .html(html),
            "https://www.liumanhua.com/category/tags/2572/page/3": .html(cards)
        ])
        let source = LiumanhuaComicSource(transport: transport)
        let groups = try await source.filterGroups()
        XCTAssertEqual(groups.map(\.key), ["classification", "subject", "state"])
        XCTAssertEqual(groups.map(\.label), ["分类", "题材", "状态"])
        XCTAssertEqual(groups[1].options[1], .init(label: "热血", value: "/tags/2572"))

        let result = try await source.category(filters: ["classification": "all", "subject": "/tags/2572", "state": "/finish/2"], page: 3)
        XCTAssertEqual(result.count, 1)
    }

    func testDetailIncludesOnlyItsCatalogFromTheSameDocument() async throws {
        let html = """
        <div class="cy_info_cover"><img data-original="/cover.jpg"></div><div class="cy_title"><h1>可爱过敏原</h1></div>
        <span>作者：稚楚</span><span class="cy_type"><a>恋爱</a></span><span>状态：连载中</span><span>最新：第119话</span>
        <p id="comic-description">简介&hellip;</p><div class="cy_plist"><ul>
        <li class="chapter__item"><a href="/302262/217344.html"><p>第119话</p></a></li>
        <li class="chapter__item"><a href="/302262/217343.html">第118话</a></li>
        <li class="chapter__item"><a href="/302262/217344.html">重复</a></li></ul></div>
        <div class="rd-guess__comic"><li class="chapter__item"><a href="/999/1.html">推荐章节</a></li></div>
        """
        let transport = LiumanhuaTransport(["https://www.liumanhua.com/302262": .html(html)])
        let detail = try await LiumanhuaComicSource(transport: transport).detail(comicId: "liumanhua:302262")

        XCTAssertEqual(detail.summary, .init(sourceId: "liumanhua", comicId: "liumanhua:302262", title: "可爱过敏原", coverUrl: "https://www.liumanhua.com/cover.jpg", subtitle: "稚楚", tags: ["恋爱"]))
        XCTAssertEqual(detail.status, "连载中")
        XCTAssertEqual(detail.description, "简介…")
        XCTAssertEqual(detail.latestChapter, "第119话")
        XCTAssertEqual(detail.chapters.map(\.chapterId), ["217344", "217343"])
        XCTAssertEqual(detail.chapters.map(\.chapterSlot), [0, 1])
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testCatalogFallbackRequiresMatchingOnlineReadingURL() async throws {
        let fallback = "<div class='cy_title'><h1>漫画</h1></div><div class='cy_kan'><a href='/302262/217344.html'>在线阅读</a></div><div class='rd-guess__comic'><a href='/999/1.html'>推荐</a></div>"
        let wrong = "<div class='cy_title'><h1>漫画</h1></div><div class='cy_kan'><a href='/999/1.html'>在线阅读</a></div>"
        let transport = LiumanhuaTransport([
            "https://www.liumanhua.com/302262": [.html(fallback), .html(wrong)]
        ])
        let source = LiumanhuaComicSource(transport: transport)

        let chapters = try await source.chapters(comicId: "302262")
        XCTAssertEqual(chapters, [.init(chapterId: "217344", title: "在线阅读", url: "https://www.liumanhua.com/302262/217344.html")])
        do { _ = try await source.chapters(comicId: "302262"); XCTFail("错误漫画的在线阅读不应回退") }
        catch { XCTAssertTrue(error.localizedDescription.contains("目录")) }
    }

    func testChapterDecryptsOpenSSLFixtureAndPreservesHTTPImages() async throws {
        // Generated independently with OpenSSL 3.0.2 AES-128-CBC/PKCS7, key 9S8$vJnU2ANeSRoF and IV 0123456789abcdef.
        let payload = "MDEyMzQ1Njc4OWFiY2RlZvWhelwjNs1fu1X1bfLj2ZeZVMl3H5UqUBUtX5nAe/ZNq475KqVbZ/8wjG60kTk4fSSA3SijtUbMEfKXQ5yf0rA0X5DP3caU6z+2xGpcl4n6YpiKgSnXRt3b175FA1kdbZFP1PP2kUnXsp4ihWqz+XMQZCVhsRwjI+cV4FEfseGideutb7En5EJQdczbHDvgToOiWZgxmHHMHc86QEY1Qrd2/w79Ur/+OITcdN0Z+YgTXj51beUjUcnq2qujX5JL4b93DvFQmgfZsotgrNIwl+0o//d5ihpIiqQtTJqYMLawjwPx4A66Y7h8g/F1ux+aLQ=="
        let html = "<title>第119话 - 六漫画</title><script>params='\(payload)'</script>"
        let transport = LiumanhuaTransport(["https://www.liumanhua.com/302262/217344.html": .html(html)])

        let page = try await LiumanhuaComicSource(transport: transport).chapter(url: "/302262/217344.html")

        XCTAssertEqual(page.chapterId, "217344")
        XCTAssertEqual(page.title, "第119话")
        XCTAssertEqual(page.imageUrls, ["https://s2.bzcdn.net/comic/1.jpg", "https://s2.bzcdn.net/comic/2.jpg"])
    }

    func testPayloadRejectsRestrictionsIdentityMismatchesAndInvalidImages() async throws {
        // Each fixed vector was independently generated with the OpenSSL command documented in testChapterDecryptsOpenSSLFixtureAndPreservesHTTPImages.
        let fixtures: [(String, String)] = [
            ("MDEyMzQ1Njc4OWFiY2RlZvWhelwjNs1fu1X1bfLj2ZeZVMl3H5UqUBUtX5nAe/ZN6gaCZt/0VAOuhB65nF3OZRdR5CoqKtmqO2+HsAuUC1KYYApqdC4P9hNeOa06DnUmOYigt5mCP6WLNDXFh9dDDAPBpP/Z3hUXHcCBp7cvIK2iC10OdkhXj93Mwmq1x1aoMFR/hrMxJOEhMZch9Q1TdA==", "限制"),
            ("MDEyMzQ1Njc4OWFiY2RlZvWhelwjNs1fu1X1bfLj2ZeZVMl3H5UqUBUtX5nAe/ZNCpXI74U76pY+WCjXVk/Qa6xQyH9mfYl1+iT7RUMgVyaLOEy/8AK03oXIwZ+4ALiOzbTqD+a82lfxp+kraAkeFGX/TQHZbSXEJCckaLxBAhZr48U/cBK4eJIRR9m+aeznf0Cdkqazp5GPEfZFCbjGTw==", "来源"),
            ("MDEyMzQ1Njc4OWFiY2RlZv7oFddcrhMZkB6L4wjSR6wfq955/WAeM3eBUCdS31vIkbk5+l0wi9vKYyNsCCxEVwcUlhbsWvoBb9TZB6SxF2U+rbl1iIZdaLKVbT7wJCHBIYUSZgbevFtwit7KNz26mhdhh4+AM5ERHeMreIp8JMl1Z+amh/wnDvUjF+nXB4jwXAI7ijezg3n8/jeg6CgSPQ==", "域名"),
            ("MDEyMzQ1Njc4OWFiY2RlZvWhelwjNs1fu1X1bfLj2ZeZVMl3H5UqUBUtX5nAe/ZN6gaCZt/0VAOuhB65nF3OZTEzQUx7XlIeJdwVIsIGmlcBAvjU+VkZn7NeViPKCVl52ao60HO1RkgIWH54SFo0yT2iXuZb3RR1wnjYc0aJrR+dn+tZ1xzBfJU+2otcXdJIHZYj54Y1y7+K5MW9tBN6pQ==", "漫画 ID"),
            ("MDEyMzQ1Njc4OWFiY2RlZvWhelwjNs1fu1X1bfLj2ZeZVMl3H5UqUBUtX5nAe/ZN6gaCZt/0VAOuhB65nF3OZQJ+1jwqMcJG0C3ohRPvFlD+9eA8LwYwR2x08bfc5ax0MsoGlkBnVQO/uVjms8CVp1SiZg+0MwBGZIPOAxCzFp+qfaE41+6XDvReH06G1U3UseYAEJXWeLC31F1QE6Q3EA==", "漫画 ID"),
            ("MDEyMzQ1Njc4OWFiY2RlZvWhelwjNs1fu1X1bfLj2ZeZVMl3H5UqUBUtX5nAe/ZN6gaCZt/0VAOuhB65nF3OZRdR5CoqKtmqO2+HsAuUC1IUWGSkQdaTFVGNl1yDyoshcpweRNA4kYSkWuq8r7MdnhUeiqtZe7L0EfbPNWgWfOs41ShASwRiLD5AuWsdyQoIDnQekCvPnJkay7Sd3IsDdw==", "章节 ID"),
            ("MDEyMzQ1Njc4OWFiY2RlZvWhelwjNs1fu1X1bfLj2ZeZVMl3H5UqUBUtX5nAe/ZN6gaCZt/0VAOuhB65nF3OZRdR5CoqKtmqO2+HsAuUC1IUWGSkQdaTFVGNl1yDyoshX4h7oxS6yro2filYX8UvqLC+J/R+7KLsSDPWsODFwldpoWIJjTz8Tlu1UCXDNCRxjCXn77YDglTq/sPRan/Ngw==", "章节 ID"),
            ("MDEyMzQ1Njc4OWFiY2RlZvWhelwjNs1fu1X1bfLj2ZeZVMl3H5UqUBUtX5nAe/ZN6gaCZt/0VAOuhB65nF3OZRdR5CoqKtmqO2+HsAuUC1IUWGSkQdaTFVGNl1yDyoshlFhMURJopKAX6daDBHgOKiZ2XJAe9ZdtRncUTWdAKqDi7bvtbuT3fKHvFRsBEriJ", "图片地址"),
            ("MDEyMzQ1Njc4OWFiY2RlZvWhelwjNs1fu1X1bfLj2ZeZVMl3H5UqUBUtX5nAe/ZN6gaCZt/0VAOuhB65nF3OZRdR5CoqKtmqO2+HsAuUC1IUWGSkQdaTFVGNl1yDyoshlFhMURJopKAX6daDBHgOKpsoR9q83RprgVuT6ORc66I=", "正文图片")
        ]
        for (payload, message) in fixtures {
            do { _ = try await LiumanhuaComicSource.decryptPayload(Data(base64Encoded: payload)!, expectedComicId: "302262", expectedChapterId: "217344"); XCTFail("应拒绝 \(message)") }
            catch { XCTAssertTrue(error.localizedDescription.contains(message), "\(error)") }
        }
    }

    func testSearchIsUnsupportedWithoutNetwork() async throws {
        let transport = LiumanhuaTransport([String: HTTPResponse]())
        let source = LiumanhuaComicSource(transport: transport)
        XCTAssertFalse(source.supportsSearch)
        do { _ = try await source.search(keyword: "可爱过敏原", page: 1); XCTFail("搜索不应成功") }
        catch { XCTAssertTrue(error.localizedDescription.contains("不支持搜索")) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testGenericH1ShellHTTPFailureAndCancellationAreRejected() async throws {
        let shell = "<html><h1>Access denied</h1></html>"
        let transport = LiumanhuaTransport([
            "https://www.liumanhua.com/category": .html(shell),
            "https://www.liumanhua.com/bad": .html(shell)
        ])
        let source = LiumanhuaComicSource(transport: transport)
        do { _ = try await source.latest(page: 1); XCTFail("错误壳不应作为空列表") } catch {}
        do { _ = try await source.detail(comicId: "bad"); XCTFail("通用 h1 不应作为详情") } catch {}

        let failed = LiumanhuaComicSource(transport: LiumanhuaTransport(["https://www.liumanhua.com/category": .html(cards, status: 503)]))
        do { _ = try await failed.latest(page: 1); XCTFail("HTTP 失败不应成功") }
        catch { XCTAssertEqual(error as? HTTPTransportError, .invalidStatusCode(503)) }
        do { _ = try await LiumanhuaComicSource(transport: LiumanhuaCancelledTransport()).latest(page: 1); XCTFail("取消不应成功") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func filter(_ name: String, _ option: String, _ path: String) -> String {
        "<div class=\"cy_tag\"><span>\(name)</span><ul><li><a href=\"/category/\">全部</a></li><li><a href=\"\(path)\">\(option)</a></li></ul></div>"
    }
}

private actor LiumanhuaTransport: HTTPTransport {
    var responses: [String: [HTTPResponse]]
    var requests: [(String, [String: String])] = []
    init(_ responses: [String: HTTPResponse]) { self.responses = responses.mapValues { [$0] } }
    init(_ responses: [String: [HTTPResponse]]) { self.responses = responses }
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append((url.absoluteString, headers))
        guard var queue = responses[url.absoluteString], !queue.isEmpty else { throw URLError(.badURL) }
        let response = queue.removeFirst()
        responses[url.absoluteString] = queue
        return response
    }
}

private struct LiumanhuaCancelledTransport: HTTPTransport {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse { throw CancellationError() }
}
