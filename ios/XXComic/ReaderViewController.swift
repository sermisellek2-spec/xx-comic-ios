import UIKit
import ComicCore

@MainActor
final class ReaderViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate, UIAdaptivePresentationControllerDelegate {
    private let environment: AppEnvironment
    private var comic: ComicSummary
    private var source: any ComicSource
    private let localPageImage: (@Sendable (URL) throws -> Data)?
    private var chapters: [Chapter]
    private var incompleteDirectory: Bool
    private var session: ReaderSession
    private var settings: ReaderPreferences
    private var images: [String] = []
    private var sizes: [String: CGSize] = [:]
    private var loadTask: Task<Void, Never>?
    private var directoryTask: Task<Void, Never>?
    private var requestID = UUID()
    private var loadState = ReaderLoadState()
    private var loading: Bool { loadState.chapterLoading }
    private var chapterRetryAction: (() -> Void)?
    private var restoring = false
    private var fullscreen = false
    private var pendingPosition: ReaderPosition?
    private var lastSaved: ReaderPosition?
    private let layout = UICollectionViewFlowLayout()
    private lazy var pages = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let toolbar = UIStackView()
    private let previous = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let readerSeekBar = ReaderSeekBar()
    private let middleButton = UIButton(type: .system)
    private let status = UIButton(type: .system)
    private let badge = UILabel()
    private let enhancementBadge = UILabel()
    private var retryAction: (() -> Void)?
    private var oldNavigationStyle: UIUserInterfaceStyle = .unspecified
    private var isZoomed = false
    private var pageAnimating = false
    private var habitTimer: Timer?
    private var leavingReader = false

