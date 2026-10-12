import XCTest
import ZIPFoundation
@testable import ComicCore

final class EpubComicContentTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }; return url
    }
    private func archive(_ body: String) throws -> URL {
        let url = try directory().appendingPathComponent("comic.epub")
        let files = ["META-INF/container.xml": "<container><rootfile full-path='OPS/book.opf'/></container>",
                     "OPS/book.opf": "<package><metadata/><manifest><item id='a' href='a.xhtml' media-type='application/xhtml+xml'/><item id='image' href='image.png' media-type='image/png'/></manifest><spine><itemref idref='a'/></spine></package>",
                     "OPS/a.xhtml": body, "OPS/image.png": "READABLE_IMAGE"]
        let zip = try Archive(url: url, accessMode: .create)
        for (path, value) in files {
            let data = Data(value.utf8)
            try zip.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, count in
                data.subdata(in: Int(position)..<min(Int(position) + count, data.count))
            }
        }
        return url
    }
    func testRealImageWrapperImportsAndReadsImageWithoutRenderingMarkup() async throws {
        let input = try archive("<html><head><title>漫画书名</title><style>body{margin:0}</style></head><body><!--说明--><img alt='第1页' src='image.png'/>&nbsp;</body></html>")
        let library = try LocalLibrary(directory: directory())
        let book = try library.importEpub(title: "漫画", archive: input) { try Data(contentsOf: $0) == Data("READABLE_IMAGE".utf8) }
        let source = LocalComicSource(library: library), chapters = try await source.chapters(comicId: book.id)
        let page = try await source.chapter(url: chapters[0].url)
        XCTAssertEqual(page.imageUrls.count, 1)
        XCTAssertEqual(try library.epubImageData(pageURL: XCTUnwrap(URL(string: page.imageUrls[0]))), Data("READABLE_IMAGE".utf8))
    }
    func testTextAndMixedWrappersRejectBeforeProbingWithoutChangingOriginalOrShelf() throws {
        let library = try LocalLibrary(directory: directory())
        for body in ["<p>小说正文</p>", "<p>短标题也不能丢掉</p><img src='image.png'/>",
                     "<img src='image.png'/><p>&#x4e2d;&#25991;</p>",
                     "<img src='image.png'/><img src='image.png'/>",
                     "<img src='image.png'/>" + String(repeating: " ", count: 1024 * 1024) + "<p>前缀检查之外的文字</p>"] {
            let input = try archive(body), original = try Data(contentsOf: input)
            XCTAssertThrowsError(try library.importEpub(title: "拒绝", archive: input) { _ in XCTFail("不完整的内容不能发布"); return true }) {
                XCTAssertEqual($0 as? LocalLibraryError, .unsupportedTextContent)
            }
            XCTAssertTrue(try library.books().isEmpty)
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }
    func testLegacySingleImageWithTextCannotSilentlyLoseItsText() async throws {
        let input = try archive("<img src='image.png'/><p>旧版本曾把这一段丢掉</p>")
        let library = try LocalLibrary(directory: directory())
        let book = try LegacyEpubFixture.persist(library: library, archive: input, title: "旧混排书")
        XCTAssertTrue(try XCTUnwrap(book.epub).isPurePictureEpub)
        let folder = library.directory.appendingPathComponent(book.id), metadata = try Data(contentsOf: folder.appendingPathComponent("book.json"))
        let source = LocalComicSource(library: library), chapters = try await source.chapters(comicId: book.id)
        do { _ = try await source.chapter(url: chapters[0].url); XCTFail("不能丢文字后继续图片阅读") }
        catch { XCTAssertEqual(error as? LocalLibraryError, .unsupportedTextContent) }
        XCTAssertEqual(try library.book(id: book.id), book)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("book.json")), metadata)
    }
    func testSvgImageAndWhitespaceAreSupportedWhileSvgTextIsRejected() throws {
        XCTAssertNoThrow(try EpubComicContent.validateMarkup("<svg><title>页名</title><image xlink:href='page.png'/></svg>&#160;\n", expectedImages: 1))
        XCTAssertThrowsError(try EpubComicContent.validateMarkup("<svg><image href='page.png'/><text>正文</text></svg>", expectedImages: 1))
        XCTAssertThrowsError(try EpubComicContent.validateMarkup("<img src='page.png'/><iframe src='text.xhtml'/>", expectedImages: 1))
    }
}
