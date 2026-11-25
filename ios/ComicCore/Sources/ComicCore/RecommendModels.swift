import Foundation

public enum RecommendConstants {
    public static let maxSpotlightItems = 12
    public static let spotlightBatchSize = 3
    public static let maxGuessItems = 24
    public static let guessBatchSize = 6
    public static let maxHotRankItems = 30
    public static let maxLatestItems = 14
    public static let maxMoreStreamItems = 120

    public static let expandedSpotlightItems = 36
    public static let expandedGuessItems = 72
    public static let expandedHotRankItems = 40
    public static let expandedLatestItems = 24
    public static let feedCacheMaxMoreItems = 160
    public static let maxReplenishedUpperItems = 120
    public static let maxFallbackCoverUrls = 2
}

public enum RecommendChannel: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case habitPersonalized = "habit_personalized"
    case systemConsensusHot = "system_consensus_hot"
    case sourceFeaturedCategory = "source_featured_category"
    case latestUpdates = "latest_updates"
    case explorationNewTaste = "exploration_new_taste"

    public var key: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .habitPersonalized: return "口味偏好"
        case .systemConsensusHot: return "多源热榜"
        case .sourceFeaturedCategory: return "站源热推"
        case .latestUpdates: return "最新更新"
        case .explorationNewTaste: return "换换口味"
        }
    }

    public static func fromKey(_ key: String?) -> RecommendChannel {
        guard let key else { return .systemConsensusHot }
        if let exact = RecommendChannel(rawValue: key) {
            return exact
        }
        switch key.uppercased() {
        case "HABIT_PERSONALIZED": return .habitPersonalized
        case "SYSTEM_CONSENSUS_HOT": return .systemConsensusHot
        case "SOURCE_FEATURED_CATEGORY": return .sourceFeaturedCategory
        case "LATEST_UPDATES": return .latestUpdates
        case "EXPLORATION_NEW_TASTE": return .explorationNewTaste
        default: return .systemConsensusHot
        }
    }
}

public struct SeedComic: Equatable, Sendable {
    public let comicId: String
    public let title: String
    public let normalizedTitle: String
    public let author: String
    public let genres: [String]
    public let sourceId: String
    public let favorite: Bool
    public let readRatio: Double
    public let lastViewedAt: Int64
    public let subtitle: String
    public let description: String

    public init(
        comicId: String,
        title: String,
        normalizedTitle: String = "",
        author: String = "",
        genres: [String] = [],
        sourceId: String = "",
        favorite: Bool = false,
        readRatio: Double = 0.0,
        lastViewedAt: Int64 = 0,
        subtitle: String = "",
        description: String = ""
    ) {
        self.comicId = comicId
        self.title = title
        self.normalizedTitle = normalizedTitle
        self.author = author
        self.genres = RecommendModels.cleanStringList(genres)
        self.sourceId = sourceId
        self.favorite = favorite
        let clampedRatio = readRatio.isNaN ? 0.0 : max(0.0, min(1.0, readRatio))
        self.readRatio = clampedRatio
        self.lastViewedAt = max(0, lastViewedAt)
        self.subtitle = subtitle
        self.description = description
    }
}

public struct SourceCandidate: Equatable, Sendable {
    public let summary: ComicSummary
    public let sourceId: String
    public let sourceName: String
    public let sourceChannel: RecommendChannel
    public let featuredCategoryLabel: String
    public let rankInList: Int
    public let author: String
    public let genres: [String]
    public let matchedQueryGenre: String
    public let matchedQueryAuthor: String
    public let fetchedAt: Int64

    public init(
        summary: ComicSummary,
        sourceId: String = "",
        sourceName: String = "",
        sourceChannel: RecommendChannel = .systemConsensusHot,
        featuredCategoryLabel: String = "",
        rankInList: Int = 0,
        author: String = "",
        genres: [String] = [],
        matchedQueryGenre: String = "",
        matchedQueryAuthor: String = "",
        fetchedAt: Int64 = 0
    ) {
        self.summary = summary
        let sid = !sourceId.isEmpty ? sourceId : summary.sourceId
        self.sourceId = sid
        self.sourceName = sourceName.isEmpty ? sid : sourceName
        self.sourceChannel = sourceChannel
        self.featuredCategoryLabel = featuredCategoryLabel
        self.rankInList = max(0, rankInList)
        self.author = author
        self.genres = RecommendModels.cleanStringList(genres)
        self.matchedQueryGenre = matchedQueryGenre
        self.matchedQueryAuthor = matchedQueryAuthor
        self.fetchedAt = max(0, fetchedAt)
    }

