import UIKit
import ComicCore

@MainActor
final class DiscoverViewController: ComicGridViewController, UISearchBarDelegate {
    private let searchBar = UISearchBar()
    private let mode = UISegmentedControl(items: ["单站", "全站"])
    private let sourceButton = UIButton(type: .system)
    private let filterButton = UIButton(type: .system)
    private let tabs = UIScrollView()
    private let tabRow = UIStackView()
    private let history = UIStackView()
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
    private var isGlobal: Bool { mode.selectedSegmentIndex == 1 }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourceIDs = environment.discoverySources.map(\.id)
        NotificationCenter.default.addObserver(self, selector: #selector(sourcesChanged), name: AppEnvironment.sourcesChanged, object: environment)
        title = "发现"
        searchBar.placeholder = "搜索漫画"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        mode.selectedSegmentIndex = 0
        mode.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        let top = UIStackView(arrangedSubviews: [searchBar, mode])
        top.alignment = .center
        mode.widthAnchor.constraint(equalToConstant: 100).isActive = true
        header.addArrangedSubview(top)
        sourceButton.addTarget(self, action: #selector(showSources), for: .touchUpInside)
        sourceButton.accessibilityIdentifier = "discover.source"
        updateSourceMenu()
        filterButton.setTitle("分类筛选", for: .normal)
        filterButton.addTarget(self, action: #selector(showFilters), for: .touchUpInside)
        let sourceRow = UIStackView(arrangedSubviews: [sourceButton, filterButton])
        sourceRow.distribution = .fillEqually
        header.addArrangedSubview(sourceRow)
        header.addArrangedSubview(tabs)
        tabs.showsHorizontalScrollIndicator = false
        tabRow.axis = .horizontal; tabRow.spacing = 6
        tabRow.translatesAutoresizingMaskIntoConstraints = false; tabs.addSubview(tabRow)
        NSLayoutConstraint.activate([
            tabs.heightAnchor.constraint(equalToConstant: 38),
            tabRow.leadingAnchor.constraint(equalTo: tabs.contentLayoutGuide.leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: tabs.contentLayoutGuide.trailingAnchor),
            tabRow.topAnchor.constraint(equalTo: tabs.contentLayoutGuide.topAnchor),
            tabRow.bottomAnchor.constraint(equalTo: tabs.contentLayoutGuide.bottomAnchor),
            tabRow.heightAnchor.constraint(equalTo: tabs.frameLayoutGuide.heightAnchor)
        ])
        history.axis = .vertical
        history.spacing = 4
        header.addArrangedSubview(history)
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshResults), for: .valueChanged)
        collection.refreshControl = refresh
        collection.keyboardDismissMode = .onDrag
        start()
    }
    deinit { tasks.forEach { $0.cancel() } }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentedViewController != nil { return }
        needsReload = loading || (isGlobal && !submittedQuery.isEmpty && finished.count < environment.discoverySearchSources.count)
        requestID = UUID(); tasks.forEach { $0.cancel() }; tasks = []
        loading = false
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if needsReload {
            needsReload = false
            start(query: submittedQuery, restoringGlobalSourceID: isGlobal ? global.selectedSourceID : nil)
        }
    }
    private func updateSourceMenu() {
        filterButton.isEnabled = !environment.discoverySources.isEmpty
        sourceButton.isEnabled = !environment.discoverySources.isEmpty
        guard !environment.discoverySources.isEmpty else {
            sourceButton.setTitle("没有已启用的站源", for: .normal)
            return
        }
        let name = environment.discoverySources.indices.contains(sourceIndex) ? environment.discoverySources[sourceIndex].name : (environment.discoverySources.first?.name ?? "")
        sourceButton.setTitle(name + " ▾", for: .normal)
    }
    @objc private func sourcesChanged() {
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
    @objc private func modeChanged() { start() }
    @objc private func refreshResults() { start() }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder(); start() }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { if searchText.isEmpty { start() } }

    private func start(query: String? = nil, restoringGlobalSourceID: String? = nil) {
        requestID = UUID()
        tasks.forEach { $0.cancel() }; tasks = []
        loading = false; ended = false; nextPage = 1
        comics = []; collection.reloadData()
        submittedQuery = query ?? SearchRules.trim(searchBar.text ?? "")
        history.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sourceButton.isHidden = isGlobal; filterButton.isHidden = isGlobal
        tabs.isHidden = !isGlobal || submittedQuery.isEmpty
        collection.refreshControl?.endRefreshing()
        guard !environment.discoverySources.isEmpty else {
            global = GlobalSearchState()
            errors = [:]; finished = []
            tabRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
            tabs.isHidden = true
            status("没有已启用的站源")
            return
        }
        if isGlobal {
            guard !environment.discoverySearchSources.isEmpty else {
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
        } else { loadSingle() }
    }

    private func showHistory() {
        let saved = environment.defaults.stringArray(forKey: "global.search.history") ?? []
        let scroll = UIScrollView()
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
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if !isGlobal && indexPath.item >= comics.count - 4 { loadSingle() }
    }

    private func loadGlobal(restoringSelectedSourceID: String? = nil) {
        let token = requestID
        let searchSources = environment.discoverySearchSources
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
            guard let source = environment.discoverySearchSources.first(where: { $0.id == id }) else { continue }
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
        let progress = "\(finished.count)/\(environment.discoverySearchSources.count) 个站源完成"
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
        else { status(progress + (comics.isEmpty && finished.contains(global.selectedSourceID ?? "") ? " · 没有找到漫画" : "")) }
    }
    @objc private func showSources() { showFilterDrawer(initialSection: 0) }
    @objc private func showFilters() { showFilterDrawer(initialSection: 1) }
    private func showFilterDrawer(initialSection: Int) {
        guard environment.discoverySources.indices.contains(sourceIndex) else { return }
        let source = environment.discoverySources[sourceIndex]
        let controller = FilterViewController(
            environment: environment,
            sources: environment.discoverySources,
            source: source,
            selected: filters,
            initialSection: initialSection
        ) { [weak self] sourceID, selected in
            guard let self, let index = self.environment.discoverySources.firstIndex(where: { $0.id == sourceID }) else { return }
            self.sourceIndex = index; self.filters = selected
            self.updateSourceMenu(); self.start()
        }
        present(FilterDrawerNavigationController(rootViewController: controller), animated: true)
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

    private let sectionSegment = UISegmentedControl(items: ["站源", "分类"])
    private let tabs = UIStackView()
    private let tabScroll = UIScrollView()
    private var tabHeight: NSLayoutConstraint?
    private let options = UIStackView()
    private let state = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)

    init(environment: AppEnvironment, sources: [any ComicSource], source: any ComicSource, selected: [String: String], initialSection: Int, onSelect: @escaping (String, [String: String]) -> Void) {
        self.environment = environment
        self.sources = sources
        self.source = source
        self.selected = selected
        self.draftSource = source
        self.draftSelected = selected
        self.activeSection = initialSection
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "站源与分类"
        view.backgroundColor = Palette.card
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "filter.close"

        sectionSegment.selectedSegmentIndex = activeSection
        sectionSegment.addTarget(self, action: #selector(sectionChanged), for: .valueChanged)

        let scroll = UIScrollView()
        tabs.axis = .horizontal; tabs.spacing = 8
        options.axis = .vertical; options.spacing = 8
        state.titleLabel?.numberOfLines = 0
        state.addTarget(self, action: #selector(stateTapped), for: .touchUpInside)

        confirmButton.configuration = .filled()
        confirmButton.setTitle("应用", for: .normal)
        confirmButton.accessibilityIdentifier = "filter.confirm"
        confirmButton.addTarget(self, action: #selector(done), for: .touchUpInside)

        for item in [sectionSegment, tabScroll, scroll, state, confirmButton] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        tabs.translatesAutoresizingMaskIntoConstraints = false; tabScroll.addSubview(tabs)
        options.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(options)
        tabHeight = tabScroll.heightAnchor.constraint(equalToConstant: 42)
        tabHeight?.isActive = true

        NSLayoutConstraint.activate([
            sectionSegment.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            sectionSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sectionSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            sectionSegment.heightAnchor.constraint(equalToConstant: 36),

            tabScroll.topAnchor.constraint(equalTo: sectionSegment.bottomAnchor, constant: 8),
            tabScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tabs.leadingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.bottomAnchor),
            tabs.heightAnchor.constraint(equalTo: tabScroll.frameLayoutGuide.heightAnchor),

            state.topAnchor.constraint(equalTo: tabScroll.bottomAnchor, constant: 4),
            state.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            state.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: state.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
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

    @objc private func sectionChanged() {
        activeSection = sectionSegment.selectedSegmentIndex
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
        task?.cancel(); draftGroups = []; render(); state.setTitle("正在加载分类…", for: .normal)
        let candidate = draftSource
        task = Task { [weak self, candidate] in
            do {
                let groups = try await candidate.filterGroups()
                try Task.checkCancellation()
                self?.draftGroups = groups
                self?.activeGroupIndex = 0
                self?.state.setTitle(groups.isEmpty ? "该站源暂无分类" : nil, for: .normal)
                self?.render()
            }
            catch {
                guard let self, !Task.isCancelled else { return }
                self.needsVerification = (error as? Mh18SourceError) == .verificationRequired
                self.state.setTitle(self.needsVerification ? "需要验证 · 去验证" : (error is CancellationError ? "已取消 · 点击重试" : "分类加载失败 · 点击重试"), for: .normal)
            }
        }
    }

    @objc private func stateTapped() {
        if needsVerification {
            showSourceManagement(environment: environment) { [weak self] in self?.loadGroups() }
        } else { loadGroups() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        task?.cancel()
    }

    @objc private func close() {
        task?.cancel()
        dismiss(animated: true)
    }

    @objc private func done() {
        task?.cancel()
        onSelect(draftSource.id, draftSelected)
        dismiss(animated: true)
    }

    private func render() {
        let isSourceSection = (activeSection == 0)
        tabScroll.isHidden = isSourceSection
        tabHeight?.constant = isSourceSection ? 0 : 42
        tabs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        options.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if isSourceSection {
            let groupName = environment.sourceGroupStore.currentGroup.name
            state.setTitle("分组 · " + groupName + " · 已启用站源", for: .normal)
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
                    var config = UIButton.Configuration.tinted()
                    config.title = candidate.name
                    config.baseBackgroundColor = isSelected ? Palette.accent : .clear
                    config.baseForegroundColor = isSelected ? .white : Palette.text
                    config.titleLineBreakMode = .byTruncatingTail
                    button.configuration = config
                    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                    button.addAction(UIAction { [weak self] _ in
                        guard let self else { return }
                        self.task?.cancel()
                        self.draftSource = candidate
                        self.draftSelected = [:]
                        self.draftGroups = []
                        self.activeSection = 1
                        self.sectionSegment.selectedSegmentIndex = 1
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
                var config = UIButton.Configuration.tinted()
                config.title = option.label
                let isCurrentOptionSelected = (draftSelected[group.key] ?? "all") == option.value
                config.baseBackgroundColor = isCurrentOptionSelected ? Palette.accent : .clear
                config.baseForegroundColor = isCurrentOptionSelected ? .white : Palette.text
                config.titleLineBreakMode = .byTruncatingTail
                button.configuration = config
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
                    self.render()
                }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            options.addArrangedSubview(row)
        }
    }
}
