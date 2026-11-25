import Foundation

/// Pure Swift local recommendation engine.
/// Merges multi-source candidates, applies consensus hotness, hybrid personalization,
/// impression decay, strict channel quotas, and MMR diversity re-ranking.
public enum RecommendEngine {
    public static let mmrLambda = 0.72
    public static let diversityWindowSize = 6
    public static let maxSameGenreInWindow = 3
    public static let maxSameAuthorInWindow = 2
    public static let maxConsecutiveSameSource = 2
    public static let impressionDecayBase = 0.65
    public static let impressionDecayGrace = 2
    public static let expandedInitialMoreItems = 180
    public static let maxRecycleExclusionWindow = 120

    private static let log2Value = log(2.0)
    private static let millisPerDay: Int64 = 86_400_000

    private static let spotlightCycle: [RecommendChannel] = [
        .habitPersonalized,
        .systemConsensusHot,
        .sourceFeaturedCategory,
        .habitPersonalized,
        .explorationNewTaste,
        .latestUpdates,
        .habitPersonalized,
        .sourceFeaturedCategory,
        .systemConsensusHot,
        .habitPersonalized,
        .explorationNewTaste,
        .sourceFeaturedCategory
    ]

    private static let guessCycle: [RecommendChannel] = [
        .habitPersonalized,
        .systemConsensusHot,
        .sourceFeaturedCategory,
        .habitPersonalized,
        .explorationNewTaste,
        .latestUpdates,
        .habitPersonalized,
        .habitPersonalized,
        .systemConsensusHot,
        .sourceFeaturedCategory,
        .habitPersonalized,
        .explorationNewTaste
    ]

    private static let moreStreamCycle: [RecommendChannel] = [
        .habitPersonalized,
        .systemConsensusHot,
        .habitPersonalized,
        .sourceFeaturedCategory,
        .explorationNewTaste,
        .habitPersonalized,
        .latestUpdates,
        .sourceFeaturedCategory,
        .habitPersonalized,
        .systemConsensusHot,
        .explorationNewTaste,
        .habitPersonalized,
        .latestUpdates,
        .habitPersonalized,
        .explorationNewTaste,
        .sourceFeaturedCategory,
        .habitPersonalized,
        .systemConsensusHot,
        .habitPersonalized,
        .habitPersonalized
    ]

    public static func buildFeed(
        rawCandidates: [SourceCandidate],
        profile: HabitProfile?,
        store: RecommendProfileStore?,
        excludedExistingTitles: [String] = [],
        titleNormalizer: ((String) -> String)? = nil,
        blacklistTitlePredicate: ((String) -> Bool)? = nil,
        nowMillis: Int64? = nil
    ) -> RecommendFeed {
        buildFeedWithCaps(
            rawCandidates: rawCandidates,
            profile: profile,
            store: store,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            nowMillis: nowMillis,
            spotlightCap: RecommendConstants.maxSpotlightItems,
            guessCap: RecommendConstants.maxGuessItems,
            hotCap: RecommendConstants.maxHotRankItems,
            latestCap: RecommendConstants.maxLatestItems,
            moreCap: RecommendConstants.maxMoreStreamItems,
            expanded: false
        )
    }

    public static func buildExpandedFeed(
        rawCandidates: [SourceCandidate],
        profile: HabitProfile?,
        store: RecommendProfileStore?,
        excludedExistingTitles: [String] = [],
        titleNormalizer: ((String) -> String)? = nil,
        blacklistTitlePredicate: ((String) -> Bool)? = nil,
        nowMillis: Int64? = nil
    ) -> RecommendFeed {
        buildFeedWithCaps(
            rawCandidates: rawCandidates,
            profile: profile,
            store: store,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            nowMillis: nowMillis,
            spotlightCap: RecommendConstants.expandedSpotlightItems,
            guessCap: RecommendConstants.expandedGuessItems,
            hotCap: RecommendConstants.expandedHotRankItems,
            latestCap: RecommendConstants.expandedLatestItems,
            moreCap: expandedInitialMoreItems,
            expanded: true
        )
    }

