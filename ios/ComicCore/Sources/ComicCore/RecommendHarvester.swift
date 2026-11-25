@preconcurrency import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 100% local recommendation harvester across enabled `ComicSource` instances.
/// Uses bounded parallel Wave-0 (up to 6 sources, 5.5s / failover 14s per-source timeout,
/// 8.5s overall harvest budget), skips manual-verification-only sources ("mh18", "jmcomic"),
/// streams progressive partial feeds, and persists atomic corruption-safe caches.
public final class RecommendHarvester: @unchecked Sendable {
    public static let schemaVersion = 1
    public static let maxPoolThreads = 6
    public static let maxHarvestSources = 6
    public static let maxUserGenresToHarvest = 3
    public static let maxUserAuthorsToHarvest = 2
    public static let maxItemsPerList = 48
    public static let maxAuthorResults = 6
    public static let defaultSourceTimeoutMs: Int64 = 5_500
    public static let defaultFailoverSourceTimeoutMs: Int64 = 14_000
    public static let defaultOverallHarvestBudgetMs: Int64 = 8_500
    public static let defaultSourceCacheTtlMs: Int64 = 6 * 60 * 60 * 1000
    public static let sourceCacheFileName = "recommend_source_cache.json"
    public static let feedCacheFileName = "recommend_feed.json"

    public struct CachedSourceBucket: Equatable, Sendable {
        public let fetchedAt: Int64
        public let candidates: [SourceCandidate]

        public init(fetchedAt: Int64, candidates: [SourceCandidate]) {
            self.fetchedAt = max(0, fetchedAt)
            self.candidates = candidates
        }
    }

    private let filesDirURL: URL
    public let sourceCacheTtlMs: Int64
    public let perSourceTimeoutMs: Int64
    public let candidatePool: RecommendCandidatePool
    private let cacheLock = NSLock()

    public init(
        filesDir: URL,
        sourceCacheTtlMs: Int64 = defaultSourceCacheTtlMs,
        perSourceTimeoutMs: Int64 = defaultSourceTimeoutMs
    ) {
        self.filesDirURL = filesDir
        self.sourceCacheTtlMs = max(0, sourceCacheTtlMs)
        self.perSourceTimeoutMs = max(100, perSourceTimeoutMs)
        self.candidatePool = RecommendCandidatePool(filesDir: filesDir)
    }

    public static func isManualVerificationOnlySource(_ sourceId: String?) -> Bool {
        sourceId == "mh18" || sourceId == "jmcomic"
    }

    /// Selects up to 6 enabled sources ordered by affinity descending, skipping
    /// manual-verification-only sources ("mh18", "jmcomic").
    public static func selectSourcesForHarvest(
        enabledSources: [any ComicSource],
        profile: HabitProfile?
    ) -> [any ComicSource] {
        guard !enabledSources.isEmpty else { return [] }
        var eligible: [(source: any ComicSource, weight: Double, index: Int)] = []
        var seenIds = Set<String>()
        for (i, src) in enabledSources.enumerated() {
            let id = src.id
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if isManualVerificationOnlySource(id) { continue }
            if !seenIds.insert(id).inserted { continue }
            let weight = profile?.sourceWeights[id] ?? UserHabitProfiler.sourceWeightDefault
            eligible.append((src, weight, i))
        }
        eligible.sort { a, b in
            if a.weight != b.weight { return a.weight > b.weight }
            return a.index < b.index
        }
        return eligible.prefix(maxHarvestSources).map(\.source)
    }

    public static func effectiveSourceTimeoutMs(source: any ComicSource, baseTimeoutMs: Int64) -> Int64 {
        if source.hasBackupFailover {
            return max(baseTimeoutMs, defaultFailoverSourceTimeoutMs)
        }
        return baseTimeoutMs
    }

    public static func computeOverallHarvestBudgetMs(
        basePerSourceTimeoutMs: Int64,
        maxEffectiveTimeoutMs: Int64
    ) -> Int64 {
        let effectiveMax = max(basePerSourceTimeoutMs, maxEffectiveTimeoutMs)
        if effectiveMax < defaultSourceTimeoutMs {
            return max(effectiveMax + 250, effectiveMax * 2)
        }
        return max(defaultOverallHarvestBudgetMs, effectiveMax)
    }

