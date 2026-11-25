import XCTest
import Foundation
@testable import ComicCore

final class Parity2056FailoverAndRulesTests: XCTestCase {

    private let baseScript = """
    var source = {
      latest: function(p){return [];},
      search: function(q,p){return [];},
      filters: function(){return [];},
      category: function(f,p){return [];},
      detail: function(id){return {title:'t',chapters:[]};},
      chapters: function(id){return [];},
      chapter: function(u){return {images:['https://a.example.com/1.jpg']};}
    };
    """

    private func makeRuleJson(
        id: String,
        name: String? = nil,
        version: Int = 1,
        engineApi: Int = 3,
        baseUrl: String = "https://primary.example.com",
        hosts: [String]? = nil,
        requires: [String] = [],
        requiresVpn: Bool = false,
        fallbackOf: String? = nil,
        fallbackOrder: Int? = nil,
        fallbackMode: String? = nil
    ) -> [String: Any] {
        let host = URL(string: baseUrl)?.host ?? "primary.example.com"
        var json: [String: Any] = [
            "id": id,
            "name": name ?? "Source \(id)",
            "version": version,
            "engineApi": engineApi,
            "baseUrl": baseUrl,
            "hosts": hosts ?? [host],
            "requires": requires,
            "script": baseScript,
            "scriptSha256": RuleDefinition.sha(Data(baseScript.utf8))
        ]
        if requiresVpn {
            json["requiresVpn"] = true
        }
        if let fallbackOf {
            json["fallbackOf"] = fallbackOf
        }
        if let fallbackOrder {
            json["fallbackOrder"] = fallbackOrder
        }
        if let fallbackMode {
            json["fallbackMode"] = fallbackMode
        }
        return json
    }

    private func makeRule(
        id: String,
        name: String? = nil,
        version: Int = 1,
        engineApi: Int = 3,
        baseUrl: String = "https://primary.example.com",
        hosts: [String]? = nil,
        requires: [String] = [],
        requiresVpn: Bool = false,
        fallbackOf: String? = nil,
        fallbackOrder: Int? = nil,
        fallbackMode: String? = nil
    ) throws -> RuleDefinition {
        try RuleDefinition(json: makeRuleJson(
            id: id,
            name: name,
            version: version,
            engineApi: engineApi,
            baseUrl: baseUrl,
            hosts: hosts,
            requires: requires,
            requiresVpn: requiresVpn,
            fallbackOf: fallbackOf,
            fallbackOrder: fallbackOrder,
            fallbackMode: fallbackMode
        ))
    }

    // MARK: - 1. RuleDefinition 32MiB, Capabilities, Fallback & Hash Identity

    func testRuleDefinition32MiBCapabilitiesFallbackAndHashIdentity() throws {
        XCTAssertEqual(RuleDefinition.MAX_PACKAGE, 32 * 1024 * 1024)

        let ruleWithCaps = try makeRule(
            id: "caps_rule",
            requires: ["avif", "lenientCookies"],
            requiresVpn: true,
            fallbackOf: "main_source",
            fallbackOrder: 2,
            fallbackMode: "search"
        )
        XCTAssertTrue(ruleWithCaps.requiresCapability("avif"))
        XCTAssertTrue(ruleWithCaps.requiresCapability("lenientCookies"))
        XCTAssertTrue(ruleWithCaps.isFallback)
        XCTAssertEqual(ruleWithCaps.fallbackOf, "main_source")
        XCTAssertEqual(ruleWithCaps.fallbackOrder, 2)
        XCTAssertEqual(ruleWithCaps.fallbackMode, "search")

        let dict = ruleWithCaps.toDictionary()
        XCTAssertEqual(dict["fallbackOf"] as? String, "main_source")
        XCTAssertEqual(dict["fallbackOrder"] as? Int, 2)
        XCTAssertEqual(dict["fallbackMode"] as? String, "search")

        let roundTrip = try RuleDefinition(json: dict)
        XCTAssertEqual(roundTrip.hash, ruleWithCaps.hash)
        XCTAssertEqual(roundTrip.coreHash, ruleWithCaps.coreHash)

        // Changing fallback metadata or requiresVpn must alter identity hash
        let orderChanged = try makeRule(
            id: "caps_rule",
            requires: ["avif", "lenientCookies"],
            requiresVpn: true,
            fallbackOf: "main_source",
            fallbackOrder: 3,
            fallbackMode: "search"
        )
        XCTAssertNotEqual(orderChanged.hash, ruleWithCaps.hash)
        XCTAssertEqual(orderChanged.coreHash, ruleWithCaps.coreHash)

        let noVpn = try makeRule(
            id: "caps_rule",
            requires: ["avif", "lenientCookies"],
            requiresVpn: false,
            fallbackOf: "main_source",
            fallbackOrder: 2,
            fallbackMode: "search"
        )
        XCTAssertNotEqual(noVpn.hash, ruleWithCaps.hash)
        XCTAssertEqual(noVpn.coreHash, ruleWithCaps.coreHash)

        // Validation guards on fallback fields
        XCTAssertThrowsError(try makeRule(id: "self_fb", fallbackOf: "self_fb"))
        XCTAssertThrowsError(try makeRule(id: "bad_fb", fallbackOf: "bad/id"))
        XCTAssertThrowsError(try makeRule(id: "bad_mode", fallbackOf: "main_source", fallbackMode: "visible"))
        XCTAssertThrowsError(try makeRule(id: "bad_order", fallbackOf: "main_source", fallbackOrder: -1))
    }

