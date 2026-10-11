import XCTest
@testable import ComicCore

final class BookshelfReadingStatusTests: XCTestCase {
    private let comic = ComicSummary(sourceId: "mh160", comicId: "mh160:test", title: "Test", latestChapter: "第9话")

    func testUnreadCountUsesObservedDirectoryAndRealReadingIndex() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try LibraryStore(directory: folder)
        let chapter = Chapter(chapterId: "2", title: "第2话", url: "https://fixture.invalid/2")
        try library.saveReading(comic, chapter: chapter, chapterIndex: 1, position: ReaderPosition(imageIndex: 0, offset: 0))
        let revision = FavoriteRevision(chapterIds: (1...9).map(String.init), chapterCount: 9)
        let status = BookshelfReadingStatus(comic: comic, reading: library.entry(for: comic)?.reading, revision: revision)
        XCTAssertEqual(status.unreadCount, 7)
        XCTAssertEqual(status.latestChapter, "第9话")
        XCTAssertEqual(status.readingDescription, "第2话")
    }

    func testUnreadBookShowsAllChaptersAndUnknownDirectoryDoesNotInventCount() {
        let revision = FavoriteRevision(chapterCount: 6)
        XCTAssertEqual(BookshelfReadingStatus(comic: comic, reading: nil, revision: revision).unreadCount, 6)
        XCTAssertEqual(BookshelfReadingStatus(comic: comic, reading: nil, revision: nil).unreadCount, -1)
        XCTAssertEqual(BookshelfReadingStatus(comic: comic, reading: nil, revision: nil).readingDescription, "未开始阅读")
    }

    func testDetailWinsAndRevisionProvidesLatestWhenSummaryHasNoEvidence() {
        let chapters = [Chapter(chapterId: "1", title: "目录末章", url: "https://fixture.invalid/1")]
        let detail = ComicDetail(summary: comic, author: "", status: "", description: "", latestChapter: "  详情最新  ", chapters: chapters)
        let status = BookshelfReadingStatus(comic: comic, reading: nil, revision: FavoriteRevision(chapterCount: 9), detail: detail)
        XCTAssertEqual(status.unreadCount, 1)
        XCTAssertEqual(status.latestChapter, "详情最新")
        let empty = ComicSummary(sourceId: "mh160", comicId: "mh160:empty", title: "Empty")
        XCTAssertEqual(BookshelfReadingStatus(comic: empty, reading: nil, revision: FavoriteRevision(latestChapterName: "观测最新")).latestChapter, "观测最新")
    }
}
