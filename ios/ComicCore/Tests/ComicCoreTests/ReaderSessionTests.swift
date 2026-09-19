import XCTest
@testable import ComicCore

final class ReaderSessionTests: XCTestCase {
    func testChapterResponseUsesIdentityAfterDirectoryExpands() {
        let saved = Chapter(chapterId: "b", title: "第二章", url: "https://example.org/b")
        let first = Chapter(chapterId: "a", title: "第一章", url: "https://example.org/a")
        var state = ReaderSession(chapterCount: 1, chapterIndex: 0)
        XCTAssertTrue(state.loaded(chapter: saved, in: [first, saved], imageCount: 8,
                                   position: ReaderPosition(imageIndex: 4, offset: 0.2)))
        XCTAssertEqual(state.chapterIndex, 1)
        XCTAssertEqual(state.chapterCount, 2)
        XCTAssertEqual(state.imageIndex, 4)
        XCTAssertFalse(state.loaded(chapter: saved, in: [first], imageCount: 1,
                                    position: ReaderPosition(imageIndex: 0, offset: 0)))
        XCTAssertEqual(state.chapterIndex, 1)
        XCTAssertEqual(state.imageCount, 8)
    }

    func testPageBoundaryRequestsAdjacentChapterWithoutChangingLoadedChapter() {
        var state = ReaderSession(chapterCount: 3, chapterIndex: 1)
        state.loaded(imageCount: 2, position: ReaderPosition(imageIndex: 0, offset: 0))
        XCTAssertEqual(state.move(delta: 1), .image(1))
        XCTAssertEqual(state.move(delta: 1), .chapter(2, atEnd: false))
        XCTAssertEqual(state.chapterIndex, 1)
        XCTAssertEqual(state.imageIndex, 1)
        XCTAssertEqual(state.move(delta: -1), .image(0))
        XCTAssertEqual(state.move(delta: -1), .chapter(0, atEnd: true))
    }

    func testChapterChangeCommitsOnlyWhenExplicitlyLoadedAndClampsOldPosition() {
        var state = ReaderSession(chapterCount: 3, chapterIndex: 1)
        state.loaded(imageCount: 2, position: ReaderPosition(imageIndex: 99, offset: 0.3))
        XCTAssertEqual(state.imageIndex, 1)
        state.changeChapter(to: 0)
        state.loaded(imageCount: 4, position: ReaderPosition(imageIndex: 3, offset: 0, atEnd: true))
        XCTAssertEqual(state.chapterIndex, 0)
        XCTAssertEqual(state.imageIndex, 3)
    }

    func testEmptyAndCancelledGestureDoesNotAdvance() {
        var state = ReaderSession(chapterCount: 2, chapterIndex: 0)
        XCTAssertEqual(state.move(delta: 1), .unavailable)
        state.loaded(imageCount: 2, position: ReaderPosition(imageIndex: 0, offset: 0))
        XCTAssertEqual(state.move(delta: 0), .unavailable)
        XCTAssertEqual(state.move(delta: -1), .boundary)
        XCTAssertEqual(state.imageIndex, 0)
    }
}
