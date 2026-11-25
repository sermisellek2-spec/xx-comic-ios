import Foundation

/// Pure Swift UI state policies extracted from Android `RecommendPageView.java`.
public enum RecommendPagePolicy {
    public static let defaultFooterError = "加载更多失败，点击重试"

    public enum FooterStateKind: Int, Equatable, Sendable {
        case ready = 0
        case loading = 1
        case error = 2
    }

    public final class FooterLoadState {
        public private(set) var state: FooterStateKind = .ready
        public private(set) var errorMessage: String = defaultFooterError
        public var callbackAcknowledged = false

        public init() {}

        public func canTriggerOnScroll(
            dy: Int,
            hasMoreItems: Bool,
            hasCallbacks: Bool,
            lastVisible: Int,
            totalCount: Int,
            spanCount: Int
        ) -> Bool {
            dy > 0
                && state == .ready
                && hasMoreItems
                && hasCallbacks
                && lastVisible >= 0
                && lastVisible >= totalCount - (spanCount * 3 + 2)
        }

        public func dispatchScrollLoad(
            onLoadMore: (() -> Void)?,
            onStateChanged: (() -> Void)?
        ) {
            callbackAcknowledged = false
            if updateState(.loading) {
                onStateChanged?()
            }
            onLoadMore?()
            if !callbackAcknowledged && state == .loading {
                if updateState(.ready) {
                    onStateChanged?()
                }
            }
        }

        @discardableResult
        public func setLoading(_ loading: Bool) -> Bool {
            callbackAcknowledged = true
            errorMessage = RecommendPagePolicy.defaultFooterError
            return updateState(loading ? .loading : .ready)
        }

        @discardableResult
        public func setError(_ message: String?) -> Bool {
            callbackAcknowledged = true
            errorMessage = (message == nil || message!.isEmpty) ? RecommendPagePolicy.defaultFooterError : message!
            return updateState(.error)
        }

        @discardableResult
        public func resetToReady() -> Bool {
            callbackAcknowledged = true
            errorMessage = RecommendPagePolicy.defaultFooterError
            return updateState(.ready)
        }

        public func resetWithoutNotify() {
            callbackAcknowledged = true
            state = .ready
            errorMessage = RecommendPagePolicy.defaultFooterError
        }

        @discardableResult
        public func updateState(_ nextState: FooterStateKind) -> Bool {
            if state == nextState && nextState != .error {
                return false
            }
            state = nextState
            return true
        }
    }

    public static func guessBatchSizeForColumns(_ columnCount: Int) -> Int {
        let cols = max(1, columnCount)
        if cols < 6 {
            let rows = (RecommendConstants.guessBatchSize + cols - 1) / cols
            return max(RecommendConstants.guessBatchSize, rows * cols)
        }
        return cols
    }

    public static func effectiveGuessBatchSize(poolSize: Int, columnCount: Int) -> Int {
        guard poolSize > 0 else { return 0 }
        let cols = max(1, columnCount)
        let desired = guessBatchSizeForColumns(cols)
        if poolSize >= desired { return desired }
        if poolSize >= cols { return (poolSize / cols) * cols }
        return poolSize
    }

    public static func selectAlignedGuessBatch(
        pool: [RecommendItem],
        batchIndex: Int,
        columnCount: Int
    ) -> [RecommendItem] {
        guard !pool.isEmpty else { return [] }
        let n = pool.count
        let cols = max(1, columnCount)
        let batchSize = effectiveGuessBatchSize(poolSize: n, columnCount: cols)
        guard batchSize > 0 else { return [] }

        let totalBatches = (n + batchSize - 1) / batchSize
        let idx = ((batchIndex % totalBatches) + totalBatches) % totalBatches
        let start = idx * batchSize
        let end = min(n, start + batchSize)

        var out: [RecommendItem] = []
        out.reserveCapacity(batchSize)
        var used = [Bool](repeating: false, count: n)
        for i in start..<end {
            out.append(pool[i])
            used[i] = true
        }
        if n >= cols && out.count % cols != 0 {
            let targetSize = min(n, max(batchSize, ((out.count + cols - 1) / cols) * cols))
            for i in 0..<n where out.count < targetSize {
                if !used[i] {
                    out.append(pool[i])
                    used[i] = true
                }
            }
        }
        return out
    }

    public static func stabilizeBatchIndexBeforePoolAppend(
        currentBatchIdx: Int,
        currentPoolSize: Int,
        batchSize: Int
    ) -> Int {
        guard currentPoolSize > 0, batchSize > 0 else { return 0 }
        let oldTotalBatches = (currentPoolSize + batchSize - 1) / batchSize
        guard oldTotalBatches > 0 else { return 0 }
        return ((currentBatchIdx % oldTotalBatches) + oldTotalBatches) % oldTotalBatches
    }

    public static func advanceBatchIndex(
        currentBatchIdx: Int,
        currentPoolSize: Int,
        batchSize: Int
    ) -> Int {
        guard currentPoolSize > 0, batchSize > 0 else { return 0 }
        let totalBatches = (currentPoolSize + batchSize - 1) / batchSize
        guard totalBatches > 0 else { return 0 }
        return (((currentBatchIdx + 1) % totalBatches) + totalBatches) % totalBatches
    }

    public static func clampScrollRestorePos(requestedPos: Int, itemCount: Int) -> Int {
        guard requestedPos >= 0, itemCount > 0 else { return -1 }
        return min(requestedPos, itemCount - 1)
    }

