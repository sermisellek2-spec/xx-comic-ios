import XCTest
@testable import ComicCore

final class SourceFilterSelectionTests: XCTestCase {
    func testExclusiveSourcesResetOtherKnownGroupsWhenSelectingAnOption() {
        for sourceID in ["mh160", "gmh", "mh18", "jmcomic"] {
            var selection = ["genre": "a"]
            SourceFilterSelection.select(sourceID: sourceID, key: "tag", value: "b",
                                         groupKeys: ["genre", "tag", "status"], in: &selection)
            XCTAssertEqual(selection, ["genre": "all", "tag": "b", "status": "all"], sourceID)
        }
    }

    func testSelectingAllOnlyChangesTheSelectedGroup() {
        for sourceID in ["mh160", "gmh", "mh18", "jmcomic"] {
            var selection = ["genre": "a", "tag": "b"]
            SourceFilterSelection.select(sourceID: sourceID, key: "tag", value: "all",
                                         groupKeys: ["genre", "tag", "status"], in: &selection)
            XCTAssertEqual(selection, ["genre": "a", "tag": "all"], sourceID)
        }
    }

    func testOrdinarySourcesKeepMultipleSelectedGroups() {
        var selection = ["genre": "a"]
        SourceFilterSelection.select(sourceID: "baozi", key: "tag", value: "b",
                                     groupKeys: ["genre", "tag", "status"], in: &selection)
        XCTAssertEqual(selection, ["genre": "a", "tag": "b"])
    }

    func testChangingAnOptionWithinTheSameGroupPreservesUnknownKeys() {
        for sourceID in ["mh160", "gmh", "mh18", "jmcomic"] {
            var selection = ["genre": "a", "tag": "all", "legacy": "saved"]
            SourceFilterSelection.select(sourceID: sourceID, key: "genre", value: "c",
                                         groupKeys: ["genre", "tag"], in: &selection)
            XCTAssertEqual(selection, ["genre": "c", "tag": "all", "legacy": "saved"], sourceID)
        }
    }
}
