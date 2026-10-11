import UIKit
import ComicCore
import UniformTypeIdentifiers

struct ComicGridAnchor {
    let sourceID: String
    let comicID: String
    let previousIndex: Int
    let offset: CGFloat
}

@MainActor
class ComicGridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    let environment: AppEnvironment
    let header = UIStackView()
    let statusButton = UIButton(type: .system)
    let collection: UICollectionView
    var comics: [ComicSummary] = []
    var retry: (() -> Void)?
    var isListLayout: Bool = false
    var usesBookshelfLayout: Bool { false }
    func bookshelfStatus(for comic: ComicSummary) -> BookshelfReadingStatus? { nil }
    private let emptyArtwork = UIImageView(image: UIImage(named: "rem_empty"))

    init(environment: AppEnvironment) {
        self.environment = environment
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 12, left: 14, bottom: 24, right: 14)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        header.axis = .vertical
        header.spacing = 8
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        statusButton.titleLabel?.numberOfLines = 0
        statusButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        statusButton.addTarget(self, action: #selector(retryPressed), for: .touchUpInside)
        collection.backgroundColor = Palette.background
        collection.register(ComicCell.self, forCellWithReuseIdentifier: "comic")
        collection.register(ComicListCell.self, forCellWithReuseIdentifier: "comic_list")
        collection.dataSource = self
        collection.delegate = self
        emptyArtwork.contentMode = .scaleAspectFit
        let emptyHost = UIView()
        emptyArtwork.translatesAutoresizingMaskIntoConstraints = false; emptyHost.addSubview(emptyArtwork)
        NSLayoutConstraint.activate([
            emptyArtwork.centerXAnchor.constraint(equalTo: emptyHost.centerXAnchor),
            emptyArtwork.centerYAnchor.constraint(equalTo: emptyHost.centerYAnchor),
            emptyArtwork.widthAnchor.constraint(equalToConstant: 180),
            emptyArtwork.heightAnchor.constraint(equalToConstant: 180)
        ])
        collection.backgroundView = emptyHost
        for item in [header, collection, statusButton] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor), collection.topAnchor.constraint(equalTo: header.bottomAnchor),
            collection.leadingAnchor.constraint(equalTo: view.leadingAnchor), collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: statusButton.topAnchor), statusButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), statusButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
    }
    @objc private func retryPressed() { retry?() }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentedViewController == nil else { return }
        collection.visibleCells.forEach {
            ($0 as? ComicCell)?.cover.cancel()
            ($0 as? ComicListCell)?.cover.cancel()
        }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collection.reloadData()
    }
    func status(_ text: String, retry: (() -> Void)? = nil) {
        statusButton.setTitle(text, for: .normal); self.retry = retry
        emptyArtwork.isHidden = !comics.isEmpty
        emptyArtwork.image = UIImage(named: retry != nil ? "rem_error" : (text.contains("正在") ? "rem_loading" : "rem_empty"))
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { comics.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let comic = comics[indexPath.item]
        let readingStatus = bookshelfStatus(for: comic)
        let hasUpdate = environment.favoriteUpdateCoordinator.hasPendingUpdate(sourceId: comic.sourceId, comicId: comic.comicId)
        let badgeText = readingStatus.map { BookshelfLayoutHelper.formatUnreadBadgeText(count: $0.unreadCount) }
        let badgeColor = hasUpdate ? Palette.updateBlue : Palette.noUpdateGray
        let source = environment.source(for: comic)

        if isListLayout {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "comic_list", for: indexPath) as! ComicListCell
            cell.configure(comic, referer: source?.referer ?? "", library: environment.localLibrary,
                           subtitle: readingStatus == nil ? nil : source?.name,
                           detail: readingStatus.map { BookshelfLayoutHelper.formatOnlineLatestChapter($0.latestChapter) + "\n阅读至 " + $0.readingDescription },
                           badgeText: badgeText, badgeColor: badgeColor, largeCover: usesBookshelfLayout)
            cell.accessibilityValue = readingStatus.map { "未读 \($0.unreadCount < 0 ? "未知" : String($0.unreadCount)) · " + BookshelfLayoutHelper.formatOnlineLatestChapter($0.latestChapter) }
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "comic", for: indexPath) as! ComicCell
            cell.configure(comic, referer: source?.referer ?? "", library: environment.localLibrary,
                           badgeText: badgeText, badgeColor: badgeColor,
                           sourceName: usesBookshelfLayout ? source?.name : nil, latestChapter: readingStatus?.latestChapter)
            cell.accessibilityValue = readingStatus.map { "未读 \($0.unreadCount < 0 ? "未知" : String($0.unreadCount)) · " + BookshelfLayoutHelper.formatOnlineLatestChapter($0.latestChapter) }
            return cell
        }
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let contentWidth = max(0, collectionView.bounds.width - 28)
        if isListLayout {
            return CGSize(width: contentWidth, height: usesBookshelfLayout ? 111 : 88)
        }
        let spacing: CGFloat = 10
        let minCardWidth: CGFloat = 105
        let cols = max(3, Int((contentWidth + spacing) / (minCardWidth + spacing)))
        let totalSpacing = CGFloat(cols - 1) * spacing
        let cardWidth = floor(max(1, (contentWidth - totalSpacing) / CGFloat(cols)))
        let cardHeight = floor(cardWidth * 4 / 3) + 42
        return CGSize(width: cardWidth, height: cardHeight)
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        open(comics[indexPath.item])
    }
    func open(_ comic: ComicSummary) {
        guard environment.source(for: comic) != nil else { status("该站源暂不可用，已保留阅读记录。"); return }
        navigationController?.pushViewController(DetailViewController(comic: comic, environment: environment), animated: true)
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let anchor = captureAnchor()
        coordinator.animate(alongsideTransition: { _ in self.collection.collectionViewLayout.invalidateLayout() }, completion: { _ in self.restoreAnchor(anchor) })
    }
    func captureAnchor() -> ComicGridAnchor? {
        let top = collection.contentOffset.y + collection.adjustedContentInset.top
        let visible = collection.indexPathsForVisibleItems.sorted { $0.item < $1.item }
        guard let index = visible.first(where: {
            (collection.layoutAttributesForItem(at: $0)?.frame.maxY ?? 0) > top
        }), comics.indices.contains(index.item), let frame = collection.layoutAttributesForItem(at: index)?.frame else { return nil }
        let comic = comics[index.item]
        return ComicGridAnchor(sourceID: comic.sourceId, comicID: comic.comicId, previousIndex: index.item, offset: top - frame.minY)
    }
    func restoreAnchor(_ anchor: ComicGridAnchor?) {
        collection.layoutIfNeeded()
        let minimum = -collection.adjustedContentInset.top
        guard let anchor, !comics.isEmpty else {
            collection.setContentOffset(CGPoint(x: 0, y: minimum), animated: false); return
        }
        let index = comics.firstIndex { $0.sourceId == anchor.sourceID && $0.comicId == anchor.comicID } ?? min(anchor.previousIndex, comics.count - 1)
        guard let frame = collection.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        let maximum = max(minimum, collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom)
        let target = min(maximum, max(minimum, frame.minY + anchor.offset - collection.adjustedContentInset.top))
        collection.setContentOffset(CGPoint(x: 0, y: target), animated: false)
    }
}