    // MARK: - 2. RuleStore 512 Cap, Hidden Backups, Duplicate-ID Before Capability Skip, Official Retired Cleanup & Cascade

    func testRuleStoreCapHiddenBackupsDuplicateIdCheckRetiredCleanupAndCascade() throws {
        XCTAssertEqual(RuleStore.MAX_SOURCES, 512)

        // Duplicate-ID check must fire BEFORE unsupported-capability skip
        var dupUnsupported = makeRuleJson(id: "dup_id", requires: ["futureCapV99"])
        dupUnsupported["engineApi"] = 3
        let dupFirst = makeRuleJson(id: "dup_id")
        let dupBundle: [String: Any] = [
            "schema": "xx-comic.rules",
            "version": 1,
            "sources": [dupFirst, dupUnsupported]
        ]
        var seenIds = Set<String>()
        XCTAssertThrowsError(try RuleStore.parsePackageAllowEmpty(json: dupBundle, seenIds: &seenIds)) { error in
            XCTAssertFalse(error is UnsupportedRuleError)
            XCTAssertTrue(error.localizedDescription.contains("dup_id"))
        }

        // Official URL detection and retiredSources gating
        XCTAssertTrue(RuleRepository.isOfficialRepositoryUrl(RuleRepository.DEFAULT_URL))
        XCTAssertTrue(RuleRepository.isOfficialRepositoryUrl(RuleRepository.LEGACY_DEFAULT_URL))
        XCTAssertFalse(RuleRepository.isOfficialRepositoryUrl("https://mirror.example.com/rules/v3/index.json"))

        let primaryJson = makeRuleJson(id: "alpha", name: "Alpha", baseUrl: "https://alpha.example.com")
        let backupJson = makeRuleJson(
            id: "alpha_bak",
            name: "Alpha Backup",
            baseUrl: "https://bak.example.com",
            fallbackOf: "alpha",
            fallbackOrder: 1,
            fallbackMode: "search"
        )
        let retiredTargetJson = makeRuleJson(id: "old_dead", name: "Old Dead", baseUrl: "https://old.example.com")
        let pkgStr: ([String: Any]) throws -> String = { pkg in
            let data = try JSONSerialization.data(withJSONObject: pkg, options: [])
            return String(decoding: data, as: UTF8.self)
        }

        let activePkgStr = try pkgStr([
            "schema": "xx-comic.rules",
            "version": 1,
            "sources": [primaryJson, backupJson]
        ])
        let activePkgSha = RuleDefinition.sha(Data(activePkgStr.utf8))
        let officialIndexStr = try pkgStr([
            "schema": "xx-comic.rule-repository",
            "version": 1,
            "retiredSources": [["id": "old_dead", "name": "已下线测试源"]],
            "packages": [["url": "https://official.example.com/pkg.json", "sha256": activePkgSha]]
        ])
        let thirdPartyIndexStr = try pkgStr([
            "schema": "xx-comic.rule-repository",
            "version": 1,
            "retiredSources": [["id": "alpha", "name": "恶意清理不应生效"]],
            "packages": [["url": "https://third.example.com/pkg.json", "sha256": activePkgSha]]
        ])

        let thirdPrepared = try RuleSubscriptionUpdate.prepareCompatible(
            urls: ["https://third.example.com/index.json"],
            validator: { _ in },
            fetcher: { url in
                url.contains("index.json") ? thirdPartyIndexStr : activePkgStr
            }
        )
        XCTAssertTrue(thirdPrepared.retiredSources.isEmpty, "Non-official repository must not propagate retiredSources")

        let officialPrepared = try RuleSubscriptionUpdate.prepareCompatible(
            urls: [RuleRepository.DEFAULT_URL],
            validator: { _ in },
            fetcher: { url in
                url == RuleRepository.DEFAULT_URL ? officialIndexStr : activePkgStr
            }
        )
        XCTAssertEqual(officialPrepared.retiredSources["old_dead"], "已下线测试源")

        // RuleStore hidden backup visibility, retired cleanup, and backup cascade (except rollback)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ParityStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try RuleStore(directory: dir)
        let oldDeadV1 = try RuleDefinition(json: retiredTargetJson)
        _ = try store.updateSubscriptionsDetailed([oldDeadV1])
        XCTAssertEqual(store.entries().count, 1)

        // Upgrade alpha v1 -> v2, alpha_bak v1, plus retired cleanup for old_dead
        let outcome = try store.updateSubscriptionsDetailed(
            officialPrepared.rules,
            retiredOfficial: officialPrepared.retiredSources
        )
        XCTAssertEqual(outcome.cleanedRetiredCount, 1)
        XCTAssertEqual(store.retiredSources()["old_dead"], "已下线测试源")
        XCTAssertNil(store.entries().first(where: { $0.rule.id == "old_dead" }))
        XCTAssertEqual(store.entries().map(\.rule.id), ["alpha", "alpha_bak"])
        XCTAssertEqual(store.visibleEntries().map(\.rule.id), ["alpha"])
        XCTAssertTrue(store.isHiddenBackup("alpha_bak"))

        // RuleCatalog failover wrapping, hidden backup resolution & retired inspection
        let catalog = RuleCatalog(store: store, invoker: { _, _, _ in "[]" })
        XCTAssertEqual(catalog.visibleEntries().map(\.rule.id), ["alpha"])
        XCTAssertTrue(catalog.isHiddenBackup("alpha_bak"))
        XCTAssertEqual(catalog.primaryIdOrSelf("alpha_bak"), "alpha")
        XCTAssertEqual(catalog.backupsOf("alpha").map(\.id), ["alpha_bak"])
        XCTAssertTrue(catalog.comicSource("alpha") is FailoverComicSource)
        XCTAssertTrue(catalog.isRetiredSource("old_dead"))
        XCTAssertEqual(catalog.retiredSourceName("old_dead"), "已下线测试源")

        // Upgrade alpha & alpha_bak to v2 so rollback has previous versions on both
        let alphaV2 = try makeRule(id: "alpha", name: "Alpha V2", version: 2, baseUrl: "https://alpha.example.com")
        let bakV2 = try makeRule(
            id: "alpha_bak",
            name: "Alpha Backup V2",
            version: 2,
            baseUrl: "https://bak.example.com",
            fallbackOf: "alpha",
            fallbackOrder: 1,
            fallbackMode: "search"
        )
        _ = try store.updateSubscriptionsDetailed([alphaV2, bakV2])

        // Disable primary cascades to hidden backup; enable restores both
        try store.change(ids: ["alpha"], action: "disable")
        XCTAssertEqual(store.entries().first(where: { $0.rule.id == "alpha" })?.enabled, false)
        XCTAssertEqual(store.entries().first(where: { $0.rule.id == "alpha_bak" })?.enabled, false)

        try store.change(ids: ["alpha"], action: "enable")
        XCTAssertEqual(store.entries().first(where: { $0.rule.id == "alpha_bak" })?.enabled, true)

        // Rollback on primary must NOT cascade to hidden backup
        try store.change(ids: ["alpha"], action: "rollback")
        XCTAssertEqual(store.entries().first(where: { $0.rule.id == "alpha" })?.rule.version, 1)
        XCTAssertEqual(store.entries().first(where: { $0.rule.id == "alpha_bak" })?.rule.version, 2)

        // Delete primary cascades to hidden backup
        try store.change(ids: ["alpha"], action: "delete")
        XCTAssertTrue(store.entries().isEmpty)
    }

