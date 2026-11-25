import Foundation

/// Builds a user `HabitProfile` from local shelf/history seeds,
/// search history, `RecommendProfileStore` feedback, and source affinity/VPN rules.
public enum UserHabitProfiler {
    public static let millisPerDay = 86_400_000.0
    public static let seedHalfLifeDays = 14.0
    public static let selectedGenreBoost = 1.8
    public static let clickRecordBoost = 0.85
    public static let searchHistoryBoost = 0.4
    public static let dislikeBasePenalty = 1.2
    public static let dislikeAuthorPenalty = 1.5
    public static let dislikeDecayWindowDays = 30.0
    public static let sourceWeightMin = 0.85
    public static let sourceWeightMax = 1.30
    public static let sourceWeightDefault = 1.0
    public static let vpnSourceMultiplier = 0.75

    public static func buildProfile(
        seeds: [SeedComic],
        searchHistory: [String],
        store: RecommendProfileStore?,
        enabledSourceIds: [String],
        vpnSourceIds: Set<String>,
        nowMillis: Int64? = nil
    ) -> HabitProfile {
        buildProfile(
            seeds: seeds,
            searchHistory: searchHistory,
            store: store,
            enabledSourceIds: enabledSourceIds,
            vpnSourcePredicate: { vpnSourceIds.contains($0) },
            nowMillis: nowMillis
        )
    }

