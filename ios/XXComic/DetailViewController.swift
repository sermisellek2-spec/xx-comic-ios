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
    private var readID = UUID()
    private var needsVerification = false

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
        retry.addTarget(self, action: #selector(retryDetail), for: .touchUpInside)
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
        cover.loadCover(comic, referer: source.referer, library: environment.localLibrary)
        loadDetail()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); updateButtons()
        if !detailLoaded && detailTask == nil { loadDetail() }
        if cover.image == nil { cover.loadCover(comic, referer: source.referer, library: environment.localLibrary) }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentedViewController == nil else { return }
        detailTask?.cancel(); detailTask = nil
        directoryID = UUID(); directoryTask?.cancel(); directoryTask = nil
        readID = UUID(); readTask?.cancel(); readTask = nil; read.isEnabled = true
        cover.cancel()
    }
    private func updateButtons() {
        favorite.setTitle(environment.library.entry(for: comic)?.isFavorite == true ? "已收藏 · 点击移除" : "加入书架", for: .normal)
        read.setTitle(environment.library.entry(for: comic)?.reading.map { "继续阅读\n上次看到 · \($0.chapter.title)" } ?? "开始阅读", for: .normal)
    }
    @objc private func loadDetail() {
        needsVerification = false
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
                self.cover.loadCover(detail.summary, referer: source.referer, library: self.environment.localLibrary)
                self.retry.setTitle(nil, for: .normal)
                self.updateButtons()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.needsVerification = (error as? Mh18SourceError) == .verificationRequired
                self.retry.setTitle(self.needsVerification ? "需要验证 · 去验证" : (error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试", for: .normal)
            }
        }
    }
    @objc private func retryDetail() {
        if needsVerification {
            showSourceManagement(environment: environment) { [weak self] in self?.loadDetail() }
        } else { loadDetail() }
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
        readID = UUID(); readTask?.cancel(); readTask = nil; read.isEnabled = true; updateButtons()
        let controller = ChapterListViewController(load: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.chapters()
        }, selectedID: environment.library.entry(for: comic)?.reading?.chapter.chapterId, defaults: environment.defaults, environment: environment) { [weak self] chapters, index in
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
            readID = UUID()
            let token = readID
            read.isEnabled = false; read.setTitle("正在加载章节…", for: .normal)
            readTask = Task { [weak self] in
                guard let self else { return }
                var independentlyCancelled = false
                defer {
                    if self.readID == token && !Task.isCancelled {
                        self.readTask = nil; self.read.isEnabled = true; self.updateButtons()
                        if independentlyCancelled { self.read.setTitle("已取消 · 点击重试", for: .normal) }
                    }
                }
                do {
                    let items = try await self.chapters(); try Task.checkCancellation()
                    guard self.readID == token else { return }
                    guard !items.isEmpty else {
                        self.retry.setTitle("暂无章节 · 点击章节目录刷新", for: .normal)
                        return
                    }
                    self.openReader(chapters: items, index: 0, incomplete: false)
                } catch {
                    if self.readID == token && !Task.isCancelled {
                        if error is CancellationError { independentlyCancelled = true; return }
                        self.showSourceError(error, environment: self.environment) { [weak self] in self?.startReading() }
                    }
                }
            }
        }
    }
    private func openReader(chapters: [Chapter], index: Int, incomplete: Bool) {
        guard chapters.indices.contains(index) else { return }
        if comic.sourceId == "local" {
            readID = UUID(); readTask?.cancel()
            let token = readID, target = chapters[index].chapterId, library = environment.localLibrary, id = comic.comicId
            read.isEnabled = false; read.setTitle("正在打开本地书籍…", for: .normal)
            let worker = Task.detached(priority: .userInitiated) { try library.book(id: id) }
            readTask = Task { [weak self] in
                do {
                    let book = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                    guard let self, self.readID == token, !Task.isCancelled else { return }
                    if let epub = book.epub, !epub.isPurePictureEpub {
                        let complete = try await self.source.chapters(comicId: id)
                        try Task.checkCancellation()
                        guard self.readID == token, !complete.isEmpty else { return }
                        // Resume callers deliberately pass only saved.chapter with index 0.
                        let savedIndex = self.environment.library.entry(for: self.comic)?.reading?.chapterIndex ?? 0
                        let realIndex = complete.firstIndex { $0.chapterId == target } ?? max(0, min(complete.count - 1, savedIndex))
                        let locator = self.environment.library.textPosition(for: self.comic, chapterID: complete[realIndex].chapterId)
                        let session = try EpubTextSession(book: book, chapterIndex: realIndex, locator: locator)
                        self.navigationController?.pushViewController(EpubTextReaderViewController(comic: self.comic, chapters: complete, session: session, locator: locator, environment: self.environment), animated: true)
                    } else {
                        self.navigationController?.pushViewController(ReaderViewController(comic: self.comic, chapters: chapters, chapterIndex: index, directoryIncomplete: incomplete, environment: self.environment), animated: true)
                    }
                    self.readTask = nil; self.read.isEnabled = true; self.updateButtons()
                } catch {
                    guard let self, self.readID == token, !Task.isCancelled else { return }
                    self.readTask = nil; self.read.isEnabled = true
                    let alert = UIAlertController(title: error is CancellationError ? "已取消打开" : "无法打开书籍", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                    alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in self?.openReader(chapters: chapters, index: index, incomplete: incomplete) })
                    self.present(alert, animated: true)
                }
            }
            return
        }
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
    private let onDismiss: () -> Void
    private let selectedID: String?
    private let defaults: UserDefaults
    private let environment: AppEnvironment?
    private var needsVerification = false
    private var chapters: [Chapter] = []
    private var descending = false
    private var task: Task<Void, Never>?
    private let state = UIButton(type: .system)
    init(load: @escaping () async throws -> [Chapter], selectedID: String?, defaults: UserDefaults = .standard, environment: AppEnvironment? = nil,
         onDismiss: @escaping () -> Void = {}, onSelect: @escaping ([Chapter], Int) -> Void) {
        self.load = load; self.selectedID = selectedID; self.onDismiss = onDismiss; self.onSelect = onSelect
        self.defaults = defaults; descending = defaults.bool(forKey: "chapter.desc")
        self.environment = environment
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "全部章节"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: descending ? "倒序" : "正序", style: .plain, target: self, action: #selector(reverseOrder))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        state.titleLabel?.numberOfLines = 0
        state.addTarget(self, action: #selector(stateTapped), for: .touchUpInside)
        tableView.backgroundView = state
        reload()
    }
    @objc private func reload() {
        needsVerification = false
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
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.needsVerification = self.environment != nil && (error as? Mh18SourceError) == .verificationRequired
                self.state.setTitle(self.needsVerification ? "需要验证 · 去验证" : (error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试", for: .normal)
            }
        }
    }
    @objc private func stateTapped() {
        if needsVerification, let environment {
            showSourceManagement(environment: environment) { [weak self] in self?.reload() }
        } else { reload() }
    }
    @objc private func close() { dismissSheet() }
    @objc private func reverseOrder() {
        descending.toggle()
        defaults.set(descending, forKey: "chapter.desc")
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
    private func dismissSheet(then completion: (() -> Void)? = nil) {
        dismiss(animated: true) { [onDismiss] in onDismiss(); completion?() }
    }
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
        dismissSheet { [onSelect] in onSelect(items, selected) }
    }
}
