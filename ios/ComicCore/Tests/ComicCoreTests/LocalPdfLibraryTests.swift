import Foundation
import XCTest
@testable import ComicCore

final class LocalPdfLibraryTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func source() throws -> URL {
        let url = try directory().appendingPathComponent("original.pdf")
        try Data("%PDF-boundary fixture, not a decodable PDF".utf8).write(to: url)
        return url
    }
    private func publication(_ count: Int = 2) -> PdfPublication {
        PdfPublication(pages: (0..<count).map { .init(width: 600 + Double($0), height: 800) })
    }
    private func imported(_ library: LocalLibrary) throws -> LocalBook {
        try library.importPdf(title: "PDF", file: source(), inspect: { _ in self.publication() }, renderCover: { _ in nil })
    }
    func testCopyPublicationCoverAndOnDemandPagesSurviveReopen() async throws {
        let library = try LocalLibrary(directory: directory()), input = try source(), original = try Data(contentsOf: input)
        let book = try library.importPdf(title: "  文档  ", file: input, inspect: { owned in
            XCTAssertNotEqual(owned, input)
            XCTAssertEqual(owned.lastPathComponent, "content.pdf")
            XCTAssertEqual(try Data(contentsOf: owned), original)
            return self.publication()
        }, renderCover: { _ in Data("cover".utf8) })
        XCTAssertEqual(try Data(contentsOf: input), original)
        try FileManager.default.removeItem(at: input)
        let reopened = try LocalLibrary(directory: library.directory)
        XCTAssertEqual(try reopened.books(), [book])
        XCTAssertEqual(book.title, "文档")
        XCTAssertEqual(book.pages, ["pdf-0", "pdf-1"])
        XCTAssertEqual(book.chapters?.map(\.title), ["全本"])
        XCTAssertNil(book.epub)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(URL(string: reopened.summary(for: book).coverUrl))), Data("cover".utf8))
        let urls = try reopened.pageURLs(for: book)
        XCTAssertEqual(urls.map(\.absoluteString), ["xxcomic-pdf://page/\(book.id)/0", "xxcomic-pdf://page/\(book.id)/1"])
        XCTAssertEqual(try reopened.pdfPageData(pageURL: urls[1]) { owned, index in
            XCTAssertEqual(try Data(contentsOf: owned), original)
            return Data("page-\(index)".utf8)
        }, Data("page-1".utf8))
        let local = LocalComicSource(library: reopened)
        let chapters = try await local.chapters(comicId: book.id)
        let page = try await local.chapter(url: XCTUnwrap(chapters.first).url)
        XCTAssertEqual(page.imageUrls, urls.map(\.absoluteString))
        let detail = try await local.detail(comicId: book.id)
        XCTAssertEqual(detail.status, "PDF")
    }
    func testInvalidPublicationsAndFailureLeaveOnlyExistingBooks() throws {
        let library = try LocalLibrary(directory: directory()), book = try imported(library), input = try source()
        for value in [publication(0), publication(50_001), PdfPublication(pages: [.init(width: 0, height: 10)]),
                      PdfPublication(pages: [.init(width: .infinity, height: 10)]), PdfPublication(pages: [.init(width: 10, height: .nan)])] {
            XCTAssertThrowsError(try library.importPdf(title: "坏数据", file: input, inspect: { _ in value }, renderCover: { _ in nil }))
        }
        XCTAssertThrowsError(try library.importPdf(title: "失败", file: input, inspect: { _ in throw CocoaError(.fileReadCorruptFile) }, renderCover: { _ in nil }))
        XCTAssertThrowsError(try library.importPdf(title: "失败", file: input, inspect: { _ in self.publication() }, renderCover: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
        XCTAssertEqual(try library.books(), [book])
    }
    func testCancellationDuringCopyInspectionAndCoverCleansOnlyOwnStaging() async throws {
        let root = try directory(), library = try LocalLibrary(directory: root), book = try imported(library), input = try source()
        let unrelated = root.appendingPathComponent(".import-other")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        for phase in 0..<3 {
            let worker = Task.detached {
                let local = try LocalLibrary(directory: root, readChunk: { handle, count in
                    if phase == 0 { withUnsafeCurrentTask { $0?.cancel() } }
                    return try handle.read(upToCount: count)
                })
                return try local.importPdf(title: "取消", file: input, inspect: { _ in
                    if phase == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                    return PdfPublication(pages: [.init(width: 600, height: 800)])
                }, renderCover: { _ in
                    if phase == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                    return Data("cover".utf8)
                })
            }
            do { _ = try await worker.value; XCTFail("取消仍发布") } catch { XCTAssertTrue(error is CancellationError) }
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), Set([book.id, ".import-other"]))
    }
    func testPageURLAttacksAndOutOfRangeNeverReachRenderer() throws {
        let library = try LocalLibrary(directory: directory()), book = try imported(library)
        for text in ["file:///tmp/book.pdf", "xxcomic-epub://page/\(book.id)/0", "xxcomic-pdf://other/\(book.id)/0",
                     "xxcomic-pdf://user@page/\(book.id)/0", "xxcomic-pdf://page:80/\(book.id)/0",
                     "xxcomic-pdf://page/\(book.id)/0?x=1", "xxcomic-pdf://page/\(book.id)/0#x",
                     "xxcomic-pdf://page/\(book.id)/%30", "xxcomic-pdf://page/\(book.id)/-1",
                     "xxcomic-pdf://page/\(book.id)/2", "xxcomic-pdf://page/\(book.id)/999999999999999999999",
                     "xxcomic-pdf://page//0", "xxcomic-pdf://page/\(book.id)/0/extra"] {
            XCTAssertThrowsError(try library.pdfPageData(pageURL: XCTUnwrap(URL(string: text))) { _, _ in XCTFail("不安全地址进入渲染器: \(text)"); return Data() })
        }
    }
    func testEmptyPortNormalizationKeepsOwnedPageIdentity() throws {
        let library = try LocalLibrary(directory: directory()), book = try imported(library)
        let url = try XCTUnwrap(URL(string: "xxcomic-pdf://page:/\(book.id)/0"))
        if url.absoluteString == "xxcomic-pdf://page/\(book.id)/0" {
            var calls = 0
            let data = try library.pdfPageData(pageURL: url) { file, index in
                calls += 1
                XCTAssertEqual(file.lastPathComponent, "content.pdf")
                XCTAssertEqual(file.deletingLastPathComponent().lastPathComponent, book.id)
                XCTAssertEqual(index, 0)
                return Data([1])
            }
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(data, Data([1]))
        } else {
            XCTAssertThrowsError(try library.pdfPageData(pageURL: url) { _, _ in
                XCTFail("Unnormalized empty port reached renderer")
                return Data([1])
            })
        }
    }

    func testSourceAndOwnedSymlinksAreRejected() throws {
        let library = try LocalLibrary(directory: directory()), input = try source(), link = try directory().appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: input)
        XCTAssertThrowsError(try library.importPdf(title: "链接", file: link, inspect: { _ in XCTFail("链接被读取"); return self.publication() }, renderCover: { _ in nil }))
        for name in ["content.pdf", "book.json", "cover.bin"] {
            let book = try library.importPdf(title: "链接", file: input, inspect: { _ in self.publication() }, renderCover: { _ in Data([1]) })
            let target = library.directory.appendingPathComponent(book.id).appendingPathComponent(name)
            let outside = try directory().appendingPathComponent(name)
            try FileManager.default.moveItem(at: target, to: outside)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
            XCTAssertThrowsError(try library.book(id: book.id))
            XCTAssertThrowsError(try library.pdfPageData(pageURL: XCTUnwrap(URL(string: "xxcomic-pdf://page/\(book.id)/0"))) { _, _ in XCTFail("链接进入渲染器"); return Data() })
        }
    }
    func testPageLimitReopensAndOldJSONRemainsCompatible() throws {
        let library = try LocalLibrary(directory: directory())
        let book = try library.importPdf(title: "边界", file: source(), inspect: { _ in self.publication(50_000) }, renderCover: { _ in nil })
        XCTAssertEqual(try library.book(id: book.id), book)
        let old = Data("{\"id\":\"\(UUID().uuidString)\",\"title\":\"旧书\",\"createdAt\":0,\"pages\":[\"0.jpg\"]}".utf8)
        let decoded = try JSONDecoder().decode(LocalBook.self, from: old)
        XCTAssertNil(decoded.pdf)
        XCTAssertNil(decoded.epub)
        XCTAssertEqual(try library.pageURLs(for: decoded).first?.lastPathComponent, "0.jpg")
    }
    func testCorruptPersistedMetadataRejected() throws {
        let library = try LocalLibrary(directory: directory()), book = try imported(library)
        let manifest = library.directory.appendingPathComponent(book.id).appendingPathComponent("book.json")
        let original = try Data(contentsOf: manifest)
        for mutation: (inout [String: Any]) -> Void in [
            { $0["pages"] = ["pdf-1", "pdf-0"] }, { $0["chapters"] = [] }, { $0["coverName"] = "../cover" },
            { $0["pdf"] = ["pages": []] }, { $0["pdf"] = ["pages": [["width": -1, "height": 10]]] },
            { $0["epub"] = ["title": "", "author": "", "description": "", "language": "", "opfPath": "a", "manifest": [], "spine": [], "navItems": [], "isFixedLayout": false, "isPurePictureEpub": false, "isReflowableText": true, "hasDrm": false, "hasFontObfuscation": false] }
        ] {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            mutation(&json)
            try JSONSerialization.data(withJSONObject: json).write(to: manifest)
            XCTAssertThrowsError(try library.book(id: book.id))
        }
    }
}
