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
    private var filters: [String: String] = [:]
    private var requestID = UUID()
    private var tasks: [Task<Void, Never>] = []
    private var global = GlobalSearchState()
    private var errors: [String: String] = [:]
    private var finished = Set<String>()
    private var nextPage = 1
    private var loading = false
    private var ended = false
    private var submittedQuery = ""
    private var needsReload = false
    private var isGlobal: Bool { mode.selectedSegmentIndex == 1 }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        sourceButton.showsMenuAsPrimaryAction = true
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
        needsReload = loading || (isGlobal && finished.count < environment.sources.count)
        requestID = UUID(); tasks.forEach { $0.cancel() }; tasks = []
        loading = false
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if needsReload { needsReload = false; start() }
    }
    private func updateSourceMenu() {
        guard !environment.sources.isEmpty else { return }
        sourceButton.setTitle(environment.sources[sourceIndex].name + " ▾", for: .normal)
        sourceButton.menu = UIMenu(children: environment.sources.enumerated().map { index, source in
            UIAction(title: source.name, state: index == sourceIndex ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.sourceIndex = index; self.filters = [:]; self.updateSourceMenu(); self.start()
            }
        })
    }
    @objc private func modeChanged() { start() }
    @objc private func refreshResults() { start() }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder(); start() }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { if searchText.isEmpty { start() } }

    private func start() {
        requestID = UUID()
        tasks.forEach { $0.cancel() }; tasks = []
        loading = false; ended = false; nextPage = 1
        comics = []; collection.reloadData()
        submittedQuery = SearchRules.trim(searchBar.text ?? "")
        history.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sourceButton.isHidden = isGlobal; filterButton.isHidden = isGlobal
        tabs.isHidden = !isGlobal || submittedQuery.isEmpty
        collection.refreshControl?.endRefreshing()
        guard !environment.sources.isEmpty else { status("没有已启用的站源"); return }
        if isGlobal {
            if submittedQuery.isEmpty { showHistory(); status("输入关键词，按搜索键开始全站搜索"); return }
            var saved = environment.defaults.stringArray(forKey: "global.search.history") ?? []
            saved.removeAll { $0 == submittedQuery }; saved.insert(submittedQuery, at: 0)
            environment.defaults.set(Array(saved.prefix(60)), forKey: "global.search.history")
            loadGlobal()
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
        guard !loading, !ended else { return }
        loading = true; status(nextPage == 1 ? "正在加载…" : "正在加载下一页…")
        let token = requestID, page = nextPage, query = submittedQuery, activeFilters = filters
        let source = environment.sources[sourceIndex]
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
                self.status(error.localizedDescription + " · 点击重试") { [weak self] in self?.loadSingle() }
            }
        })
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if !isGlobal && indexPath.item >= comics.count - 4 { loadSingle() }
    }

    private func loadGlobal() {
        let token = requestID
        let generation = global.begin(query: submittedQuery, sourceIDs: environment.sources.map(\.id))
        errors = [:]; finished = []
        refreshGlobal()
        for source in environment.sources {
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
                    self.errors[source.id] = error.localizedDescription
                    self.finished.insert(source.id); self.refreshGlobal()
                }
            })
        }
    }
    private func refreshGlobal() {
        tabRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, source) in environment.sources.enumerated() {
            let button = UIButton(type: .system)
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
        let progress = "\(finished.count)/\(environment.sources.count) 个站源完成"
        if let error = errors[global.selectedSourceID ?? ""] { status(progress + " · " + error + " · 点击重试") { [weak self] in self?.start() } }
        else { status(progress + (comics.isEmpty && finished.contains(global.selectedSourceID ?? "") ? " · 没有找到漫画" : "")) }
    }
    @objc private func selectGlobalSource(_ sender: UIButton) {
        guard environment.sources.indices.contains(sender.tag) else { return }
        global.select(environment.sources[sender.tag].id); refreshGlobal()
    }
    @objc private func showFilters() {
        let source = environment.sources[sourceIndex]
        let controller = FilterViewController(source: source, selected: filters) { [weak self] selected in
            self?.filters = selected; self?.start()
        }
        present(UINavigationController(rootViewController: controller), animated: true)
    }
}

@MainActor
private final class FilterViewController: UITableViewController {
    let source: any ComicSource
    var selected: [String: String]
    let onSelect: ([String: String]) -> Void
    var groups: [SourceFilterGroup] = []
    var task: Task<Void, Never>?
    init(source: any ComicSource, selected: [String: String], onSelect: @escaping ([String: String]) -> Void) {
        self.source = source; self.selected = selected; self.onSelect = onSelect
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "正在加载分类…"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(done))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "重试", style: .plain, target: self, action: #selector(loadGroups))
        loadGroups()
    }
    @objc private func loadGroups() {
        task?.cancel(); title = "正在加载分类…"
        task = Task { [weak self, source] in
            do { let groups = try await source.filterGroups(); try Task.checkCancellation(); self?.groups = groups; self?.title = "分类筛选"; self?.tableView.reloadData() }
            catch { if !Task.isCancelled { self?.title = "分类加载失败"; self?.showError(error) } }
        }
    }
    @objc private func done() { onSelect(selected); dismiss(animated: true) }
    override func numberOfSections(in tableView: UITableView) -> Int { groups.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { groups[section].options.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { groups[section].label }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let group = groups[indexPath.section], option = group.options[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = option.label
        cell.accessoryType = (selected[group.key] ?? "all") == option.value ? .checkmark : .none
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let group = groups[indexPath.section]
        selected[group.key] = group.options[indexPath.row].value
        tableView.reloadData()
    }
}
