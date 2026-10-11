import XCTest
@testable import ComicCore

final class PreferencesTests: XCTestCase {
    func testAndroidPageModeValuesKeepTheirMeaning() {
        XCTAssertEqual(ReaderTurnMode(rawValue: 0), .tap)
        XCTAssertEqual(ReaderTurnMode(rawValue: 1), .buttons)
        XCTAssertEqual(ReaderTurnMode(rawValue: 2), .swipe)
    }

    func testLegacyButtonPreferenceIsUsedOnlyUntilExplicitModeExists() {
        let name = "XXComicTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "reader.button.mode")
        let store = ReaderPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.load().turnMode, .buttons)
        defaults.set(0, forKey: "reader.page.mode")
        XCTAssertEqual(store.load().turnMode, .tap)
    }

    func testRetiredLeftHandPreferenceDoesNotChangeCurrentReaderSettings() {
        let name = "XXComicTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(true, forKey: "reader.left.hand")

        XCTAssertEqual(ReaderPreferencesStore(defaults: defaults).load(), ReaderPreferences())
    }

    func testPersistedReaderChoicesSurviveNewStoreAndDoNotChangeAppTheme() {
        let name = "XXComicTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(2, forKey: "theme.mode")
        let store = ReaderPreferencesStore(defaults: defaults)
        var settings = store.load()
        XCTAssertFalse(settings.disablePageAnimation)
        XCTAssertFalse(settings.cropWhiteMargins)
        XCTAssertTrue(settings.pinchZoom)
        settings.theme = .dark
        settings.disablePageAnimation = true
        settings.cropWhiteMargins = true
        settings.layout = .paged
        store.save(settings)
        let restored = ReaderPreferencesStore(defaults: defaults).load()
        XCTAssertEqual(restored, settings)
        XCTAssertEqual(defaults.integer(forKey: "theme.mode"), 2)
    }

    func testInvalidSettingsFallBackToUsableModes() {
        let name = "XXComicTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(99, forKey: "reader.theme.mode")
        defaults.set(-7, forKey: "reader.layout.mode")
        defaults.set(99, forKey: "reader.page.mode")
        let settings = ReaderPreferencesStore(defaults: defaults).load()
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.layout, .strip)
        XCTAssertEqual(settings.turnMode, .swipe)
    }
}
