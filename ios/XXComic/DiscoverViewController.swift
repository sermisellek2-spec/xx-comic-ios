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
        sourceIDs = environment.sources.map(\.id)
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
        needsReload = loading || (isGlobal && !submittedQuery.isEmpty && finished.count < environment.searchSources.count)
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
        filterButton.isEnabled = !environment.sources.isEmpty
        sourceButton.isEnabled = !environment.sources.isEmpty
        guard !environment.sources.isEmpty else {
            sourceButton.setTitle("没有已启用的站源", for: .normal)
            return
        }
        sourceButton.setTitle(environment.sources[sourceIndex].name + " ▾", for: .normal)
    }
    @objc private func sourcesChanged() {
        let selectedGlobalSourceID = global.selectedSourceID
        let previous = sourceIDs.indices.contains(sourceIndex) ? sourceIDs[sourceIndex] : nil
        sourceIDs = environment.sources.map(\.id)
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
        guard !environment.sources.isEmpty else {
            global = GlobalSearchState()
            errors = [:]; finished = []
            tabRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
            tabs.isHidden = true
            status("没有已启用的站源")
            return
        }
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
        guard !loading, !ended, environment.sources.indices.contains(sourceIndex) else { return }
        let source = environment.sources[sourceIndex]
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
        let generation = global.begin(query: submittedQuery, sourceIDs: environment.searchSources.map(\.id), restoringSelectedSourceID: restoringSelectedSourceID)
        errors = [:]; finished = []
        refreshGlobal()
        for source in environment.searchSources {
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
        for (index, source) in environment.searchSources.enumerated() {
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = "discover.global." + source.id
            var configuration = UIButton.Configuration.tinted()
            configuration.title = source.name
            configuration.baseBackgroundColor = source.id == global.selectedSourceID ? .systemBlue : .clear
            if global.exactSourceIDs.contains(source.id) {
                configuration.image = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 6))?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
                configuration.imagePlacement = .trailing; configuration.imagePadding = 4
                button.accessibilityValue = "有同名结果"
            }
            button.configuration = configuration; button.tag = index
            button.addTarget(self, action: #selector(selectGlobalSource(_:)), for: .touchUpInside)
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
        else { status(progress + (comics.isEmpty && finished.contains(global.selectedSourceID ?? "") ? " · 没有找到漫画" : "")) }
    }
    @objc private func selectGlobalSource(_ sender: UIButton) {
        guard environment.searchSources.indices.contains(sender.tag) else { return }
        global.select(environment.searchSources[sender.tag].id); refreshGlobal()
    }
    @objc private func showSources() { showFilterDrawer(sourceList: true) }
    @objc private func showFilters() { showFilterDrawer(sourceList: false) }
    private func showFilterDrawer(sourceList: Bool) {
        guard environment.sources.indices.contains(sourceIndex) else { return }
        let source = environment.sources[sourceIndex]
        let controller = FilterViewController(environment: environment, sources: environment.sources, source: source, selected: filters, sourceList: sourceList) { [weak self] sourceID, selected in
            guard let self, let index = self.environment.sources.firstIndex(where: { $0.id == sourceID }) else { return }
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
    var groups: [SourceFilterGroup] = []
    var task: Task<Void, Never>?
    private let tabs = UIStackView()
    private let tabScroll = UIScrollView()
    private var tabHeight: NSLayoutConstraint?
    private let options = UIStackView()
    private let state = UIButton(type: .system)
    private var activeGroup: Int
    init(environment: AppEnvironment, sources: [any ComicSource], source: any ComicSource, selected: [String: String], sourceList: Bool, onSelect: @escaping (String, [String: String]) -> Void) {
        self.environment = environment
        self.sources = sources; self.source = source; self.selected = selected; self.onSelect = onSelect
        activeGroup = sourceList ? -1 : 0
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "筛选"
        view.backgroundColor = Palette.card
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "filter.close"
        let scroll = UIScrollView(), confirm = UIButton(type: .system)
        tabs.axis = .horizontal; tabs.spacing = 8
        options.axis = .vertical; options.spacing = 8
        state.titleLabel?.numberOfLines = 0
        state.addTarget(self, action: #selector(stateTapped), for: .touchUpInside)
        confirm.configuration = .filled(); confirm.setTitle("确认搜索", for: .normal)
        confirm.accessibilityIdentifier = "filter.confirm"
        confirm.addTarget(self, action: #selector(done), for: .touchUpInside)
        for item in [tabScroll, scroll, state, confirm] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        tabs.translatesAutoresizingMaskIntoConstraints = false; tabScroll.addSubview(tabs)
        options.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(options)
        tabHeight = tabScroll.heightAnchor.constraint(equalToConstant: 42)
        tabHeight?.isActive = true
        NSLayoutConstraint.activate([
            tabScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), tabScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tabs.leadingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.topAnchor), tabs.bottomAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.bottomAnchor),
            tabs.heightAnchor.constraint(equalTo: tabScroll.frameLayoutGuide.heightAnchor),
            state.topAnchor.constraint(equalTo: tabScroll.bottomAnchor), state.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), state.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: state.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: confirm.topAnchor, constant: -12),
            options.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), options.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            options.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), options.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            options.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            confirm.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), confirm.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            confirm.heightAnchor.constraint(equalToConstant: 46), confirm.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        if activeGroup < 0 { render() } else { loadGroups() }
    }
    @objc private func loadGroups() {
        needsVerification = false
        task?.cancel(); groups = []; render(); state.setTitle("正在加载分类…", for: .normal)
        task = Task { [weak self, source] in
            do {
                let groups = try await source.filterGroups(); try Task.checkCancellation()
                self?.groups = groups; self?.activeGroup = 0
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
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); task?.cancel() }
    @objc private func close() { task?.cancel(); dismiss(animated: true) }
    @objc private func done() { task?.cancel(); onSelect(source.id, selected); dismiss(animated: true) }
    private func render() {
        tabScroll.isHidden = activeGroup < 0
        tabHeight?.constant = activeGroup < 0 ? 0 : 42
        tabs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        options.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if activeGroup < 0 {
            state.setTitle("已启用站源", for: .normal)
            state.isEnabled = false
            for candidate in sources {
                let button = UIButton(type: .system)
                button.accessibilityIdentifier = "filter.source." + candidate.id
                button.contentHorizontalAlignment = .leading
                button.setTitle(candidate.name + (candidate.id == source.id ? "  ✓" : ""), for: .normal)
                button.tintColor = candidate.id == source.id ? Palette.accent : Palette.text
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.task?.cancel(); self.source = candidate; self.selected = [:]; self.groups = []
                    if ["mh18", "jmcomic"].contains(candidate.id) { self.render() }
                    else { self.activeGroup = 0; self.loadGroups() }
                }, for: .touchUpInside)
                options.addArrangedSubview(button)
            }
            return
        }
        state.isEnabled = true
        for (index, group) in groups.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(group.label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: index == activeGroup ? .bold : .regular)
            button.addAction(UIAction { [weak self] _ in self?.activeGroup = index; self?.render() }, for: .touchUpInside)
            tabs.addArrangedSubview(button)
        }
        guard groups.indices.contains(activeGroup) else { return }
        let group = groups[activeGroup]
        for start in stride(from: 0, to: group.options.count, by: 3) {
            let row = UIStackView(); row.axis = .horizontal; row.spacing = 8; row.distribution = .fillEqually
            for index in start..<(start + 3) {
                guard group.options.indices.contains(index) else { row.addArrangedSubview(UIView()); continue }
                let option = group.options[index], button = UIButton(type: .system)
                var config = UIButton.Configuration.tinted()
                config.title = option.label
                config.baseBackgroundColor = (selected[group.key] ?? "all") == option.value ? Palette.accent : .clear
                config.titleLineBreakMode = .byTruncatingTail
                button.configuration = config
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    SourceFilterSelection.select(sourceID: self.source.id, key: group.key, value: option.value,
                                                 groupKeys: self.groups.map(\.key), in: &self.selected)
                    self.render()
                }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            options.addArrangedSubview(row)
        }
    }
}
