import XCTest
@testable import ComicCore

final class SearchRulesTests: XCTestCase {
    func testExactMatchOnlyTrimsJavaWhitespace() {
        XCTAssertTrue(SearchRules.isExact(title: "\t陷阱\n", query: " 陷阱 "))
        for title in ["甜蜜陷阱", "陷阱！", "陷 阱", "陷阱 第二季", "\u{00a0}陷阱"] {
            XCTAssertFalse(SearchRules.isExact(title: title, query: "陷阱"))
        }
        XCTAssertFalse(SearchRules.isExact(title: "ABC", query: "abc"))
        XCTAssertFalse(SearchRules.isExact(title: "ＡＢＣ", query: "ABC"))
        XCTAssertFalse(SearchRules.isExact(title: " ", query: " "))
        XCTAssertFalse(SearchRules.isExact(title: "é", query: "e\u{0301}"))
    }

    func testStablePartitionKeepsDistinctSameNamedBooks() {
        let items = [comic("a", "甜蜜陷阱"), comic("b", "陷阱"), comic("c", "其他"), comic("d", " 陷阱 ")]
        XCTAssertEqual(SearchRules.prioritize(items, query: "陷阱").map(\.comicId), ["b", "d", "a", "c"])
        XCTAssertTrue(SearchRules.hasExact(items, query: "陷阱"))
        XCTAssertEqual(SearchRules.prioritize(items, query: "").map(\.comicId), ["a", "b", "c", "d"])
    }

    func testSourceOrderDiscardsStaleAndDuplicateIDsAndAppendsNewOnes() {
        XCTAssertEqual(SourceOrder.normalize(["b", "missing", "b"], available: ["a", "b", "c"]), ["b", "a", "c"])
    }

    func testLateResultsCannotContaminateNewSearch() {
        var state = GlobalSearchState()
        let old = state.begin(query: "陷阱", sourceIDs: ["a", "b"])
        let current = state.begin(query: "其他", sourceIDs: ["a", "b"])
        XCTAssertFalse(state.receive(sourceID: "a", items: [comic("old", "陷阱")], generation: old))
        XCTAssertTrue(state.receive(sourceID: "b", items: [comic("new", "其他")], generation: current))
        XCTAssertEqual(state.selectedSourceID, "b")
        XCTAssertEqual(state.exactSourceIDs, ["b"])
        XCTAssertNil(state.results["a"])
    }

    func testFirstNonemptyResultSelectsOnceAndManualChoiceWins() {
        var state = GlobalSearchState()
        let generation = state.begin(query: "陷阱", sourceIDs: ["a", "b", "c"])
        _ = state.receive(sourceID: "b", items: [comic("b1", "甜蜜陷阱")], generation: generation)
        _ = state.receive(sourceID: "a", items: [comic("a1", "陷阱")], generation: generation)
        XCTAssertEqual(state.selectedSourceID, "b")
        state.select("c")
        _ = state.receive(sourceID: "c", items: [comic("c1", "陷阱")], generation: generation)
        XCTAssertEqual(state.selectedSourceID, "c")
        _ = state.begin(query: "新词", sourceIDs: ["a"])
        XCTAssertTrue(state.exactSourceIDs.isEmpty)
        XCTAssertTrue(state.results.isEmpty)
    }

    private func comic(_ id: String, _ title: String) -> ComicSummary {
        ComicSummary(sourceId: "test", comicId: id, title: title)
    }
}