    public func toJSONObject() -> [String: Any] {
        [
            "summary": RecommendModels.summaryToJSONObject(summary),
            "sourceId": sourceId,
            "sourceName": sourceName,
            "sourceChannel": sourceChannel.key,
            "featuredCategoryLabel": featuredCategoryLabel,
            "rankInList": rankInList,
            "author": author,
            "genres": genres,
            "matchedQueryGenre": matchedQueryGenre,
            "matchedQueryAuthor": matchedQueryAuthor,
            "fetchedAt": NSNumber(value: fetchedAt)
        ]
    }

    public static func fromJSONObject(_ obj: [String: Any]?) -> SourceCandidate? {
        guard let obj,
              let sumObj = obj["summary"] as? [String: Any],
              let sum = RecommendModels.summaryFromJSONObject(sumObj) else {
            return nil
        }
        return SourceCandidate(
            summary: sum,
            sourceId: RecommendModels.optString(obj, "sourceId"),
            sourceName: RecommendModels.optString(obj, "sourceName"),
            sourceChannel: RecommendChannel.fromKey(RecommendModels.optString(obj, "sourceChannel")),
            featuredCategoryLabel: RecommendModels.optString(obj, "featuredCategoryLabel"),
            rankInList: RecommendModels.optInt(obj, "rankInList", defaultValue: 0),
            author: RecommendModels.optString(obj, "author"),
            genres: RecommendModels.stringList(obj["genres"]),
            matchedQueryGenre: RecommendModels.optString(obj, "matchedQueryGenre"),
            matchedQueryAuthor: RecommendModels.optString(obj, "matchedQueryAuthor"),
            fetchedAt: RecommendModels.optInt64(obj, "fetchedAt", defaultValue: 0)
        )
    }
}

public struct RecommendItem: Equatable, Sendable {
    public let summary: ComicSummary
    public let normalizedTitle: String
    public let score: Double
    public let channel: RecommendChannel
    public let reason: String
    public let gridReason: String
    public let genres: [String]
    public let author: String
    public let hotSourceCount: Int
    public let sourceName: String
    public let featuredCategoryLabel: String
    public let allSourceIds: [String]
    public let fallbackCoverUrls: [String]

    public init(
        summary: ComicSummary,
        normalizedTitle: String = "",
        score: Double = 0.0,
        channel: RecommendChannel = .systemConsensusHot,
        reason: String = "",
        gridReason: String = "",
        genres: [String] = [],
        author: String = "",
        hotSourceCount: Int = 0,
        sourceName: String = "",
        featuredCategoryLabel: String = "",
        allSourceIds: [String] = [],
        fallbackCoverUrls: [String] = []
    ) {
        self.summary = summary
        self.normalizedTitle = normalizedTitle
        self.score = score.isNaN ? 0.0 : score
        self.channel = channel
        self.reason = reason
        self.gridReason = gridReason
        self.genres = RecommendModels.cleanStringList(genres)
        self.author = author
        self.hotSourceCount = max(0, hotSourceCount)
        self.sourceName = sourceName
        self.featuredCategoryLabel = featuredCategoryLabel
        var sourceIds = RecommendModels.uniqueCleanStringList(allSourceIds)
        if sourceIds.isEmpty && !summary.sourceId.isEmpty {
            sourceIds = [summary.sourceId]
        }
        self.allSourceIds = sourceIds
        let primaryCover = summary.coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fallbackCoverUrls = RecommendModels.normalizeFallbackCoverUrls(primaryCover: primaryCover, urls: fallbackCoverUrls)
    }

    public func withChannelAndReasons(
        _ nextChannel: RecommendChannel,
        reason nextReason: String,
        gridReason nextGridReason: String
    ) -> RecommendItem {
        RecommendItem(
            summary: summary,
            normalizedTitle: normalizedTitle,
            score: score,
            channel: nextChannel,
            reason: nextReason,
            gridReason: nextGridReason,
            genres: genres,
            author: author,
            hotSourceCount: hotSourceCount,
            sourceName: sourceName,
            featuredCategoryLabel: featuredCategoryLabel,
            allSourceIds: allSourceIds,
            fallbackCoverUrls: fallbackCoverUrls
        )
    }

