import XCTest
@testable import ComicCore

final class ReadingRulesTests: XCTestCase {
    func testTapZonesHonorControlsMiddleHeightAndPageInputMode() {
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.1, y: 0.5, controlsVisible: true, layout: .paged, mode: .tap, zoomed: false), .toggleControls)
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.29, y: 0.5, controlsVisible: false, layout: .paged, mode: .tap, zoomed: false), .toggleControls)
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.1, y: 0.1, controlsVisible: false, layout: .paged, mode: .tap, zoomed: false), .none)
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.1, y: 0.5, controlsVisible: false, layout: .paged, mode: .swipe, zoomed: false), .move(-1))
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.1, y: 0.5, controlsVisible: false, layout: .strip, mode: .swipe, zoomed: false), .toggleControls)
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.1, y: 0.5, controlsVisible: false, layout: .strip, mode: .tap, zoomed: false), .toggleControls)
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.9, y: 0.5, controlsVisible: false, layout: .paged, mode: .tap, zoomed: true), .toggleControls)
        XCTAssertFalse(ReaderNavigation.isEdgeTapNavigationPermitted(layout: .strip, mode: .tap))
        XCTAssertFalse(ReaderNavigation.isEdgeTapNavigationPermitted(layout: .strip, mode: .swipe))
        XCTAssertTrue(ReaderNavigation.isEdgeTapNavigationPermitted(layout: .paged, mode: .tap))
        XCTAssertFalse(ReaderNavigation.isEdgeTapNavigationPermitted(layout: .paged, mode: .buttons))
    }
    func testLegacyProgressRestoresImageAndOffset() {
        let position = ReaderPosition.fromLegacy(4200, count: 8)
        XCTAssertEqual(position.imageIndex, 3)
        XCTAssertEqual(position.offset, 0.36, accuracy: 0.0001)
        XCTAssertEqual(position.legacyProgress(count: 8), 4200)
    }

    func testNormalAndMangaViewsRetainTheStripOffsetWhileReadingTheSameImage() {
        let images = ["first", "second", "third"]
        let strip = ReaderPosition(imageIndex: 1, offset: 0.625)
        let normal = strip.forPagedImage(at: 1, in: images)
        let manga = normal.forPagedImage(at: 1, in: images)
        XCTAssertEqual(normal, strip)
        XCTAssertEqual(manga, strip)
        XCTAssertEqual(manga.legacyProgress(count: images.count), strip.legacyProgress(count: images.count))
    }

    func testReadingAnotherPagedImageResetsThePreviousStripOffsetAndCompletion() {
        let images = ["first", "second", "third"]
        let completed = ReaderPosition(imageIndex: 2, offset: 0.625, atEnd: true)
        let previous = completed.forPagedImage(at: 1, in: images)
        XCTAssertEqual(previous, ReaderPosition(imageIndex: 1, offset: 0))
        let tail = previous.forPagedImage(at: 2, in: images)
        XCTAssertEqual(tail, ReaderPosition(imageIndex: 2, offset: 0, atEnd: true))
        XCTAssertEqual(tail.forPagedImage(at: 0, in: []), ReaderPosition(imageIndex: 0, offset: 0))
        let shortened = ReaderPosition(imageIndex: 99, offset: 0.625).forPagedImage(at: 99, in: images)
        XCTAssertEqual(shortened, ReaderPosition(imageIndex: 2, offset: 0, atEnd: true))
    }

    func testPagedOffsetTracksLinkedImageIdentityAfterTheFolderOrderChanges() throws {
        let page = UUID(), other = UUID(), book = UUID()
        let first = try LinkedFolderPageURL.make(bookID: book.uuidString, pageID: page.uuidString)
        let second = try LinkedFolderPageURL.make(bookID: book.uuidString, pageID: other.uuidString)
        let position = ReaderPosition(imageIndex: 0, offset: 0.5, linkedPageID: page.uuidString, linkedTailID: other.uuidString)
        let moved = position.forPagedImage(at: 1, in: [second.absoluteString, first.absoluteString])
        XCTAssertEqual(moved.imageIndex, 1)
        XCTAssertEqual(moved.offset, 0.5)
        XCTAssertEqual(moved.linkedPageID, page.uuidString)
        XCTAssertFalse(moved.atEnd)
        let changed = moved.forPagedImage(at: 0, in: [second.absoluteString, first.absoluteString])
        XCTAssertEqual(changed.offset, 0)
        XCTAssertEqual(changed.linkedPageID, other.uuidString)
        let removed = position.forPagedImage(at: 0, in: [second.absoluteString])
        XCTAssertEqual(removed.offset, 0)
        XCTAssertEqual(removed.linkedPageID, other.uuidString)
    }

    func testCompletedAndShortenedChapters() {
        let position = ReaderPosition.fromLegacy(10000, count: 8)
        XCTAssertEqual(position.imageIndex, 7)
        XCTAssertTrue(position.atEnd)
        XCTAssertEqual(position.legacyProgress(count: 8), 10000)
        XCTAssertEqual(position.index(for: 3), 2)
        XCTAssertEqual(position.legacyProgress(count: 0), 0)
        XCTAssertEqual(ReaderPosition.fromLegacy(-100, count: 8).imageIndex, 0)
        XCTAssertFalse(ReaderPosition.fromLegacy(10000, count: 0).atEnd)
    }

    func testInvalidOffsetsAreClamped() throws {
        XCTAssertEqual(ReaderPosition(imageIndex: -1, offset: .nan).offset, 0)
        XCTAssertEqual(ReaderPosition(imageIndex: -1, offset: .infinity).offset, 1)
        let data = Data(#"{"imageIndex":-3,"offset":2,"atEnd":false}"#.utf8)
        let decoded = try JSONDecoder().decode(ReaderPosition.self, from: data)
        XCTAssertEqual(decoded.imageIndex, 0)
        XCTAssertEqual(decoded.offset, 1)
    }

    func testDefaultGestureDirectionKeepsLogicalPageOrder() {
        XCTAssertEqual(ReaderNavigation.tapDelta(leftSide: true), -1)
        XCTAssertEqual(ReaderNavigation.tapDelta(leftSide: false), 1)
        XCTAssertEqual(ReaderNavigation.swipeDelta(dx: 100), -1)
        XCTAssertEqual(ReaderNavigation.swipeDelta(dx: -100), 1)
        XCTAssertFalse(ReaderNavigation.crossesChapter(index: 0, count: 3, delta: 1))
        XCTAssertTrue(ReaderNavigation.crossesChapter(index: 2, count: 3, delta: 1))
        XCTAssertTrue(ReaderNavigation.crossesChapter(index: 0, count: 3, delta: -1))
        XCTAssertFalse(ReaderNavigation.crossesChapter(index: 0, count: 0, delta: 1))
    }

    func testMangaTapAndSwipeAdvanceFromTheLeftWithoutReversingChapters() {
        XCTAssertEqual(ReaderNavigation.tapDelta(leftSide: true, direction: .rightToLeft), 1)
        XCTAssertEqual(ReaderNavigation.tapDelta(leftSide: false, direction: .rightToLeft), -1)
        XCTAssertEqual(ReaderNavigation.swipeDelta(dx: 100, direction: .rightToLeft), 1)
        XCTAssertEqual(ReaderNavigation.swipeDelta(dx: -100, direction: .rightToLeft), -1)
        var session = ReaderSession(chapterCount: 3, chapterIndex: 1)
        session.loaded(imageCount: 2, position: ReaderPosition(imageIndex: 0, offset: 0))
        XCTAssertEqual(session.move(delta: ReaderNavigation.tapDelta(leftSide: true, direction: .rightToLeft)), .image(1))
        XCTAssertEqual(session.move(delta: ReaderNavigation.tapDelta(leftSide: true, direction: .rightToLeft)), .chapter(2, atEnd: false))
    }

    func testMangaDirectionDoesNotBypassStripZoomOrOverlayTapRules() {
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.1, y: 0.5, controlsVisible: false, layout: .paged, mode: .tap, zoomed: false, direction: .rightToLeft), .move(1))
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.9, y: 0.5, controlsVisible: false, layout: .paged, mode: .tap, zoomed: false, direction: .rightToLeft), .move(-1))
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.1, y: 0.5, controlsVisible: true, layout: .paged, mode: .tap, zoomed: false, direction: .rightToLeft), .toggleControls)
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.1, y: 0.5, controlsVisible: false, layout: .strip, mode: .tap, zoomed: false, direction: .rightToLeft), .toggleControls)
        XCTAssertEqual(ReaderNavigation.tapAction(x: 0.1, y: 0.5, controlsVisible: false, layout: .paged, mode: .tap, zoomed: true, direction: .rightToLeft), .toggleControls)
    }

    func testHistorySurvivesChangedOrMissingDirectory() {
        XCTAssertEqual(HistoryProgressLabel.label(savedIndex: 9, titles: ["全卷"]), "目录已更新 · 点击继续")
        XCTAssertEqual(HistoryProgressLabel.label(savedIndex: -1, titles: []), "有阅读记录")
        XCTAssertEqual(HistoryProgressLabel.label(savedIndex: 2, titles: []), "上次看到 第 3 章")
        XCTAssertEqual(HistoryProgressLabel.label(savedIndex: 0, titles: [" 第1话 "]), "上次看到 · 第1话")
        XCTAssertEqual(HistoryProgressLabel.label(savedIndex: 0, titles: [nil]), "上次看到 第 1 章")
    }

    func testReaderThemeFollowsSystemIndependentlyAndOverridesIt() {
        XCTAssertTrue(ReaderTheme.system.isDark(systemDark: true))
        XCTAssertFalse(ReaderTheme.system.isDark(systemDark: false))
        XCTAssertTrue(ReaderTheme.dark.isDark(systemDark: false))
        XCTAssertFalse(ReaderTheme.light.isDark(systemDark: true))
    }
}
