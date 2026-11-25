import XCTest
import Foundation
@testable import ComicCore

final class Parity2056RecommendTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Parity2056Rec-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - 1. RecommendSourceClassifier

    func testClassifierCanonicalGenresNoisyTagsPlansAndAll27TextRules() {
        XCTAssertEqual(RecommendSourceClassifier.canonicalGenres.count, 22)
        XCTAssertEqual(RecommendSourceClassifier.normalizeGenreTag("愛情漫畫"), "恋爱")
        XCTAssertEqual(RecommendSourceClassifier.normalizeGenreTag("#校园(123)"), "校园")
        XCTAssertEqual(RecommendSourceClassifier.normalizeGenreTag("题材：熱血"), "热血")
        XCTAssertEqual(RecommendSourceClassifier.extractCanonicalGenres(text: "恋爱 / 搞笑 · 修仙"), ["恋爱", "搞笑", "玄幻"])

        for noisy in ["连载中", "完结", "第12话", "100回", "国漫", "all", "少女漫画", "全部"] {
            XCTAssertTrue(RecommendSourceClassifier.isNoisyTag(noisy), "Expected noisy: \(noisy)")
        }

        let groups = [
            SourceFilterGroup(key: "sort", label: "排序", options: [
                SourceFilterOption(label: "全部", value: "all"),
                SourceFilterOption(label: "編輯推薦", value: "rec"),
                SourceFilterOption(label: "熱門排行", value: "hot"),
                SourceFilterOption(label: "最近更新", value: "latest")
            ]),
            SourceFilterGroup(key: "theme", label: "题材", options: [
                SourceFilterOption(label: "全部", value: "all"),
                SourceFilterOption(label: "熱血", value: "rx"),
                SourceFilterOption(label: "懸疑", value: "xy")
            ]),
            SourceFilterGroup(key: "state", label: "状态", options: [
                SourceFilterOption(label: "全部", value: "all"),
                SourceFilterOption(label: "连载", value: "1")
            ])
        ]
        XCTAssertEqual(RecommendSourceClassifier.detectFeaturedRecommendPlan(groups)?.matchedValue, "rec")
        XCTAssertEqual(RecommendSourceClassifier.detectHotRankingPlan(groups)?.matchedValue, "hot")
        XCTAssertEqual(RecommendSourceClassifier.detectLatestPlan(groups)?.matchedValue, "latest")
        XCTAssertEqual(RecommendSourceClassifier.detectGenrePlan(groups, canonicalGenre: "热血")?.matchedValue, "rx")
        XCTAssertNil(RecommendSourceClassifier.detectGenrePlan(groups, canonicalGenre: "连载"))

        // Verify all 27 inferGenresFromText rule categories + 240 char desc cap + max 3 cap
        let sampleInputs: [(String, [String])] = [
            ("转生异世界", ["奇幻", "穿越"]),
            ("快穿穿书", ["穿越"]),
            ("勇者讨伐魔王", ["奇幻", "冒险"]),
            ("公会迷宫寻宝", ["冒险"]),
            ("精灵魔物", ["奇幻"]),
            ("魔法巫师", ["魔幻"]),
            ("修仙炼气渡劫", ["玄幻"]),
            ("宗门弟子", ["武侠", "玄幻"]),
            ("武林剑客内功", ["武侠"]),
            ("仙侠奇缘", ["古风", "玄幻"]),
            ("江湖风云", ["古风", "武侠"]),
            ("长安宫斗朝堂", ["古风"]),
            ("三国大唐王朝", ["历史"]),
            ("高校社团学生会", ["校园"]),
            ("初恋暗恋告白", ["恋爱"]),
            ("轻百双女主", ["百合"]),
            ("悬案谜团", ["悬疑"]),
            ("密室侦探破案", ["悬疑", "推理"]),
            ("星际机甲末日", ["科幻"]),
            ("社畜职场霸总", ["都市"]),
            ("沙雕爆笑吐槽", ["搞笑"]),
            ("丧尸怪谈驱魔", ["恐怖"]),
            ("武道拳击格斗家", ["热血", "格斗"]),
            ("热血决斗", ["热血"]),
            ("足球电竞甲子园", ["竞技"]),
            ("露营猫咪慢生活", ["治愈", "日常"]),
            ("咖啡馆美食料理", ["日常"])
        ]
        for (text, expectedGenres) in sampleInputs {
            let inferred = RecommendSourceClassifier.inferGenresFromText(title: text, subtitle: "", description: "")
            for g in expectedGenres {
                XCTAssertTrue(inferred.contains(g), "Rule for '\(text)' missing '\(g)', got \(inferred)")
            }
        }

        // 240-char description truncation ignores keywords beyond 240 chars, and max 3 genres returned
        let paddedDesc = String(repeating: "a", count: 245) + "魔法恐怖校园恋爱"
        XCTAssertTrue(RecommendSourceClassifier.inferGenresFromText(title: "普通故事", subtitle: "", description: paddedDesc).isEmpty)
        let multi = RecommendSourceClassifier.inferGenresFromText(title: "热血恋爱悬疑奇幻冒险校园", subtitle: "", description: "")
        XCTAssertEqual(multi.count, 3)
    }

    // MARK: - 2. RecommendProfileStore

    func testProfileStoreCapsUndoResetAndCorruptSafety() throws {
        let file = tempDir.appendingPathComponent(RecommendProfileStore.fileName)
        let store = RecommendProfileStore(storageFile: file)
        XCTAssertTrue(store.isPersonalizationEnabled)

        store.setSelectedGenres(["愛情", "搞笑", "连载"])
        XCTAssertEqual(store.getSelectedGenres(), ["恋爱", "搞笑"])
        XCTAssertFalse(store.togglePreferredGenre("恋爱"))
        XCTAssertTrue(store.togglePreferredGenre("悬疑"))

        // Dislike & undo
        store.recordDislike(normalizedTitle: "t1", displayTitle: "T1", genres: ["恋爱"], author: "A1", timestamp: 100)
        store.recordDislike(normalizedTitle: "t2", displayTitle: "T2", genres: ["搞笑"], author: "A2", timestamp: 200)
        XCTAssertTrue(store.isDisliked("t1"))
        XCTAssertTrue(store.undoLastDislike())
        XCTAssertFalse(store.isDisliked("t2"))
        XCTAssertTrue(store.undoDislike("t1"))
        XCTAssertFalse(store.isDisliked("t1"))

        // Click cap = 100 (deduplicates & evicts oldest)
        for i in 1...110 {
            store.recordClick(
                normalizedTitle: "click_\(i)",
                title: "Click \(i)",
                sourceId: "s1",
                author: "Auth",
                genres: ["热血"],
                timestamp: Int64(1000 + i)
            )
        }
        XCTAssertEqual(store.getClickedRecords().count, 100)
        XCTAssertEqual(store.getClickedRecords().first?.normalizedTitle, "click_110")

        // Impression cap = 2000 (evicts oldest by max(lastImpressionAt, lastClickAt))
        let batchKeys = (1...2010).map { "imp_\($0)" }
        store.recordImpressions(Array(batchKeys.prefix(10)), timestamp: 500)
        store.recordImpressions(Array(batchKeys.dropFirst(10)), timestamp: 2000)
        XCTAssertEqual(store.getImpressionRecords().count, 2000)
        XCTAssertNil(store.getImpressionRecord("imp_1"))
        XCTAssertNotNil(store.getImpressionRecord("imp_2010"))

        // resetLearningData preserves personalizationEnabled
        store.setPersonalizationEnabled(false)
        store.resetLearningData()
        XCTAssertFalse(store.isPersonalizationEnabled)
        XCTAssertTrue(store.getSelectedGenres().isEmpty)
        XCTAssertTrue(store.getClickedRecords().isEmpty)
        XCTAssertTrue(store.getImpressionRecords().isEmpty)

        // Corrupt guard
        let corruptFile = tempDir.appendingPathComponent("corrupt_profile.json")
        try Data("{corrupt".utf8).write(to: corruptFile)
        let corruptStore = RecommendProfileStore(storageFile: corruptFile)
        XCTAssertTrue(corruptStore.isCorrupted)
        corruptStore.setSelectedGenres(["热血"])
        XCTAssertEqual(String(data: try Data(contentsOf: corruptFile), encoding: .utf8), "{corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptFile.path + ".corrupt"))
    }

    // MARK: - 3. UserHabitProfiler

    func testUserHabitProfilerWeightsIdfDecayAndVpnBounds() {
        let now: Int64 = 1_700_000_000_000
        let dayMs = Int64(UserHabitProfiler.millisPerDay)
        let store = RecommendProfileStore(storageFile: tempDir.appendingPathComponent("profiler.json"))
        store.setSelectedGenres(["奇幻"])
        store.recordClick(normalizedTitle: "c1", title: "Clicked", sourceId: "s2", author: "ClickAuthor", genres: ["校园"], timestamp: now)
        store.recordDislike(normalizedTitle: "d1", displayTitle: "Bad", genres: ["恐怖"], author: "BadAuthor", timestamp: now - 15 * dayMs)
        store.recordDislike(normalizedTitle: "d2", displayTitle: "OldBad", genres: ["科幻"], author: "OldAuthor", timestamp: now - 35 * dayMs)

        let seed1 = SeedComic(comicId: "1", title: "主力热血作", author: "大师", genres: ["热血", "冒险"], sourceId: "s1", favorite: true, readRatio: 1.0, lastViewedAt: now)
        let seed2 = SeedComic(comicId: "2", title: "过期作", author: "路人", genres: ["冒险"], sourceId: "s1", favorite: false, readRatio: 0.0, lastViewedAt: now - 14 * dayMs)

        let profile = UserHabitProfiler.buildProfile(
            seeds: [seed1, seed2],
            searchHistory: ["搞笑"],
            store: store,
            enabledSourceIds: ["s1", "s2", "sUnused", "sVpn"],
            vpnSourceIds: ["sVpn"],
            nowMillis: now
        )

        XCTAssertFalse(profile.isColdStart)
        XCTAssertEqual(profile.topSeedTitleByGenre["热血"], "主力热血作")
        XCTAssertEqual(profile.topSeedTitleByAuthor["大师"], "主力热血作")
        XCTAssertEqual(profile.genreWeights["奇幻"] ?? 0, 1.8, accuracy: 0.01)
        XCTAssertEqual(profile.genreWeights["搞笑"] ?? 0, 0.4, accuracy: 0.01)
        XCTAssertEqual(profile.genreWeights["校园"] ?? 0, 0.85, accuracy: 0.01)
        // 15 days out of 30 => 0.5 decay => -0.6 genre, -0.75 author
        XCTAssertEqual(profile.genreWeights["恐怖"] ?? 0, -0.6, accuracy: 0.01)
        XCTAssertEqual(profile.authorWeights["badauthor"] ?? 0, -0.75, accuracy: 0.01)
        // >= 30 days expired => no penalty
        XCTAssertNil(profile.genreWeights["科幻"])

        XCTAssertEqual(profile.sourceWeights["s1"] ?? 0, 1.30, accuracy: 0.001)
        XCTAssertEqual(profile.sourceWeights["sUnused"] ?? 0, 0.85, accuracy: 0.001)
        XCTAssertEqual(profile.sourceWeights["sVpn"] ?? 0, 0.85 * 0.75, accuracy: 0.001)

        // Personalization disabled -> cold-start empty profile with neutral source weights
        store.setPersonalizationEnabled(false)
        let disabledProfile = UserHabitProfiler.buildProfile(
            seeds: [seed1],
            searchHistory: ["搞笑"],
            store: store,
            enabledSourceIds: ["s1", "sVpn"],
            vpnSourceIds: ["sVpn"],
            nowMillis: now
        )
        XCTAssertTrue(disabledProfile.isColdStart)
        XCTAssertEqual(disabledProfile.sourceWeights["s1"] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(disabledProfile.sourceWeights["sVpn"] ?? 0, 0.75, accuracy: 0.001)
    }

    // MARK: - 4. RecommendCandidatePool

    func testCandidatePoolTtlEnrichmentEvictionAndRemoveSources() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let poolDir = tempDir.appendingPathComponent("pool", isDirectory: true)
        let pool = RecommendCandidatePool(filesDir: poolDir, poolTtlMs: 24 * 60 * 60 * 1000, maxCandidates: 3)

        let c1Weak = SourceCandidate(
            summary: ComicSummary(sourceId: "s1", comicId: "1", title: "作品甲", coverUrl: "", subtitle: "", tags: []),
            sourceId: "s1", sourceName: "S1", sourceChannel: .explorationNewTaste, rankInList: 10, author: "", genres: [], fetchedAt: now - 1000
        )
        let c1Rich = SourceCandidate(
            summary: ComicSummary(sourceId: "s1", comicId: "1", title: "作品甲", coverUrl: "https://img/1.jpg", subtitle: "", tags: ["热血"], latestChapter: "第9话"),
            sourceId: "s1", sourceName: "S1", sourceChannel: .systemConsensusHot, rankInList: 2, author: "作者甲", genres: ["热血"], fetchedAt: now
        )
        let expired = SourceCandidate(
            summary: ComicSummary(sourceId: "s1", comicId: "old", title: "过期", coverUrl: ""),
            sourceId: "s1", fetchedAt: now - 25 * 60 * 60 * 1000
        )

        XCTAssertEqual(pool.merge([c1Weak, expired], nowMillis: now), 1)
        XCTAssertEqual(pool.mergeAndPersist([c1Rich], nowMillis: now), 1)
        let snap = pool.snapshotForSources(allowedSourceIds: nil, nowMillis: now)
        XCTAssertEqual(snap.count, 1)
        XCTAssertEqual(snap[0].sourceChannel, .systemConsensusHot)
        XCTAssertEqual(snap[0].author, "作者甲")
        XCTAssertEqual(snap[0].summary.coverUrl, "https://img/1.jpg")
        XCTAssertEqual(snap[0].rankInList, 2)

        // Cap at 3
        let extras = (2...5).map { idx in
            SourceCandidate(
                summary: ComicSummary(sourceId: "s2", comicId: "\(idx)", title: "作品\(idx)"),
                sourceId: "s2", rankInList: idx, fetchedAt: now + Int64(idx)
            )
        }
        _ = pool.mergeAndPersist(extras, nowMillis: now + 10)
        XCTAssertEqual(pool.size, 3)

        // Reload from disk and remove s2
        let reloaded = RecommendCandidatePool(filesDir: poolDir, poolTtlMs: 24 * 60 * 60 * 1000, maxCandidates: 3)
        XCTAssertEqual(reloaded.size, 3)
        XCTAssertEqual(reloaded.removeSources(["s2"]), 3)
        XCTAssertEqual(reloaded.size, 0)
    }

    // MARK: - 5. RecommendEngine & RecommendReasonFormatter

    func testRecommendEngineScoringDiversityCoversRecycleAndReasons() {
        let now: Int64 = 1_700_000_000_000
        let store = RecommendProfileStore(storageFile: tempDir.appendingPathComponent("engine_prof.json"))
        store.recordImpressions(["decayedtitle", "decayedtitle", "decayedtitle", "decayedtitle"], timestamp: now)

        let profile = HabitProfile(
            genreWeights: ["热血": 2.0, "恋爱": 1.4],
            authorWeights: ["authora": 1.6],
            sourceWeights: ["s1": 1.2, "s2": 1.1, "s3": 1.0, "s4": 0.9],
            topSeedTitleByGenre: ["热血": "海贼王"],
            topSeedTitleByAuthor: ["authora": "名作"],
            topGenres: ["热血", "恋爱"],
            topAuthors: ["authora"],
            knownGenres: ["热血", "恋爱"],
            preferredSelectedGenres: ["热血"],
            searchedTerms: [],
            isColdStart: false,
            seedCount: 3
        )

        var candidates: [SourceCandidate] = []
        // Multi-source candidate with fallback covers across distinct hosts
        for (idx, sid) in ["s1", "s2", "s3"].enumerated() {
            candidates.append(SourceCandidate(
                summary: ComicSummary(
                    sourceId: sid, comicId: "multi_\(idx)", title: "多源神作",
                    coverUrl: "https://cdn\(idx + 1).example.com/cover.jpg", tags: ["奇幻"]
                ),
                sourceId: sid, sourceName: "站\(sid)", sourceChannel: .systemConsensusHot,
                rankInList: idx, author: "Other", genres: ["奇幻"], fetchedAt: now
            ))
        }
        // Featured candidates (must obey <= 25% cap)
        for i in 1...12 {
            candidates.append(SourceCandidate(
                summary: ComicSummary(sourceId: "s\((i % 4) + 1)", comicId: "feat_\(i)", title: "热推漫画\(i)", coverUrl: "https://c.com/\(i).jpg", tags: ["悬疑"]),
                sourceId: "s\((i % 4) + 1)", sourceName: "站\((i % 4) + 1)", sourceChannel: .sourceFeaturedCategory,
                featuredCategoryLabel: "热门推荐", rankInList: i, author: "F\(i)", genres: ["悬疑"], fetchedAt: now
            ))
        }
        // Habit + Latest + Explore candidates
        for i in 1...20 {
            let sid = "s\((i % 4) + 1)"
            candidates.append(SourceCandidate(
                summary: ComicSummary(sourceId: sid, comicId: "hab_\(i)", title: i == 1 ? "DecayedTitle" : "热血漫画\(i)", coverUrl: "https://h.com/\(i).jpg", tags: ["热血"]),
                sourceId: sid, sourceName: "站\(sid)", sourceChannel: i % 3 == 0 ? .latestUpdates : .habitPersonalized,
                rankInList: i, author: i == 2 ? "AuthorA" : "H\(i)", genres: i % 2 == 0 ? ["热血"] : ["搞笑"], fetchedAt: now
            ))
        }

        let feed = RecommendEngine.buildFeed(
            rawCandidates: candidates,
            profile: profile,
            store: store,
            titleNormalizer: { ComicTitleNormalizer.normalize($0) },
            nowMillis: now
        )
        XCTAssertFalse(feed.isEmpty)
        let multiItem = feed.hotRankItems.first { $0.normalizedTitle == ComicTitleNormalizer.normalize("多源神作") }
        XCTAssertNotNil(multiItem)
        XCTAssertEqual(multiItem?.hotSourceCount, 3)
        XCTAssertEqual(multiItem?.fallbackCoverUrls.count, 2)

        // Verify <= 25% featured cap in moreStreamItems and no >1 featured in sliding window of 4
        let featuredCount = feed.moreStreamItems.filter { $0.channel == .sourceFeaturedCategory }.count
        XCTAssertLessThanOrEqual(featuredCount * 4, feed.moreStreamItems.count)
        if feed.moreStreamItems.count >= 4 {
            for i in 0...(feed.moreStreamItems.count - 4) {
                let winFeatured = feed.moreStreamItems[i..<(i + 4)].filter { $0.channel == .sourceFeaturedCategory }.count
                XCTAssertLessThanOrEqual(winFeatured, 1)
            }
        }

        // Deterministic daily jitter
        let j1 = RecommendEngine.deterministicDailyJitter(epochDay: 19700, seedSalt: 0, normTitle: "abc")
        let j2 = RecommendEngine.deterministicDailyJitter(epochDay: 19700, seedSalt: 0, normTitle: "abc")
        XCTAssertEqual(j1, j2)

        // Option A recycle batch + upper replenish
        let recycled = RecommendEngine.buildRecycledBatch(
            poolCandidates: candidates,
            profile: profile,
            store: store,
            recentShownOrderNormTitles: [ComicTitleNormalizer.normalize("热血漫画2")],
            excludedExistingTitles: [],
            titleNormalizer: { ComicTitleNormalizer.normalize($0) },
            blacklistTitlePredicate: nil,
            batchSize: 6,
            recentTailItems: [],
            nowMillis: now,
            recycleRound: 1
        )
        XCTAssertEqual(recycled.count, 6)

        let upper = RecommendEngine.buildUpperReplenishBatch(
            poolCandidates: candidates,
            profile: profile,
            store: store,
            existingUpperNormTitles: Set(feed.spotlightPool.map(\.normalizedTitle)),
            excludedExistingTitles: [],
            titleNormalizer: { ComicTitleNormalizer.normalize($0) },
            blacklistTitlePredicate: nil,
            isSpotlight: true,
            batchSize: 3,
            nowMillis: now,
            roundSeed: 1
        )
        XCTAssertFalse(upper.isEmpty)

        // RecommendReasonFormatter 8-tier checks + emoji/cliché sanitizer + 22/11 char cap
        let rAuthorSeed = RecommendReasonFormatter.format(
            channel: .habitPersonalized, candidateGenres: ["热血"], author: "AuthorA",
            hotSourceCount: 1, sourceName: "站1", featuredCategoryLabel: "", profile: profile, personalizationActive: true
        )
        XCTAssertTrue(rAuthorSeed.reason.contains("同作者"))
        XCTAssertLessThanOrEqual(rAuthorSeed.reason.utf16.count, 22)
        XCTAssertLessThanOrEqual(rAuthorSeed.gridReason.utf16.count, 11)

        let rSanitized = RecommendReasonFormatter.format(
            channel: .sourceFeaturedCategory, candidateGenres: [], author: "",
            hotSourceCount: 1, sourceName: "🔥AI智能推荐站", featuredCategoryLabel: "猜你喜欢量身定制超长标签名称测试",
            profile: profile, personalizationActive: false
        )
        XCTAssertFalse(rSanitized.reason.contains("🔥"))
        XCTAssertFalse(rSanitized.reason.contains("AI"))
        XCTAssertFalse(rSanitized.reason.contains("智能"))
        XCTAssertFalse(rSanitized.reason.contains("量身定制"))
        XCTAssertLessThanOrEqual(rSanitized.reason.utf16.count, 22)
        XCTAssertLessThanOrEqual(rSanitized.gridReason.utf16.count, 11)
    }

    // MARK: - 6. RecommendHarvester & RecommendStreamPager

    func testHarvesterSkipsVerificationSourcesCapsSixAndPropagatesPriority() async {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let mh18 = MockRecommendSource(id: "mh18", name: "MH18")
        let jm = MockRecommendSource(id: "jmcomic", name: "JM")
        let failoverSrc = MockRecommendSource(id: "fo", name: "Failover", hasBackupFailover: true)
        XCTAssertEqual(RecommendHarvester.effectiveSourceTimeoutMs(source: failoverSrc, baseTimeoutMs: 5_500), 14_000)

        var sources: [any ComicSource] = [mh18, jm]
        for i in 1...8 {
            let src = MockRecommendSource(id: "s\(i)", name: "Source \(i)")
            src.categoryItems = [
                ComicSummary(sourceId: "s\(i)", comicId: "c\(i)_1", title: "漫画\(i)_1", coverUrl: "https://c/\(i).jpg", tags: ["热血"]),
                ComicSummary(sourceId: "s\(i)", comicId: "c\(i)_2", title: "漫画\(i)_2", coverUrl: "https://c/\(i)b.jpg", tags: ["搞笑"])
            ]
            sources.append(src)
        }

        let profile = HabitProfile(
            genreWeights: [:], authorWeights: [:],
            sourceWeights: ["s8": 1.30, "s7": 1.25],
            topSeedTitleByGenre: [:], topSeedTitleByAuthor: [:],
            topGenres: [], topAuthors: [], knownGenres: [],
            preferredSelectedGenres: [], searchedTerms: [],
            isColdStart: true, seedCount: 0
        )
        let selected = RecommendHarvester.selectSourcesForHarvest(enabledSources: sources, profile: profile)
        XCTAssertEqual(selected.count, 6)
        XCTAssertFalse(selected.contains { $0.id == "mh18" || $0.id == "jmcomic" })
        XCTAssertEqual(selected.first?.id, "s8")

        let harvester = RecommendHarvester(filesDir: tempDir)
        let store = RecommendProfileStore(storageFile: tempDir.appendingPathComponent("h_prof.json"))
        var partialFeedCount = 0
        let feed = await harvester.harvestAndBuildFeedProgressive(
            enabledSources: sources,
            seeds: [],
            searchHistory: [],
            profileStore: store,
            vpnSourceIds: [],
            excludedExistingTitles: [],
            titleNormalizer: { ComicTitleNormalizer.normalize($0) },
            blacklistTitlePredicate: { $0 == ComicTitleNormalizer.normalize("漫画8_1") },
            forceRefresh: true,
            nowMillis: now,
            onPartialFeed: { _ in partialFeedCount += 1 }
        )
        XCTAssertFalse(feed.isEmpty)
        XCTAssertGreaterThanOrEqual(partialFeedCount, 1)
        XCTAssertTrue(mh18.recordedPriorities.isEmpty)
        XCTAssertTrue(jm.recordedPriorities.isEmpty)
        XCTAssertTrue((sources[2] as! MockRecommendSource).recordedPriorities.allSatisfy { $0 })

        // Filtered cached feed respects allowedSourceIds and blacklist
        let filteredCached = harvester.loadCachedFeedFiltered(
            store: store,
            excludedExistingTitles: [],
            blacklistTitlePredicate: nil,
            titleNormalizer: { ComicTitleNormalizer.normalize($0) },
            allowedSourceIds: ["s8"]
        )
        XCTAssertNotNil(filteredCached)
        if let filteredCached {
            XCTAssertTrue(filteredCached.moreStreamItems.allSatisfy { $0.summary.sourceId == "s8" })
        }
    }

    func testStreamPagerWaveOrderVpnDeferralLoopAndErrorExhaustion() async {
        let now: Int64 = 1_700_000_000_000
        let w0 = MockRecommendSource(id: "w0", name: "Wave0")
        let w1 = MockRecommendSource(id: "w1", name: "Wave1")
        let vpn = MockRecommendSource(id: "vpn1", name: "VPN1")

        // w1 returns duplicate IDs on page 2 to trigger prevPageIds loop exhaustion
        w1.categoryPages[1] = (1...5).map { ComicSummary(sourceId: "w1", comicId: "dup_\($0)", title: "Wave1作品\($0)") }
        w1.categoryPages[2] = w1.categoryPages[1]
        // w0 fails to trigger >= 2 error exhaustion
        w0.shouldThrow = true
        vpn.categoryPages[1] = (1...6).map { ComicSummary(sourceId: "vpn1", comicId: "v_\($0)", title: "VPN作品\($0)") }

        let pool = RecommendCandidatePool(filesDir: tempDir.appendingPathComponent("pager_pool", isDirectory: true))
        let pager = RecommendStreamPager(
            enabledSources: [w0, w1, vpn],
            profile: HabitProfile.empty(),
            profileStore: nil,
            candidatePool: pool,
            vpnSourceIds: ["vpn1"],
            wave0SourceIdsOrdered: ["w0"],
            excludedExistingTitles: [],
            titleNormalizer: { ComicTitleNormalizer.normalize($0) },
            blacklistTitlePredicate: nil,
            initialShownItems: [],
            perSourceTimeoutMs: 2_000,
            fixedNowMillis: now
        )

        let b1 = await pager.fetchNextBatch(targetBatchSize: 5)
        XCTAssertFalse(b1.recycled)
        XCTAssertEqual(b1.items.count, 5)
        // Non-VPN Wave-1 ran before VPN
        XCTAssertTrue(vpn.recordedPriorities.isEmpty)
        XCTAssertTrue(w1.recordedPriorities.allSatisfy { $0 })

        // Subsequent batches drain w1 & w0, then fetch VPN, then recycle via Option A
        var sawVpnItems = false
        var sawRecycled = false
        for _ in 0..<8 {
            let next = await pager.fetchNextBatch(targetBatchSize: 6)
            if next.items.contains(where: { $0.summary.sourceId == "vpn1" && !next.recycled }) {
                sawVpnItems = true
            }
            if sawVpnItems && next.recycled {
                sawRecycled = true
                XCTAssertTrue(next.hasItems)
                break
            }
        }
        XCTAssertTrue(sawVpnItems)
        XCTAssertTrue(sawRecycled)
        XCTAssertFalse(vpn.recordedPriorities.isEmpty)
        XCTAssertTrue(vpn.recordedPriorities.allSatisfy { $0 })

        // Blacklist sync & undo
        pager.markTitleBlacklistedOrRemoved("VPN作品1")
        pager.removeFromSeen("VPN作品1")
    }

    // MARK: - 7. RecommendPagePolicy

    func testRecommendPagePolicyAlignmentFooterAndFilterCache() {
        XCTAssertEqual(RecommendPagePolicy.guessBatchSizeForColumns(3), 6)
        XCTAssertEqual(RecommendPagePolicy.guessBatchSizeForColumns(4), 8)
        XCTAssertEqual(RecommendPagePolicy.guessBatchSizeForColumns(5), 10)
        XCTAssertEqual(RecommendPagePolicy.guessBatchSizeForColumns(6), 6)
        XCTAssertEqual(RecommendPagePolicy.effectiveGuessBatchSize(poolSize: 7, columnCount: 4), 4)

        let poolItems = (1...7).map { idx in
            RecommendItem(summary: ComicSummary(sourceId: "s", comicId: "\(idx)", title: "Item\(idx)"), normalizedTitle: "item\(idx)")
        }
        let aligned = RecommendPagePolicy.selectAlignedGuessBatch(pool: poolItems, batchIndex: 1, columnCount: 4)
        XCTAssertEqual(aligned.count, 4)

        // Sync footer early-return guard when callback does not acknowledge loading
        let footer = RecommendPagePolicy.FooterLoadState()
        XCTAssertTrue(footer.canTriggerOnScroll(dy: 10, hasMoreItems: true, hasCallbacks: true, lastVisible: 18, totalCount: 20, spanCount: 3))
        var stateTransitions: [RecommendPagePolicy.FooterStateKind] = []
        footer.dispatchScrollLoad(
            onLoadMore: { /* synchronous no-op without calling setLoading */ },
            onStateChanged: { stateTransitions.append(footer.state) }
        )
        XCTAssertEqual(stateTransitions, [.loading, .ready])
        XCTAssertEqual(footer.state, .ready)

        XCTAssertEqual(RecommendPagePolicy.stabilizeBatchIndexBeforePoolAppend(currentBatchIdx: 5, currentPoolSize: 9, batchSize: 3), 2)
        XCTAssertEqual(RecommendPagePolicy.advanceBatchIndex(currentBatchIdx: 2, currentPoolSize: 9, batchSize: 3), 0)
        XCTAssertEqual(RecommendPagePolicy.clampScrollRestorePos(requestedPos: 10, itemCount: 4), 3)
        XCTAssertEqual(RecommendPagePolicy.clampScrollRestorePos(requestedPos: 0, itemCount: 0), -1)
        XCTAssertFalse(RecommendPagePolicy.shouldUpdateContentWidth(nextWidthPx: 101, currentWidthPx: 100))
        XCTAssertTrue(RecommendPagePolicy.shouldUpdateContentWidth(nextWidthPx: 102, currentWidthPx: 100))

        let sig = RecommendPagePolicy.computeSpotlightBatchMeasureSignature(batch: Array(poolItems.prefix(2)), cardWidthPx: 320)
        XCTAssertTrue(sig.hasPrefix("w=320|n=2|item:"))

        // BlacklistFeedFilterCache caches across unchanged feed + blacklist
        let blStore = ComicBlacklistStore(storageFile: tempDir.appendingPathComponent("policy_bl.json"))
        _ = blStore.add(BlacklistEntry(displayTitle: "Item1", blacklistedAt: 1))
        let feed = RecommendFeed.createExpanded(
            availableGenres: [], spotlightPool: poolItems, guessPool: [], hotRankItems: [],
            latestItems: [], moreStreamItems: [], generatedAt: 1, isColdStart: true, personalizationActive: true
        )
        let cache = BlacklistFeedFilterCache()
        let first = cache.filter(feed, blacklistStore: blStore)
        let second = cache.filter(feed, blacklistStore: blStore)
        XCTAssertEqual(first?.spotlightPool.count, 6)
        XCTAssertEqual(first, second)
    }
}