    public func toJSONObject() -> [String: Any] {
        [
            "summary": RecommendModels.summaryToJSONObject(summary),
            "normalizedTitle": normalizedTitle,
            "score": score,
            "channel": channel.key,
            "reason": reason,
            "gridReason": gridReason,
            "genres": genres,
            "author": author,
            "hotSourceCount": hotSourceCount,
            "sourceName": sourceName,
            "featuredCategoryLabel": featuredCategoryLabel,
            "allSourceIds": allSourceIds,
            "fallbackCoverUrls": fallbackCoverUrls
        ]
    }

    public static func fromJSONObject(_ obj: [String: Any]?) -> RecommendItem? {
        guard let obj,
              let sumObj = obj["summary"] as? [String: Any],
              let sum = RecommendModels.summaryFromJSONObject(sumObj) else {
            return nil
        }
        return RecommendItem(
            summary: sum,
            normalizedTitle: RecommendModels.optString(obj, "normalizedTitle"),
            score: RecommendModels.optDouble(obj, "score", defaultValue: 0.0),
            channel: RecommendChannel.fromKey(RecommendModels.optString(obj, "channel")),
            reason: RecommendModels.optString(obj, "reason"),
            gridReason: RecommendModels.optString(obj, "gridReason"),
            genres: RecommendModels.stringList(obj["genres"]),
            author: RecommendModels.optString(obj, "author"),
            hotSourceCount: RecommendModels.optInt(obj, "hotSourceCount", defaultValue: 1),
            sourceName: RecommendModels.optString(obj, "sourceName"),
            featuredCategoryLabel: RecommendModels.optString(obj, "featuredCategoryLabel"),
            allSourceIds: RecommendModels.stringList(obj["allSourceIds"]),
            fallbackCoverUrls: RecommendModels.stringList(obj["fallbackCoverUrls"])
        )
    }
}

public struct RecommendFeed: Equatable, Sendable {
    public let availableGenres: [String]
    public let spotlightPool: [RecommendItem]
    public let guessPool: [RecommendItem]
    public let hotRankItems: [RecommendItem]
    public let latestItems: [RecommendItem]
    public let moreStreamItems: [RecommendItem]
    public let generatedAt: Int64
    public let isColdStart: Bool
    public let personalizationActive: Bool

    public init(
        availableGenres: [String],
        spotlightPool: [RecommendItem],
        guessPool: [RecommendItem],
        hotRankItems: [RecommendItem],
        latestItems: [RecommendItem],
        moreStreamItems: [RecommendItem],
        generatedAt: Int64,
        isColdStart: Bool,
        personalizationActive: Bool
    ) {
        self.init(
            availableGenres: availableGenres,
            spotlightPool: spotlightPool,
            guessPool: guessPool,
            hotRankItems: hotRankItems,
            latestItems: latestItems,
            moreStreamItems: moreStreamItems,
            generatedAt: generatedAt,
            isColdStart: isColdStart,
            personalizationActive: personalizationActive,
            spotlightCap: RecommendConstants.maxSpotlightItems,
            guessCap: RecommendConstants.maxGuessItems,
            hotCap: RecommendConstants.maxHotRankItems,
            latestCap: RecommendConstants.maxLatestItems,
            moreCap: RecommendConstants.maxMoreStreamItems
        )
    }

    init(
        availableGenres: [String],
        spotlightPool: [RecommendItem],
        guessPool: [RecommendItem],
        hotRankItems: [RecommendItem],
        latestItems: [RecommendItem],
        moreStreamItems: [RecommendItem],
        generatedAt: Int64,
        isColdStart: Bool,
        personalizationActive: Bool,
        spotlightCap: Int,
        guessCap: Int,
        hotCap: Int,
        latestCap: Int,
        moreCap: Int
    ) {
        self.availableGenres = RecommendModels.uniqueCleanStringList(availableGenres)
        self.spotlightPool = RecommendModels.boundedItemList(spotlightPool, max: spotlightCap)
        self.guessPool = RecommendModels.boundedItemList(guessPool, max: guessCap)
        self.hotRankItems = RecommendModels.boundedItemList(hotRankItems, max: hotCap)
        self.latestItems = RecommendModels.boundedItemList(latestItems, max: latestCap)
        self.moreStreamItems = RecommendModels.boundedItemList(moreStreamItems, max: moreCap)
        self.generatedAt = max(0, generatedAt)
        self.isColdStart = isColdStart
        self.personalizationActive = personalizationActive
    }