    public static func buildProfile(
        seeds: [SeedComic],
        searchHistory: [String],
        store: RecommendProfileStore?,
        enabledSourceIds: [String],
        vpnSourcePredicate: (String) -> Bool,
        nowMillis: Int64? = nil
    ) -> HabitProfile {
        let now = (nowMillis ?? 0) > 0 ? nowMillis! : Int64(Date().timeIntervalSince1970 * 1000.0)
        let personalizationEnabled = store?.isPersonalizationEnabled ?? true

        if !personalizationEnabled {
            let neutralSources = computeSourceWeights(
                sourceUsage: [:],
                enabledSourceIds: enabledSourceIds,
                vpnSourcePredicate: vpnSourcePredicate
            )
            return HabitProfile.empty(sourceWeights: neutralSources)
        }

        var docFreq: [String: Int] = [:]
        var seedGenresList: [[String]] = []
        seedGenresList.reserveCapacity(seeds.count)
        for seed in seeds {
            var canonical = RecommendSourceClassifier.extractCanonicalGenres(seed.genres)
            if canonical.isEmpty {
                canonical = RecommendSourceClassifier.inferGenresFromText(
                    title: seed.title,
                    subtitle: seed.subtitle,
                    description: seed.description
                )
            }
            seedGenresList.append(canonical)
            for g in canonical {
                docFreq[g, default: 0] += 1
            }
        }

        var genreWeights: [String: Double] = [:]
        var authorWeights: [String: Double] = [:]
        var sourceUsage: [String: Double] = [:]
        var topSeedTitleByGenre: [String: String] = [:]
        var bestGenreSeedScore: [String: Double] = [:]
        var topSeedTitleByAuthor: [String: String] = [:]
        var bestAuthorSeedScore: [String: Double] = [:]
        var knownGenres = Set<String>()

        let totalSeeds = seeds.count
        for (i, seed) in seeds.enumerated() {
            let s = computeSeedWeight(seed, nowMillis: now)
            if !seed.sourceId.isEmpty {
                sourceUsage[seed.sourceId, default: 0.0] += s
            }

            let canonicalGenres = seedGenresList[i]
            if !canonicalGenres.isEmpty {
                let spreadNorm = 1.0 / sqrt(Double(canonicalGenres.count))
                for g in canonicalGenres {
                    let df = docFreq[g] ?? 1
                    let idf = log(1.0 + Double(totalSeeds + 1) / Double(df + 1))
                    let contrib = s * idf * spreadNorm
                    genreWeights[g, default: 0.0] += contrib
                    knownGenres.insert(g)

                    if !seed.title.isEmpty {
                        if bestGenreSeedScore[g] == nil || s > bestGenreSeedScore[g]! {
                            bestGenreSeedScore[g] = s
                            topSeedTitleByGenre[g] = seed.title
                        }
                    }
                }
            }

            for authorKey in splitAuthors(seed.author) {
                authorWeights[authorKey, default: 0.0] += s
                if !seed.title.isEmpty {
                    if bestAuthorSeedScore[authorKey] == nil || s > bestAuthorSeedScore[authorKey]! {
                        bestAuthorSeedScore[authorKey] = s
                        topSeedTitleByAuthor[authorKey] = seed.title
                    }
                }
            }
        }

        var preferredSelectedGenres = Set<String>()
        if let store {
            for rawGenre in store.getSelectedGenres() {
                let g = normalizeOrCleanGenre(rawGenre)
                if g.isEmpty { continue }
                preferredSelectedGenres.insert(g)
                knownGenres.insert(g)
                genreWeights[g, default: 0.0] += selectedGenreBoost
            }

            for click in store.getClickedRecords() {
                let deltaDays = click.clickedAt > 0
                    ? max(0.0, Double(now - click.clickedAt) / millisPerDay)
                    : 7.0
                let clickWeight = clickRecordBoost * exp(-deltaDays / seedHalfLifeDays)
                if !click.sourceId.isEmpty {
                    sourceUsage[click.sourceId, default: 0.0] += clickWeight
                }
                var clickGenres = RecommendSourceClassifier.extractCanonicalGenres(click.genres)
                if clickGenres.isEmpty {
                    clickGenres = RecommendSourceClassifier.inferGenresFromText(
                        title: click.title,
                        subtitle: "",
                        description: ""
                    )
                }
                if !clickGenres.isEmpty {
                    let spreadNorm = 1.0 / sqrt(Double(clickGenres.count))
                    for g in clickGenres {
                        genreWeights[g, default: 0.0] += clickWeight * spreadNorm
                        knownGenres.insert(g)
                    }
                }
                for authorKey in splitAuthors(click.author) {
                    authorWeights[authorKey, default: 0.0] += clickWeight
                }
            }
        }

        var searchedTerms = Set<String>()
        for query in searchHistory {
            let trimmed = SearchRules.trim(RecommendSourceClassifier.toSimplified(query))
            if trimmed.isEmpty { continue }
            searchedTerms.insert(trimmed.lowercased())

            for g in extractGenresFromSearch(trimmed) {
                genreWeights[g, default: 0.0] += searchHistoryBoost
                knownGenres.insert(g)
            }
        }

        // Apply 30-day decayed dislike penalties after accumulating positive signals.
        if let store {
            for dislike in store.listDisliked() {
                let deltaDays = dislike.timestamp > 0
                    ? max(0.0, Double(now - dislike.timestamp) / millisPerDay)
                    : 0.0
                if deltaDays >= dislikeDecayWindowDays { continue }
                let decay = max(0.0, 1.0 - deltaDays / dislikeDecayWindowDays)
                let genrePenalty = dislikeBasePenalty * decay
                for g in RecommendSourceClassifier.extractCanonicalGenres(dislike.genres) {
                    genreWeights[g, default: 0.0] -= genrePenalty
                }
                let authorPenalty = dislikeAuthorPenalty * decay
                for authorKey in splitAuthors(dislike.author) {
                    authorWeights[authorKey, default: 0.0] -= authorPenalty
                }
            }
        }

        let topGenres = sortedPositiveKeys(genreWeights)
        let topAuthors = sortedPositiveKeys(authorWeights)
        knownGenres.formIntersection(topGenres)

        let sourceWeights = computeSourceWeights(
            sourceUsage: sourceUsage,
            enabledSourceIds: enabledSourceIds,
            vpnSourcePredicate: vpnSourcePredicate
        )
        let coldStart = topGenres.isEmpty && topAuthors.isEmpty && seeds.isEmpty

        return HabitProfile(
            genreWeights: genreWeights,
            authorWeights: authorWeights,
            sourceWeights: sourceWeights,
            topSeedTitleByGenre: topSeedTitleByGenre,
            topSeedTitleByAuthor: topSeedTitleByAuthor,
            topGenres: topGenres,
            topAuthors: topAuthors,
            knownGenres: knownGenres,
            preferredSelectedGenres: preferredSelectedGenres,
            searchedTerms: searchedTerms,
            isColdStart: coldStart,
            seedCount: seeds.count
        )
    }

