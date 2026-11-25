import UIKit
import ComicCore

@MainActor
final class DiscoverViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextFieldDelegate {
    private let environment: AppEnvironment

    // MARK: - Top Dual-Tab Header
    private var activeTab = 0 // 0 = 发现 (default), 1 = 推荐
    private let dualTabStack = UIStackView()
    private let discoverTabButton = UIButton(type: .system)
    private let recommendTabButton = UIButton(type: .system)
    private let discoverTabIndicator = UIView()
    private let recommendTabIndicator = UIView()
    private let sourceButton = UIButton(type: .system)
    private var sourceButtonWidth: NSLayoutConstraint?
    private lazy var sourceBarItem = UIBarButtonItem(customView: sourceButton)
    private lazy var recommendPrefBarItem: UIBarButtonItem = SecondaryHeaderBar.textButton(
        title: "推荐偏好",
        accessibilityIdentifier: "recommend.pref",
        target: self,
        action: #selector(openRecommendPref)
    )

    // MARK: - Child Tabs & Discovery Chrome
    private let discoverContainer = UIView()
    private lazy var recommendVC: RecommendViewController = {
        let vc = RecommendViewController(environment: environment)
        vc.onOpenDetail = { [weak self] comic in
            self?.openDetail(comic)
        }
        vc.onManageSources = { [weak self] in
            self?.openSourceSettingsFromGuide()
        }
        return vc
    }()

    private let header = UIStackView()
    private let toolsHost = UIView()
    private let tools = UIStackView()
    private var collapsedToolsHeight: NSLayoutConstraint!
    private var toolsHidden = false
    private var headerGesture = DiscoveryHeaderGesture()

    private let searchBar = UISearchTextField()
    private let modeButton = UIButton(type: .system)
    private weak var searchOutline: UIView?

    private let browseModeBar = UIStackView()
    private let recommendModeButton = UIButton(type: .system)
    private let categoryModeButton = UIButton(type: .system)
    private let filterButton = UIButton(type: .system)
    private let resetFiltersButton = UIButton(type: .system)

    private let inlineFiltersStack = UIStackView()
    private let tabs = SourceOptionScrollView()
    private let tabRow = UIStackView()
    private let sectionHeading = UILabel()
    private let emptySourcesGuide = UIView()

    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
    private let stateOverlayView = DiscoveryStateOverlayView()
    private let refreshControl = UIRefreshControl()
    private let backToTopButton = BackToTopButton()

    // MARK: - State
    private var browseMode: DiscoveryBrowseMode = .recommend
    private var globalMode = false
    private var isGlobal: Bool { globalMode }
    private var sourceIndex = 0
    private var sourceIDs: [String] = []
    private var filters: [String: String] = [:]
    private var filterLabels: [String: String] = [:]
    private var scopeGroups: [SourceFilterGroup] = []
    private var scopeSourceID: String?
    private var scopeRequestID = UUID()
    private var scopeTask: Task<Void, Never>?

    private var rawSingleComics: [ComicSummary] = []
    private var visibleSingleComics: [ComicSummary] = []
    private var rows: [DiscoveryRowItem] = []

    private var requestID = UUID()
    private var tasks: [Task<Void, Never>] = []
    private var nextPage = 1
    private var loading = false
    private var ended = false
    private var singleErrorMessage: String?
    private var singleNeedsVerification = false
    private var submittedQuery = ""
    private var needsReload = false
    private var hasPendingDirtyReload = false

    private var global = GlobalSearchState()
    private var pendingGlobalSources: [any ComicSource] = []
    private var activeGlobalCount = 0
    private var currentGlobalGeneration = UUID()
    private var expandedGlobalSourceIDs: Set<String> = []
    private var errors: [String: Error] = [:]
    private var finished = Set<String>()
    private let globalCoalescer = GlobalSearchUiCoalescer()

    private var detailIdleObserverID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var prewarmTask: Task<Void, Never>?
    private var didSchedulePrewarm = false
    private var lastScrollOffsetY: CGFloat = 0
    private var lastLayoutWidth: CGFloat = 0

