import XCTest
import UIKit
import ComicCore
@testable import XXComic

@MainActor
final class Parity2047NativeTests: XCTestCase {
    func testFreshInstallDefaultsToZeroSourcesUntilRuleSubscribed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FreshSources2047-" + UUID().uuidString, isDirectory: true)
        let suite = "FreshSources2047." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let environment = try AppEnvironment(defaults: defaults, storageDirectory: root, forceFreshInstall: true)
        defer {
            environment.cancelFolderSynchronization()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try environment.usageStats.setEnabled(false)

        XCTAssertFalse(environment.usesLegacyBuiltinSources)
        XCTAssertTrue(environment.sourcePreferences.availableIDs.isEmpty)
        XCTAssertTrue(environment.sourcePreferences.orderedIDs.isEmpty)
        XCTAssertTrue(environment.sources.isEmpty)

        let script = """
        function search(q, p) { return []; }
        function detail(u) { return { chapters: [] }; }
        function chapter(u) { return []; }
        """
        let rule = try RuleDefinition(json: [
            "id": "fresh_rule_1",
            "name": "订阅测试源",
            "version": 1,
            "engineApi": 2,
            "baseUrl": "https://sub.fixture.invalid",
            "hosts": ["sub.fixture.invalid"],
            "script": script,
            "scriptSha256": RuleDefinition.sha(Data(script.utf8)),
            "replacesNative": false,
            "imageRefresh": false,
            "requiresVpn": true
        ])
        _ = try environment.ruleCatalog.store().updateSubscriptions([rule])
        environment.reloadSources()

        XCTAssertEqual(environment.sourcePreferences.orderedIDs, ["fresh_rule_1"])
        XCTAssertEqual(environment.sources.map(\.id), ["fresh_rule_1"])
        XCTAssertTrue(environment.requiresVpn(sourceId: "fresh_rule_1"))
    }

    func testFavoriteUndoAndSourceReplacementUndoRestoreGroupsAndReading() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Undo2047-" + UUID().uuidString, isDirectory: true)
        let suite = "Undo2047." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let environment = try AppEnvironment(defaults: defaults, storageDirectory: root)
        defer {
            environment.cancelFolderSynchronization()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try environment.usageStats.setEnabled(false)

        let comic = ComicSummary(sourceId: "mh160", comicId: "fav-undo-1", title: "撤销测试漫画")
        let ch1 = Chapter(chapterId: "c1", title: "第1话", url: "https://fixture.invalid/c1")
        let groupA = try environment.bookshelfGroupStore.createGroup(scope: .online, rawName: "神作")
        let groupB = try environment.bookshelfGroupStore.createGroup(scope: .online, rawName: "待追")

        try environment.setFavorite(comic, favorite: true)
        try environment.library.saveReading(comic, chapter: ch1, chapterIndex: 0, position: ReaderPosition(imageIndex: 3, offset: 0.4))
        environment.bookshelfGroupStore.updateComicGroups(scope: .online, comicId: comic.comicId, targetGroupIds: [groupA.id, groupB.id])

        let favSnapshot = try environment.removeFavoriteWithSnapshot(comic)
        XCTAssertFalse(environment.library.entry(for: comic)?.isFavorite ?? true)
        XCTAssertTrue(environment.bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: comic.comicId).isEmpty)

        try environment.restoreFavorite(favSnapshot)
        XCTAssertTrue(environment.library.entry(for: comic)?.isFavorite == true)
        XCTAssertEqual(environment.library.entry(for: comic)?.reading?.position.imageIndex, 3)
        let restoredGroups = environment.bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: comic.comicId)
        XCTAssertTrue(restoredGroups.contains(where: \.isBuiltin))
        XCTAssertEqual(
            Set(restoredGroups.filter { !$0.isBuiltin }.map(\.id)),
            Set([groupA.id, groupB.id])
        )

        let targetSummary = ComicSummary(sourceId: "copy4000", comicId: "fav-undo-target", title: "撤销测试漫画")
        let targetChapter = Chapter(chapterId: "tc1", title: "第1话", url: "https://fixture.invalid/tc1")
        let targetDetail = ComicDetail(summary: targetSummary, author: "A", status: "连载", description: "", latestChapter: "第1话", chapters: [targetChapter])

        let switchSnapshot = environment.captureSourceReplacementSnapshot(original: comic, target: targetSummary)
        try environment.replaceSource(original: comic, target: targetDetail, matchingChapter: targetChapter, matchingChapterIndex: 0)
        XCTAssertNil(environment.library.entry(for: comic))
        XCTAssertTrue(environment.library.entry(for: targetSummary)?.isFavorite == true)

        try environment.undoSourceReplacement(switchSnapshot)
        XCTAssertTrue(environment.library.entry(for: comic)?.isFavorite == true)
        XCTAssertNil(environment.library.entry(for: targetSummary))
        let undoneGroups = environment.bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: comic.comicId)
        XCTAssertTrue(undoneGroups.contains(where: \.isBuiltin))
        XCTAssertEqual(
            Set(undoneGroups.filter { !$0.isBuiltin }.map(\.id)),
            Set([groupA.id, groupB.id])
        )
        XCTAssertTrue(environment.bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: targetSummary.comicId).isEmpty)
    }

    func testEnhancementMemoryWarningThrottlesTransientlyWithoutMutatingPreferences() async throws {
        let suite = "EnhanceMem2047." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReaderPreferencesStore(defaults: defaults)
        var saved = store.load()
        saved.enhancementMode = ImageEnhancementPolicy.modeSmart
        store.save(saved)

        let engine = ReaderEnhancementEngine(tilePredictor: { _, _, input in
            input.transformed(by: CGAffineTransform(scaleX: 2, y: 2))
        })
        XCTAssertFalse(engine.isTransientlyThrottled)

        engine.handleMemoryWarning()
        XCTAssertTrue(engine.isTransientlyThrottled)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let input = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        }
        let result = await engine.enhanceResult(url: "fixture://mem-throttle", original: input, mode: ImageEnhancementPolicy.modeSmart)
        XCTAssertEqual(result.method, .fallback)
        XCTAssertEqual(store.load().enhancementMode, ImageEnhancementPolicy.modeSmart)
    }
}
