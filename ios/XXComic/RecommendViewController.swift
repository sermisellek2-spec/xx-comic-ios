import UIKit
import ComicCore

@MainActor
final class RecommendViewController: UIViewController {
    private enum SectionItem {
        case state(RecommendStateCell.Mode)
        case spotlight([RecommendItem])
        case guess([RecommendItem])
        case hotRank([RecommendItem])
        case latest([RecommendItem])
        case moreHeader
        case moreCard(RecommendItem)
        case footer(RecommendPagePolicy.FooterStateKind, String)
    }

    private let environment: AppEnvironment
    var onOpenDetail: ((ComicSummary) -> Void)?
    var onManageSources: (() -> Void)?

    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
    private let refreshControl = UIRefreshControl()
    private let backToTopButton = BackToTopButton()

    private var rawFeed: RecommendFeed?
    private var filteredFeed: RecommendFeed?
    private var sectionItems: [SectionItem] = []

    private var spotlightBatchIndex = 0
    private var guessBatchIndex = 0
    private var guessPoolSizeLast = 0
    private var isActivated = false
    private var isLoadingInitial = false
    private var isRefreshingUpper = false
    private var isReplenishingUpper = false
    private var hasPendingDirtyRefresh = false
    private var lastLayoutWidth: CGFloat = 0
    private var initialLoadErrorMessage: String?

    private var harvestGeneration = UUID()
    private var harvestTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var streamPager: RecommendStreamPager?
    private var streamGeneration = UUID()

    private let footerState = RecommendPagePolicy.FooterLoadState()
    private let blacklistFilterCache = BlacklistFeedFilterCache()
    private var lastScrollOffsetY: CGFloat = 0
    private weak var activeRankSheet: RecommendRankSheetController?
    private var observers: [NSObjectProtocol] = []