    public static func createExpanded(
        availableGenres: [String],
        spotlightPool: [RecommendItem],
        guessPool: [RecommendItem],
        hotRankItems: [RecommendItem],
        latestItems: [RecommendItem],
        moreStreamItems: [RecommendItem],
        generatedAt: Int64,
        isColdStart: Bool,
        personalizationActive: Bool
    ) -> RecommendFeed {
        RecommendFeed(
            availableGenres: availableGenres,
            spotlightPool: spotlightPool,
            guessPool: guessPool,
            hotRankItems: hotRankItems,
            latestItems: latestItems,
            moreStreamItems: moreStreamItems,
            generatedAt: generatedAt,
            isColdStart: isColdStart,
            personalizationActive: personalizationActive,
            spotlightCap: RecommendConstants.expandedSpotlightItems,
            guessCap: RecommendConstants.expandedGuessItems,
            hotCap: RecommendConstants.expandedHotRankItems,
            latestCap: RecommendConstants.expandedLatestItems,
            moreCap: 0
        )
    }

    public static func empty(
        generatedAt: Int64,
        isColdStart: Bool,
        personalizationActive: Bool
    ) -> RecommendFeed {
        RecommendFeed(
            availableGenres: [],
            spotlightPool: [],
            guessPool: [],
            hotRankItems: [],
            latestItems: [],
            moreStreamItems: [],
            generatedAt: generatedAt,
            isColdStart: isColdStart,
            personalizationActive: personalizationActive
        )
    }

    public func withAppendedMoreItems(_ additions: [RecommendItem], allowRecycled: Bool = false) -> RecommendFeed {
        guard !additions.isEmpty else { return self }
        let merged = allowRecycled
            ? RecommendModels.appendDedupAdditionsOnly(existing: moreStreamItems, additions: additions)
            : RecommendModels.mergeUniqueItems(existing: moreStreamItems, additions: additions)
        if merged.count == moreStreamItems.count {
            return self
        }
        return RecommendFeed(
            availableGenres: availableGenres,
            spotlightPool: spotlightPool,
            guessPool: guessPool,
            hotRankItems: hotRankItems,
            latestItems: latestItems,
            moreStreamItems: merged,
            generatedAt: generatedAt,
            isColdStart: isColdStart,
            personalizationActive: personalizationActive,
            spotlightCap: max(RecommendConstants.expandedSpotlightItems, spotlightPool.count),
            guessCap: max(RecommendConstants.expandedGuessItems, guessPool.count),
            hotCap: max(RecommendConstants.expandedHotRankItems, hotRankItems.count),
            latestCap: max(RecommendConstants.expandedLatestItems, latestItems.count),
            moreCap: 0
        )
    }

    public func withAppendedUpperItems(isSpotlight: Bool, additions: [RecommendItem]) -> RecommendFeed {
        guard !additions.isEmpty else { return self }
        let base = isSpotlight ? spotlightPool : guessPool
        let merged = RecommendModels.mergeUniqueItems(existing: base, additions: additions)
        if merged.count == base.count {
            return self
        }
        let spotCap = isSpotlight
            ? max(RecommendConstants.maxReplenishedUpperItems, spotlightPool.count)
            : max(RecommendConstants.expandedSpotlightItems, spotlightPool.count)
        let guessCap = isSpotlight
            ? max(RecommendConstants.expandedGuessItems, guessPool.count)
            : max(RecommendConstants.maxReplenishedUpperItems, guessPool.count)
        return RecommendFeed(
            availableGenres: availableGenres,
            spotlightPool: isSpotlight ? merged : spotlightPool,
            guessPool: isSpotlight ? guessPool : merged,
            hotRankItems: hotRankItems,
            latestItems: latestItems,
            moreStreamItems: moreStreamItems,
            generatedAt: generatedAt,
            isColdStart: isColdStart,
            personalizationActive: personalizationActive,
            spotlightCap: spotCap,
            guessCap: guessCap,
            hotCap: max(RecommendConstants.expandedHotRankItems, hotRankItems.count),
            latestCap: max(RecommendConstants.expandedLatestItems, latestItems.count),
            moreCap: 0
        )
    }