    private var hasNoInstalledSources: Bool {
        environment.sourcePreferences.orderedIDs.isEmpty && environment.sources.isEmpty
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    deinit {
        tasks.forEach { $0.cancel() }
        scopeTask?.cancel()
        prewarmTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let observerID = detailIdleObserverID {
            let env = environment
            Task { @MainActor in env.removeForegroundDetailIdleObserver(observerID) }
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        sourceIDs = environment.discoverySources.map(\.id)

        setupDualTabNavigationBar()
        setupDiscoverContainer()
        setupRecommendChild()
        setupEmptySourcesGuide()
        setupBackToTop()
        setupObservers()

        applyActiveTab(0, animated: false)
        updateSourceMenu()
        loadInlineFilters(for: currentSource)
        start()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleSilentRecommendPrewarmIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // P3 Keep-Alive: do not unconditionally reload collection when popping back from DetailViewController.
        if needsReload {
            needsReload = false
            start(query: submittedQuery, restoringGlobalSourceID: isGlobal ? global.selectedSourceID : nil)
        } else if hasPendingDirtyReload {
            hasPendingDirtyReload = false
            handleDirtyRefresh()
        } else {
            updateSourceMenu()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        headerGesture.end()
        if presentedViewController != nil { return }
        let isChildPushedInSameTab: Bool = {
            guard let nav = navigationController,
                  nav.viewControllers.contains(self),
                  nav.viewControllers.count > 1 else { return false }
            if let tab = nav.tabBarController {
                return tab.selectedViewController === nav
            }
            return true
        }()
        if isChildPushedInSameTab {
            // Keep visible covers and loaded data alive when pushing DetailViewController.
            return
        }
        needsReload = loading || (isGlobal && !submittedQuery.isEmpty && finished.count < environment.searchSources.count)
        cancelActiveRequests()
        scopeTask?.cancel()
        scopeSourceID = nil
        scopeRequestID = UUID()
        loading = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        if width > 0 && abs(width - lastLayoutWidth) > 1 {
            lastLayoutWidth = width
            flowLayout.invalidateLayout()
        }
        updateSourceControlSize()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        searchOutline?.layer.borderColor = Palette.border.resolvedColor(with: traitCollection).cgColor
        updateTabButtonStyles()
    }

    // MARK: - Setup UI

    private func setupDualTabNavigationBar() {
        title = "发现"
        SecondaryHeaderBar.configureNavigationBarAppearance(for: navigationController)

        discoverTabButton.setTitle("发现", for: .normal)
        discoverTabButton.accessibilityIdentifier = "discover.tab.discover"
        discoverTabButton.accessibilityLabel = "发现"
        discoverTabButton.addTarget(self, action: #selector(selectDiscoverTab), for: .touchUpInside)

        recommendTabButton.setTitle("推荐", for: .normal)
        recommendTabButton.accessibilityIdentifier = "discover.tab.recommend"
        recommendTabButton.accessibilityLabel = "推荐"
        recommendTabButton.addTarget(self, action: #selector(selectRecommendTab), for: .touchUpInside)

        discoverTabIndicator.backgroundColor = Palette.accent
        discoverTabIndicator.layer.cornerRadius = 1.5
        discoverTabIndicator.translatesAutoresizingMaskIntoConstraints = false

        recommendTabIndicator.backgroundColor = Palette.accent
        recommendTabIndicator.layer.cornerRadius = 1.5
        recommendTabIndicator.translatesAutoresizingMaskIntoConstraints = false

        let discoverWrap = UIView()
        discoverTabButton.translatesAutoresizingMaskIntoConstraints = false
        discoverWrap.addSubview(discoverTabButton)
        discoverWrap.addSubview(discoverTabIndicator)
        NSLayoutConstraint.activate([
            discoverTabButton.topAnchor.constraint(equalTo: discoverWrap.topAnchor),
            discoverTabButton.leadingAnchor.constraint(equalTo: discoverWrap.leadingAnchor),
            discoverTabButton.trailingAnchor.constraint(equalTo: discoverWrap.trailingAnchor),
            discoverTabButton.bottomAnchor.constraint(equalTo: discoverWrap.bottomAnchor, constant: -3),
            discoverTabIndicator.centerXAnchor.constraint(equalTo: discoverWrap.centerXAnchor),
            discoverTabIndicator.bottomAnchor.constraint(equalTo: discoverWrap.bottomAnchor),
            discoverTabIndicator.widthAnchor.constraint(equalToConstant: 18),
            discoverTabIndicator.heightAnchor.constraint(equalToConstant: 3)
        ])

        let recommendWrap = UIView()
        recommendTabButton.translatesAutoresizingMaskIntoConstraints = false
        recommendWrap.addSubview(recommendTabButton)
        recommendWrap.addSubview(recommendTabIndicator)
        NSLayoutConstraint.activate([
            recommendTabButton.topAnchor.constraint(equalTo: recommendWrap.topAnchor),
            recommendTabButton.leadingAnchor.constraint(equalTo: recommendWrap.leadingAnchor),
            recommendTabButton.trailingAnchor.constraint(equalTo: recommendWrap.trailingAnchor),
            recommendTabButton.bottomAnchor.constraint(equalTo: recommendWrap.bottomAnchor, constant: -3),
            recommendTabIndicator.centerXAnchor.constraint(equalTo: recommendWrap.centerXAnchor),
            recommendTabIndicator.bottomAnchor.constraint(equalTo: recommendWrap.bottomAnchor),
            recommendTabIndicator.widthAnchor.constraint(equalToConstant: 18),
            recommendTabIndicator.heightAnchor.constraint(equalToConstant: 3)
        ])

        let separator = UILabel()
        separator.text = "|"
        separator.font = .systemFont(ofSize: 13, weight: .regular)
        separator.textColor = Palette.border

        dualTabStack.axis = .horizontal
        dualTabStack.alignment = .center
        dualTabStack.spacing = 10
        dualTabStack.addArrangedSubview(discoverWrap)
        dualTabStack.addArrangedSubview(separator)
        dualTabStack.addArrangedSubview(recommendWrap)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: dualTabStack)

        sourceButton.accessibilityIdentifier = "discover.source"
        sourceButton.titleLabel?.lineBreakMode = .byTruncatingTail
        sourceButton.addTarget(self, action: #selector(showSources), for: .touchUpInside)
        sourceButtonWidth = sourceButton.widthAnchor.constraint(lessThanOrEqualToConstant: 180)
        sourceButtonWidth?.isActive = true
        navigationItem.rightBarButtonItem = sourceBarItem

        updateTabButtonStyles()
    }

    private func setupDiscoverContainer() {
        discoverContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(discoverContainer)
        NSLayoutConstraint.activate([
            discoverContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            discoverContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            discoverContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            discoverContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        header.axis = .vertical
        header.spacing = 6
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 4, right: 12)
        header.translatesAutoresizingMaskIntoConstraints = false
        discoverContainer.addSubview(header)

        tools.axis = .vertical
        tools.spacing = 6
        tools.accessibilityIdentifier = "discover.tools"
        tools.translatesAutoresizingMaskIntoConstraints = false
        toolsHost.clipsToBounds = true
        toolsHost.addSubview(tools)
        let bottomConstraint = tools.bottomAnchor.constraint(equalTo: toolsHost.bottomAnchor)
        bottomConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            tools.topAnchor.constraint(equalTo: toolsHost.topAnchor),
            tools.leadingAnchor.constraint(equalTo: toolsHost.leadingAnchor),
            tools.trailingAnchor.constraint(equalTo: toolsHost.trailingAnchor),
            bottomConstraint
        ])
        collapsedToolsHeight = toolsHost.heightAnchor.constraint(equalToConstant: 0)
        header.addArrangedSubview(toolsHost)

        // Search row
        searchBar.delegate = self
        searchBar.backgroundColor = .clear
        searchBar.borderStyle = .none
        searchBar.font = .systemFont(ofSize: 14)
        searchBar.textColor = Palette.text
        searchBar.returnKeyType = .search
        searchBar.clearButtonMode = .whileEditing
        searchBar.accessibilityIdentifier = "discover.search"
        searchBar.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        let searchIcon = UIImageView(image: ParityIcon.search.image(size: 20))
        searchIcon.tintColor = Palette.text3
        searchIcon.contentMode = .center
        searchIcon.frame = CGRect(x: 0, y: 0, width: 38, height: 40)
        searchBar.leftView = searchIcon
        searchBar.leftViewMode = .always

        modeButton.accessibilityIdentifier = "discover.search.mode"
        modeButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        modeButton.tintColor = Palette.accent
        modeButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        modeButton.addTarget(self, action: #selector(modeChanged), for: .touchUpInside)

        let searchContainer = UIStackView(arrangedSubviews: [searchBar, modeButton])
        searchContainer.alignment = .center
        searchContainer.backgroundColor = Palette.card
        searchContainer.layer.cornerRadius = 10
        searchContainer.layer.borderWidth = 1
        searchContainer.layer.borderColor = Palette.border.resolvedColor(with: traitCollection).cgColor
        searchContainer.accessibilityIdentifier = "discover.search.container"
        searchContainer.isLayoutMarginsRelativeArrangement = true
        searchContainer.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        searchContainer.heightAnchor.constraint(equalToConstant: 40).isActive = true
        searchOutline = searchContainer
        tools.addArrangedSubview(searchContainer)

        // Browse mode & filter row
        browseModeBar.axis = .horizontal
        browseModeBar.alignment = .center
        browseModeBar.spacing = 8

        configureModePill(recommendModeButton, title: "推荐", identifier: "discover.mode.recommend", action: #selector(selectBrowseRecommend))
        configureModePill(categoryModeButton, title: "分类", identifier: "discover.mode.category", action: #selector(selectBrowseCategory))

        filterButton.setTitle("筛选", for: .normal)
        filterButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        filterButton.setTitleColor(Palette.accentText, for: .normal)
        filterButton.backgroundColor = Palette.accentSoft
        filterButton.layer.cornerRadius = 13
        filterButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        filterButton.accessibilityIdentifier = "discover.filter.button"
        filterButton.addTarget(self, action: #selector(showFilters), for: .touchUpInside)

        resetFiltersButton.setTitle("重置", for: .normal)
        resetFiltersButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        resetFiltersButton.setTitleColor(Palette.secondaryText, for: .normal)
        resetFiltersButton.backgroundColor = Palette.surface
        resetFiltersButton.layer.cornerRadius = 13
        resetFiltersButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        resetFiltersButton.accessibilityIdentifier = "discover.filter.reset"
        resetFiltersButton.addTarget(self, action: #selector(resetInlineFilters), for: .touchUpInside)
        resetFiltersButton.isHidden = true

        browseModeBar.addArrangedSubview(recommendModeButton)
        browseModeBar.addArrangedSubview(categoryModeButton)
        browseModeBar.addArrangedSubview(UIView())
        browseModeBar.addArrangedSubview(resetFiltersButton)
        browseModeBar.addArrangedSubview(filterButton)
        tools.addArrangedSubview(browseModeBar)

        // Inline filter rows (max 3 groups in Category mode)
        inlineFiltersStack.axis = .vertical
        inlineFiltersStack.spacing = 6
        inlineFiltersStack.isHidden = true
        tools.addArrangedSubview(inlineFiltersStack)

        // Global search chip bar
        tabs.showsHorizontalScrollIndicator = false
        tabs.isHidden = true
        tabs.heightAnchor.constraint(equalToConstant: 36).isActive = true
        tabRow.axis = .horizontal
        tabRow.spacing = 8
        tabRow.alignment = .center
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabs.addSubview(tabRow)
        NSLayoutConstraint.activate([
            tabRow.topAnchor.constraint(equalTo: tabs.topAnchor),
            tabRow.bottomAnchor.constraint(equalTo: tabs.bottomAnchor),
            tabRow.leadingAnchor.constraint(equalTo: tabs.leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: tabs.trailingAnchor),
            tabRow.heightAnchor.constraint(equalTo: tabs.heightAnchor)
        ])
        tools.addArrangedSubview(tabs)

        // Section summary heading
        sectionHeading.font = .systemFont(ofSize: 12, weight: .medium)
        sectionHeading.textColor = Palette.secondaryText
        sectionHeading.isHidden = true
        header.addArrangedSubview(sectionHeading)

        // Collection view
        flowLayout.minimumInteritemSpacing = DiscoveryLayoutMetrics.interItemSpacing
        flowLayout.minimumLineSpacing = DiscoveryLayoutMetrics.rowSpacing
        flowLayout.sectionInset = UIEdgeInsets(
            top: 8,
            left: DiscoveryLayoutMetrics.horizontalPadding,
            bottom: 24,
            right: DiscoveryLayoutMetrics.horizontalPadding
        )

        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .onDrag
        collection.dataSource = self
        collection.delegate = self
        collection.accessibilityIdentifier = "discover.collection"
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.register(DiscoveryPosterCell.self, forCellWithReuseIdentifier: DiscoveryPosterCell.reuseId)
        collection.register(DiscoverySectionHeaderCell.self, forCellWithReuseIdentifier: DiscoverySectionHeaderCell.reuseId)
        collection.register(DiscoveryFooterCell.self, forCellWithReuseIdentifier: DiscoveryFooterCell.reuseId)
        collection.register(DiscoveryStateCell.self, forCellWithReuseIdentifier: DiscoveryStateCell.reuseId)
        collection.panGestureRecognizer.addTarget(self, action: #selector(discoveryDrag(_:)))

        refreshControl.tintColor = Palette.accent
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        collection.refreshControl = refreshControl

        discoverContainer.addSubview(collection)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: discoverContainer.topAnchor),
            header.leadingAnchor.constraint(equalTo: discoverContainer.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: discoverContainer.trailingAnchor),

            collection.topAnchor.constraint(equalTo: header.bottomAnchor),
            collection.leadingAnchor.constraint(equalTo: discoverContainer.leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: discoverContainer.trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: discoverContainer.bottomAnchor)
        ])
    }

    private func setupRecommendChild() {
        addChild(recommendVC)
        recommendVC.view.translatesAutoresizingMaskIntoConstraints = false
        recommendVC.view.isHidden = true
        view.addSubview(recommendVC.view)
        NSLayoutConstraint.activate([
            recommendVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            recommendVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            recommendVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            recommendVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        recommendVC.didMove(toParent: self)
    }

    private func setupEmptySourcesGuide() {
        emptySourcesGuide.isHidden = true
        emptySourcesGuide.translatesAutoresizingMaskIntoConstraints = false
        discoverContainer.addSubview(emptySourcesGuide)

        let card = UIView()
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = Palette.borderSoft.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        emptySourcesGuide.addSubview(card)

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        AppIllustrationCache.bind(imageView, assetName: "rem_empty_discovery", maxSideDp: 96)

        let titleLabel = UILabel()
        titleLabel.text = "还没有站源"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "订阅站源规则或导入配置后即可浏览和搜索漫画"
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = Palette.secondaryText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let addButton = UIButton(type: .system)
        addButton.setTitle("添加站源", for: .normal)
        addButton.setTitleColor(.white, for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        addButton.backgroundColor = Palette.accent
        addButton.layer.cornerRadius = 10
        addButton.accessibilityIdentifier = "discover.add.sources"
        addButton.addTarget(self, action: #selector(openSourceSettingsFromGuide), for: .touchUpInside)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, subtitleLabel, addButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let cardWidth = card.widthAnchor.constraint(equalTo: emptySourcesGuide.widthAnchor, constant: -40)
        cardWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            emptySourcesGuide.topAnchor.constraint(equalTo: header.bottomAnchor),
            emptySourcesGuide.leadingAnchor.constraint(equalTo: discoverContainer.leadingAnchor),
            emptySourcesGuide.trailingAnchor.constraint(equalTo: discoverContainer.trailingAnchor),
            emptySourcesGuide.bottomAnchor.constraint(equalTo: discoverContainer.safeAreaLayoutGuide.bottomAnchor),

            card.centerXAnchor.constraint(equalTo: emptySourcesGuide.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: emptySourcesGuide.centerYAnchor, constant: -16),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            cardWidth,

            imageView.widthAnchor.constraint(equalToConstant: 96),
            imageView.heightAnchor.constraint(equalToConstant: 96),
            addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 148),
            addButton.heightAnchor.constraint(equalToConstant: 44),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20)
        ])
    }

    private func setupBackToTop() {
        backToTopButton.translatesAutoresizingMaskIntoConstraints = false
        backToTopButton.onTap = { [weak self] in
            guard let self else { return }
            BackToTopButton.smoothScrollToTop(self.collection)
        }
        discoverContainer.addSubview(backToTopButton)
        NSLayoutConstraint.activate([
            backToTopButton.trailingAnchor.constraint(equalTo: discoverContainer.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            backToTopButton.bottomAnchor.constraint(equalTo: discoverContainer.safeAreaLayoutGuide.bottomAnchor, constant: -18)
        ])
    }

    private func setupObservers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AppEnvironment.sourcesChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.sourcesChanged()
            }
        })
        observers.append(nc.addObserver(forName: AppEnvironment.blacklistChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.blacklistChanged()
            }
        })
        detailIdleObserverID = environment.observeForegroundDetailIdle { [weak self] in
            self?.pumpGlobalDispatchQueue()
        }
    }

    // MARK: - Dual-Tab Switching & Prewarm

    @objc private func selectDiscoverTab() {
        if activeTab == 0 {
            BackToTopButton.smoothScrollToTop(collection)
        } else {
            applyActiveTab(0, animated: true)
        }
    }

    @objc private func selectRecommendTab() {
        if activeTab == 1 {
            recommendVC.scrollToTop(animated: true)
        } else {
            applyActiveTab(1, animated: true)
        }
    }

    private func applyActiveTab(_ tab: Int, animated: Bool) {
        activeTab = tab
        updateTabButtonStyles()
        if tab == 0 {
            discoverContainer.isHidden = false
            recommendVC.view.isHidden = true
            navigationItem.rightBarButtonItem = hasNoInstalledSources ? nil : sourceBarItem
            updateSourceMenu()
        } else {
            searchBar.resignFirstResponder()
            discoverContainer.isHidden = true
            recommendVC.view.isHidden = false
            navigationItem.rightBarButtonItem = recommendPrefBarItem
            recommendVC.activateIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.18) {
                self.dualTabStack.layoutIfNeeded()
            }
        }
    }

    private func updateTabButtonStyles() {
        let isDiscover = activeTab == 0
        discoverTabButton.titleLabel?.font = .systemFont(ofSize: isDiscover ? 17 : 15, weight: isDiscover ? .bold : .medium)
        discoverTabButton.setTitleColor(isDiscover ? Palette.text : Palette.secondaryText, for: .normal)
        discoverTabIndicator.isHidden = !isDiscover

        recommendTabButton.titleLabel?.font = .systemFont(ofSize: isDiscover ? 15 : 17, weight: isDiscover ? .medium : .bold)
        recommendTabButton.setTitleColor(isDiscover ? Palette.secondaryText : Palette.text, for: .normal)
        recommendTabIndicator.isHidden = isDiscover
    }

    @objc private func openRecommendPref() {
        recommendVC.openPrefSheet()
    }

    private func scheduleSilentRecommendPrewarmIfNeeded() {
        guard !didSchedulePrewarm else { return }
        didSchedulePrewarm = true
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }

        let env = environment
        prewarmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            let context = await MainActor.run { RecommendViewController.buildContext(environment: env) }
            guard !context.sources.isEmpty else { return }
            let harvester = env.recommendHarvester
            let profileStore = env.recommendProfileStore
            let blacklistStore = env.blacklistStore
            let feed = await Task.detached(priority: .utility) {
                await harvester.harvestAndBuildExpandedFeedProgressive(
                    enabledSources: context.sources,
                    seeds: context.seeds,
                    searchHistory: context.searchHistory,
                    profileStore: profileStore,
                    vpnSourceIds: context.vpnSourceIds,
                    excludedExistingTitles: context.excludedTitles,
                    titleNormalizer: { ComicTitleNormalizer.normalize($0) },
                    blacklistTitlePredicate: { blacklistStore.isBlacklistedTitle($0) },
                    forceRefresh: false,
                    onPartialFeed: nil
                )
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.recommendVC.applyPrewarmedFeed(feed)
            }
        }
    }