    private static func buildFeedWithCaps(
        rawCandidates: [SourceCandidate],
        profile: HabitProfile?,
        store: RecommendProfileStore?,
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)?,
        blacklistTitlePredicate: ((String) -> Bool)?,
        nowMillis: Int64?,
        spotlightCap: Int,
        guessCap: Int,
        hotCap: Int,
        latestCap: Int,
        moreCap: Int,
        expanded: Bool
    ) -> RecommendFeed {
        let ctx = prepareScoringContext(
            rawCandidates: rawCandidates,
            profile: profile,
            store: store,
            alreadyExcludedNormTitles: nil,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            recentTailItems: nil,
            nowMillis: nowMillis,
            seedSalt: 0
        )
        if ctx.scoredEntries.isEmpty {
            return RecommendFeed.empty(
                generatedAt: ctx.now,
                isColdStart: ctx.isColdStart,
                personalizationActive: ctx.personalizationActive
            )
        }

        let hotRankItems = buildHotRankList(
            scoredEntries: ctx.scoredEntries,
            profile: ctx.profile,
            personalizationActive: ctx.personalizationActive,
            maxItems: hotCap
        )
        let latestItems = buildLatestList(
            scoredEntries: ctx.scoredEntries,
            profile: ctx.profile,
            personalizationActive: ctx.personalizationActive,
            maxItems: latestCap
        )

        let spotlightPicked = buildQuotaMmrList(
            allScored: ctx.scoredEntries,
            maxItems: spotlightCap,
            cycle: spotlightCycle,
            featuredWindowSize: RecommendConstants.spotlightBatchSize,
            maxFeaturedPerWindow: 1,
            distinctSourceCount: ctx.distinctSourceCount,
            deprioritizeTitles: [],
            diversityAnchors: []
        )
        let spotlightPool = materializeItems(
            spotlightPicked,
            profile: ctx.profile,
            personalizationActive: ctx.personalizationActive
        )

        let usedInSpotlight = Set(spotlightPicked.map(\.normTitle))
        let guessPicked = buildQuotaMmrList(
            allScored: ctx.scoredEntries,
            maxItems: guessCap,
            cycle: guessCycle,
            featuredWindowSize: RecommendConstants.guessBatchSize,
            maxFeaturedPerWindow: 2,
            distinctSourceCount: ctx.distinctSourceCount,
            deprioritizeTitles: usedInSpotlight,
            diversityAnchors: []
        )
        let guessPool = materializeItems(
            guessPicked,
            profile: ctx.profile,
            personalizationActive: ctx.personalizationActive
        )

        let streamPicked = buildQuotaMmrList(
            allScored: ctx.scoredEntries,
            maxItems: moreCap,
            cycle: moreStreamCycle,
            featuredWindowSize: 4,
            maxFeaturedPerWindow: 1,
            distinctSourceCount: ctx.distinctSourceCount,
            deprioritizeTitles: [],
            diversityAnchors: []
        )
        let moreStreamItems = materializeItems(
            streamPicked,
            profile: ctx.profile,
            personalizationActive: ctx.personalizationActive
        )

        let availableGenres = collectAvailableGenres(
            spotlight: spotlightPool,
            guess: guessPool,
            hot: hotRankItems,
            latest: latestItems,
            more: moreStreamItems,
            profile: ctx.profile
        )

        if expanded {
            return RecommendFeed.createExpanded(
                availableGenres: availableGenres,
                spotlightPool: spotlightPool,
                guessPool: guessPool,
                hotRankItems: hotRankItems,
                latestItems: latestItems,
                moreStreamItems: moreStreamItems,
                generatedAt: ctx.now,
                isColdStart: ctx.isColdStart,
                personalizationActive: ctx.personalizationActive
            )
        }
        return RecommendFeed(
            availableGenres: availableGenres,
            spotlightPool: spotlightPool,
            guessPool: guessPool,
            hotRankItems: hotRankItems,
            latestItems: latestItems,
            moreStreamItems: moreStreamItems,
            generatedAt: ctx.now,
            isColdStart: ctx.isColdStart,
            personalizationActive: ctx.personalizationActive
        )
    }

    public static func buildMoreBatch(
        rawCandidates: [SourceCandidate],
        profile: HabitProfile?,
        store: RecommendProfileStore?,
        alreadyShownNormTitles: Set<String>?,
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)?,
        blacklistTitlePredicate: ((String) -> Bool)?,
        batchSize: Int,
        recentTailItems: [RecommendItem]?,
        nowMillis: Int64?,
        cycleSeed: Int
    ) -> [RecommendItem] {
        guard !rawCandidates.isEmpty, batchSize > 0 else { return [] }
        let ctx = prepareScoringContext(
            rawCandidates: rawCandidates,
            profile: profile,
            store: store,
            alreadyExcludedNormTitles: alreadyShownNormTitles,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            recentTailItems: recentTailItems,
            nowMillis: nowMillis,
            seedSalt: cycleSeed
        )
        guard !ctx.scoredEntries.isEmpty else { return [] }
        let picked = buildQuotaMmrList(
            allScored: ctx.scoredEntries,
            maxItems: batchSize,
            cycle: moreStreamCycle,
            featuredWindowSize: 4,
            maxFeaturedPerWindow: 1,
            distinctSourceCount: ctx.distinctSourceCount,
            deprioritizeTitles: [],
            diversityAnchors: ctx.diversityAnchors
        )
        return materializeItems(picked, profile: ctx.profile, personalizationActive: ctx.personalizationActive)
    }

    public static func buildRecycledBatch(
        poolCandidates: [SourceCandidate],
        profile: HabitProfile?,
        store: RecommendProfileStore?,
        recentShownOrderNormTitles: [String]?,
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)?,
        blacklistTitlePredicate: ((String) -> Bool)?,
        batchSize: Int,
        recentTailItems: [RecommendItem]?,
        nowMillis: Int64?,
        recycleRound: Int
    ) -> [RecommendItem] {
        guard !poolCandidates.isEmpty, batchSize > 0 else { return [] }
        let ctx = prepareScoringContext(
            rawCandidates: poolCandidates,
            profile: profile,
            store: store,
            alreadyExcludedNormTitles: nil,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            recentTailItems: recentTailItems,
            nowMillis: nowMillis,
            seedSalt: recycleRound
        )
        guard !ctx.scoredEntries.isEmpty else { return [] }

        let totalEligible = ctx.scoredEntries.count
        let eligibleKeys = Set(ctx.scoredEntries.map(\.normTitle))
        var recentCounts: [String: Int] = [:]
        var softExcluded = Set<String>()

        if let recentShownOrderNormTitles, !recentShownOrderNormTitles.isEmpty {
            for t in recentShownOrderNormTitles where !t.isEmpty {
                recentCounts[t, default: 0] += 1
            }
            let softLimit = min(
                recentShownOrderNormTitles.count,
                min(maxRecycleExclusionWindow, max(0, totalEligible - batchSize))
            )
            var i = recentShownOrderNormTitles.count - 1
            while i >= 0 && softExcluded.count < softLimit {
                let t = recentShownOrderNormTitles[i]
                if eligibleKeys.contains(t) {
                    softExcluded.insert(t)
                }
                i -= 1
            }
        }

        var recyclePool: [ScoredEntry] = []
        recyclePool.reserveCapacity(totalEligible)
        for entry in ctx.scoredEntries {
            if softExcluded.contains(entry.normTitle) { continue }
            let recentCount = recentCounts[entry.normTitle] ?? 0
            let modulated = entry.score * (1.0 / (1.0 + Double(recentCount)))
            recyclePool.append(entry.withScore(modulated))
        }
        guard !recyclePool.isEmpty else { return [] }
        recyclePool.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.normTitle < b.normTitle
        }

        let picked = buildQuotaMmrList(
            allScored: recyclePool,
            maxItems: min(batchSize, recyclePool.count),
            cycle: moreStreamCycle,
            featuredWindowSize: 4,
            maxFeaturedPerWindow: 1,
            distinctSourceCount: ctx.distinctSourceCount,
            deprioritizeTitles: [],
            diversityAnchors: ctx.diversityAnchors
        )
        return materializeItems(picked, profile: ctx.profile, personalizationActive: ctx.personalizationActive)
    }

    public static func buildUpperReplenishBatch(
        poolCandidates: [SourceCandidate],
        profile: HabitProfile?,
        store: RecommendProfileStore?,
        existingUpperNormTitles: Set<String>?,
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)?,
        blacklistTitlePredicate: ((String) -> Bool)?,
        isSpotlight: Bool,
        batchSize: Int,
        nowMillis: Int64?,
        roundSeed: Int
    ) -> [RecommendItem] {
        guard !poolCandidates.isEmpty, batchSize > 0 else { return [] }
        let ctx = prepareScoringContext(
            rawCandidates: poolCandidates,
            profile: profile,
            store: store,
            alreadyExcludedNormTitles: existingUpperNormTitles,
            excludedExistingTitles: excludedExistingTitles,
            titleNormalizer: titleNormalizer,
            blacklistTitlePredicate: blacklistTitlePredicate,
            recentTailItems: nil,
            nowMillis: nowMillis,
            seedSalt: roundSeed
        )
        guard !ctx.scoredEntries.isEmpty else { return [] }
        let cycle = isSpotlight ? spotlightCycle : guessCycle
        let windowSize = isSpotlight ? RecommendConstants.spotlightBatchSize : RecommendConstants.guessBatchSize
        let maxFeatured = isSpotlight ? 1 : 2
        let picked = buildQuotaMmrList(
            allScored: ctx.scoredEntries,
            maxItems: batchSize,
            cycle: cycle,
            featuredWindowSize: windowSize,
            maxFeaturedPerWindow: maxFeatured,
            distinctSourceCount: ctx.distinctSourceCount,
            deprioritizeTitles: [],
            diversityAnchors: []
        )
        return materializeItems(picked, profile: ctx.profile, personalizationActive: ctx.personalizationActive)
    }

    public static func selectSpotlightBatch(_ feed: RecommendFeed?, batchIndex: Int) -> [RecommendItem] {
        guard let feed, !feed.spotlightPool.isEmpty else { return [] }
        return selectBatch(pool: feed.spotlightPool, batchSize: RecommendConstants.spotlightBatchSize, batchIndex: batchIndex)
    }

    public static func selectGuessBatch(_ feed: RecommendFeed?, batchIndex: Int) -> [RecommendItem] {
        guard let feed, !feed.guessPool.isEmpty else { return [] }
        return selectBatch(pool: feed.guessPool, batchSize: RecommendConstants.guessBatchSize, batchIndex: batchIndex)
    }

    private static func selectBatch(pool: [RecommendItem], batchSize: Int, batchIndex: Int) -> [RecommendItem] {
        let totalBatches = (pool.count + batchSize - 1) / batchSize
        guard totalBatches > 0 else { return [] }
        let idx = ((batchIndex % totalBatches) + totalBatches) % totalBatches
        let start = idx * batchSize
        let end = min(pool.count, start + batchSize)
        return Array(pool[start..<end])
    }

    public static func filterFeedByGenre(_ feed: RecommendFeed?, genre: String?) -> RecommendFeed {
        guard let feed else {
            return RecommendFeed.empty(generatedAt: 0, isColdStart: true, personalizationActive: true)
        }
        guard let genre, !SearchRules.trim(genre).isEmpty else { return feed }
        let trimmed = RecommendSourceClassifier.toSimplified(SearchRules.trim(genre))
        if trimmed == "全部" || trimmed.lowercased() == "all" { return feed }
        let canonical = RecommendSourceClassifier.normalizeGenreTag(trimmed)
        let target = canonical.isEmpty ? trimmed : canonical

        return RecommendFeed(
            availableGenres: feed.availableGenres,
            spotlightPool: filterItemsByGenre(feed.spotlightPool, targetGenre: target),
            guessPool: filterItemsByGenre(feed.guessPool, targetGenre: target),
            hotRankItems: filterItemsByGenre(feed.hotRankItems, targetGenre: target),
            latestItems: filterItemsByGenre(feed.latestItems, targetGenre: target),
            moreStreamItems: filterItemsByGenre(feed.moreStreamItems, targetGenre: target),
            generatedAt: feed.generatedAt,
            isColdStart: feed.isColdStart,
            personalizationActive: feed.personalizationActive
        )
    }

    private static func filterItemsByGenre(_ items: [RecommendItem], targetGenre: String) -> [RecommendItem] {
        items.filter { item in
            item.genres.contains { $0.caseInsensitiveCompare(targetGenre) == .orderedSame }
        }
    }

    // MARK: - Scoring & Merging Internals

    private static func prepareScoringContext(
        rawCandidates: [SourceCandidate],
        profile: HabitProfile?,
        store: RecommendProfileStore?,
        alreadyExcludedNormTitles: Set<String>?,
        excludedExistingTitles: [String],
        titleNormalizer: ((String) -> String)?,
        blacklistTitlePredicate: ((String) -> Bool)?,
        recentTailItems: [RecommendItem]?,
        nowMillis: Int64?,
        seedSalt: Int
    ) -> ScoringContext {
        let now = (nowMillis ?? 0) > 0 ? nowMillis! : Int64(Date().timeIntervalSince1970 * 1000.0)
        let epochDay = now / millisPerDay
        let normalizer = titleNormalizer ?? { RecommendModels.normalizeTitleFallback($0) }
        let personalizationActive = store?.isPersonalizationEnabled ?? true
        let safeProfile = profile ?? HabitProfile.empty()
        let isColdStart = !personalizationActive || safeProfile.isColdStart

        guard !rawCandidates.isEmpty else {
            return ScoringContext(
                now: now,
                profile: safeProfile,
                personalizationActive: personalizationActive,
                isColdStart: isColdStart,
                scoredEntries: [],
                diversityAnchors: [],
                distinctSourceCount: 0
            )
        }

        var excludedNorms = Set<String>()
        if let alreadyExcludedNormTitles {
            for norm in alreadyExcludedNormTitles where !norm.isEmpty {
                excludedNorms.insert(norm)
            }
        }
        for title in excludedExistingTitles {
            let norm = normalizer(title)
            if !norm.isEmpty {
                excludedNorms.insert(norm)
            }
        }

        var dislikedNorms = Set<String>()
        if let store {
            for disliked in store.listDisliked() {
                if !disliked.normalizedTitle.isEmpty {
                    dislikedNorms.insert(disliked.normalizedTitle)
                }
                if !disliked.displayTitle.isEmpty {
                    let norm = normalizer(disliked.displayTitle)
                    if !norm.isEmpty {
                        dislikedNorms.insert(norm)
                    }
                }
            }
        }

        let mergedEntries = mergeCandidates(
            rawCandidates: rawCandidates,
            profile: safeProfile,
            excludedNorms: excludedNorms,
            dislikedNorms: dislikedNorms,
            normalizer: normalizer,
            blacklistTitlePredicate: blacklistTitlePredicate
        )
        guard !mergedEntries.isEmpty else {
            return ScoringContext(
                now: now,
                profile: safeProfile,
                personalizationActive: personalizationActive,
                isColdStart: isColdStart,
                scoredEntries: [],
                diversityAnchors: [],
                distinctSourceCount: 0
            )
        }

        let scoredEntries = scoreEntries(
            entries: mergedEntries,
            profile: safeProfile,
            store: store,
            isColdStart: isColdStart,
            epochDay: epochDay,
            seedSalt: seedSalt
        )
        let anchors = toDiversityAnchors(recentTailItems: recentTailItems, normalizer: normalizer)

        var allDistinctSources = Set<String>()
        for e in scoredEntries where !e.primarySourceId.isEmpty {
            allDistinctSources.insert(e.primarySourceId)
        }
        for a in anchors where !a.primarySourceId.isEmpty {
            allDistinctSources.insert(a.primarySourceId)
        }

        return ScoringContext(
            now: now,
            profile: safeProfile,
            personalizationActive: personalizationActive,
            isColdStart: isColdStart,
            scoredEntries: scoredEntries,
            diversityAnchors: anchors,
            distinctSourceCount: allDistinctSources.count
        )
    }

    private static func toDiversityAnchors(
        recentTailItems: [RecommendItem]?,
        normalizer: (String) -> String
    ) -> [ScoredEntry] {
        guard let recentTailItems, !recentTailItems.isEmpty else { return [] }
        let windowKeep = max(1, diversityWindowSize - 1)
        let start = max(0, recentTailItems.count - windowKeep)
        var anchors: [ScoredEntry] = []
        anchors.reserveCapacity(recentTailItems.count - start)
        for i in start..<recentTailItems.count {
            let item = recentTailItems[i]
            let title = item.summary.title
            let norm = !item.normalizedTitle.isEmpty ? item.normalizedTitle : normalizer(title)
            let sourceId = item.allSourceIds.first ?? item.summary.sourceId
            let entry = MergedEntry(normTitle: norm)
            entry.genres = item.genres
            entry.author = item.author
            entry.representative = SourceCandidate(
                summary: item.summary,
                sourceId: sourceId,
                sourceName: item.sourceName,
                sourceChannel: item.channel,
                featuredCategoryLabel: item.featuredCategoryLabel,
                rankInList: 0,
                author: item.author,
                genres: item.genres
            )
            anchors.append(ScoredEntry(
                entry: entry,
                score: item.score,
                consensusHotness: 0.0,
                primaryChannel: item.channel,
                explorationEligible: false,
                authorMatched: false,
                genreMatched: false
            ))
        }
        return anchors
    }

    private static func mergeCandidates(
        rawCandidates: [SourceCandidate],
        profile: HabitProfile,
        excludedNorms: Set<String>,
        dislikedNorms: Set<String>,
        normalizer: (String) -> String,
        blacklistTitlePredicate: ((String) -> Bool)?
    ) -> [MergedEntry] {
        var mergedMap: [String: MergedEntry] = [:]
        var mergedOrder: [String] = []
        for candidate in rawCandidates {
            let rawTitle = candidate.summary.title
            if SearchRules.trim(rawTitle).isEmpty { continue }
            let normTitle = normalizer(rawTitle)
            if normTitle.isEmpty { continue }
            if excludedNorms.contains(normTitle) || dislikedNorms.contains(normTitle) { continue }
            if let pred = blacklistTitlePredicate, pred(normTitle) || pred(rawTitle) {
                continue
            }
            if let entry = mergedMap[normTitle] {
                entry.addCandidate(candidate, profile: profile)
            } else {
                let entry = MergedEntry(normTitle: normTitle)
                entry.addCandidate(candidate, profile: profile)
                mergedMap[normTitle] = entry
                mergedOrder.append(normTitle)
            }
        }
        return mergedOrder.compactMap { mergedMap[$0] }
    }

    private static func scoreEntries(
        entries: [MergedEntry],
        profile: HabitProfile,
        store: RecommendProfileStore?,
        isColdStart: Bool,
        epochDay: Int64,
        seedSalt: Int
    ) -> [ScoredEntry] {
        var scored: [ScoredEntry] = []
        scored.reserveCapacity(entries.count)
        for entry in entries {
            let consensus = entry.computeConsensusHotness(profile: profile)
            var habitAffinity = 0.0
            var matchedGenreCount = 0
            var authorMatched = false

            if !isColdStart {
                for g in entry.genres {
                    if let gw = profile.genreWeights[g] {
                        habitAffinity += gw
                        if gw > 0.0 { matchedGenreCount += 1 }
                    }
                }
                if !entry.genres.isEmpty {
                    habitAffinity /= sqrt(Double(entry.genres.count))
                }
                for authorKey in UserHabitProfiler.splitAuthors(entry.author) {
                    if let aw = profile.authorWeights[authorKey] {
                        habitAffinity += 1.8 * aw
                        if aw > 0.0 { authorMatched = true }
                    }
                }
                if !profile.searchedTerms.isEmpty, let rep = entry.representative {
                    let lowerTitle = RecommendSourceClassifier.toSimplified(rep.summary.title).lowercased()
                    let lowerAuthor = RecommendModels.normalizeAuthorKey(entry.author)
                    for term in profile.searchedTerms {
                        if term.utf16.count >= 2
                            && (lowerTitle.contains(term) || (!lowerAuthor.isEmpty && lowerAuthor.contains(term))) {
                            habitAffinity += 0.4
                            break
                        }
                    }
                }
            }

            let channelBoost = (entry.fromFeatured ? 0.25 : 0.0) + (entry.fromLatest ? 0.12 : 0.0)
            var base = isColdStart
                ? (consensus + channelBoost)
                : (0.55 * habitAffinity + 0.45 * consensus + channelBoost)
            base = max(0.001, base)

            var impressionDecay = 1.0
            if let store, let rec = store.getImpressionRecord(entry.normTitle) {
                if rec.clicks == 0 && rec.impressions > impressionDecayGrace {
                    impressionDecay = pow(impressionDecayBase, Double(rec.impressions - impressionDecayGrace))
                }
            }

            let dailyJitter = deterministicDailyJitter(epochDay: epochDay, seedSalt: seedSalt, normTitle: entry.normTitle)
            let finalScore = (base + dailyJitter) * impressionDecay

            var hasNegativeDislikedGenre = false
            var unseenGenreCount = 0
            if !isColdStart {
                for g in entry.genres {
                    if let gw = profile.genreWeights[g], gw < -0.5 {
                        hasNegativeDislikedGenre = true
                    }
                    if !profile.knownGenres.contains(g) {
                        unseenGenreCount += 1
                    }
                }
            }

            let explorationEligible = !isColdStart
                && !authorMatched
                && !hasNegativeDislikedGenre
                && !entry.genres.isEmpty
                && unseenGenreCount > 0
                && (entry.fromHot || entry.distinctSourceIds.count >= 2)
                && !entry.fromFeatured
                && consensus >= 0.35

            let primaryChannel: RecommendChannel
            if !isColdStart {
                if authorMatched || (matchedGenreCount > 0 && habitAffinity >= 0.75) {
                    primaryChannel = .habitPersonalized
                } else if entry.fromFeatured && entry.distinctSourceIds.count < 2 {
                    primaryChannel = .sourceFeaturedCategory
                } else if entry.fromLatest && !entry.fromHot && !entry.fromFeatured {
                    primaryChannel = .latestUpdates
                } else if explorationEligible {
                    primaryChannel = .explorationNewTaste
                } else {
                    primaryChannel = .systemConsensusHot
                }
            } else {
                if entry.fromFeatured && entry.distinctSourceIds.count < 2 {
                    primaryChannel = .sourceFeaturedCategory
                } else if entry.fromLatest && !entry.fromHot && !entry.fromFeatured {
                    primaryChannel = .latestUpdates
                } else {
                    primaryChannel = .systemConsensusHot
                }
            }

            scored.append(ScoredEntry(
                entry: entry,
                score: finalScore,
                consensusHotness: consensus,
                primaryChannel: primaryChannel,
                explorationEligible: explorationEligible,
                authorMatched: authorMatched,
                genreMatched: matchedGenreCount > 0
            ))
        }

        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.normTitle < b.normTitle
        }
        return scored
    }

    private static func buildHotRankList(
        scoredEntries: [ScoredEntry],
        profile: HabitProfile,
        personalizationActive: Bool,
        maxItems: Int
    ) -> [RecommendItem] {
        guard maxItems > 0 else { return [] }
        let sorted = scoredEntries.sorted { a, b in
            let multiA = a.entry.fromHot || a.entry.distinctSourceIds.count >= 2
            let multiB = b.entry.fromHot || b.entry.distinctSourceIds.count >= 2
            if multiA != multiB { return multiA && !multiB }
            if a.consensusHotness != b.consensusHotness { return a.consensusHotness > b.consensusHotness }
            return a.score > b.score
        }
        return sorted.prefix(maxItems).map { s in
            let ch: RecommendChannel = (s.entry.distinctSourceIds.count >= 2 || s.entry.fromHot)
                ? .systemConsensusHot
                : s.primaryChannel
            return toRecommendItem(scored: s, channel: ch, profile: profile, personalizationActive: personalizationActive)
        }
    }

    private static func buildLatestList(
        scoredEntries: [ScoredEntry],
        profile: HabitProfile,
        personalizationActive: Bool,
        maxItems: Int
    ) -> [RecommendItem] {
        guard maxItems > 0 else { return [] }
        let latestOnly = scoredEntries
            .filter { $0.entry.fromLatest }
            .sorted { a, b in
                if a.entry.bestLatestRank != b.entry.bestLatestRank {
                    return a.entry.bestLatestRank < b.entry.bestLatestRank
                }
                return a.score > b.score
            }
        return latestOnly.prefix(maxItems).map {
            toRecommendItem(scored: $0, channel: .latestUpdates, profile: profile, personalizationActive: personalizationActive)
        }
    }

    private static func buildQuotaMmrList(
        allScored: [ScoredEntry],
        maxItems: Int,
        cycle: [RecommendChannel],
        featuredWindowSize: Int,
        maxFeaturedPerWindow: Int,
        distinctSourceCount: Int,
        deprioritizeTitles: Set<String>,
        diversityAnchors: [ScoredEntry]
    ) -> [ScoredEntry] {
        guard !allScored.isEmpty, maxItems > 0 else { return [] }

        var preferredPool: [ScoredEntry] = []
        var fallbackPool: [ScoredEntry] = []
        for s in allScored {
            if deprioritizeTitles.contains(s.normTitle) {
                fallbackPool.append(s)
            } else {
                preferredPool.append(s)
            }
        }

        var nonFeaturedTotal = preferredPool.reduce(0) { $0 + ($1.primaryChannel != .sourceFeaturedCategory ? 1 : 0) }
        let includeFallback = preferredPool.count < maxItems || nonFeaturedTotal < (maxItems * 3) / 4
        if includeFallback {
            nonFeaturedTotal += fallbackPool.reduce(0) { $0 + ($1.primaryChannel != .sourceFeaturedCategory ? 1 : 0) }
        }

        var primaryRemaining = preferredPool
        var fallbackRemaining = includeFallback ? fallbackPool : []

        var maxScore = 1e-6
        for s in primaryRemaining where s.score > maxScore { maxScore = s.score }
        for s in fallbackRemaining where s.score > maxScore { maxScore = s.score }

        let maxFeaturedTotal: Int
        if nonFeaturedTotal == 0 {
            maxFeaturedTotal = maxItems
        } else if nonFeaturedTotal < 3 {
            maxFeaturedTotal = 1
        } else {
            maxFeaturedTotal = min(maxItems / 4, nonFeaturedTotal / 3)
        }

        var placed: [ScoredEntry] = []
        placed.reserveCapacity(min(maxItems, primaryRemaining.count + fallbackRemaining.count))
        var featuredPlacedCount = 0

        for slot in 0..<maxItems {
            if primaryRemaining.isEmpty && fallbackRemaining.isEmpty { break }
            var usePrimary = !primaryRemaining.isEmpty

            let nonFeaturedRemaining =
                primaryRemaining.reduce(0) { $0 + ($1.primaryChannel != .sourceFeaturedCategory ? 1 : 0) }
                + fallbackRemaining.reduce(0) { $0 + ($1.primaryChannel != .sourceFeaturedCategory ? 1 : 0) }

            let allowFeaturedHere: Bool
            if nonFeaturedTotal == 0 {
                allowFeaturedHere = true
            } else {
                let windowOk: Bool
                if featuredWindowSize == 4 && maxFeaturedPerWindow == 1 && nonFeaturedRemaining > 0 {
                    windowOk = !hasRecentFeaturedInSlidingWindow(
                        anchors: diversityAnchors,
                        placed: placed,
                        windowSize: featuredWindowSize,
                        nonFeaturedRemaining: nonFeaturedRemaining
                    )
                } else {
                    windowOk = countFeaturedInCurrentWindow(placed: placed, windowSize: featuredWindowSize) < maxFeaturedPerWindow
                        && !hasBoundaryFeaturedConflict(
                            anchors: diversityAnchors,
                            placed: placed,
                            featuredWindowSize: featuredWindowSize,
                            nonFeaturedRemaining: nonFeaturedRemaining
                        )
                }
                let hasBudget = featuredPlacedCount < maxFeaturedTotal && windowOk
                let canCompleteWindow = nonFeaturedRemaining > 0
                    || ((placed.count + 1) % featuredWindowSize == 0
                        && (featuredPlacedCount + 1) * 4 <= placed.count + 1)
                allowFeaturedHere = hasBudget && canCompleteWindow
            }

            if !allowFeaturedHere && nonFeaturedRemaining == 0 {
                break
            }

            let targetChannel = cycle[slot % cycle.count]
            var choice = pickBestMmrCandidate(
                remaining: usePrimary ? primaryRemaining : fallbackRemaining,
                anchors: diversityAnchors,
                placed: placed,
                targetChannel: targetChannel,
                allowFeaturedHere: allowFeaturedHere,
                nonFeaturedExist: nonFeaturedRemaining > 0,
                maxScore: maxScore,
                distinctSourceCount: distinctSourceCount
            )
            if choice == nil && usePrimary && !fallbackRemaining.isEmpty {
                usePrimary = false
                choice = pickBestMmrCandidate(
                    remaining: fallbackRemaining,
                    anchors: diversityAnchors,
                    placed: placed,
                    targetChannel: targetChannel,
                    allowFeaturedHere: allowFeaturedHere,
                    nonFeaturedExist: nonFeaturedRemaining > 0,
                    maxScore: maxScore,
                    distinctSourceCount: distinctSourceCount
                )
            }
            guard let picked = choice else { break }

            if usePrimary {
                primaryRemaining.remove(at: picked.index)
            } else {
                fallbackRemaining.remove(at: picked.index)
            }
            let finalized = picked.entry.withAssignedChannel(picked.assignedChannel)
            placed.append(finalized)
            if picked.assignedChannel == .sourceFeaturedCategory {
                featuredPlacedCount += 1
            }
        }
        return placed
    }

    private static func hasRecentFeaturedInSlidingWindow(
        anchors: [ScoredEntry],
        placed: [ScoredEntry],
        windowSize: Int,
        nonFeaturedRemaining: Int
    ) -> Bool {
        if nonFeaturedRemaining <= 0 || windowSize <= 1 { return false }
        let total = anchors.count + placed.count
        let start = max(0, total - (windowSize - 1))
        for i in start..<total {
            if getContextAt(anchors: anchors, placed: placed, index: i).primaryChannel == .sourceFeaturedCategory {
                return true
            }
        }
        return false
    }

    private static func hasBoundaryFeaturedConflict(
        anchors: [ScoredEntry],
        placed: [ScoredEntry],
        featuredWindowSize: Int,
        nonFeaturedRemaining: Int
    ) -> Bool {
        if nonFeaturedRemaining <= 0 || featuredWindowSize <= 1 || anchors.isEmpty { return false }
        let neededFromAnchors = (featuredWindowSize - 1) - placed.count
        if neededFromAnchors <= 0 { return false }
        let anchorStart = max(0, anchors.count - neededFromAnchors)
        for i in anchorStart..<anchors.count {
            if anchors[i].primaryChannel == .sourceFeaturedCategory {
                return true
            }
        }
        return false
    }

    private static func pickBestMmrCandidate(
        remaining: [ScoredEntry],
        anchors: [ScoredEntry],
        placed: [ScoredEntry],
        targetChannel: RecommendChannel,
        allowFeaturedHere: Bool,
        nonFeaturedExist: Bool,
        maxScore: Double,
        distinctSourceCount: Int
    ) -> PickedChoice? {
        if let pick = scanCandidates(
            remaining: remaining, anchors: anchors, placed: placed, targetChannel: targetChannel,
            requireChannelMatch: true, enforceWindowRules: true,
            allowFeaturedHere: allowFeaturedHere, nonFeaturedExist: nonFeaturedExist,
            maxScore: maxScore, distinctSourceCount: distinctSourceCount
        ) { return pick }
        if let pick = scanCandidates(
            remaining: remaining, anchors: anchors, placed: placed, targetChannel: targetChannel,
            requireChannelMatch: false, enforceWindowRules: true,
            allowFeaturedHere: allowFeaturedHere, nonFeaturedExist: nonFeaturedExist,
            maxScore: maxScore, distinctSourceCount: distinctSourceCount
        ) { return pick }
        if let pick = scanCandidates(
            remaining: remaining, anchors: anchors, placed: placed, targetChannel: targetChannel,
            requireChannelMatch: true, enforceWindowRules: false,
            allowFeaturedHere: allowFeaturedHere, nonFeaturedExist: nonFeaturedExist,
            maxScore: maxScore, distinctSourceCount: distinctSourceCount
        ) { return pick }
        return scanCandidates(
            remaining: remaining, anchors: anchors, placed: placed, targetChannel: targetChannel,
            requireChannelMatch: false, enforceWindowRules: false,
            allowFeaturedHere: allowFeaturedHere, nonFeaturedExist: nonFeaturedExist,
            maxScore: maxScore, distinctSourceCount: distinctSourceCount
        )
    }

    private static func scanCandidates(
        remaining: [ScoredEntry],
        anchors: [ScoredEntry],
        placed: [ScoredEntry],
        targetChannel: RecommendChannel,
        requireChannelMatch: Bool,
        enforceWindowRules: Bool,
        allowFeaturedHere: Bool,
        nonFeaturedExist: Bool,
        maxScore: Double,
        distinctSourceCount: Int
    ) -> PickedChoice? {
        var bestIndex = -1
        var bestEntry: ScoredEntry?
        var bestChannel: RecommendChannel?
        var bestMmr = -Double.infinity

        for (index, candidate) in remaining.enumerated() {
            guard let effectiveChannel = effectiveChannelForSlot(
                candidate: candidate,
                targetChannel: targetChannel,
                requireChannelMatch: requireChannelMatch,
                allowFeaturedHere: allowFeaturedHere
            ) else { continue }

            if effectiveChannel == .sourceFeaturedCategory && !allowFeaturedHere && nonFeaturedExist {
                continue
            }
            if enforceWindowRules && !passesWindowDiversity(
                candidate: candidate,
                anchors: anchors,
                placed: placed,
                distinctSourceCount: distinctSourceCount
            ) {
                continue
            }

            let relevance = candidate.score / maxScore
            let maxSim = maxSimilarityToRecentWindow(candidate: candidate, anchors: anchors, placed: placed)
            let mmr = mmrLambda * relevance - (1.0 - mmrLambda) * maxSim
            if bestEntry == nil || mmr > bestMmr {
                bestMmr = mmr
                bestIndex = index
                bestEntry = candidate
                bestChannel = effectiveChannel
            }
        }
        guard let bestEntry, let bestChannel, bestIndex >= 0 else { return nil }
        return PickedChoice(index: bestIndex, entry: bestEntry, assignedChannel: bestChannel)
    }

    private static func effectiveChannelForSlot(
        candidate: ScoredEntry,
        targetChannel: RecommendChannel,
        requireChannelMatch: Bool,
        allowFeaturedHere: Bool
    ) -> RecommendChannel? {
        if !requireChannelMatch {
            if candidate.primaryChannel == .sourceFeaturedCategory && !allowFeaturedHere {
                return nil
            }
            return candidate.primaryChannel
        }
        if candidate.primaryChannel == targetChannel {
            return targetChannel
        }
        if targetChannel == .explorationNewTaste && candidate.explorationEligible {
            return .explorationNewTaste
        }
        if targetChannel == .sourceFeaturedCategory && allowFeaturedHere && candidate.entry.fromFeatured && !candidate.authorMatched {
            return .sourceFeaturedCategory
        }
        if targetChannel == .latestUpdates && candidate.entry.fromLatest && !candidate.authorMatched {
            return .latestUpdates
        }
        if targetChannel == .systemConsensusHot && (candidate.entry.fromHot || candidate.entry.distinctSourceIds.count >= 2) {
            return .systemConsensusHot
        }
        return nil
    }

    private static func getContextAt(anchors: [ScoredEntry], placed: [ScoredEntry], index: Int) -> ScoredEntry {
        let anchorCount = anchors.count
        return index < anchorCount ? anchors[index] : placed[index - anchorCount]
    }

    private static func passesWindowDiversity(
        candidate: ScoredEntry,
        anchors: [ScoredEntry],
        placed: [ScoredEntry],
        distinctSourceCount: Int
    ) -> Bool {
        let size = anchors.count + placed.count
        if size == 0 { return true }

        let windowStart = max(0, size - (diversityWindowSize - 1))
        let candGenre = candidate.primaryGenre
        let candAuthor = candidate.normAuthor

        if !candGenre.isEmpty {
            var sameGenre = 0
            for i in windowStart..<size {
                if candGenre == getContextAt(anchors: anchors, placed: placed, index: i).primaryGenre {
                    sameGenre += 1
                }
            }
            if sameGenre >= maxSameGenreInWindow { return false }
        }

        if !candAuthor.isEmpty {
            var sameAuthor = 0
            for i in windowStart..<size {
                if candAuthor == getContextAt(anchors: anchors, placed: placed, index: i).normAuthor {
                    sameAuthor += 1
                }
            }
            if sameAuthor >= maxSameAuthorInWindow { return false }
        }

        if distinctSourceCount >= 3 && size >= maxConsecutiveSameSource {
            var allSame = true
            for i in (size - maxConsecutiveSameSource)..<size {
                if candidate.primarySourceId != getContextAt(anchors: anchors, placed: placed, index: i).primarySourceId {
                    allSame = false
                    break
                }
            }
            if allSame { return false }
        }
        return true
    }

    private static func maxSimilarityToRecentWindow(
        candidate: ScoredEntry,
        anchors: [ScoredEntry],
        placed: [ScoredEntry]
    ) -> Double {
        let size = anchors.count + placed.count
        if size == 0 { return 0.0 }
        let start = max(0, size - diversityWindowSize)
        var maxSim = 0.0
        for i in start..<size {
            let sim = pairSimilarity(candidate, getContextAt(anchors: anchors, placed: placed, index: i))
            if sim > maxSim { maxSim = sim }
        }
        return maxSim
    }

    private static func pairSimilarity(_ a: ScoredEntry, _ b: ScoredEntry) -> Double {
        var sim = 0.0
        if !a.primaryGenre.isEmpty && a.primaryGenre == b.primaryGenre {
            sim += 0.40
        } else if !a.entry.genres.isEmpty && !b.entry.genres.isEmpty {
            let setB = Set(b.entry.genres)
            var inter = 0
            for g in a.entry.genres where setB.contains(g) {
                inter += 1
            }
            if inter > 0 {
                let union = a.entry.genres.count + b.entry.genres.count - inter
                sim += 0.35 * (Double(inter) / Double(max(1, union)))
            }
        }
        if !a.normAuthor.isEmpty && a.normAuthor == b.normAuthor {
            sim += 0.40
        }
        if !a.primarySourceId.isEmpty && a.primarySourceId == b.primarySourceId {
            sim += 0.20
        }
        return min(1.0, sim)
    }

    private static func countFeaturedInCurrentWindow(placed: [ScoredEntry], windowSize: Int) -> Int {
        guard windowSize > 0, !placed.isEmpty else { return 0 }
        let pos = placed.count
        let batchStart = (pos / windowSize) * windowSize
        var count = 0
        for i in batchStart..<pos where placed[i].primaryChannel == .sourceFeaturedCategory {
            count += 1
        }
        return count
    }

    private static func materializeItems(
        _ picked: [ScoredEntry],
        profile: HabitProfile,
        personalizationActive: Bool
    ) -> [RecommendItem] {
        picked.map {
            toRecommendItem(
                scored: $0,
                channel: $0.primaryChannel,
                profile: profile,
                personalizationActive: personalizationActive
            )
        }
    }

    private static func toRecommendItem(
        scored: ScoredEntry,
        channel: RecommendChannel,
        profile: HabitProfile,
        personalizationActive: Bool
    ) -> RecommendItem {
        let entry = scored.entry
        let rep = entry.representative!
        let sourceName = rep.sourceName
        let featuredLabel = channel == .sourceFeaturedCategory
            ? (entry.featuredCategoryLabel.isEmpty ? "热门推荐" : entry.featuredCategoryLabel)
            : entry.featuredCategoryLabel
        let formatted = RecommendReasonFormatter.format(
            channel: channel,
            candidateGenres: entry.genres,
            author: entry.author,
            hotSourceCount: entry.distinctSourceIds.count,
            sourceName: sourceName,
            featuredCategoryLabel: featuredLabel,
            profile: profile,
            personalizationActive: personalizationActive
        )
        return RecommendItem(
            summary: rep.summary,
            normalizedTitle: entry.normTitle,
            score: scored.score,
            channel: channel,
            reason: formatted.reason,
            gridReason: formatted.gridReason,
            genres: entry.genres,
            author: entry.author,
            hotSourceCount: entry.distinctSourceIds.count,
            sourceName: sourceName,
            featuredCategoryLabel: entry.featuredCategoryLabel,
            allSourceIds: entry.distinctSourceIds,
            fallbackCoverUrls: entry.buildFallbackCoverUrls()
        )
    }

    private static func collectAvailableGenres(
        spotlight: [RecommendItem],
        guess: [RecommendItem],
        hot: [RecommendItem],
        latest: [RecommendItem],
        more: [RecommendItem],
        profile: HabitProfile?
    ) -> [String] {
        var freq: [String: Int] = [:]
        var keyOrder: [String] = []
        func count(_ items: [RecommendItem]) {
            for item in items {
                for g in item.genres {
                    if freq[g] == nil { keyOrder.append(g) }
                    freq[g, default: 0] += 1
                }
            }
        }
        count(spotlight)
        count(guess)
        count(hot)
        count(latest)
        count(more)
        guard !freq.isEmpty else { return [] }

        var ordered: [String] = []
        var seen = Set<String>()
        if let profile {
            for g in profile.topGenres where freq[g] != nil && seen.insert(g).inserted {
                ordered.append(g)
            }
        }
        let rest = keyOrder
            .filter { !seen.contains($0) }
            .sorted { (freq[$0] ?? 0) > (freq[$1] ?? 0) }
        ordered.append(contentsOf: rest)
        return ordered
    }

    static func deterministicDailyJitter(epochDay: Int64, seedSalt: Int, normTitle: String) -> Double {
        let dayU = UInt64(bitPattern: epochDay)
        let saltU = UInt64(bitPattern: Int64(seedSalt))
        let golden: UInt64 = 0x9e3779b97f4a7c15
        let daySalt = seedSalt == 0 ? dayU : (dayU ^ (saltU &* golden))
        var h: UInt64 = 0xcbf29ce484222325 ^ (daySalt &* golden)
        for u16 in normTitle.utf16 {
            h ^= UInt64(u16)
            h &*= 0x100000001b3
        }
        h ^= (h >> 33)
        h &*= 0xff51afd7ed558ccd
        h ^= (h >> 33)
        let positive = h & 0x7fffffffffffffff
        return Double(positive % 10000) / 10000.0 * 0.06
    }

    // MARK: - Helper Types

    private struct ScoringContext {
        let now: Int64
        let profile: HabitProfile
        let personalizationActive: Bool
        let isColdStart: Bool
        let scoredEntries: [ScoredEntry]
        let diversityAnchors: [ScoredEntry]
        let distinctSourceCount: Int
    }

    private struct CoverOption {
        let sourceId: String
        let coverUrl: String
        let host: String
        let priority: Double
    }

    private final class MergedEntry {
        let normTitle: String
        var bestRankBySource: [String: Int] = [:]
        var distinctSourceIds: [String] = []
        private var distinctSourceSet = Set<String>()
        private var genreSet = Set<String>()
        var genres: [String] = []
        var coverOptions: [CoverOption] = []
        var representative: SourceCandidate?
        var repPriority: Double = -1.0
        var author: String = ""
        var featuredCategoryLabel: String = ""
        var fromFeatured = false
        var fromHot = false
        var fromLatest = false
        var bestLatestRank = Int.max

        init(normTitle: String) {
            self.normTitle = normTitle
        }

        func addCandidate(_ c: SourceCandidate, profile: HabitProfile) {
            let sid = c.sourceId
            if !sid.isEmpty {
                if distinctSourceSet.insert(sid).inserted {
                    distinctSourceIds.append(sid)
                }
                if let prevRank = bestRankBySource[sid] {
                    if c.rankInList < prevRank { bestRankBySource[sid] = c.rankInList }
                } else {
                    bestRankBySource[sid] = c.rankInList
                }
            }

            switch c.sourceChannel {
            case .sourceFeaturedCategory:
                fromFeatured = true
                if featuredCategoryLabel.isEmpty && !c.featuredCategoryLabel.isEmpty {
                    featuredCategoryLabel = c.featuredCategoryLabel
                }
            case .systemConsensusHot:
                fromHot = true
            case .latestUpdates:
                fromLatest = true
                if c.rankInList < bestLatestRank {
                    bestLatestRank = c.rankInList
                }
            default:
                break
            }

            if author.isEmpty && !c.author.isEmpty {
                author = c.author.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var extracted: [String] = []
            extracted.append(contentsOf: RecommendSourceClassifier.extractCanonicalGenres(c.genres))
            extracted.append(contentsOf: RecommendSourceClassifier.extractCanonicalGenres(c.summary.tags))
            if !c.matchedQueryGenre.isEmpty {
                let g = RecommendSourceClassifier.normalizeGenreTag(c.matchedQueryGenre)
                if !g.isEmpty { extracted.append(g) }
            }
            if !extracted.isEmpty {
                for g in extracted where genreSet.insert(g).inserted {
                    genres.append(g)
                }
            }

            let sw = Self.sourceWeight(profile: profile, sourceId: sid)
            let trimmedCoverUrl = c.summary.coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasCover = !trimmedCoverUrl.isEmpty
            let priority = (hasCover ? 100.0 : 0.0) + sw * 10.0 - Double(c.rankInList) * 0.01
            if hasCover {
                coverOptions.append(CoverOption(
                    sourceId: sid.trimmingCharacters(in: .whitespacesAndNewlines),
                    coverUrl: trimmedCoverUrl,
                    host: Self.extractHost(trimmedCoverUrl),
                    priority: priority
                ))
            }
            if representative == nil || priority > repPriority {
                repPriority = priority
                representative = c
            }
        }

        func buildFallbackCoverUrls() -> [String] {
            guard !coverOptions.isEmpty else { return [] }
            let primaryUrl = representative?.summary.coverUrl.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let primarySourceId = representative?.sourceId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let primaryHost = Self.extractHost(primaryUrl)

            var candidates = coverOptions.filter { !$0.coverUrl.isEmpty && $0.coverUrl != primaryUrl }
            guard !candidates.isEmpty else { return [] }

            candidates.sort { a, b in
                let diffHostA = !primaryHost.isEmpty && !a.host.isEmpty && a.host != primaryHost
                let diffHostB = !primaryHost.isEmpty && !b.host.isEmpty && b.host != primaryHost
                if diffHostA != diffHostB { return diffHostA && !diffHostB }

                let diffSourceA = !primarySourceId.isEmpty && !a.sourceId.isEmpty && a.sourceId != primarySourceId
                let diffSourceB = !primarySourceId.isEmpty && !b.sourceId.isEmpty && b.sourceId != primarySourceId
                if diffSourceA != diffSourceB { return diffSourceA && !diffSourceB }

                return a.priority > b.priority
            }

            var picked: [String] = []
            var seenUrls = Set<String>()
            var seenHosts = Set<String>()
            if !primaryHost.isEmpty { seenHosts.insert(primaryHost) }

            for opt in candidates {
                if picked.count >= RecommendConstants.maxFallbackCoverUrls { break }
                if opt.host.isEmpty || seenHosts.contains(opt.host) { continue }
                if seenUrls.insert(opt.coverUrl).inserted {
                    seenHosts.insert(opt.host)
                    picked.append(opt.coverUrl)
                }
            }
            if picked.count < RecommendConstants.maxFallbackCoverUrls {
                for opt in candidates {
                    if picked.count >= RecommendConstants.maxFallbackCoverUrls { break }
                    if seenUrls.insert(opt.coverUrl).inserted {
                        picked.append(opt.coverUrl)
                    }
                }
            }
            return picked
        }

        func computeConsensusHotness(profile: HabitProfile) -> Double {
            guard !bestRankBySource.isEmpty else { return 0.0 }
            var sum = 0.0
            for (sid, rank) in bestRankBySource {
                let w = Self.sourceWeight(profile: profile, sourceId: sid)
                let denom = log(Double(rank) + 2.0) / RecommendEngine.log2Value
                sum += w / max(1.0, denom)
            }
            return sum
        }

        private static func sourceWeight(profile: HabitProfile, sourceId: String) -> Double {
            guard !sourceId.isEmpty else { return 1.0 }
            return profile.sourceWeights[sourceId] ?? 1.0
        }

        private static func extractHost(_ rawUrl: String) -> String {
            let trimmed = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            let clean: String
            if let hashIdx = trimmed.firstIndex(of: "#") {
                clean = String(trimmed[..<hashIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                clean = trimmed
            }
            guard !clean.isEmpty, let host = URLComponents(string: clean)?.host ?? URL(string: clean)?.host else {
                return ""
            }
            return host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private struct ScoredEntry {
        let entry: MergedEntry
        let normTitle: String
        let primaryGenre: String
        let normAuthor: String
        let primarySourceId: String
        let score: Double
        let consensusHotness: Double
        let primaryChannel: RecommendChannel
        let explorationEligible: Bool
        let authorMatched: Bool
        let genreMatched: Bool

        init(
            entry: MergedEntry,
            score: Double,
            consensusHotness: Double,
            primaryChannel: RecommendChannel,
            explorationEligible: Bool,
            authorMatched: Bool,
            genreMatched: Bool
        ) {
            self.entry = entry
            self.normTitle = entry.normTitle
            self.primaryGenre = entry.genres.first ?? ""
            self.normAuthor = UserHabitProfiler.splitAuthors(entry.author).first ?? ""
            self.primarySourceId = entry.representative?.sourceId ?? ""
            self.score = score
            self.consensusHotness = consensusHotness
            self.primaryChannel = primaryChannel
            self.explorationEligible = explorationEligible
            self.authorMatched = authorMatched
            self.genreMatched = genreMatched
        }

        func withAssignedChannel(_ nextChannel: RecommendChannel) -> ScoredEntry {
            if nextChannel == primaryChannel { return self }
            return ScoredEntry(
                entry: entry,
                score: score,
                consensusHotness: consensusHotness,
                primaryChannel: nextChannel,
                explorationEligible: explorationEligible,
                authorMatched: authorMatched,
                genreMatched: genreMatched
            )
        }

        func withScore(_ nextScore: Double) -> ScoredEntry {
            ScoredEntry(
                entry: entry,
                score: nextScore,
                consensusHotness: consensusHotness,
                primaryChannel: primaryChannel,
                explorationEligible: explorationEligible,
                authorMatched: authorMatched,
                genreMatched: genreMatched
            )
        }
    }

    private struct PickedChoice {
        let index: Int
        let entry: ScoredEntry
        let assignedChannel: RecommendChannel
    }
}