private enum MockSourceError: Error {
    case network
}

private final class MockRecommendSource: ComicSource, @unchecked Sendable {
    let id: String
    let name: String
    let referer = "https://example.com"
    let hasBackupFailover: Bool

    var categoryItems: [ComicSummary] = []
    var categoryPages: [Int: [ComicSummary]] = [:]
    var shouldThrow = false
    private let lock = NSLock()
    private(set) var recordedPriorities: [Bool] = []

    init(id: String, name: String, hasBackupFailover: Bool = false) {
        self.id = id
        self.name = name
        self.hasBackupFailover = hasBackupFailover
    }

    private func recordPriority() {
        lock.lock()
        recordedPriorities.append(RuleCallPriority.currentIsBackground())
        lock.unlock()
    }

    func latest(page: Int) async throws -> [ComicSummary] {
        recordPriority()
        if shouldThrow { throw MockSourceError.network }
        return categoryPages[page] ?? (page == 1 ? categoryItems : [])
    }

    func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        recordPriority()
        if shouldThrow { throw MockSourceError.network }
        return []
    }

    func detail(comicId: String) async throws -> ComicDetail {
        ComicDetail(summary: ComicSummary(sourceId: id, comicId: comicId, title: comicId), author: "", status: "", description: "", latestChapter: "", chapters: [])
    }

    func chapters(comicId: String) async throws -> [Chapter] { [] }
    func chapter(url: String) async throws -> ChapterPage { ChapterPage(chapterId: "", title: "", imageUrls: []) }

    func filterGroups() async throws -> [SourceFilterGroup] {
        recordPriority()
        if shouldThrow { throw MockSourceError.network }
        return [
            SourceFilterGroup(key: "sort", label: "排序", options: [
                SourceFilterOption(label: "全部", value: "all"),
                SourceFilterOption(label: "热门排行", value: "hot")
            ])
        ]
    }

    func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        recordPriority()
        if shouldThrow { throw MockSourceError.network }
        return categoryPages[page] ?? (page == 1 ? categoryItems : [])
    }
}