    public var isEmpty: Bool {
        spotlightPool.isEmpty
            && guessPool.isEmpty
            && hotRankItems.isEmpty
            && latestItems.isEmpty
            && moreStreamItems.isEmpty
    }

    public func toJSONObject() -> [String: Any] {
        [
            "availableGenres": availableGenres,
            "spotlightPool": spotlightPool.prefix(RecommendConstants.expandedSpotlightItems).map { $0.toJSONObject() },
            "guessPool": guessPool.prefix(RecommendConstants.expandedGuessItems).map { $0.toJSONObject() },
            "hotRankItems": hotRankItems.prefix(RecommendConstants.expandedHotRankItems).map { $0.toJSONObject() },
            "latestItems": latestItems.prefix(RecommendConstants.expandedLatestItems).map { $0.toJSONObject() },
            "moreStreamItems": moreStreamItems.prefix(RecommendConstants.feedCacheMaxMoreItems).map { $0.toJSONObject() },
            "generatedAt": NSNumber(value: generatedAt),
            "isColdStart": isColdStart,
            "personalizationActive": personalizationActive
        ]
    }

    public static func fromJSONObject(_ obj: [String: Any]?) -> RecommendFeed? {
        guard let obj else { return nil }
        return createExpanded(
            availableGenres: RecommendModels.stringList(obj["availableGenres"]),
            spotlightPool: RecommendModels.itemsFromJSONArray(obj["spotlightPool"]),
            guessPool: RecommendModels.itemsFromJSONArray(obj["guessPool"]),
            hotRankItems: RecommendModels.itemsFromJSONArray(obj["hotRankItems"]),
            latestItems: RecommendModels.itemsFromJSONArray(obj["latestItems"]),
            moreStreamItems: RecommendModels.itemsFromJSONArray(obj["moreStreamItems"]),
            generatedAt: RecommendModels.optInt64(obj, "generatedAt", defaultValue: 0),
            isColdStart: RecommendModels.optBool(obj, "isColdStart", defaultValue: true),
            personalizationActive: RecommendModels.optBool(obj, "personalizationActive", defaultValue: true)
        )
    }
}

public struct FilterPlan: Equatable, Sendable {
    public let filters: [String: String]
    public let targetGroupKey: String
    public let matchedLabel: String
    public let matchedValue: String
    public let priorityScore: Int

    public init(
        filters: [String: String],
        targetGroupKey: String,
        matchedLabel: String,
        matchedValue: String,
        priorityScore: Int
    ) {
        self.filters = filters
        self.targetGroupKey = targetGroupKey
        self.matchedLabel = matchedLabel
        self.matchedValue = matchedValue
        self.priorityScore = priorityScore
    }
}

public struct DislikedRecord: Equatable, Sendable {
    public let normalizedTitle: String
    public let displayTitle: String
    public let genres: [String]
    public let author: String
    public let timestamp: Int64

    public init(
        normalizedTitle: String,
        displayTitle: String,
        genres: [String],
        author: String,
        timestamp: Int64
    ) {
        self.normalizedTitle = normalizedTitle
        self.displayTitle = displayTitle
        self.genres = RecommendModels.uniqueCleanStringList(genres)
        self.author = author
        self.timestamp = max(0, timestamp)
    }

    public func toJSONObject() -> [String: Any] {
        [
            "normalizedTitle": normalizedTitle,
            "displayTitle": displayTitle,
            "genres": genres,
            "author": author,
            "timestamp": NSNumber(value: timestamp)
        ]
    }

    public static func fromJSONObject(_ obj: [String: Any]?) -> DislikedRecord? {
        guard let obj else { return nil }
        let key = RecommendModels.optString(obj, "normalizedTitle").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return DislikedRecord(
            normalizedTitle: key,
            displayTitle: RecommendModels.optString(obj, "displayTitle"),
            genres: RecommendModels.stringList(obj["genres"]),
            author: RecommendModels.optString(obj, "author"),
            timestamp: RecommendModels.optInt64(obj, "timestamp", defaultValue: 0)
        )
    }
}

public struct ImpressionRecord: Equatable, Sendable {
    public let normalizedTitle: String
    public let impressions: Int
    public let clicks: Int
    public let lastImpressionAt: Int64
    public let lastClickAt: Int64

