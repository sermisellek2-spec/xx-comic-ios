import XCTest
@testable import ComicCore

final class LocalLibraryTests: XCTestCase {
    func testImportedImagesAreCopiedSortedAndSurviveReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let two = root.appendingPathComponent("2.jpg"), ten = root.appendingPathComponent("10.jpg")
        try Data([2]).write(to: two); try Data([10]).write(to: ten)
        let directory = root.appendingPathComponent("library")
        let library = try LocalLibrary(directory: directory)
        let book = try library.importImages(title: "测试漫画", files: [ten, two])
        try FileManager.default.removeItem(at: two)
        let reopened = try LocalLibrary(directory: directory)
        XCTAssertEqual(try reopened.books(), [book])
        let pages = try reopened.pageURLs(for: book)
        XCTAssertEqual(try Data(contentsOf: pages[0]), Data([2]))
        XCTAssertEqual(try Data(contentsOf: pages[1]), Data([10]))
        XCTAssertEqual(book.title, "测试漫画")
        let source = LocalComicSource(library: reopened)
        let chapters = try await source.chapters(comicId: book.id)
        let page = try await source.chapter(url: chapters[0].url)
        XCTAssertEqual(page.imageUrls, pages.map(\.absoluteString))
        let detail = try await source.detail(comicId: book.id)
        XCTAssertEqual(detail.summary.sourceId, "local")
        XCTAssertEqual(detail.summary.coverUrl, pages[0].absoluteString)
    }
    func testFailedImportDoesNotPublishPartialBookOrModifyExistingBook() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try LocalLibrary(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("one.jpg")
        try Data([1]).write(to: source)
        let book = try library.importImages(title: "保留", files: [source])
        XCTAssertThrowsError(try library.importImages(title: "失败", files: [source, root.appendingPathComponent("missing.jpg")]))
        XCTAssertEqual(try library.books(), [book])
        XCTAssertThrowsError(try library.importImages(title: "空", files: []))
    }
    func testManifestCannotEscapeItsBookDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try LocalLibrary(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let book = LocalBook(id: UUID().uuidString, title: "无效", createdAt: 0, pages: ["../private.jpg"])
        XCTAssertThrowsError(try library.pageURLs(for: book))
    }
}
