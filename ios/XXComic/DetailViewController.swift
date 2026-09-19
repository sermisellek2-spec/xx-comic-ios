import UIKit
import ComicCore

@MainActor
final class DetailViewController: UIViewController {
    private let environment: AppEnvironment
    private var comic: ComicSummary
    private let source: any ComicSource
    private let cover = RemoteImageView()
    private let heading = UILabel()
    private let descriptionLabel = UILabel()
    private let favorite = UIButton(type: .system)
    private let read = UIButton(type: .system)
    private let directory = UIButton(type: .system)
    private let retry = UIButton(type: .system)
    private var detailTask: Task<Void, Never>?
    private var directoryTask: Task<[Chapter], Error>?
    private var cachedChapters: [Chapter]?
    private var detailLoaded = false
    private var directoryID = UUID()
    private var readTask: Task<Void, Never>?

    init(comic: ComicSummary, environment: AppEnvironment) {
        self.comic = comic; self.environment = environment
        source = environment.source(for: comic)!
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { detailTask?.cancel(); directoryTask?.cancel(); readTask?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = source.name
        view.backgroundColor = Palette.background
        let scroll = UIScrollView()
        let content = UIStackView()
        content.axis = .vertical; content.spacing = 18
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(content)
        cover.contentMode = .scaleAspectFit
        cover.heightAnchor.constraint(equalToConstant: 280).isActive = true
        heading.text = comic.title; heading.numberOfLines = 0
        heading.font = .preferredFont(forTextStyle: .title2); heading.textColor = Palette.text
        descriptionLabel.numberOfLines = 0; descriptionLabel.font = .preferredFont(forTextStyle: .body)
        descriptionLabel.textColor = Palette.secondaryText
        heading.adjustsFontForContentSizeCategory = true; descriptionLabel.adjustsFontForContentSizeCategory = true
        favorite.addTarget(self, action: #selector(toggleFavorite), for: .touchUpInside)
        read.addTarget(self, action: #selector(startReading), for: .touchUpInside)
        read.titleLabel?.numberOfLines = 2
        directory.setTitle("章节目录", for: .normal)
        directory.addTarget(self, action: #selector(showDirectory), for: .touchUpInside)
        retry.addTarget(self, action: #selector(loadDetail), for: .touchUpInside)
        retry.titleLabel?.numberOfLines = 0
        for item in [cover, heading, descriptionLabel, favorite, directory, read, retry] { content.addArrangedSubview(item) }
        for button in [favorite, directory, read, retry] { button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        cover.load(comic.coverUrl, referer: source.referer)
        loadDetail()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); updateButtons()
        if !detailLoaded && detailTask == nil { loadDetail() }
        if cover.image == nil { cover.load(comic.coverUrl, referer: source.referer) }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentedViewController == nil else { return }
        detailTask?.cancel(); detailTask = nil
        directoryID = UUID(); directoryTask?.cancel(); directoryTask = nil
        readTask?.cancel(); readTask = nil; read.isEnabled = true
        cover.cancel()
    }
    private func updateButtons() {
        favorite.setTitle(environment.library.entry(for: comic)?.isFavorite == true ? "已收藏 · 点击移除" : "加入书架", for: .normal)
        read.setTitle(environment.library.entry(for: comic)?.reading.map { "继续阅读\n上次看到 · \($0.chapter.title)" } ?? "开始阅读", for: .normal)
    }
    @objc private func loadDetail() {
        detailTask?.cancel()
        retry.setTitle("正在加载详情…", for: .normal)
        let id = comic.comicId
        detailTask = Task { [weak self, source] in
            do {
                let detail = try await source.detail(comicId: id)
                try Task.checkCancellation()
                guard let self else { return }
                self.comic = detail.summary
                self.detailLoaded = true
                self.heading.text = detail.summary.title
                self.descriptionLabel.text = [detail.author, detail.status, detail.description].filter { !$0.isEmpty }.joined(separator: "\n\n")
                self.cover.load(detail.summary.coverUrl, referer: source.referer)
                self.retry.setTitle(nil, for: .normal)
                self.updateButtons()
            } catch { if !Task.isCancelled { self?.retry.setTitle(error.localizedDescription + " · 点击重试", for: .normal) } }
        }
    }
    @objc private func toggleFavorite() {
        do {
            try environment.library.setFavorite(comic, favorite: environment.library.entry(for: comic)?.isFavorite != true)
            environment.notifyLibraryChanged(); updateButtons()
        } catch { showError(error) }
    }
    private func chapters() async throws -> [Chapter] {
        if let cachedChapters { return cachedChapters }
        if directoryTask == nil {
            directoryID = UUID()
            let id = comic.comicId
            directoryTask = Task { [source] in try await source.chapters(comicId: id) }
        }
        let token = directoryID
        do {
            let result = try await directoryTask!.value
            guard directoryID == token else { throw CancellationError() }
            cachedChapters = result.isEmpty ? nil : result; directoryTask = nil
            return result
        } catch { if directoryID == token { directoryTask = nil }; throw error }
    }
    @objc private func showDirectory() {
        let controller = ChapterListViewController(load: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.chapters()
        }, selectedID: environment.library.entry(for: comic)?.reading?.chapter.chapterId) { [weak self] chapters, index in
            guard let self else { return }
            self.openReader(chapters: chapters, index: index, incomplete: false)
        }
        present(ChapterListViewController.navigation(controller), animated: true)
    }
    @objc private func startReading() {
        if let saved = environment.library.entry(for: comic)?.reading {
            // Saved chapter URL is sufficient; do not block resume on directory loading.
            openReader(chapters: [saved.chapter], index: 0, incomplete: true)
        } else {
            guard readTask == nil else { return }
            read.isEnabled = false; read.setTitle("正在加载章节…", for: .normal)
            readTask = Task { [weak self] in
                guard let self else { return }
                defer { self.readTask = nil; self.read.isEnabled = true; self.updateButtons() }
                do {
                    let items = try await self.chapters(); try Task.checkCancellation()
                    guard !items.isEmpty else {
                        self.retry.setTitle("暂无章节 · 点击章节目录刷新", for: .normal)
                        return
                    }
                    self.openReader(chapters: items, index: 0, incomplete: false)
                } catch { if !Task.isCancelled { self.showError(error) } }
            }
        }
    }
    private func openReader(chapters: [Chapter], index: Int, incomplete: Bool) {
        navigationController?.pushViewController(ReaderViewController(comic: comic, chapters: chapters,
            chapterIndex: index, directoryIncomplete: incomplete, environment: environment), animated: true)
    }
}

@MainActor
final class ChapterListViewController: UITableViewController {
    static func navigation(_ controller: ChapterListViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [
                .custom(identifier: .init("collapsed")) { $0.maximumDetentValue * 0.55 },
                .custom(identifier: .init("expanded")) { $0.maximumDetentValue * 0.92 }
            ]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        return navigation
    }
    private let load: () async throws -> [Chapter]
    private let onSelect: ([Chapter], Int) -> Void
    private let selectedID: String?
    private var chapters: [Chapter] = []
    private var descending = false
    private var task: Task<Void, Never>?
    private let state = UIButton(type: .system)
    init(load: @escaping () async throws -> [Chapter], selectedID: String?, onSelect: @escaping ([Chapter], Int) -> Void) {
        self.load = load; self.selectedID = selectedID; self.onSelect = onSelect
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "全部章节"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "正序", style: .plain, target: self, action: #selector(reverseOrder))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        state.titleLabel?.numberOfLines = 0
        state.addTarget(self, action: #selector(reload), for: .touchUpInside)
        tableView.backgroundView = state
        reload()
    }
    @objc private func reload() {
        task?.cancel(); state.setTitle("正在加载目录…", for: .normal)
        let loader = load
        task = Task { [weak self] in
            do {
                let chapters = try await loader(); try Task.checkCancellation()
                guard let self else { return }
                self.chapters = chapters
                self.state.setTitle(chapters.isEmpty ? "暂无章节 · 点击刷新" : nil, for: .normal)
                self.tableView.reloadData()
                self.scrollToSelected()
            } catch { if !Task.isCancelled { self?.state.setTitle(error.localizedDescription + " · 点击重试", for: .normal) } }
        }
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func reverseOrder() {
        descending.toggle()
        navigationItem.leftBarButtonItem?.title = descending ? "倒序" : "正序"
        tableView.reloadData()
        scrollToSelected()
    }
    private func scrollToSelected() {
        guard let selectedID, let selected = chapters.firstIndex(where: { $0.chapterId == selectedID }) else { return }
        tableView.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: descending ? chapters.count - 1 - selected : selected, section: 0), at: .top, animated: false)
    }
    private func index(_ row: Int) -> Int { descending ? chapters.count - 1 - row : row }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { chapters.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let chapter = chapters[index(indexPath.row)]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = chapter.title; cell.textLabel?.numberOfLines = 2
        cell.accessoryType = chapter.chapterId == selectedID ? .checkmark : .none
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selected = index(indexPath.row), items = chapters
        dismiss(animated: true) { [onSelect] in onSelect(items, selected) }
    }
}
