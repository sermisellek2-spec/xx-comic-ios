import XCTest
@testable import ComicCore

final class DetailChapterSectionTests: XCTestCase {

    // MARK: - DetailChapterSection Layout & Segment Tests (from DetailChapterSectionTest.java)

    func testBuildSegments_ascendingAndDescendingPreserveBounds() {
        let asc = DetailChapterSection.buildSegments(totalChapters: 145, isDesc: false)
        XCTAssertEqual(asc.count, 3)
        XCTAssertEqual(asc[0].label, "1-60")
        XCTAssertEqual(asc[0].chapterIndices.count, 60)
        XCTAssertEqual(asc[0].chapterIndices.first, 0)
        XCTAssertEqual(asc[0].chapterIndices[59], 59)

        XCTAssertEqual(asc[1].label, "61-120")
        XCTAssertEqual(asc[2].label, "121-145")
        XCTAssertEqual(asc[2].chapterIndices.count, 25)
        XCTAssertEqual(asc[2].chapterIndices[24], 144)

        let desc = DetailChapterSection.buildSegments(totalChapters: 145, isDesc: true)
        XCTAssertEqual(desc.count, 3)
        XCTAssertEqual(desc[0].label, "145-86")
        XCTAssertEqual(desc[0].chapterIndices.first, 144)
        XCTAssertEqual(desc[0].chapterIndices[59], 85)
        XCTAssertEqual(desc[1].label, "85-26")
        XCTAssertEqual(desc[2].label, "25-1")
        XCTAssertEqual(desc[2].chapterIndices[24], 0)
    }

    func testBuildSegments_capsSegmentCountForMassiveChapterLists() {
        let massive = DetailChapterSection.buildSegments(totalChapters: 12000, isDesc: false)
        XCTAssertTrue(massive.count <= 25, "Segment pills should stay bounded for 12,000 chapters")
        var totalCovered = 0
        for seg in massive {
            totalCovered += seg.chapterIndices.count
        }
        XCTAssertEqual(totalCovered, 12000)
    }

    func testSelectDefaultSegmentAndVisibleWindow_focusesCurrentReadingChapter() {
        let asc = DetailChapterSection.buildSegments(totalChapters: 200, isDesc: false)
        let segIdx = DetailChapterSection.selectDefaultSegmentIndex(segments: asc, currentChapterIndex: 95, hasCurrent: true)
        XCTAssertEqual(segIdx, 1) // 61-120 contains index 95 (chapter 96)

        let preview = DetailChapterSection.selectVisibleWindow(
            segmentIndices: asc[segIdx].chapterIndices,
            currentChapterIndex: 95,
            hasCurrent: true,
            expanded: false,
            columns: 3
        )
        XCTAssertEqual(preview.count, DetailChapterSection.previewLimit)
        XCTAssertTrue(preview.contains(95), "Preview window must include currently read chapter")
        XCTAssertEqual(preview[0] % 3, 0, "Row start should align to 3-column grid")

        let expanded = DetailChapterSection.selectVisibleWindow(
            segmentIndices: asc[segIdx].chapterIndices,
            currentChapterIndex: 95,
            hasCurrent: true,
            expanded: true,
            columns: 3
        )
        XCTAssertEqual(expanded.count, 60)
        XCTAssertTrue(expanded.contains(95))
    }

    func testChapterLabelFormatting() {
        XCTAssertEqual(DetailChapterSection.chapterLabel(1), "第一话")
        XCTAssertEqual(DetailChapterSection.chapterLabel(5), "第五话")
        XCTAssertEqual(DetailChapterSection.chapterLabel(9), "第九话")
        XCTAssertEqual(DetailChapterSection.chapterLabel(10), "第十话")
        XCTAssertEqual(DetailChapterSection.chapterLabel(15), "第十五话")
        XCTAssertEqual(DetailChapterSection.chapterLabel(20), "第二十话")
        XCTAssertEqual(DetailChapterSection.chapterLabel(25), "第25话")
        XCTAssertEqual(DetailChapterSection.chapterLabel(100), "第100话")
    }

    func testCleanChapterTitle() {
        let ch1 = Chapter(chapterId: "1", title: "  第1话 启程  ", url: "/1")
        XCTAssertEqual(DetailChapterSection.cleanChapterTitle(chapter: ch1, index: 0), "第1话 启程")

        let ch2 = Chapter(chapterId: "2", title: "   ", url: "/2")
        XCTAssertEqual(DetailChapterSection.cleanChapterTitle(chapter: ch2, index: 1), "第 2 话")

        XCTAssertEqual(DetailChapterSection.cleanChapterTitle(chapter: nil, index: 4), "第 5 话")
        XCTAssertEqual(DetailChapterSection.cleanChapterTitle(title: "特别篇", index: 0), "特别篇")
        XCTAssertEqual(DetailChapterSection.cleanChapterTitle(title: nil, index: 9), "第 10 话")
    }

    // MARK: - SwipeChapterSelection Tests (from SwipeChapterSelectionTest.java)

    func testVisitedCellsArePaintedAndUnvisitedCellsStayUntouched() {
        let m = SwipeChapterSelection(available: ["a", "b", "c", "d"], selected: [])
        XCTAssertTrue(m.begin("a"))
        XCTAssertTrue(m.visit("c"))
        m.finish()
        XCTAssertEqual(m.selected, Set(["a", "c"]))
    }

