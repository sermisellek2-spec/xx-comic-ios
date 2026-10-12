import UIKit
import ComicCore

@MainActor
final class DiscoverViewController: ComicGridViewController, UITextFieldDelegate {
    private let searchBar = UISearchTextField()
    private let modeButton = UIButton(type: .system)
    private var globalMode = false
    private let sourceButton = UIButton(type: .system)
    private var sourceButtonWidth: NSLayoutConstraint?
    private let filterButton = UIButton(type: .system)
    private let filterScroll = SourceOptionScrollView()
    private let filterRow = UIStackView()
    private let sectionHeading = UILabel()
    private weak var searchOutline: UIView?
    private var scopeGroups: [SourceFilterGroup] = []
    private var scopeSourceID: String?
    private var scopeRequestID = UUID()
    private var scopeTask: Task<Void, Never>?
    private let tabs = SourceOptionScrollView()
    private let tabRow = UIStackView()
    private let history = UIStackView()
    private let tools = UIStackView()
    private let toolsHost = UIView()
    private var collapsedToolsHeight: NSLayoutConstraint!
    private var toolsHidden = false
    private var headerGesture = DiscoveryHeaderGesture()
    private var sourceIndex = 0
    private var sourceIDs: [String] = []
    private var filters: [String: String] = [:]
    private var requestID = UUID()
    private var tasks: [Task<Void, Never>] = []
    private var global = GlobalSearchState()
    private var errors: [String: Error] = [:]
    private var finished = Set<String>()
    private var nextPage = 1
    private var loading = false
    private var ended = false
    private var submittedQuery = ""
    private var needsReload = false
    private var isGlobal: Bool { globalMode }
    override var usesDiscoveryLayout: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourceIDs = environment.discoverySources.map(\.id)
        NotificationCenter.default.addObserver(self, selector: #selector(sourcesChanged), name: AppEnvironment.sourcesChanged, object: environment)
        title = "发现"
        tools.axis = .vertical; tools.spacing = 2
        header.layoutMargins = UIEdgeInsets(top: 6, left: 16, bottom: 0, right: 16)
        if let layout = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.sectionInset.top = 0; layout.sectionInset.left = 16; layout.sectionInset.right = 16
            layout.minimumInteritemSpacing = 8
            layout.minimumLineSpacing = 6
        }
        tools.accessibilityIdentifier = "discover.tools"
        tools.translatesAutoresizingMaskIntoConstraints = false
        toolsHost.clipsToBounds = true; toolsHost.addSubview(tools)
        let bottom = tools.bottomAnchor.constraint(equalTo: toolsHost.bottomAnchor)
        // Content keeps its own dimensions while the host animates to zero.
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([tools.topAnchor.constraint(equalTo: toolsHost.topAnchor),
            tools.leadingAnchor.constraint(equalTo: toolsHost.leadingAnchor),
            tools.trailingAnchor.constraint(equalTo: toolsHost.trailingAnchor), bottom])
        collapsedToolsHeight = toolsHost.heightAnchor.constraint(equalToConstant: 0)
        header.addArrangedSubview(toolsHost)
        collection.panGestureRecognizer.addTarget(self, action: #selector(discoveryDrag(_:)))
        searchBar.delegate = self
        searchBar.backgroundColor = .clear; searchBar.borderStyle = .none
        searchBar.font = .systemFont(ofSize: 14); searchBar.textColor = Palette.text
        searchBar.returnKeyType = .search; searchBar.clearButtonMode = .whileEditing
        searchBar.accessibilityIdentifier = "discover.search"
        searchBar.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        let searchIcon = UIImageView(image: ParityIcon.search.image(size: 22))
        searchIcon.tintColor = Palette.text3; searchIcon.contentMode = .center
        searchIcon.frame = CGRect(x: 0, y: 0, width: 40, height: 42)
        searchBar.leftView = searchIcon; searchBar.leftViewMode = .always
        modeButton.accessibilityIdentifier = "discover.search.mode"
        modeButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        modeButton.tintColor = Palette.accent
        modeButton.addTarget(self, action: #selector(modeChanged), for: .touchUpInside)
        let searchContainer = UIStackView(arrangedSubviews: [searchBar, modeButton])
        searchContainer.alignment = .center; searchContainer.backgroundColor = Palette.card
        searchContainer.layer.cornerRadius = 8; searchContainer.layer.borderWidth = 1
        searchContainer.layer.borderColor = Palette.border.resolvedColor(with: traitCollection).cgColor
        searchContainer.accessibilityIdentifier = "discover.search.container"
        searchOutline = searchContainer
        searchContainer.isLayoutMarginsRelativeArrangement = true
        searchContainer.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        searchContainer.heightAnchor.constraint(equalToConstant: 42).isActive = true
        searchBar.heightAnchor.constraint(equalToConstant: 42).isActive = true
        modeButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        modeButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        tools.addArrangedSubview(searchContainer)
        sourceButton.addTarget(self, action: #selector(showSources), for: .touchUpInside)
        sourceButton.accessibilityIdentifier = "discover.source"
        sourceButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        sourceButtonWidth = sourceButton.widthAnchor.constraint(equalToConstant: 44)
        sourceButtonWidth?.isActive = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: sourceButton)
        configureFilterButton(filterButton, title: "分类")
        filterButton.addTarget(self, action: #selector(showFilters), for: .touchUpInside)
        filterRow.axis = .horizontal; filterRow.spacing = 14; filterRow.alignment = .center
        filterRow.translatesAutoresizingMaskIntoConstraints = false; filterScroll.addSubview(filterRow)
        filterScroll.showsHorizontalScrollIndicator = false
        NSLayoutConstraint.activate([
            filterScroll.heightAnchor.constraint(equalToConstant: 28),
            filterRow.leadingAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.leadingAnchor),
            filterRow.trailingAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.trailingAnchor),
            filterRow.topAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.topAnchor),
            filterRow.bottomAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.bottomAnchor),
            filterRow.heightAnchor.constraint(equalTo: filterScroll.frameLayoutGuide.heightAnchor)
        ])
        tools.addArrangedSubview(filterScroll)
        sectionHeading.font = .systemFont(ofSize: 16, weight: .bold); sectionHeading.textColor = Palette.text
        sectionHeading.accessibilityIdentifier = "discover.section"
        sectionHeading.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        tools.addArrangedSubview(sectionHeading)
        tools.addArrangedSubview(tabs)
        tabs.showsHorizontalScrollIndicator = false
        tabRow.axis = .horizontal; tabRow.spacing = 6
        tabRow.translatesAutoresizingMaskIntoConstraints = false; tabs.addSubview(tabRow)
        let tabsHeight = tabs.heightAnchor.constraint(equalToConstant: 38)
        tabsHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            tabsHeight,
            tabRow.leadingAnchor.constraint(equalTo: tabs.contentLayoutGuide.leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: tabs.contentLayoutGuide.trailingAnchor),
            tabRow.topAnchor.constraint(equalTo: tabs.contentLayoutGuide.topAnchor),
            tabRow.bottomAnchor.constraint(equalTo: tabs.contentLayoutGuide.bottomAnchor),
            tabRow.heightAnchor.constraint(equalTo: tabs.frameLayoutGuide.heightAnchor)
        ])
        history.axis = .vertical
        history.spacing = 4
        tools.addArrangedSubview(history)
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshResults), for: .valueChanged)
        collection.refreshControl = refresh
        collection.keyboardDismissMode = .onDrag
        start()
    }
    deinit { tasks.forEach { $0.cancel() }; scopeTask?.cancel() }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        headerGesture.end()
        if presentedViewController != nil { return }
        needsReload = loading || (isGlobal && !submittedQuery.isEmpty && finished.count < environment.searchSources.count)
        requestID = UUID(); tasks.forEach { $0.cancel() }; tasks = []
        scopeTask?.cancel(); scopeSourceID = nil; scopeRequestID = UUID()
        loading = false
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if needsReload {
            needsReload = false
            start(query: submittedQuery, restoringGlobalSourceID: isGlobal ? global.selectedSourceID : nil)
        } else { updateSourceMenu() }
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        searchOutline?.layer.borderColor = Palette.border.resolvedColor(with: traitCollection).cgColor
    }
    private func updateSourceMenu() {
        filterButton.isEnabled = !environment.discoverySources.isEmpty
        sourceButton.isEnabled = !environment.discoverySources.isEmpty
        modeButton.setTitle(isGlobal ? "全站" : "单站", for: .normal)
        modeButton.accessibilityLabel = "切换搜索模式，当前" + (isGlobal ? "全站" : "单站")
        modeButton.accessibilityValue = isGlobal ? "全站" : "单站"
        guard !environment.discoverySources.isEmpty else {
            var configuration = sourceButton.configuration ?? .plain()
            configuration.title = "没有已启用的站源"; configuration.image = nil
            sourceButton.configuration = configuration
            updateSourceControlSize()
            updateSearchPlaceholder(isGlobal ? "搜索全部站源" : "搜索漫画")
            scopeTask?.cancel(); scopeSourceID = nil; scopeGroups = []; renderScopeGroups()
            return
        }
        let name = environment.discoverySources.indices.contains(sourceIndex) ? environment.discoverySources[sourceIndex].name : (environment.discoverySources.first?.name ?? "")
        var config = UIButton.Configuration.plain()
        config.title = name; config.image = ParityIcon.chevronDown.image(size: 16)
        config.imagePlacement = .trailing; config.imagePadding = 6
        config.baseForegroundColor = Palette.accent; config.contentInsets = .zero
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var result = $0; result.font = .systemFont(ofSize: 12, weight: .bold); return result }
        sourceButton.configuration = config
        updateSourceControlSize()
        updateSearchPlaceholder(isGlobal ? "搜索全部站源" : "搜索" + name)
        loadScopeGroups()
    }
    private func updateSourceControlSize() {
        sourceButton.invalidateIntrinsicContentSize()
        sourceButtonWidth?.constant = max(44, min(sourceButton.intrinsicContentSize.width, max(44, view.bounds.width - 140)))
        // Reinstall the item after its title changes so UINavigationBar does
        // not retain the previous custom view's compressed fitting size.
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: sourceButton)
    }
    private func updateSearchPlaceholder(_ text: String) {
        searchBar.attributedPlaceholder = NSAttributedString(string: text, attributes: [
            .foregroundColor: Palette.text3,
            .font: UIFont.systemFont(ofSize: 14)
        ])
    }
    private func configureFilterButton(_ button: UIButton, title: String) {
        var config = UIButton.Configuration.plain()
        config.title = title; config.image = ParityIcon.chevronDown.image(size: 14)
        config.imagePlacement = .trailing; config.imagePadding = 6
        config.baseForegroundColor = Palette.text3
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var result = $0; result.font = .systemFont(ofSize: 12, weight: .bold); return result }
        button.configuration = config
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    private func renderScopeGroups() {
        filterRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if scopeGroups.isEmpty { filterRow.addArrangedSubview(filterButton); return }
        for (index, group) in scopeGroups.enumerated() {
            let button = UIButton(type: .system)
            configureFilterButton(button, title: group.label)
            button.accessibilityIdentifier = "discover.filter." + group.key
            button.addAction(UIAction { [weak self] _ in self?.showFilterDrawer(initialSection: 1, initialGroupIndex: index) }, for: .touchUpInside)
            filterRow.addArrangedSubview(button)
        }
    }
    private func loadScopeGroups() {
        guard !isGlobal, environment.discoverySources.indices.contains(sourceIndex) else { return }
        let candidate = environment.discoverySources[sourceIndex]
        guard scopeSourceID != candidate.id else { return }
        scopeTask?.cancel(); scopeRequestID = UUID()
        let token = scopeRequestID
        scopeSourceID = candidate.id; scopeGroups = []
        configureFilterButton(filterButton, title: "分类"); renderScopeGroups()
        scopeTask = Task { [weak self, candidate] in
            do {
                let groups = try await candidate.filterGroups()
                try Task.checkCancellation()
                guard let self, self.scopeRequestID == token else { return }
                self.scopeGroups = groups; self.renderScopeGroups()
            } catch {
                guard let self, self.scopeRequestID == token, !Task.isCancelled else { return }
                self.scopeSourceID = nil
                self.configureFilterButton(self.filterButton, title: "分类加载失败，重试")
                self.renderScopeGroups()
            }
        }
    }
    @objc private func sourcesChanged() {
        scopeTask?.cancel(); scopeRequestID = UUID(); scopeSourceID = nil; scopeGroups = []
        let selectedGlobalSourceID = global.selectedSourceID
        let previous = sourceIDs.indices.contains(sourceIndex) ? sourceIDs[sourceIndex] : nil
        sourceIDs = environment.discoverySources.map(\.id)
        if let previous, let index = sourceIDs.firstIndex(of: previous) { sourceIndex = index }
        else { sourceIndex = 0; filters = [:] }
        requestID = UUID(); tasks.forEach { $0.cancel() }; tasks = []
        loading = false
        updateSourceMenu()
        if viewIfLoaded?.window != nil { start(query: submittedQuery, restoringGlobalSourceID: selectedGlobalSourceID) }
        else { needsReload = true }
    }
    @objc private func modeChanged() { globalMode.toggle(); start() }
    @objc private func refreshResults() { start() }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); start(); return true }
    @objc private func searchTextChanged() { if searchBar.text?.isEmpty == true { start() } }

    @objc private func discoveryDrag(_ gesture: UIPanGestureRecognizer) {
        guard gesture.numberOfTouches <= 1, !searchBar.isFirstResponder else { headerGesture.end(); return }
        let point = gesture.location(in: nil)
        switch gesture.state {
        case .began: headerGesture.begin(x: Double(point.x), y: Double(point.y))
        case .changed:
            let direction = headerGesture.move(x: Double(point.x), y: Double(point.y))
            let canScroll = collection.contentSize.height > collection.bounds.height || collection.contentOffset.y > -collection.adjustedContentInset.top
            if direction < 0 && canScroll { setToolsHidden(true, animated: true) }
            else if direction > 0 { setToolsHidden(false, animated: true) }
        default: headerGesture.end()
        }
    }
    private func setToolsHidden(_ hidden: Bool, animated: Bool) {
        guard hidden != toolsHidden else { return }
        toolsHidden = hidden
        tools.accessibilityElementsHidden = hidden
        let anchor = captureAnchor()
        view.layoutIfNeeded()
        let update = {
            self.collapsedToolsHeight.isActive = hidden
            self.tools.alpha = hidden ? 0 : 1
            self.view.layoutIfNeeded()
            self.restoreAnchor(anchor)
        }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: update)
        } else { update() }
    }

    private func start(query: String? = nil, restoringGlobalSourceID: String? = nil) {
        setToolsHidden(false, animated: false)
        requestID = UUID()
        tasks.forEach { $0.cancel() }; tasks = []
        loading = false; ended = false; nextPage = 1
        comics = []; collection.reloadData()
        submittedQuery = query ?? SearchRules.trim(searchBar.text ?? "")
        updateSourceMenu()
        history.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sourceButton.isHidden = isGlobal; filterScroll.isHidden = isGlobal
        sectionHeading.text = submittedQuery.isEmpty ? "全部漫画" : "搜索结果"
        sectionHeading.isHidden = isGlobal && submittedQuery.isEmpty
        tabs.isHidden = !isGlobal || submittedQuery.isEmpty
        collection.refreshControl?.endRefreshing()
        if isGlobal {
            guard !environment.searchSources.isEmpty else {
                global = GlobalSearchState()
                errors = [:]; finished = []
                tabRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
                tabs.isHidden = true
                status("没有支持搜索的已启用站源")
                return
            }
            if submittedQuery.isEmpty { showHistory(); status("输入关键词，按搜索键开始全站搜索"); return }
            var saved = environment.defaults.stringArray(forKey: "global.search.history") ?? []
            saved.removeAll { $0 == submittedQuery }; saved.insert(submittedQuery, at: 0)
            environment.defaults.set(Array(saved.prefix(60)), forKey: "global.search.history")
            loadGlobal(restoringSelectedSourceID: restoringGlobalSourceID)
        } else {
            guard !environment.discoverySources.isEmpty else {
                global = GlobalSearchState()
                errors = [:]; finished = []
                tabRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
                tabs.isHidden = true
                status("当前分组没有已启用的站源")
                return
            }
            loadSingle()
        }
    }

    private func showHistory() {
        let saved = environment.defaults.stringArray(forKey: "global.search.history") ?? []
        let scroll = SourceOptionScrollView()
        scroll.delaysContentTouches = false; scroll.canCancelContentTouches = true
        let row = UIStackView()
        row.axis = .horizontal; row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor), scroll.heightAnchor.constraint(equalToConstant: 40)
        ])
        for word in saved {
            let button = UIButton(type: .system)
            button.setTitle(word, for: .normal)
            button.addAction(UIAction { [weak self] _ in self?.searchBar.text = word; self?.start() }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        history.addArrangedSubview(scroll)
        if !saved.isEmpty {
            let clear = UIButton(type: .system)
            clear.setTitle("清空搜索记录", for: .normal)
            clear.addAction(UIAction { [weak self] _ in self?.environment.defaults.removeObject(forKey: "global.search.history"); self?.start() }, for: .touchUpInside)
            history.addArrangedSubview(clear)
        }
    }

    private func loadSingle() {
        guard !loading, !ended, environment.discoverySources.indices.contains(sourceIndex) else { return }
        let source = environment.discoverySources[sourceIndex]
        guard submittedQuery.isEmpty || source.supportsSearch else {
            ended = true
            status(source.name + "暂不支持搜索")
            return
        }
        loading = true; status(nextPage == 1 ? "正在加载…" : "正在加载下一页…")
        let token = requestID, page = nextPage, query = submittedQuery, activeFilters = filters
        tasks.append(Task { [weak self] in
            do {
                let results = try await (query.isEmpty ? source.category(filters: activeFilters, page: page) : source.search(keyword: query, page: page))
                try Task.checkCancellation()
                guard let self, self.requestID == token else { return }
                let known = Set(self.comics.map(\.comicId))
                var seen = known
                let new = results.filter { seen.insert($0.comicId).inserted }
                self.comics.append(contentsOf: new)
                self.nextPage = page + 1; self.ended = new.isEmpty; self.loading = false
                self.collection.reloadData()
                self.status(self.comics.isEmpty ? "没有找到漫画" : (self.ended ? "已经到底了" : ""))
            } catch {
                guard let self, self.requestID == token, !Task.isCancelled else { return }
                self.loading = false
                if (error as? Mh18SourceError) == .verificationRequired {
                    self.status("需要验证 · 去验证") { [weak self] in
                        guard let self else { return }
                        self.showSourceManagement(environment: self.environment) { [weak self] in self?.loadSingle() }
                    }
                } else {
                    self.status((error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试") { [weak self] in self?.loadSingle() }
                }
            }
        })
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Android requests another page when the user moves toward the bottom;
        // displaying a short first page alone must not mark it as exhausted.
        guard scrollView === collection, !isGlobal, scrollView.isDragging || scrollView.isDecelerating,
              scrollView.panGestureRecognizer.translation(in: scrollView).y < 0,
              scrollView.contentOffset.y > -scrollView.adjustedContentInset.top,
              scrollView.contentOffset.y + scrollView.bounds.height >= scrollView.contentSize.height - 120 else { return }
        loadSingle()
    }

    private func loadGlobal(restoringSelectedSourceID: String? = nil) {
        let token = requestID
        let searchSources = environment.searchSources
        let generation = global.begin(query: submittedQuery, sourceIDs: searchSources.map(\.id), restoringSelectedSourceID: restoringSelectedSourceID)
        errors = [:]; finished = []
        refreshGlobal()
        for source in searchSources {
            let query = submittedQuery
            tasks.append(Task { [weak self] in
                do {
                    let items = try await source.search(keyword: query, page: 1)
                    try Task.checkCancellation()
                    guard let self, self.requestID == token else { return }
                    self.global.receive(sourceID: source.id, items: items, generation: generation)
                    self.finished.insert(source.id); self.refreshGlobal()
                } catch {
                    guard let self, self.requestID == token, !Task.isCancelled else { return }
                    self.errors[source.id] = error
                    self.finished.insert(source.id); self.refreshGlobal()
                }
            })
        }
    }
    private func refreshGlobal() {
        tabRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let visibleIDs = global.visibleSourceIDs
        tabs.isHidden = visibleIDs.isEmpty || submittedQuery.isEmpty || !isGlobal
        for id in visibleIDs {
            guard let source = environment.searchSources.first(where: { $0.id == id }) else { continue }
            let count = global.results[id]?.count ?? 0
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = "discover.global." + source.id
            var configuration = UIButton.Configuration.tinted()
            configuration.title = source.name + (count > 0 ? " \(count)" : "")
            let isSelected = (source.id == global.selectedSourceID)
            configuration.baseBackgroundColor = isSelected ? Palette.accent : .clear
            configuration.baseForegroundColor = isSelected ? .white : Palette.text
            if global.exactSourceIDs.contains(source.id) {
                configuration.image = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 6))?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
                configuration.imagePlacement = .trailing; configuration.imagePadding = 4
                button.accessibilityValue = "有同名结果"
            }
            button.configuration = configuration
            button.addAction(UIAction { [weak self] _ in
                self?.global.select(source.id)
                self?.refreshGlobal()
            }, for: .touchUpInside)
            tabRow.addArrangedSubview(button)
        }
        comics = global.results[global.selectedSourceID ?? ""] ?? []
        collection.reloadData()
        let progress = "\(finished.count)/\(environment.searchSources.count) 个站源完成"
        if let error = errors[global.selectedSourceID ?? ""] {
            if (error as? Mh18SourceError) == .verificationRequired {
                status(progress + " · 需要验证 · 去验证") { [weak self] in
                    guard let self else { return }
                    let sourceID = self.global.selectedSourceID
                    self.showSourceManagement(environment: self.environment) { [weak self] in
                        guard let self else { return }
                        self.start(query: self.submittedQuery, restoringGlobalSourceID: sourceID)
                    }
                }
            } else {
                status(progress + " · " + (error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试") { [weak self] in
                    guard let self else { return }
                    self.start(query: self.submittedQuery, restoringGlobalSourceID: self.global.selectedSourceID)
                }
            }
        }
        else if comics.isEmpty {
            status(progress + (finished.count == environment.searchSources.count ? " · 没有找到漫画" : " · 正在搜索…"))
        } else { status(progress) }
    }
    @objc private func showSources() { searchBar.resignFirstResponder(); showFilterDrawer(initialSection: 0) }
    @objc private func showFilters() { loadScopeGroups(); showFilterDrawer(initialSection: 1) }
    private func showFilterDrawer(initialSection: Int, initialGroupIndex: Int = 0) {
        guard environment.discoverySources.indices.contains(sourceIndex) else { return }
        let source = environment.discoverySources[sourceIndex]
        let controller = FilterViewController(
            environment: environment,
            sources: environment.discoverySources,
            source: source,
            selected: filters,
            initialSection: initialSection,
            initialGroupIndex: initialGroupIndex
        ) { [weak self] sourceID, selected in
            guard let self, let index = self.environment.discoverySources.firstIndex(where: { $0.id == sourceID }) else { return }
            self.sourceIndex = index; self.filters = selected
            self.updateSourceMenu(); self.start()
        }
        let navigation = FilterDrawerNavigationController(rootViewController: controller)
        // A custom presentation is a sibling of the themed tab controller.
        // Apply the saved app mode; automatic still follows the system window.
        switch AppTheme(rawValue: environment.defaults.integer(forKey: "theme.mode")) ?? .automatic {
        case .automatic: navigation.overrideUserInterfaceStyle = .unspecified
        case .light: navigation.overrideUserInterfaceStyle = .light
        case .dark: navigation.overrideUserInterfaceStyle = .dark
        }
        present(navigation, animated: true)
    }
}

@MainActor
private final class FilterViewController: UIViewController {
    private let environment: AppEnvironment
    private var needsVerification = false
    let sources: [any ComicSource]
    var source: any ComicSource
    var selected: [String: String]
    let onSelect: (String, [String: String]) -> Void

    // Draft state for cancellation & confirmation
    private var draftSource: any ComicSource
    private var draftSelected: [String: String]
    private var draftGroups: [SourceFilterGroup] = []
    private var activeSection: Int // 0: 站源, 1: 分类
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

    init(environment: AppEnvironment, sources: [any ComicSource], source: any ComicSource, selected: [String: String], initialSection: Int, initialGroupIndex: Int, onSelect: @escaping (String, [String: String]) -> Void) {
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
        let sheetHeader = UIView(), grip = UIView(), heading = UILabel(), closeButton = UIButton(type: .system)
        grip.backgroundColor = Palette.border; grip.layer.cornerRadius = 2
        heading.text = title; heading.font = .systemFont(ofSize: 17, weight: .bold); heading.textColor = Palette.text
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16)), for: .normal)
        closeButton.tintColor = Palette.text3; closeButton.accessibilityIdentifier = "filter.close"; closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        for child in [grip, heading, closeButton] { child.translatesAutoresizingMaskIntoConstraints = false; sheetHeader.addSubview(child) }
        sheetHeader.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHeader(_:))))
        sectionSegment.axis = .horizontal; sectionSegment.spacing = 8; sectionSegment.distribution = .fillEqually
        for (index, button) in sectionButtons.enumerated() {
            button.tag = index; button.accessibilityIdentifier = "filter.section.\(index)"
            button.addTarget(self, action: #selector(sectionChanged(_:)), for: .touchUpInside)
            sectionSegment.addArrangedSubview(button)
        }

        let scroll = SourceOptionScrollView()
        scroll.delaysContentTouches = false; scroll.canCancelContentTouches = true
        scroll.accessibilityIdentifier = "filter.options"
        tabs.axis = .horizontal; tabs.spacing = 8
        options.axis = .vertical; options.spacing = 8
        state.titleLabel?.numberOfLines = 0
        state.titleLabel?.font = .systemFont(ofSize: 12)
        state.contentHorizontalAlignment = .leading; state.setTitleColor(Palette.text3, for: .normal)
        state.setTitleColor(Palette.text3, for: .disabled)
        state.addTarget(self, action: #selector(stateTapped), for: .touchUpInside)
        sourceDescription.font = .systemFont(ofSize: 12); sourceDescription.textColor = Palette.text3
        sourceDescription.numberOfLines = 0
        stateRow.axis = .vertical
        stateRow.addArrangedSubview(sourceDescription); stateRow.addArrangedSubview(state)
        let retryHeight = state.heightAnchor.constraint(equalToConstant: 44)
        retryHeight.priority = .init(999); retryHeight.isActive = true

        confirmButton.configuration = .filled()
        confirmButton.configuration?.baseBackgroundColor = Palette.accent
        confirmButton.configuration?.baseForegroundColor = .white
        confirmButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes; updated.font = .systemFont(ofSize: 15, weight: .medium); return updated
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
        tabs.translatesAutoresizingMaskIntoConstraints = false; tabScroll.addSubview(tabs)
        options.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(options)
        tabHeight = tabScroll.heightAnchor.constraint(equalToConstant: 42)
        tabHeight?.isActive = true

        NSLayoutConstraint.activate([
            sheetHeader.topAnchor.constraint(equalTo: view.topAnchor), sheetHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor), sheetHeader.heightAnchor.constraint(equalToConstant: 56),
            grip.topAnchor.constraint(equalTo: sheetHeader.topAnchor, constant: 6), grip.centerXAnchor.constraint(equalTo: sheetHeader.centerXAnchor),
            grip.widthAnchor.constraint(equalToConstant: 32), grip.heightAnchor.constraint(equalToConstant: 4),
            heading.topAnchor.constraint(equalTo: sheetHeader.topAnchor, constant: 26), heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.centerYAnchor.constraint(equalTo: heading.centerYAnchor), closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 36), closeButton.heightAnchor.constraint(equalToConstant: 36),
            sectionSegment.topAnchor.constraint(equalTo: sheetHeader.bottomAnchor),
            sectionSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sectionSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            sectionSegment.heightAnchor.constraint(equalToConstant: 44),

            tabScroll.topAnchor.constraint(equalTo: sectionSegment.bottomAnchor, constant: 8),
            tabScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tabScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tabs.leadingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.bottomAnchor),
            tabs.heightAnchor.constraint(equalTo: tabScroll.frameLayoutGuide.heightAnchor),

            stateRow.topAnchor.constraint(equalTo: tabScroll.bottomAnchor, constant: 4),
            stateRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stateRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: stateRow.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: confirmButton.topAnchor, constant: -12),

            options.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            options.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            options.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            options.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            options.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),

            confirmButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            confirmButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            confirmButton.heightAnchor.constraint(equalToConstant: 44),
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        if activeSection == 0 {
            render()
        } else {
            loadGroups()
        }
    }

    @objc private func sectionChanged(_ sender: UIButton) {
        activeSection = sender.tag
        if activeSection == 0 {
            render()
        } else {
            if draftGroups.isEmpty {
                loadGroups()
            } else {
                render()
            }
        }
    }

    @objc private func loadGroups() {
        needsVerification = false
        task?.cancel(); draftGroups = []; render(); setStateMessage("正在加载分类…")
        let candidate = draftSource
        task = Task { [weak self, candidate] in
            do {
                var groups = try await candidate.filterGroups()
                try Task.checkCancellation()
                if candidate.id == "favcomic", let fav = candidate as? PublicComicSource,
                   let selectedType = self?.draftSelected["type"], !selectedType.isEmpty, selectedType != "all" {
                    groups = fav.filterGroupsForType(selectedType)
                }
                self?.draftGroups = groups
                if let self { self.activeGroupIndex = min(self.activeGroupIndex, max(0, groups.count - 1)) }
                self?.setStateMessage(groups.isEmpty ? "该站源暂无分类" : nil)
                self?.render()
            }
            catch {
                guard let self, !Task.isCancelled else { return }
                self.needsVerification = (error as? Mh18SourceError) == .verificationRequired
                self.setStateMessage(self.needsVerification ? "需要验证 · 去验证" : (error is CancellationError ? "已取消 · 点击重试" : "分类加载失败 · 点击重试"))
            }
        }
    }

    @objc private func stateTapped() {
        if needsVerification {
            showSourceManagement(environment: environment) { [weak self] in self?.loadGroups() }
        } else { loadGroups() }
    }
    private func setStateMessage(_ message: String?) {
        state.setTitle(message, for: .normal)
        state.isHidden = activeSection == 0 || message?.isEmpty != false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        task?.cancel()
    }

    @objc private func close() {
        task?.cancel()
        dismiss(animated: true)
    }
    @objc private func dragHeader(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began { dragStartHeight = view.bounds.height - view.safeAreaInsets.bottom }
        if pan.state == .changed { navigationController?.preferredContentSize.height = max(220, dragStartHeight - pan.translation(in: view).y) }
        if pan.state == .ended, pan.translation(in: view).y > 60, pan.velocity(in: view).y > 300 { close() }
    }

    @objc private func done() {
        task?.cancel()
        onSelect(draftSource.id, draftSelected)
        dismiss(animated: true)
    }

    private func render() {
        let isSourceSection = (activeSection == 0)
        for (index, button) in sectionButtons.enumerated() {
            configureOption(button, title: index == 0 ? "站源" : "分类", selected: false)
            button.configuration?.baseForegroundColor = index == activeSection ? Palette.accent : Palette.text3
            button.isSelected = index == activeSection
            button.accessibilityTraits = index == activeSection ? [.button, .selected] : .button
        }
        tabScroll.isHidden = isSourceSection
        tabHeight?.constant = isSourceSection ? 0 : 42
        sourceDescription.isHidden = !isSourceSection
        state.isHidden = isSourceSection || state.currentTitle?.isEmpty != false
        tabs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        options.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if isSourceSection {
            let groupName = environment.sourceGroupStore.currentGroup.name
            sourceDescription.text = "分组 · " + groupName + " · 已启用站源"
            state.isEnabled = false

            if sources.isEmpty {
                let emptyLabel = UILabel()
                emptyLabel.text = "分组内没有可用站源"
                emptyLabel.textColor = Palette.secondaryText
                emptyLabel.textAlignment = .center
                emptyLabel.font = .systemFont(ofSize: 14)
                options.addArrangedSubview(emptyLabel)
                return
            }

            for start in stride(from: 0, to: sources.count, by: 3) {
                let row = UIStackView()
                row.axis = .horizontal; row.spacing = 8; row.distribution = .fillEqually
                for index in start..<(start + 3) {
                    guard sources.indices.contains(index) else {
                        row.addArrangedSubview(UIView())
                        continue
                    }
                    let candidate = sources[index]
                    let isSelected = (candidate.id == draftSource.id)
                    let button = UIButton(type: .system)
                    button.accessibilityIdentifier = "filter.source." + candidate.id
                    configureOption(button, title: candidate.name, selected: isSelected)
                    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                    button.addAction(UIAction { [weak self] _ in
                        guard let self else { return }
                        self.task?.cancel()
                        self.draftSource = candidate
                        self.draftSelected = [:]
                        self.draftGroups = []
                        self.activeSection = 1
                        self.activeGroupIndex = 0
                        self.loadGroups()
                    }, for: .touchUpInside)
                    row.addArrangedSubview(button)
                }
                options.addArrangedSubview(row)
            }
            return
        }

        // Category section
        state.isEnabled = true
        for (index, group) in draftGroups.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(group.label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: index == activeGroupIndex ? .bold : .regular)
            button.tintColor = index == activeGroupIndex ? Palette.accent : Palette.text
            button.addAction(UIAction { [weak self] _ in
                self?.activeGroupIndex = index
                self?.render()
            }, for: .touchUpInside)
            tabs.addArrangedSubview(button)
        }

        guard draftGroups.indices.contains(activeGroupIndex) else { return }
        let group = draftGroups[activeGroupIndex]
        for start in stride(from: 0, to: group.options.count, by: 3) {
            let row = UIStackView(); row.axis = .horizontal; row.spacing = 8; row.distribution = .fillEqually
            for index in start..<(start + 3) {
                guard group.options.indices.contains(index) else {
                    row.addArrangedSubview(UIView())
                    continue
                }
                let option = group.options[index]
                let button = UIButton(type: .system)
                let isCurrentOptionSelected = (draftSelected[group.key] ?? "all") == option.value
                configureOption(button, title: option.label, selected: isCurrentOptionSelected)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    SourceFilterSelection.select(
                        sourceID: self.draftSource.id,
                        key: group.key,
                        value: option.value,
                        groupKeys: self.draftGroups.map(\.key),
                        in: &self.draftSelected
                    )
                    if self.draftSource.id == "favcomic", group.key == "type",
                       let fav = self.draftSource as? PublicComicSource {
                        self.draftGroups = fav.filterGroupsForType(option.value)
                        self.draftSelected["tag"] = "all"
                    }
                    self.render()
                }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            options.addArrangedSubview(row)
        }
    }
    private func configureOption(_ button: UIButton, title: String, selected: Bool) {
        var config = UIButton.Configuration.plain()
        config.title = title; config.titleAlignment = .center; config.titleLineBreakMode = .byWordWrapping
        config.baseForegroundColor = selected ? Palette.accent : Palette.text
        config.background.backgroundColor = selected ? Palette.accentSoft : Palette.card
        config.background.strokeColor = selected ? Palette.accent : Palette.border
        config.background.strokeWidth = 1; config.background.cornerRadius = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var result = $0; result.font = .systemFont(ofSize: 12, weight: .bold); return result }
        button.configuration = config; button.titleLabel?.numberOfLines = 2
        button.isSelected = selected; button.accessibilityLabel = title
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