    // MARK: - Sources & Navigation Chrome

    private var currentSource: (any ComicSource)? {
        let list = environment.discoverySources
        guard !list.isEmpty else { return nil }
        if list.indices.contains(sourceIndex) { return list[sourceIndex] }
        return list.first
    }

    private func configureModePill(_ button: UIButton, title: String, identifier: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.layer.cornerRadius = 13
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func updateBrowseModePills() {
        let showBrowseControls = !hasNoInstalledSources && !isGlobal && submittedQuery.isEmpty && !environment.discoverySources.isEmpty
        browseModeBar.isHidden = !showBrowseControls
        guard showBrowseControls else {
            inlineFiltersStack.isHidden = true
            return
        }

        let isRec = browseMode == .recommend
        recommendModeButton.backgroundColor = isRec ? Palette.accent : Palette.surface
        recommendModeButton.setTitleColor(isRec ? Palette.onAccent : Palette.secondaryText, for: .normal)
        categoryModeButton.backgroundColor = !isRec ? Palette.accent : Palette.surface
        categoryModeButton.setTitleColor(!isRec ? Palette.onAccent : Palette.secondaryText, for: .normal)

        let hasActiveFilters = !filters.values.filter { !$0.isEmpty && $0.lowercased() != "all" }.isEmpty
        resetFiltersButton.isHidden = !hasActiveFilters
        inlineFiltersStack.isHidden = browseMode != .category || scopeGroups.isEmpty
    }

    private func updateSourceMenu() {
        if hasNoInstalledSources {
            searchBar.resignFirstResponder()
            searchBar.isEnabled = false
            modeButton.isEnabled = false
            searchOutline?.alpha = 0.55
            updateSearchPlaceholder("请先添加站源")
            sourceButton.isHidden = true
            if activeTab == 0 { navigationItem.rightBarButtonItem = nil }
            filterButton.isEnabled = false
            scopeTask?.cancel()
            scopeSourceID = nil
            scopeGroups = []
            renderInlineFilters()
            updateBrowseModePills()
            return
        }

        searchBar.isEnabled = true
        modeButton.isEnabled = true
        searchOutline?.alpha = 1.0
        sourceButton.isHidden = false
        if activeTab == 0 { navigationItem.rightBarButtonItem = sourceBarItem }

        let sources = environment.discoverySources
        filterButton.isEnabled = !sources.isEmpty
        sourceButton.isEnabled = !sources.isEmpty

        modeButton.setTitle(isGlobal ? "全站" : "单站", for: .normal)
        modeButton.accessibilityLabel = "切换搜索模式，当前" + (isGlobal ? "全站" : "单站")
        modeButton.accessibilityValue = isGlobal ? "全站" : "单站"

        guard !sources.isEmpty else {
            var configuration = sourceButton.configuration ?? .plain()
            configuration.title = "没有已启用的站源"
            configuration.image = nil
            sourceButton.configuration = configuration
            updateSourceControlSize()
            updateSearchPlaceholder(isGlobal ? "搜索全部站源" : "搜索漫画")
            scopeTask?.cancel()
            scopeSourceID = nil
            scopeGroups = []
            renderInlineFilters()
            updateBrowseModePills()
            return
        }

        let name = currentSource?.name ?? ""
        var config = UIButton.Configuration.plain()
        config.title = name
        config.image = ParityIcon.chevronDown.image(size: 14)
        config.imagePlacement = .trailing
        config.imagePadding = 5
        config.baseForegroundColor = Palette.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 4)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: 13, weight: .semibold)
            return updated
        }
        sourceButton.configuration = config
        sourceButton.accessibilityLabel = name
        updateSourceControlSize()

        updateSearchPlaceholder(isGlobal ? "搜索全部站源" : (currentSource?.supportsSearch == false ? "\(name)暂不支持搜索" : "在\(name)中搜索"))
        updateBrowseModePills()
        if !isGlobal && submittedQuery.isEmpty {
            loadInlineFilters(for: currentSource)
        }
    }

    private func updateSearchPlaceholder(_ placeholder: String) {
        searchBar.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: Palette.text3]
        )
    }

    private func updateSourceControlSize() {
        let maxW = max(120, min(180, (view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width) * 0.42))
        sourceButtonWidth?.constant = maxW
        sourceButton.sizeToFit()
    }

    private func sourcesChanged() {
        let nextIDs = environment.discoverySources.map(\.id)
        if isGlobal, !submittedQuery.isEmpty, nextIDs != sourceIDs {
            let previousSelectedID = global.selectedSourceID
            sourceIDs = nextIDs
            let activeID = nextIDs.indices.contains(sourceIndex) ? nextIDs[sourceIndex] : nil
            sourceIndex = activeID.flatMap { nextIDs.firstIndex(of: $0) } ?? 0
            updateSourceMenu()
            start(query: submittedQuery, restoringGlobalSourceID: previousSelectedID)
            return
        }

        let currentID = sourceIDs.indices.contains(sourceIndex) ? sourceIDs[sourceIndex] : nil
        let previousFilters = filters
        sourceIDs = nextIDs
        sourceIndex = currentID.flatMap { nextIDs.firstIndex(of: $0) } ?? 0
        if currentID != (nextIDs.indices.contains(sourceIndex) ? nextIDs[sourceIndex] : nil) {
            filters = [:]
            filterLabels = [:]
        } else {
            filters = previousFilters
        }
        updateSourceMenu()
        start(query: submittedQuery)
    }

    private func blacklistChanged() {
        if isGlobal && !submittedQuery.isEmpty {
            refreshGlobalRowsOnly()
        } else if !rawSingleComics.isEmpty {
            visibleSingleComics = environment.blacklistStore.filterSummaries(rawSingleComics)
            rebuildSingleRows()
        }
    }

    private func handleDirtyRefresh() {
        updateSourceMenu()
        if isGlobal && !submittedQuery.isEmpty {
            refreshGlobalRowsOnly()
        } else {
            start(query: submittedQuery)
        }
    }

    // MARK: - Inline Filters

    private func loadInlineFilters(for source: (any ComicSource)?) {
        guard let source, !isGlobal, submittedQuery.isEmpty else {
            scopeTask?.cancel()
            scopeSourceID = nil
            scopeGroups = []
            renderInlineFilters()
            return
        }
        guard scopeSourceID != source.id else {
            let dynamic = source.filterGroupsForSelection(filters)
            if !dynamic.isEmpty {
                scopeGroups = dynamic
            }
            renderInlineFilters()
            return
        }
        scopeTask?.cancel()
        scopeSourceID = source.id
        scopeGroups = []
        renderInlineFilters()
        let token = UUID()
        scopeRequestID = token
        let activeFilters = filters
        scopeTask = Task { [weak self] in
            let groups = (try? await source.filterGroups()) ?? []
            guard let self, !Task.isCancelled, self.scopeRequestID == token else { return }
            let dynamic = source.filterGroupsForSelection(activeFilters)
            self.scopeGroups = dynamic.isEmpty ? groups : dynamic
            self.renderInlineFilters()
        }
    }

    private func renderInlineFilters() {
        inlineFiltersStack.arrangedSubviews.forEach {
            inlineFiltersStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard browseMode == .category,
              !isGlobal,
              submittedQuery.isEmpty,
              !hasNoInstalledSources,
              !scopeGroups.isEmpty else {
            inlineFiltersStack.isHidden = true
            return
        }

        let visibleIndices = DiscoveryModels.visibleInlineGroupIndices(scopeGroups, selectedFilters: filters)
        guard !visibleIndices.isEmpty else {
            inlineFiltersStack.isHidden = true
            return
        }

        let showExpand = DiscoveryModels.countValidFilterGroups(scopeGroups) > DiscoveryModels.inlineFilterMaxGroups
            || scopeGroups.contains { DiscoveryModels.shouldShowFilterExpand($0) }
        let selectedSource = currentSource
        let isRule = selectedSource is ScriptComicSource || selectedSource is FailoverComicSource

        for (displayRowIdx, groupIndex) in visibleIndices.enumerated() {
            let group = scopeGroups[groupIndex]
            let rowScroll = SourceOptionScrollView()
            rowScroll.showsHorizontalScrollIndicator = false
            rowScroll.translatesAutoresizingMaskIntoConstraints = false
            rowScroll.heightAnchor.constraint(equalToConstant: 32).isActive = true

            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 6
            rowStack.alignment = .center
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            rowScroll.addSubview(rowStack)
            NSLayoutConstraint.activate([
                rowStack.topAnchor.constraint(equalTo: rowScroll.topAnchor),
                rowStack.bottomAnchor.constraint(equalTo: rowScroll.bottomAnchor),
                rowStack.leadingAnchor.constraint(equalTo: rowScroll.leadingAnchor),
                rowStack.trailingAnchor.constraint(equalTo: rowScroll.trailingAnchor),
                rowStack.heightAnchor.constraint(equalTo: rowScroll.heightAnchor)
            ])

            let groupTitle = UILabel()
            groupTitle.text = group.label + ":"
            groupTitle.font = .systemFont(ofSize: 12, weight: .semibold)
            groupTitle.textColor = Palette.secondaryText
            rowStack.addArrangedSubview(groupTitle)

            let currentVal = filters[group.key] ?? ""
            let inlineOpts = DiscoveryModels.inlineOptionsForGroup(group, selectedValue: currentVal)
            for option in inlineOpts {
                let isSelected = (currentVal.isEmpty && option == group.options.first) || currentVal == option.value
                let chip = UIButton(type: .system)
                chip.setTitle(option.label, for: .normal)
                chip.titleLabel?.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
                chip.setTitleColor(isSelected ? Palette.onAccent : Palette.text, for: .normal)
                chip.backgroundColor = isSelected ? Palette.accent : Palette.surface
                chip.layer.cornerRadius = 13
                chip.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
                chip.accessibilityIdentifier = "discover.inline.\(group.key).\(option.value)"
                chip.addAction(UIAction { [weak self] _ in
                    guard let self, let src = self.currentSource else { return }
                    var updated = self.filters
                    var updatedLabels = self.filterLabels
                    SourceFilterSelection.select(
                        sourceID: src.id,
                        isRuleSource: isRule,
                        groups: self.scopeGroups,
                        selectedGroup: group,
                        selectedOption: option,
                        in: &updated,
                        labels: &updatedLabels
                    )
                    for depKey in src.dependentFilterKeys(group.key) {
                        updated.removeValue(forKey: depKey)
                        updatedLabels.removeValue(forKey: depKey)
                    }
                    self.filters = updated
                    self.filterLabels = updatedLabels
                    let refreshedGroups = src.filterGroupsForSelection(updated)
                    if !refreshedGroups.isEmpty {
                        self.scopeGroups = refreshedGroups
                    }
                    self.updateBrowseModePills()
                    self.renderInlineFilters()
                    self.start()
                }, for: .touchUpInside)
                rowStack.addArrangedSubview(chip)
            }

            if showExpand && displayRowIdx == visibleIndices.count - 1 {
                let moreBtn = UIButton(type: .system)
                let totalGroups = DiscoveryModels.countValidFilterGroups(scopeGroups)
                moreBtn.setTitle("更多筛选 (\(totalGroups))", for: .normal)
                moreBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
                moreBtn.setTitleColor(Palette.accentText, for: .normal)
                moreBtn.backgroundColor = Palette.accentSoft
                moreBtn.layer.cornerRadius = 13
                moreBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
                moreBtn.accessibilityIdentifier = "discover.inline.more"
                moreBtn.addAction(UIAction { [weak self] _ in
                    self?.openFilterDrawer(initialSection: 1)
                }, for: .touchUpInside)
                rowStack.addArrangedSubview(moreBtn)
            }

            inlineFiltersStack.addArrangedSubview(rowScroll)
        }

        inlineFiltersStack.isHidden = false
    }

    // MARK: - Actions & Search Mode

    @objc private func selectBrowseRecommend() {
        guard browseMode != .recommend else { return }
        browseMode = .recommend
        updateBrowseModePills()
        renderInlineFilters()
        start()
    }

    @objc private func selectBrowseCategory() {
        guard browseMode != .category else { return }
        browseMode = .category
        updateBrowseModePills()
        loadInlineFilters(for: currentSource)
        start()
    }

    @objc private func resetInlineFilters() {
        filters = [:]
        filterLabels = [:]
        updateBrowseModePills()
        renderInlineFilters()
        start()
    }

    @objc private func showSources() {
        searchBar.resignFirstResponder()
        let selectedId = currentSource?.id ?? ""
        let sheet = SourceChooserSheetController(
            environment: environment,
            selectedSourceId: selectedId,
            onSelectSource: { [weak self] chosen in
                guard let self else { return }
                let list = self.environment.discoverySources
                if let idx = list.firstIndex(where: { $0.id == chosen.id }) {
                    self.sourceIndex = idx
                } else {
                    self.sourceIndex = 0
                }
                self.filters = [:]
                self.filterLabels = [:]
                self.scopeSourceID = nil
                self.updateSourceMenu()
                if self.isGlobal {
                    self.globalMode = false
                    self.submittedQuery = ""
                    self.searchBar.text = nil
                }
                self.start()
            },
            onGroupChanged: { [weak self] in
                self?.sourcesChanged()
            },
            onManageSources: { [weak self] in
                self?.openSourceSettingsFromGuide()
            }
        )
        present(sheet, animated: false)
    }

    @objc private func showFilters() {
        openFilterDrawer(initialSection: 1)
    }

    private func openFilterDrawer(initialSection: Int) {
        let sources = environment.discoverySources
        guard let source = currentSource else { return }
        let initialGroupIndex = max(0, DiscoveryModels.firstCollapsedFilterTab(scopeGroups, selectedFilters: filters) - 1)
        let controller = FilterViewController(
            environment: environment,
            sources: sources,
            source: source,
            selected: filters,
            initialSection: initialSection,
            initialGroupIndex: initialGroupIndex
        ) { [weak self] selectedSourceID, selectedFilters in
            guard let self else { return }
            self.sourceIndex = self.environment.discoverySources.firstIndex(where: { $0.id == selectedSourceID }) ?? self.sourceIndex
            self.filters = selectedFilters
            let hasActive = !selectedFilters.values.filter { !$0.isEmpty && $0.lowercased() != "all" }.isEmpty
            if hasActive {
                self.browseMode = .category
            }
            self.scopeSourceID = nil
            self.updateSourceMenu()
            self.start()
        }
        present(FilterDrawerNavigationController(rootViewController: controller), animated: true)
    }

    @objc private func openSourceSettingsFromGuide() {
        let controller = SourceSettingsViewController(environment: environment)
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func modeChanged() {
        globalMode.toggle()
        updateSourceMenu()
        if !submittedQuery.isEmpty || !(searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            let q = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            submittedQuery = q
        }
        start(query: submittedQuery)
    }

    @objc private func handlePullToRefresh() {
        start(query: submittedQuery, restoringGlobalSourceID: isGlobal ? global.selectedSourceID : nil)
    }

    @objc private func discoveryDrag(_ gesture: UIPanGestureRecognizer) {
        guard gesture.numberOfTouches <= 1, !searchBar.isFirstResponder else {
            headerGesture.end()
            return
        }
        let point = gesture.location(in: nil)
        switch gesture.state {
        case .began:
            headerGesture.begin(x: point.x, y: point.y)
        case .changed:
            let direction = headerGesture.move(x: point.x, y: point.y)
            let canScroll = collection.contentSize.height > collection.bounds.height
                || collection.contentOffset.y > -collection.adjustedContentInset.top
            if direction < 0 && canScroll {
                setToolsHidden(true)
            } else if direction > 0 {
                setToolsHidden(false)
            }
        default:
            headerGesture.end()
        }
    }

    private func setToolsHidden(_ hidden: Bool, animated: Bool = true) {
        guard hidden != toolsHidden else { return }
        toolsHidden = hidden
        tools.accessibilityElementsHidden = hidden
        if hidden {
            searchBar.resignFirstResponder()
        }
        view.layoutIfNeeded()
        let update = {
            self.collapsedToolsHeight.isActive = hidden
            self.tools.alpha = hidden ? 0 : 1
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: update)
        } else {
            update()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let q = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        start(query: q)
        return true
    }

    @objc private func searchTextChanged() {
        let text = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && !submittedQuery.isEmpty {
            start(query: "")
        } else if isGlobal && text.isEmpty {
            refreshGlobal()
        }
    }

    // MARK: - Core Loading Pipeline

    private func cancelActiveRequests() {
        requestID = UUID()
        tasks.forEach { $0.cancel() }
        tasks = []
        pendingGlobalSources = []
        activeGlobalCount = 0
        globalCoalescer.cancel()
    }

    private func start(query: String = "", restoringGlobalSourceID: String? = nil) {
        cancelActiveRequests()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        submittedQuery = trimmed
        expandedGlobalSourceIDs.removeAll()
        rawSingleComics = []
        visibleSingleComics = []
        nextPage = 1
        loading = false
        ended = false
        singleErrorMessage = nil
        singleNeedsVerification = false
        setToolsHidden(false)

        let showGuide = hasNoInstalledSources
        emptySourcesGuide.isHidden = !showGuide
        collection.isHidden = showGuide
        updateBrowseModePills()

        guard !showGuide else {
            refreshControl.endRefreshing()
            applyRows([])
            return
        }

        if !trimmed.isEmpty {
            saveSearchHistoryTerm(trimmed)
        }

        if isGlobal {
            sectionHeading.isHidden = true
            inlineFiltersStack.isHidden = true
            if trimmed.isEmpty {
                tabs.isHidden = true
                refreshControl.endRefreshing()
                showGlobalSearchHistory()
                return
            }
            tabs.isHidden = false
            loadGlobal(restoringSelectedSourceID: restoringGlobalSourceID)
        } else {
            tabs.isHidden = true
            loadInlineFilters(for: currentSource)
            loadSingle()
        }
    }

    private func saveSearchHistoryTerm(_ term: String) {
        var saved = environment.defaults.stringArray(forKey: "global.search.history") ?? []
        saved.removeAll { $0 == term }
        saved.insert(term, at: 0)
        environment.defaults.set(Array(saved.prefix(20)), forKey: "global.search.history")
    }

    private func showGlobalSearchHistory() {
        let saved = environment.defaults.stringArray(forKey: "global.search.history") ?? []
        if saved.isEmpty {
            applyRows([.fullCustom("emptyGlobalPrompt")])
        } else {
            applyRows([.fullCustom("history")])
        }
    }

    private func loadSingle() {
        guard !loading, !ended, let source = currentSource else {
            refreshControl.endRefreshing()
            if currentSource == nil {
                applyRows([.fullCustom("noSources")])
            }
            return
        }

        guard submittedQuery.isEmpty || source.supportsSearch else {
            ended = true
            refreshControl.endRefreshing()
            applyRows([.fullCustom("unsupportedSearch")])
            return
        }

        loading = true
        singleErrorMessage = nil
        singleNeedsVerification = false

        if nextPage == 1 {
            applyRows([.fullCustom("skeleton")])
        } else {
            rebuildSingleRows()
        }

        let token = requestID
        let page = nextPage
        let query = submittedQuery
        let activeFilters = filters
        let mode = browseMode
        let hasActiveFilterValues = !activeFilters.values.filter { !$0.isEmpty && $0.lowercased() != "all" }.isEmpty

        tasks.append(Task { [weak self] in
            do {
                let rawResults: [ComicSummary]
                if !query.isEmpty {
                    rawResults = try await source.search(keyword: query, page: page)
                } else if mode == .recommend && !hasActiveFilterValues {
                    rawResults = try await source.latest(page: page)
                } else {
                    rawResults = try await source.category(filters: activeFilters, page: page)
                }
                try Task.checkCancellation()
                guard let self, self.requestID == token else { return }

                var seenIds = Set(self.rawSingleComics.map(\.comicId))
                let uniqueNew = rawResults.filter { seenIds.insert($0.comicId).inserted }
                self.rawSingleComics.append(contentsOf: uniqueNew)
                self.visibleSingleComics = self.environment.blacklistStore.filterSummaries(self.rawSingleComics)

                self.nextPage = page + 1
                let hasMore = !query.isEmpty
                    ? source.hasMoreSearchPage(rawResults)
                    : source.hasMoreCategoryPage(rawResults)
                self.ended = uniqueNew.isEmpty || !hasMore
                self.loading = false
                self.refreshControl.endRefreshing()
                self.rebuildSingleRows()
            } catch {
                guard let self, self.requestID == token, !Task.isCancelled else { return }
                self.loading = false
                self.refreshControl.endRefreshing()
                if (error as? Mh18SourceError) == .verificationRequired {
                    self.singleNeedsVerification = true
                    self.singleErrorMessage = "该站源需要验证"
                } else {
                    self.singleErrorMessage = (error is CancellationError) ? "已取消" : error.localizedDescription
                }
                self.rebuildSingleRows()
            }
        })
    }

    private func rebuildSingleRows() {
        var nextRows: [DiscoveryRowItem] = []
        let sourceId = currentSource?.id ?? ""

        if visibleSingleComics.isEmpty {
            if loading {
                nextRows.append(.fullCustom("skeleton"))
            } else if singleNeedsVerification {
                nextRows.append(.fullCustom("verifySingle"))
            } else if singleErrorMessage != nil {
                nextRows.append(.fullCustom("errorSingle"))
            } else {
                nextRows.append(.fullCustom("emptySingle"))
            }
            applyRows(nextRows)
            return
        }

        for comic in visibleSingleComics {
            nextRows.append(.poster(DiscoveryPosterRow(sectionSourceId: sourceId, comic: comic)))
        }

        let footerState: DiscoveryFooterState
        if loading {
            footerState = .loading
        } else if singleNeedsVerification {
            footerState = .verifyRequired
        } else if singleErrorMessage != nil {
            footerState = .errorRetry
        } else if ended {
            footerState = .end
        } else {
            footerState = .loadMore
        }
        nextRows.append(.footer(footerState))
        applyRows(nextRows)
    }

    // MARK: - Global Search Pipeline

    private func loadGlobal(restoringSelectedSourceID: String? = nil) {
        let searchSources = environment.searchSources
        if searchSources.isEmpty {
            refreshControl.endRefreshing()
            applyRows([.fullCustom("noSources")])
            return
        }

        currentGlobalGeneration = global.begin(
            query: submittedQuery,
            sourceIDs: searchSources.map(\.id),
            restoringSelectedSourceID: restoringSelectedSourceID,
            preferAllSources: true
        )
        errors = [:]
        finished = []
        globalCoalescer.beginSession()

        let byID = Dictionary(uniqueKeysWithValues: searchSources.map { ($0.id, $0) })
        let sortedIDs = GlobalSearchDispatchPolicy.shared.sortForDispatch(searchSources.map(\.id)) { id in
            environment.requiresVpn(sourceId: id)
        }
        pendingGlobalSources = sortedIDs.compactMap { byID[$0] }
        activeGlobalCount = 0

        refreshGlobal(forceImmediate: true)
        pumpGlobalDispatchQueue()
    }

    private func pumpGlobalDispatchQueue() {
        guard isGlobal, !submittedQuery.isEmpty else { return }
        guard !environment.isForegroundDetailBusy else { return }

        let token = requestID
        let generation = currentGlobalGeneration
        let query = submittedQuery

        while activeGlobalCount < GlobalSearchDispatchPolicy.maxConcurrency, !pendingGlobalSources.isEmpty {
            let source = pendingGlobalSources.removeFirst()
            activeGlobalCount += 1
            let timeoutMs = GlobalSearchDispatchPolicy.shared.timeoutMilliseconds(
                for: source.id,
                requiresVpn: environment.requiresVpn(sourceId: source.id)
            )
            let startedUptime = ProcessInfo.processInfo.systemUptime

            tasks.append(Task { [weak self] in
                defer {
                    if let self, self.requestID == token {
                        self.activeGlobalCount = max(0, self.activeGlobalCount - 1)
                        self.pumpGlobalDispatchQueue()
                    }
                }
                do {
                    let rawItems = try await withThrowingTaskGroup(of: [ComicSummary].self) { group in
                        group.addTask {
                            try await source.search(keyword: query, page: 1)
                        }
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(max(1000, timeoutMs)) * 1_000_000)
                            throw URLError(.timedOut)
                        }
                        let first = try await group.next() ?? []
                        group.cancelAll()
                        return first
                    }
                    try Task.checkCancellation()
                    let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - startedUptime) * 1000)
                    GlobalSearchDispatchPolicy.shared.recordSuccess(sourceID: source.id, elapsedMs: elapsedMs)
                    guard let self, self.requestID == token else { return }

                    self.finished.insert(source.id)
                    let isFinal = self.finished.count >= self.global.sourceIDs.count
                    _ = self.global.receive(sourceID: source.id, items: rawItems, generation: generation)
                    self.refreshGlobal(forceImmediate: isFinal)
                } catch {
                    if !Task.isCancelled {
                        GlobalSearchDispatchPolicy.shared.recordFailure(
                            sourceID: source.id,
                            timedOut: (error as? URLError)?.code == .timedOut
                        )
                    }
                    guard let self, self.requestID == token, !Task.isCancelled else { return }
                    self.errors[source.id] = error
                    self.finished.insert(source.id)
                    let isVerify = (error as? Mh18SourceError) == .verificationRequired
                    _ = self.global.recordFailure(sourceID: source.id, offerVerification: isVerify, generation: generation)
                    let isFinal = self.finished.count >= self.global.sourceIDs.count
                    self.refreshGlobal(forceImmediate: isFinal)
                }
            })
        }
    }

    private func refreshGlobal(forceImmediate: Bool = false) {
        if forceImmediate {
            globalCoalescer.flushNow { [weak self] in
                self?.renderGlobalStateNow()
            }
        } else {
            globalCoalescer.requestRefresh(forceImmediate: false) { [weak self] in
                self?.renderGlobalStateNow()
            }
        }
    }

    private func renderGlobalStateNow() {
        guard isGlobal else { return }
        refreshControl.endRefreshing()
        rebuildGlobalTabs()
        refreshGlobalRowsOnly()
    }

    private func rebuildGlobalTabs() {
        tabRow.arrangedSubviews.forEach {
            tabRow.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let blacklistStore = environment.blacklistStore
        let visibleIDs = global.visibleSourceIDs.filter { id in
            !(blacklistStore.filterSummaries(global.results[id] ?? [])).isEmpty
        }

        let totalDisplayed = visibleIDs.reduce(0) { sum, id in
            let filtered = blacklistStore.filterSummaries(global.results[id] ?? [])
            return sum + min(DiscoveryModels.globalMaxItemsPerSource, filtered.count)
        }

        let allSelected = (global.selectedSourceID ?? GlobalSearchState.allSourcesID) == GlobalSearchState.allSourcesID
        let allChip = makeGlobalChip(
            title: totalDisplayed > 0 ? "全部 \(totalDisplayed)" : "全部",
            selected: allSelected,
            identifier: "discover.global.all"
        ) { [weak self] in
            self?.global.select(GlobalSearchState.allSourcesID)
            self?.rebuildGlobalTabs()
            self?.refreshGlobalRowsOnly()
        }
        tabRow.addArrangedSubview(allChip)

        let nameByID = Dictionary(uniqueKeysWithValues: environment.searchSources.map { ($0.id, $0.name) })
        for id in visibleIDs {
            let filtered = blacklistStore.filterSummaries(global.results[id] ?? [])
            let selected = global.selectedSourceID == id
            let name = nameByID[id] ?? id
            let chip = makeGlobalChip(
                title: "\(name) \(filtered.count)",
                selected: selected,
                identifier: "discover.global.\(id)"
            ) { [weak self] in
                self?.global.select(id)
                self?.rebuildGlobalTabs()
                self?.refreshGlobalRowsOnly()
            }
            tabRow.addArrangedSubview(chip)
        }

        for id in global.verificationRequiredWithoutResultsSourceIDs {
            let selected = global.selectedSourceID == id
            let name = nameByID[id] ?? id
            let chip = makeGlobalChip(
                title: "\(name) · 需验证",
                selected: selected,
                identifier: "discover.global.\(id)"
            ) { [weak self] in
                self?.global.select(id)
                self?.rebuildGlobalTabs()
                self?.refreshGlobalRowsOnly()
            }
            tabRow.addArrangedSubview(chip)
        }
    }

    private func makeGlobalChip(title: String, selected: Bool, identifier: String, action: @escaping () -> Void) -> UIButton {
        let chip = UIButton(type: .system)
        chip.setTitle(title, for: .normal)
        chip.titleLabel?.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .medium)
        chip.setTitleColor(selected ? Palette.onAccent : Palette.text, for: .normal)
        chip.backgroundColor = selected ? Palette.accent : Palette.surface
        chip.layer.cornerRadius = 14
        chip.layer.borderWidth = 0.5
        chip.layer.borderColor = (selected ? Palette.accent : Palette.borderSoft).cgColor
        chip.contentEdgeInsets = UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11)
        chip.accessibilityIdentifier = identifier
        chip.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return chip
    }

    private func refreshGlobalRowsOnly() {
        guard isGlobal else { return }
        if submittedQuery.isEmpty {
            showGlobalSearchHistory()
            return
        }

        let sourceList = environment.searchSources
        let nameByID = Dictionary(uniqueKeysWithValues: sourceList.map { ($0.id, $0.name) })
        let blacklistStore = environment.blacklistStore
        let filteredResultsByID = global.results.mapValues { blacklistStore.filterSummaries($0) }

        var hitMetas: [DiscoverySourceMeta] = []
        for id in global.visibleSourceIDs {
            let filtered = filteredResultsByID[id] ?? []
            guard !filtered.isEmpty else { continue }
            let meta = DiscoverySourceMeta(
                id: id,
                name: nameByID[id] ?? id,
                requiresVpn: environment.requiresVpn(sourceId: id),
                hasExactMatch: SearchRules.hasExact(filtered, query: submittedQuery)
            )
            hitMetas.append(meta)
        }

        let verifyMetas: [DiscoverySourceMeta] = global.verificationRequiredWithoutResultsSourceIDs.map { id in
            DiscoverySourceMeta(
                id: id,
                name: nameByID[id] ?? id,
                requiresVpn: environment.requiresVpn(sourceId: id),
                hasExactMatch: false
            )
        }

        let selectedID = global.selectedSourceID ?? GlobalSearchState.allSourcesID
        var builtRows: [DiscoveryRowItem] = []

        if selectedID == GlobalSearchState.allSourcesID {
            for meta in hitMetas {
                let allItems = filteredResultsByID[meta.id] ?? []
                guard !allItems.isEmpty else { continue }
                let isExpanded = expandedGlobalSourceIDs.contains(meta.id)
                let shown = isExpanded ? allItems : DiscoveryModels.capGlobalItems(allItems)
                let actionLabel: String
                if allItems.count > DiscoveryModels.globalMaxItemsPerSource {
                    actionLabel = isExpanded ? "收起" : "全部 \(allItems.count) ›"
                } else {
                    actionLabel = "单站搜索 ›"
                }
                builtRows.append(.sectionHeader(DiscoverySectionHeaderRow(
                    sourceId: meta.id,
                    title: meta.name,
                    requiresVpn: meta.requiresVpn,
                    hasExactMatch: meta.hasExactMatch,
                    countBadge: "\(allItems.count) 部",
                    actionLabel: actionLabel,
                    actionType: .singleSearch
                )))
                for item in shown {
                    builtRows.append(.poster(DiscoveryPosterRow(sectionSourceId: meta.id, comic: item)))
                }
            }
            for verifyMeta in verifyMetas {
                builtRows.append(.sectionHeader(DiscoverySectionHeaderRow(
                    sourceId: verifyMeta.id,
                    title: verifyMeta.name,
                    requiresVpn: verifyMeta.requiresVpn,
                    hasExactMatch: false,
                    countBadge: "需验证",
                    actionLabel: "去验证 ›",
                    actionType: .verify
                )))
            }
        } else {
            let singleRows = DiscoveryModels.buildGlobalRows(
                selectedSourceId: selectedID,
                orderedHitSources: hitMetas,
                verificationSources: verifyMetas,
                resultsBySource: filteredResultsByID,
                query: submittedQuery
            )
            // In single-source chip view inside global search, show full non-capped list when available.
            if let allForSelected = filteredResultsByID[selectedID], !allForSelected.isEmpty,
               let header = singleRows.first(where: { if case .sectionHeader = $0 { return true }; return false }) {
                if case .sectionHeader(let h) = header {
                    builtRows.append(.sectionHeader(DiscoverySectionHeaderRow(
                        sourceId: h.sourceId,
                        title: h.title,
                        requiresVpn: h.requiresVpn,
                        hasExactMatch: h.hasExactMatch,
                        countBadge: "\(allForSelected.count) 部",
                        actionLabel: "单站搜索 ›",
                        actionType: .singleSearch
                    )))
                    for item in allForSelected {
                        builtRows.append(.poster(DiscoveryPosterRow(sectionSourceId: selectedID, comic: item)))
                    }
                }
            } else {
                builtRows.append(contentsOf: singleRows)
            }
        }

        let totalSources = global.sourceIDs.count
        let doneCount = finished.count
        if doneCount < totalSources {
            sectionHeading.text = "全站搜索中 (\(doneCount)/\(totalSources))..."
            sectionHeading.isHidden = false
        } else {
            sectionHeading.isHidden = true
        }

        if builtRows.isEmpty {
            if doneCount < totalSources {
                builtRows = [.fullCustom("skeleton")]
            } else {
                builtRows = [.fullCustom("emptyGlobal")]
            }
        } else if doneCount < totalSources {
            builtRows.append(.footer(.loading))
        }

        applyRows(builtRows)
    }

    private func applyRows(_ nextRows: [DiscoveryRowItem]) {
        if nextRows.count == 1, case .fullCustom(let key) = nextRows[0], key != "skeleton", key != "history" {
            switch key {
            case "noSources":
                stateOverlayView.configure(
                    title: "当前没有已启用的发现站源",
                    subtitle: "前往站源管理启用站源或调整分组",
                    buttonTitle: "管理站源",
                    statusAccessibilityLabel: "管理站源",
                    assetName: "rem_empty_discovery"
                ) { [weak self] in
                    self?.openSourceSettingsFromGuide()
                }
            case "unsupportedSearch":
                let name = currentSource?.name ?? ""
                let msg = name + "暂不支持搜索"
                stateOverlayView.configure(
                    title: msg,
                    subtitle: "请切换为全站搜索或选择支持搜索的站源",
                    buttonTitle: "切换站源",
                    statusAccessibilityLabel: msg,
                    assetName: "rem_empty_discovery"
                ) { [weak self] in
                    self?.showSources()
                }
            case "verifySingle":
                stateOverlayView.configure(
                    title: "需要验证",
                    subtitle: "该站源当前需要人机或网页验证",
                    buttonTitle: "去验证",
                    statusAccessibilityLabel: "需要验证 · 去验证",
                    assetName: nil
                ) { [weak self] in
                    guard let self else { return }
                    self.showSourceManagement(environment: self.environment) { [weak self] in
                        self?.loadSingle()
                    }
                }
            case "errorSingle":
                let msg = singleErrorMessage ?? "加载失败"
                stateOverlayView.configure(
                    title: msg,
                    subtitle: "请检查网络或切换其他站源重试",
                    buttonTitle: "点击重试",
                    statusAccessibilityLabel: msg,
                    assetName: nil
                ) { [weak self] in
                    self?.loadSingle()
                }
            case "emptyGlobal":
                stateOverlayView.configure(
                    title: "没有找到漫画",
                    subtitle: "尝试缩短关键词或切换其他站源重试",
                    buttonTitle: "重新搜索",
                    statusAccessibilityLabel: "没有找到漫画",
                    assetName: "rem_empty_search"
                ) { [weak self] in
                    self?.searchBar.becomeFirstResponder()
                }
            case "emptyGlobalPrompt":
                stateOverlayView.configure(
                    title: "输入关键词全站搜索",
                    subtitle: "将同时检索所有支持搜索的已启用站源",
                    buttonTitle: nil,
                    statusAccessibilityLabel: "输入关键词全站搜索",
                    assetName: "rem_empty_search",
                    onAction: nil
                )
            default:
                let title = submittedQuery.isEmpty ? "暂无漫画内容" : "没有找到漫画"
                stateOverlayView.configure(
                    title: title,
                    subtitle: submittedQuery.isEmpty ? "可下拉刷新或切换其他分类" : "尝试更换关键词或切换全站搜索",
                    buttonTitle: submittedQuery.isEmpty ? "重新加载" : nil,
                    statusAccessibilityLabel: title,
                    assetName: submittedQuery.isEmpty ? "rem_empty_discovery" : "rem_empty_search",
                    onAction: submittedQuery.isEmpty ? { [weak self] in self?.start() } : nil
                )
            }
            rows = []
            collection.backgroundView = stateOverlayView
            collection.reloadData()
        } else {
            collection.backgroundView = nil
            rows = nextRows
            collection.reloadData()
        }
    }

    // MARK: - Item Actions

    private func openDetail(_ comic: ComicSummary) {
        navigationController?.pushViewController(DetailViewController(comic: comic, environment: environment), animated: true)
    }

    private func switchToSingleSearch(sourceId: String) {
        let query = submittedQuery
        if let idx = environment.discoverySources.firstIndex(where: { $0.id == sourceId }) {
            sourceIndex = idx
        }
        globalMode = false
        filters = [:]
        filterLabels = [:]
        updateSourceMenu()
        start(query: query)
    }

    private func handleSectionAction(_ row: DiscoverySectionHeaderRow) {
        switch row.actionType {
        case .verify:
            showSourceManagement(environment: environment) { [weak self] in
                guard let self else { return }
                self.start(query: self.submittedQuery, restoringGlobalSourceID: self.global.selectedSourceID)
            }
        case .singleSearch:
            let selectedID = global.selectedSourceID ?? GlobalSearchState.allSourcesID
            let filteredCount = environment.blacklistStore.filterSummaries(global.results[row.sourceId] ?? []).count
            if selectedID == GlobalSearchState.allSourcesID && filteredCount > DiscoveryModels.globalMaxItemsPerSource {
                if expandedGlobalSourceIDs.contains(row.sourceId) {
                    expandedGlobalSourceIDs.remove(row.sourceId)
                } else {
                    expandedGlobalSourceIDs.insert(row.sourceId)
                }
                refreshGlobalRowsOnly()
            } else {
                switchToSingleSearch(sourceId: row.sourceId)
            }
        case .none:
            break
        }
    }

    private func presentQuickActions(for poster: DiscoveryPosterRow) {
        let comic = poster.comic
        let sourceName = environment.allSources.first(where: { $0.id == comic.sourceId })?.name ?? comic.sourceId
        let referer = environment.allSources.first(where: { $0.id == comic.sourceId })?.referer(forUrl: comic.coverUrl) ?? ""
        let isFavorite = environment.library.entry(for: comic)?.isFavorite == true

        let sheet = ComicQuickActionSheetController(
            comic: comic,
            sourceName: sourceName,
            referer: referer,
            library: environment.localLibrary,
            isFavorite: isFavorite,
            showNotInterested: false,
            allowRemoveFromShelf: false,
            onToggleFavorite: { [weak self] in
                guard let self else { return }
                do {
                    let next = !isFavorite
                    try self.environment.setFavorite(comic, favorite: next)
                    RemToastView.show(
                        message: next ? "已加入书架" : "已取消收藏",
                        kind: .info,
                        window: self.view.window
                    )
                } catch {
                    self.showError(error)
                }
            },
            onSwitchSource: { [weak self] in
                guard let self else { return }
                let switchSheet = SourceSwitchSheet(environment: self.environment, originalComic: comic) { [weak self] replacedDetail in
                    self?.openDetail(replacedDetail.summary)
                }
                self.present(UINavigationController(rootViewController: switchSheet), animated: true)
            },
            onBlacklist: { [weak self] in
                guard let self else { return }
                BlacklistConfirmHelper.presentAndAdd(
                    from: self,
                    environment: self.environment,
                    comic: comic,
                    sourceName: sourceName
                )
            }
        )
        present(sheet, animated: false)
    }

    private func referer(for comic: ComicSummary) -> String {
        environment.allSources.first(where: { $0.id == comic.sourceId })?.referer(forUrl: comic.coverUrl) ?? ""
    }

    private func sourceName(for comic: ComicSummary) -> String {
        environment.allSources.first(where: { $0.id == comic.sourceId })?.name ?? comic.sourceId
    }

    // MARK: - UICollectionViewDataSource & DelegateFlowLayout

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        rows.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = rows[indexPath.item]
        switch item {
        case .sectionHeader(let headerRow):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiscoverySectionHeaderCell.reuseId, for: indexPath) as? DiscoverySectionHeaderCell else {
                return UICollectionViewCell()
            }
            cell.configure(row: headerRow) { [weak self] in
                self?.handleSectionAction(headerRow)
            }
            return cell

        case .poster(let posterRow):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiscoveryPosterCell.reuseId, for: indexPath) as? DiscoveryPosterCell else {
                return UICollectionViewCell()
            }
            let showSourceBadge = isGlobal && (global.selectedSourceID ?? GlobalSearchState.allSourcesID) == GlobalSearchState.allSourcesID
            let badgeName = showSourceBadge ? sourceName(for: posterRow.comic) : nil
            cell.configure(
                comic: posterRow.comic,
                remark: posterRow.remark,
                sourceName: badgeName,
                referer: referer(for: posterRow.comic),
                library: environment.localLibrary
            ) { [weak self] in
                self?.presentQuickActions(for: posterRow)
            }
            return cell

        case .footer(let state):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiscoveryFooterCell.reuseId, for: indexPath) as? DiscoveryFooterCell else {
                return UICollectionViewCell()
            }
            cell.configure(state: state) { [weak self] in
                guard let self else { return }
                switch state {
                case .errorRetry, .loadMore:
                    self.loadSingle()
                case .verifyRequired:
                    self.showSourceManagement(environment: self.environment) { [weak self] in
                        self?.loadSingle()
                    }
                default:
                    break
                }
            }
            return cell

        case .fullCustom(let key):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiscoveryStateCell.reuseId, for: indexPath) as? DiscoveryStateCell else {
                return UICollectionViewCell()
            }
            let fullW = max(220, collectionView.bounds.width - DiscoveryLayoutMetrics.horizontalPadding * 2)
            let cols = DiscoveryLayoutMetrics.columns(forWidth: collectionView.bounds.width)
            switch key {
            case "skeleton":
                cell.configure(mode: .skeleton(columns: cols), availableWidth: fullW)
            case "noSources":
                cell.configure(mode: .noSources { [weak self] in
                    self?.openSourceSettingsFromGuide()
                }, availableWidth: fullW)
            case "unsupportedSearch":
                let name = currentSource?.name ?? ""
                let msg = name + "暂不支持搜索"
                cell.configure(mode: .empty(
                    title: msg,
                    subtitle: "请切换为全站搜索或选择支持搜索的站源",
                    buttonTitle: "切换站源",
                    statusAccessibilityLabel: msg,
                    assetName: "rem_empty_discovery",
                    onAction: { [weak self] in self?.showSources() }
                ), availableWidth: fullW)
            case "verifySingle":
                cell.configure(mode: .empty(
                    title: "需要验证",
                    subtitle: "该站源当前需要人机或网页验证",
                    buttonTitle: "去验证",
                    statusAccessibilityLabel: "需要验证 · 去验证",
                    assetName: nil,
                    onAction: { [weak self] in
                        guard let self else { return }
                        self.showSourceManagement(environment: self.environment) { [weak self] in
                            self?.loadSingle()
                        }
                    }
                ), availableWidth: fullW)
            case "errorSingle":
                let msg = singleErrorMessage ?? "加载失败"
                cell.configure(mode: .error(message: msg, retryTitle: "点击重试") { [weak self] in
                    self?.loadSingle()
                }, availableWidth: fullW)
            case "emptyGlobal":
                cell.configure(mode: .empty(
                    title: "没有找到漫画",
                    subtitle: "尝试缩短关键词或切换其他站源重试",
                    buttonTitle: "重新搜索",
                    statusAccessibilityLabel: "没有找到漫画",
                    assetName: "rem_empty_search",
                    onAction: { [weak self] in
                        self?.searchBar.becomeFirstResponder()
                    }
                ), availableWidth: fullW)
            case "emptyGlobalPrompt":
                cell.configure(mode: .empty(
                    title: "输入关键词全站搜索",
                    subtitle: "将同时检索所有支持搜索的已启用站源",
                    buttonTitle: nil,
                    statusAccessibilityLabel: "输入关键词全站搜索",
                    assetName: "rem_empty_search",
                    onAction: nil
                ), availableWidth: fullW)
            case "history":
                let terms = environment.defaults.stringArray(forKey: "global.search.history") ?? []
                cell.configure(mode: .searchHistory(
                    terms: terms,
                    onTapTerm: { [weak self] term in
                        self?.searchBar.text = term
                        self?.searchBar.resignFirstResponder()
                        self?.start(query: term)
                    },
                    onClear: { [weak self] in
                        self?.environment.defaults.removeObject(forKey: "global.search.history")
                        self?.showGlobalSearchHistory()
                    }
                ), availableWidth: fullW)
            default:
                let title = submittedQuery.isEmpty ? "暂无漫画内容" : "没有找到漫画"
                cell.configure(mode: .empty(
                    title: title,
                    subtitle: submittedQuery.isEmpty ? "可下拉刷新或切换其他分类" : "尝试更换关键词或切换全站搜索",
                    buttonTitle: submittedQuery.isEmpty ? "重新加载" : nil,
                    statusAccessibilityLabel: title,
                    assetName: submittedQuery.isEmpty ? "rem_empty_discovery" : "rem_empty_search",
                    onAction: submittedQuery.isEmpty ? { [weak self] in self?.start() } : nil
                ), availableWidth: fullW)
            }
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < rows.count else { return }
        if case .poster(let posterRow) = rows[indexPath.item] {
            openDetail(posterRow.comic)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let totalW = collectionView.bounds.width > 0 ? collectionView.bounds.width : UIScreen.main.bounds.width
        let fullW = max(200, totalW - DiscoveryLayoutMetrics.horizontalPadding * 2)
        switch rows[indexPath.item] {
        case .sectionHeader:
            return CGSize(width: fullW, height: 36)
        case .poster:
            let cardW = DiscoveryLayoutMetrics.cardWidth(forWidth: totalW)
            let showSourceBadge = isGlobal && (global.selectedSourceID ?? GlobalSearchState.allSourcesID) == GlobalSearchState.allSourcesID
            return CGSize(width: cardW, height: DiscoveryLayoutMetrics.posterCardHeight(forCardWidth: cardW, showSourceBadge: showSourceBadge))
        case .footer:
            return CGSize(width: fullW, height: 48)
        case .fullCustom(let key):
            if key == "skeleton" {
                let cardW = DiscoveryLayoutMetrics.cardWidth(forWidth: totalW)
                let coverH = ceil(cardW * 4.0 / 3.0)
                return CGSize(width: fullW, height: (coverH + 34) * 2 + 24)
            }
            if key == "history" {
                return CGSize(width: fullW, height: 220)
            }
            return CGSize(width: fullW, height: 260)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collection else { return }
        let dy = scrollView.contentOffset.y - lastScrollOffsetY
        lastScrollOffsetY = scrollView.contentOffset.y

        let visiblePaths = collection.indexPathsForVisibleItems.sorted()
        let firstVisible = visiblePaths.first?.item ?? 0
        let cols = DiscoveryLayoutMetrics.columns(forWidth: collection.bounds.width)
        backToTopButton.updateScrollState(
            scrollView: scrollView,
            dy: dy,
            firstVisibleIndex: firstVisible,
            spanCount: cols,
            isMixedFullSpanList: isGlobal
        )

        guard !isGlobal,
              scrollView.isDragging || scrollView.isDecelerating,
              scrollView.panGestureRecognizer.translation(in: scrollView).y < 0,
              scrollView.contentOffset.y > -scrollView.adjustedContentInset.top,
              scrollView.contentOffset.y + scrollView.bounds.height >= scrollView.contentSize.height - 140 else {
            return
        }
        loadSingle()
    }
}