    var currentAvailableGenres: [String] {
        filteredFeed?.availableGenres ?? rawFeed?.availableGenres ?? []
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    deinit {
        harvestTask?.cancel()
        streamTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        setupCollectionView()
        setupBackToTop()
        setupObservers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        if width > 0 && abs(width - lastLayoutWidth) > 1 {
            lastLayoutWidth = width
            flowLayout.invalidateLayout()
            if !sectionItems.isEmpty {
                rebuildSectionItems()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isActivated && hasPendingDirtyRefresh {
            hasPendingDirtyRefresh = false
            reloadFromScratch(forceRefresh: true, showSkeletonIfEmpty: false)
        }
    }

    // MARK: - Public Integration API

    func activateIfNeeded() {
        isActivated = true
        if rawFeed == nil && !isLoadingInitial {
            loadInitialFeed()
        } else if hasPendingDirtyRefresh {
            hasPendingDirtyRefresh = false
            reloadFromScratch(forceRefresh: true, showSkeletonIfEmpty: false)
        }
    }

    func applyPrewarmedFeed(_ prewarmed: RecommendFeed) {
        guard !prewarmed.isEmpty else { return }
        if rawFeed == nil {
            rawFeed = prewarmed
            blacklistFilterCache.invalidate()
            applyBlacklistFilterAndRebuild()
            ensureStreamPager()
        }
    }

    func scrollToTop(animated: Bool = true) {
        if animated {
            BackToTopButton.smoothScrollToTop(collectionView)
        } else {
            collectionView.setContentOffset(.zero, animated: false)
        }
    }

    func openPrefSheet() {
        let sheet = RecommendPrefSheetController(
            environment: environment,
            availableGenres: currentAvailableGenres
        )
        present(sheet, animated: false)
    }

    // MARK: - Setup

    private func setupCollectionView() {
        flowLayout.minimumInteritemSpacing = DiscoveryLayoutMetrics.interItemSpacing
        flowLayout.minimumLineSpacing = DiscoveryLayoutMetrics.rowSpacing
        flowLayout.sectionInset = UIEdgeInsets(
            top: 10,
            left: DiscoveryLayoutMetrics.horizontalPadding,
            bottom: 24,
            right: DiscoveryLayoutMetrics.horizontalPadding
        )

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "recommend.collection"
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        collectionView.register(RecommendStateCell.self, forCellWithReuseIdentifier: RecommendStateCell.reuseId)
        collectionView.register(RecommendSpotlightCell.self, forCellWithReuseIdentifier: RecommendSpotlightCell.reuseId)
        collectionView.register(RecommendGuessCell.self, forCellWithReuseIdentifier: RecommendGuessCell.reuseId)
        collectionView.register(RecommendHotCell.self, forCellWithReuseIdentifier: RecommendHotCell.reuseId)
        collectionView.register(RecommendLatestCell.self, forCellWithReuseIdentifier: RecommendLatestCell.reuseId)
        collectionView.register(RecommendMoreHeaderCell.self, forCellWithReuseIdentifier: RecommendMoreHeaderCell.reuseId)
        collectionView.register(RecommendMoreCardCell.self, forCellWithReuseIdentifier: RecommendMoreCardCell.reuseId)
        collectionView.register(RecommendFooterCell.self, forCellWithReuseIdentifier: RecommendFooterCell.reuseId)

        refreshControl.tintColor = Palette.accent
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupBackToTop() {
        backToTopButton.translatesAutoresizingMaskIntoConstraints = false
        backToTopButton.onTap = { [weak self] in
            guard let self else { return }
            BackToTopButton.smoothScrollToTop(self.collectionView)
        }
        view.addSubview(backToTopButton)
        NSLayoutConstraint.activate([
            backToTopButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            backToTopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18)
        ])
    }

    private func setupObservers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AppEnvironment.blacklistChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleBlacklistChanged()
            }
        })
        observers.append(nc.addObserver(forName: AppEnvironment.recommendProfileChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromScratch(forceRefresh: true, showSkeletonIfEmpty: true)
            }
        })
        observers.append(nc.addObserver(forName: AppEnvironment.sourcesChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isActivated {
                    self.reloadFromScratch(forceRefresh: true, showSkeletonIfEmpty: true)
                } else {
                    self.hasPendingDirtyRefresh = true
                    self.rawFeed = nil
                    self.filteredFeed = nil
                    self.streamPager = nil
                }
            }
        })
        observers.append(nc.addObserver(forName: AppEnvironment.libraryChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.hasPendingDirtyRefresh = false
            }
        })
    }

    // MARK: - Data Pipeline

    static func buildContext(environment: AppEnvironment) -> (
        sources: [any ComicSource],
        seeds: [SeedComic],
        searchHistory: [String],
        vpnSourceIds: Set<String>,
        excludedTitles: [String]
    ) {
        let sources = environment.discoverySources
        let vpnIds = Set(sources.filter { environment.requiresVpn(sourceId: $0.id) }.map(\.id))

        var seeds: [SeedComic] = []
        var seenSeedKeys = Set<String>()
        let allEntries = environment.visibleFavorites() + environment.visibleHistory()
        for entry in allEntries {
            let s = entry.summary
            let key = "\(s.sourceId)\n\(s.comicId)"
            guard seenSeedKeys.insert(key).inserted else { continue }
            let norm = ComicTitleNormalizer.normalize(s.title)
            var readRatio = 0.0
            if let reading = entry.reading {
                if reading.position.atEnd {
                    readRatio = 1.0
                } else if let detail = environment.cachedDetail(sourceId: s.sourceId, comicId: s.comicId), !detail.chapters.isEmpty {
                    readRatio = min(1.0, Double(reading.chapterIndex + 1) / Double(detail.chapters.count))
                } else {
                    readRatio = reading.chapterIndex > 0 ? 0.5 : (reading.position.imageIndex > 0 ? 0.25 : 0.1)
                }
            }
            let viewedMs = Int64((entry.reading?.updatedAt ?? entry.favoriteAt ?? 0) * 1000)
            seeds.append(SeedComic(
                comicId: s.comicId,
                title: s.title,
                normalizedTitle: norm,
                author: "",
                genres: s.tags,
                sourceId: s.sourceId,
                favorite: entry.isFavorite,
                readRatio: readRatio,
                lastViewedAt: viewedMs,
                subtitle: s.subtitle,
                description: ""
            ))
        }

        let excludedTitles = allEntries.map(\.summary.title)
        let searchHistory = environment.defaults.stringArray(forKey: "global.search.history") ?? []
        return (sources, seeds, searchHistory, vpnIds, excludedTitles)
    }

    private func loadInitialFeed() {
        let enabledSources = environment.discoverySources
        if enabledSources.isEmpty {
            rawFeed = nil
            filteredFeed = nil
            rebuildSectionItems()
            return
        }

        let context = Self.buildContext(environment: environment)
        let allowedIds = Set(context.sources.map(\.id))
        let blacklistStore = environment.blacklistStore
        let profileStore = environment.recommendProfileStore

        if let cached = environment.recommendHarvester.loadCachedFeedFiltered(
            store: profileStore,
            excludedExistingTitles: context.excludedTitles,
            blacklistTitlePredicate: { blacklistStore.isBlacklistedTitle($0) },
            titleNormalizer: { ComicTitleNormalizer.normalize($0) },
            allowedSourceIds: allowedIds
        ), !cached.isEmpty {
            rawFeed = cached
            blacklistFilterCache.invalidate()
            applyBlacklistFilterAndRebuild()
            ensureStreamPager()

            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let isStale = nowMs - cached.generatedAt > 900_000
            if isStale {
                reloadFromScratch(forceRefresh: false, showSkeletonIfEmpty: false)
            }
            return
        }

        reloadFromScratch(forceRefresh: false, showSkeletonIfEmpty: true)
    }

    private func reloadFromScratch(forceRefresh: Bool, showSkeletonIfEmpty: Bool) {
        let enabledSources = environment.discoverySources
        if enabledSources.isEmpty {
            harvestTask?.cancel()
            streamTask?.cancel()
            streamPager = nil
            rawFeed = nil
            filteredFeed = nil
            isLoadingInitial = false
            isRefreshingUpper = false
            refreshControl.endRefreshing()
            rebuildSectionItems()
            return
        }

        harvestTask?.cancel()
        streamTask?.cancel()
        streamPager = nil
        footerState.resetWithoutNotify()
        initialLoadErrorMessage = nil

        if showSkeletonIfEmpty || rawFeed == nil {
            isLoadingInitial = true
            spotlightBatchIndex = 0
            guessBatchIndex = 0
            guessPoolSizeLast = 0
            rebuildSectionItems()
        } else {
            isRefreshingUpper = true
        }

        let token = UUID()
        harvestGeneration = token
        let harvester = environment.recommendHarvester
        let profileStore = environment.recommendProfileStore
        let blacklistStore = environment.blacklistStore
        let context = Self.buildContext(environment: environment)

        harvestTask = Task.detached(priority: .userInitiated) { [weak self] in
            let feed = await harvester.harvestAndBuildExpandedFeedProgressive(
                enabledSources: context.sources,
                seeds: context.seeds,
                searchHistory: context.searchHistory,
                profileStore: profileStore,
                vpnSourceIds: context.vpnSourceIds,
                excludedExistingTitles: context.excludedTitles,
                titleNormalizer: { ComicTitleNormalizer.normalize($0) },
                blacklistTitlePredicate: { blacklistStore.isBlacklistedTitle($0) },
                forceRefresh: forceRefresh,
                onPartialFeed: { [weak self] partial in
                    Task { @MainActor [weak self] in
                        guard let self, self.harvestGeneration == token else { return }
                        if self.rawFeed == nil || partial.moreStreamItems.count > (self.rawFeed?.moreStreamItems.count ?? 0) {
                            self.rawFeed = partial
                            self.isLoadingInitial = false
                            self.blacklistFilterCache.invalidate()
                            self.applyBlacklistFilterAndRebuild()
                        }
                    }
                }
            )

            await MainActor.run { [weak self] in
                guard let self, self.harvestGeneration == token else { return }
                self.isLoadingInitial = false
                self.isRefreshingUpper = false
                self.refreshControl.endRefreshing()
                if !feed.isEmpty {
                    self.rawFeed = feed
                    self.blacklistFilterCache.invalidate()
                    self.applyBlacklistFilterAndRebuild()
                    self.ensureStreamPager()
                } else if self.rawFeed == nil {
                    self.initialLoadErrorMessage = "暂时未能获取到推荐内容"
                    self.rebuildSectionItems()
                }
            }
        }
    }

    private func ensureStreamPager() {
        let context = Self.buildContext(environment: environment)
        let blacklistStore = environment.blacklistStore
        let existing = filteredFeed.map {
            $0.spotlightPool + $0.guessPool + $0.hotRankItems + $0.latestItems + $0.moreStreamItems
        } ?? []
        streamPager = environment.recommendHarvester.createStreamPager(
            enabledSources: context.sources,
            seeds: context.seeds,
            searchHistory: context.searchHistory,
            profileStore: environment.recommendProfileStore,
            vpnSourceIds: context.vpnSourceIds,
            excludedExistingTitles: context.excludedTitles,
            titleNormalizer: { ComicTitleNormalizer.normalize($0) },
            blacklistTitlePredicate: { blacklistStore.isBlacklistedTitle($0) },
            initialShownItems: existing
        )
    }

    private func handleBlacklistChanged() {
        blacklistFilterCache.invalidate()
        streamPager?.notifyBlacklistChanged()
        applyBlacklistFilterAndRebuild()
        if let activeRankSheet, let hot = filteredFeed?.hotRankItems {
            activeRankSheet.updateItems(hot)
        }
    }

    private func applyBlacklistFilterAndRebuild() {
        let filtered = blacklistFilterCache.filter(rawFeed, blacklistStore: environment.blacklistStore)
        filteredFeed = filtered
        let poolCount = filtered?.guessPool.count ?? 0
        if poolCount > guessPoolSizeLast && guessPoolSizeLast > 0 {
            let cols = DiscoveryLayoutMetrics.columns(forWidth: viewWidth)
            let batchSize = RecommendPagePolicy.effectiveGuessBatchSize(poolSize: guessPoolSizeLast, columnCount: cols)
            guessBatchIndex = RecommendPagePolicy.stabilizeBatchIndexBeforePoolAppend(
                currentBatchIdx: guessBatchIndex,
                currentPoolSize: guessPoolSizeLast,
                batchSize: batchSize
            )
        }
        guessPoolSizeLast = poolCount
        rebuildSectionItems()
    }

    private var viewWidth: CGFloat {
        let w = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        return max(260, w - DiscoveryLayoutMetrics.horizontalPadding * 2)
    }

    private func rebuildSectionItems() {
        var rows: [SectionItem] = []

        if environment.discoverySources.isEmpty {
            rows.append(.state(.emptySources { [weak self] in
                self?.onManageSources?()
            }))
            sectionItems = rows
            collectionView.reloadData()
            return
        }

        if isLoadingInitial && (filteredFeed?.isEmpty ?? true) {
            rows.append(.state(.skeleton(columns: DiscoveryLayoutMetrics.columns(forWidth: viewWidth))))
            sectionItems = rows
            collectionView.reloadData()
            return
        }

        guard let feed = filteredFeed, !feed.isEmpty else {
            if let errorMsg = initialLoadErrorMessage {
                rows.append(.state(.error(message: errorMsg) { [weak self] in
                    self?.reloadFromScratch(forceRefresh: true, showSkeletonIfEmpty: true)
                }))
            } else if !environment.recommendProfileStore.isPersonalizationEnabled {
                rows.append(.state(.noPersonalization { [weak self] in
                    self?.openPrefSheet()
                }))
            } else {
                rows.append(.state(.emptyFeed(message: "暂无匹配当前偏好的推荐") { [weak self] in
                    self?.reloadFromScratch(forceRefresh: true, showSkeletonIfEmpty: true)
                }))
            }
            sectionItems = rows
            collectionView.reloadData()
            return
        }

        if !feed.spotlightPool.isEmpty {
            let batch = RecommendEngine.selectSpotlightBatch(feed, batchIndex: spotlightBatchIndex)
            if !batch.isEmpty {
                rows.append(.spotlight(batch))
            }
        }

        if !feed.guessPool.isEmpty {
            let cols = DiscoveryLayoutMetrics.columns(forWidth: viewWidth)
            let batch = RecommendPagePolicy.selectAlignedGuessBatch(
                pool: feed.guessPool,
                batchIndex: guessBatchIndex,
                columnCount: cols
            )
            if !batch.isEmpty {
                rows.append(.guess(batch))
            }
        }

        if !feed.hotRankItems.isEmpty {
            rows.append(.hotRank(feed.hotRankItems))
        }

        if !feed.latestItems.isEmpty {
            rows.append(.latest(feed.latestItems))
        }

        if !feed.moreStreamItems.isEmpty {
            rows.append(.moreHeader)
            for item in feed.moreStreamItems {
                rows.append(.moreCard(item))
            }
        }

        rows.append(.footer(footerState.state, footerState.errorMessage))
        sectionItems = rows
        collectionView.reloadData()
    }

    // MARK: - Actions & Pagination

    @objc private func handlePullToRefresh() {
        reloadFromScratch(forceRefresh: true, showSkeletonIfEmpty: false)
    }

    private func rotateSpotlightBatch() {
        guard let feed = filteredFeed, !feed.spotlightPool.isEmpty else { return }
        let totalBatches = max(1, Int(ceil(Double(feed.spotlightPool.count) / Double(RecommendConstants.spotlightBatchSize))))
        spotlightBatchIndex = (spotlightBatchIndex + 1) % totalBatches
        rebuildSectionItems()
        if feed.spotlightPool.count < RecommendConstants.maxReplenishedUpperItems {
            replenishUpperSection(isSpotlight: true)
        }
    }

    private func rotateGuessBatch() {
        guard let feed = filteredFeed, !feed.guessPool.isEmpty else { return }
        let cols = DiscoveryLayoutMetrics.columns(forWidth: viewWidth)
        let batchSize = RecommendPagePolicy.effectiveGuessBatchSize(poolSize: feed.guessPool.count, columnCount: cols)
        guessBatchIndex = RecommendPagePolicy.advanceBatchIndex(
            currentBatchIdx: guessBatchIndex,
            currentPoolSize: feed.guessPool.count,
            batchSize: batchSize
        )
        rebuildSectionItems()
        if feed.guessPool.count < RecommendConstants.maxReplenishedUpperItems {
            replenishUpperSection(isSpotlight: false)
        }
    }

    private func replenishUpperSection(isSpotlight: Bool) {
        guard !isReplenishingUpper else { return }
        if streamPager == nil { ensureStreamPager() }
        guard let pager = streamPager, let current = rawFeed else { return }
        isReplenishingUpper = true
        let existingNorms = Set((current.spotlightPool + current.guessPool).map(\.normalizedTitle))

        Task.detached(priority: .utility) { [weak self] in
            let additions = await pager.replenishUpperSection(
                isSpotlight: isSpotlight,
                existingUpperNorms: existingNorms,
                count: isSpotlight ? 6 : 12
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isReplenishingUpper = false
                guard !additions.isEmpty, let latest = self.rawFeed else { return }
                self.rawFeed = latest.withAppendedUpperItems(isSpotlight: isSpotlight, additions: additions)
                self.blacklistFilterCache.invalidate()
                self.applyBlacklistFilterAndRebuild()
            }
        }
    }

    private func loadNextStreamBatch(force: Bool = false) {
        if streamPager == nil { ensureStreamPager() }
        guard let pager = streamPager else { return }
        if !force {
            guard footerState.state == .ready else { return }
        }
        _ = footerState.setLoading(true)
        updateFooterCellOrReload()

        let token = UUID()
        streamGeneration = token
        streamTask?.cancel()
        streamTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = await pager.fetchNextBatch(targetBatchSize: 18)
            await MainActor.run { [weak self] in
                guard let self, self.streamGeneration == token else { return }
                if !result.items.isEmpty, let current = self.rawFeed {
                    self.rawFeed = current.withAppendedMoreItems(result.items, allowRecycled: result.recycled)
                    _ = self.footerState.resetToReady()
                    self.blacklistFilterCache.invalidate()
                    self.applyBlacklistFilterAndRebuild()
                } else if !result.errorMessage.isEmpty {
                    _ = self.footerState.setError(result.errorMessage)
                    self.updateFooterCellOrReload()
                } else {
                    _ = self.footerState.resetToReady()
                    self.updateFooterCellOrReload()
                }
            }
        }
    }

    private func updateFooterCellOrReload() {
        guard !sectionItems.isEmpty else {
            rebuildSectionItems()
            return
        }
        if case .footer = sectionItems[sectionItems.count - 1] {
            sectionItems[sectionItems.count - 1] = .footer(footerState.state, footerState.errorMessage)
            let lastPath = IndexPath(item: sectionItems.count - 1, section: 0)
            if let cell = collectionView.cellForItem(at: lastPath) as? RecommendFooterCell {
                cell.configure(state: footerState.state, errorMessage: footerState.errorMessage) { [weak self] in
                    self?.loadNextStreamBatch(force: true)
                }
                return
            }
        }
        rebuildSectionItems()
    }

    // MARK: - Item Interactions

    private func referer(for item: RecommendItem) -> String {
        environment.allSources.first(where: { $0.id == item.summary.sourceId })?.referer(forUrl: item.summary.coverUrl) ?? ""
    }

    private func handleSelectItem(_ item: RecommendItem) {
        environment.recommendProfileStore.recordClick(
            normalizedTitle: item.normalizedTitle,
            title: item.summary.title,
            sourceId: item.summary.sourceId,
            author: item.author,
            genres: item.genres
        )
        openComicDetail(item.summary)
    }

    private func openComicDetail(_ summary: ComicSummary) {
        if let onOpenDetail {
            onOpenDetail(summary)
        } else {
            navigationController?.pushViewController(DetailViewController(comic: summary, environment: environment), animated: true)
        }
    }

    private func presentQuickActions(for item: RecommendItem) {
        let isFavorite = environment.library.entry(for: item.summary)?.isFavorite == true
        let sheet = ComicQuickActionSheetController(
            comic: item.summary,
            sourceName: item.sourceName,
            referer: referer(for: item),
            library: environment.localLibrary,
            isFavorite: isFavorite,
            showNotInterested: true,
            allowRemoveFromShelf: false,
            onToggleFavorite: { [weak self] in
                guard let self else { return }
                do {
                    let target = !isFavorite
                    try self.environment.setFavorite(item.summary, favorite: target)
                    RemToastView.show(
                        message: target ? "已加入书架" : "已取消收藏",
                        kind: .info,
                        window: self.view.window
                    )
                } catch {
                    self.showError(error)
                }
            },
            onSwitchSource: { [weak self] in
                guard let self else { return }
                let switchSheet = SourceSwitchSheet(environment: self.environment, originalComic: item.summary) { [weak self] replacedDetail in
                    self?.openComicDetail(replacedDetail.summary)
                }
                self.present(UINavigationController(rootViewController: switchSheet), animated: true)
            },
            onNotInterested: { [weak self] in
                self?.markNotInterested(item)
            },
            onBlacklist: { [weak self] in
                guard let self else { return }
                BlacklistConfirmHelper.presentAndAdd(
                    from: self,
                    environment: self.environment,
                    comic: item.summary,
                    sourceName: item.sourceName
                )
            }
        )
        present(sheet, animated: false)
    }

    private func markNotInterested(_ item: RecommendItem) {
        environment.recommendProfileStore.recordDislike(
            normalizedTitle: item.normalizedTitle,
            displayTitle: item.summary.title,
            genres: item.genres,
            author: item.author
        )
        streamPager?.markTitleBlacklistedOrRemoved(item.normalizedTitle)

        let previousFeed = rawFeed
        if let feed = rawFeed {
            rawFeed = filterItemOut(feed: feed, normalizedTitle: item.normalizedTitle)
            blacklistFilterCache.invalidate()
            applyBlacklistFilterAndRebuild()
        }
        if let activeRankSheet, let hot = filteredFeed?.hotRankItems {
            activeRankSheet.updateItems(hot)
        }

        RemToastView.show(
            message: "已减少《\(item.summary.title)》相关推荐",
            kind: .info,
            actionTitle: "撤销",
            duration: 5.0,
            window: view.window
        ) { [weak self] in
            guard let self else { return }
            _ = self.environment.recommendProfileStore.undoDislike(item.normalizedTitle)
            self.streamPager?.removeFromSeen(item.normalizedTitle)
            if let previousFeed {
                self.rawFeed = previousFeed
                self.blacklistFilterCache.invalidate()
                self.applyBlacklistFilterAndRebuild()
                if let activeRankSheet = self.activeRankSheet, let hot = self.filteredFeed?.hotRankItems {
                    activeRankSheet.updateItems(hot)
                }
            }
        }
    }

    private func filterItemOut(feed: RecommendFeed, normalizedTitle: String) -> RecommendFeed {
        RecommendFeed(
            availableGenres: feed.availableGenres,
            spotlightPool: feed.spotlightPool.filter { $0.normalizedTitle != normalizedTitle },
            guessPool: feed.guessPool.filter { $0.normalizedTitle != normalizedTitle },
            hotRankItems: feed.hotRankItems.filter { $0.normalizedTitle != normalizedTitle },
            latestItems: feed.latestItems.filter { $0.normalizedTitle != normalizedTitle },
            moreStreamItems: feed.moreStreamItems.filter { $0.normalizedTitle != normalizedTitle },
            generatedAt: feed.generatedAt,
            isColdStart: feed.isColdStart,
            personalizationActive: feed.personalizationActive
        )
    }

    private func presentHotRankSheet() {
        guard let hot = filteredFeed?.hotRankItems, !hot.isEmpty else { return }
        let sheet = RecommendRankSheetController(
            environment: environment,
            items: hot,
            onSelect: { [weak self] item in
                self?.handleSelectItem(item)
            },
            onLongPress: { [weak self] item in
                self?.presentQuickActions(for: item)
            }
        )
        activeRankSheet = sheet
        present(sheet, animated: false)
    }
}

