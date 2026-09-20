import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ComicCore

final class DefaultDownloadImageFetcherTests: XCTestCase {
    private var tempDir: URL!
    private var server: LocalTestHTTPServer!
    private var destination: URL!
    // 1x1 transparent PNG
    private let pngBytes = Data([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
        0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
        0x42, 0x60, 0x82
    ])

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        destination = tempDir.appendingPathComponent("test_image.part")
        server = try LocalTestHTTPServer()
        server.start()
    }

    override func tearDownWithError() throws {
        server?.stop()
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testStreamingSuccessWithValidImage() async throws {
        server.route("/valid.png") { req in
            XCTAssertEqual(req.header("Referer"), "https://source.com/chapter1")
            return LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "image/png"],
                body: self.pngBytes
            )
        }

        let fetcher = DefaultDownloadImageFetcher()
        let result = try await fetcher.fetch(
            sourceId: "test_source",
            url: server.url(for: "/valid.png"),
            referer: "https://source.com/chapter1",
            destination: destination,
            check: {}
        )

        XCTAssertEqual(result.bytes, Int64(pngBytes.count))
        XCTAssertEqual(result.hash, DownloadModels.sha256Hex(pngBytes))
        let savedData = try Data(contentsOf: destination)
        XCTAssertEqual(savedData, pngBytes)
    }

    func testRejectsHTMLResponse() async throws {
        server.route("/error.html") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: Data("<html><body>502 Bad Gateway</body></html>".utf8)
            )
        }

        let fetcher = DefaultDownloadImageFetcher()
        do {
            _ = try await fetcher.fetch(
                sourceId: "test_source",
                url: server.url(for: "/error.html"),
                referer: "",
                destination: destination,
                check: {}
            )
            XCTFail("Should have rejected HTML")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testRejectsJSONResponse() async throws {
        server.route("/error.json") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: Data("{\"error\": \"not found\"}".utf8)
            )
        }

        let fetcher = DefaultDownloadImageFetcher()
        do {
            _ = try await fetcher.fetch(
                sourceId: "test_source",
                url: server.url(for: "/error.json"),
                referer: "",
                destination: destination,
                check: {}
            )
            XCTFail("Should have rejected JSON")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testRejectsHTMLBodyEvenWithImageContentType() async throws {
        server.route("/fake_image") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "image/jpeg"],
                body: Data("<!DOCTYPE html><html><body>Error</body></html>".utf8)
            )
        }

        let fetcher = DefaultDownloadImageFetcher()
        do {
            _ = try await fetcher.fetch(
                sourceId: "test_source",
                url: server.url(for: "/fake_image"),
                referer: "",
                destination: destination,
                check: {}
            )
            XCTFail("Should have rejected HTML body")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testRejectsTruncatedResponse() async throws {
        server.route("/truncated") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: [
                    "Content-Type": "image/png",
                    "Content-Length": "100"
                ],
                body: self.pngBytes.prefix(10) // Only 10 bytes instead of 100
            )
        }

        let fetcher = DefaultDownloadImageFetcher()
        do {
            _ = try await fetcher.fetch(
                sourceId: "test_source",
                url: server.url(for: "/truncated"),
                referer: "",
                destination: destination,
                check: {}
            )
            XCTFail("Should have rejected truncated response")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testRejectsUnsolicitedPartialResponse() async throws {
        server.route("/partial") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 206,
                headers: [
                    "Content-Type": "image/png",
                    "Content-Range": "bytes 0-10/67"
                ],
                body: self.pngBytes.prefix(10)
            )
        }

        let fetcher = DefaultDownloadImageFetcher()
        do {
            _ = try await fetcher.fetch(
                sourceId: "test_source",
                url: server.url(for: "/partial"),
                referer: "",
                destination: destination,
                check: {}
            )
            XCTFail("Should have rejected 206 partial response")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testRejectsCorruptOrNonImageBytes() async throws {
        server.route("/corrupt") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/octet-stream"],
                body: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
            )
        }

        let fetcher = DefaultDownloadImageFetcher()
        do {
            _ = try await fetcher.fetch(
                sourceId: "test_source",
                url: server.url(for: "/corrupt"),
                referer: "",
                destination: destination,
                check: {}
            )
            XCTFail("Should have rejected non-image bytes")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testCancellationStopsRequestAndDeletesPartFile() async throws {
        server.route("/cancel") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "image/png"],
                body: self.pngBytes
            )
        }

        let fetcher = DefaultDownloadImageFetcher()
        do {
            _ = try await fetcher.fetch(
                sourceId: "test_source",
                url: server.url(for: "/cancel"),
                referer: "",
                destination: destination,
                check: {
                    throw DownloadError.taskCancelled
                }
            )
            XCTFail("Should have thrown taskCancelled")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testDecodesManwaEncryptedImage() async throws {
        // Standard Manwa test vector from Android baseline
        guard let payload = Data(base64Encoded: "AAECAwQFBgcICQoLDA0OD54Tk4Nv+8l3Uh1THnnKXglPAH8cC/Tv25bOvDH6oRQArf7/DrKbyeVJ4noUr0XJwZLp/D3rGO6sUAtVnQsw81HqEsIN/dDPOSp+6DzeooBM"),
              let expected = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9AAAAABJRU5ErkJggg==") else {
            XCTFail("Invalid base64 test vector")
            return
        }

        server.route("/manwa.img") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/octet-stream"],
                body: payload
            )
        }

        let fetcher = DefaultDownloadImageFetcher()
        let result = try await fetcher.fetch(
            sourceId: "manwa",
            url: server.url(for: "/manwa.img"),
            referer: "",
            destination: destination,
            check: {}
        )

        XCTAssertEqual(result.bytes, Int64(expected.count))
        let savedData = try Data(contentsOf: destination)
        XCTAssertEqual(savedData, expected)
    }
}
