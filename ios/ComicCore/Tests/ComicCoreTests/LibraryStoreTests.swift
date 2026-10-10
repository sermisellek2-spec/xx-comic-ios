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

    func testDeleteHistoryClearsPositionsAndRetainsFavorites() throws {
        let folder = try directory()
        let store = try LibraryStore(directory: folder)
        let comicFav = ComicSummary(sourceId: "a", comicId: "fav1", title: "收藏漫画")
        let comicUnfav = ComicSummary(sourceId: "a", comicId: "unfav1", title: "普通漫画")
        let ch = Chapter(chapterId: "c1", title: "第1话", url: "https://example.org/1")

        // 1. 收藏漫画：加收藏 + 存阅读记录 + 存章节位置
        try store.setFavorite(comicFav, favorite: true, now: 100)
        try store.saveReading(comicFav, chapter: ch, chapterIndex: 0, position: ReaderPosition(imageIndex: 10, offset: 0.5), now: 150)

        // 2. 普通漫画：未收藏 + 存阅读记录
        try store.saveReading(comicUnfav, chapter: ch, chapterIndex: 0, position: ReaderPosition(imageIndex: 2, offset: 0.1), now: 160)

        XCTAssertEqual(store.history.count, 2)
        XCTAssertEqual(store.favorites.count, 1)

        // 删除普通漫画历史 -> 应该从 snapshot 中完全移除
        try store.deleteHistory(for: comicUnfav)
        XCTAssertEqual(store.history.count, 1)
        XCTAssertNil(store.entry(for: comicUnfav))

        // 删除收藏漫画历史 -> 历史清除、位置清除，但收藏仍被保留！
        try store.deleteHistory(for: comicFav)
        XCTAssertEqual(store.history.count, 0)
        XCTAssertEqual(store.favorites.count, 1)
        let entry = try XCTUnwrap(store.entry(for: comicFav))
        XCTAssertTrue(entry.isFavorite)
        XCTAssertNil(entry.reading)
        XCTAssertTrue(entry.positions.isEmpty)
        XCTAssertNil(store.position(for: comicFav, chapterID: "c1"))

        // 重启 store，校验持久化结果
        let reloaded = try LibraryStore(directory: folder)
        XCTAssertTrue(reloaded.history.isEmpty)
        XCTAssertEqual(reloaded.favorites.count, 1)
        XCTAssertEqual(reloaded.favorites.first?.summary.comicId, "fav1")
    }

    func testClearHistoryClearsAllReadingRecordsAndPositions() throws {
        let folder = try directory()
        let store = try LibraryStore(directory: folder)
        let c1 = ComicSummary(sourceId: "a", comicId: "1", title: "书1")
        let c2 = ComicSummary(sourceId: "a", comicId: "2", title: "书2")
        let ch = Chapter(chapterId: "c", title: "话", url: "u")

        try store.setFavorite(c1, favorite: true, now: 10)
        try store.saveReading(c1, chapter: ch, chapterIndex: 0, position: ReaderPosition(imageIndex: 1, offset: 0), now: 20)
        try store.saveReading(c2, chapter: ch, chapterIndex: 0, position: ReaderPosition(imageIndex: 3, offset: 0), now: 30)

        XCTAssertEqual(store.history.count, 2)
        try store.clearHistory()

        XCTAssertEqual(store.history.count, 0)
        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertNil(store.entry(for: c2))
        XCTAssertNotNil(store.entry(for: c1))
        XCTAssertTrue(store.entry(for: c1)!.positions.isEmpty)
    }

    func testReplaceSourcePreservesFavoriteAndReadingPosition() throws {
        let folder = try directory()
        let store = try LibraryStore(directory: folder)
        let original = ComicSummary(sourceId: "srcA", comicId: "c1", title: "漫画A")
        let target = ComicSummary(sourceId: "srcB", comicId: "c2", title: "漫画A")
        let oldChapter = Chapter(chapterId: "old_1", title: "第1话", url: "/ch1")
        let targetChapter = Chapter(chapterId: "target_1", title: "第1话", url: "/ch1")

        try store.setFavorite(original, favorite: true, now: 100)
        try store.saveReading(original, chapter: oldChapter, chapterIndex: 0,
                              position: ReaderPosition(imageIndex: 8, offset: 0.5), now: 200)

        try store.replaceSource(original: original, target: target, matchingChapter: targetChapter, matchingChapterIndex: 0)

        XCTAssertNil(store.entry(for: original))
        let targetEntry = try XCTUnwrap(store.entry(for: target))
        XCTAssertTrue(targetEntry.isFavorite)
        XCTAssertEqual(targetEntry.favoriteAt, 100)
        XCTAssertEqual(targetEntry.reading?.chapter.chapterId, "target_1")
        XCTAssertEqual(targetEntry.reading?.position.imageIndex, 8)
        XCTAssertEqual(targetEntry.positions["target_1"]?.imageIndex, 8)
    }
}