    public static func shouldUpdateContentWidth(nextWidthPx: Int, currentWidthPx: Int) -> Bool {
        nextWidthPx > 0 && abs(Int64(nextWidthPx) - Int64(currentWidthPx)) > 1
    }

    public static func computeSpotlightBatchMeasureSignature(
        batch: [RecommendItem]?,
        cardWidthPx: Int
    ) -> String {
        var sb = "w=\(cardWidthPx)|"
        guard let batch else {
            sb += "n=-1"
            return sb
        }
        sb += "n=\(batch.count)"
        for item in batch {
            sb += "|item:"
            appendSignatureField(&sb, item.summary.comicId)
            appendSignatureField(&sb, item.summary.title)
            appendSignatureField(&sb, item.author)
            appendSignatureField(&sb, item.summary.latestChapter)
            sb += "g=\(item.genres.count):"
            for genre in item.genres {
                appendSignatureField(&sb, genre)
            }
            appendSignatureField(&sb, item.reason)
            appendSignatureField(&sb, item.sourceName)
        }
        return sb
    }

    private static func appendSignatureField(_ sb: inout String, _ value: String?) {
        guard let value else {
            sb += "-1:"
            return
        }
        sb += "\(value.utf16.count):\(value);"
    }

    public static func extractBlacklistNormalizedKeys(_ blacklistStore: ComicBlacklistStore?) -> Set<String> {
        guard let blacklistStore, blacklistStore.size > 0 else { return [] }
        let entries = blacklistStore.listEntries()
        guard !entries.isEmpty else { return [] }
        var keys = Set<String>()
        for entry in entries where !entry.normalizedTitle.isEmpty {
            keys.insert(entry.normalizedTitle)
        }
        return keys
    }

    public static func filterListByBlacklist(
        _ list: [RecommendItem],
        blacklistStore: ComicBlacklistStore?
    ) -> [RecommendItem] {
        guard !list.isEmpty else { return [] }
        guard let blacklistStore, blacklistStore.size > 0 else { return list }
        return list.filter { !blacklistStore.isBlacklistedTitle($0.summary.title) }
    }

    public static func buildFilteredFeed(
        _ feed: RecommendFeed?,
        blacklistStore: ComicBlacklistStore?
    ) -> RecommendFeed? {
        guard let feed, let blacklistStore, blacklistStore.size > 0 else { return feed }
        return buildPreservingFeed(
            availableGenres: feed.availableGenres,
            spotlightPool: filterListByBlacklist(feed.spotlightPool, blacklistStore: blacklistStore),
            guessPool: filterListByBlacklist(feed.guessPool, blacklistStore: blacklistStore),
            hotRankItems: filterListByBlacklist(feed.hotRankItems, blacklistStore: blacklistStore),
            latestItems: filterListByBlacklist(feed.latestItems, blacklistStore: blacklistStore),
            moreStreamItems: filterListByBlacklist(feed.moreStreamItems, blacklistStore: blacklistStore),
            generatedAt: feed.generatedAt,
            isColdStart: feed.isColdStart,
            personalizationActive: feed.personalizationActive
        )
    }

    private static func buildPreservingFeed(
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
        var base = RecommendFeed.createExpanded(
            availableGenres: availableGenres,
            spotlightPool: spotlightPool,
            guessPool: guessPool,
            hotRankItems: hotRankItems,
            latestItems: latestItems,
            moreStreamItems: moreStreamItems,
            generatedAt: generatedAt,
            isColdStart: isColdStart,
            personalizationActive: personalizationActive
        )
        if spotlightPool.count > RecommendConstants.expandedSpotlightItems {
            base = base.withAppendedUpperItems(
                isSpotlight: true,
                additions: Array(spotlightPool.dropFirst(RecommendConstants.expandedSpotlightItems))
            )
        }
        if guessPool.count > RecommendConstants.expandedGuessItems {
            base = base.withAppendedUpperItems(
                isSpotlight: false,
                additions: Array(guessPool.dropFirst(RecommendConstants.expandedGuessItems))
            )
        }
        return base
    }
}

public final class BlacklistFeedFilterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var lastFilterInputFeed: RecommendFeed?
    private var lastFilterBlacklistVersion = Set<String>()
    private var lastFilteredFeedResult: RecommendFeed?

    public init() {}

    public func invalidate() {
        lock.lock()
        lastFilterInputFeed = nil
        lastFilterBlacklistVersion.removeAll()
        lastFilteredFeedResult = nil
        lock.unlock()
    }

    public func filter(_ feed: RecommendFeed?, blacklistStore: ComicBlacklistStore?) -> RecommendFeed? {
        guard let feed, let blacklistStore, blacklistStore.size > 0 else { return feed }
        let currentBlacklistKeys = RecommendPagePolicy.extractBlacklistNormalizedKeys(blacklistStore)
        guard !currentBlacklistKeys.isEmpty else { return feed }

        lock.lock()
        if let lastInput = lastFilterInputFeed,
           lastInput == feed,
           let cached = lastFilteredFeedResult,
           currentBlacklistKeys == lastFilterBlacklistVersion {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let filtered = RecommendPagePolicy.buildFilteredFeed(feed, blacklistStore: blacklistStore)

        lock.lock()
        lastFilterInputFeed = feed
        lastFilterBlacklistVersion = currentBlacklistKeys
        lastFilteredFeedResult = filtered
        lock.unlock()

        return filtered
    }
}