    func testStartingOnSelectedCellClearsOnlyVisitedCells() {
        let m = SwipeChapterSelection(available: ["a", "b", "c", "d"], selected: ["a", "b", "c"])
        XCTAssertTrue(m.begin("a"))
        XCTAssertTrue(m.visit("c"))
        m.finish()
        XCTAssertEqual(m.selected, Set(["b"]))
    }

    func testCrossingTheSameCellAgainDoesNotToggleItBack() {
        let m = SwipeChapterSelection(available: ["a", "b", "c", "d"], selected: [])
        XCTAssertTrue(m.begin("a"))
        XCTAssertTrue(m.visit("b"))
        XCTAssertFalse(m.visit("a"))
        XCTAssertFalse(m.visit("b"))
        m.finish()
        XCTAssertEqual(m.selected, Set(["a", "b"]))
    }

    func testCancelRestoresTheWholePreStrokeSelection() {
        let m = SwipeChapterSelection(available: ["a", "b", "c", "d"], selected: ["d"])
        XCTAssertTrue(m.begin("a"))
        XCTAssertTrue(m.visit("b"))
        XCTAssertTrue(m.cancel())
        XCTAssertEqual(m.selected, Set(["d"]))
        XCTAssertFalse(m.cancel())
    }

    func testCancelledDeselectionRestoresSelectedCells() {
        let m = SwipeChapterSelection(available: ["a", "b", "c", "d"], selected: ["a", "b"])
        XCTAssertTrue(m.begin("a"))
        XCTAssertTrue(m.visit("b"))
        XCTAssertTrue(m.cancel())
        XCTAssertEqual(m.selected, Set(["a", "b"]))
    }

    func testUnavailableAndRetiredIdsNeverEnterAStrokeOrCount() {
        let m = SwipeChapterSelection(available: ["a", "b", "c", "d"], selected: ["downloaded"])
        XCTAssertEqual(m.count, 0)
        XCTAssertFalse(m.begin("downloaded"))
        XCTAssertTrue(m.begin("a"))
        XCTAssertFalse(m.visit("downloaded"))
        m.finish()
        XCTAssertFalse(m.toggle("downloaded"))
        XCTAssertEqual(m.count, 1)
    }

    func testAllActionAddsMissingEligibleIdsThenClearsThem() {
        let m = SwipeChapterSelection(available: ["a", "b", "c", "d"], selected: ["b"])
        m.toggleAll()
        XCTAssertEqual(m.count, 4)
        XCTAssertTrue(m.allSelected())
        m.toggleAll()
        XCTAssertEqual(m.count, 0)
        XCTAssertFalse(m.allSelected())
    }

    func testNextStrokeCanReverseDirectionAfterCommit() {
        let m = SwipeChapterSelection(available: ["a", "b", "c", "d"], selected: [])
        XCTAssertTrue(m.begin("a"))
        XCTAssertTrue(m.visit("b"))
        m.finish()
        XCTAssertTrue(m.begin("b"))
        XCTAssertFalse(m.visit("c")) // "c" was not in selected, deselecting mode returns false
        m.finish()
        XCTAssertEqual(m.selected, Set(["a"]))
    }

    func testIdentitySurvivesAReorderedCatalog() {
        let m = SwipeChapterSelection(available: ["d", "c", "b", "a"], selected: ["b"])
        XCTAssertEqual(m.selected, Set(["b"]))
    }

    func testEmptyCatalogHasNoFalseAllSelectedState() {
        let m = SwipeChapterSelection(available: [], selected: [])
        XCTAssertFalse(m.allSelected())
        m.toggleAll()
        XCTAssertEqual(m.availableCount, 0)
        XCTAssertEqual(m.count, 0)
    }

    // MARK: - Drag Selection Index-Based Tests

    func testIndexBasedDragSelection() {
        let ids = ["c0", "c1", "c2", "c3", "c4"]
        let m = SwipeChapterSelection(available: ids)
        m.disabledIndices = [2]

        XCTAssertTrue(m.beginIndex(0, orderedIds: ids))
        XCTAssertEqual(m.startIndex, 0)
        XCTAssertTrue(m.isSelecting)

        XCTAssertTrue(m.visitIndex(1, orderedIds: ids))
        XCTAssertFalse(m.visitIndex(2, orderedIds: ids)) // disabled
        XCTAssertTrue(m.visitIndex(3, orderedIds: ids))
        m.finish()

        XCTAssertEqual(m.selected, Set(["c0", "c1", "c3"]))
        XCTAssertNil(m.startIndex)
    }

    func testApplyRangeSelection() {
        let ids = ["c0", "c1", "c2", "c3", "c4"]
        let m = SwipeChapterSelection(available: ids)
        m.disabledIndices = [1]

        XCTAssertTrue(m.begin("c0"))
        let count = m.applyRange(from: 0, to: 4, orderedIds: ids)
        XCTAssertEqual(count, 3) // c1 is disabled, c0 was visited in begin, c2, c3, c4 added
        m.finish()

        XCTAssertEqual(m.selected, Set(["c0", "c2", "c3", "c4"]))
    }
}
