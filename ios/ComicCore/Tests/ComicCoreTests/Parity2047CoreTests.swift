import XCTest
import Foundation
@testable import ComicCore

final class Parity2047CoreTests: XCTestCase {
    func testRuleImagesStripHeadersResolveAndPrefixDecode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RuleImages2047-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let script = """
        function search(q, p) { return []; }
        function detail(u) { return { chapters: [] }; }
        function chapter(u) { return []; }
        """
        let ruleJson: [String: Any] = [
            "id": "ruleimg_test",
            "name": "规则图测试源",
            "version": 1,
            "engineApi": 2,
            "baseUrl": "https://img.fixture.invalid",
            "hosts": ["img.fixture.invalid"],
            "script": script,
            "scriptSha256": RuleDefinition.sha(Data(script.utf8)),
            "replacesNative": false,
            "imageRefresh": false,
            "requiresVpn": true
        ]
        let rule = try RuleDefinition(json: ruleJson)
        let catalog = RuleCatalog(directory: dir)
        _ = try catalog.store().updateSubscriptions([rule])
        catalog.refresh()

        let magic = Data("HDR!".utf8)
        let descriptor: [String: Any] = [
            "url": "https://img.fixture.invalid/ch1/001.bin",
            "referer": "https://img.fixture.invalid/read/1",
            "headers": ["X-Token": "tok-42"],
            "cookies": ["sid": "abc123"],
            "decode": [
                "type": "prefix",
                "bytes": 4,
                "magic": RuleBase64.encode(magic, false)
            ]
        ]

        let tagged = try RuleImages.tag(rule: rule, image: descriptor, chapter: "ch-1", index: 0)
        XCTAssertTrue(RuleImages.isRule(tagged))
        XCTAssertEqual(RuleImages.strip(tagged), "https://img.fixture.invalid/ch1/001.bin")

        let req = try RuleImages.requestHeaders(catalog: catalog, tagged: tagged)
        XCTAssertEqual(req.url, "https://img.fixture.invalid/ch1/001.bin")
        XCTAssertEqual(req.referer, "https://img.fixture.invalid/read/1")
        XCTAssertEqual(req.headers["X-Token"], "tok-42")
        XCTAssertEqual(req.cookieHeader, "sid=abc123")

