import XCTest
import Foundation
@testable import ComicCore

final class Parity2056BlacklistAndDiscoveryTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Parity2056BD-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - 1. ComicTitleNormalizer

    func testTitleNormalizerFoldingPairsPunctuationAndFallback() {
        XCTAssertGreaterThanOrEqual(ComicTitleNormalizer.mappingCount, 680)
        XCTAssertEqual(ComicTitleNormalizer.normalize(nil), "")
        XCTAssertEqual(ComicTitleNormalizer.normalize(""), "")
        XCTAssertEqual(ComicTitleNormalizer.normalize("   \t\n\u{3000}  "), "")

        // Full-width ASCII & Trad/Simp folding + punctuation strip
        XCTAssertEqual(ComicTitleNormalizer.normalize("　ＡＢＣ　１２３！ "), "abc123")
        XCTAssertTrue(ComicTitleNormalizer.isSameComicTitle("進擊的巨人", "进击的巨人"))
        XCTAssertTrue(ComicTitleNormalizer.isSameComicTitle("《海賊王》：草帽篇！", "海贼王 草帽篇"))
        XCTAssertTrue(ComicTitleNormalizer.isSameComicTitle("龍珠Ｚ", "龙珠z"))
        XCTAssertTrue(ComicTitleNormalizer.isSameComicTitle("間諜過家家", "间谍过家家"))

        // Symbol-only fallback ignores whitespace while keeping non-whitespace symbols
        XCTAssertEqual(ComicTitleNormalizer.normalize(" ★ ☆ "), "★☆")
        XCTAssertTrue(ComicTitleNormalizer.isSameComicTitle("★ ☆", "★☆"))
        XCTAssertFalse(ComicTitleNormalizer.isSameComicTitle("   ", "   "))
    }

    // MARK: - 2. ComicBlacklistStore

    func testBlacklistStoreRoundTripTmpRecoveryCorruptGuardAndMutations() throws {
        let storageURL = tempDir.appendingPathComponent(ComicBlacklistStore.fileName)
        let store = ComicBlacklistStore(storageFile: storageURL)
        XCTAssertEqual(store.size, 0)
        XCTAssertFalse(store.isCorrupted)

        let e1 = BlacklistEntry(
            normalizedTitle: "",
            displayTitle: "進擊的巨人",
            coverUrl: "https://cdn.example.com/1.jpg",
            comicId: "c1",
            sourceId: "srcA",
            sourceName: "Source A",
            originScope: "recommend",
            originLabel: "推荐",
            groupSummary: "全部",
            blacklistedAt: 100
        )
        let e2 = BlacklistEntry(
            normalizedTitle: ComicTitleNormalizer.normalize("海贼王"),
            displayTitle: "海贼王",
            coverUrl: "https://cdn.example.com/2.jpg",
            comicId: "c2",
            sourceId: "srcB",
            sourceName: "Source B",
            originScope: "discovery",
            originLabel: "发现",
            groupSummary: "热血",
            blacklistedAt: 200
        )
        XCTAssertTrue(store.add(e1))
        XCTAssertTrue(store.add(e2))
        XCTAssertEqual(store.size, 2)
        XCTAssertTrue(store.isBlacklistedTitle("进击的巨人"))
        XCTAssertTrue(store.isBlacklistedNormalizedTitle(ComicTitleNormalizer.normalize("海賊王")))

        let summaries = [
            ComicSummary(sourceId: "s", comicId: "1", title: "进击的巨人"),
            ComicSummary(sourceId: "s", comicId: "2", title: "火影忍者"),
            ComicSummary(sourceId: "s", comicId: "3", title: "海賊王")
        ]
        let filtered = store.filterSummaries(summaries)
        XCTAssertEqual(filtered.map(\.comicId), ["2"])

        // Verify strict v1 JSON round-trip and descending sort
        let reloaded = ComicBlacklistStore(storageFile: storageURL)
        XCTAssertEqual(reloaded.size, 2)
        XCTAssertEqual(reloaded.listEntries().map(\.comicId), ["c2", "c1"])
        let rawObj = try JSONSerialization.jsonObject(with: Data(contentsOf: storageURL)) as? [String: Any]
        XCTAssertEqual(rawObj?["version"] as? Int, 1)
        XCTAssertEqual((rawObj?["entries"] as? [[String: Any]])?.count, 2)

        // Batch remove + restore + clearAll
        XCTAssertEqual(reloaded.removeByNormalizedTitles([e1.normalizedTitle]), 1)
        XCTAssertEqual(reloaded.size, 1)
        XCTAssertEqual(reloaded.restoreEntries([e1]), 1)
        XCTAssertEqual(reloaded.size, 2)
        XCTAssertTrue(reloaded.removeByNormalizedTitle(e2.normalizedTitle))
        XCTAssertEqual(reloaded.size, 1)

        // .tmp recovery when main file missing
        let tmpDir = tempDir.appendingPathComponent("tmp-recover", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpMain = tmpDir.appendingPathComponent(ComicBlacklistStore.fileName)
        let tmpFile = tmpDir.appendingPathComponent(ComicBlacklistStore.fileName + ".tmp")
        let validPayload = try Data(contentsOf: storageURL)
        try validPayload.write(to: tmpFile)
        let recoveredStore = ComicBlacklistStore(storageFile: tmpMain)
        XCTAssertFalse(recoveredStore.isCorrupted)
        XCTAssertEqual(recoveredStore.size, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpMain.path))

        // Corrupt payload protection: creates .corrupt backup and refuses to overwrite on mutations
        let corruptDir = tempDir.appendingPathComponent("corrupt-guard", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        let corruptMain = corruptDir.appendingPathComponent(ComicBlacklistStore.fileName)
        let corruptBytes = Data("{broken json".utf8)
        try corruptBytes.write(to: corruptMain)
        let corruptStore = ComicBlacklistStore(storageFile: corruptMain)
        XCTAssertTrue(corruptStore.isCorrupted)
        XCTAssertEqual(corruptStore.size, 0)
        let backupURL = corruptDir.appendingPathComponent(ComicBlacklistStore.fileName + ".corrupt")
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptBytes)

        // Mutations while corrupted must NOT overwrite corruptMain or backupURL
        _ = corruptStore.add(e2)
        XCTAssertEqual(try Data(contentsOf: corruptMain), corruptBytes)

        // clearAll resets corrupted flag and writes clean store
        _ = corruptStore.clearAll()
        XCTAssertFalse(corruptStore.isCorrupted)
        let afterClear = ComicBlacklistStore(storageFile: corruptMain)
        XCTAssertFalse(afterClear.isCorrupted)
        XCTAssertEqual(afterClear.size, 0)
    }

    func testBlacklistStoreStrictSchemaValidationRejectsInvalidVersionsAndEntries() throws {
        let badCases = [
            "{\"entries\":[]}",
            "{\"version\":true,\"entries\":[]}",
            "{\"version\":99,\"entries\":[]}",
            "{\"version\":1,\"entries\":[\"bad-string\"]}"
        ]
        for (idx, payload) in badCases.enumerated() {
            let subDir = tempDir.appendingPathComponent("bad-\(idx)", isDirectory: true)
            try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
            let file = subDir.appendingPathComponent(ComicBlacklistStore.fileName)
            try Data(payload.utf8).write(to: file)
            let store = ComicBlacklistStore(storageFile: file)
            XCTAssertTrue(store.isCorrupted, "Case \(idx) must be flagged corrupt")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path + ".corrupt"))
        }
    }

    // MARK: - 3. SourceFilterSelection

    func testSourceFilterSelectionExclusiveGroupDefaultLabelsAndNotes() {
        let defaultLabels = [
            "全部", "默认", "不限",
            "全部题材", "全部地区", "全部状态", "全部分类",
            "默认排序", "全部排序", "综合排序",
            "更新时间", "最新更新", "最近更新", "按更新", "更新", "最新",
            "all", "ALL"
        ]
        for label in defaultLabels {
            XCTAssertTrue(
                SourceFilterSelection.isDefaultOptionLabel(SourceFilterOption(label: label, value: "0")),
                "Expected default option label: \(label)"
            )
        }
        XCTAssertFalse(SourceFilterSelection.isDefaultOptionLabel(SourceFilterOption(label: "热血", value: "hot")))

        let gTheme = SourceFilterGroup(
            key: "theme",
            label: "题材",
            options: [SourceFilterOption(label: "全部", value: "all"), SourceFilterOption(label: "热血", value: "1")],
            exclusiveGroup: "cat"
        )
        let gRegion = SourceFilterGroup(
            key: "region",
            label: "地区",
            options: [SourceFilterOption(label: "全部地区", value: "0"), SourceFilterOption(label: "日漫", value: "jp")],
            exclusiveGroup: "cat"
        )
        let gSort = SourceFilterGroup(
            key: "sort",
            label: "排序",
            options: [SourceFilterOption(label: "综合排序", value: "default"), SourceFilterOption(label: "人气", value: "hot")],
            exclusiveGroup: ""
        )

        XCTAssertTrue(SourceFilterSelection.hasAnyExclusiveGroup([gTheme, gRegion, gSort]))
        XCTAssertTrue(SourceFilterSelection.isPartialMutexFilterSchema([gTheme, gRegion, gSort]))
        XCTAssertEqual(
            SourceFilterSelection.filterMutexNote([gTheme, gRegion, gSort]),
            "部分筛选条件受原站限制互斥，标注以外条件可叠加组合"
        )

        XCTAssertFalse(SourceFilterSelection.isPartialMutexFilterSchema([gTheme, gRegion]))
        XCTAssertEqual(
            SourceFilterSelection.filterMutexNote([gTheme, gRegion]),
            "原站仅支持单条件筛选，切换分类会重置其他互斥项"
        )
        XCTAssertNil(SourceFilterSelection.filterMutexNote([gSort]))

        // Default option check using first-option default label even when value != "all"
        XCTAssertTrue(SourceFilterSelection.isDefaultFilterOption(group: gRegion, option: gRegion.options[0]))
        XCTAssertFalse(SourceFilterSelection.isDefaultFilterOption(group: gRegion, option: gRegion.options[1]))

        // Selecting theme="1" resets region ("cat" mutex) to "0", while preserving sort="hot"
        var selection = ["theme": "all", "region": "jp", "sort": "hot"]
        var labels = ["theme": "全部", "region": "日漫", "sort": "人气"]
        let reset = SourceFilterSelection.select(
            sourceID: "rule_src",
            isRuleSource: true,
            groups: [gTheme, gRegion, gSort],
            selectedGroup: gTheme,
            selectedOption: gTheme.options[1],
            in: &selection,
            labels: &labels
        )
        XCTAssertEqual(reset, ["region"])
        XCTAssertEqual(selection, ["theme": "1", "region": "0", "sort": "hot"])
        XCTAssertEqual(labels["region"], "全部地区")

        // Legacy built-in fallback when non-rule and no exclusiveGroup
        let legacyGroups = [
            SourceFilterGroup(key: "genre", label: "题材", options: [SourceFilterOption(label: "全部", value: "all"), SourceFilterOption(label: "恋爱", value: "love")]),
            SourceFilterGroup(key: "status", label: "状态", options: [SourceFilterOption(label: "全部", value: "all"), SourceFilterOption(label: "连载", value: "ser")])
        ]
        var legacySel = ["genre": "love", "status": "ser"]
        var legacyLabels = ["genre": "恋爱", "status": "连载"]
        let legacyReset = SourceFilterSelection.select(
            sourceID: "mh160",
            isRuleSource: false,
            groups: legacyGroups,
            selectedGroup: legacyGroups[0],
            selectedOption: legacyGroups[0].options[1],
            in: &legacySel,
            labels: &legacyLabels
        )
        XCTAssertEqual(legacyReset, ["status"])
        XCTAssertEqual(legacySel, ["genre": "love", "status": "all"])

        // Rule source without exclusiveGroup keeps independent filters even if id matches legacy
        var ruleSel = ["genre": "love", "status": "ser"]
        var ruleLabels = ["genre": "恋爱", "status": "连载"]
        let ruleReset = SourceFilterSelection.select(
            sourceID: "mh160",
            isRuleSource: true,
            groups: legacyGroups,
            selectedGroup: legacyGroups[0],
            selectedOption: legacyGroups[0].options[1],
            in: &ruleSel,
            labels: &ruleLabels
        )
        XCTAssertTrue(ruleReset.isEmpty)
        XCTAssertEqual(ruleSel["status"], "ser")
    }

    // MARK: - 4. DiscoveryModels, GlobalSearchState, Coalescer & BackToTopPolicy

    func testDiscoveryModelsHelpersAndGlobalRows() {
        XCTAssertEqual(
            DiscoveryModels.compactRemark(ComicSummary(sourceId: "s", comicId: "1", title: "T", subtitle: "作者", latestChapter: "第10话")),
            "第10话"
        )
        XCTAssertEqual(
            DiscoveryModels.compactRemark(ComicSummary(sourceId: "s", comicId: "1", title: "T", subtitle: "暂无")),
            ""
        )
        XCTAssertEqual(
            DiscoveryModels.compactRemark(ComicSummary(sourceId: "s", comicId: "1", title: "T", subtitle: "作者张三 · 很长很长的附加说明超过十八字")),
            "作者张三"
        )

        let manyComics = (1...10).map { ComicSummary(sourceId: "s1", comicId: "\($0)", title: "Comic \($0)") }
        XCTAssertEqual(DiscoveryModels.capGlobalItems(manyComics).count, 6)

        // Filter group collapsing & inline >= 32 insertion at index 1
        let manyOptions = (0..<40).map { SourceFilterOption(label: "标签\($0)", value: "v\($0)") }
        let groups = [
            SourceFilterGroup(key: "g0", label: "G0", options: [SourceFilterOption(label: "全部", value: "all"), SourceFilterOption(label: "A", value: "a")]),
            SourceFilterGroup(key: "g1", label: "G1", options: [SourceFilterOption(label: "全部", value: "all"), SourceFilterOption(label: "B", value: "b")]),
            SourceFilterGroup(key: "g2", label: "G2", options: manyOptions),
            SourceFilterGroup(key: "g3", label: "G3", options: [SourceFilterOption(label: "全部", value: "all"), SourceFilterOption(label: "D", value: "d")]),
            SourceFilterGroup(key: "g4", label: "G4", options: [SourceFilterOption(label: "全部", value: "all"), SourceFilterOption(label: "E", value: "e")])
        ]
        XCTAssertTrue(DiscoveryModels.shouldShowFilterExpand(groups[2]))
        XCTAssertFalse(DiscoveryModels.shouldShowFilterExpand(groups[0]))
        XCTAssertEqual(DiscoveryModels.visibleInlineGroupIndices(groups, selectedFilters: ["g4": "e"]), [0, 1, 2, 4])
        XCTAssertEqual(DiscoveryModels.firstCollapsedFilterTab(groups, selectedFilters: ["g4": "e"]), 4)

        let sliced = DiscoveryModels.inlineOptionsForGroup(groups[2], selectedValue: "v35")
        XCTAssertEqual(sliced.count, 33)
        XCTAssertEqual(sliced[1].value, "v35")

        // GlobalSearchState aggregated stream + verification tracking
        var searchState = GlobalSearchState()
        let gen = searchState.begin(query: "海贼", sourceIDs: ["s1", "sVerify"], preferAllSources: true)
        XCTAssertEqual(searchState.selectedSourceID, "")
        XCTAssertTrue(searchState.receive(sourceID: "s1", items: manyComics, generation: gen))
        XCTAssertEqual(searchState.selectedSourceID, "") // aggregated mode does not hijack selection
        XCTAssertEqual(searchState.cappedResults(for: "s1").count, 6)
        XCTAssertTrue(searchState.recordFailure(sourceID: "sVerify", offerVerification: true, generation: gen))
        XCTAssertEqual(searchState.totalDisplayedGlobalHits, 6)

        let rows = searchState.buildGlobalRows(sourceMetaByID: [
            "s1": DiscoverySourceMeta(id: "s1", name: "站源1", requiresVpn: false, hasExactMatch: false),
            "sVerify": DiscoverySourceMeta(id: "sVerify", name: "验证源", requiresVpn: true, hasExactMatch: false)
        ])
        // 1 header + 6 posters + 1 verify header = 8
        XCTAssertEqual(rows.count, 8)
        if case .sectionHeader(let h0) = rows[0] {
            XCTAssertEqual(h0.actionType, .singleSearch)
            XCTAssertEqual(h0.countBadge, "6 部")
        } else {
            XCTFail("Expected section header at 0")
        }
        if case .sectionHeader(let hVerify) = rows[7] {
            XCTAssertEqual(hVerify.actionType, .verify)
            XCTAssertEqual(hVerify.countBadge, "需验证")
            XCTAssertTrue(hVerify.requiresVpn)
        } else {
            XCTFail("Expected verify header at 7")
        }
        if case .poster(let p0) = rows[1] {
            XCTAssertEqual(p0.stableItemKey, "s1\u{0000}1")
        } else {
            XCTFail("Expected poster at 1")
        }

        XCTAssertEqual(
            DiscoveryModels.totalDisplayedGlobalHits(
                orderedHitSources: [DiscoverySourceMeta(id: "s1", name: "站源1", requiresVpn: false, hasExactMatch: false)],
                resultsBySource: ["s1": manyComics]
            ),
            6
        )
    }

    func testGlobalSearchUiCoalescerFixedWindowFlushAndCancel() {
        let scheduler = FakeGlobalSearchScheduler()
        let coalescer = GlobalSearchUiCoalescer(scheduler: scheduler, windowMs: 160)
        var log: [String] = []

        coalescer.beginSession()
        // First call fires immediately
        coalescer.requestRefresh(forceImmediate: false) { log.append("first") }
        XCTAssertEqual(log, ["first"])
        XCTAssertFalse(coalescer.hasPendingRefresh)

        // Rapid subsequent bursts coalesce without extending the scheduled timer
        coalescer.requestRefresh(forceImmediate: false) { log.append("b1") }
        XCTAssertTrue(coalescer.hasPendingRefresh)
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(scheduler.scheduled[0].delayMs, 160)

        coalescer.requestRefresh(forceImmediate: false) { log.append("b2") }
        XCTAssertEqual(scheduler.scheduled.count, 1) // no duplicate timer

        scheduler.fireNext()
        XCTAssertEqual(log, ["first", "b2"])
        XCTAssertFalse(coalescer.hasPendingRefresh)

        // flushNow cancels pending timer and executes final action
        coalescer.requestRefresh(forceImmediate: false) { log.append("b3") }
        coalescer.flushNow { log.append("final") }
        XCTAssertFalse(coalescer.hasPendingRefresh)
        XCTAssertEqual(log, ["first", "b2", "final"])
        scheduler.fireAllRemaining()
        XCTAssertEqual(log, ["first", "b2", "final"])

        // beginSession cancels pending callbacks from prior session
        coalescer.requestRefresh(forceImmediate: false) { log.append("stale") }
        coalescer.beginSession()
        scheduler.fireAllRemaining()
        XCTAssertEqual(log, ["first", "b2", "final"])
    }

    func testBackToTopPolicyThresholdsVisibilityJumpAndDuration() {
        XCTAssertFalse(BackToTopPolicy.isEligible(firstVisible: 0, scrollOffsetPx: 0, viewportHeightPx: 1000, spanCount: 3, isMixedFullSpanList: false))
        XCTAssertTrue(BackToTopPolicy.isEligible(firstVisible: 1, scrollOffsetPx: 900, viewportHeightPx: 1000, spanCount: 3, isMixedFullSpanList: false))
        XCTAssertTrue(BackToTopPolicy.isEligible(firstVisible: 6, scrollOffsetPx: 10, viewportHeightPx: 1000, spanCount: 3, isMixedFullSpanList: false))
        XCTAssertFalse(BackToTopPolicy.isEligible(firstVisible: 5, scrollOffsetPx: 10, viewportHeightPx: 1000, spanCount: 3, isMixedFullSpanList: false))
        XCTAssertTrue(BackToTopPolicy.isEligible(firstVisible: 2, scrollOffsetPx: 10, viewportHeightPx: 1000, spanCount: 3, isMixedFullSpanList: true))

        XCTAssertFalse(BackToTopPolicy.nextVisibility(currentVisible: true, eligible: false, dy: -50, scrollState: BackToTopPolicy.scrollStateIdle))
        XCTAssertFalse(BackToTopPolicy.nextVisibility(currentVisible: true, eligible: true, dy: 25, scrollState: BackToTopPolicy.scrollStateDragging))
        XCTAssertTrue(BackToTopPolicy.nextVisibility(currentVisible: false, eligible: true, dy: -17, scrollState: BackToTopPolicy.scrollStateDragging))
        XCTAssertTrue(BackToTopPolicy.nextVisibility(currentVisible: false, eligible: true, dy: 0, scrollState: BackToTopPolicy.scrollStateIdle))
        XCTAssertFalse(BackToTopPolicy.nextVisibility(currentVisible: false, eligible: true, dy: 5, scrollState: BackToTopPolicy.scrollStateDragging))

        XCTAssertEqual(BackToTopPolicy.computeJumpPosition(firstVisible: 10, spanCount: 3, isMixedFullSpanList: false), -1)
        XCTAssertEqual(BackToTopPolicy.computeJumpPosition(firstVisible: 19, spanCount: 3, isMixedFullSpanList: false), 12)
        XCTAssertEqual(BackToTopPolicy.computeJumpPosition(firstVisible: 13, spanCount: 3, isMixedFullSpanList: true), 10)

        XCTAssertEqual(BackToTopPolicy.computeSmoothDurationMs(distancePx: 0, density: 2.0), 180)
        XCTAssertEqual(BackToTopPolicy.computeSmoothDurationMs(distancePx: 960, density: 2.0), 260)
        XCTAssertEqual(BackToTopPolicy.computeSmoothDurationMs(distancePx: 5000, density: 2.0), 360)
    }
}

private final class FakeGlobalSearchScheduler: GlobalSearchScheduler {
    final class Token {
        var cancelled = false
    }
    struct ScheduledItem {
        let delayMs: Int64
        let block: () -> Void
        let token: Token
    }

    var scheduled: [ScheduledItem] = []

    func postDelayed(_ action: @escaping () -> Void, delayMs: Int64) -> AnyObject {
        let token = Token()
        scheduled.append(ScheduledItem(delayMs: delayMs, block: action, token: token))
        return token
    }

    func removeCallbacks(_ handle: AnyObject) {
        if let token = handle as? Token {
            token.cancelled = true
        }
    }

    func fireNext() {
        while !scheduled.isEmpty {
            let item = scheduled.removeFirst()
            if !item.token.cancelled {
                item.block()
                return
            }
        }
    }

    func fireAllRemaining() {
        let copy = scheduled
        scheduled.removeAll()
        for item in copy where !item.token.cancelled {
            item.block()
        }
    }
}
