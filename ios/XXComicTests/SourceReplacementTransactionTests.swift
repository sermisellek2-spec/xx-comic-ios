import XCTest
import ComicCore
@testable import XXComic

@MainActor
final class SourceReplacementTransactionTests: XCTestCase {
    func testFailedLibraryWritePreservesGroupsFavoriteAndReadingUntilARealRetrySucceeds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SourceReplacement-" + UUID().uuidString, isDirectory: true)
        let suite = "SourceReplacement." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let environment = try AppEnvironment(defaults: defaults, storageDirectory: root)
        defer {
            environment.cancelFolderSynchronization()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try environment.usageStats.setEnabled(false)
        let original = ComicSummary(sourceId: "mh160", comicId: "original", title: "事务验收")
        let target = ComicSummary(sourceId: "copy4000", comicId: "target", title: "事务验收")
        let oldChapter = Chapter(chapterId: "old-2", title: "第2话", url: "https://fixture.invalid/old/2")
        let chapter = Chapter(chapterId: "new-2", title: "第2话", url: "https://fixture.invalid/new/2")
        try environment.library.setFavorite(original, favorite: true)
        try environment.library.saveReading(original, chapter: oldChapter, chapterIndex: 1, position: ReaderPosition(imageIndex: 2, offset: 0.3))
        let group = try environment.bookshelfGroupStore.createGroup(scope: .online, rawName: "保留分组")
        environment.bookshelfGroupStore.addToScope(scope: .online, comicId: original.comicId)
        environment.bookshelfGroupStore.updateComicGroups(scope: .online, comicId: original.comicId, targetGroupIds: [group.id])
        let oldEntry = try XCTUnwrap(environment.library.entry(for: original))
        let oldGroups = environment.bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: original.comicId)
        let libraryFile = root.appendingPathComponent("library.json"), savedFile = root.appendingPathComponent("library-original.json")
        let originalBytes = try Data(contentsOf: libraryFile)
        try FileManager.default.moveItem(at: libraryFile, to: savedFile)
        try FileManager.default.createDirectory(at: libraryFile, withIntermediateDirectories: false)
        let detail = ComicDetail(summary: target, author: "", status: "", description: "", latestChapter: chapter.title, chapters: [chapter])
        XCTAssertThrowsError(try environment.replaceSource(original: original, target: detail, matchingChapter: chapter, matchingChapterIndex: 0))
        XCTAssertEqual(environment.library.entry(for: original), oldEntry)
        XCTAssertNil(environment.library.entry(for: target))
        XCTAssertEqual(environment.bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: original.comicId), oldGroups)
        XCTAssertEqual(try Data(contentsOf: savedFile), originalBytes)
        XCTAssertFalse(environment.bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: target.comicId).contains { $0.id == group.id })
        try FileManager.default.removeItem(at: libraryFile)
        try FileManager.default.moveItem(at: savedFile, to: libraryFile)
        try environment.replaceSource(original: original, target: detail, matchingChapter: chapter, matchingChapterIndex: 0)
        XCTAssertNil(environment.library.entry(for: original))
        let replaced = try XCTUnwrap(environment.library.entry(for: target))
        XCTAssertTrue(replaced.isFavorite)
        XCTAssertEqual(replaced.reading?.position, oldEntry.reading?.position)
        XCTAssertEqual(replaced.reading?.chapter, chapter)
        XCTAssertTrue(environment.bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: target.comicId).contains { $0.id == group.id })
        XCTAssertEqual(try LibraryStore(directory: root).entry(for: target), replaced)
    }
}