    public init(
        normalizedTitle: String,
        impressions: Int,
        clicks: Int,
        lastImpressionAt: Int64,
        lastClickAt: Int64
    ) {
        self.normalizedTitle = normalizedTitle
        self.impressions = max(0, impressions)
        self.clicks = max(0, clicks)
        self.lastImpressionAt = max(0, lastImpressionAt)
        self.lastClickAt = max(0, lastClickAt)
    }

    public func toJSONObject() -> [String: Any] {
        [
            "impressions": impressions,
            "clicks": clicks,
            "lastImpressionAt": NSNumber(value: lastImpressionAt),
            "lastClickAt": NSNumber(value: lastClickAt)
        ]
    }

    public static func fromJSONObject(normalizedTitle: String, obj: [String: Any]?) -> ImpressionRecord? {
        guard let obj, !normalizedTitle.isEmpty else { return nil }
        return ImpressionRecord(
            normalizedTitle: normalizedTitle,
            impressions: RecommendModels.optInt(obj, "impressions", defaultValue: 0),
            clicks: RecommendModels.optInt(obj, "clicks", defaultValue: 0),
            lastImpressionAt: RecommendModels.optInt64(obj, "lastImpressionAt", defaultValue: 0),
            lastClickAt: RecommendModels.optInt64(obj, "lastClickAt", defaultValue: 0)
        )
    }
}

public struct ClickedRecord: Equatable, Sendable {
    public let normalizedTitle: String
    public let title: String
    public let sourceId: String
    public let author: String
    public let genres: [String]
    public let clickedAt: Int64

    public init(
        normalizedTitle: String,
        title: String,
        sourceId: String,
        author: String,
        genres: [String],
        clickedAt: Int64
    ) {
        self.normalizedTitle = normalizedTitle
        self.title = title
        self.sourceId = sourceId
        self.author = author
        self.genres = RecommendModels.uniqueCleanStringList(genres)
        self.clickedAt = max(0, clickedAt)
    }

    public func toJSONObject() -> [String: Any] {
        [
            "normalizedTitle": normalizedTitle,
            "title": title,
            "sourceId": sourceId,
            "author": author,
            "genres": genres,
            "clickedAt": NSNumber(value: clickedAt)
        ]
    }

    public static func fromJSONObject(_ obj: [String: Any]?) -> ClickedRecord? {
        guard let obj else { return nil }
        let key = RecommendModels.optString(obj, "normalizedTitle").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return ClickedRecord(
            normalizedTitle: key,
            title: RecommendModels.optString(obj, "title"),
            sourceId: RecommendModels.optString(obj, "sourceId"),
            author: RecommendModels.optString(obj, "author"),
            genres: RecommendModels.stringList(obj["genres"]),
            clickedAt: RecommendModels.optInt64(obj, "clickedAt", defaultValue: 0)
        )
    }
}

public struct HabitProfile: Equatable, Sendable {
    public let genreWeights: [String: Double]
    public let authorWeights: [String: Double]
    public let sourceWeights: [String: Double]
    public let topSeedTitleByGenre: [String: String]
    public let topSeedTitleByAuthor: [String: String]
    public let topGenres: [String]
    public let topAuthors: [String]
    public let knownGenres: Set<String>
    public let preferredSelectedGenres: Set<String>
    public let searchedTerms: Set<String>
    public let isColdStart: Bool
    public let seedCount: Int

    public init(
        genreWeights: [String: Double],
        authorWeights: [String: Double],
        sourceWeights: [String: Double],
        topSeedTitleByGenre: [String: String],
        topSeedTitleByAuthor: [String: String],
        topGenres: [String],
        topAuthors: [String],
        knownGenres: Set<String>,
        preferredSelectedGenres: Set<String>,
        searchedTerms: Set<String>,
        isColdStart: Bool,
        seedCount: Int
    ) {
        self.genreWeights = genreWeights
        self.authorWeights = authorWeights
        self.sourceWeights = sourceWeights
        self.topSeedTitleByGenre = topSeedTitleByGenre
        self.topSeedTitleByAuthor = topSeedTitleByAuthor
        self.topGenres = RecommendModels.uniqueCleanStringList(topGenres)
        self.topAuthors = RecommendModels.uniqueCleanStringList(topAuthors)
        self.knownGenres = knownGenres
        self.preferredSelectedGenres = preferredSelectedGenres
        self.searchedTerms = searchedTerms
        self.isColdStart = isColdStart
        self.seedCount = max(0, seedCount)
    }

