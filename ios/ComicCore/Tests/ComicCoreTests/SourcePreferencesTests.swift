import XCTest
@testable import ComicCore

final class SourcePreferencesTests: XCTestCase {
    func testOrderDropsRemovedAndDuplicatesAndAppendsNewSources() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set(#"[null,42,{},"","b","b","removed"]"#, forKey: "source.order")
        let store = SourcePreferences(defaults: defaults, defaultIDs: ["a", "b", "c"])
        XCTAssertEqual(store.orderedIDs, ["b", "a", "c"])
        store.setOrder(["c", "b", "a"])
        XCTAssertEqual(SourcePreferences(defaults: defaults, defaultIDs: ["a", "b", "c", "d"]).orderedIDs, ["c", "b", "a", "d"])
        XCTAssertEqual(SourcePreferences(defaults: defaults, defaultIDs: ["a", "c"]).orderedIDs, ["c", "a"])
    }
    func testDisablingPreservesPositionAcrossReloadAndResetLeavesSwitchesUnchanged() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = SourcePreferences(defaults: defaults, defaultIDs: ["a", "b", "c"])
        store.setOrder(["c", "b", "a"])
        store.setEnabled(false, id: "b")
        XCTAssertEqual(store.enabledIDs, ["c", "a"])
        let reopened = SourcePreferences(defaults: defaults, defaultIDs: ["a", "b", "c"])
        XCTAssertEqual(reopened.orderedIDs, ["c", "b", "a"])
        XCTAssertEqual(reopened.enabledIDs, ["c", "a"])
        reopened.setEnabled(true, id: "b")
        XCTAssertEqual(reopened.enabledIDs, ["c", "b", "a"])
        for id in ["a", "b", "c"] { reopened.setEnabled(false, id: id) }
        XCTAssertEqual(reopened.enabledIDs, [])
        reopened.resetOrder()
        XCTAssertEqual(reopened.orderedIDs, ["a", "b", "c"])
        XCTAssertEqual(reopened.enabledIDs, [])
    }
    func testInvalidPreferencesKeepDefaultsAndCannotCreatePhantomSource() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set("broken", forKey: "source.order")
        let store = SourcePreferences(defaults: defaults, defaultIDs: ["a", "b"])
        XCTAssertEqual(store.enabledIDs, ["a", "b"])
        store.setOrder(["deleted", "b", "b"])
        store.setEnabled(true, id: "deleted")
        XCTAssertEqual(store.enabledIDs, ["b", "a"])
        XCTAssertNil(defaults.object(forKey: "source.deleted.enabled"))
    }
    private let defaultsName = "SourcePreferencesTests." + UUID().uuidString
    private func makeDefaults() -> UserDefaults { UserDefaults(suiteName: defaultsName)! }
}