// MARK: - UICollectionViewDataSource & DelegateFlowLayout

extension RecommendViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sectionItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch sectionItems[indexPath.item] {
        case .state(let mode):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecommendStateCell.reuseId, for: indexPath) as? RecommendStateCell else {
                return UICollectionViewCell()
            }
            cell.configure(mode: mode, availableWidth: viewWidth)
            return cell

        case .spotlight(let items):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecommendSpotlightCell.reuseId, for: indexPath) as? RecommendSpotlightCell else {
                return UICollectionViewCell()
            }
            cell.configure(
                items: items,
                availableWidth: viewWidth,
                refererProvider: { [weak self] item in self?.referer(for: item) ?? "" },
                library: environment.localLibrary,
                onRefresh: { [weak self] in self?.rotateSpotlightBatch() },
                onSelect: { [weak self] item in self?.handleSelectItem(item) },
                onLongPress: { [weak self] item in self?.presentQuickActions(for: item) },
                onImpressions: { [weak self] visible in
                    self?.environment.recommendProfileStore.recordImpressions(visible.map(\.normalizedTitle))
                }
            )
            return cell

        case .guess(let items):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecommendGuessCell.reuseId, for: indexPath) as? RecommendGuessCell else {
                return UICollectionViewCell()
            }
            let cols = DiscoveryLayoutMetrics.columns(forWidth: viewWidth)
            cell.configure(
                items: items,
                columnCount: cols,
                availableWidth: viewWidth,
                refererProvider: { [weak self] item in self?.referer(for: item) ?? "" },
                library: environment.localLibrary,
                onRefresh: { [weak self] in self?.rotateGuessBatch() },
                onSelect: { [weak self] item in self?.handleSelectItem(item) },
                onLongPress: { [weak self] item in self?.presentQuickActions(for: item) }
            )
            return cell

        case .hotRank(let items):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecommendHotCell.reuseId, for: indexPath) as? RecommendHotCell else {
                return UICollectionViewCell()
            }
            cell.configure(
                items: items,
                availableWidth: viewWidth,
                refererProvider: { [weak self] item in self?.referer(for: item) ?? "" },
                library: environment.localLibrary,
                onViewAll: { [weak self] in self?.presentHotRankSheet() },
                onSelect: { [weak self] item in self?.handleSelectItem(item) },
                onLongPress: { [weak self] item in self?.presentQuickActions(for: item) }
            )
            return cell

        case .latest(let items):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecommendLatestCell.reuseId, for: indexPath) as? RecommendLatestCell else {
                return UICollectionViewCell()
            }
            cell.configure(
                items: items,
                refererProvider: { [weak self] item in self?.referer(for: item) ?? "" },
                library: environment.localLibrary,
                onSelect: { [weak self] item in self?.handleSelectItem(item) },
                onLongPress: { [weak self] item in self?.presentQuickActions(for: item) }
            )
            return cell

        case .moreHeader:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecommendMoreHeaderCell.reuseId, for: indexPath) as? RecommendMoreHeaderCell else {
                return UICollectionViewCell()
            }
            cell.configure()
            return cell

        case .moreCard(let item):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecommendMoreCardCell.reuseId, for: indexPath) as? RecommendMoreCardCell else {
                return UICollectionViewCell()
            }
            cell.configure(item: item, referer: referer(for: item), library: environment.localLibrary) { [weak self] in
                self?.presentQuickActions(for: item)
            }
            return cell

        case .footer(let state, let err):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecommendFooterCell.reuseId, for: indexPath) as? RecommendFooterCell else {
                return UICollectionViewCell()
            }
            cell.configure(state: state, errorMessage: err) { [weak self] in
                self?.loadNextStreamBatch(force: true)
            }
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < sectionItems.count else { return }
        if case .moreCard(let item) = sectionItems[indexPath.item] {
            handleSelectItem(item)
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard indexPath.item < sectionItems.count else { return }
        if case .moreCard(let item) = sectionItems[indexPath.item] {
            environment.recommendProfileStore.recordImpressions([item.normalizedTitle])
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = viewWidth
        let fullW = max(200, width)
        switch sectionItems[indexPath.item] {
        case .state(let mode):
            switch mode {
            case .skeleton(let cols):
                let spacing = DiscoveryLayoutMetrics.interItemSpacing
                let cardW = floor((fullW - spacing * CGFloat(cols - 1)) / CGFloat(cols))
                let coverH = ceil(cardW * 4.0 / 3.0)
                return CGSize(width: fullW, height: 124 + 24 + (coverH + 20) * 2 + 36)
            default:
                return CGSize(width: fullW, height: 290)
            }
        case .spotlight:
            return CGSize(width: fullW, height: RecommendSpotlightCell.requiredHeight())
        case .guess(let items):
            let cols = DiscoveryLayoutMetrics.columns(forWidth: fullW)
            return CGSize(width: fullW, height: RecommendGuessCell.requiredHeight(itemCount: items.count, columnCount: cols, availableWidth: fullW))
        case .hotRank(let items):
            return CGSize(width: fullW, height: RecommendHotCell.requiredHeight(totalItems: items.count, availableWidth: fullW))
        case .latest:
            return CGSize(width: fullW, height: RecommendLatestCell.requiredHeight())
        case .moreHeader:
            return CGSize(width: fullW, height: 30)
        case .moreCard:
            let cardW = DiscoveryLayoutMetrics.cardWidth(forWidth: view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width)
            return CGSize(width: cardW, height: RecommendMoreCardCell.cardHeight(forCardWidth: cardW))
        case .footer:
            return CGSize(width: fullW, height: 48)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let dy = scrollView.contentOffset.y - lastScrollOffsetY
        lastScrollOffsetY = scrollView.contentOffset.y
        let visiblePaths = collectionView.indexPathsForVisibleItems.sorted()
        let firstVisible = visiblePaths.first?.item ?? 0
        let lastVisible = visiblePaths.last?.item ?? 0
        let cols = DiscoveryLayoutMetrics.columns(forWidth: viewWidth)

        backToTopButton.updateScrollState(
            scrollView: scrollView,
            dy: dy,
            firstVisibleIndex: firstVisible,
            spanCount: cols,
            isMixedFullSpanList: true
        )

        if !(filteredFeed?.isEmpty ?? true),
           !isRefreshingUpper,
           footerState.canTriggerOnScroll(
               dy: Int(dy.rounded()),
               hasMoreItems: true,
               hasCallbacks: true,
               lastVisible: lastVisible,
               totalCount: sectionItems.count,
               spanCount: cols
           ) {
            footerState.dispatchScrollLoad(
                onLoadMore: { [weak self] in self?.loadNextStreamBatch() },
                onStateChanged: { [weak self] in self?.updateFooterCellOrReload() }
            )
        }
    }
}
