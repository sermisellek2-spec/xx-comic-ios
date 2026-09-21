import Foundation
import XCTest
@testable import ComicCore

final class EpubReaderResourceTests: XCTestCase {
    private let id = "A2DA4DA0-271B-4B86-86E4-814D4DD6249B"
    private let host = "a2da4da0-271b-4b86-86e4-814d4dd6249b"

    func testGeneratedURLRoundTripsLiteralZIPNamesAndFragment() throws {
        let path = "OEBPS/文+字%20 空格.xhtml"
        let url = try EpubReaderResource.url(bookID: id, path: path, fragment: "引言")
        XCTAssertEqual(url.absoluteString, "xxcomic-book://\(host)/OEBPS/%E6%96%87+%E5%AD%97%2520%20%E7%A9%BA%E6%A0%BC.xhtml#%E5%BC%95%E8%A8%80")
        XCTAssertEqual(try EpubReaderResource.path(from: url, bookID: id), path)
        XCTAssertEqual(try EpubReaderResource.path(from: url, bookID: host), path)
        for literal in ["OPS/%2f.xhtml", "OPS/%2e%2e/a", "OPS/100%.css", "OPS/a?#.svg"] {
            let generated = try EpubReaderResource.url(bookID: id, path: literal)
            XCTAssertEqual(try EpubReaderResource.path(from: generated, bookID: id), literal)
        }
    }

    func testGenerationRejectsInvalidBookAndNoncanonicalZIPPaths() {
        XCTAssertThrowsError(try EpubReaderResource.url(bookID: "not-a-uuid", path: "OPS/a"))
        for path in ["", "/OPS/a", "OPS/", "OPS//a", "OPS/./a", "OPS/../a", ".", "..", "OPS\\a", "OPS/a\0", "https:a"] {
            XCTAssertThrowsError(try EpubReaderResource.url(bookID: id, path: path), path)
        }
    }

    func testParserRejectsForeignBookSchemesAndAuthorityTricks() throws {
        for raw in [
            "xxcomic-book://b2da4da0-271b-4b86-86e4-814d4dd6249b/OPS/a",
            "https://\(host)/OPS/a", "xxcomic-epub://\(host)/OPS/a", "XXCOMIC-BOOK://\(host)/OPS/a",
            "xxcomic-book://\(id)/OPS/a", "xxcomic-book://\(host).evil/OPS/a",
            "xxcomic-book://%612da4da0-271b-4b86-86e4-814d4dd6249b/OPS/a",
            "xxcomic-book://\(host)@evil/OPS/a", "xxcomic-book://evil@\(host)/OPS/a",
            "xxcomic-book://user:pass@\(host)/OPS/a", "xxcomic-book://@\(host)/OPS/a",
            "xxcomic-book://\(host):80/OPS/a", "xxcomic-book://\(host)/OPS/a?query",
            "xxcomic-book://\(host)/OPS/a?"
        ] {
            let url = try XCTUnwrap(URL(string: raw), raw)
            XCTAssertThrowsError(try EpubReaderResource.path(from: url, bookID: id), raw)
        }
        let url = try XCTUnwrap(URL(string: "xxcomic-book://\(host)/OPS/a"))
        XCTAssertThrowsError(try EpubReaderResource.path(from: url, bookID: "invalid"))
    }

    func testParserRejectsEncodedSeparatorsDotsAndNoncanonicalPaths() throws {
        for path in ["", "/", "//OPS/a", "/OPS/", "/OPS//a", "/OPS/./a", "/OPS/../a",
                     "/OPS/%2e/a", "/OPS/%2E%2e/a", "/OPS/.%2e/a", "/OPS/%2fetc",
                     "/OPS/a%2Fb", "/OPS/a%5cb", "/OPS/%5Ca", "/OPS/a%00b", "/C%3A/a"] {
            let url = try XCTUnwrap(URL(string: "xxcomic-book://\(host)" + path), path)
            XCTAssertThrowsError(try EpubReaderResource.path(from: url, bookID: id), path)
        }
    }

    func testParserDecodesOnceAndIgnoresFragment() throws {
        let url = try XCTUnwrap(URL(string: "xxcomic-book://\(host)/OPS/a+b%2520.xhtml#part%2F..%2Ftwo"))
        XCTAssertEqual(try EpubReaderResource.path(from: url, bookID: id), "OPS/a+b%20.xhtml")
    }

    func testParserRejectsEmptyPortDelimiter() throws {
        let url = try XCTUnwrap(URL(string: "xxcomic-book://\(host):/OPS/a"))
        print("URL_DIAGNOSTIC input=xxcomic-book://\(host):/OPS/a absolute=\(url.absoluteString) components=\(String(describing: URLComponents(url: url, resolvingAgainstBaseURL: false)))")
        XCTAssertThrowsError(try EpubReaderResource.path(from: url, bookID: id))
    }

    func testManifestMIMEWinsOnlyForMatchingCanonicalZIPPath() {
        let publication = publication(manifest: [
            .init(id: "a", href: "OPS/a.xhtml", mediaType: "text/html", properties: ""),
            .init(id: "b", href: "OPS/文+字%20", mediaType: "image/svg+xml", properties: "")
        ])
        XCTAssertEqual(EpubReaderResource.mimeType(path: "OPS/a.xhtml", publication: publication), "text/html")
        XCTAssertEqual(EpubReaderResource.mimeType(path: "OPS/文+字%20", publication: publication), "image/svg+xml")
        XCTAssertEqual(EpubReaderResource.mimeType(path: "OPS/./a.xhtml", publication: publication), "application/xhtml+xml")
        XCTAssertEqual(EpubReaderResource.mimeType(path: "OPS/文+字 ", publication: publication), "application/octet-stream")
    }

    func testMIMEFallbackSupportsOnlyKnownExtensions() {
        let publication = publication(manifest: [])
        let cases = ["html": "text/html", "xhtml": "application/xhtml+xml", "css": "text/css",
                     "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif",
                     "webp": "image/webp", "svg": "image/svg+xml", "ttf": "font/ttf", "otf": "font/otf",
                     "woff": "font/woff", "woff2": "font/woff2", "js": "application/octet-stream",
                     "unknown": "application/octet-stream"]
        for (ext, mime) in cases {
            XCTAssertEqual(EpubReaderResource.mimeType(path: "OPS/item." + ext.uppercased(), publication: publication), mime)
        }
        XCTAssertEqual(EpubReaderResource.mimeType(path: "OPS/noextension", publication: publication), "application/octet-stream")
    }

    private func publication(manifest: [EpubPublication.ManifestItem]) -> EpubPublication {
        EpubPublication(title: "", author: "", description: "", language: "", opfPath: "OPS/content.opf",
                        coverEntry: nil, manifest: manifest, spine: [], navItems: [], isFixedLayout: false,
                        isPurePictureEpub: false, isReflowableText: true, hasDrm: false,
                        hasFontObfuscation: false, unsupportedReason: nil)
    }
}