    // MARK: - 3. RuleBitmapTransform Vertical reverseBands + Dimension Bounds

    func testRuleBitmapTransformVerticalReverseBandsAndDimensionBounds() throws {
        // API 2 rejects vertical axis and dimension bounds
        XCTAssertThrowsError(try RuleBitmapTransform.validateAndSerialize(
            engineApi: 2,
            transform: ["type": "reverseBands", "bands": 3, "axis": "vertical"]
        ))
        XCTAssertThrowsError(try RuleBitmapTransform.validateAndSerialize(
            engineApi: 2,
            transform: ["type": "reverseBands", "bands": 3, "minWidth": 100]
        ))

        let tx = try RuleBitmapTransform.validateAndSerialize(
            engineApi: 3,
            transform: [
                "type": "reverseBands",
                "bands": 3,
                "axis": "vertical",
                "minWidth": 10,
                "maxWidth": 20,
                "minHeight": 2,
                "maxHeight": 10
            ]
        )
        XCTAssertTrue(tx.hasPrefix(RuleBitmapTransform.PREFIX_TX))
        XCTAssertTrue(RuleBitmapTransform.isSupported(tx))

        // Width 10 split into 3 bands: step=3, covered=6 -> leftmost remainder [0,4) moves to rightmost [6,10)
        let bounds = try RuleBitmapTransform.verticalBounds(width: 10, count: 3)
        XCTAssertEqual(bounds, [
            [7, 10, 0, 3],
            [4, 7, 3, 6],
            [0, 4, 6, 10]
        ])

        let ops = RuleBitmapTransform.plan(width: 10, height: 2, origWidth: 10, origHeight: 2, transform: tx)
        XCTAssertEqual(ops.count, 3)
        XCTAssertEqual(ops[2].srcLeft, 0)
        XCTAssertEqual(ops[2].srcRight, 4)
        XCTAssertEqual(ops[2].dstLeft, 6)
        XCTAssertEqual(ops[2].dstRight, 10)

        // Verify pixel movement for a 10x1 strip [0,1,2,3,4,5,6,7,8,9]
        let row: [UInt32] = (0..<10).map { UInt32($0) }
        let restored = RuleBitmapTransform.applyToArgb(row, width: 10, height: 1, origWidth: 10, origHeight: 2, transform: tx)
        XCTAssertEqual(restored, [7, 8, 9, 4, 5, 6, 0, 1, 2, 3])

        // Out-of-bounds original dimensions skip transformation cleanly
        XCTAssertTrue(RuleBitmapTransform.plan(width: 10, height: 2, origWidth: 9, origHeight: 2, transform: tx).isEmpty)
        XCTAssertTrue(RuleBitmapTransform.plan(width: 10, height: 2, origWidth: 21, origHeight: 2, transform: tx).isEmpty)
        XCTAssertTrue(RuleBitmapTransform.plan(width: 10, height: 2, origWidth: 10, origHeight: 1, transform: tx).isEmpty)
        XCTAssertTrue(RuleBitmapTransform.plan(width: 10, height: 2, origWidth: 10, origHeight: 11, transform: tx).isEmpty)
    }

    // MARK: - 4. FailoverRouteStore, FailoverContextRegistry, FailoverChapterAligner, FailoverComicSource

    func testFailoverRouteStorePersistenceReverseLookupAndLruEviction() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RouteStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("failover-routes.json")