    public static func empty(sourceWeights: [String: Double] = [:]) -> HabitProfile {
        HabitProfile(
            genreWeights: [:],
            authorWeights: [:],
            sourceWeights: sourceWeights,
            topSeedTitleByGenre: [:],
            topSeedTitleByAuthor: [:],
            topGenres: [],
            topAuthors: [],
            knownGenres: [],
            preferredSelectedGenres: [],
            searchedTerms: [],
            isColdStart: true,
            seedCount: 0
        )
    }
}

public enum RecommendModels {
    /// Pure fallback title normalizer (used when caller does not supply an external normalizer).
    public static func normalizeTitleFallback(_ rawTitle: String?) -> String {
        guard let rawTitle else { return "" }
        let trimmed = SearchRules.trim(rawTitle)
        guard !trimmed.isEmpty else { return "" }
        var folded = String.UnicodeScalarView()
        for scalar in trimmed.unicodeScalars {
            var v = scalar.value
            if v >= 0xFF01 && v <= 0xFF5E {
                v -= 0xFEE0
            } else if v == 0x3000 {
                v = 0x20
            }
            if let s = UnicodeScalar(v) {
                for lc in String(s).lowercased().unicodeScalars {
                    let simp = RecommendSourceClassifier.toSimplifiedScalar(lc)
                    folded.append(simp)
                }
            }
        }
        var alnum = String.UnicodeScalarView()
        var nonWs = String.UnicodeScalarView()
        for scalar in folded {
            if !scalar.properties.isWhitespace {
                nonWs.append(scalar)
            }
            let ch = Character(scalar)
            if ch.isLetter || ch.isNumber {
                alnum.append(scalar)
            }
        }
        if !alnum.isEmpty {
            return String(alnum)
        }
        return String(nonWs)
    }

