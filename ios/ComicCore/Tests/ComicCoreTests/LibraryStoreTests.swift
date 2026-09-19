import XCTest
@testable import ComicCore

final class LibraryStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testRemovingFavoritePreservesReadingHistoryAcrossRestart() throws {
        let folder = try directory()
        let store = try LibraryStore(directory: folder)
        let comic = ComicSummary(sourceId: "gmh", comicId: "gmh:one", title: "一本漫画")
        let chapter = Chapter(chapterId: "c1", title: "第一话", url: "https://example.org/1")
        try store.setFavorite(comic, favorite: true, now: 100)
        try store.saveReading(comic, chapter: chapter, chapterIndex: 0,
                              position: ReaderPosition(imageIndex: 5, offset: 0.4), now: 200)
        try store.setFavorite(comic, favorite: false, now: 300)
        let restored = try LibraryStore(directory: folder)
        XCTAssertTrue(restored.favorites.isEmpty)
        XCTAssertEqual(restored.history.map(\.summary.title), ["一本漫画"])
        XCTAssertEqual(restored.entry(for: comic)?.reading?.position.imageIndex, 5)
        XCTAssertEqual(restored.position(for: comic, chapterID: "c1")?.offset, 0.4)
    }

    func testSameNamedBooksAndSourceLocalIDsDoNotCollide() throws {
        let store = try LibraryStore(directory: directory())
        let first = ComicSummary(sourceId: "a", comicId: "1", title: "同名")
        let second = ComicSummary(sourceId: "b", comicId: "1", title: "同名")
        try store.setFavorite(first, favorite: true, now: 10)
        try store.setFavorite(second, favorite: true, now: 20)
        XCTAssertEqual(store.favorites.map(\.summary.sourceId), ["b", "a"])
        let chapter = Chapter(chapterId: "x", title: "第一话", url: "https://example.org/x")
        try store.saveReading(first, chapter: chapter, chapterIndex: 0, position: .fromLegacy(3000, count: 10), now: 30)
        XCTAssertEqual(store.favorites.map(\.summary.sourceId), ["a", "b"])
    }

    func testPositionBelongsToItsChapter() throws {
        let store = try LibraryStore(directory: directory())
        let comic = ComicSummary(sourceId: "a", comicId: "one", title: "漫画")
        for (id, image) in [("1", 3), ("2", 7)] {
            try store.saveReading(comic, chapter: Chapter(chapterId: id, title: id, url: id),
                                  chapterIndex: 0, position: ReaderPosition(imageIndex: image, offset: 0.2), now: 20)
        }
        XCTAssertEqual(store.position(for: comic, chapterID: "1")?.imageIndex, 3)
        XCTAssertEqual(store.position(for: comic, chapterID: "2")?.imageIndex, 7)
    }

    func testCorruptFileIsReportedAndNotOverwritten() throws {
        let folder = try directory()
        let file = folder.appendingPathComponent("library.json")
        let original = Data("{broken".utf8)
        try original.write(to: file)
        XCTAssertThrowsError(try LibraryStore(directory: folder))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testFailedWriteDoesNotChangeInMemoryFavorites() throws {
        let folder = try directory()
        let store = try LibraryStore(directory: folder)
        try FileManager.default.removeItem(at: folder)
        try Data("not a directory".utf8).write(to: folder)
        let comic = ComicSummary(sourceId: "a", comicId: "1", title: "漫画")
        XCTAssertThrowsError(try store.setFavorite(comic, favorite: true, now: 1))
        XCTAssertTrue(store.favorites.isEmpty)
    }
}
