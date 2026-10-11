import XCTest
@testable import ComicCore

final class BuiltinSourceCatalogTests: XCTestCase {
    // Taken from Android 2.0.40's frozen defaultSourceOrder and public registry, not iOS helpers.
    private let androidIDs = [
        "mh160", "gmh", "mh18", "jmcomic", "mkzhan", "hiperdex", "manhuagui", "hanman18",
        "d5d6", "manben", "manhuazhan", "bbyin", "antbyw", "cuimh", "liumanhua", "copy4000",
        "manwa", "dingmanhua", "dongmanla", "xinmanhua", "zaimanhua", "guazi",
        "dm5", "kkk", "manhuaren", "dongman", "dogemanga", "sisi", "manxiaosi", "lele",
        "tuku", "ycy", "miaoqu", "aimi", "duya", "xiuxiu", "waiwai", "mh250", "tuhao",
        "manshiduo", "dumanwu", "ciyuan", "wmanhua", "aba", "comic51", "dmanhua", "mh360",
        "favcomic", "ttk", "laiman", "lmanhua"
    ]

    func testFreshSourceManagementShowsExactlyAndroidCurrentSourcesAndOrder() throws {
        let suite = "BuiltinSourceCatalogTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs)
        XCTAssertEqual(preferences.orderedIDs, androidIDs)
        XCTAssertEqual(Set(preferences.orderedIDs).count, 51)
        XCTAssertEqual(preferences.enabledIDs.count, 50)
        XCTAssertEqual(Set(preferences.orderedIDs).subtracting(preferences.enabledIDs), ["duya"])
        XCTAssertFalse(preferences.orderedIDs.contains("haoman"))
    }

    func testOldRetiredSwitchCannotReappearInDiscoveryOrGlobalSearch() throws {
        let suite = "BuiltinSourceCatalogTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "source.baozimh.enabled")
        defaults.set(true, forKey: "source.mhua5.enabled")
        defaults.set(false, forKey: "source.gmh.enabled")
        defaults.set(#"["baozimh","gmh","copymanga","mhua5"]"#, forKey: "source.order")
        let preferences = SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs)
        XCTAssertFalse(preferences.enabledIDs.contains("baozimh"))
        XCTAssertFalse(preferences.enabledIDs.contains("mhua5"))
        XCTAssertFalse(preferences.enabledIDs.contains("gmh"))
        XCTAssertEqual(Array(preferences.orderedIDs.prefix(2)), ["gmh", "copy4000"])
        XCTAssertEqual(defaults.object(forKey: "source.baozimh.enabled") as? Bool, true,
                       "Removing a retired entry must not erase stored user data")
    }

    func testResetOrderRestoresAndroidOrderAfterUserReordering() throws {
        let suite = "BuiltinSourceCatalogTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs)
        preferences.setOrder(["favcomic", "copy4000", "gmh"])
        preferences.setEnabled(false, id: "copy4000")
        preferences.resetOrder()
        XCTAssertEqual(preferences.orderedIDs, androidIDs)
        XCTAssertFalse(preferences.isEnabled("copy4000"))
    }
}