@MainActor
final class BookshelfViewController: ComicGridViewController, UIDocumentPickerDelegate {
    private let historyOnly: Bool
    private let resume = UIButton(type: .system)
    private let shelfMode = BookshelfTabsView()
    private let groupBar = BookshelfGroupBar()
    private let floatingBubble = FloatingImportBubble()
    private var currentGroupId: String = BookshelfGroupStore.builtinOnlineAllId
    private var currentScope: BookshelfScope { localMode ? .local : .online }
    private var layoutItem: UIBarButtonItem?
    private var importTask: Task<Void, Never>?
    private var downloadSelectionTask: Task<Void, Never>?
    private var downloadSelectionID = UUID()
    private var refreshTask: Task<Void, Never>?
    private var refreshID = UUID()
    private var renderedContext: String?
    private var context: String { "\(historyOnly)-\(currentScope.rawValue)-\(currentGroupId)" }
    override var usesBookshelfLayout: Bool { !historyOnly }
    override func bookshelfStatus(for comic: ComicSummary) -> BookshelfReadingStatus? {
        guard !historyOnly, !localMode else { return nil }
        let state = environment.favoriteUpdateCoordinator.state(sourceId: comic.sourceId, comicId: comic.comicId)
        return BookshelfReadingStatus(comic: comic, reading: environment.library.entry(for: comic)?.reading, revision: state?.observedRevision)
    }
    private enum ImportKind: Sendable { case images, folder, archive, epub, pdf, kindle }
    private var importKind = ImportKind.images
    private var localMode: Bool { !historyOnly && shelfMode.selectedSegmentIndex == 1 }

