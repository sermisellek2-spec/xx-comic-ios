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

    func testReorderedSourcesRestoreManualGlobalSelection() {
        var state = GlobalSearchState()
        _ = state.begin(query: "陷阱", sourceIDs: ["a", "b", "c"])
        state.select("b")
        let selected = state.selectedSourceID

        let generation = state.begin(query: "陷阱", sourceIDs: ["c", "b", "a"], restoringSelectedSourceID: selected)
        XCTAssertEqual(state.selectedSourceID, "b")
        _ = state.receive(sourceID: "c", items: [comic("c1", "陷阱")], generation: generation)
        XCTAssertEqual(state.selectedSourceID, "b")
    }

    func testDisabledGlobalSelectionFallsBackToFirstEnabledSource() {
        var state = GlobalSearchState()
        _ = state.begin(query: "陷阱", sourceIDs: ["a", "b", "c"])
        state.select("b")
        let selected = state.selectedSourceID

        _ = state.begin(query: "陷阱", sourceIDs: ["c", "a"], restoringSelectedSourceID: selected)
        XCTAssertEqual(state.selectedSourceID, "c")
    }

    func testNewGlobalSearchStillSelectsFirstNonemptyResult() {
        var state = GlobalSearchState()
        _ = state.begin(query: "旧词", sourceIDs: ["a", "b"])
        state.select("a")

        let generation = state.begin(query: "新词", sourceIDs: ["a", "b"])
        _ = state.receive(sourceID: "b", items: [comic("b1", "新词")], generation: generation)
        _ = state.receive(sourceID: "a", items: [comic("a1", "新词")], generation: generation)
        XCTAssertEqual(state.selectedSourceID, "b")
    }

    func testSourceOrderExactFirst() {
        let items = ["b", "c", "a", "d"]
        let partitioned = SourceOrder.exactFirst(items) { $0 == "a" || $0 == "c" }
        XCTAssertEqual(partitioned, ["c", "a", "b", "d"])
    }

    func testVisibleSourceIDsHidesEmptySourcesAndOrdersExactMatchesFirst() {
        var state = GlobalSearchState()
        let generation = state.begin(query: "陷阱", sourceIDs: ["sourceA", "sourceB", "sourceC", "sourceD"])
        XCTAssertEqual(state.visibleSourceIDs, [])

        // sourceB has non-exact results
        _ = state.receive(sourceID: "sourceB", items: [comic("b1", "甜蜜陷阱")], generation: generation)
        XCTAssertEqual(state.visibleSourceIDs, ["sourceB"])

        // sourceC has empty results (must remain hidden)
        _ = state.receive(sourceID: "sourceC", items: [], generation: generation)
        XCTAssertEqual(state.visibleSourceIDs, ["sourceB"])

        // sourceD has exact match (must jump ahead of sourceB)
        _ = state.receive(sourceID: "sourceD", items: [comic("d1", " 陷阱 ")], generation: generation)
        XCTAssertEqual(state.visibleSourceIDs, ["sourceD", "sourceB"])
    }

    func testCalculateMatchScore_ExactAndWhitespace() {
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王", query: "海贼王"), SearchRules.exactMatchScore)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "  海贼王  ", query: "海贼王"), SearchRules.exactMatchScore)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王", query: "  海贼王  "), SearchRules.exactMatchScore)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "\t海贼王\n", query: " \t海贼王 "), SearchRules.exactMatchScore)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "ONE PIECE", query: "ONE PIECE"), SearchRules.exactMatchScore)

        // Safety on empty inputs
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "", query: "海贼王"), 0)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王", query: ""), 0)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "   ", query: "海贼王"), 0)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王", query: "   "), 0)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "", query: ""), 0)
    }

    func testCalculateMatchScore_CaseInsensitive() {
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "ONE PIECE", query: "one piece"), 9900)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "one piece", query: "ONE PIECE"), 9900)
    }

    func testCalculateMatchScore_PunctuationStripped() {
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "《海贼王》", query: "海贼王"), 9500)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王！", query: "海贼王"), 9500)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王.", query: "海贼王"), 9500)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王：草帽篇", query: "海贼王草帽篇"), 9500)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王[完]", query: "海贼王完"), 9500)
    }

    func testCalculateMatchScore_PartialMatchPrefixSuffixAndRatio() {
        // Partial Match A (title contains query)
        // prefix match: "海贼王" for query "海贼" (qLen 2, tLen 3, ratio 1000, prefix 800 -> 8800)
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王", query: "海贼"), 8800)
        // prefix match longer title: qLen 2, tLen 10, ratio 300, prefix 800 -> 8100
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼王剧场版狂热行动", query: "海贼"), 8100)
        // middle match: qLen 2, tLen 12, ratio 250, prefix 0 -> 7250
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "我在海贼世界当船长的日子", query: "海贼"), 7250)

        // Partial Match B (query contains title, title len >= 2)
        // tLen 2, qLen 3, ratio 600, prefix 300 -> 6700
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼", query: "海贼王"), 6700)
    }

    func testCalculateMatchScore_Similarity() {
        // "海贼之王" vs "海贼王": LCS 3, common 3, coverage 1.0, score 5275
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "海贼之王", query: "海贼王"), 5275)
        // unrelated strings
        XCTAssertEqual(SearchRules.calculateMatchScore(title: "火影忍者", query: "海贼王"), 0)
    }

    func testBestMatchScore_OrdersSourcesByHierarchy() {
        let exactSource = [comic("1", "海贼王")]
        let tightPartialSource = [comic("2", "海贼王全彩")]
        let loosePartialSource = [comic("3", "关于我在海贼王世界当海军")]
        let fuzzySource = [comic("4", "海贼之王")]
        let unrelatedSource = [comic("5", "火影忍者")]

        let sExact = SearchRules.bestMatchScore(exactSource, query: "海贼王")
        let sTight = SearchRules.bestMatchScore(tightPartialSource, query: "海贼王")
        let sLoose = SearchRules.bestMatchScore(loosePartialSource, query: "海贼王")
        let sFuzzy = SearchRules.bestMatchScore(fuzzySource, query: "海贼王")
        let sUnrelated = SearchRules.bestMatchScore(unrelatedSource, query: "海贼王")

        XCTAssertTrue(sExact > sTight)
        XCTAssertTrue(sTight > sLoose)
        XCTAssertTrue(sLoose > sFuzzy)
        XCTAssertTrue(sFuzzy > sUnrelated)
        XCTAssertEqual(sUnrelated, 0)

        XCTAssertEqual(SearchRules.bestMatchScore([], query: "海贼王"), 0)
        XCTAssertEqual(SearchRules.bestMatchScore(exactSource, query: ""), 0)
        XCTAssertEqual(SearchRules.bestMatchScore(exactSource, query: "   "), 0)
    }

    func testPrioritize_PartialAndSimilarityRankingWhenNoExactMatch() {
        let unrelated = comic("1", "火影忍者")
        let loosePartial = comic("2", "我在海贼世界当船长的日子")
        let prefixLong = comic("3", "海贼王剧场版狂热行动")
        let prefixTight = comic("4", "海贼王")

        let items = [unrelated, loosePartial, prefixLong, prefixTight]
        let prioritized = SearchRules.prioritize(items, query: "海贼")

        XCTAssertEqual(prioritized.map(\.comicId), ["4", "3", "2", "1"])
    }

    func testPrioritize_MultipleExactMatchesPreserveOrder() {
        let c1 = comic("1", "其他作品A")
        let c2 = comic("2", "海贼王")
        let c3 = comic("3", "其他作品B")
        let c4 = comic("4", "  海贼王  ")
        let c5 = comic("5", "其他作品C")
        let c6 = comic("6", "海贼王")

        let items = [c1, c2, c3, c4, c5, c6]
        let prioritized = SearchRules.prioritize(items, query: "  海贼王  ")

        XCTAssertEqual(prioritized.map(\.comicId), ["2", "4", "6", "1", "3", "5"])
    }

    func testSourceOrderRankByScore() {
        let managed = ["unmatched1", "partialLow", "exact1", "partialHigh", "exact2", "unmatched2"]
        let ranked = SourceOrder.rankByScore(managed) { id in
            if id.hasPrefix("exact") { return 10000 }
            if id == "partialHigh" { return 8500 }
            if id == "partialLow" { return 7200 }
            return 0
        }
        XCTAssertEqual(ranked, ["exact1", "exact2", "partialHigh", "partialLow", "unmatched1", "unmatched2"])
    }

    func testVisibleSourceIDsRanksByBestMatchScore() {
        var state = GlobalSearchState()
        let generation = state.begin(query: "海贼王", sourceIDs: ["srcUnrelated", "srcLoose", "srcExact", "srcTight", "srcEmpty"])
        _ = state.receive(sourceID: "srcUnrelated", items: [comic("u1", "火影忍者")], generation: generation)
        _ = state.receive(sourceID: "srcLoose", items: [comic("l1", "关于我在海贼王世界当海军")], generation: generation)
        _ = state.receive(sourceID: "srcExact", items: [comic("e1", "海贼王")], generation: generation)
        _ = state.receive(sourceID: "srcTight", items: [comic("t1", "海贼王全彩")], generation: generation)
        _ = state.receive(sourceID: "srcEmpty", items: [], generation: generation)

        // srcExact (10000) > srcTight (8700) > srcLoose (7375) > srcUnrelated (0); srcEmpty excluded
        XCTAssertEqual(state.visibleSourceIDs, ["srcExact", "srcTight", "srcLoose", "srcUnrelated"])
    }

    private func comic(_ id: String, _ title: String) -> ComicSummary {
        ComicSummary(sourceId: "test", comicId: id, title: title)
    }
}
