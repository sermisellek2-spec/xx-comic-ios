import Foundation

/// Endless multi-source paginated stream controller for the recommendation feed.
/// Expands lazily beyond Wave-0 sources across all eligible non-VPN and VPN sources,
/// enforces duplicate-page loop protection, persists new candidates to `RecommendCandidatePool`,
/// and falls back to Option A long-tail recycling when all tracks exhaust.
public final class RecommendStreamPager: @unchecked Sendable {
    public static let defaultTargetBatchSize = 18
    public static let maxTracksPerSubRound = 3
    public static let maxLazyInitSources = 3
    public static let maxPersonalizedGenreTracks = 6
    public static let maxExplorationGenreTracks = 3
    public static let maxAuthorSearchTracks = 2
    public static let maxRecentShownHistory = 400
    public static let maxConsecutiveTrackErrors = 2

    private enum Bucket {
        case habit
        case hot
        case featured
        case exploreLatest
    }

    private static let bucketSchedule: [Bucket] = [
        .habit,
        .hot,
        .habit,
        .featured,
        .exploreLatest,
        .habit,
        .hot,
        .exploreLatest
    ]

    public struct BatchResult: Equatable, Sendable {
        public let items: [RecommendItem]
        public let recycled: Bool
        public let errorMessage: String

        public init(items: [RecommendItem], recycled: Bool, errorMessage: String = "") {
            self.items = items
            self.recycled = recycled
            self.errorMessage = errorMessage
        }

        public static func items(_ items: [RecommendItem], recycled: Bool) -> BatchResult {
            BatchResult(items: items, recycled: recycled, errorMessage: "")
        }

        public static func error(_ errorMessage: String) -> BatchResult {
            BatchResult(items: [], recycled: false, errorMessage: errorMessage)
        }

        public var hasItems: Bool { !items.isEmpty }
    }

    private let stateLock = NSLock()
    private let eligibleSources: [any ComicSource]
    private let eligibleSourceIds: Set<String>
    private let profile: HabitProfile
    private let profileStore: RecommendProfileStore?
    private let candidatePool: RecommendCandidatePool
    private let vpnSourceIds: Set<String>
    private let wave0IndexBySourceId: [String: Int]
    private let wave0OrderKnown: Bool
    private let excludedExistingTitles: Set<String>
    private var sessionExcludedTitles = Set<String>()
    private let titleNormalizer: (String) -> String
    private let blacklistTitlePredicate: ((String) -> Bool)?
    private let perSourceTimeoutMs: Int64
    private let fixedNowMillis: Int64

    private var nonVpnInitQueue: [SourceHolder] = []
    private var vpnInitQueue: [SourceHolder] = []
    private var initializedSources: [SourceHolder] = []
    private var sourceFilterCache: [String: [SourceFilterGroup]] = [:]

    private var seenStreamTitles = Set<String>()
    private var recentShownOrder: [String] = []
    private var recentTailItems: [RecommendItem] = []

    private var bucketScheduleIndex = 0
    private var sourceOrderInitCounter = 0
    private var batchRoundSeed = 0
    private var recycleRound = 0
    private var upperRoundSeed = 0