// MARK: - FilterViewController (Android 2.0.56 Exclusive-Group Category Drawer)

@MainActor
private final class FilterViewController: UIViewController {
    private let environment: AppEnvironment
    private var needsVerification = false
    let sources: [any ComicSource]
    var source: any ComicSource
    var selected: [String: String]
    let onSelect: (String, [String: String]) -> Void

    private var draftSource: any ComicSource
    private var draftSelected: [String: String]
    private var draftLabels: [String: String] = [:]
    private var draftGroups: [SourceFilterGroup] = []
    private var activeSection: Int
    private var activeGroupIndex: Int = 0
    private var task: Task<Void, Never>?

    private let sectionSegment = UIStackView()
    private let sectionButtons = [UIButton(type: .system), UIButton(type: .system)]
    private let tabs = UIStackView()
    private let tabScroll = SourceOptionScrollView()
    private var tabHeight: NSLayoutConstraint?
    private let options = UIStackView()
    private let state = UIButton(type: .system)
    private let sourceDescription = UILabel()
    private let stateRow = UIStackView()
    private let confirmButton = UIButton(type: .system)
    private var dragStartHeight: CGFloat = 400

    init(
        environment: AppEnvironment,
        sources: [any ComicSource],
        source: any ComicSource,
        selected: [String: String],
        initialSection: Int,
        initialGroupIndex: Int,
        onSelect: @escaping (String, [String: String]) -> Void
    ) {
        self.environment = environment
        self.sources = sources
        self.source = source
        self.selected = selected
        self.draftSource = source
        self.draftSelected = selected
        self.activeSection = initialSection
        self.activeGroupIndex = initialGroupIndex
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "站源与分类"
        view.backgroundColor = Palette.card

        let sheetHeader = UIView()
        let grip = UIView()
        let heading = UILabel()
        let closeButton = UIButton(type: .system)

        grip.backgroundColor = Palette.border
        grip.layer.cornerRadius = 2
        heading.text = title
        heading.font = .systemFont(ofSize: 17, weight: .bold)
        heading.textColor = Palette.text
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16)), for: .normal)
        closeButton.tintColor = Palette.text3
        closeButton.accessibilityIdentifier = "filter.close"
        closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        for child in [grip, heading, closeButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            sheetHeader.addSubview(child)
        }
        sheetHeader.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHeader(_:))))

        sectionSegment.axis = .horizontal
        sectionSegment.spacing = 8
        sectionSegment.distribution = .fillEqually
        for (index, button) in sectionButtons.enumerated() {
            button.tag = index
            button.accessibilityIdentifier = "filter.section.\(index)"
            button.addTarget(self, action: #selector(sectionChanged(_:)), for: .touchUpInside)
            sectionSegment.addArrangedSubview(button)
        }

        let scroll = SourceOptionScrollView()
        scroll.accessibilityIdentifier = "filter.options"
        tabs.axis = .horizontal
        tabs.spacing = 8
        options.axis = .vertical
        options.spacing = 8

        state.titleLabel?.numberOfLines = 0
        state.titleLabel?.font = .systemFont(ofSize: 12)
        state.contentHorizontalAlignment = .leading
        state.setTitleColor(Palette.text3, for: .normal)
        state.setTitleColor(Palette.text3, for: .disabled)
        state.addTarget(self, action: #selector(stateTapped), for: .touchUpInside)

        sourceDescription.font = .systemFont(ofSize: 12)
        sourceDescription.textColor = Palette.text3
        sourceDescription.numberOfLines = 0
        stateRow.axis = .vertical
        stateRow.spacing = 4
        stateRow.addArrangedSubview(sourceDescription)
        stateRow.addArrangedSubview(state)
        let retryHeight = state.heightAnchor.constraint(equalToConstant: 44)
        retryHeight.priority = .init(999)
        retryHeight.isActive = true

        confirmButton.configuration = .filled()
        confirmButton.configuration?.baseBackgroundColor = Palette.accent
        confirmButton.configuration?.baseForegroundColor = .white
        confirmButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: 15, weight: .medium)
            return updated
        }
        confirmButton.configuration?.cornerStyle = .fixed
        confirmButton.configuration?.background.cornerRadius = 8
        confirmButton.setTitle("应用", for: .normal)
        confirmButton.accessibilityIdentifier = "filter.confirm"
        confirmButton.addTarget(self, action: #selector(done), for: .touchUpInside)

        for item in [sheetHeader, sectionSegment, tabScroll, scroll, stateRow, confirmButton] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabScroll.addSubview(tabs)
        options.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(options)
        tabHeight = tabScroll.heightAnchor.constraint(equalToConstant: 42)
        tabHeight?.isActive = true

        NSLayoutConstraint.activate([
            sheetHeader.topAnchor.constraint(equalTo: view.topAnchor),
            sheetHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetHeader.heightAnchor.constraint(equalToConstant: 56),
            grip.topAnchor.constraint(equalTo: sheetHeader.topAnchor, constant: 10),
            grip.centerXAnchor.constraint(equalTo: sheetHeader.centerXAnchor),
            grip.widthAnchor.constraint(equalToConstant: 36),
            grip.heightAnchor.constraint(equalToConstant: 4),
            heading.leadingAnchor.constraint(equalTo: sheetHeader.leadingAnchor, constant: 16),
            heading.bottomAnchor.constraint(equalTo: sheetHeader.bottomAnchor, constant: -6),
            closeButton.trailingAnchor.constraint(equalTo: sheetHeader.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            sectionSegment.topAnchor.constraint(equalTo: sheetHeader.bottomAnchor, constant: 4),
            sectionSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sectionSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            sectionSegment.heightAnchor.constraint(equalToConstant: 36),

            tabScroll.topAnchor.constraint(equalTo: sectionSegment.bottomAnchor, constant: 8),
            tabScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tabScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tabs.topAnchor.constraint(equalTo: tabScroll.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: tabScroll.bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: tabScroll.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: tabScroll.trailingAnchor),
            tabs.heightAnchor.constraint(equalTo: tabScroll.heightAnchor),

            scroll.topAnchor.constraint(equalTo: tabScroll.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            options.topAnchor.constraint(equalTo: scroll.topAnchor),
            options.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            options.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            options.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            options.widthAnchor.constraint(equalTo: scroll.widthAnchor),

            stateRow.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            stateRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stateRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            confirmButton.topAnchor.constraint(equalTo: stateRow.bottomAnchor, constant: 10),
            confirmButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            confirmButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            confirmButton.heightAnchor.constraint(equalToConstant: 46)
        ])

        renderSectionButtons()
        loadGroups(for: draftSource)
    }

    @objc private func sectionChanged(_ sender: UIButton) {
        activeSection = sender.tag
        renderSectionButtons()
        render()
    }

    @objc private func stateTapped() {
        if needsVerification {
            showSourceManagement(environment: environment) { [weak self] in
                guard let self else { return }
                self.loadGroups(for: self.draftSource)
            }
        } else {
            loadGroups(for: draftSource)
        }
    }

    private func renderSectionButtons() {
        let titles = ["站源", "分类"]
        for (index, button) in sectionButtons.enumerated() {
            let active = index == activeSection
            var config = UIButton.Configuration.filled()
            config.title = titles[index]
            config.baseBackgroundColor = active ? Palette.accent : Palette.surface
            config.baseForegroundColor = active ? Palette.onAccent : Palette.secondaryText
            config.cornerStyle = .fixed
            config.background.cornerRadius = 8
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = .systemFont(ofSize: 13, weight: active ? .bold : .medium)
                return updated
            }
            button.configuration = config
            button.isSelected = active
        }
    }

    private func loadGroups(for candidate: any ComicSource) {
        task?.cancel()
        needsVerification = false
        let dynamic = candidate.filterGroupsForSelection(draftSelected)
        if !dynamic.isEmpty {
            draftGroups = dynamic
            updateState()
            render()
            return
        }
        draftGroups = []
        state.isEnabled = false
        state.setTitle("正在加载分类…", for: .normal)
        render()
        let targetID = candidate.id
        task = Task { [weak self] in
            do {
                let groups = try await candidate.filterGroups()
                try Task.checkCancellation()
                guard let self, self.draftSource.id == targetID else { return }
                let refreshed = candidate.filterGroupsForSelection(self.draftSelected)
                self.draftGroups = refreshed.isEmpty ? groups : refreshed
                self.updateState()
                self.render()
            } catch {
                guard let self, !Task.isCancelled, self.draftSource.id == targetID else { return }
                self.needsVerification = (error as? Mh18SourceError) == .verificationRequired
                let errorText = self.needsVerification ? "需要验证 · 点击去验证" : (error.localizedDescription + " · 点击重试")
                self.state.isEnabled = true
                self.state.setTitle(errorText, for: .normal)
                self.render()
            }
        }
    }

    private func updateState() {
        state.isEnabled = false
        let mutexNote = SourceFilterSelection.filterMutexNote(draftGroups)
        let activeDesc = draftGroups.isEmpty
            ? "当前站源暂无可用分类筛选"
            : "\(draftSource.name)：支持 \(draftGroups.count) 组筛选"
        sourceDescription.text = mutexNote.map { "\(activeDesc) · \($0)" } ?? activeDesc
        state.setTitle("", for: .normal)
    }

    private func render() {
        tabs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        options.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let isSourceMode = activeSection == 0

        tabScroll.isHidden = isSourceMode
        tabHeight?.constant = isSourceMode ? 0 : 42

        if isSourceMode {
            updateState()
            renderSources()
            return
        }

        guard !draftGroups.isEmpty else {
            return
        }
        if activeGroupIndex >= draftGroups.count { activeGroupIndex = 0 }

        let partialMutex = SourceFilterSelection.isPartialMutexFilterSchema(draftGroups)
        for (index, group) in draftGroups.enumerated() {
            let button = UIButton(type: .system)
            var titleText = group.label
            if partialMutex && !group.exclusiveGroup.isEmpty {
                titleText += " (互斥)"
            }
            let active = index == activeGroupIndex
            var config = UIButton.Configuration.filled()
            config.title = titleText
            config.baseBackgroundColor = active ? Palette.accentSoft : Palette.surface
            config.baseForegroundColor = active ? Palette.accentText : Palette.secondaryText
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = .systemFont(ofSize: 13, weight: active ? .bold : .medium)
                return updated
            }
            button.configuration = config
            button.tag = index
            button.accessibilityIdentifier = "filter.group.\(group.key)"
            button.addTarget(self, action: #selector(groupTabTapped(_:)), for: .touchUpInside)
            tabs.addArrangedSubview(button)
        }

        renderOptions(for: draftGroups[activeGroupIndex], groupIndex: activeGroupIndex)
    }

    @objc private func groupTabTapped(_ sender: UIButton) {
        activeGroupIndex = sender.tag
        render()
    }

    private func renderSources() {
        for candidate in sources {
            let selected = candidate.id == draftSource.id
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = candidate.name
            config.baseBackgroundColor = selected ? Palette.accentSoft : Palette.surface
            config.baseForegroundColor = selected ? Palette.accentText : Palette.text
            config.cornerStyle = .fixed
            config.background.cornerRadius = 8
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = .systemFont(ofSize: 14, weight: selected ? .bold : .medium)
                return updated
            }
            button.configuration = config
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "filter.source.\(candidate.id)"
            button.accessibilityLabel = candidate.name
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                if self.draftSource.id != candidate.id {
                    self.draftSource = candidate
                    self.draftSelected = [:]
                    self.draftLabels = [:]
                    self.activeGroupIndex = 0
                    self.loadGroups(for: candidate)
                }
            }, for: .touchUpInside)
            options.addArrangedSubview(button)
        }
    }

    private func renderOptions(for group: SourceFilterGroup, groupIndex: Int) {
        let current = draftSelected[group.key] ?? ""
        let isRule = draftSource is ScriptComicSource || draftSource is FailoverComicSource

        for (optIndex, option) in group.options.enumerated() {
            let selected = (current.isEmpty && optIndex == 0) || current == option.value
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = option.label
            config.baseBackgroundColor = selected ? Palette.accentSoft : Palette.surface
            config.baseForegroundColor = selected ? Palette.accentText : Palette.text
            config.cornerStyle = .fixed
            config.background.cornerRadius = 8
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = .systemFont(ofSize: 14, weight: selected ? .bold : .medium)
                return updated
            }
            button.configuration = config
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "filter.option.\(groupIndex).\(optIndex)"
            button.accessibilityLabel = option.label
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                SourceFilterSelection.select(
                    sourceID: self.draftSource.id,
                    isRuleSource: isRule,
                    groups: self.draftGroups,
                    selectedGroup: group,
                    selectedOption: option,
                    in: &self.draftSelected,
                    labels: &self.draftLabels
                )
                for depKey in self.draftSource.dependentFilterKeys(group.key) {
                    self.draftSelected.removeValue(forKey: depKey)
                    self.draftLabels.removeValue(forKey: depKey)
                }
                let refreshed = self.draftSource.filterGroupsForSelection(self.draftSelected)
                if !refreshed.isEmpty {
                    self.draftGroups = refreshed
                }
                self.updateState()
                self.render()
            }, for: .touchUpInside)
            options.addArrangedSubview(button)
        }
    }

    @objc private func dragHeader(_ gesture: UIPanGestureRecognizer) {
        let hostHeight = view.window?.bounds.height ?? 700
        let currentH = navigationController?.preferredContentSize.height ?? 420
        switch gesture.state {
        case .began:
            dragStartHeight = currentH > 0 ? currentH : 420
        case .changed:
            let y = gesture.translation(in: view).y
            let nextH = max(240, min(hostHeight * 0.78, dragStartHeight - y))
            navigationController?.preferredContentSize = CGSize(width: 0, height: nextH)
        case .ended, .cancelled:
            if gesture.translation(in: view).y > 120 || gesture.velocity(in: view).y > 800 {
                dismiss(animated: true)
            }
        default:
            break
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func done() {
        onSelect(draftSource.id, draftSelected)
        dismiss(animated: true)
    }
}
