import XCTest
@testable import ComicCore

final class ChapterMatchingTests: XCTestCase {
    func testNormalizeChapterName() {
        XCTAssertEqual(ChapterMatching.normalizeChapterName("第 1 话"), "1")
        XCTAssertEqual(ChapterMatching.normalizeChapterName("【第12卷】 终章"), "12终")
        XCTAssertEqual(ChapterMatching.normalizeChapterName("第100回: 决战"), "100:决战")
        XCTAssertEqual(ChapterMatching.normalizeChapterName("Chapter 05 (上)"), "chapter05上")
        XCTAssertEqual(ChapterMatching.normalizeChapterName(""), "")
        XCTAssertEqual(ChapterMatching.normalizeChapterName(nil), "")
    }

    func testFindMatchingChapterIndexExactMatch() {
        let chapters = [
            Chapter(chapterId: "ch1", title: "第 1 话", url: "/1"),
            Chapter(chapterId: "ch2", title: "第 2 话", url: "/2"),
            Chapter(chapterId: "ch3", title: "第 3 话", url: "/3")
        ]
        XCTAssertEqual(ChapterMatching.findMatchingChapterIndex(chapters: chapters, currentTitle: "第 2 话", defaultIndex: 0), 1)
        XCTAssertEqual(ChapterMatching.findMatchingChapterIndex(chapters: chapters, currentTitle: "  第 1 话  ", defaultIndex: 2), 0)
    }

    func testFindMatchingChapterIndexNormalizedMatch() {
        let chapters = [
            Chapter(chapterId: "ch1", title: "第1话", url: "/1"),
            Chapter(chapterId: "ch2", title: "第2话 特别篇", url: "/2"),
            Chapter(chapterId: "ch3", title: "第3话", url: "/3")
        ]
        // Target has "1话" without "第"
        XCTAssertEqual(ChapterMatching.findMatchingChapterIndex(chapters: chapters, currentTitle: "1话", defaultIndex: 2), 0)
        // Target has "2 特别篇"
        XCTAssertEqual(ChapterMatching.findMatchingChapterIndex(chapters: chapters, currentTitle: "2特别篇", defaultIndex: 0), 1)
    }

    func testFindMatchingChapterIndexSubstringMatch() {
        let chapters = [
            Chapter(chapterId: "ch1", title: "01", url: "/1"),
            Chapter(chapterId: "ch2", title: "02 新的旅程", url: "/2")
        ]
        XCTAssertEqual(ChapterMatching.findMatchingChapterIndex(chapters: chapters, currentTitle: "新的旅程", defaultIndex: 0), 1)
    }

    func testFindMatchingChapterIndexFallback() {
        let chapters = [
            Chapter(chapterId: "ch1", title: "序章", url: "/0"),
            Chapter(chapterId: "ch2", title: "第一章", url: "/1")
        ]
        // Non-matching title falls back to defaultIndex clamped
        XCTAssertEqual(ChapterMatching.findMatchingChapterIndex(chapters: chapters, currentTitle: "未知内容", defaultIndex: 1), 1)
        XCTAssertEqual(ChapterMatching.findMatchingChapterIndex(chapters: chapters, currentTitle: nil, defaultIndex: 0), 0)
        XCTAssertEqual(ChapterMatching.findMatchingChapterIndex(chapters: chapters, currentTitle: nil, defaultIndex: 99), 1)
    }
}