    // Async serialization gate so concurrent async fetch calls execute in order without holding stateLock across await.
    private var asyncBusy = false
    private var asyncWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        enabledSources: [any ComicSource],
        profile: HabitProfile?,
        profileStore: RecommendProfileStore?,
        candidatePool: RecommendCandidatePool,
        vpnSourceIds: Set<String>,
        wave0SourceIdsOrdered: [String],
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)? = nil,
        blacklistTitlePredicate: ((String) -> Bool)? = nil,
        initialShownItems: [RecommendItem] = [],
        perSourceTimeoutMs: Int64 = RecommendHarvester.defaultSourceTimeoutMs,
        fixedNowMillis: Int64 = 0,
        wave0OrderKnown: Bool? = nil
    ) {
        self.vpnSourceIds = vpnSourceIds
        self.profile = profile ?? HabitProfile.empty()
        self.profileStore = profileStore
        self.candidatePool = candidatePool
        self.titleNormalizer = titleNormalizer ?? { RecommendModels.normalizeTitleFallback($0) }
        self.blacklistTitlePredicate = blacklistTitlePredicate
        self.perSourceTimeoutMs = max(50, perSourceTimeoutMs)
        self.fixedNowMillis = fixedNowMillis

        let orderedEligible = Self.selectAllEligibleSources(
            enabledSources: enabledSources,
            profile: self.profile,
            vpnSourceIds: vpnSourceIds
        )
        self.eligibleSources = orderedEligible
        self.eligibleSourceIds = Set(orderedEligible.map(\.id))

        var w0Map: [String: Int] = [:]
        var idx = 0
        for rawId in wave0SourceIdsOrdered {
            let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && w0Map[trimmed] == nil {
                w0Map[trimmed] = idx
                idx += 1
            }
        }
        self.wave0IndexBySourceId = w0Map
        self.wave0OrderKnown = wave0OrderKnown ?? true
        self.excludedExistingTitles = Set(
            excludedExistingTitles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )

        var nonVpnWave1: [SourceHolder] = []
        var nonVpnWave0: [SourceHolder] = []
        var vpnWave1: [SourceHolder] = []
        var vpnWave0: [SourceHolder] = []
        for (i, src) in orderedEligible.enumerated() {
            let isVpn = vpnSourceIds.contains(src.id)
            let holder = SourceHolder(source: src, isVpn: isVpn, orderSeed: i)
            let isWave0 = w0Map[src.id] != nil
            if isVpn {
                if isWave0 { vpnWave0.append(holder) } else { vpnWave1.append(holder) }
            } else {
                if isWave0 { nonVpnWave0.append(holder) } else { nonVpnWave1.append(holder) }
            }
        }
        self.nonVpnInitQueue = nonVpnWave1 + nonVpnWave0
        self.vpnInitQueue = vpnWave1 + vpnWave0

        if !initialShownItems.isEmpty {
            recordCommittedItemsLocked(initialShownItems)
        }
    }

    public static func selectAllEligibleSources(
        enabledSources: [any ComicSource],
        profile: HabitProfile?,
        vpnSourceIds: Set<String>
    ) -> [any ComicSource] {
        guard !enabledSources.isEmpty else { return [] }
        var eligible: [(source: any ComicSource, isVpn: Bool, weight: Double, index: Int)] = []
        var seenIds = Set<String>()
        for (i, src) in enabledSources.enumerated() {
            let trimmedId = src.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedId.isEmpty { continue }
            if RecommendHarvester.isManualVerificationOnlySource(trimmedId) { continue }
            if !seenIds.insert(trimmedId).inserted { continue }
            let isVpn = vpnSourceIds.contains(trimmedId)
            let weight = profile?.sourceWeights[trimmedId] ?? UserHabitProfiler.sourceWeightDefault
            eligible.append((src, isVpn, weight, i))
        }
        eligible.sort { a, b in
            if a.isVpn != b.isVpn { return !a.isVpn && b.isVpn }
            if a.weight != b.weight { return a.weight > b.weight }
            return a.index < b.index
        }
        return eligible.map(\.source)
    }

    public func markTitleBlacklistedOrRemoved(_ titleOrNorm: String?) {
        let norm = normalizeKey(titleOrNorm)
        guard !norm.isEmpty else { return }
        stateLock.lock()
        seenStreamTitles.insert(norm)
        sessionExcludedTitles.insert(norm)
        removeTitleFromRecentLocked(norm)
        stateLock.unlock()
    }

    public func removeFromSeen(_ titleOrNorm: String?) {
        let norm = normalizeKey(titleOrNorm)
        guard !norm.isEmpty else { return }
        stateLock.lock()
        seenStreamTitles.remove(norm)
        sessionExcludedTitles.remove(norm)
        removeTitleFromRecentLocked(norm)
        stateLock.unlock()
    }

    public func notifyBlacklistChanged() {
        guard let blacklistTitlePredicate else { return }
        stateLock.lock()
        recentShownOrder.removeAll { blacklistTitlePredicate($0) }
        recentTailItems.removeAll { item in
            let rawTitle = item.summary.title
            let norm = resolveItemNormTitle(item)
            return blacklistTitlePredicate(norm) || (!rawTitle.isEmpty && blacklistTitlePredicate(rawTitle))
        }
        stateLock.unlock()
    }

    public func fetchNextBatch(targetBatchSize: Int = defaultTargetBatchSize) async -> BatchResult {
        await acquireAsyncGate()
        defer { releaseAsyncGate() }

        let safeTarget = max(1, targetBatchSize)
        let now = currentNowMillis()

        stateLock.lock()
        let excludedNow = buildCombinedExclusionsLocked()
        batchRoundSeed += 1
        let currentBatchSeed = batchRoundSeed
        let initialSeen = seenStreamTitles
        let initialTail = recentTailItems
        stateLock.unlock()

        // Step 1: Fast Reserve from candidate pool
        var poolSnapshot = eligibleSourceIds.isEmpty
            ? []
            : candidatePool.snapshotForSources(allowedSourceIds: eligibleSourceIds, nowMillis: now)
        var accumulated: [RecommendItem] = poolSnapshot.isEmpty
            ? []
            : RecommendEngine.buildMoreBatch(
                rawCandidates: poolSnapshot,
                profile: profile,
                store: profileStore,
                alreadyShownNormTitles: initialSeen,
                excludedExistingTitles: Array(excludedNow),
                titleNormalizer: titleNormalizer,
                blacklistTitlePredicate: blacklistTitlePredicate,
                batchSize: safeTarget,
                recentTailItems: initialTail,
                nowMillis: now,
                cycleSeed: currentBatchSeed
            )
        if accumulated.count >= safeTarget {
            stateLock.lock()
            recordCommittedItemsLocked(accumulated)
            stateLock.unlock()
            return .items(accumulated, recycled: false)
        }

        // Step 2: Concurrent Multi-Source Track Fetch (up to 2 sub-rounds)
        var networkErrors = 0
        for subRound in 0..<2 {
            if Task.isCancelled { break }
            await ensureSourcesInitialized(isFirstSubRound: subRound == 0)

            stateLock.lock()
            var pickedTracks = pickDistinctSourceTracksLocked(maxTracks: Self.maxTracksPerSubRound)
            let needVpnInit = pickedTracks.isEmpty && nonVpnInitQueue.isEmpty
                && activeTrackCountLocked(vpnOnly: false) == 0 && !vpnInitQueue.isEmpty
            stateLock.unlock()

            if needVpnInit {
                await initNextSources(fromVpnQueue: true, maxToInit: Self.maxLazyInitSources)
                stateLock.lock()
                pickedTracks = pickDistinctSourceTracksLocked(maxTracks: Self.maxTracksPerSubRound)
                stateLock.unlock()
            }
            if pickedTracks.isEmpty { break }

            let outcome = await executeTracksConcurrently(pickedTracks: pickedTracks, nowMillis: now)
            networkErrors += outcome.networkErrors

            if !outcome.candidates.isEmpty {
                let changed = candidatePool.merge(outcome.candidates, titleNormalizer: titleNormalizer, nowMillis: now)
                if changed > 0 {
                    candidatePool.persistNow()
                }
                poolSnapshot = candidatePool.snapshotForSources(allowedSourceIds: eligibleSourceIds, nowMillis: now)
                stateLock.lock()
                let seenNow = seenStreamTitles
                let tailNow = recentTailItems
                let exclNow = buildCombinedExclusionsLocked()
                stateLock.unlock()

                accumulated = RecommendEngine.buildMoreBatch(
                    rawCandidates: poolSnapshot,
                    profile: profile,
                    store: profileStore,
                    alreadyShownNormTitles: seenNow,
                    excludedExistingTitles: Array(exclNow),
                    titleNormalizer: titleNormalizer,
                    blacklistTitlePredicate: blacklistTitlePredicate,
                    batchSize: safeTarget,
                    recentTailItems: tailNow,
                    nowMillis: now,
                    cycleSeed: currentBatchSeed
                )
            }

            if accumulated.count >= min(safeTarget, Self.defaultTargetBatchSize) {
                stateLock.lock()
                recordCommittedItemsLocked(accumulated)
                stateLock.unlock()
                return .items(accumulated, recycled: false)
            }
        }

        if !accumulated.isEmpty {
            stateLock.lock()
            let allTracksExhausted = !hasAnyRemainingSourcesOrTracksLocked()
            if !allTracksExhausted || accumulated.count >= safeTarget {
                recordCommittedItemsLocked(accumulated)
                stateLock.unlock()
                return .items(accumulated, recycled: false)
            }
            recordCommittedItemsLocked(accumulated)
            var excludedForTopUp = buildCombinedExclusionsLocked()
            for item in accumulated {
                let norm = resolveItemNormTitle(item)
                if !norm.isEmpty { excludedForTopUp.insert(norm) }
            }
            let recentOrderSnapshot = recentShownOrder
            let tailSnapshot = recentTailItems
            recycleRound += 1
            let round = recycleRound
            stateLock.unlock()

            poolSnapshot = candidatePool.snapshotForSources(allowedSourceIds: eligibleSourceIds, nowMillis: now)
            let recycledTopUp = RecommendEngine.buildRecycledBatch(
                poolCandidates: poolSnapshot,
                profile: profile,
                store: profileStore,
                recentShownOrderNormTitles: recentOrderSnapshot,
                excludedExistingTitles: Array(excludedForTopUp),
                titleNormalizer: titleNormalizer,
                blacklistTitlePredicate: blacklistTitlePredicate,
                batchSize: safeTarget - accumulated.count,
                recentTailItems: tailSnapshot,
                nowMillis: now,
                recycleRound: round
            )
            if recycledTopUp.isEmpty {
                return .items(accumulated, recycled: false)
            }
            stateLock.lock()
            recordRecycledItemsLocked(recycledTopUp)
            stateLock.unlock()
            return .items(accumulated + recycledTopUp, recycled: true)
        }

        // Step 3: Option A Endless Recycle Fallback
        poolSnapshot = eligibleSourceIds.isEmpty
            ? []
            : candidatePool.snapshotForSources(allowedSourceIds: eligibleSourceIds, nowMillis: now)
        if poolSnapshot.isEmpty {
            if networkErrors > 0 {
                return .error("加载更多推荐失败，请点击重试")
            }
            return .items([], recycled: false)
        }

        stateLock.lock()
        let recentOrderSnapshot = recentShownOrder
        let tailSnapshot = recentTailItems
        let exclNow = buildCombinedExclusionsLocked()
        recycleRound += 1
        let round = recycleRound
        stateLock.unlock()

        let recycledBatch = RecommendEngine.buildRecycledBatch(
            poolCandidates: poolSnapshot,
            profile: profile,
            store: profileStore,
            recentShownOrderNormTitles: recentOrderSnapshot,
            excludedExistingTitles: Array(exclNow),
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            batchSize: safeTarget,
            recentTailItems: tailSnapshot,
            nowMillis: now,
            recycleRound: round
        )
        if recycledBatch.isEmpty {
            return .items([], recycled: false)
        }
        stateLock.lock()
        recordRecycledItemsLocked(recycledBatch)
        stateLock.unlock()
        return .items(recycledBatch, recycled: true)
    }

    public func replenishUpperSection(
        isSpotlight: Bool,
        existingUpperNorms: Set<String>,
        count: Int
    ) async -> [RecommendItem] {
        await acquireAsyncGate()
        defer { releaseAsyncGate() }

        let safeCount = max(1, count)
        let now = currentNowMillis()

        stateLock.lock()
        let excludedNow = buildCombinedExclusionsLocked()
        upperRoundSeed += 1
        let round = upperRoundSeed
        let hasRemaining = hasAnyRemainingSourcesOrTracksLocked()
        stateLock.unlock()

        var poolSnapshot = eligibleSourceIds.isEmpty
            ? []
            : candidatePool.snapshotForSources(allowedSourceIds: eligibleSourceIds, nowMillis: now)
        var items = RecommendEngine.buildUpperReplenishBatch(
            poolCandidates: poolSnapshot,
            profile: profile,
            store: profileStore,
            existingUpperNormTitles: existingUpperNorms,
            excludedExistingTitles: Array(excludedNow),
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            isSpotlight: isSpotlight,
            batchSize: safeCount,
            nowMillis: now,
            roundSeed: round
        )
        if items.count >= safeCount || !hasRemaining {
            return items
        }

        await ensureSourcesInitialized(isFirstSubRound: true)

        stateLock.lock()
        var pickedTracks = pickDistinctSourceTracksLocked(maxTracks: Self.maxTracksPerSubRound)
        let needVpnInit = pickedTracks.isEmpty && nonVpnInitQueue.isEmpty
            && activeTrackCountLocked(vpnOnly: false) == 0 && !vpnInitQueue.isEmpty
        stateLock.unlock()

        if needVpnInit {
            await initNextSources(fromVpnQueue: true, maxToInit: Self.maxLazyInitSources)
            stateLock.lock()
            pickedTracks = pickDistinctSourceTracksLocked(maxTracks: Self.maxTracksPerSubRound)
            stateLock.unlock()
        }
        guard !pickedTracks.isEmpty else { return items }

        let outcome = await executeTracksConcurrently(pickedTracks: pickedTracks, nowMillis: now)
        if !outcome.candidates.isEmpty {
            let changed = candidatePool.merge(outcome.candidates, titleNormalizer: titleNormalizer, nowMillis: now)
            if changed > 0 {
                candidatePool.persistNow()
            }
            poolSnapshot = candidatePool.snapshotForSources(allowedSourceIds: eligibleSourceIds, nowMillis: now)
            items = RecommendEngine.buildUpperReplenishBatch(
                poolCandidates: poolSnapshot,
                profile: profile,
                store: profileStore,
                existingUpperNormTitles: existingUpperNorms,
                excludedExistingTitles: Array(excludedNow),
                titleNormalizer: titleNormalizer,
                blacklistTitlePredicate: blacklistTitlePredicate,
                isSpotlight: isSpotlight,
                batchSize: safeCount,
                nowMillis: now,
                roundSeed: round
            )
        }
        return items
    }

    // MARK: - Source Initialization & Track Scheduling

    private func ensureSourcesInitialized(isFirstSubRound: Bool) async {
        stateLock.lock()
        let hasNonVpnQueue = !nonVpnInitQueue.isEmpty
        let activeNonVpn = activeTrackCountLocked(vpnOnly: false)
        let hasVpnQueue = !vpnInitQueue.isEmpty
        let activeVpn = activeTrackCountLocked(vpnOnly: true)
        stateLock.unlock()

        if hasNonVpnQueue {
            if isFirstSubRound || activeNonVpn < 6 {
                await initNextSources(fromVpnQueue: false, maxToInit: Self.maxLazyInitSources)
            }
            return
        }
        if activeNonVpn == 0 && hasVpnQueue && (isFirstSubRound || activeVpn < 6) {
            await initNextSources(fromVpnQueue: true, maxToInit: Self.maxLazyInitSources)
        }
    }

    private enum FilterGroupEvent: Sendable {
        case loaded(sourceId: String, groups: [SourceFilterGroup])
        case budgetExpired
    }

    private func initNextSources(fromVpnQueue: Bool, maxToInit: Int) async {
        stateLock.lock()
        var batch: [SourceHolder] = []
        if fromVpnQueue {
            while batch.count < maxToInit && !vpnInitQueue.isEmpty {
                batch.append(vpnInitQueue.removeFirst())
            }
        } else {
            while batch.count < maxToInit && !nonVpnInitQueue.isEmpty {
                batch.append(nonVpnInitQueue.removeFirst())
            }
        }
        let needFilters = batch.filter { sourceFilterCache[$0.sourceId] == nil }
        stateLock.unlock()

        guard !batch.isEmpty else { return }

        if !needFilters.isEmpty {
            let maxTimeoutMs = needFilters
                .map { RecommendHarvester.effectiveSourceTimeoutMs(source: $0.source, baseTimeoutMs: perSourceTimeoutMs) }
                .max() ?? perSourceTimeoutMs
            let budgetMs = Self.computeBatchBudgetMs(
                basePerSourceTimeoutMs: perSourceTimeoutMs,
                maxEffectiveTimeoutMs: maxTimeoutMs
            )

            var loadedMap: [String: [SourceFilterGroup]] = [:]
            await withTaskGroup(of: FilterGroupEvent.self) { group in
                for holder in needFilters {
                    let source = holder.source
                    let sourceId = holder.sourceId
                    let timeoutMs = RecommendHarvester.effectiveSourceTimeoutMs(
                        source: source,
                        baseTimeoutMs: perSourceTimeoutMs
                    )
                    group.addTask {
                        let groups = await RecommendHarvester.runWithTimeout(timeoutMs: timeoutMs) {
                            await RuleCallPriority.withBackgroundPriority {
                                (try? await source.filterGroups()) ?? []
                            }
                        }
                        return .loaded(sourceId: sourceId, groups: groups ?? [])
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(max(1, budgetMs)) * 1_000_000)
                    return .budgetExpired
                }

                var remaining = needFilters.count
                for await event in group {
                    switch event {
                    case .budgetExpired:
                        group.cancelAll()
                        remaining = 0
                    case .loaded(let sid, let groups):
                        remaining -= 1
                        loadedMap[sid] = groups
                        if remaining <= 0 {
                            group.cancelAll()
                        }
                    }
                    if remaining <= 0 { break }
                }
            }

            stateLock.lock()
            for holder in needFilters {
                if let groups = loadedMap[holder.sourceId] {
                    sourceFilterCache[holder.sourceId] = groups
                } else if sourceFilterCache[holder.sourceId] == nil {
                    sourceFilterCache[holder.sourceId] = []
                }
            }
            stateLock.unlock()
        }

        stateLock.lock()
        for holder in batch {
            let groups = sourceFilterCache[holder.sourceId] ?? []
            let initIdx = sourceOrderInitCounter
            sourceOrderInitCounter += 1
            buildTracksForSourceLocked(holder: holder, groups: groups, sourceInitIndex: initIdx)
            initializedSources.append(holder)
        }
        stateLock.unlock()
    }

    private func buildTracksForSourceLocked(
        holder: SourceHolder,
        groups: [SourceFilterGroup],
        sourceInitIndex: Int
    ) {
        let source = holder.source
        let sourceId = holder.sourceId
        let sourceName = holder.sourceName
        let wave0Idx = wave0IndexBySourceId[sourceId]
        let isWave0 = wave0Idx != nil
        let resolvedWave0Idx = wave0Idx ?? -1
        let personalizationActive = profileStore?.isPersonalizationEnabled ?? true

        var usedFilters = Set<[String: String]>()

        let featuredPlan = RecommendSourceClassifier.detectFeaturedRecommendPlan(groups)
        let hotPlan = RecommendSourceClassifier.detectHotRankingPlan(groups)
        let latestPlan = RecommendSourceClassifier.detectLatestPlan(groups)

        if let featuredPlan, usedFilters.insert(featuredPlan.filters).inserted {
            let featStartPage = isWave0 && (!wave0OrderKnown || resolvedWave0Idx < 3 || hotPlan == nil) ? 2 : 1
            holder.tracks.append(TrackState.categoryTrack(
                source: source, sourceId: sourceId, sourceName: sourceName,
                bucket: .featured, channel: .sourceFeaturedCategory,
                filters: featuredPlan.filters, featuredLabel: featuredPlan.matchedLabel,
                queryGenre: "", initialPage: featStartPage
            ))
        }

        if let hotPlan, usedFilters.insert(hotPlan.filters).inserted {
            let hotStartPage = isWave0 ? 2 : 1
            holder.tracks.append(TrackState.categoryTrack(
                source: source, sourceId: sourceId, sourceName: sourceName,
                bucket: .hot, channel: .systemConsensusHot,
                filters: hotPlan.filters, featuredLabel: "",
                queryGenre: "", initialPage: hotStartPage
            ))
        }

        let latestStartPage = isWave0 && (!wave0OrderKnown || resolvedWave0Idx < 3) ? 2 : 1
        if let latestPlan, usedFilters.insert(latestPlan.filters).inserted {
            holder.tracks.append(TrackState.categoryTrack(
                source: source, sourceId: sourceId, sourceName: sourceName,
                bucket: .exploreLatest, channel: .latestUpdates,
                filters: latestPlan.filters, featuredLabel: "",
                queryGenre: "", initialPage: latestStartPage
            ))
        } else {
            holder.tracks.append(TrackState.latestFallbackTrack(
                source: source, sourceId: sourceId, sourceName: sourceName,
                initialPage: latestStartPage
            ))
        }

        // Personalized genre tracks (up to 6)
        var personalGenresOrdered: [String] = []
        var personalSeen = Set<String>()
        for g in profile.topGenres where personalSeen.insert(g).inserted {
            personalGenresOrdered.append(g)
        }
        for g in profile.knownGenres where personalSeen.insert(g).inserted {
            personalGenresOrdered.append(g)
        }

        var wave0ShardedGenre = ""
        if isWave0 && personalizationActive && !profile.topGenres.isEmpty
            && (!wave0OrderKnown || resolvedWave0Idx < 4) {
            let genreCount = profile.topGenres.count
            let startIdx = wave0OrderKnown ? (resolvedWave0Idx % genreCount) : 0
            var simulatedFilters = usedFilters
            for offset in 0..<genreCount {
                let g = profile.topGenres[(startIdx + offset) % genreCount]
                if let gp = RecommendSourceClassifier.detectGenrePlan(groups, canonicalGenre: g),
                   simulatedFilters.insert(gp.filters).inserted {
                    wave0ShardedGenre = g
                    break
                }
            }
        }

        var addedPersonal = 0
        for genre in personalGenresOrdered {
            if addedPersonal >= Self.maxPersonalizedGenreTracks { break }
            if let w = profile.genreWeights[genre], w < -0.5 { continue }
            if let genrePlan = RecommendSourceClassifier.detectGenrePlan(groups, canonicalGenre: genre),
               usedFilters.insert(genrePlan.filters).inserted {
                let startPage = (isWave0 && genre == wave0ShardedGenre) ? 2 : 1
                holder.tracks.append(TrackState.categoryTrack(
                    source: source, sourceId: sourceId, sourceName: sourceName,
                    bucket: .habit, channel: .habitPersonalized,
                    filters: genrePlan.filters, featuredLabel: "",
                    queryGenre: genre, initialPage: startPage
                ))
                addedPersonal += 1
            }
        }

        // Exploration tracks: up to 3 unseen canonical genres
        let canonical = RecommendSourceClassifier.canonicalGenres
        if !canonical.isEmpty {
            let offsetStart = (sourceInitIndex * 3) % canonical.count
            var addedExplore = 0
            var i = 0
            while i < canonical.count && addedExplore < Self.maxExplorationGenreTracks {
                let genre = canonical[(offsetStart + i) % canonical.count]
                i += 1
                if profile.knownGenres.contains(genre) { continue }
                if let w = profile.genreWeights[genre], w < -0.5 { continue }
                if let explorePlan = RecommendSourceClassifier.detectGenrePlan(groups, canonicalGenre: genre),
                   usedFilters.insert(explorePlan.filters).inserted {
                    holder.tracks.append(TrackState.categoryTrack(
                        source: source, sourceId: sourceId, sourceName: sourceName,
                        bucket: .exploreLatest, channel: .explorationNewTaste,
                        filters: explorePlan.filters, featuredLabel: "",
                        queryGenre: genre, initialPage: 1
                    ))
                    addedExplore += 1
                }
            }
        }

        // Personalized author search tracks
        if personalizationActive && !profile.topAuthors.isEmpty && source.supportsSearch {
            let authorLimit = min(Self.maxAuthorSearchTracks, profile.topAuthors.count)
            for i in 0..<authorLimit {
                let author = profile.topAuthors[i]
                let startPage = (isWave0 && wave0OrderKnown && resolvedWave0Idx == i) ? 2 : 1
                holder.tracks.append(TrackState.authorSearchTrack(
                    source: source, sourceId: sourceId, sourceName: sourceName,
                    author: author, initialPage: startPage
                ))
            }
        }
    }

    private func pickDistinctSourceTracksLocked(maxTracks: Int) -> [TrackState] {
        let allowVpn = activeTrackCountLocked(vpnOnly: false) == 0 && nonVpnInitQueue.isEmpty
        var candidates = initializedSources.filter { holder in
            (allowVpn || !holder.isVpn) && holder.hasActiveTracks
        }
        guard !candidates.isEmpty else { return [] }

        candidates.sort { a, b in
            if a.isVpn != b.isVpn { return !a.isVpn && b.isVpn }
            if a.fetchCount != b.fetchCount { return a.fetchCount < b.fetchCount }
            return a.orderSeed < b.orderSeed
        }

        var picked: [TrackState] = []
        picked.reserveCapacity(maxTracks)
        var usedSourceIds = Set<String>()

        for _ in 0..<maxTracks {
            if picked.count >= candidates.count { break }
            let targetBucket = Self.bucketSchedule[bucketScheduleIndex % Self.bucketSchedule.count]
            bucketScheduleIndex += 1

            var chosen: TrackState?
            var chosenHolder: SourceHolder?
            for holder in candidates where !usedSourceIds.contains(holder.sourceId) {
                if let t = holder.bestActiveTrack(for: targetBucket) {
                    chosen = t
                    chosenHolder = holder
                    break
                }
            }
            if chosen == nil {
                for holder in candidates where !usedSourceIds.contains(holder.sourceId) {
                    if let t = holder.bestAnyActiveTrack() {
                        chosen = t
                        chosenHolder = holder
                        break
                    }
                }
            }
            guard let chosen, let chosenHolder else { break }
            usedSourceIds.insert(chosenHolder.sourceId)
            chosenHolder.fetchCount += 1
            picked.append(chosen)
        }
        return picked
    }

    private enum TrackGroupEvent: Sendable {
        case fetched(trackIndex: Int, fetchedPage: Int, summaries: [ComicSummary]?, hasMore: Bool, failed: Bool)
        case budgetExpired
    }

    private func executeTracksConcurrently(pickedTracks: [TrackState], nowMillis: Int64) async -> (candidates: [SourceCandidate], networkErrors: Int) {
        let maxTimeoutMs = pickedTracks
            .map { RecommendHarvester.effectiveSourceTimeoutMs(source: $0.source, baseTimeoutMs: perSourceTimeoutMs) }
            .max() ?? perSourceTimeoutMs
        let batchBudgetMs = Self.computeBatchBudgetMs(
            basePerSourceTimeoutMs: perSourceTimeoutMs,
            maxEffectiveTimeoutMs: maxTimeoutMs
        )

        var outcomes: [Int: TrackGroupEvent] = [:]
        await withTaskGroup(of: TrackGroupEvent.self) { group in
            for (idx, track) in pickedTracks.enumerated() {
                stateLock.lock()
                let pageToFetch = track.nextPage
                stateLock.unlock()

                let source = track.source
                let isSearch = track.isSearch
                let isLatestFallback = track.isLatestFallback
                let queryAuthor = track.queryAuthor
                let filters = track.filters
                let timeoutMs = RecommendHarvester.effectiveSourceTimeoutMs(
                    source: source,
                    baseTimeoutMs: perSourceTimeoutMs
                )
                group.addTask {
                    let result = await RecommendHarvester.runWithTimeout(timeoutMs: timeoutMs) {
                        await RuleCallPriority.withBackgroundPriority {
                            do {
                                let summaries: [ComicSummary]
                                let hasMore: Bool
                                if isSearch {
                                    summaries = try await source.search(keyword: queryAuthor, page: pageToFetch)
                                    hasMore = !summaries.isEmpty && source.hasMoreSearchPage(summaries)
                                } else if isLatestFallback {
                                    summaries = try await source.latest(page: pageToFetch)
                                    hasMore = !summaries.isEmpty && source.hasMoreCategoryPage(summaries)
                                } else {
                                    summaries = try await source.category(filters: filters, page: pageToFetch)
                                    hasMore = !summaries.isEmpty && source.hasMoreCategoryPage(summaries)
                                }
                                return (summaries: summaries, hasMore: hasMore, failed: false)
                            } catch {
                                return (summaries: [ComicSummary](), hasMore: false, failed: true)
                            }
                        }
                    }
                    if let result {
                        return .fetched(
                            trackIndex: idx,
                            fetchedPage: pageToFetch,
                            summaries: result.summaries,
                            hasMore: result.hasMore,
                            failed: result.failed
                        )
                    } else {
                        return .fetched(trackIndex: idx, fetchedPage: pageToFetch, summaries: nil, hasMore: false, failed: true)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(1, batchBudgetMs)) * 1_000_000)
                return .budgetExpired
            }

            var remaining = pickedTracks.count
            for await event in group {
                switch event {
                case .budgetExpired:
                    group.cancelAll()
                    remaining = 0
                case .fetched(let trackIndex, _, _, _, _):
                    remaining -= 1
                    outcomes[trackIndex] = event
                    if remaining <= 0 {
                        group.cancelAll()
                    }
                }
                if remaining <= 0 { break }
            }
        }

        var mergedCandidates: [SourceCandidate] = []
        var networkErrors = 0

        stateLock.lock()
        for (idx, track) in pickedTracks.enumerated() {
            guard let event = outcomes[idx],
                  case .fetched(_, let fetchedPage, let summaries, let hasMore, let failed) = event,
                  !failed,
                  let summaries else {
                recordTrackFailureLocked(track)
                networkErrors += 1
                continue
            }
            processTrackOutcomeLocked(
                track: track,
                fetchedPage: fetchedPage,
                summaries: summaries,
                hasMore: hasMore,
                nowMillis: nowMillis,
                outCandidates: &mergedCandidates
            )
        }
        stateLock.unlock()

        return (mergedCandidates, networkErrors)
    }

    private func processTrackOutcomeLocked(
        track: TrackState,
        fetchedPage: Int,
        summaries: [ComicSummary],
        hasMore: Bool,
        nowMillis: Int64,
        outCandidates: inout [SourceCandidate]
    ) {
        if summaries.isEmpty {
            track.exhausted = true
            return
        }

        var pageIds = Set<String>()
        for s in summaries {
            let cid = !s.comicId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? s.comicId.trimmingCharacters(in: .whitespacesAndNewlines)
                : s.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cid.isEmpty {
                pageIds.insert(cid)
            }
        }
        if pageIds.isEmpty {
            track.exhausted = true
            return
        }

        // Looping pagination protection: stop if every ID on this page was already seen on previous pages.
        if !track.prevPageIds.isEmpty && pageIds.isSubset(of: track.prevPageIds) {
            track.exhausted = true
            return
        }

        track.prevPageIds.formUnion(pageIds)
        track.consecutiveErrors = 0

        let maxPerList = track.isSearch ? RecommendHarvester.maxAuthorResults : RecommendHarvester.maxItemsPerList
        let rankOffset = max(0, (fetchedPage - 1) * maxPerList)
        RecommendHarvester.convertSummariesToCandidates(
            summaries: summaries,
            sourceId: track.sourceId,
            sourceName: track.sourceName,
            channel: track.channel,
            featuredLabel: track.featuredLabel,
            queryGenre: track.queryGenre,
            queryAuthor: track.queryAuthor,
            maxItems: maxPerList,
            rankOffset: rankOffset,
            nowMillis: nowMillis,
            out: &outCandidates
        )

        if !hasMore {
            track.exhausted = true
        } else {
            track.nextPage += 1
        }
    }

    private func recordTrackFailureLocked(_ track: TrackState) {
        track.consecutiveErrors += 1
        if track.consecutiveErrors >= Self.maxConsecutiveTrackErrors {
            track.exhausted = true
        }
    }

    public static func computeBatchBudgetMs(basePerSourceTimeoutMs: Int64, maxEffectiveTimeoutMs: Int64) -> Int64 {
        let effectiveMax = max(basePerSourceTimeoutMs, maxEffectiveTimeoutMs)
        if effectiveMax < RecommendHarvester.defaultSourceTimeoutMs {
            return max(effectiveMax + 250, effectiveMax * 2)
        }
        return max(7_500, effectiveMax + 2_000)
    }

    private func activeTrackCountLocked(vpnOnly: Bool) -> Int {
        var count = 0
        for holder in initializedSources where holder.isVpn == vpnOnly {
            for t in holder.tracks where !t.exhausted {
                count += 1
            }
        }
        return count
    }

    private func hasAnyRemainingSourcesOrTracksLocked() -> Bool {
        if !nonVpnInitQueue.isEmpty || !vpnInitQueue.isEmpty { return true }
        return initializedSources.contains { $0.hasActiveTracks }
    }

    private func buildCombinedExclusionsLocked() -> Set<String> {
        excludedExistingTitles.union(sessionExcludedTitles)
    }

    private func recordCommittedItemsLocked(_ items: [RecommendItem]) {
        for item in items {
            let norm = resolveItemNormTitle(item)
            if !norm.isEmpty {
                seenStreamTitles.insert(norm)
                recentShownOrder.append(norm)
            }
            recentTailItems.append(item)
        }
        trimRecentBuffersLocked()
    }

    private func recordRecycledItemsLocked(_ items: [RecommendItem]) {
        for item in items {
            let norm = resolveItemNormTitle(item)
            if !norm.isEmpty {
                recentShownOrder.append(norm)
            }
            recentTailItems.append(item)
        }
        trimRecentBuffersLocked()
    }

    private func trimRecentBuffersLocked() {
        while recentShownOrder.count > Self.maxRecentShownHistory {
            recentShownOrder.removeFirst()
        }
        while recentTailItems.count > RecommendEngine.diversityWindowSize {
            recentTailItems.removeFirst()
        }
    }

    private func removeTitleFromRecentLocked(_ norm: String) {
        recentShownOrder.removeAll { $0 == norm }
        recentTailItems.removeAll { resolveItemNormTitle($0) == norm }
    }

    private func resolveItemNormTitle(_ item: RecommendItem) -> String {
        if !item.normalizedTitle.isEmpty { return item.normalizedTitle }
        return normalizeKey(item.summary.title)
    }

    private func normalizeKey(_ titleOrNorm: String?) -> String {
        guard let titleOrNorm else { return "" }
        let trimmed = titleOrNorm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let norm = titleNormalizer(trimmed)
        return norm.isEmpty ? RecommendModels.normalizeTitleFallback(trimmed) : norm
    }

    private func currentNowMillis() -> Int64 {
        fixedNowMillis > 0 ? fixedNowMillis : Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private func acquireAsyncGate() async {
        await withCheckedContinuation { continuation in
            stateLock.lock()
            if !asyncBusy {
                asyncBusy = true
                stateLock.unlock()
                continuation.resume()
            } else {
                asyncWaiters.append(continuation)
                stateLock.unlock()
            }
        }
    }

    private func releaseAsyncGate() {
        stateLock.lock()
        if !asyncWaiters.isEmpty {
            let next = asyncWaiters.removeFirst()
            stateLock.unlock()
            next.resume()
        } else {
            asyncBusy = false
            stateLock.unlock()
        }
    }

    // MARK: - Internal Holder & Track Models

    private final class SourceHolder {
        let source: any ComicSource
        let sourceId: String
        let sourceName: String
        let isVpn: Bool
        var tracks: [TrackState] = []
        var fetchCount = 0
        let orderSeed: Int

        init(source: any ComicSource, isVpn: Bool, orderSeed: Int) {
            self.source = source
            let trimmedId = source.id.trimmingCharacters(in: .whitespacesAndNewlines)
            self.sourceId = trimmedId
            let rawName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            self.sourceName = rawName.isEmpty ? trimmedId : rawName
            self.isVpn = isVpn
            self.orderSeed = orderSeed
        }

        var hasActiveTracks: Bool {
            tracks.contains { !$0.exhausted }
        }

        func bestActiveTrack(for bucket: Bucket) -> TrackState? {
            var best: TrackState?
            for t in tracks where !t.exhausted && t.bucket == bucket {
                if best == nil || t.nextPage < best!.nextPage {
                    best = t
                }
            }
            return best
        }

        func bestAnyActiveTrack() -> TrackState? {
            var best: TrackState?
            for t in tracks where !t.exhausted {
                if best == nil || t.nextPage < best!.nextPage {
                    best = t
                }
            }
            return best
        }
    }

    private final class TrackState: @unchecked Sendable {
        let source: any ComicSource
        let sourceId: String
        let sourceName: String
        let bucket: Bucket
        let channel: RecommendChannel
        let filters: [String: String]
        let featuredLabel: String
        let queryGenre: String
        let queryAuthor: String
        let isLatestFallback: Bool
        let isSearch: Bool
        var prevPageIds = Set<String>()
        var nextPage: Int
        var exhausted = false
        var consecutiveErrors = 0

        private init(
            source: any ComicSource,
            sourceId: String,
            sourceName: String,
            bucket: Bucket,
            channel: RecommendChannel,
            filters: [String: String],
            featuredLabel: String,
            queryGenre: String,
            queryAuthor: String,
            isLatestFallback: Bool,
            isSearch: Bool,
            initialPage: Int
        ) {
            self.source = source
            self.sourceId = sourceId
            self.sourceName = sourceName
            self.bucket = bucket
            self.channel = channel
            self.filters = filters
            self.featuredLabel = featuredLabel
            self.queryGenre = queryGenre
            self.queryAuthor = queryAuthor
            self.isLatestFallback = isLatestFallback
            self.isSearch = isSearch
            self.nextPage = max(1, initialPage)
        }

        static func categoryTrack(
            source: any ComicSource,
            sourceId: String,
            sourceName: String,
            bucket: Bucket,
            channel: RecommendChannel,
            filters: [String: String],
            featuredLabel: String,
            queryGenre: String,
            initialPage: Int
        ) -> TrackState {
            TrackState(
                source: source, sourceId: sourceId, sourceName: sourceName,
                bucket: bucket, channel: channel, filters: filters,
                featuredLabel: featuredLabel, queryGenre: queryGenre, queryAuthor: "",
                isLatestFallback: false, isSearch: false, initialPage: initialPage
            )
        }

        static func latestFallbackTrack(
            source: any ComicSource,
            sourceId: String,
            sourceName: String,
            initialPage: Int
        ) -> TrackState {
            TrackState(
                source: source, sourceId: sourceId, sourceName: sourceName,
                bucket: .exploreLatest, channel: .latestUpdates, filters: [:],
                featuredLabel: "", queryGenre: "", queryAuthor: "",
                isLatestFallback: true, isSearch: false, initialPage: initialPage
            )
        }

        static func authorSearchTrack(
            source: any ComicSource,
            sourceId: String,
            sourceName: String,
            author: String,
            initialPage: Int
        ) -> TrackState {
            TrackState(
                source: source, sourceId: sourceId, sourceName: sourceName,
                bucket: .habit, channel: .habitPersonalized, filters: [:],
                featuredLabel: "", queryGenre: "", queryAuthor: author,
                isLatestFallback: false, isSearch: true, initialPage: initialPage
            )
        }
    }
}
