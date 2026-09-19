import XCTest
@testable import ComicCore

final class ReadingRulesTests: XCTestCase {
    func testLegacyProgressRestoresImageAndOffset() {
        let position = ReaderPosition.fromLegacy(4200, count: 8)
        XCTAssertEqual(position.imageIndex, 3)
        XCTAssertEqual(position.offset, 0.36, accuracy: 0.0001)
        XCTAssertEqual(position.legacyProgress(count: 8), 4200)
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

    func testHandednessChangesGestureNotLogicalOrder() {
        XCTAssertEqual(ReaderNavigation.tapDelta(leftSide: true, leftHand: true), 1)
        XCTAssertEqual(ReaderNavigation.tapDelta(leftSide: false, leftHand: false), 1)
        XCTAssertEqual(ReaderNavigation.swipeDelta(dx: 100, leftHand: true), 1)
        XCTAssertEqual(ReaderNavigation.swipeDelta(dx: -100, leftHand: false), 1)
        XCTAssertFalse(ReaderNavigation.crossesChapter(index: 0, count: 3, delta: 1))
        XCTAssertTrue(ReaderNavigation.crossesChapter(index: 2, count: 3, delta: 1))
        XCTAssertTrue(ReaderNavigation.crossesChapter(index: 0, count: 3, delta: -1))
        XCTAssertFalse(ReaderNavigation.crossesChapter(index: 0, count: 0, delta: 1))
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