    public static func normalizeAuthorKey(_ author: String?) -> String {
        guard let author else { return "" }
        let simplified = SearchRules.trim(RecommendSourceClassifier.toSimplified(author))
        guard !simplified.isEmpty else { return "" }
        return simplified
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    static func cleanStringList(_ items: [String]) -> [String] {
        var out: [String] = []
        out.reserveCapacity(items.count)
        for item in items {
            let trimmed = SearchRules.trim(item)
            if !trimmed.isEmpty {
                out.append(trimmed)
            }
        }
        return out
    }

    static func uniqueCleanStringList(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(items.count)
        for item in items {
            let trimmed = SearchRules.trim(item)
            if !trimmed.isEmpty && seen.insert(trimmed).inserted {
                out.append(trimmed)
            }
        }
        return out
    }

    static func normalizeFallbackCoverUrls(primaryCover: String, urls: [String]) -> [String] {
        guard !urls.isEmpty else { return [] }
        let primary = primaryCover.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var out: [String] = []
        for raw in urls {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == primary { continue }
            if seen.insert(trimmed).inserted {
                out.append(trimmed)
                if out.count >= RecommendConstants.maxFallbackCoverUrls { break }
            }
        }
        return out
    }

    static func boundedItemList(_ items: [RecommendItem], max maxCount: Int) -> [RecommendItem] {
        guard !items.isEmpty else { return [] }
        if maxCount > 0 {
            return Array(items.prefix(maxCount))
        }
        return items
    }

    static func mergeUniqueItems(existing: [RecommendItem], additions: [RecommendItem]) -> [RecommendItem] {
        var out: [RecommendItem] = []
        out.reserveCapacity(existing.count + additions.count)
        var seenKeys = Set<String>()
        for item in existing {
            let key = itemDedupKey(item)
            if !key.isEmpty && !seenKeys.insert(key).inserted { continue }
            out.append(item)
        }
        for item in additions {
            let key = itemDedupKey(item)
            if !key.isEmpty && !seenKeys.insert(key).inserted { continue }
            out.append(item)
        }
        return out
    }

    static func appendDedupAdditionsOnly(existing: [RecommendItem], additions: [RecommendItem]) -> [RecommendItem] {
        var out = existing
        out.reserveCapacity(existing.count + additions.count)
        var addedKeys = Set<String>()
        for item in additions {
            let key = itemDedupKey(item)
            if !key.isEmpty && !addedKeys.insert(key).inserted { continue }
            out.append(item)
        }
        return out
    }

    static func itemDedupKey(_ item: RecommendItem) -> String {
        if !item.normalizedTitle.isEmpty { return item.normalizedTitle }
        return normalizeTitleFallback(item.summary.title)
    }

    static func summaryToJSONObject(_ s: ComicSummary) -> [String: Any] {
        [
            "sourceId": s.sourceId,
            "comicId": s.comicId,
            "title": s.title,
            "coverUrl": s.coverUrl,
            "subtitle": s.subtitle,
            "tags": s.tags,
            "latestChapter": s.latestChapter ?? ""
        ]
    }

    static func summaryFromJSONObject(_ obj: [String: Any]?) -> ComicSummary? {
        guard let obj else { return nil }
        let title = optString(obj, "title")
        let comicId = optString(obj, "comicId")
        guard !SearchRules.trim(title).isEmpty, !SearchRules.trim(comicId).isEmpty else {
            return nil
        }
        let latest = optString(obj, "latestChapter")
        return ComicSummary(
            sourceId: optString(obj, "sourceId"),
            comicId: comicId,
            title: title,
            coverUrl: optString(obj, "coverUrl"),
            subtitle: optString(obj, "subtitle"),
            tags: stringList(obj["tags"]),
            latestChapter: latest.isEmpty ? nil : latest
        )
    }

    static func itemsFromJSONArray(_ raw: Any?) -> [RecommendItem] {
        guard let arr = raw as? [Any] else { return [] }
        var out: [RecommendItem] = []
        out.reserveCapacity(arr.count)
        for elem in arr {
            if let dict = elem as? [String: Any], let item = RecommendItem.fromJSONObject(dict) {
                out.append(item)
            }
        }
        return out
    }

    static func stringList(_ raw: Any?) -> [String] {
        guard let arr = raw as? [Any] else { return [] }
        var out: [String] = []
        out.reserveCapacity(arr.count)
        for elem in arr {
            if let str = elem as? String, !str.isEmpty {
                out.append(str)
            }
        }
        return out
    }

    static func optString(_ obj: [String: Any], _ key: String) -> String {
        guard let val = obj[key], !(val is NSNull) else { return "" }
        if let str = val as? String { return str }
        if JsonValueHelper.isJsonBoolean(val) {
            return (val as? Bool ?? false) ? "true" : "false"
        }
        if let num = val as? NSNumber { return num.stringValue }
        return ""
    }

    static func optInt(_ obj: [String: Any], _ key: String, defaultValue: Int) -> Int {
        guard let val = obj[key], !(val is NSNull), !JsonValueHelper.isJsonBoolean(val) else { return defaultValue }
        if let num = val as? NSNumber { return num.intValue }
        if let i = val as? Int { return i }
        if let str = val as? String, let parsed = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return defaultValue
    }

    static func optInt64(_ obj: [String: Any], _ key: String, defaultValue: Int64) -> Int64 {
        guard let val = obj[key], !(val is NSNull), !JsonValueHelper.isJsonBoolean(val) else { return defaultValue }
        if let num = val as? NSNumber { return num.int64Value }
        if let i = val as? Int64 { return i }
        if let i = val as? Int { return Int64(i) }
        if let str = val as? String, let parsed = Int64(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return defaultValue
    }

    static func optDouble(_ obj: [String: Any], _ key: String, defaultValue: Double) -> Double {
        guard let val = obj[key], !(val is NSNull), !JsonValueHelper.isJsonBoolean(val) else { return defaultValue }
        if let num = val as? NSNumber {
            let d = num.doubleValue
            return d.isNaN ? defaultValue : d
        }
        if let d = val as? Double { return d.isNaN ? defaultValue : d }
        if let i = val as? Int { return Double(i) }
        if let str = val as? String, let parsed = Double(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed.isNaN ? defaultValue : parsed
        }
        return defaultValue
    }

    static func optBool(_ obj: [String: Any], _ key: String, defaultValue: Bool) -> Bool {
        guard let val = obj[key], !(val is NSNull) else { return defaultValue }
        if let b = val as? Bool { return b }
        if let str = val as? String {
            switch str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true": return true
            case "false": return false
            default: return defaultValue
            }
        }
        return defaultValue
    }
}