        let pngPayload = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE
        ])
        let prefixed = magic + pngPayload
        let decoded = try RuleImages.decode(prefixed, tagged: tagged)
        XCTAssertEqual(decoded, pngPayload)

        XCTAssertTrue(SourceVpnPolicy.requiresVpn(sourceId: "ruleimg_test", ruleCatalog: catalog))
        XCTAssertTrue(SourceVpnPolicy.requiresVpn(sourceId: "jmcomic", ruleCatalog: catalog))
    }

    func testLibraryStorePrunesPositionsByLRUAndRestoresEntries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryLRU2047-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try LibraryStore(directory: dir, maxPositions: 5)
        let comic = ComicSummary(sourceId: "mh160", comicId: "c-lru", title: "LRU测试")
        try store.setFavorite(comic, favorite: true, now: 100)

        for idx in 1...8 {
            let chapter = Chapter(chapterId: "ch-\(idx)", title: "第\(idx)话", url: "https://fixture.invalid/\(idx)")
            try store.saveReading(
                comic,
                chapter: chapter,
                chapterIndex: idx - 1,
                position: ReaderPosition(imageIndex: idx, offset: 0.25),
                now: TimeInterval(100 + idx)
            )
        }

        let currentEntry = try XCTUnwrap(store.entry(for: comic))
        XCTAssertEqual(currentEntry.positions.count, 5)
        XCTAssertNil(currentEntry.positions["ch-1"])
        XCTAssertNil(currentEntry.positions["ch-3"])
        XCTAssertNotNil(currentEntry.positions["ch-4"])
        XCTAssertNotNil(currentEntry.positions["ch-8"])
        XCTAssertEqual(currentEntry.reading?.chapter.chapterId, "ch-8")

        let reloaded = try LibraryStore(directory: dir, maxPositions: 5)
        XCTAssertEqual(reloaded.entry(for: comic)?.positions.count, 5)

        try store.setFavorite(comic, favorite: false, now: 200)
        XCTAssertFalse(store.entry(for: comic)?.isFavorite ?? true)

        try store.restoreEntries([(comic, currentEntry)])
        XCTAssertTrue(store.entry(for: comic)?.isFavorite == true)
        XCTAssertEqual(store.entry(for: comic)?.reading?.chapter.chapterId, "ch-8")
    }

    func testBookshelfGroupStoreAsyncPersistenceFlush() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GroupsAsync2047-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("bookshelf_groups.json")
        let store = BookshelfGroupStore(file: file, asyncPersistence: true)
        let g1 = try store.createGroup(scope: .online, rawName: "追更中")
        let g2 = try store.createGroup(scope: .online, rawName: "已完结")
        store.addToScope(scope: .online, comicId: "comic-1")
        store.updateComicGroups(scope: .online, comicId: "comic-1", targetGroupIds: [g1.id, g2.id])
        store.flush()

        let reloaded = BookshelfGroupStore(file: file, asyncPersistence: false)
        let groups = reloaded.getGroupsForComic(scope: .online, comicId: "comic-1")
        XCTAssertTrue(groups.contains(where: { $0.isBuiltin && $0.name == "全部" }))
        XCTAssertEqual(Set(groups.filter { !$0.isBuiltin }.map(\.name)), Set(["追更中", "已完结"]))
    }

    func testSourcePreferencesUpdateAvailableIDsPreservesCustomOrderAndAppendsNewRules() throws {
        let suite = "SourcePrefs2047." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = SourcePreferences(defaults: defaults, defaultIDs: [], importableIDs: BuiltinSourceCatalog.activeIDs)
        XCTAssertTrue(prefs.availableIDs.isEmpty)
        XCTAssertTrue(prefs.orderedIDs.isEmpty)
        XCTAssertTrue(prefs.enabledIDs.isEmpty)

        prefs.updateAvailableIDs(["rule_a", "rule_b"])
        XCTAssertEqual(prefs.orderedIDs, ["rule_a", "rule_b"])
        prefs.setOrder(["rule_b", "rule_a"])

        prefs.updateAvailableIDs(["rule_a", "rule_b", "rule_c"])
        XCTAssertEqual(prefs.orderedIDs, ["rule_b", "rule_a", "rule_c"])

        prefs.updateAvailableIDs(["rule_b", "rule_c"])
        XCTAssertEqual(prefs.orderedIDs, ["rule_b", "rule_c"])
    }

    func testReaderComfortPolicyAndPreferencesRoundTrip() throws {
        XCTAssertEqual(ReaderComfortPolicy.normalizeKeepScreenMinutes(999), ReaderComfortPolicy.defaultKeepScreenMinutes)
        XCTAssertEqual(ReaderComfortPolicy.normalizeKeepScreenMinutes(-1), -1)
        XCTAssertFalse(ReaderComfortPolicy.isKeepScreenIdleExpired(minutes: 0, lastInteractionUptime: 10, nowUptime: 10_000))
        XCTAssertFalse(ReaderComfortPolicy.isKeepScreenIdleExpired(minutes: -1, lastInteractionUptime: 10, nowUptime: 10_000))
        XCTAssertFalse(ReaderComfortPolicy.isKeepScreenIdleExpired(minutes: 5, lastInteractionUptime: 100, nowUptime: 399))
        XCTAssertTrue(ReaderComfortPolicy.isKeepScreenIdleExpired(minutes: 5, lastInteractionUptime: 100, nowUptime: 400))

        XCTAssertEqual(ReaderComfortPolicy.clampBrightness(-0.5), 0.01, accuracy: 0.0001)
        XCTAssertEqual(ReaderComfortPolicy.clampBrightness(1.8), 1.0, accuracy: 0.0001)
        XCTAssertEqual(ReaderComfortPolicy.clampExtraDim(0.85), 0.60, accuracy: 0.0001)
        XCTAssertEqual(ReaderComfortPolicy.resolveExtraDimAlpha(readerVisible: false, dim: 0.35), 0.0, accuracy: 0.0001)
        XCTAssertEqual(ReaderComfortPolicy.resolveExtraDimAlpha(readerVisible: true, dim: 0.35), 0.35, accuracy: 0.0001)

        let suite = "ReaderComfort2047." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReaderPreferencesStore(defaults: defaults)
        var settings = store.load()
        XCTAssertEqual(settings.keepScreenMinutes, 15)
        XCTAssertTrue(settings.brightnessFollowSystem)
        XCTAssertEqual(settings.brightnessLevel, 0.60, accuracy: 0.001)
        XCTAssertEqual(settings.brightnessDim, 0.0, accuracy: 0.001)

        settings.keepScreenMinutes = 30
        settings.brightnessFollowSystem = false
        settings.brightnessLevel = 0.42
        settings.brightnessDim = 0.25
        store.save(settings)

        let reloaded = store.load()
        XCTAssertEqual(reloaded.keepScreenMinutes, 30)
        XCTAssertFalse(reloaded.brightnessFollowSystem)
        XCTAssertEqual(reloaded.brightnessLevel, 0.42, accuracy: 0.001)
        XCTAssertEqual(reloaded.brightnessDim, 0.25, accuracy: 0.001)
    }
}