    public func harvestAndBuildFeed(
        enabledSources: [any ComicSource],
        seeds: [SeedComic],
        searchHistory: [String],
        profileStore: RecommendProfileStore?,
        vpnSourceIds: Set<String>,
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)? = nil,
        blacklistTitlePredicate: ((String) -> Bool)? = nil,
        forceRefresh: Bool,
        nowMillis: Int64? = nil
    ) async -> RecommendFeed {
        await harvestAndBuildFeedProgressive(
            enabledSources: enabledSources,
            seeds: seeds,
            searchHistory: searchHistory,
            profileStore: profileStore,
            vpnSourceIds: vpnSourceIds,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            forceRefresh: forceRefresh,
            nowMillis: nowMillis,
            onPartialFeed: nil
        )
    }

    public func harvestAndBuildFeedProgressive(
        enabledSources: [any ComicSource],
        seeds: [SeedComic],
        searchHistory: [String],
        profileStore: RecommendProfileStore?,
        vpnSourceIds: Set<String>,
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)? = nil,
        blacklistTitlePredicate: ((String) -> Bool)? = nil,
        forceRefresh: Bool,
        nowMillis: Int64? = nil,
        onPartialFeed: ((RecommendFeed) -> Void)?
    ) async -> RecommendFeed {
        let now = (nowMillis ?? 0) > 0 ? nowMillis! : Self.currentMillis()
        let profile = buildProfileForSources(
            enabledSources: enabledSources,
            seeds: seeds,
            searchHistory: searchHistory,
            profileStore: profileStore,
            vpnSourceIds: vpnSourceIds,
            now: now
        )
        let personalizationActive = profileStore?.isPersonalizationEnabled ?? true

        let candidates = await harvestCandidatesInternal(
            enabledSources: enabledSources,
            profile: profile,
            personalizationActive: personalizationActive,
            forceRefresh: forceRefresh,
            nowMillis: now,
            onBatchCandidates: onPartialFeed == nil ? nil : { partialCandidates in
                let partialFeed = RecommendEngine.buildFeed(
                    rawCandidates: partialCandidates,
                    profile: profile,
                    store: profileStore,
                    excludedExistingTitles: excludedExistingTitles,
                    titleNormalizer: titleNormalizer,
                    blacklistTitlePredicate: blacklistTitlePredicate,
                    nowMillis: now
                )
                if !partialFeed.isEmpty {
                    onPartialFeed?(partialFeed)
                }
            }
        )

        let feed = RecommendEngine.buildFeed(
            rawCandidates: candidates,
            profile: profile,
            store: profileStore,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            nowMillis: now
        )
        if !feed.isEmpty {
            saveFeed(feed)
        }
        return feed
    }

    public func harvestAndBuildExpandedFeedProgressive(
        enabledSources: [any ComicSource],
        seeds: [SeedComic],
        searchHistory: [String],
        profileStore: RecommendProfileStore?,
        vpnSourceIds: Set<String>,
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)? = nil,
        blacklistTitlePredicate: ((String) -> Bool)? = nil,
        forceRefresh: Bool,
        nowMillis: Int64? = nil,
        onPartialFeed: ((RecommendFeed) -> Void)?
    ) async -> RecommendFeed {
        let now = (nowMillis ?? 0) > 0 ? nowMillis! : Self.currentMillis()
        let profile = buildProfileForSources(
            enabledSources: enabledSources,
            seeds: seeds,
            searchHistory: searchHistory,
            profileStore: profileStore,
            vpnSourceIds: vpnSourceIds,
            now: now
        )
        let allEligibleIds = Self.collectEligibleSourceIds(enabledSources)
        let personalizationActive = profileStore?.isPersonalizationEnabled ?? true

        let candidates = await harvestCandidatesInternal(
            enabledSources: enabledSources,
            profile: profile,
            personalizationActive: personalizationActive,
            forceRefresh: forceRefresh,
            nowMillis: now,
            onBatchCandidates: onPartialFeed == nil ? nil : { partialCandidates in
                let combined = self.combineWithPoolSnapshot(
                    waveCandidates: partialCandidates,
                    eligibleIds: allEligibleIds,
                    now: now
                )
                let partialFeed = RecommendEngine.buildExpandedFeed(
                    rawCandidates: combined,
                    profile: profile,
                    store: profileStore,
                    excludedExistingTitles: excludedExistingTitles,
                    titleNormalizer: titleNormalizer,
                    blacklistTitlePredicate: blacklistTitlePredicate,
                    nowMillis: now
                )
                if !partialFeed.isEmpty {
                    onPartialFeed?(partialFeed)
                }
            }
        )
        candidatePool.persistNow()

        let combined = combineWithPoolSnapshot(waveCandidates: candidates, eligibleIds: allEligibleIds, now: now)
        let feed = RecommendEngine.buildExpandedFeed(
            rawCandidates: combined,
            profile: profile,
            store: profileStore,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            nowMillis: now
        )
        if !feed.isEmpty {
            saveFeed(feed)
        }
        return feed
    }

    public func createStreamPager(
        enabledSources: [any ComicSource],
        seeds: [SeedComic],
        searchHistory: [String],
        profileStore: RecommendProfileStore?,
        vpnSourceIds: Set<String>,
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)? = nil,
        blacklistTitlePredicate: ((String) -> Bool)? = nil,
        initialShownItems: [RecommendItem] = [],
        nowMillis: Int64? = nil
    ) -> RecommendStreamPager {
        let resolvedNow = (nowMillis ?? 0) > 0 ? nowMillis! : Self.currentMillis()
        let profile = buildProfileForSources(
            enabledSources: enabledSources,
            seeds: seeds,
            searchHistory: searchHistory,
            profileStore: profileStore,
            vpnSourceIds: vpnSourceIds,
            now: resolvedNow
        )
        let wave0Sources = Self.selectSourcesForHarvest(enabledSources: enabledSources, profile: profile)
        let wave0Ids = wave0Sources.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return RecommendStreamPager(
            enabledSources: enabledSources,
            profile: profile,
            profileStore: profileStore,
            candidatePool: candidatePool,
            vpnSourceIds: vpnSourceIds,
            wave0SourceIdsOrdered: wave0Ids,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            initialShownItems: initialShownItems,
            perSourceTimeoutMs: perSourceTimeoutMs,
            fixedNowMillis: (nowMillis ?? 0) > 0 ? nowMillis! : 0
        )
    }

    public func harvestCandidates(
        enabledSources: [any ComicSource],
        profile: HabitProfile?,
        personalizationActive: Bool,
        forceRefresh: Bool,
        nowMillis: Int64? = nil
    ) async -> [SourceCandidate] {
        await harvestCandidatesInternal(
            enabledSources: enabledSources,
            profile: profile,
            personalizationActive: personalizationActive,
            forceRefresh: forceRefresh,
            nowMillis: nowMillis,
            onBatchCandidates: nil
        )
    }

    private func buildProfileForSources(
        enabledSources: [any ComicSource],
        seeds: [SeedComic],
        searchHistory: [String],
        profileStore: RecommendProfileStore?,
        vpnSourceIds: Set<String>,
        now: Int64
    ) -> HabitProfile {
        let enabledIds = enabledSources
            .map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return UserHabitProfiler.buildProfile(
            seeds: seeds,
            searchHistory: searchHistory,
            store: profileStore,
            enabledSourceIds: enabledIds,
            vpnSourceIds: vpnSourceIds,
            nowMillis: now
        )
    }

    private static func collectEligibleSourceIds(_ enabledSources: [any ComicSource]) -> Set<String> {
        var ids = Set<String>()
        for s in enabledSources {
            let id = s.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty || isManualVerificationOnlySource(id) { continue }
            ids.insert(id)
        }
        return ids
    }

    private func combineWithPoolSnapshot(
        waveCandidates: [SourceCandidate],
        eligibleIds: Set<String>,
        now: Int64
    ) -> [SourceCandidate] {
        let poolSnapshot = eligibleIds.isEmpty
            ? []
            : candidatePool.snapshotForSources(allowedSourceIds: eligibleIds, nowMillis: now)
        if poolSnapshot.isEmpty { return waveCandidates }
        if waveCandidates.isEmpty { return poolSnapshot }
        return waveCandidates + poolSnapshot
    }

    private enum HarvestGroupEvent: Sendable {
        case source(sourceId: String, candidates: [SourceCandidate])
        case budgetExpired
    }

    private func harvestCandidatesInternal(
        enabledSources: [any ComicSource],
        profile: HabitProfile?,
        personalizationActive: Bool,
        forceRefresh: Bool,
        nowMillis: Int64?,
        onBatchCandidates: (([SourceCandidate]) -> Void)?
    ) async -> [SourceCandidate] {
        let now = (nowMillis ?? 0) > 0 ? nowMillis! : Self.currentMillis()
        let selected = Self.selectSourcesForHarvest(enabledSources: enabledSources, profile: profile)
        guard !selected.isEmpty else { return [] }

        var cache = loadSourceCache()
        var allCandidates: [SourceCandidate] = []
        var toSubmit: [(source: any ComicSource, index: Int, timeoutMs: Int64)] = []
        var poolMergedCount = 0

        for (i, source) in selected.enumerated() {
            let sid = source.id
            if !forceRefresh,
               let cached = cache[sid],
               !cached.candidates.isEmpty,
               (now - cached.fetchedAt) >= 0,
               (now - cached.fetchedAt) < sourceCacheTtlMs {
                allCandidates.append(contentsOf: cached.candidates)
                poolMergedCount += candidatePool.merge(cached.candidates, nowMillis: now)
                continue
            }
            toSubmit.append((source, i, Self.effectiveSourceTimeoutMs(source: source, baseTimeoutMs: perSourceTimeoutMs)))
        }

        if toSubmit.isEmpty {
            if poolMergedCount > 0 {
                candidatePool.persistNow()
            }
            return allCandidates
        }

        if !allCandidates.isEmpty, let onBatchCandidates {
            onBatchCandidates(allCandidates)
        }

        let maxTaskTimeoutMs = toSubmit.map(\.timeoutMs).max() ?? perSourceTimeoutMs
        let overallBudgetMs = Self.computeOverallHarvestBudgetMs(
            basePerSourceTimeoutMs: perSourceTimeoutMs,
            maxEffectiveTimeoutMs: maxTaskTimeoutMs
        )

        var cacheUpdated = false
        var nonEmptyNetworkBatches = 0

        await withTaskGroup(of: HarvestGroupEvent.self) { group in
            for task in toSubmit {
                group.addTask { [self] in
                    let fetched = await Self.runWithTimeout(timeoutMs: task.timeoutMs) {
                        await RuleCallPriority.withBackgroundPriority {
                            await self.harvestSingleSource(
                                source: task.source,
                                sourceIndex: task.index,
                                profile: profile,
                                personalizationActive: personalizationActive,
                                nowMillis: now
                            )
                        }
                    }
                    return .source(sourceId: task.source.id, candidates: fetched ?? [])
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(1, overallBudgetMs)) * 1_000_000)
                return .budgetExpired
            }

            var remaining = toSubmit.count
            for await event in group {
                switch event {
                case .budgetExpired:
                    group.cancelAll()
                    remaining = 0
                case .source(let sourceId, let candidates):
                    remaining -= 1
                    if !candidates.isEmpty {
                        allCandidates.append(contentsOf: candidates)
                        cache[sourceId] = CachedSourceBucket(fetchedAt: now, candidates: candidates)
                        cacheUpdated = true
                        poolMergedCount += candidatePool.merge(candidates, nowMillis: now)
                        nonEmptyNetworkBatches += 1
                        if let onBatchCandidates, remaining > 0,
                           (nonEmptyNetworkBatches == 1 || nonEmptyNetworkBatches == 3) {
                            onBatchCandidates(allCandidates)
                        }
                    }
                    if remaining <= 0 {
                        group.cancelAll()
                    }
                }
                if remaining <= 0 {
                    break
                }
            }
        }

        if cacheUpdated {
            saveSourceCache(cache)
        }
        if poolMergedCount > 0 {
            candidatePool.persistNow()
        }
        return allCandidates
    }

    private func harvestSingleSource(
        source: any ComicSource,
        sourceIndex: Int,
        profile: HabitProfile?,
        personalizationActive: Bool,
        nowMillis: Int64
    ) async -> [SourceCandidate] {
        var out: [SourceCandidate] = []
        let sourceId = source.id
        let sourceName = source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? sourceId
            : source.name.trimmingCharacters(in: .whitespacesAndNewlines)

        let groups = (try? await source.filterGroups()) ?? []
        if Task.isCancelled { return out }

        var fetchedFilters = Set<[String: String]>()

        // 1. Featured & Hot
        let featuredPlan = RecommendSourceClassifier.detectFeaturedRecommendPlan(groups)
        let hotPlan = RecommendSourceClassifier.detectHotRankingPlan(groups)
        if let featuredPlan, (sourceIndex < 3 || hotPlan == nil),
           fetchedFilters.insert(featuredPlan.filters).inserted {
            await fetchCategoryPlan(
                source: source, sourceId: sourceId, sourceName: sourceName,
                filters: featuredPlan.filters, channel: .sourceFeaturedCategory,
                featuredLabel: featuredPlan.matchedLabel, queryGenre: "",
                nowMillis: nowMillis, out: &out
            )
        }

        if Task.isCancelled { return out }

        if let hotPlan, fetchedFilters.insert(hotPlan.filters).inserted {
            await fetchCategoryPlan(
                source: source, sourceId: sourceId, sourceName: sourceName,
                filters: hotPlan.filters, channel: .systemConsensusHot,
                featuredLabel: "", queryGenre: "",
                nowMillis: nowMillis, out: &out
            )
        }

        if Task.isCancelled { return out }

        // 2. Latest updates
        if sourceIndex < 3 || out.isEmpty {
            if let latestPlan = RecommendSourceClassifier.detectLatestPlan(groups),
               fetchedFilters.insert(latestPlan.filters).inserted {
                await fetchCategoryPlan(
                    source: source, sourceId: sourceId, sourceName: sourceName,
                    filters: latestPlan.filters, channel: .latestUpdates,
                    featuredLabel: "", queryGenre: "",
                    nowMillis: nowMillis, out: &out
                )
            } else if let latest = try? await source.latest(page: 1) {
                Self.convertSummariesToCandidates(
                    summaries: latest,
                    sourceId: sourceId,
                    sourceName: sourceName,
                    channel: .latestUpdates,
                    featuredLabel: "",
                    queryGenre: "",
                    queryAuthor: "",
                    maxItems: Self.maxItemsPerList,
                    rankOffset: 0,
                    nowMillis: nowMillis,
                    out: &out
                )
            }
        }

        if Task.isCancelled { return out }

        // 3. Sharded personalized genre
        if personalizationActive, let profile, !profile.topGenres.isEmpty, sourceIndex < 4 {
            let genreCount = profile.topGenres.count
            let startIdx = sourceIndex % genreCount
            for offset in 0..<genreCount {
                if Task.isCancelled { return out }
                let genre = profile.topGenres[(startIdx + offset) % genreCount]
                if let genrePlan = RecommendSourceClassifier.detectGenrePlan(groups, canonicalGenre: genre),
                   fetchedFilters.insert(genrePlan.filters).inserted {
                    await fetchCategoryPlan(
                        source: source, sourceId: sourceId, sourceName: sourceName,
                        filters: genrePlan.filters, channel: .habitPersonalized,
                        featuredLabel: "", queryGenre: genre,
                        nowMillis: nowMillis, out: &out
                    )
                    break
                }
            }
        }

        if Task.isCancelled { return out }

        // 4. Sharded personalized author search
        if personalizationActive, let profile, !profile.topAuthors.isEmpty,
           source.supportsSearch,
           sourceIndex < min(Self.maxUserAuthorsToHarvest, profile.topAuthors.count) {
            let author = profile.topAuthors[sourceIndex]
            if let searchResults = try? await source.search(keyword: author, page: 1) {
                Self.convertSummariesToCandidates(
                    summaries: searchResults,
                    sourceId: sourceId,
                    sourceName: sourceName,
                    channel: .habitPersonalized,
                    featuredLabel: "",
                    queryGenre: "",
                    queryAuthor: author,
                    maxItems: Self.maxAuthorResults,
                    rankOffset: 0,
                    nowMillis: nowMillis,
                    out: &out
                )
            }
        }

        return out
    }

    private func fetchCategoryPlan(
        source: any ComicSource,
        sourceId: String,
        sourceName: String,
        filters: [String: String],
        channel: RecommendChannel,
        featuredLabel: String,
        queryGenre: String,
        nowMillis: Int64,
        out: inout [SourceCandidate]
    ) async {
        guard let items = try? await source.category(filters: filters, page: 1) else { return }
        Self.convertSummariesToCandidates(
            summaries: items,
            sourceId: sourceId,
            sourceName: sourceName,
            channel: channel,
            featuredLabel: featuredLabel,
            queryGenre: queryGenre,
            queryAuthor: "",
            maxItems: Self.maxItemsPerList,
            rankOffset: 0,
            nowMillis: nowMillis,
            out: &out
        )
    }

    static func convertSummariesToCandidates(
        summaries: [ComicSummary],
        sourceId: String,
        sourceName: String,
        channel: RecommendChannel,
        featuredLabel: String,
        queryGenre: String,
        queryAuthor: String,
        maxItems: Int,
        rankOffset: Int,
        nowMillis: Int64,
        out: inout [SourceCandidate]
    ) {
        guard !summaries.isEmpty else { return }
        let limit = min(maxItems, summaries.count)
        let safeOffset = max(0, rankOffset)
        for i in 0..<limit {
            let s = summaries[i]
            if SearchRules.trim(s.title).isEmpty { continue }

            var genres = s.tags
            if !queryGenre.isEmpty { genres.append(queryGenre) }
            if genres.isEmpty || RecommendSourceClassifier.extractCanonicalGenres(genres).isEmpty {
                genres.append(contentsOf: RecommendSourceClassifier.inferGenresFromText(
                    title: s.title,
                    subtitle: s.subtitle,
                    description: ""
                ))
            }
            let author = inferAuthor(summary: s, queryAuthor: queryAuthor)
            out.append(SourceCandidate(
                summary: s,
                sourceId: sourceId,
                sourceName: sourceName,
                sourceChannel: channel,
                featuredCategoryLabel: featuredLabel,
                rankInList: safeOffset + i,
                author: author,
                genres: genres,
                matchedQueryGenre: queryGenre,
                matchedQueryAuthor: queryAuthor,
                fetchedAt: nowMillis
            ))
        }
    }

    private static func inferAuthor(summary: ComicSummary, queryAuthor: String) -> String {
        let sub = summary.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sub.isEmpty && !looksLikeChapterOrStatus(sub) {
            return sub
        }
        return queryAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeChapterOrStatus(_ text: String) -> Bool {
        let s = RecommendSourceClassifier.toSimplified(text)
        if s.hasPrefix("第") || s.contains("话") || s.contains("章")
            || s.contains("连载") || s.contains("完结") || s.contains("更新") {
            return true
        }
        return s.range(of: "\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil
    }

    static func runWithTimeout<T: Sendable>(
        timeoutMs: Int64,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutMs)) * 1_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Disk Cache Persistence (Atomic + Corruption Safe)

    public func saveFeed(_ feed: RecommendFeed?) {
        guard let feed else { return }
        let feedFile = filesDirURL.appendingPathComponent(Self.feedCacheFileName)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let root: [String: Any] = [
            "version": Self.schemaVersion,
            "feed": feed.toJSONObject()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: root, options: []) {
            try? writeAtomic(data, to: feedFile)
        }
    }

    public func loadCachedFeed() -> RecommendFeed? {
        let feedFile = filesDirURL.appendingPathComponent(Self.feedCacheFileName)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let fm = FileManager.default
        guard fm.fileExists(atPath: feedFile.path),
              let attrs = try? fm.attributesOfItem(atPath: feedFile.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value, size > 0 else {
            return nil
        }
        do {
            let data = try Data(contentsOf: feedFile)
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let root = obj as? [String: Any],
                  let verVal = root["version"],
                  let ver = JsonValueHelper.strictInt(verVal),
                  ver >= 1, ver <= Self.schemaVersion,
                  let feedDict = root["feed"] as? [String: Any] else {
                throw CacheError.invalid
            }
            return RecommendFeed.fromJSONObject(feedDict)
        } catch {
            backupCorruptFileIfAbsent(feedFile)
            return nil
        }
    }

    public func clearFeedCache() {
        let feedFile = filesDirURL.appendingPathComponent(Self.feedCacheFileName)
        let tmpFile = filesDirURL.appendingPathComponent(Self.feedCacheFileName + ".tmp")
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let fm = FileManager.default
        if fm.fileExists(atPath: feedFile.path) { try? fm.removeItem(at: feedFile) }
        if fm.fileExists(atPath: tmpFile.path) { try? fm.removeItem(at: tmpFile) }
    }

    public func invalidateSources(_ sourceIds: [String]) {
        let cleanIds = Set(sourceIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !cleanIds.isEmpty else { return }

        cacheLock.lock()
        var cache = loadSourceCacheLocked()
        var changed = false
        for key in Array(cache.keys) {
            if cleanIds.contains(key.trimmingCharacters(in: .whitespacesAndNewlines)) {
                cache.removeValue(forKey: key)
                changed = true
            }
        }
        if changed {
            saveSourceCacheLocked(cache)
        }
        cacheLock.unlock()

        candidatePool.removeSources(Array(cleanIds))
        clearFeedCache()
    }

    public func loadCachedFeedFiltered(
        store: RecommendProfileStore?,
        excludedExistingTitles: [String],
        blacklistTitlePredicate: ((String) -> Bool)?,
        titleNormalizer: ((String) -> String)?,
        allowedSourceIds: Set<String>? = nil
    ) -> RecommendFeed? {
        var cleanAllowedIds: Set<String>?
        if let allowedSourceIds {
            if allowedSourceIds.isEmpty { return nil }
            let trimmed = Set(allowedSourceIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            if trimmed.isEmpty { return nil }
            cleanAllowedIds = trimmed
        }

        guard let cached = loadCachedFeed() else { return nil }
        let normalizer = titleNormalizer ?? { RecommendModels.normalizeTitleFallback($0) }
        let personalizationActive = store?.isPersonalizationEnabled ?? true

        var excludedNorms = Set<String>()
        for title in excludedExistingTitles {
            let norm = normalizer(title)
            if !norm.isEmpty { excludedNorms.insert(norm) }
        }
        var dislikedNorms = Set<String>()
        if let store {
            for d in store.listDisliked() {
                if !d.normalizedTitle.isEmpty { dislikedNorms.insert(d.normalizedTitle) }
                if !d.displayTitle.isEmpty {
                    let norm = normalizer(d.displayTitle)
                    if !norm.isEmpty { dislikedNorms.insert(norm) }
                }
            }
        }

        func filterList(_ items: [RecommendItem]) -> [RecommendItem] {
            items.filter { item in
                if let cleanAllowedIds {
                    let sid = item.summary.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanAllowedIds.contains(sid) { return false }
                }
                if !personalizationActive && item.channel == .habitPersonalized {
                    return false
                }
                let rawTitle = item.summary.title
                let norm = !item.normalizedTitle.isEmpty ? item.normalizedTitle : normalizer(rawTitle)
                let reNorm = normalizer(rawTitle)
                if excludedNorms.contains(norm) || (!reNorm.isEmpty && excludedNorms.contains(reNorm)) {
                    return false
                }
                if dislikedNorms.contains(norm) || (!reNorm.isEmpty && dislikedNorms.contains(reNorm)) {
                    return false
                }
                if let pred = blacklistTitlePredicate,
                   pred(norm) || (!reNorm.isEmpty && pred(reNorm)) || pred(rawTitle) {
                    return false
                }
                return true
            }
        }

        return RecommendFeed.createExpanded(
            availableGenres: cached.availableGenres,
            spotlightPool: filterList(cached.spotlightPool),
            guessPool: filterList(cached.guessPool),
            hotRankItems: filterList(cached.hotRankItems),
            latestItems: filterList(cached.latestItems),
            moreStreamItems: filterList(cached.moreStreamItems),
            generatedAt: cached.generatedAt,
            isColdStart: cached.isColdStart || !personalizationActive,
            personalizationActive: personalizationActive
        )
    }

    public func loadSourceCache() -> [String: CachedSourceBucket] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return loadSourceCacheLocked()
    }

    private func loadSourceCacheLocked() -> [String: CachedSourceBucket] {
        let cacheFile = filesDirURL.appendingPathComponent(Self.sourceCacheFileName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheFile.path),
              let attrs = try? fm.attributesOfItem(atPath: cacheFile.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value, size > 0 else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: cacheFile)
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let root = obj as? [String: Any],
                  let verVal = root["version"],
                  let ver = JsonValueHelper.strictInt(verVal),
                  ver >= 1, ver <= Self.schemaVersion,
                  let sourcesObj = root["sources"] as? [String: Any] else {
                throw CacheError.invalid
            }
            var out: [String: CachedSourceBucket] = [:]
            for (sid, rawBucket) in sourcesObj {
                if sid.isEmpty || rawBucket is NSNull { continue }
                guard let bucketObj = rawBucket as? [String: Any] else { throw CacheError.invalid }
                let fetchedAt = RecommendModels.optInt64(bucketObj, "fetchedAt", defaultValue: 0)
                var list: [SourceCandidate] = []
                if let arr = bucketObj["candidates"] as? [Any] {
                    for elem in arr {
                        if let dict = elem as? [String: Any], let c = SourceCandidate.fromJSONObject(dict) {
                            list.append(c)
                        }
                    }
                }
                out[sid] = CachedSourceBucket(fetchedAt: fetchedAt, candidates: list)
            }
            return out
        } catch {
            backupCorruptFileIfAbsent(cacheFile)
            return [:]
        }
    }

    public func saveSourceCache(_ cache: [String: CachedSourceBucket]) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        saveSourceCacheLocked(cache)
    }

    private func saveSourceCacheLocked(_ cache: [String: CachedSourceBucket]) {
        let cacheFile = filesDirURL.appendingPathComponent(Self.sourceCacheFileName)
        var sourcesObj: [String: Any] = [:]
        for (sid, bucket) in cache where !sid.isEmpty {
            sourcesObj[sid] = [
                "fetchedAt": NSNumber(value: bucket.fetchedAt),
                "candidates": bucket.candidates.map { $0.toJSONObject() }
            ]
        }
        let root: [String: Any] = [
            "version": Self.schemaVersion,
            "sources": sourcesObj
        ]
        if let data = try? JSONSerialization.data(withJSONObject: root, options: []) {
            try? writeAtomic(data, to: cacheFile)
        }
    }

    private func writeAtomic(_ payload: Data, to target: URL) throws {
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let tmp = parent.appendingPathComponent(target.lastPathComponent + ".tmp")
        do {
            try payload.write(to: tmp, options: [])
            if let handle = try? FileHandle(forWritingTo: tmp) {
                try? handle.synchronize()
                try? handle.close()
            }
            let result = tmp.withUnsafeFileSystemRepresentation { srcPath -> Int32 in
                target.withUnsafeFileSystemRepresentation { dstPath -> Int32 in
                    guard let srcPath, let dstPath else { return -1 }
                    return rename(srcPath, dstPath)
                }
            }
            if result != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }

    private func backupCorruptFileIfAbsent(_ file: URL) {
        let backup = file.deletingLastPathComponent()
            .appendingPathComponent(file.lastPathComponent + ".corrupt")
        if FileManager.default.fileExists(atPath: backup.path) { return }
        if let data = try? Data(contentsOf: file) {
            try? data.write(to: backup, options: [])
        }
    }

    private static func currentMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private enum CacheError: Error {
        case invalid
    }
}