    public static func computeSeedWeight(_ seed: SeedComic?, nowMillis: Int64) -> Double {
        guard let seed else { return 0.0 }
        let deltaDays = seed.lastViewedAt > 0
            ? max(0.0, Double(nowMillis - seed.lastViewedAt) / millisPerDay)
            : seedHalfLifeDays
        let recency = exp(-deltaDays / seedHalfLifeDays)
        let readFactor = 1.0 + max(0.0, min(1.0, seed.readRatio))
        let favFactor = seed.favorite ? 1.5 : 1.0
        return recency * readFactor * favFactor
    }

    public static func computeSourceWeights(
        sourceUsage: [String: Double],
        enabledSourceIds: [String],
        vpnSourcePredicate: (String) -> Bool
    ) -> [String: Double] {
        var allSourceIds: [String] = []
        var seen = Set<String>()
        for id in enabledSourceIds {
            let trimmed = SearchRules.trim(id)
            if !trimmed.isEmpty && seen.insert(trimmed).inserted {
                allSourceIds.append(trimmed)
            }
        }
        for id in sourceUsage.keys {
            let trimmed = SearchRules.trim(id)
            if !trimmed.isEmpty && seen.insert(trimmed).inserted {
                allSourceIds.append(trimmed)
            }
        }

        let maxUsage = sourceUsage.values.max() ?? 0.0
        var result: [String: Double] = [:]
        for sourceId in allSourceIds {
            var base: Double
            if maxUsage <= 0.0 {
                base = sourceWeightDefault
            } else {
                let usage = sourceUsage[sourceId] ?? 0.0
                let ratio = max(0.0, min(1.0, usage / maxUsage))
                base = sourceWeightMin + (sourceWeightMax - sourceWeightMin) * ratio
            }
            base = max(sourceWeightMin, min(sourceWeightMax, base))
            if vpnSourcePredicate(sourceId) {
                base *= vpnSourceMultiplier
            }
            result[sourceId] = base
        }
        return result
    }

    public static func splitAuthors(_ rawAuthor: String?) -> [String] {
        guard let rawAuthor, !SearchRules.trim(rawAuthor).isEmpty else { return [] }
        let simplified = RecommendSourceClassifier.toSimplified(rawAuthor)
        guard !simplified.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: "/,、|｜;；")
        let parts = simplified.components(separatedBy: separators)
        var seen = Set<String>()
        var out: [String] = []
        for part in parts {
            let key = RecommendModels.normalizeAuthorKey(part)
            if !key.isEmpty && key != "佚名" && key != "未知" && seen.insert(key).inserted {
                out.append(key)
            }
        }
        return out
    }

    private static func extractGenresFromSearch(_ simplifiedQuery: String) -> [String] {
        let extracted = RecommendSourceClassifier.extractCanonicalGenres(text: simplifiedQuery)
        if !extracted.isEmpty { return extracted }
        var matched: [String] = []
        var seen = Set<String>()
        for canonical in RecommendSourceClassifier.canonicalGenres where simplifiedQuery.contains(canonical) {
            if seen.insert(canonical).inserted {
                matched.append(canonical)
            }
        }
        return matched
    }

    private static func normalizeOrCleanGenre(_ raw: String) -> String {
        let canonical = RecommendSourceClassifier.normalizeGenreTag(raw)
        if !canonical.isEmpty { return canonical }
        let simplified = RecommendSourceClassifier.toSimplified(raw)
        return RecommendSourceClassifier.isNoisyTag(simplified) ? "" : simplified
    }

    private static func sortedPositiveKeys(_ weights: [String: Double]) -> [String] {
        weights
            .filter { $0.value > 0.0 }
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return a.key < b.key
            }
            .map(\.key)
    }
}
