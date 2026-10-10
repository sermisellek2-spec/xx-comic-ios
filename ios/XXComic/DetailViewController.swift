import UIKit
import ComicCore

@MainActor
final class DetailViewController: UIViewController {
    private let environment: AppEnvironment
    private var comic: ComicSummary
    private var source: any ComicSource
    private let cover = RemoteImageView()
    private let heading = UILabel()
    private let descriptionLabel = UILabel()
    private let favorite = UIButton(type: .system)
    private let read = UIButton(type: .system)
    private let directory = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)
    private let sourceSwitchButton = UIButton(type: .system)
    private let manageVolumes = UIButton(type: .system)
    private let retry = UIButton(type: .system)
    private var cachedDetail: ComicDetail?
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
        let longFav = UILongPressGestureRecognizer(target: self, action: #selector(favoriteLongPressed(_:)))
        favorite.addGestureRecognizer(longFav)
        read.addTarget(self, action: #selector(startReading), for: .touchUpInside)
        read.titleLabel?.numberOfLines = 2
        directory.setTitle("章节目录", for: .normal)
        directory.addTarget(self, action: #selector(showDirectory), for: .touchUpInside)
        downloadButton.setTitle("下载章节", for: .normal)
        downloadButton.addTarget(self, action: #selector(openDownloadSelection), for: .touchUpInside)
        sourceSwitchButton.setTitle("\(source.name) · 切换站源", for: .normal)
        sourceSwitchButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath"), for: .normal)
        sourceSwitchButton.tintColor = Palette.accent
        sourceSwitchButton.addTarget(self, action: #selector(openSourceSwitchSheet), for: .touchUpInside)
        retry.addTarget(self, action: #selector(retryDetail), for: .touchUpInside)
        retry.titleLabel?.numberOfLines = 0

        var items: [UIView] = [cover, heading, descriptionLabel, favorite, directory]
        var buttons = [favorite, directory, read, retry]
        if comic.sourceId == "local" {
            manageVolumes.setTitle("管理分卷", for: .normal)
            manageVolumes.addTarget(self, action: #selector(openVolumeManager), for: .touchUpInside)
            items.append(manageVolumes)
            buttons.append(manageVolumes)
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "管理", style: .plain, target: self, action: #selector(showLocalManagementMenu))
        } else {
            items.append(contentsOf: [sourceSwitchButton, downloadButton])
            buttons.append(contentsOf: [sourceSwitchButton, downloadButton])
            let centerItem = UIBarButtonItem(image: UIImage(systemName: "arrow.down.circle"), style: .plain, target: self, action: #selector(openDownloadCenter))
            navigationItem.rightBarButtonItem = centerItem
        }
        items.append(contentsOf: [read, retry])
        for item in items { content.addArrangedSubview(item) }
        for button in buttons { button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true }
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
        let isFav = environment.library.entry(for: comic)?.isFavorite == true
        favorite.setTitle(isFav ? "已收藏 · 点击移除" : "加入书架", for: .normal)
        if let favImg = UIImage(named: isFav ? "rem_in_bookshelf" : "rem_not_in_bookshelf") {
            favorite.setImage(favImg, for: .normal)
            favorite.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        }
        read.setTitle(environment.library.entry(for: comic)?.reading.map { "继续阅读\n上次看到 · \($0.chapter.title)" } ?? "开始阅读", for: .normal)
    }
    @objc private func loadDetail() {
        needsVerification = false
        detailTask?.cancel()
        retry.setTitle("正在加载详情…", for: .normal)
        let id = comic.comicId
        detailTask = Task { [weak self, source] in
            do {
                let detail: ComicDetail
                do {
                    detail = try await source.detail(comicId: id)
                } catch {
                    if let self,
                       let bookId = try? DownloadModels.bookId(source: self.comic.sourceId, comic: id),
                       let snapshot = self.environment.downloadStore.snapshot(id: bookId) {
                        detail = snapshot
                    } else {
                        throw error
                    }
                }
                try Task.checkCancellation()
                guard let self else { return }
                self.comic = detail.summary
                self.cachedDetail = detail
                self.detailLoaded = true
                self.heading.text = detail.summary.title
                self.descriptionLabel.text = [detail.author, detail.status, detail.description].filter { !$0.isEmpty }.joined(separator: "\n\n")
                self.cover.loadCover(detail.summary, referer: source.referer, library: self.environment.localLibrary)
                self.retry.setTitle(nil, for: .normal)
                self.updateButtons()
                let revision = FavoriteRevision.fromChapters(latestChapterName: detail.latestChapter, chapters: detail.chapters)
                self.environment.favoriteUpdateCoordinator.acknowledge(sourceId: detail.summary.sourceId, comicId: detail.summary.comicId, revision: revision)
            } catch {
                guard let self, !Task.isCancelled else { return }
                if !(error is CancellationError) {
                    ErrorLogStore.shared.append(title: "详情加载失败: \(self.comic.title)", error: error)
                }
                self.needsVerification = (error as? Mh18SourceError) == .verificationRequired
                if (error as? LocalCatalogError) == .targetNotFound {
                    self.retry.setTitle("书籍已删除 · 重新导入相同内容即可恢复", for: .normal)
                } else {
                    self.retry.setTitle(self.needsVerification ? "需要验证 · 去验证" : (error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试", for: .normal)
                }
            }
        }
    }
    @objc private func retryDetail() {
        if needsVerification {
            showSourceManagement(environment: environment) { [weak self] in self?.loadDetail() }
        } else { loadDetail() }
    }
    @objc private func openDownloadSelection() {
        if let detail = cachedDetail {
            let selectionVC = DownloadSelectionViewController(detail: detail, currentIndex: 0, environment: environment) { [weak self] in
                let alert = UIAlertController(title: "提示", message: "已加入下载队列", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self?.present(alert, animated: true)
            }
            present(selectionVC, animated: true)
        } else {
            Task {
                do {
                    let detail = try await source.detail(comicId: comic.comicId)
                    self.cachedDetail = detail
                    let selectionVC = DownloadSelectionViewController(detail: detail, currentIndex: 0, environment: environment)
                    present(selectionVC, animated: true)
                } catch {
                    showError(error)
                }
            }
        }
    }
    @objc private func openDownloadCenter() {
        let centerVC = DownloadCenterViewController(environment: environment)
        navigationController?.pushViewController(centerVC, animated: true)
    }
    @objc private func toggleFavorite() {
        do {
            try environment.library.setFavorite(comic, favorite: environment.library.entry(for: comic)?.isFavorite != true)
            environment.notifyLibraryChanged(); updateButtons()
        } catch { showError(error) }
    }
    @objc private func favoriteLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        if environment.library.entry(for: comic)?.isFavorite != true {
            try? environment.library.setFavorite(comic, favorite: true)
            environment.notifyLibraryChanged()
            updateButtons()
        }
        let sheet = BookshelfGroupSelectSheet(environment: environment, scope: .online, comicId: comic.comicId, comicTitle: comic.title)
        present(sheet, animated: true)
    }
    @objc private func openSourceSwitchSheet() {
        let sheet = SourceSwitchSheet(comic: comic, environment: environment) { [weak self] targetDetail in
            guard let self else { return }
            self.applySwitchedSource(targetDetail: targetDetail)
        }
        present(sheet, animated: true)
    }
    private func applySwitchedSource(targetDetail: ComicDetail) {
        guard let newSource = environment.source(for: targetDetail.summary) else { return }
        self.comic = targetDetail.summary
        self.source = newSource
        self.title = newSource.name
        self.sourceSwitchButton.setTitle("\(newSource.name) · 切换站源", for: .normal)
        self.sourceSwitchButton.isEnabled = true
        self.cachedDetail = targetDetail
        self.cachedChapters = targetDetail.chapters
        self.detailLoaded = true
        self.heading.text = targetDetail.summary.title
        self.descriptionLabel.text = [targetDetail.author, targetDetail.status, targetDetail.description].filter { !$0.isEmpty }.joined(separator: "\n\n")
        self.cover.loadCover(targetDetail.summary, referer: newSource.referer, library: self.environment.localLibrary)
        self.retry.setTitle(nil, for: .normal)
        self.updateButtons()
        let revision = FavoriteRevision.fromChapters(latestChapterName: targetDetail.latestChapter, chapters: targetDetail.chapters)
        self.environment.favoriteUpdateCoordinator.acknowledge(sourceId: targetDetail.summary.sourceId, comicId: targetDetail.summary.comicId, revision: revision)
    }
    private func switchToSource(target: ComicSummary) {
        guard target.comicId != comic.comicId else { return }
        guard let newSource = environment.source(for: target) else { return }
        sourceSwitchButton.setTitle("正在切换至 \(newSource.name)…", for: .normal)
        sourceSwitchButton.isEnabled = false

        Task { [weak self] in
            do {
                let targetDetail = try await newSource.detail(comicId: target.comicId)
                guard let self else { return }
                if self.environment.library.entry(for: self.comic)?.isFavorite == true {
                    try? self.environment.replaceSource(original: self.comic, target: targetDetail)
                }
                self.applySwitchedSource(targetDetail: targetDetail)
            } catch {
                guard let self else { return }
                self.sourceSwitchButton.setTitle("\(self.source.name) · 切换站源", for: .normal)
                self.sourceSwitchButton.isEnabled = true
                let alert = UIAlertController(title: "换源失败", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert, animated: true)
            }
        }
    }
    @objc private func openVolumeManager() {
        let vm = VolumeManagerViewController(seriesId: comic.comicId, seriesTitle: comic.title, environment: environment) { [weak self] in
            guard let self else { return }
            self.cachedChapters = nil
            self.loadDetail()
            self.environment.notifyLibraryChanged()
        }
        let nav = UINavigationController(rootViewController: vm)
        present(nav, animated: true)
    }
    @objc private func showLocalManagementMenu() {
        let alert = UIAlertController(title: "漫画管理", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "管理分卷", style: .default) { [weak self] _ in
            self?.openVolumeManager()
        })
        alert.addAction(UIAlertAction(title: "修改作品名称", style: .default) { [weak self] _ in
            self?.renameLocalSeries()
        })
        alert.addAction(UIAlertAction(title: "删除本地漫画", style: .destructive) { [weak self] _ in
            self?.confirmDeleteLocalSeries()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }
    @objc private func renameLocalSeries() {
        let alert = UIAlertController(title: "修改作品名称", message: "修改当前漫画的展示名称", preferredStyle: .alert)
        alert.addTextField { [weak self] in
            $0.text = self?.comic.title
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self, let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            Task {
                do {
                    _ = try await self.environment.localLibrary.renameSeries(id: self.comic.comicId, newTitle: title)
                    self.loadDetail()
                    self.environment.notifyLibraryChanged()
                } catch {
                    self.showError(error)
                }
            }
        })
        present(alert, animated: true)
    }
    @objc private func confirmDeleteLocalSeries() {
        let alert = UIAlertController(
            title: "删除本地漫画",
            message: "将从书架和 App 本地存储中移除此漫画，原导入文件不受影响。\n（若以后重新导入相同文件，阅读历史和进度将自动恢复）",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "删除 App 副本", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await self.environment.localLibrary.deleteSeries(id: self.comic.comicId)
                    try? self.environment.library.setFavorite(self.comic, favorite: false)
                    self.environment.notifyLibraryChanged()
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    self.showError(error)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }
    private func chapters() async throws -> [Chapter] {
        if let cachedChapters { return cachedChapters }
        if directoryTask == nil {
            directoryID = UUID()
            let id = comic.comicId
            let sourceId = comic.sourceId
            directoryTask = Task { [source, weak self] in
                do {
                    return try await source.chapters(comicId: id)
                } catch {
                    if let self,
                       let bookId = try? DownloadModels.bookId(source: sourceId, comic: id),
                       let snapshot = self.environment.downloadStore.snapshot(id: bookId),
                       !snapshot.chapters.isEmpty {
                        return snapshot.chapters
                    }
                    throw error
                }
            }
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
                        ErrorLogStore.shared.append(title: "目录加载失败: \(self.comic.title)", error: error)
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
            let token = readID, targetChapter = chapters[index], library = environment.localLibrary, id = comic.comicId
            read.isEnabled = false; read.setTitle("正在打开本地书籍…", for: .normal)
            readTask = Task { [weak self] in
                do {
                    let target = try await library.readingTarget(seriesId: id, chapterId: targetChapter.chapterId)
                    guard let self, self.readID == token, !Task.isCancelled else { return }
                    if target.kind == .text {
                        let book = try library.book(id: target.volumeId)
                        let complete = try await self.source.chapters(comicId: id)
                        try Task.checkCancellation()
                        guard self.readID == token, !complete.isEmpty else { return }
                        let savedIndex = self.environment.library.entry(for: self.comic)?.reading?.chapterIndex ?? 0
                        let realIndex = complete.firstIndex { $0.chapterId == targetChapter.chapterId } ?? max(0, min(complete.count - 1, savedIndex))
                        let savedLocator = self.environment.library.textPosition(for: self.comic, chapterID: complete[realIndex].chapterId)
                        let volLocator = savedLocator?.toVolumeLocator(volumeId: target.volumeId, volumeChapterIndex: target.volumeChapterIndex)
                        let session = try EpubTextSession(book: book, chapterIndex: target.volumeChapterIndex, locator: volLocator)
                        self.navigationController?.pushViewController(EpubTextReaderViewController(comic: self.comic, chapters: complete, session: session, locator: volLocator, environment: self.environment), animated: true)
                    } else {
                        let complete = incomplete ? try await self.source.chapters(comicId: id) : chapters
                        try Task.checkCancellation()
                        guard self.readID == token, !complete.isEmpty else { return }
                        let realIndex = complete.firstIndex { $0.chapterId == targetChapter.chapterId } ?? target.globalChapterIndex
                        self.navigationController?.pushViewController(ReaderViewController(comic: self.comic, chapters: complete, chapterIndex: realIndex, directoryIncomplete: false, environment: self.environment), animated: true)
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