        let store = FailoverRouteStore(fileURL: fileURL, maxEntries: 4) // Clamps to minimum 16
        for i in 1...17 {
            store.saveRoute(comicId: "canon-\(i)", memberId: "bak", memberRawId: "raw-\(i)")
        }
        XCTAssertEqual(store.size(), 16)
        XCTAssertNil(store.findMemberRawId("canon-1", memberId: "bak"), "Oldest entry should be evicted by LRU")
        XCTAssertNil(store.findCanonicalComicId(memberId: "bak", memberRawId: "raw-1"))
        XCTAssertEqual(store.findMemberRawId("canon-17", memberId: "bak"), "raw-17")
        XCTAssertEqual(store.findCanonicalComicId(memberId: "bak", memberRawId: "raw-17"), "canon-17")

        let reloaded = FailoverRouteStore(fileURL: fileURL, maxEntries: 16)
        XCTAssertEqual(reloaded.size(), 16)
        XCTAssertEqual(reloaded.findMemberRawId("canon-2", memberId: "bak"), "raw-2")
        XCTAssertEqual(reloaded.findCanonicalComicId(memberId: "bak", memberRawId: "raw-17"), "canon-17")
    }

    func testFailoverContextRegistryDebounceCooldownAndCorruptSafety() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HealthReg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let healthFile = dir.appendingPathComponent("failover-health.json")

        // Corrupt file must NOT crash or be overwritten on load, and backs up to .corrupt before next atomic write
        try Data("{not-valid-json".utf8).write(to: healthFile)
        let afterCorrupt = FailoverContextRegistry(healthFileURL: healthFile)
        XCTAssertFalse(afterCorrupt.lastPersistenceError.isEmpty)
        XCTAssertEqual(try String(contentsOf: healthFile, encoding: .utf8), "{not-valid-json", "Load failure must not overwrite original corrupt store")
        afterCorrupt.markUnhealthy("m_blocked")
        afterCorrupt.flushPersistenceForTesting()
        let filesInDir = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(filesInDir.contains { $0.contains(".corrupt") })
        XCTAssertFalse(afterCorrupt.isHealthy("m_blocked"))

        // Valid persistence lifecycle with 150ms debounce & flush
        let validDir = dir.appendingPathComponent("valid", isDirectory: true)
        try FileManager.default.createDirectory(at: validDir, withIntermediateDirectories: true)
        let validFile = validDir.appendingPathComponent("failover-health.json")
        let reg = FailoverContextRegistry(healthFileURL: validFile)
        XCTAssertTrue(reg.isHealthy("src_a"))
        reg.markUnhealthy("src_a")
        XCTAssertFalse(reg.isHealthy("src_a"))
        XCTAssertGreaterThan(reg.unhealthyRemainingMs("src_a"), 0)
        reg.flushPersistenceForTesting()

        let reloaded = FailoverContextRegistry(healthFileURL: validFile)
        XCTAssertFalse(reloaded.isHealthy("src_a"))
        XCTAssertLessThanOrEqual(reloaded.unhealthyRemainingMs("src_a"), FailoverContextRegistry.maxPersistedCooldownMs)
        reloaded.markHealthy("src_a")
        XCTAssertTrue(reloaded.isHealthy("src_a"))
    }

    func testFailoverChapterAlignerKeysAndOneToOneMatching() {
        XCTAssertEqual(FailoverChapterAligner.stripTitleTags("进击的巨人【完结】[全彩] (最新)"), "进击的巨人")
        XCTAssertGreaterThanOrEqual(
            FailoverChapterAligner.titleMatchScore(candidateTitle: "进击的巨人【完结】", targetTitle: "进击的巨人"),
            9500
        )
        XCTAssertEqual(FailoverChapterAligner.parseChineseNumber("零"), 0)
        XCTAssertEqual(FailoverChapterAligner.parseChineseNumber("十二"), 12)
        XCTAssertEqual(FailoverChapterAligner.parseChineseNumber("一千零三"), 1003)

        XCTAssertEqual(FailoverChapterAligner.extractChapterKey("第十二话 起始"), "ep:12")
        XCTAssertEqual(FailoverChapterAligner.extractChapterKey("第005话"), "ep:5")
        XCTAssertEqual(FailoverChapterAligner.extractChapterKey("5.5话"), "ep:5.5")
        XCTAssertEqual(FailoverChapterAligner.extractChapterKey("最终话"), "sp:finale")
        XCTAssertEqual(FailoverChapterAligner.extractChapterKey("番外篇"), "sp:extra")

        let refs = [
            Chapter(chapterId: "r1", title: "第1话", url: "https://p.com/1"),
            Chapter(chapterId: "r2", title: "第12话", url: "https://p.com/12"),
            Chapter(chapterId: "r3", title: "番外篇", url: "https://p.com/ex")
        ]
        let cands = [
            Chapter(chapterId: "c1", title: "第十二话 冲突", url: "https://b.com/12"),
            Chapter(chapterId: "c2", title: "第1话 序幕", url: "https://b.com/1"),
            Chapter(chapterId: "c3", title: "番外篇", url: "https://b.com/ex"),
            Chapter(chapterId: "c4", title: "第99话", url: "https://b.com/99")
        ]
        let aligned = FailoverChapterAligner.alignChapters(references: refs, candidates: cands)
        XCTAssertEqual(aligned.map(\.chapterId), ["r2", "r1", "r3", "c4"])

        let matched = FailoverChapterAligner.findMatchingChapter(
            target: Chapter(chapterId: "t", title: "第十二话", url: ""),
            candidates: cands
        )
        XCTAssertEqual(matched?.chapterId, "c1")
    }

    func testFailoverComicSourceFailoverNotFoundKanEhSearchFiltersAndReferer() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FailoverSrc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let primaryRule = try makeRule(id: "pri", name: "Primary", baseUrl: "https://pri.example.com")
        let bakMissRule = try makeRule(
            id: "bak_miss",
            name: "BackupMiss",
            baseUrl: "https://miss.example.com",
            fallbackOf: "pri",
            fallbackOrder: 1,
            fallbackMode: "search"
        )
        let backupRule = try makeRule(
            id: "bak",
            name: "Backup",
            baseUrl: "https://bak.example.com",
            fallbackOf: "pri",
            fallbackOrder: 2,
            fallbackMode: "kanId"
        )
        let ehBackupRule = try makeRule(
            id: "bak_eh",
            name: "BackupEH",
            baseUrl: "https://eh.example.com",
            fallbackOf: "pri",
            fallbackOrder: 3,
            fallbackMode: "ehGid"
        )

        final class MockFlags: @unchecked Sendable {
            var priFailsLatest = true
            var bakDetailCalls: [String] = []
            var ehDetailCalls: [String] = []
            var bakCategoryFilters: [[String: String]] = []
        }
        let flags = MockFlags()

        let jsonStr: (Any) -> String = { obj in
            let data = try! JSONSerialization.data(withJSONObject: obj, options: [])
            return String(decoding: data, as: UTF8.self)
        }

        let primary = ScriptComicSource(rule: primaryRule) { _, method, _ in
            switch method {
            case "latest":
                if flags.priFailsLatest { throw RuleError("primary down") }
                return jsonStr(["items": [["id": "kan/100", "title": "测试漫画"]], "hasMore": false])
            case "filters":
                return jsonStr([[
                    "key": "status",
                    "label": "状态",
                    "options": [["value": "all", "label": "全部"], ["value": "1", "label": "连载中"]]
                ]])
            case "category":
                throw RuleError("primary category down")
            case "detail":
                throw RuleError("primary detail network down")
            case "chapters":
                return jsonStr([])
            case "search":
                return jsonStr(["items": [], "hasMore": false])
            case "chapter":
                return jsonStr(["images": ["https://pri.example.com/1.jpg"]])
            default:
                return jsonStr([])
            }
        }

        let bakMiss = ScriptComicSource(rule: bakMissRule) { _, method, _ in
            switch method {
            case "latest", "category":
                throw RuleError("miss member feed down")
            case "filters":
                return jsonStr([])
            case "search":
                return jsonStr(["items": [], "hasMore": false]) // triggers NotFoundOnMemberError in resolveByTitleMatch
            default:
                throw RuleError("unexpected call on bakMiss")
            }
        }

        let backup = ScriptComicSource(rule: backupRule) { _, method, args in
            switch method {
            case "latest":
                return jsonStr([
                    "items": [
                        ["id": "kan/200", "title": "备线漫画"],
                        ["id": "200-abc123", "title": "EH作品"]
                    ],
                    "hasMore": false
                ])
            case "filters":
                return jsonStr([[
                    "key": "st",
                    "label": "进度",
                    "options": [["value": "0", "label": "全部"], ["value": "on", "label": "ongoing"]]
                ]])
            case "category":
                if let f = args.first as? [String: String] {
                    flags.bakCategoryFilters.append(f)
                }
                return jsonStr(["items": [["id": "kan/200", "title": "分类结果"]], "hasMore": false])
            case "detail":
                let cid = (args.first as? String) ?? ""
                flags.bakDetailCalls.append(cid)
                if cid == "100" || cid == "bak_found_1" {
                    return jsonStr([
                        "id": cid,
                        "title": "测试漫画",
                        "author": "作者",
                        "status": "连载"
                    ])
                }
                throw RuleError("HTTP 404")
            case "chapters":
                return jsonStr([["id": "ch1", "title": "第1话", "url": "https://bak.example.com/ch/1"]])
            case "search":
                let q = (args.first as? String) ?? ""
                if q == "搜索标题" {
                    return jsonStr(["items": [["id": "bak_found_1", "title": "搜索标题【最新】"]], "hasMore": false])
                }
                return jsonStr(["items": [], "hasMore": false])
            case "chapter":
                return jsonStr(["images": ["https://bak.example.com/img/1.jpg"]])
            default:
                return jsonStr([])
            }
        }

        let ehBackup = ScriptComicSource(rule: ehBackupRule) { _, method, args in
            switch method {
            case "search":
                return jsonStr(["items": [], "hasMore": false])
            case "detail":
                let cid = (args.first as? String) ?? ""
                flags.ehDetailCalls.append(cid)
                if cid == "200" {
                    return jsonStr([
                        "id": cid,
                        "title": "EH作品",
                        "author": "作者EH",
                        "status": "完结"
                    ])
                }
                throw RuleError("HTTP 404")
            case "chapters":
                return jsonStr([["id": "eh1", "title": "第1话", "url": "https://eh.example.com/ch/1"]])
            default:
                return jsonStr([])
            }
        }

        let routes = FailoverRouteStore(fileURL: dir.appendingPathComponent("routes.json"))
        let registry = FailoverContextRegistry(healthFileURL: dir.appendingPathComponent("health.json"))
        let failover = FailoverComicSource(
            identitySourceId: "pri",
            displayName: "Primary",
            members: [primary, bakMiss, backup, ehBackup],
            routeStore: routes,
            contextRegistry: registry
        )
        XCTAssertTrue(failover.hasBackupFailover)
        XCTAssertEqual(failover.referer(forUrl: "https://bak.example.com/ch/1"), backup.referer)
        XCTAssertEqual(failover.resolveOwnerMemberIdByUrl("https://bak.example.com/ch/1"), "bak")

        // 1. Primary fails -> marks unhealthy & rewrites backup listing (kan/200 deterministic + @via~bak~ for unmapped ID)
        let latest = try await failover.latest(page: 1)
        XCTAssertFalse(registry.isHealthy("pri"))
        XCTAssertEqual(latest.map(\.comicId), ["pri:kan/200", "pri:@via~bak~200-abc123"])

        // 2. Clear health so pri/bak_miss are tried; NotFoundOnMemberError on bak_miss MUST NOT mark bak_miss unhealthy
        registry.clearHealth()
        failover.seedFromSummary(ComicSummary(sourceId: "pri", comicId: "pri:comic/title_only", title: "搜索标题"))
        let searchDetail = try await failover.detail(comicId: "pri:comic/title_only")
        XCTAssertEqual(searchDetail.summary.title, "测试漫画")
        XCTAssertFalse(registry.isHealthy("pri"), "IO error must mark primary unhealthy")
        XCTAssertTrue(registry.isHealthy("bak_miss"), "NotFoundOnMember must not mark bak_miss unhealthy")
        XCTAssertEqual(routes.findMemberRawId("pri:comic/title_only", memberId: "bak"), "bak_found_1")

        // 3. Deterministic kanId and ehGid direct probes on backups
        let kanDetail = try await failover.detail(comicId: "https://pri.example.com/kan/100")
        XCTAssertEqual(kanDetail.summary.comicId, "https://pri.example.com/kan/100")
        XCTAssertTrue(flags.bakDetailCalls.contains("100"))

        let ehDetail = try await failover.detail(comicId: "pri:200-abc123")
        XCTAssertEqual(ehDetail.summary.title, "EH作品")
        let ehChapters = try await failover.chapters(comicId: "pri:200-abc123")
        XCTAssertEqual(ehChapters.first?.url, "https://eh.example.com/ch/1")
        XCTAssertTrue(flags.ehDetailCalls.contains("200"))

        // 4. Filter synonym translation ("连载中" -> "ongoing" value "on")
        registry.clearHealth()
        _ = try await failover.filterGroups()
        let cat = try await failover.category(filters: ["status": "1"], page: 1)
        XCTAssertEqual(cat.count, 1)
        XCTAssertEqual(flags.bakCategoryFilters.last?["st"], "on")
    }

    // MARK: - 5. RuleCallPriority, ProtectedSessionHttp, RuleWebRenderer, Manwa, DetailSourceSearch, RetiredComicSource

    func testRuleCallPriorityTaskLocalAndThreadDictionary() async throws {
        XCTAssertFalse(RuleCallPriority.currentIsBackground())

        let syncInside = RuleCallPriority.withBackgroundPriority {
            RuleCallPriority.currentIsBackground()
        }
        XCTAssertTrue(syncInside)
        XCTAssertFalse(RuleCallPriority.currentIsBackground())

        let asyncInside = await RuleCallPriority.withBackgroundPriority { () -> Bool in
            await Task.yield()
            return RuleCallPriority.currentIsBackground()
        }
        XCTAssertTrue(asyncInside)
        XCTAssertFalse(RuleCallPriority.currentIsBackground())

        // Restore after throw
        struct DummyErr: Error {}
        XCTAssertThrowsError(try RuleCallPriority.withBackgroundPriority {
            XCTAssertTrue(RuleCallPriority.currentIsBackground())
            throw DummyErr()
        })
        XCTAssertFalse(RuleCallPriority.currentIsBackground())
    }

    func testProtectedSessionHttpCrossOriginCookieStripAndCfChallenge() throws {
        final class MemoryCookieStore: ProtectedSessionHttp.CookieStore, @unchecked Sendable {
            private let lock = NSLock()
            private var byHost: [String: [String: String]] = [:]

            func getCookie(for url: String) -> String? {
                guard let hostKey = originKey(url) else { return nil }
                lock.lock()
                defer { lock.unlock() }
                let pairs = byHost[hostKey] ?? [:]
                guard !pairs.isEmpty else { return nil }
                return pairs.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            }

            func setCookie(url: String, value: String) {
                guard let hostKey = originKey(url) else { return }
                let first = value.split(separator: ";", maxSplits: 1).first.map(String.init) ?? value
                guard let eq = first.firstIndex(of: "=") else { return }
                let k = String(first[..<eq]).trimmingCharacters(in: .whitespaces)
                let v = String(first[first.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                lock.lock()
                byHost[hostKey, default: [:]][k] = v
                lock.unlock()
            }

            func flush() {}

            private func originKey(_ url: String) -> String? {
                guard let parsed = URL(string: url), let h = parsed.host else { return nil }
                let p = parsed.port ?? 80
                return "\(h):\(p)"
            }
        }

        let serverA = try LocalTestHTTPServer()
        let serverB = try LocalTestHTTPServer()
        let urlBFinal = serverB.url(for: "/landing")

        serverA.route("/start") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 302,
                statusText: "Found",
                headers: [
                    "Location": "/same",
                    "Set-Cookie": "sid=secret123; Path=/"
                ]
            )
        }
        serverA.route("/same") { req in
            let cookieSeen = req.header("Cookie") ?? ""
            XCTAssertTrue(cookieSeen.contains("sid=secret123"))
            return LocalTestHTTPServer.Response(
                statusCode: 302,
                statusText: "Found",
                headers: ["Location": urlBFinal]
            )
        }
        serverB.route("/landing") { req in
            let leaked = req.header("Cookie") ?? ""
            return LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "text/plain"],
                body: Data("cookie=\(leaked)".utf8)
            )
        }
        serverA.route("/cf") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 403,
                statusText: "Forbidden",
                headers: ["cf-mitigated": "challenge"],
                body: Data("blocked".utf8)
            )
        }

        serverA.start()
        serverB.start()
        defer {
            serverA.stop()
            serverB.stop()
        }

        XCTAssertFalse(ProtectedSessionHttp.isSameOrigin(URL(string: serverA.url(for: "/")), URL(string: serverB.url(for: "/"))))

        let cookies = MemoryCookieStore()
        let crossResult = try ProtectedSessionHttp.fetch(
            url: serverA.url(for: "/start"),
            userAgent: "TestAgent",
            connectTimeoutMs: 5000,
            readTimeoutMs: 5000,
            cookieStore: cookies
        )
        XCTAssertEqual(crossResult.statusCode, 200)
        XCTAssertEqual(crossResult.finalUrl, urlBFinal)
        XCTAssertEqual(crossResult.body, "cookie=", "Cross-origin redirect must strip Cookie header")

        let cfResult = try ProtectedSessionHttp.fetch(
            url: serverA.url(for: "/cf"),
            userAgent: "TestAgent",
            connectTimeoutMs: 5000,
            readTimeoutMs: 5000,
            cookieStore: cookies
        )
        XCTAssertEqual(cfResult.statusCode, 403)
        XCTAssertEqual(cfResult.mitigated, "challenge")
        XCTAssertEqual(cfResult.body, "")
    }

    func testRuleWebRendererStaticHelpersAndManwaAndDetailSearchAndRetired() async throws {
        // RuleWebRenderer static helpers
        XCTAssertTrue(RuleWebRenderer.isErrorOrBlankUrl(nil))
        XCTAssertTrue(RuleWebRenderer.isErrorOrBlankUrl("about:blank"))
        XCTAssertTrue(RuleWebRenderer.isErrorOrBlankUrl("chrome-error://chromewebdata/"))
        XCTAssertFalse(RuleWebRenderer.isErrorOrBlankUrl("https://example.com/page"))

        XCTAssertTrue(RuleWebRenderer.isDocumentReadyForCapture(pageFinished: true, actualUrl: "https://example.com", readyState: "complete"))
        XCTAssertFalse(RuleWebRenderer.isDocumentReadyForCapture(pageFinished: false, actualUrl: "https://example.com", readyState: "complete"))
        XCTAssertFalse(RuleWebRenderer.isDocumentReadyForCapture(pageFinished: true, actualUrl: "about:blank", readyState: "complete"))

        XCTAssertTrue(RuleWebRenderer.isBlankHtml("<html><head></head><body>   \n</body></html>"))
        XCTAssertFalse(RuleWebRenderer.isBlankHtml("<html><body><div>ok</div></body></html>"))
        XCTAssertTrue(RuleWebRenderer.isHeavySubresource("https://cdn.example.com/a.avif"))

        XCTAssertThrowsError(try RuleWebRenderer.buildRenderResult(
            requestedUrl: "https://a.com", actualUrl: "about:blank", html: "", httpStatus: 500, networkError: "timeout"
        ))
        XCTAssertThrowsError(try RuleWebRenderer.buildRenderResult(
            requestedUrl: "https://a.com", actualUrl: "https://a.com", html: "<html><body></body></html>", httpStatus: 503, networkError: nil
        ))
        let rendered = try RuleWebRenderer.buildRenderResult(
            requestedUrl: "https://a.com", actualUrl: "https://a.com/final#hash", html: "<html><body>ok</body></html>", httpStatus: 0, networkError: nil
        )
        XCTAssertEqual(rendered["url"] as? String, "https://a.com/final")
        XCTAssertEqual(rendered["status"] as? Int, 200)

        // Manwa 18 mirrors, 6 publish routers, 5 IMAGE_CDNS & mirror failover
        XCTAssertEqual(ManwaComicSource.mirrors.count, 18)
        XCTAssertEqual(ManwaComicSource.publishRouters.count, 6)
        XCTAssertEqual(ManwaImageDecoder.IMAGE_CDNS.count, 5)
        XCTAssertTrue(ManwaImageDecoder.isDeadImageHost("a.mwtuwu.cc"))
        XCTAssertFalse(ManwaImageDecoder.isDeadImageHost("tu.mwzu.cc"))

        let resolvedCdn0 = ManwaImageDecoder.resolveImageUrl("https://mwtuwu.cc/en_images/a/1.jpg", attempt: 0)
        let resolvedCdn1 = ManwaImageDecoder.resolveImageUrl("https://mwtuwu.cc/en_images/a/1.jpg", attempt: 1)
        XCTAssertNotEqual(resolvedCdn0, resolvedCdn1)
        XCTAssertTrue(resolvedCdn0.hasSuffix("/en_images/a/1.jpg"))
        ManwaImageDecoder.markImageHostSuccess("https://tu.mwzu.cc/en_images/a/1.jpg")
        XCTAssertEqual(ManwaImageDecoder.preferredCdn, "https://tu.mwzu.cc")

        final class MockManwaTransport: HTTPTransport, @unchecked Sendable {
            private let lock = NSLock()
            var requestedHosts: [String] = []
            var returnFatal403 = false

            func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
                let host = url.host ?? ""
                lock.lock()
                requestedHosts.append(host)
                let fatal = returnFatal403
                lock.unlock()
                if fatal {
                    return HTTPResponse(data: Data(#"{"code":403,"data":{}}"#.utf8), statusCode: 200, finalURL: url)
                }
                if host == "manwadz.cc" {
                    throw URLError(.cannotConnectToHost)
                }
                if host == "www.manwacn.cc" && url.path.contains("/api/search") {
                    let json = #"{"code":200,"data":{"list":[{"id":999,"title":"测试漫蛙","cover":"https://tu.mwzu.cc/en_images/999/cover.jpg"}]}}"#
                    return HTTPResponse(data: Data(json.utf8), statusCode: 200, finalURL: url)
                }
                throw URLError(.badServerResponse)
            }
        }
        let manwaTransport = MockManwaTransport()
        let manwa = ManwaComicSource(transport: manwaTransport)
        let manwaResults = try await manwa.search(keyword: "测试", page: 1)
        XCTAssertEqual(manwaResults.count, 1)
        XCTAssertEqual(manwa.activeBaseUrl, "https://www.manwacn.cc")
        XCTAssertEqual(manwaResults.first?.comicId, "manwa:999")

        // FatalManwaError stops failover on first host instead of trying remaining mirrors
        let fatalTransport = MockManwaTransport()
        fatalTransport.returnFatal403 = true
        let fatalManwa = ManwaComicSource(transport: fatalTransport)
        do {
            _ = try await fatalManwa.search(keyword: "测试", page: 1)
            XCTFail("Expected FatalManwaError")
        } catch is FatalManwaError {
            XCTAssertEqual(fatalTransport.requestedHosts.count, 1)
        }

        // RuleHostExecutor 3-channel selection & foreground reserve
        XCTAssertEqual(RuleHostExecutor.foregroundPermitsCount, 4)
        XCTAssertEqual(RuleHostExecutor.searchPermitsCount, 12)
        XCTAssertEqual(RuleHostExecutor.backgroundPermitsCount, 2)
        XCTAssertEqual(RuleHostExecutor.hostQueueCapacity, 64)
        XCTAssertEqual(RuleHostExecutor.searchQueueReserveForForeground, 8)
        XCTAssertEqual(RuleHostExecutor.selectPermitChannel(method: "search", isBackground: true), .search)
        XCTAssertEqual(RuleHostExecutor.selectPermitChannel(method: "detail", isBackground: true), .background)
        XCTAssertEqual(RuleHostExecutor.selectPermitChannel(method: "detail", isBackground: false), .foreground)
        XCTAssertTrue(RuleHostExecutor.shouldRejectForForegroundReserve(isSearch: true, isBackground: false, queuedHostTasks: 56))
        XCTAssertTrue(RuleHostExecutor.shouldRejectForForegroundReserve(isSearch: false, isBackground: true, queuedHostTasks: 56))
        XCTAssertFalse(RuleHostExecutor.shouldRejectForForegroundReserve(isSearch: false, isBackground: false, queuedHostTasks: 56))

        // DetailSourceSearch timeout, delayed start, flushPendingStartNow & titleExcludeFilter
        let ruleSingle = try makeRule(id: "ds_single", baseUrl: "https://ds1.example.com")
        let ruleBak = try makeRule(id: "ds_bak", baseUrl: "https://ds2.example.com", fallbackOf: "ds_single")
        let srcSingle = ScriptComicSource(rule: ruleSingle) { _, method, _ in
            method == "search" ? #"[{"id":"1","title":"目标漫画"},{"id":"2","title":"黑名单漫画"}]"# : "[]"
        }
        let srcBak = ScriptComicSource(rule: ruleBak) { _, _, _ in "[]" }
        let chain = FailoverComicSource(identitySourceId: "ds_single", displayName: "Single", members: [srcSingle, srcBak])

        XCTAssertEqual(DetailSourceSearch.effectiveTimeoutMs(source: srcSingle, timeoutMs: 10_000), 10_000)
        XCTAssertEqual(DetailSourceSearch.effectiveTimeoutMs(source: chain, timeoutMs: 10_000), 16_000)

        let searchHelper = DetailSourceSearch(timeoutMs: 10_000, maxConcurrency: 3, callbackQueue: DispatchQueue.global())
        let doneExp = expectation(description: "DetailSourceSearch completed")
        final class SearchCapture: @unchecked Sendable {
            var items: [ComicSummary] = []
            var fulfilled = false
        }
        let capture = SearchCapture()
        searchHelper.startDelayed(
            delayMs: 1200,
            current: ComicSummary(sourceId: "other", comicId: "0", title: "目标漫画"),
            sources: [srcSingle],
            titleExcludeFilter: { title in title.contains("黑名单") }
        ) { items, loading in
            if !loading && !capture.fulfilled {
                capture.items = items
                capture.fulfilled = true
                doneExp.fulfill()
            }
        }
        searchHelper.flushPendingStartNow()
        await fulfillment(of: [doneExp], timeout: 3.0)
        XCTAssertEqual(capture.items.map(\.title), ["目标漫画"])

        // RetiredComicSource: all 16 builtin IDs
        let expectedRetiredIds = [
            "baozimh", "mhua5", "duya", "xcomic", "mh250", "xiuxiu", "aimi",
            "comic51", "favcomic", "waiwai", "hiperdex", "momic", "jcomic", "fuman", "pipigou_bika", "cl1024_pic"
        ]
        XCTAssertEqual(RetiredComicSource.builtinRetiredSources.count, 16)
        for rid in expectedRetiredIds {
            XCTAssertTrue(RetiredComicSource.isBuiltinRetired(rid), "Missing retired ID: \(rid)")
            XCTAssertFalse((RetiredComicSource.builtinRetiredName(for: rid) ?? "").isEmpty)
        }
    }
}