    init(comic: ComicSummary, chapters: [Chapter], chapterIndex: Int, directoryIncomplete: Bool, environment: AppEnvironment) {
        self.comic = comic; self.chapters = chapters; self.environment = environment
        source = environment.source(for: comic)!
        if comic.sourceId == "local" {
            let library = environment.localLibrary
            localPageImage = { url in
                switch url.scheme {
                case "xxcomic-epub": return try library.epubImageData(pageURL: url)
                case "xxcomic-pdf": return try library.pdfPageData(pageURL: url) { try PdfRenderer.render($0, pageIndex: $1) }
                default: throw LocalLibraryError.invalidBook
                }
            }
        } else { localPageImage = nil }
        incompleteDirectory = directoryIncomplete
        session = ReaderSession(chapterCount: chapters.count, chapterIndex: chapterIndex)
        settings = environment.preferences.load()
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { loadTask?.cancel(); directoryTask?.cancel() }
    override var prefersStatusBarHidden: Bool { fullscreen }
    override func viewDidLoad() {
        super.viewDidLoad()
        oldNavigationStyle = navigationController?.overrideUserInterfaceStyle ?? .unspecified
        layout.minimumLineSpacing = 0; layout.minimumInteritemSpacing = 0
        pages.dataSource = self; pages.delegate = self
        pages.register(ReaderImageCell.self, forCellWithReuseIdentifier: "image")
        pages.contentInsetAdjustmentBehavior = .never
        pages.showsHorizontalScrollIndicator = false

        // Two-row bottom toolbar aligned with Android 2.0.40
        toolbar.axis = .vertical
        toolbar.spacing = 6
        toolbar.backgroundColor = UIColor(red: 28/255, green: 33/255, blue: 40/255, alpha: 0.94) // Dark translucent
        toolbar.layer.cornerRadius = 12
        toolbar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        toolbar.isLayoutMarginsRelativeArrangement = true
        toolbar.layoutMargins = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)

        // Row 1: prevChapter | seekbar | nextChapter
        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.alignment = .center
        row1.spacing = 8
        previous.setTitle("上一章", for: .normal)
        previous.titleLabel?.font = .systemFont(ofSize: 13)
        previous.tintColor = Palette.accent
        previous.addTarget(self, action: #selector(backward), for: .touchUpInside)

        nextButton.setTitle("下一章", for: .normal)
        nextButton.titleLabel?.font = .systemFont(ofSize: 13)
        nextButton.tintColor = Palette.accent
        nextButton.addTarget(self, action: #selector(forward), for: .touchUpInside)

        readerSeekBar.onCommit = { [weak self] pageIndex in
            guard let self, self.images.indices.contains(pageIndex) else { return }
            self.environment.readingHabits.userDidRead()
            if self.settings.layout == .paged {
                let x = CGFloat(pageIndex) * self.pages.bounds.width
                self.pages.setContentOffset(CGPoint(x: x, y: 0), animated: false)
            } else {
                self.pages.scrollToItem(at: IndexPath(item: pageIndex, section: 0), at: .top, animated: false)
            }
            self.session.updateImage(pageIndex)
            self.updateBadge()
            self.savePosition()
        }

        row1.addArrangedSubview(previous)
        row1.addArrangedSubview(readerSeekBar)
        row1.addArrangedSubview(nextButton)
        previous.widthAnchor.constraint(equalToConstant: 52).isActive = true
        nextButton.widthAnchor.constraint(equalToConstant: 52).isActive = true

        // Row 2: 目录 | 换源/详情 | 设置
        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.distribution = .fillEqually
        let directory = UIButton(type: .system), preferences = UIButton(type: .system)
        directory.setTitle("目录", for: .normal)
        directory.titleLabel?.font = .systemFont(ofSize: 14)
        directory.tintColor = .white
        directory.addTarget(self, action: #selector(showDirectory), for: .touchUpInside)

        middleButton.setTitle(comic.sourceId == "local" ? "详情" : "换源", for: .normal)
        middleButton.titleLabel?.font = .systemFont(ofSize: 14)
        middleButton.tintColor = .white
        middleButton.addTarget(self, action: #selector(middleButtonAction), for: .touchUpInside)

        preferences.setTitle("设置", for: .normal)
        preferences.titleLabel?.font = .systemFont(ofSize: 14)
        preferences.tintColor = .white
        preferences.addTarget(self, action: #selector(showSettings), for: .touchUpInside)

        for btn in [directory, middleButton, preferences] { row2.addArrangedSubview(btn) }
        toolbar.addArrangedSubview(row1)
        toolbar.addArrangedSubview(row2)

        status.titleLabel?.numberOfLines = 0
        status.addTarget(self, action: #selector(retry), for: .touchUpInside)
        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        badge.textAlignment = .right; badge.numberOfLines = 2

        enhancementBadge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        enhancementBadge.textColor = .white
        enhancementBadge.backgroundColor = UIColor(red: 12/255, green: 20/255, blue: 32/255, alpha: 0.8)
        enhancementBadge.layer.cornerRadius = 4
        enhancementBadge.layer.masksToBounds = true
        enhancementBadge.textAlignment = .center
        enhancementBadge.isHidden = true

        for item in [pages, toolbar, status, badge, enhancementBadge] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        NSLayoutConstraint.activate([
            pages.topAnchor.constraint(equalTo: view.topAnchor), pages.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pages.leadingAnchor.constraint(equalTo: view.leadingAnchor), pages.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor), toolbar.heightAnchor.constraint(equalToConstant: 88),
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor), status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            badge.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            badge.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            enhancementBadge.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            enhancementBadge.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            enhancementBadge.heightAnchor.constraint(equalToConstant: 20)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self; pages.addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        pages.addGestureRecognizer(doubleTap); tap.require(toFail: doubleTap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1; pan.delegate = self; pages.addGestureRecognizer(pan)
        // Keep page changes discrete. UIScrollView owns strip scrolling and zoom only.
        pages.panGestureRecognizer.require(toFail: pan)
        NotificationCenter.default.addObserver(self, selector: #selector(saveBeforeBackground), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshReaderTheme), name: UIApplication.didBecomeActiveNotification, object: nil)
        environment.readingHabits.enterReader(comicID: comic.comicId, isLocal: comic.sourceId == "local")
        syncHabitOverlay()
        applySettings()
        loadChapter(session.chapterIndex)
        if incompleteDirectory { loadDirectory() }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applySettings()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        habitTimer?.invalidate()
        habitTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.environment.readingHabits.tick()
        }
        syncHabitOverlay()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        habitTimer?.invalidate(); habitTimer = nil
        leavingReader = isMovingFromParent
        savePosition()
        if isMovingFromParent {
            loadTask?.cancel(); directoryTask?.cancel()
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.overrideUserInterfaceStyle = oldNavigationStyle
        }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if leavingReader {
            environment.readingHabits.exitReader()
            leavingReader = false
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let position = pendingPosition, !images.isEmpty, pages.bounds.width > 0 {
            pendingPosition = nil; restore(position)
        }
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let position = currentPosition()
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.layout.invalidateLayout() }, completion: { _ in self.restore(position) })
    }
    private func applySettings() {
        let position = currentPosition()
        let previousSettings = settings
        settings = environment.preferences.load()
        if pageAnimating {
            pages.setContentOffset(pages.contentOffset, animated: false)
            pageAnimating = false
            restore(position)
        }
        layout.scrollDirection = settings.layout == .strip ? .vertical : .horizontal
        pages.isPagingEnabled = settings.layout == .paged
        pages.isScrollEnabled = settings.layout == .strip && !isZoomed
        previous.setTitle(settings.layout == .strip ? "上一章" : "上一页", for: .normal)
        nextButton.setTitle(settings.layout == .strip ? "下一章" : "下一页", for: .normal)
        let style: UIUserInterfaceStyle = settings.theme == .system ? UIScreen.main.traitCollection.userInterfaceStyle : (settings.theme == .dark ? .dark : .light)
        overrideUserInterfaceStyle = style
        navigationController?.overrideUserInterfaceStyle = style
        pages.backgroundColor = .systemBackground; view.backgroundColor = .systemBackground
        toolbar.backgroundColor = .secondarySystemBackground
        badge.textColor = .secondaryLabel
        badge.isHidden = !fullscreen || settings.fullyImmersive
        presentedViewController?.overrideUserInterfaceStyle = style
        for cell in pages.visibleCells { (cell as? ReaderImageCell)?.apply(settings) }
        if previousSettings.layout != settings.layout {
            layout.invalidateLayout(); pages.reloadData()
            pendingPosition = position
            view.setNeedsLayout()
        }
    }
    private func loadDirectory() {
        directoryTask?.cancel()
        if !loading && loadState.visibleFailure == nil {
            status.isHidden = false
            status.setTitle("正在加载目录…", for: .normal)
            retryAction = nil
        }
        let id = comic.comicId
        directoryTask = Task { [weak self, source] in
            do {
                let all = try await source.chapters(comicId: id); try Task.checkCancellation()
                guard let self, self.chapters.indices.contains(self.session.chapterIndex) else { return }
                let current = self.chapters[self.session.chapterIndex]
                guard let index = all.firstIndex(where: { $0.chapterId == current.chapterId || $0.url == current.url }) else { throw ReaderError.chapterMissing }
                let position = self.currentPosition()
                self.chapters = all
                self.session = ReaderSession(chapterCount: all.count, chapterIndex: index)
                self.session.loaded(imageCount: self.images.count, position: position)
                self.incompleteDirectory = false
                self.loadState.directoryFinished()
                self.updateLoadStatus()
            } catch {
                guard let self, !Task.isCancelled else { return }
                if !(error is CancellationError) {
                    ErrorLogStore.shared.append(title: "目录加载失败: \(self.comic.title)", error: error)
                }
                self.loadState.directoryFinished(error: error)
                self.updateLoadStatus()
            }
        }
    }
    private func loadChapter(_ index: Int, atEnd: Bool = false, restoreSaved: Bool = true) {
        guard chapters.indices.contains(index) else { return }
        savePosition()
        loadTask?.cancel(); requestID = UUID()
        let token = requestID, chapter = chapters[index]
        loadState.chapterStarted()
        chapterRetryAction = { [weak self] in
            guard let self, let currentIndex = self.chapters.firstIndex(where: { $0.chapterId == chapter.chapterId || $0.url == chapter.url }) else { return }
            self.loadChapter(currentIndex, atEnd: atEnd, restoreSaved: restoreSaved)
        }
        updateLoadStatus()
        loadTask = Task { [weak self, source] in
            do {
                let page: ChapterPage
                if let self, self.comic.sourceId != "local" {
                    let runtime = self.environment.downloadRuntime
                    if let taskId = try? DownloadModels.key(self.comic.sourceId, self.comic.comicId, chapter.chapterId),
                       let task = runtime.store.get(id: taskId), task.state == .completed {
                        do {
                            guard let local = try runtime.localChapter(
                                detail: ComicDetail(summary: self.comic, author: "", status: "", description: "", latestChapter: "", chapters: self.chapters),
                                chapterIndex: index
                            ) else {
                                throw DownloadError.corruptedData("本章下载文件需要修复")
                            }
                            page = local
                        } catch {
                            ErrorLogStore.shared.append(title: "下载文件损坏: \(self.comic.title) - \(chapter.title)", error: error)
                            throw DownloadError.corruptedData("本章下载文件需要修复")
                        }
                    } else if !runtime.isNetworkConnected {
                        throw DownloadError.corruptedData("这一章还没有下载哦")
                    } else {
                        page = try await source.chapter(url: chapter.url)
                    }
                } else {
                    page = try await source.chapter(url: chapter.url)
                }
                try Task.checkCancellation()
                guard let self, self.requestID == token else { return }
                guard !page.imageUrls.isEmpty else { throw ReaderError.noImages }
                let saved = restoreSaved ? self.environment.library.position(for: self.comic, chapterID: chapter.chapterId) : nil
                let position = atEnd ? ReaderPosition(imageIndex: page.imageUrls.count - 1, offset: 0, atEnd: true)
                    : (saved ?? ReaderPosition(imageIndex: 0, offset: 0))
                guard self.session.loaded(chapter: chapter, in: self.chapters, imageCount: page.imageUrls.count, position: position) else { throw ReaderError.chapterMissing }
                self.images = page.imageUrls; self.sizes = [:]
                self.title = chapter.title
                self.loadState.chapterFinished(); self.updateLoadStatus(); self.lastSaved = nil
                self.pages.reloadData(); self.layout.invalidateLayout()
                self.pendingPosition = position; self.view.setNeedsLayout()
                self.updateBadge()
                self.readerSeekBar.configure(currentPage: position.imageIndex, total: self.images.count, sessionToken: Int64(self.session.chapterIndex))
            } catch {
                guard let self, self.requestID == token, !Task.isCancelled else { return }
                if (error as? LocalLibraryError) == .requiresTextReader {
                    self.switchToTextReader(chapterIndex: index, atEnd: atEnd, restoreSaved: restoreSaved)
                    return
                }
                if !(error is CancellationError) {
                    ErrorLogStore.shared.append(title: "章节加载失败: \(self.comic.title) - \(chapter.title)", error: error)
                }
                self.loadState.chapterFinished(error: error)
                self.updateLoadStatus()
            }
        }
    }
    private func switchToTextReader(chapterIndex: Int, atEnd: Bool, restoreSaved: Bool) {
        guard chapters.indices.contains(chapterIndex) else { return }
        savePosition()
        let chapter = chapters[chapterIndex]
        let library = environment.localLibrary
        Task { [weak self] in
            guard let self else { return }
            do {
                let target = try await library.readingTarget(seriesId: self.comic.comicId, chapterId: chapter.chapterId)
                let book = try library.book(id: target.volumeId)
                let saved = restoreSaved ? self.environment.library.textPosition(for: self.comic, chapterID: chapter.chapterId) : nil
                let volLocator: TextLocator?
                if let saved {
                    volLocator = saved.toVolumeLocator(volumeId: target.volumeId, volumeChapterIndex: target.volumeChapterIndex)
                } else if atEnd {
                    let spineCount = book.chapters?[target.volumeChapterIndex].pages.count ?? 1
                    volLocator = TextLocator(bookID: target.volumeId, chapterIndex: target.volumeChapterIndex,
                                             spineIndex: max(0, spineCount - 1), resourceHref: "", anchorID: "", scrollPercentage: 1.0)
                } else {
                    volLocator = TextLocator(bookID: target.volumeId, chapterIndex: target.volumeChapterIndex,
                                             spineIndex: 0, resourceHref: "", anchorID: "", scrollPercentage: 0.0)
                }
                let session = try EpubTextSession(book: book, chapterIndex: target.volumeChapterIndex, locator: volLocator)
                let textVC = EpubTextReaderViewController(comic: self.comic, chapters: self.chapters, session: session,
                                                          locator: volLocator, environment: self.environment)
                if let nav = self.navigationController {
                    var vcs = nav.viewControllers
                    if let idx = vcs.lastIndex(where: { $0 === self }) {
                        vcs[idx] = textVC
                        nav.setViewControllers(vcs, animated: false)
                    }
                }
            } catch {
                self.loadState.chapterFinished(error: error)
                self.updateLoadStatus()
            }
        }
    }
    private func updateLoadStatus() {
        retryAction = nil
        if loading {
            status.isHidden = false
            status.setTitle("正在加载章节…", for: .normal)
            return
        }
        guard let failure = loadState.visibleFailure else { status.isHidden = true; return }
        status.isHidden = false
        if let dlErr = failure.error as? DownloadError, case .corruptedData(let msg) = dlErr {
            if msg == "本章下载文件需要修复" {
                status.setTitle("本章下载文件需要修复 · 到下载中心重新下载本章", for: .normal)
                retryAction = { [weak self] in
                    self?.showDownloadCenter()
                }
                return
            } else if msg == "这一章还没有下载哦" {
                status.setTitle("这一章还没有下载哦 · 已下载的章节可以在下载中心找到", for: .normal)
                retryAction = { [weak self] in
                    self?.showDownloadCenter()
                }
                return
            }
        }
        let retry: () -> Void = failure.kind == .chapter
            ? { [weak self] in self?.chapterRetryAction?() }
            : { [weak self] in self?.loadDirectory() }
        if (failure.error as? Mh18SourceError) == .verificationRequired {
            status.setTitle("需要验证 · 去验证", for: .normal)
            retryAction = { [weak self] in
                guard let self else { return }
                self.showSourceManagement(environment: self.environment, onVerified: retry)
            }
        } else {
            let text = failure.error is CancellationError ? "已取消" : (failure.kind == .directory ? "目录加载失败：" : "") + failure.error.localizedDescription
            status.setTitle(text + " · 点击重试", for: .normal)
            retryAction = retry
        }
    }
    private func showDownloadCenter() {
        let centerVC = DownloadCenterViewController(environment: environment)
        let nav = UINavigationController(rootViewController: centerVC)
        centerVC.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeSheet))
        present(nav, animated: true)
    }
    private func currentPosition() -> ReaderPosition {
        guard !images.isEmpty, pages.bounds.width > 0 else { return ReaderPosition(imageIndex: 0, offset: 0) }
        if let pendingPosition { return pendingPosition }
        if settings.layout == .paged {
            let index = Int((pages.contentOffset.x / max(1, pages.bounds.width)).rounded())
            return ReaderPosition(imageIndex: max(0, min(images.count - 1, index)), offset: 0, atEnd: index == images.count - 1)
        }
        let visible = pages.indexPathsForVisibleItems.sorted { $0.item < $1.item }
        let index = visible.first(where: { (layout.layoutAttributesForItem(at: $0)?.frame.maxY ?? 0) > pages.contentOffset.y + 1 }) ?? visible.first
        guard let index, let frame = layout.layoutAttributesForItem(at: index)?.frame else { return ReaderPosition(imageIndex: session.imageIndex, offset: 0) }
        let offset = (pages.contentOffset.y - frame.minY) / max(1, frame.height)
        let end = pages.contentSize.height > pages.bounds.height && pages.contentOffset.y + pages.bounds.height >= pages.contentSize.height - 2
        return ReaderPosition(imageIndex: index.item, offset: Double(offset), atEnd: end)
    }
    private func restore(_ position: ReaderPosition) {
        guard !images.isEmpty else { return }
        restoring = true
        pages.layoutIfNeeded()
        let index = position.index(for: images.count)
        if settings.layout == .paged {
            pages.setContentOffset(CGPoint(x: CGFloat(index) * pages.bounds.width, y: 0), animated: false)
        } else if let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame {
            let maxY = max(0, pages.contentSize.height - pages.bounds.height)
            let target = position.atEnd ? maxY : frame.minY + frame.height * CGFloat(position.offset)
            pages.setContentOffset(CGPoint(x: 0, y: max(0, min(maxY, target))), animated: false)
        }
        session.updateImage(index); restoring = false; updateBadge()
    }
    private func savePosition() {
        guard !loading, !restoring, !images.isEmpty, chapters.indices.contains(session.chapterIndex) else { return }
        let position = currentPosition()
        guard position != lastSaved else { return }
        do {
            try environment.library.saveReading(comic, chapter: chapters[session.chapterIndex], chapterIndex: session.chapterIndex, position: position)
            lastSaved = position
        } catch { status.isHidden = false; status.setTitle("阅读位置保存失败：" + error.localizedDescription, for: .normal) }
    }
    @objc private func saveBeforeBackground() { savePosition() }
    @objc private func refreshReaderTheme() { if viewIfLoaded?.window != nil { applySettings() } }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        if settings.theme == .system && overrideUserInterfaceStyle != UIScreen.main.traitCollection.userInterfaceStyle { applySettings() }
    }
    private func updateBadge() {
        guard !images.isEmpty else { badge.text = nil; enhancementBadge.isHidden = true; return }
        badge.text = "\(session.imageIndex + 1)/\(images.count) · \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
        if settings.enhancementMode != ImageEnhancementPolicy.modeOff {
            enhancementBadge.isHidden = false
            enhancementBadge.text = settings.enhancementMode == ImageEnhancementPolicy.modeSmart ? " AI 2X " : " 增强 "
        } else {
            enhancementBadge.isHidden = true
        }
    }
    @objc private func retry() { retryAction?() }
    @objc private func backward() { move(-1) }
    @objc private func forward() { move(1) }
    private func move(_ delta: Int) {
        guard !loading, !isZoomed, !pageAnimating else { return }
        environment.readingHabits.userDidRead()
        session.updateImage(currentPosition().imageIndex)
        if settings.layout == .strip { changeChapter(delta); return }
        switch session.move(delta: delta) {
        case .image(let index):
            pageAnimating = !settings.disablePageAnimation && !settings.inkScreen
            pages.setContentOffset(CGPoint(x: CGFloat(index) * pages.bounds.width, y: 0), animated: pageAnimating)
            updateBadge()
            if settings.disablePageAnimation || settings.inkScreen { savePosition() }
        case .chapter(_, let atEnd): changeChapter(delta, atEnd: atEnd)
        case .boundary: boundary()
        case .unavailable: break
        }
    }
    private func changeChapter(_ delta: Int, atEnd: Bool = false) {
        if incompleteDirectory { loadDirectory(); return }
        let index = session.chapterIndex + delta
        guard chapters.indices.contains(index) else { boundary(); return }
        loadChapter(index, atEnd: atEnd, restoreSaved: false)
    }
    private func boundary() {
        guard presentedViewController == nil else { return }
        environment.readingHabits.overlayVisibilityChanged(isVisible: true)
        let alert = UIAlertController(title: "没有更多章节了", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let self else { return }
            self.environment.readingHabits.overlayVisibilityChanged(isVisible: !self.fullscreen)
        })
        present(alert, animated: true)
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: pages)
        let action = ReaderNavigation.tapAction(
            x: Double((location.x - pages.bounds.minX) / max(1, pages.bounds.width)),
            y: Double((location.y - pages.bounds.minY) / max(1, pages.bounds.height)),
            controlsVisible: !fullscreen, layout: settings.layout, mode: settings.turnMode,
            leftHand: settings.leftHand, zoomed: isZoomed)
        switch action {
        case .none: break
        case .move(let delta): move(delta)
        case .toggleControls:
            environment.readingHabits.userDidRead()
            fullscreen.toggle()
            toolbar.isHidden = fullscreen
            badge.isHidden = !fullscreen || settings.fullyImmersive
            navigationController?.setNavigationBarHidden(fullscreen, animated: true)
            setNeedsStatusBarAppearanceUpdate()
            syncHabitOverlay()
        }
    }
    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard settings.pinchZoom, !loading, !pageAnimating,
              let index = pages.indexPathForItem(at: gesture.location(in: pages)),
              let cell = pages.cellForItem(at: index) as? ReaderImageCell else { return }
        environment.readingHabits.userDidRead()
        cell.toggleZoom()
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended, !isZoomed, settings.layout == .paged, settings.turnMode == .swipe else { return }
        let translation = gesture.translation(in: pages)
        guard abs(translation.x) > 72, abs(translation.x) > abs(translation.y) * 1.35 else { return }
        move(ReaderNavigation.swipeDelta(dx: Double(translation.x), leftHand: settings.leftHand))
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.view === pages {
            let velocity = pan.velocity(in: pages)
            return settings.layout == .paged && settings.turnMode == .swipe && !isZoomed && abs(velocity.x) > abs(velocity.y) * 1.35
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touched = touch.view
        while let current = touched {
            if current is UIControl { return false }
            if current === pages { break }
            touched = current.superview
        }
        return true
    }
    @objc private func showSettings() {
        savePosition()
        environment.readingHabits.userDidRead()
        environment.readingHabits.overlayVisibilityChanged(isVisible: true)
        let controller = ReaderSettingsViewController(store: environment.preferences)
        controller.onChange = { [weak self] in self?.applySettings() }
        let navigation = UINavigationController(rootViewController: controller)
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeSheet))
        navigation.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        present(navigation, animated: true)
        navigation.presentationController?.delegate = self
    }
    @objc private func closeSheet() { dismiss(animated: true) { [weak self] in self?.syncHabitOverlay() } }
    @objc private func showDirectory() {
        guard chapters.indices.contains(session.chapterIndex) else { return }
        environment.readingHabits.userDidRead()
        environment.readingHabits.overlayVisibilityChanged(isVisible: true)
        let isDark = settings.theme == .dark || (settings.theme == .system && traitCollection.userInterfaceStyle == .dark)
        let drawer = ChapterDrawerSheet(
            chapters: chapters,
            currentChapterIndex: session.chapterIndex,
            hasCurrent: true,
            isReader: true,
            isDarkReader: isDark,
            isDesc: false
        ) { [weak self] selectedIndex in
            guard let self, self.chapters.indices.contains(selectedIndex) else { return }
            self.savePosition()
            self.loadChapter(selectedIndex)
        }
        present(drawer, animated: false)
    }

    @objc private func middleButtonAction() {
        if comic.sourceId == "local" {
            navigationController?.popViewController(animated: true)
        } else {
            showReaderSourceSheet()
        }
    }

    private func showReaderSourceSheet() {
        let sheet = SourceSwitchSheet(comic: comic, environment: environment) { [weak self] target in
            guard let self else { return }
            self.switchReaderSource(target: target)
        }
        present(sheet, animated: true)
    }

    private func switchReaderSource(target: ComicSummary) {
        guard target.comicId != comic.comicId else { return }
        guard let targetSource = environment.source(for: target) else { return }
        let currentTitle = chapters.indices.contains(session.chapterIndex) ? chapters[session.chapterIndex].title : ""
        let currentIndex = session.chapterIndex

        let alert = UIAlertController(title: nil, message: "正在切换至 \(targetSource.name)…", preferredStyle: .alert)
        present(alert, animated: true)

        Task { [weak self] in
            do {
                let targetDetail = try await targetSource.detail(comicId: target.comicId)
                var targetChapters = targetDetail.chapters
                if targetChapters.isEmpty {
                    targetChapters = try await targetSource.chapters(comicId: target.comicId)
                }
                guard let self, !targetChapters.isEmpty else {
                    await alert.dismiss(animated: true)
                    return
                }
                await alert.dismiss(animated: true)

                let matchedIndex = ChapterMatching.findMatchingChapterIndex(
                    chapters: targetChapters,
                    currentTitle: currentTitle,
                    defaultIndex: currentIndex
                )

                if self.environment.library.entry(for: self.comic)?.isFavorite == true {
                    try? self.environment.replaceSource(from: self.comic, to: targetDetail)
                }

                self.comic = targetDetail.summary
                self.source = targetSource
                self.chapters = targetChapters
                self.incompleteDirectory = false
                self.session = ReaderSession(chapterCount: targetChapters.count, chapterIndex: matchedIndex)
                self.images = []
                self.pages.reloadData()
                self.loadChapter(matchedIndex)
                self.middleButton.setTitle(self.comic.sourceId == "local" ? "详情" : "换源", for: .normal)
            } catch {
                await alert.dismiss(animated: true)
                guard let self else { return }
                let errAlert = UIAlertController(title: "换源失败", message: error.localizedDescription, preferredStyle: .alert)
                errAlert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(errAlert, animated: true)
            }
        }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { syncHabitOverlay() }
    private func syncHabitOverlay() {
        environment.readingHabits.overlayVisibilityChanged(isVisible: !fullscreen || presentedViewController != nil)
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { images.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "image", for: indexPath) as! ReaderImageCell
        let url = images[indexPath.item]
        cell.onZoom = { [weak self] zoomed in
            guard let self else { return }; self.isZoomed = zoomed
            self.pages.isScrollEnabled = self.settings.layout == .strip && !zoomed
        }
        cell.onUserAction = { [weak self] in self?.environment.readingHabits.userDidRead() }
        cell.onSize = { [weak self] size in
            guard let self, self.images.contains(url) else { return }
            self.environment.readingHabits.contentBecameReadable()
            guard self.sizes[url] != size else { return }
            let position = self.currentPosition()
            self.sizes[url] = size
            if self.settings.layout == .strip { self.layout.invalidateLayout(); self.restore(position) }
            self.savePosition()
        }
        cell.onComparing = { [weak self] isComparing in
            guard let self else { return }
            if isComparing {
                self.enhancementBadge.isHidden = false
                self.enhancementBadge.text = " 原图 "
            } else {
                self.updateBadge()
            }
        }
        cell.configure(url: url, referer: source.referer, settings: settings, localPageImage: localPageImage)
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ReaderImageCell)?.cancel()
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = max(1, collectionView.bounds.width)
        if settings.layout == .paged { return CGSize(width: width, height: max(1, collectionView.bounds.height)) }
        let size = sizes[images[indexPath.item]] ?? CGSize(width: 3, height: 4)
        return CGSize(width: width, height: max(1, width * size.height / max(1, size.width)))
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !restoring else { return }
        session.updateImage(currentPosition().imageIndex); updateBadge()
        readerSeekBar.configure(currentPage: session.imageIndex, total: images.count, sessionToken: Int64(session.chapterIndex))
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { environment.readingHabits.userDidRead() }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { savePosition() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { pageAnimating = false; savePosition() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { savePosition() } }
}

private enum ReaderError: LocalizedError {
    case noImages, chapterMissing
    var errorDescription: String? {
        switch self {
        case .noImages: return "章节没有返回可阅读的图片"
        case .chapterMissing: return "当前章节已不在目录中，请重新选择章节"
        }
    }
}

@MainActor
private final class ReaderImageCell: UICollectionViewCell, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let image = RemoteImageView()
    private let retry = UIButton(type: .system)
    private var url = "", referer = ""
    private var localPageImage: (@Sendable (URL) throws -> Data)?
    private var rawImage: UIImage?
    private var enhancedImage: UIImage?
    private var isComparing = false
    private var currentMode = 0
    private var comparisonEnabled = false
    var onComparing: ((Bool) -> Void)?
    var onSize: ((CGSize) -> Void)?
    var onZoom: ((Bool) -> Void)?
    var onUserAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.delegate = self; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4
        scroll.showsHorizontalScrollIndicator = false; scroll.showsVerticalScrollIndicator = false
        scroll.bouncesZoom = true
        image.contentMode = .scaleAspectFit
        contentView.addSubview(scroll); scroll.addSubview(image); contentView.addSubview(retry)
        retry.setTitle("正在加载图片…", for: .normal)
        retry.addTarget(self, action: #selector(reload), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        contentView.addGestureRecognizer(longPress)

        image.onLoaded = { [weak self] size in
            guard let self else { return }
            self.retry.isHidden = true
            self.rawImage = self.image.image
            if self.currentMode != ImageEnhancementPolicy.modeOff, let raw = self.rawImage {
                Task { [weak self] in
                    guard let self, let raw = self.rawImage else { return }
                    let enhanced = await ReaderEnhancementEngine.shared.enhance(url: self.url, original: raw, mode: self.currentMode)
                    guard !Task.isCancelled, self.rawImage === raw else { return }
                    self.enhancedImage = enhanced
                    if !self.isComparing {
                        self.image.image = enhanced
                    }
                }
            }
            let callback = self.onSize
            DispatchQueue.main.async { callback?(size) }
        }
        image.onFailure = { [weak self] in self?.retry.isHidden = false; self?.retry.setTitle("图片加载失败 · 点击重试", for: .normal) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard comparisonEnabled, enhancedImage != nil, rawImage != nil else { return }
        if gesture.state == .began {
            isComparing = true
            image.image = rawImage
            onComparing?(true)
        } else if gesture.state == .ended || gesture.state == .cancelled {
            isComparing = false
            image.image = enhancedImage ?? rawImage
            onComparing?(false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = contentView.bounds
        if scroll.zoomScale == 1 { image.frame = scroll.bounds; scroll.contentSize = scroll.bounds.size }
        retry.frame = CGRect(x: 0, y: max(0, bounds.midY - 22), width: bounds.width, height: 44)
    }
    func configure(url: String, referer: String, settings: ReaderPreferences, localPageImage: (@Sendable (URL) throws -> Data)? = nil) {
        self.url = url; self.referer = referer
        self.localPageImage = localPageImage
        self.currentMode = settings.enhancementMode
        self.comparisonEnabled = settings.enhancementComparison
        scroll.setZoomScale(1, animated: false)
        apply(settings)
        reload()
    }
    func apply(_ settings: ReaderPreferences) {
        self.currentMode = settings.enhancementMode
        self.comparisonEnabled = settings.enhancementComparison
        setZoomEnabled(settings.pinchZoom)
        image.setReaderEffects(crop: settings.cropWhiteMargins, vertical: settings.layout == .paged, ink: settings.inkScreen)
    }
    func setZoomEnabled(_ enabled: Bool) {
        if !enabled { scroll.setZoomScale(1, animated: false) }
        scroll.maximumZoomScale = enabled ? 4 : 1
    }
    func toggleZoom() { scroll.setZoomScale(scroll.zoomScale > 1.05 ? 1 : min(2, scroll.maximumZoomScale), animated: true) }
    @objc private func reload() { retry.isHidden = false; retry.setTitle("正在加载图片…", for: .normal); image.load(url, referer: referer, reader: true, localPageImage: localPageImage) }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { onZoom?(scrollView.zoomScale > 1.05) }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { onUserAction?() }
    func cancel() { image.cancel() }
    override func prepareForReuse() {
        super.prepareForReuse()
        image.cancel()
        localPageImage = nil
        onSize = nil
        onZoom = nil
        onUserAction = nil
        onComparing = nil
        rawImage = nil
        enhancedImage = nil
        isComparing = false
        scroll.setZoomScale(1, animated: false)
    }
}