    init(environment: AppEnvironment, historyOnly: Bool = false) {
        self.historyOnly = historyOnly
        super.init(environment: environment)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = historyOnly ? "阅读历史" : "书架"
        if !historyOnly {
            environment.favoriteUpdateCoordinator.onRevisionObserved = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.viewIfLoaded?.window != nil else { return }
                    let anchor = self.captureAnchor()
                    self.collection.reloadData()
                    self.restoreAnchor(anchor)
                }
            }
            let layoutImg = UIImage(systemName: isListLayout ? "square.grid.2x2" : "list.bullet")
            let layoutButton = UIBarButtonItem(image: layoutImg, style: .plain, target: self, action: #selector(toggleLayoutTapped))
            layoutItem = layoutButton
            layoutButton.accessibilityIdentifier = "bookshelf.layout"
            let artwork = UIImageView(image: UIImage(named: "rem_reader_resume"))
            artwork.contentMode = .scaleAspectFill; artwork.clipsToBounds = true; artwork.layer.cornerRadius = 11.5
            artwork.frame = CGRect(x: 0, y: 0, width: 23, height: 23)
            artwork.isAccessibilityElement = true; artwork.accessibilityLabel = "蕾姆主题"
            navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: artwork), layoutButton]
            shelfMode.selectedSegmentIndex = environment.readingHabits.currentLaunchTab
            shelfMode.addTarget(self, action: #selector(shelfChanged), for: .valueChanged)
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: shelfMode)

            groupBar.onGroupSelected = { [weak self] group in
                self?.currentGroupId = group.id
                self?.refresh()
            }
            groupBar.onManageGroups = { [weak self] in
                self?.showGroupManagementSheet()
            }
            header.addArrangedSubview(groupBar)

            resume.titleLabel?.numberOfLines = 2
            resume.contentHorizontalAlignment = .leading
            resume.addTarget(self, action: #selector(continueReading), for: .touchUpInside)
            header.addArrangedSubview(resume)

            floatingBubble.onTap = { [weak self] in self?.importImages() }
            view.addSubview(floatingBubble)

            checkPendingBatchSession()
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "清空", style: .plain, target: self, action: #selector(clearHistoryTapped))
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !historyOnly {
            floatingBubble.positionInParent()
        }
    }

    @objc private func toggleLayoutTapped() {
        let anchor = captureAnchor()
        let nextGrid = isListLayout
        BookshelfLayoutHelper.setGridMode(defaults: environment.defaults, scope: currentScope, isGrid: nextGrid)
        isListLayout = !nextGrid
        let layoutImg = UIImage(systemName: isListLayout ? "square.grid.2x2" : "list.bullet")
        layoutItem?.image = layoutImg
        collection.collectionViewLayout.invalidateLayout()
        collection.reloadData()
        restoreAnchor(anchor)
    }

    private func showGroupManagementSheet() {
        let sheet = BookshelfGroupSheet(environment: environment, scope: currentScope, selectedGroupId: currentGroupId)
        sheet.onGroupSelected = { [weak self] group in
            self?.currentGroupId = group.id
            self?.refresh()
        }
        sheet.onGroupsChanged = { [weak self] in
            self?.refresh()
        }
        let nav = UINavigationController(rootViewController: sheet)
        present(nav, animated: true)
    }

    private func checkPendingBatchSession() {
        let sessionURL = environment.localLibrary.directory.appendingPathComponent("batch_import_session.json")
        guard FileManager.default.fileExists(atPath: sessionURL.path) else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let session = try? BatchImportSession(file: sessionURL),
                  let current = await session.current(),
                  current.groups.contains(where: { $0.items.contains { $0.state == .pending || $0.state == .failed } }) else { return }
            let pendingCount = current.groups.flatMap(\.items).filter { $0.state == .pending || $0.state == .failed }.count
            guard pendingCount > 0 else { return }
            let alert = UIAlertController(
                title: "未完成的批量导入",
                message: "上次导入有 \(pendingCount) 个项目未完成，是否重新选择文件恢复？",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "忽略", style: .cancel))
            alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
                try? FileManager.default.removeItem(at: sessionURL)
            })
            alert.addAction(UIAlertAction(title: "选择文件恢复", style: .default) { [weak self] _ in
                self?.pickBatchImport()
            })
            self.present(alert, animated: true)
        }
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); refresh() }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentedViewController == nil {
            cancelDownloadSelection()
            refreshID = UUID(); refreshTask?.cancel(); refreshTask = nil
        }
    }

    private func cancelDownloadSelection() {
        guard downloadSelectionTask != nil else { return }
        downloadSelectionID = UUID()
        downloadSelectionTask?.cancel(); downloadSelectionTask = nil
        status("")
    }

    private func openDownloadSelection(_ comic: ComicSummary) {
        guard let source = environment.source(for: comic) else { open(comic); return }
        cancelDownloadSelection()
        downloadSelectionID = UUID()
        let token = downloadSelectionID
        status("正在加载目录 · 点击取消") { [weak self] in self?.cancelDownloadSelection() }
        downloadSelectionTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.downloadSelectionID == token { self.downloadSelectionTask = nil } }
            do {
                let detail = try await source.detail(comicId: comic.comicId)
                let prepared = try await detail.ensuringChapters { try await source.chapters(comicId: comic.comicId) }
                try Task.checkCancellation()
                guard self.downloadSelectionID == token, self.viewIfLoaded?.window != nil,
                      self.presentedViewController == nil else { return }
                let saved = self.environment.library.entry(for: comic)?.reading
                let current = prepared.chapters.firstIndex { $0.chapterId == saved?.chapter.chapterId } ?? saved?.chapterIndex ?? 0
                self.status("")
                let selection = DownloadSelectionViewController(detail: prepared, currentIndex: current, environment: self.environment) { [weak self] in
                    self?.status("已加入下载队列")
                }
                self.present(selection, animated: true)
            } catch {
                guard self.downloadSelectionID == token, !Task.isCancelled else { return }
                if (error as? Mh18SourceError) == .verificationRequired {
                    self.status("需要验证 · 点击重试") { [weak self] in self?.openDownloadSelection(comic) }
                    self.showSourceError(error, environment: self.environment) { [weak self] in self?.openDownloadSelection(comic) }
                } else {
                    self.status((error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试") { [weak self] in
                        self?.openDownloadSelection(comic)
                    }
                }
            }
        }
    }
    private func refresh() {
        refreshID = UUID(); refreshTask?.cancel(); refreshTask = nil
        let token = refreshID, currentContext = context
        let anchor = renderedContext == currentContext ? captureAnchor() : nil
        isListLayout = !BookshelfLayoutHelper.isGridMode(defaults: environment.defaults, scope: currentScope)
        let layoutImg = UIImage(systemName: isListLayout ? "square.grid.2x2" : "list.bullet")
        layoutItem?.image = layoutImg

        if !historyOnly {
            floatingBubble.isHidden = !localMode
            let groups = environment.bookshelfGroupStore.getGroups(scope: currentScope)
            if !groups.contains(where: { $0.id == currentGroupId }) {
                currentGroupId = (currentScope == .online) ? BookshelfGroupStore.builtinOnlineAllId : BookshelfGroupStore.builtinLocalAllId
            }
            groupBar.configure(groups: groups, selectedId: currentGroupId)
            groupBar.isHidden = false
        } else {
            groupBar.isHidden = true
            floatingBubble.isHidden = true
        }

        if localMode {
            resume.isHidden = true
            refreshTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let series = try await self.environment.localLibrary.series()
                    var list = series.compactMap { try? self.environment.localLibrary.summary(for: $0) }
                    let tasks = self.environment.downloadStore.list()
                    let completedBookIDs = Set(tasks.filter { $0.state == .completed }.map(\.bookId))
                    for bookId in completedBookIDs {
                        if let snapshot = self.environment.downloadStore.snapshot(id: bookId) {
                            if !list.contains(where: { $0.comicId == snapshot.summary.comicId && $0.sourceId == snapshot.summary.sourceId }) {
                                list.append(snapshot.summary)
                            }
                        }
                    }
                    if self.currentGroupId != BookshelfGroupStore.builtinLocalAllId {
                        let members = self.environment.bookshelfGroupStore.getMembers(groupId: self.currentGroupId)
                        list = list.filter { members.contains($0.comicId) }
                    }
                    guard self.refreshID == token, self.context == currentContext, !Task.isCancelled else { return }
                    self.comics = list.filter { comic in
                        if comic.sourceId == "local" { return !self.environment.localDeletion.containsLocalSeries(comic.comicId) }
                        guard let id = try? DownloadModels.bookId(source: comic.sourceId, comic: comic.comicId) else { return true }
                        return !self.environment.localDeletion.containsDownloadBook(id)
                    }
                    self.renderedContext = currentContext
                    self.collection.reloadData()
                    self.restoreAnchor(anchor)
                    self.status(self.comics.isEmpty ? "本地书架空空的，点击导入添加图片、文件夹、ZIP/CBZ、EPUB、PDF 或 Kindle" : "")
                } catch {
                    guard self.refreshID == token, !Task.isCancelled else { return }
                    self.status(error.localizedDescription) { [weak self] in self?.refresh() }
                }
            }
            return
        }
        var list = (historyOnly ? environment.library.history : environment.library.favorites).map(\.summary)
        if !historyOnly && currentGroupId != BookshelfGroupStore.builtinOnlineAllId {
            let members = environment.bookshelfGroupStore.getMembers(groupId: currentGroupId)
            list = list.filter { members.contains($0.comicId) }
        }
        comics = list
        renderedContext = currentContext
        collection.reloadData()
        restoreAnchor(anchor)
        status(comics.isEmpty ? (historyOnly ? "还没有阅读记录" : "书架空空的，去发现页找漫画吧") : "")
        let recent = environment.library.history.first
        resume.isHidden = recent == nil || historyOnly
        resume.setTitle(recent.map { "继续阅读 · \($0.summary.title)\n\($0.reading?.chapter.title ?? "")" }, for: .normal)
        if !historyOnly {
            environment.favoriteUpdateChecker.startAutoCheck()
        }
    }
    @objc private func showHistory() {
        navigationController?.pushViewController(BookshelfViewController(environment: environment, historyOnly: true), animated: true)
    }
    @objc private func shelfChanged() {
        environment.readingHabits.lastManualTab = shelfMode.selectedSegmentIndex
        currentGroupId = localMode ? BookshelfGroupStore.builtinLocalAllId : BookshelfGroupStore.builtinOnlineAllId
        refresh()
    }
    @objc private func importImages() {
        if let importTask { importTask.cancel(); return }
        let menu = UIAlertController(title: "导入本地漫画", message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "批量导入多文件 (ZIP/EPUB/PDF)", style: .default) { [weak self] _ in self?.pickBatchImport() })
        menu.addAction(UIAlertAction(title: "图片文件 (合并为一卷)", style: .default) { [weak self] _ in self?.pickImport(.images) })
        menu.addAction(UIAlertAction(title: "图片文件夹", style: .default) { [weak self] _ in self?.pickImport(.folder) })
        menu.addAction(UIAlertAction(title: "ZIP / CBZ 压缩包", style: .default) { [weak self] _ in self?.pickImport(.archive) })
        menu.addAction(UIAlertAction(title: "EPUB 电子书", style: .default) { [weak self] _ in self?.pickImport(.epub) })
        menu.addAction(UIAlertAction(title: "PDF 文档", style: .default) { [weak self] _ in self?.pickImport(.pdf) })
        menu.addAction(UIAlertAction(title: "Kindle 电子书", style: .default) { [weak self] _ in self?.pickImport(.kindle) })
        #if DEBUG
        // Fixture URLs exist only under the isolated UI-test library, using the real import worker.
        for (name, url) in EpubUITestFixtures.kindleImports(library: environment.localLibrary) {
            menu.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in self?.confirmImport([url], kind: .kindle) })
        }
        #endif
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        menu.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(menu, animated: true)
    }
    private func pickBatchImport() {
        let types: [UTType] = [.zip, .epub, .pdf, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }
    private func pickImport(_ kind: ImportKind) {
        importKind = kind
        let types: [UTType]
        switch kind {
        case .images: types = [.image]
        case .folder: types = [.folder]
        case .archive: types = [.zip, UTType(filenameExtension: "cbz", conformingTo: .archive) ?? .archive]
        case .epub: types = [UTType(filenameExtension: "epub") ?? .data]
        case .pdf: types = [.pdf]
        case .kindle:
            let available = ["mobi", "azw", "azw3"].compactMap { UTType(filenameExtension: $0) }
            types = available.count == 3 ? available : [.data]
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: kind == .images)
        picker.allowsMultipleSelection = kind != .folder
        picker.delegate = self
        present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count > 1 && importKind != .images {
            var urlMap: [String: URL] = [:]
            let candidates = urls.enumerated().compactMap { idx, url -> BatchImportCandidate? in
                urlMap[url.path] = url
                return try? BatchImportCandidate(
                    fileName: url.lastPathComponent,
                    fileId: url.path,
                    format: url.pathExtension,
                    selectionIndex: idx
                )
            }
            let confirmVC = BatchImportConfirmationViewController(candidates: candidates, urlMap: urlMap) { [weak self] groups, finalUrlMap in
                self?.beginBatchImport(groups: groups, urlMap: finalUrlMap)
            }
            let nav = UINavigationController(rootViewController: confirmVC)
            present(nav, animated: true)
        } else {
            confirmImport(urls, kind: importKind, picker: controller)
        }
    }
    private func confirmImport(_ urls: [URL], kind: ImportKind, picker: UIViewController? = nil) {
        guard !urls.isEmpty else { return }
        let prompt: (String, String)
        switch kind {
        case .images: prompt = ("导入图片漫画", "所选图片合并为一本漫画，按文件名自然排序。")
        case .folder: prompt = ("导入文件夹漫画", "支持图片和章节子目录，按自然顺序导入。")
        case .archive: prompt = ("导入压缩包漫画", "仅支持 ZIP / CBZ，按目录自然分章。原压缩包会保留。")
        case .epub: prompt = ("导入 EPUB 电子书", "支持文字、图文与纯图片 EPUB，保留原文件和完整目录。不支持 DRM 加密电子书。")
        case .pdf: prompt = ("导入 PDF 文档", "按页阅读，保留原文件。不支持密码保护的 PDF。")
        case .kindle: prompt = ("导入 Kindle 电子书", "选择 MOBI、AZW 或 AZW3 文件，保留原文件。支持可转换的旧版 Kindle 内容，不支持 DRM 加密和纯 KF8 电子书。")
        }
        let alert = UIAlertController(title: prompt.0, message: prompt.1, preferredStyle: .alert)
        alert.addTextField { $0.text = kind == .folder ? urls.first?.lastPathComponent : urls.first?.deletingPathExtension().lastPathComponent }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "导入", style: .default) { [weak self, weak alert] _ in
            self?.beginImport(urls, title: alert?.textFields?.first?.text ?? "本地漫画", kind: kind)
        })
        if let picker, presentedViewController === picker {
            picker.dismiss(animated: true) { [weak self] in self?.present(alert, animated: true) }
        } else { present(alert, animated: true) }
    }
    private func beginBatchImport(groups: [BatchImportGroup], urlMap: [String: URL]) {
        let library = environment.localLibrary
        status("正在准备批量导入…，再次点击导入可取消")
        var currentWorker: BatchImportWorker?
        importTask = Task { [weak self] in
            do {
                guard let self else { return }
                let sessionURL = library.directory.appendingPathComponent("batch_import_session.json")
                let session = try BatchImportSession(file: sessionURL)
                let worker = BatchImportWorker(
                    library: library,
                    session: session,
                    isReadableImage: LocalImageProbe.isReadable,
                    inspectPdf: PdfRenderer.inspect,
                    renderPdfCover: { try PdfRenderer.render($0, pageIndex: 0, maximumDimension: 720, quality: 0.85) }
                )
                currentWorker = worker
                let summary = try await worker.execute(groups: groups, urlMap: urlMap) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.status("正在导入 \(progress.itemName) (\(progress.itemIndex + 1)/\(progress.totalItemsInGroup))…")
                    }
                }
                self.shelfMode.selectedSegmentIndex = 1
                self.refresh()
                if summary.failedCount > 0 {
                    self.status("导入完成：\(summary.succeededCount) 卷成功，\(summary.failedCount) 卷失败")
                    let alert = UIAlertController(
                        title: "批量导入完成",
                        message: "\(summary.succeededCount) 卷成功，\(summary.failedCount) 卷失败。\n是否重试失败项目？",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "稍后", style: .cancel))
                    alert.addAction(UIAlertAction(title: "重试失败项", style: .default) { [weak self] _ in
                        self?.retryBatchImport(worker: worker, urlMap: urlMap)
                    })
                    self.present(alert, animated: true)
                } else {
                    self.status("批量导入完成，共 \(summary.succeededCount) 卷")
                }
            } catch {
                self?.status(error is CancellationError ? "已取消导入，原文件未改动" : error.localizedDescription)
            }
            self?.importTask = nil
        }
    }
    private func retryBatchImport(worker: BatchImportWorker, urlMap: [String: URL]) {
        status("正在重试失败项…")
        importTask = Task { [weak self] in
            do {
                guard let self else { return }
                let summary = try await worker.retryFailed(urlMap: urlMap) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.status("正在重试 \(progress.itemName) (\(progress.itemIndex + 1)/\(progress.totalItemsInGroup))…")
                    }
                }
                self.refresh()
                self.status("重试完成：\(summary.succeededCount) 卷成功，\(summary.failedCount) 卷失败")
            } catch {
                self?.status(error is CancellationError ? "已取消重试" : error.localizedDescription)
            }
            self?.importTask = nil
        }
    }
    private func beginImport(_ urls: [URL], title: String, kind: ImportKind) {
        let library = environment.localLibrary
        status(kind == .archive ? "正在校验并导入压缩包…，再次点击导入可取消" : "正在导入…，再次点击导入可取消")
        let worker = Task.detached(priority: .userInitiated) {
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            if kind == .pdf, let url = urls.first {
                return try library.importPdf(title: title, file: url, inspect: PdfRenderer.inspect,
                                             renderCover: { try PdfRenderer.render($0, pageIndex: 0, maximumDimension: 720, quality: 0.85) })
            }
            if kind == .epub, let url = urls.first {
                return try library.importEpub(title: title, archive: url, isReadableImage: LocalImageProbe.isReadable)
            }
            if kind == .kindle, let url = urls.first {
                guard let format = LocalKindleFormat(rawValue: url.pathExtension.lowercased()) else { throw LocalLibraryError.invalidBook }
                return try library.importKindle(title: title, source: url, format: format, isReadableImage: LocalImageProbe.isReadable)
            }
            if kind == .archive, let url = urls.first {
                return try library.importArchive(title: title, archive: url, isReadableImage: LocalImageProbe.isReadable)
            }
            if kind == .folder, let url = urls.first {
                return try library.importFolder(title: title, folder: url, isReadableImage: LocalImageProbe.isReadable)
            }
            for url in urls {
                try Task.checkCancellation()
                guard try LocalImageProbe.isReadable(url) else { throw LocalLibraryError.invalidBook }
            }
            return try library.importImages(title: title, files: urls)
        }
        importTask = Task { [weak self] in
            do {
                _ = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self else { return }
                self.shelfMode.selectedSegmentIndex = 1; self.refresh()
                self.status("导入完成")
            } catch {
                self?.status(error is CancellationError ? "已取消导入，原文件未改动" : error.localizedDescription)
            }
            self?.importTask = nil
        }
    }
    deinit { importTask?.cancel(); downloadSelectionTask?.cancel() }
    @objc private func continueReading() { if let recent = environment.library.history.first { open(recent.summary) } }
    @objc private func clearHistoryTapped() {
        guard !comics.isEmpty else { return }
        let alert = UIAlertController(
            title: "清空全部阅读历史？",
            message: "所有已读章节记录都会被清空，书架收藏不受影响。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            guard let self else { return }
            try? self.environment.library.clearHistory()
            self.environment.notifyLibraryChanged()
            self.refresh()
        })
        present(alert, animated: true)
    }
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let comic = comics[indexPath.item]
        if historyOnly {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let deleteAction = UIAction(title: "删除此条历史", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    try? self.environment.library.deleteHistory(for: comic)
                    if comic.sourceId == "local" {
                        Task { try? await self.environment.localLibrary.catalogStore.removeTombstones(forSeriesId: comic.comicId) }
                    }
                    self.environment.notifyLibraryChanged()
                    self.refresh()
                }
                return UIMenu(children: [deleteAction])
            }
        }
        if localMode {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                let moveAction = UIAction(title: "移动", image: UIImage(systemName: "folder")) { [weak self] _ in
                    guard let self else { return }
                    let sheet = BookshelfGroupSelectSheet(environment: self.environment, scope: .local, comicId: comic.comicId, comicTitle: comic.title)
                    sheet.onGroupsUpdated = { [weak self] _ in self?.refresh() }
                    let nav = UINavigationController(rootViewController: sheet)
                    self.present(nav, animated: true)
                }
                let manageAction = UIAction(title: "管理分卷", image: UIImage(systemName: "square.stack.3d.up")) { [weak self] _ in
                    guard let self else { return }
                    let vm = VolumeManagerViewController(seriesId: comic.comicId, seriesTitle: comic.title, environment: self.environment) { [weak self] in
                        self?.refresh()
                    }
                    let nav = UINavigationController(rootViewController: vm)
                    self.present(nav, animated: true)
                }
                let renameAction = UIAction(title: "修改作品名称", image: UIImage(systemName: "pencil")) { [weak self] _ in
                    guard let self else { return }
                    let alert = UIAlertController(title: "修改作品名称", message: nil, preferredStyle: .alert)
                    alert.addTextField { $0.text = comic.title; $0.clearButtonMode = .whileEditing }
                    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                    alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
                        guard let self, let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
                        Task {
                            _ = try? await self.environment.localLibrary.renameSeries(id: comic.comicId, newTitle: title)
                            self.refresh()
                        }
                    })
                    self.present(alert, animated: true)
                }
                let isDownload = comic.sourceId != "local" || (try? DownloadModels.bookId(source: comic.sourceId, comic: comic.comicId)).flatMap { self.environment.downloadStore.snapshot(id: $0) } != nil
                let deleteTitle = isDownload ? "删除离线漫画" : "删除本地漫画"
                let deleteMessage = isDownload
                    ? "将从本地存储中彻底移除离线下载文件与任务。\n（在线收藏与阅读记录将完整保留）"
                    : "将从书架和 App 本地存储中移除此漫画，原导入文件不受影响。\n（若以后重新导入相同文件，阅读历史和进度将自动恢复）"
                let deleteAction = UIAction(title: deleteTitle, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    let alert = UIAlertController(
                        title: deleteTitle,
                        message: deleteMessage,
                        preferredStyle: .actionSheet
                    )
                    alert.addAction(UIAlertAction(title: isDownload ? "删除离线内容" : "删除 App 副本", style: .destructive) { [weak self] _ in
                        guard let self else { return }
                        let target: LocalDeletionTarget
                        if isDownload {
                            guard let id = try? DownloadModels.bookId(source: comic.sourceId, comic: comic.comicId) else { self.status("无法识别下载书籍，文件已保留"); return }
                            target = .downloadBook(id)
                        } else { target = .localSeries(comic.comicId) }
                        self.environment.localDeletion.schedule([.init(target: target, title: comic.title, groupComicID: comic.comicId)], from: self)
                        self.refresh()
                    })
                    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                    if let popover = alert.popoverPresentationController {
                        if let cell = self.collection.cellForItem(at: indexPath) {
                            popover.sourceView = cell
                            popover.sourceRect = cell.bounds
                        } else {
                            popover.sourceView = self.view
                            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                            popover.permittedArrowDirections = []
                        }
                    }
                    self.present(alert, animated: true)
                }
                return UIMenu(children: [moveAction, manageAction, renameAction, deleteAction])
            }
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let moveAction = UIAction(title: "移动", image: UIImage(systemName: "folder")) { [weak self] _ in
                guard let self else { return }
                let sheet = BookshelfGroupSelectSheet(environment: self.environment, scope: .online, comicId: comic.comicId, comicTitle: comic.title)
                sheet.onGroupsUpdated = { [weak self] _ in self?.refresh() }
                let nav = UINavigationController(rootViewController: sheet)
                self.present(nav, animated: true)
            }
            let switchSourceAction = UIAction(title: "换源", image: UIImage(systemName: "arrow.triangle.2.circlepath")) { [weak self] _ in
                guard let self else { return }
                let sheet = SourceSwitchSheet(environment: self.environment, originalComic: comic)
                sheet.onSourceReplaced = { [weak self] _ in self?.refresh() }
                let nav = UINavigationController(rootViewController: sheet)
                self.present(nav, animated: true)
            }
            let downloadAction = UIAction(title: "下载", image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in
                self?.openDownloadSelection(comic)
            }
            let deleteAction = UIAction(title: "移出收藏", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                guard let self else { return }
                do {
                    try self.environment.setFavorite(comic, favorite: false)
                    self.refresh()
                    self.status("已移出收藏 · 点击撤销") { [weak self] in
                        guard let self else { return }
                        do { try self.environment.setFavorite(comic, favorite: true); self.refresh() }
                        catch { self.showError(error) }
                    }
                } catch { self.showError(error) }
            }
            return UIMenu(children: [moveAction, switchSourceAction, downloadAction, deleteAction])
        }
    }
}
