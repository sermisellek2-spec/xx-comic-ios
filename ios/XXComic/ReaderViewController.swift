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
    private var continuousPages = ContinuousReaderPages()
    private var continuationTask: Task<Void, Never>?
    private var continuationRequestID = UUID()
    private var continuationError: Error?
    private var lastObservedPosition: (chapter: Chapter, position: ReaderPosition)?
    private var sizes: [String: CGSize] = [:]
    private var loadTask: Task<Void, Never>?
    private var directoryTask: Task<Void, Never>?
    private var requestID = UUID()
    private var loadState = ReaderLoadState()
    private var loading: Bool { loadState.chapterLoading }
    private var chapterRetryAction: (() -> Void)?
    private var restoring = false
    private var viewportTransitioning = false
    private var fullscreen = false
    private var pendingPosition: ReaderPosition?
    private var lastSaved: ReaderPosition?
    private let layout = ReaderPageLayout()
    private lazy var pages = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let toolbar = UIStackView()
    private let topChrome = ReaderChromeGradientView(edge: .top)
    private let bottomChrome = ReaderChromeGradientView(edge: .bottom)
    private let chapterProgress = UIProgressView(progressViewStyle: .bar)
    private let readerHeading = UILabel()
    private let badgeTimeFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; return formatter
    }()
    private var headerWidth: NSLayoutConstraint?
    private let previous = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let readerSeekBar = ReaderSeekBar()
    private let middleButton = UIButton(type: .system)
    private let status = UIButton(type: .system)
    private let badge = ReaderOverlayBadge()
    private let enhancementBadge = UILabel()
    private var retryAction: (() -> Void)?
    private weak var downloadRepairController: UIViewController?
    private var downloadRepairAction: (() -> Void)?
    private var oldNavigationStyle: UIUserInterfaceStyle = .unspecified
    private var oldBatteryMonitoring = false
    private var isZoomed = false
    private var pageAnimating = false
    private var pagePanBeganAt: TimeInterval?
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
                case "file", "xxcomic-folder": return try library.ownedImageData(at: url)
                default: throw LocalLibraryError.invalidBook
                }
            }
        } else {
            let runtime = environment.downloadRuntime
            localPageImage = { try runtime.offlineImageData(at: $0) }
        }
        incompleteDirectory = directoryIncomplete
        session = ReaderSession(chapterCount: chapters.count, chapterIndex: chapterIndex)
        settings = environment.preferences.load()
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { loadTask?.cancel(); directoryTask?.cancel(); continuationTask?.cancel() }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { overrideUserInterfaceStyle == .dark ? .lightContent : .darkContent }
    override var prefersHomeIndicatorAutoHidden: Bool { fullscreen }
    override func viewDidLoad() {
        super.viewDidLoad()
        oldNavigationStyle = navigationController?.overrideUserInterfaceStyle ?? .unspecified
        oldBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        // Keep the image canvas fixed while UIKit's navigation/status bars
        // appear or disappear. The controls are overlays, never content insets.
        edgesForExtendedLayout = .all; extendedLayoutIncludesOpaqueBars = true
        let appearance = UINavigationBarAppearance(); appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance; navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        let back = UIButton(type: .system)
        back.setImage(ParityIcon.back.image(size: 20), for: .normal)
        back.tintColor = .label; back.accessibilityIdentifier = "reader.back"; back.accessibilityLabel = "返回"
        back.addTarget(self, action: #selector(returnToDetail), for: .touchUpInside)
        back.widthAnchor.constraint(equalToConstant: 44).isActive = true
        back.heightAnchor.constraint(equalToConstant: 44).isActive = true
        readerHeading.font = .systemFont(ofSize: 13, weight: .medium); readerHeading.textColor = .label
        readerHeading.lineBreakMode = .byTruncatingTail; readerHeading.accessibilityIdentifier = "reader.title"
        let header = UIStackView(arrangedSubviews: [back, readerHeading]); header.alignment = .center
        header.spacing = 0; header.translatesAutoresizingMaskIntoConstraints = false
        headerWidth = header.widthAnchor.constraint(equalToConstant: 260); headerWidth?.isActive = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: header)
        navigationItem.titleView = UIView(frame: .zero)
        layout.minimumLineSpacing = 0; layout.minimumInteritemSpacing = 0
        pages.dataSource = self; pages.delegate = self
        pages.register(ReaderImageCell.self, forCellWithReuseIdentifier: "image")
        pages.register(ReaderContinuationFooter.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "continuation")
        pages.accessibilityIdentifier = "reader.pages"
        pages.contentInsetAdjustmentBehavior = .never
        pages.showsHorizontalScrollIndicator = false

        // Two-row bottom toolbar aligned with Android 2.0.40
        toolbar.axis = .vertical
        toolbar.spacing = 0
        toolbar.accessibilityIdentifier = "reader.toolbar"

        // Row 1: prevChapter | seekbar | nextChapter
        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.alignment = .center
        row1.spacing = 10
        row1.isLayoutMarginsRelativeArrangement = true
        row1.layoutMargins = UIEdgeInsets(top: 2, left: 12, bottom: 0, right: 12)
        row1.heightAnchor.constraint(equalToConstant: 42).isActive = true
        previous.setTitle("上一章", for: .normal)
        previous.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        previous.tintColor = .label
        previous.accessibilityIdentifier = "reader.previous.chapter"
        previous.addTarget(self, action: #selector(backward), for: .touchUpInside)

        nextButton.setTitle("下一章", for: .normal)
        nextButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        nextButton.tintColor = .label
        nextButton.accessibilityIdentifier = "reader.next.chapter"
        nextButton.addTarget(self, action: #selector(forward), for: .touchUpInside)

        readerSeekBar.onCommit = { [weak self] pageIndex in
            guard let self, self.chapters.indices.contains(self.session.chapterIndex), pageIndex >= 0, pageIndex < self.session.imageCount else { return }
            self.environment.readingHabits.userDidRead()
            let chapter = self.chapters[self.session.chapterIndex]
            let target = self.settings.layout == .strip
                ? self.continuousPages.globalIndex(for: chapter, position: ReaderPosition(imageIndex: pageIndex, offset: 0)) : pageIndex
            guard let target else { return }
            if self.settings.layout == .paged {
                self.scrollToPage(target, animated: false)
            } else {
                self.pages.scrollToItem(at: IndexPath(item: target, section: 0), at: .top, animated: false)
            }
            self.session.updateImage(pageIndex)
            self.updateBadge()
            self.savePosition()
        }

        row1.addArrangedSubview(previous)
        row1.addArrangedSubview(readerSeekBar)
        row1.addArrangedSubview(nextButton)
        previous.widthAnchor.constraint(equalToConstant: 60).isActive = true
        nextButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        previous.heightAnchor.constraint(equalToConstant: 40).isActive = true
        nextButton.heightAnchor.constraint(equalToConstant: 40).isActive = true

        // Row 2: 目录 | 换源/详情 | 设置
        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.distribution = .fillEqually
        row2.heightAnchor.constraint(equalToConstant: 46).isActive = true
        row2.isLayoutMarginsRelativeArrangement = true
        row2.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        let directory = UIButton(type: .system), preferences = UIButton(type: .system)
        configureToolbarAction(directory, title: "目录", image: ParityIcon.chapterList.image(size: 20))
        directory.accessibilityIdentifier = "reader.directory"
        directory.addTarget(self, action: #selector(showDirectory), for: .touchUpInside)

        updateMiddleButton()
        middleButton.addTarget(self, action: #selector(middleButtonAction), for: .touchUpInside)

        configureToolbarAction(preferences, title: "设置", image: ParityIcon.settings.image(size: 20))
        preferences.accessibilityIdentifier = "reader.settings"
        preferences.addTarget(self, action: #selector(showSettings), for: .touchUpInside)

        for btn in [directory, middleButton, preferences] { row2.addArrangedSubview(btn) }
        toolbar.addArrangedSubview(row1)
        toolbar.addArrangedSubview(row2)

        status.titleLabel?.numberOfLines = 0
        status.accessibilityIdentifier = "reader.load.status"
        status.addTarget(self, action: #selector(retry), for: .touchUpInside)
        badge.textAlignment = .right
        chapterProgress.isHidden = true; chapterProgress.trackTintColor = .clear; chapterProgress.progressTintColor = .systemBlue

        enhancementBadge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        enhancementBadge.textColor = .white
        enhancementBadge.backgroundColor = UIColor(red: 12/255, green: 20/255, blue: 32/255, alpha: 0.8)
        enhancementBadge.layer.cornerRadius = 4
        enhancementBadge.layer.masksToBounds = true
        enhancementBadge.textAlignment = .center
        enhancementBadge.isHidden = true
        enhancementBadge.accessibilityIdentifier = "reader.enhancement.badge"

        for item in [pages, topChrome, bottomChrome, toolbar, chapterProgress, status, badge, enhancementBadge] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        NSLayoutConstraint.activate([
            pages.topAnchor.constraint(equalTo: view.topAnchor), pages.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pages.leadingAnchor.constraint(equalTo: view.leadingAnchor), pages.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor), toolbar.heightAnchor.constraint(equalToConstant: 88),
            topChrome.topAnchor.constraint(equalTo: view.topAnchor), topChrome.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor), topChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomChrome.topAnchor.constraint(equalTo: toolbar.topAnchor), bottomChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor), bottomChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chapterProgress.bottomAnchor.constraint(equalTo: view.bottomAnchor), chapterProgress.heightAnchor.constraint(equalToConstant: 2),
            chapterProgress.leadingAnchor.constraint(equalTo: view.leadingAnchor), chapterProgress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor), status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            badge.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            badge.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
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
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBadge), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        environment.readingHabits.enterReader(comicID: comic.comicId, isLocal: comic.sourceId == "local")
        syncHabitOverlay()
        applySettings()
        loadChapter(session.chapterIndex)
        if incompleteDirectory { loadDirectory() }
        let revision = FavoriteRevision.fromChapters(latestChapterName: chapters.last?.title, chapters: chapters)
        environment.favoriteUpdateCoordinator.acknowledge(sourceId: comic.sourceId, comicId: comic.comicId, revision: revision)
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
            self?.updateBadge()
        }
        syncHabitOverlay()
        appendNextChapterIfNeeded()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        habitTimer?.invalidate(); habitTimer = nil
        leavingReader = isMovingFromParent
        savePosition()
        if isMovingFromParent {
            downloadRepairAction = nil; downloadRepairController = nil
            loadTask?.cancel(); directoryTask?.cancel()
            cancelContinuation()
            pages.visibleCells.forEach { ($0 as? ReaderImageCell)?.cancel() }
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.overrideUserInterfaceStyle = oldNavigationStyle
            UIDevice.current.isBatteryMonitoringEnabled = oldBatteryMonitoring
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
        headerWidth?.constant = max(44, view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 32)
        if let position = pendingPosition, !viewportTransitioning, !images.isEmpty, pages.bounds.width > 0 {
            pendingPosition = nil; restore(position)
        }
        appendNextChapterIfNeeded()
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        // UIKit may already be recalculating item frames when this callback
        // arrives. Preserve the chapter-local position from the last stable
        // scroll observation instead of interpreting an old offset in new frames.
        let observed = settings.layout == .strip ? lastObservedPosition : nil
        let position = pendingPosition ?? observed?.position ?? currentPosition()
        let chapter = !loading ? (observed?.chapter ?? (chapters.indices.contains(session.chapterIndex) ? chapters[session.chapterIndex] : nil)) : nil
        let token = requestID
        viewportTransitioning = true
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.layout.invalidateLayout() }) { _ in
            if self.requestID == token, let chapter, let segment = self.continuousPages.segment(for: chapter),
               self.session.loaded(chapter: chapter, in: self.chapters, imageCount: segment.imageURLs.count, position: position) {
                self.layout.invalidateLayout()
                self.updateReaderHeading(self.chapters[self.session.chapterIndex])
                self.restore(position)
                self.lastObservedPosition = (chapter, position)
            }
            // Keep scroll callbacks suppressed through layout and restoration.
            self.viewportTransitioning = false
            if self.pendingPosition != nil {
                self.view.setNeedsLayout(); self.view.layoutIfNeeded()
            }
            self.readerSeekBar.configure(currentPage: self.session.imageIndex, total: self.session.imageCount, sessionToken: Int64(self.session.chapterIndex))
            self.appendNextChapterIfNeeded()
        }
    }
    private func applySettings() {
        synchronizeContinuousSession()
        savePosition()
        let position = currentPosition()
        let previousSettings = settings
        let wasRestoring = restoring
        restoring = true
        defer { restoring = wasRestoring }
        settings = environment.preferences.load()
        if pageAnimating {
            pages.setContentOffset(pages.contentOffset, animated: false)
            pageAnimating = false
            restore(position)
        }
        layout.scrollDirection = settings.layout == .strip ? .vertical : .horizontal
        // Reverse page frames explicitly, keeping image pixels and logical
        // chapter/page identities unchanged. Local RTL semantics alone do not
        // reverse UICollectionViewFlowLayout in an LTR application.
        layout.reversesPages = settings.pageDirection == .rightToLeft
        pages.semanticContentAttribute = .forceLeftToRight
        pages.isPagingEnabled = settings.layout == .paged
        pages.isScrollEnabled = settings.layout == .strip && !isZoomed
        let style: UIUserInterfaceStyle = settings.theme == .system ? UIScreen.main.traitCollection.userInterfaceStyle : (settings.theme == .dark ? .dark : .light)
        overrideUserInterfaceStyle = style
        navigationController?.overrideUserInterfaceStyle = style
        pages.backgroundColor = .systemBackground; view.backgroundColor = .systemBackground
        toolbar.backgroundColor = .clear
        badge.isHidden = !fullscreen || settings.fullyImmersive
        presentedViewController?.overrideUserInterfaceStyle = style
        for cell in pages.visibleCells { (cell as? ReaderImageCell)?.apply(settings) }
        if previousSettings.readingMode != settings.readingMode {
            cancelContinuation()
            if chapters.indices.contains(session.chapterIndex), let segment = continuousPages.segment(for: chapters[session.chapterIndex]) {
                images = segment.imageURLs
                continuousPages = ContinuousReaderPages()
                continuousPages.append(chapter: chapters[session.chapterIndex], imageURLs: images)
                session.loaded(imageCount: images.count, position: position)
            }
            layout.invalidateLayout(); pages.reloadData()
            pendingPosition = position
            view.setNeedsLayout()
        }
        updateContinuationFooter()
        setNeedsStatusBarAppearanceUpdate()
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
                self.session.loaded(imageCount: self.continuousPages.segment(for: current)?.imageURLs.count ?? self.images.count, position: position)
                self.incompleteDirectory = false
                self.loadState.directoryFinished()
                self.updateLoadStatus()
                self.updateContinuationFooter()
                self.appendNextChapterIfNeeded()
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
        cancelContinuation()
        lastObservedPosition = nil
        loadTask?.cancel(); requestID = UUID()
        let token = requestID, chapter = chapters[index]
        let requestComic = comic, requestChapters = chapters, requestSource = source
        loadState.chapterStarted()
        chapterRetryAction = { [weak self] in
            guard let self, let currentIndex = self.chapters.firstIndex(where: { $0.chapterId == chapter.chapterId || $0.url == chapter.url }) else { return }
            self.loadChapter(currentIndex, atEnd: atEnd, restoreSaved: restoreSaved)
        }
        updateLoadStatus()
        loadTask = Task { [weak self] in
            do {
                guard let self else { return }
                let page = try await self.fetchChapterPage(chapter: chapter, index: index, comic: requestComic, chapters: requestChapters, source: requestSource)
                try Task.checkCancellation()
                guard self.requestID == token else { return }
                guard !page.imageUrls.isEmpty else { throw ReaderError.noImages }
                let saved = restoreSaved ? self.environment.library.position(for: self.comic, chapterID: chapter.chapterId) : nil
                let position = atEnd ? ReaderPosition(imageIndex: page.imageUrls.count - 1, offset: 0, atEnd: true)
                    : (saved ?? ReaderPosition(imageIndex: 0, offset: 0))
                guard self.session.loaded(chapter: chapter, in: self.chapters, imageCount: page.imageUrls.count, position: position) else { throw ReaderError.chapterMissing }
                self.session.updateImage(position.index(in: page.imageUrls))
                self.images = page.imageUrls; self.sizes = [:]
                self.continuousPages = ContinuousReaderPages()
                self.continuousPages.append(chapter: chapter, imageURLs: page.imageUrls)
                self.title = chapter.title
                self.updateReaderHeading(chapter)
                self.loadState.chapterFinished(); self.updateLoadStatus(); self.lastSaved = nil
                self.pages.reloadData(); self.layout.invalidateLayout()
                self.pendingPosition = position; self.view.setNeedsLayout()
                self.updateBadge()
                self.readerSeekBar.configure(currentPage: self.session.imageIndex, total: self.images.count, sessionToken: Int64(self.session.chapterIndex))
                self.updateContinuationFooter()
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
    private func fetchChapterPage(chapter: Chapter, index: Int, comic: ComicSummary, chapters: [Chapter], source: any ComicSource) async throws -> ChapterPage {
        guard comic.sourceId != "local" else { return try await source.chapter(url: chapter.url) }
        let runtime = environment.downloadRuntime
        if let taskID = try? DownloadModels.key(comic.sourceId, comic.comicId, chapter.chapterId),
           let task = runtime.store.get(id: taskID), task.state == .completed {
            do {
                let detail = ComicDetail(summary: comic, author: "", status: "", description: "", latestChapter: "", chapters: chapters)
                let worker = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    return try runtime.localChapter(detail: detail, chapterIndex: index)
                }
                let local = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let local else { throw DownloadError.corruptedData("本章下载文件需要修复") }
                return local
            } catch {
                ErrorLogStore.shared.append(title: "下载文件损坏: \(comic.title) - \(chapter.title)", error: error)
                throw error
            }
        }
        guard runtime.isNetworkConnected else { throw DownloadError.corruptedData("这一章还没有下载哦") }
        return try await source.chapter(url: chapter.url)
    }

    private var nextContinuousChapterIndex: Int? {
        guard !incompleteDirectory, let last = continuousPages.lastChapter,
              let index = chapters.firstIndex(where: { ContinuousReaderPages.matches($0, last) }),
              chapters.indices.contains(index + 1) else { return nil }
        return index + 1
    }

    private func cancelContinuation() {
        continuationRequestID = UUID()
        continuationTask?.cancel(); continuationTask = nil; continuationError = nil
    }

    private func appendNextChapterIfNeeded() {
        guard settings.layout == .strip, !loading, !restoring, !viewportTransitioning, pendingPosition == nil, !isZoomed, !leavingReader,
              viewIfLoaded?.window != nil, continuationTask == nil, continuationError == nil,
              pages.contentSize.height > 0, pages.bounds.height > 0,
              let lastVisible = pages.indexPathsForVisibleItems.map(\.item).max(),
              lastVisible >= max(0, images.count - 5),
              let index = nextContinuousChapterIndex else { return }
        let chapter = chapters[index], token = UUID(), sceneToken = requestID
        let requestComic = comic, requestChapters = chapters, requestSource = source
        continuationRequestID = token
        continuationTask = Task { [weak self] in
            do {
                guard let self else { return }
                let page = try await self.fetchChapterPage(chapter: chapter, index: index, comic: requestComic, chapters: requestChapters, source: requestSource)
                try Task.checkCancellation()
                guard self.continuationRequestID == token, self.requestID == sceneToken, self.settings.layout == .strip else { return }
                guard self.continuousPages.append(chapter: chapter, imageURLs: page.imageUrls) else { throw ReaderError.noImages }
                let start = self.images.count
                let appended = self.continuousPages.imageURLs
                let inserted = (start..<appended.count).map { IndexPath(item: $0, section: 0) }
                UIView.performWithoutAnimation {
                    self.pages.performBatchUpdates({
                        self.images = appended
                        self.pages.insertItems(at: inserted)
                    }) { [weak self] _ in
                        guard let self, self.continuationRequestID == token else { return }
                        self.continuationTask = nil
                        self.updateContinuationFooter()
                        self.appendNextChapterIfNeeded()
                    }
                }
            } catch {
                guard let self, self.continuationRequestID == token, self.requestID == sceneToken, !Task.isCancelled else { return }
                self.continuationTask = nil; self.continuationError = error
                ErrorLogStore.shared.append(title: "下一章加载失败: \(requestComic.title) - \(chapter.title)", error: error)
                self.updateContinuationFooter()
            }
        }
        updateContinuationFooter()
    }

    private func updateContinuationFooter() {
        guard isViewLoaded else { return }
        for footer in pages.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionFooter) {
            if let footer = footer as? ReaderContinuationFooter { configureContinuationFooter(footer) }
        }
    }

    private func configureContinuationFooter(_ footer: ReaderContinuationFooter) {
        let text: String, canRetry: Bool
        if let error = continuationError {
            if (error as? LocalLibraryError) == .requiresTextReader {
                text = "下一章是文字内容 · 点击继续"
            } else if let error = error as? DownloadError, case .corruptedData(let message) = error {
                text = message + " · 打开下载中心"
            } else { text = "下一章加载失败 · 点击重试" }
            canRetry = true
        } else if continuationTask != nil { text = "正在加载下一章…"; canRetry = false }
        else if incompleteDirectory { text = "等待章节目录"; canRetry = false }
        else if nextContinuousChapterIndex != nil { text = "继续向下阅读"; canRetry = true }
        else { text = "已到最后一章"; canRetry = false }
        footer.configure(text: text, loading: continuationTask != nil, canRetry: canRetry) { [weak self] in
            guard let self else { return }
            if (self.continuationError as? LocalLibraryError) == .requiresTextReader,
               let index = self.nextContinuousChapterIndex {
                self.loadChapter(index, restoreSaved: false); return
            }
            if let error = self.continuationError as? DownloadError, case .corruptedData = error {
                self.showDownloadCenter(forContinuation: true); return
            }
            self.continuationError = nil; self.appendNextChapterIfNeeded(); self.updateContinuationFooter()
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
                    let chPages = (book.chapters?.indices.contains(target.volumeChapterIndex) == true) ? book.chapters![target.volumeChapterIndex].pages : []
                    let targetPage = chPages.last ?? ""
                    let spineIdx = book.pages.firstIndex(of: targetPage) ?? max(0, book.pages.count - 1)
                    let href = (book.epub?.spine.indices.contains(spineIdx) == true) ? book.epub!.spine[spineIdx].fullZipPath : targetPage
                    volLocator = TextLocator(bookID: target.volumeId, chapterIndex: target.volumeChapterIndex,
                                             spineIndex: spineIdx, resourceHref: href, anchorID: "", scrollPercentage: 1.0)
                } else {
                    let chPages = (book.chapters?.indices.contains(target.volumeChapterIndex) == true) ? book.chapters![target.volumeChapterIndex].pages : []
                    let targetPage = chPages.first ?? ""
                    let spineIdx = book.pages.firstIndex(of: targetPage) ?? 0
                    let href = (book.epub?.spine.indices.contains(spineIdx) == true) ? book.epub!.spine[spineIdx].fullZipPath : targetPage
                    volLocator = TextLocator(bookID: target.volumeId, chapterIndex: target.volumeChapterIndex,
                                             spineIndex: spineIdx, resourceHref: href, anchorID: "", scrollPercentage: 0.0)
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
        previous.isEnabled = !loading && (incompleteDirectory || session.chapterIndex > 0)
        nextButton.isEnabled = !loading && (incompleteDirectory || session.chapterIndex + 1 < chapters.count)
        previous.alpha = previous.isEnabled ? 1 : 0.35
        nextButton.alpha = nextButton.isEnabled ? 1 : 0.35
        retryAction = nil
        if loading {
            status.isHidden = false
            status.setTitle("正在加载章节…", for: .normal)
            return
        }
        guard let failure = loadState.visibleFailure else { status.isHidden = true; return }
        status.isHidden = false
        if let dlErr = failure.error as? DownloadError, case .corruptedData(let msg) = dlErr {
            if msg == "这一章还没有下载哦" {
                status.setTitle("这一章还没有下载哦 · 已下载的章节可以在下载中心找到", for: .normal)
            } else {
                status.setTitle(msg + " · 打开下载中心", for: .normal)
            }
            retryAction = { [weak self] in self?.showDownloadCenter() }
            return
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
    private func showDownloadCenter(forContinuation: Bool = false) {
        guard presentedViewController == nil else { return }
        let sceneToken = requestID, retry = chapterRetryAction
        let nextChapter = nextContinuousChapterIndex.map { chapters[$0] }
        downloadRepairAction = { [weak self] in
            guard let self, self.requestID == sceneToken, !self.leavingReader else { return }
            // Always re-read the owned files and their hashes. Returning from the
            // center is not evidence that the user completed a repair.
            if forContinuation {
                guard self.settings.layout == .strip, let nextChapter,
                      let nextIndex = self.nextContinuousChapterIndex,
                      ContinuousReaderPages.matches(self.chapters[nextIndex], nextChapter) else { return }
                self.continuationError = nil
                self.appendNextChapterIfNeeded(); self.updateContinuationFooter()
            } else { retry?() }
        }
        let centerVC = DownloadCenterViewController(environment: environment)
        let nav = UINavigationController(rootViewController: centerVC)
        // The center owns its right-hand network controls, including after a
        // network-mode change. Keep the return action in the independent slot.
        let close = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeSheet))
        close.accessibilityIdentifier = "download.reader.close"; close.accessibilityLabel = "返回阅读"
        centerVC.navigationItem.leftBarButtonItem = close
        downloadRepairController = nav
        environment.readingHabits.userDidRead()
        environment.readingHabits.overlayVisibilityChanged(isVisible: true)
        present(nav, animated: true)
        nav.presentationController?.delegate = self
    }
    private func currentPosition() -> ReaderPosition {
        guard !images.isEmpty, pages.bounds.width > 0 else { return ReaderPosition(imageIndex: 0, offset: 0) }
        if let pendingPosition { return pendingPosition }
        if settings.layout == .paged {
            let center = CGPoint(x: pages.bounds.midX, y: pages.bounds.midY)
            let index = pages.indexPathForItem(at: center)?.item ?? session.imageIndex
            return positionAtImage(max(0, min(images.count - 1, index)), offset: 0, atEnd: index == images.count - 1)
        }
        let index = visibleStripImageIndex()
        guard let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return positionAtImage(index, offset: 0) }
        let offset = (pages.contentOffset.y - frame.minY) / max(1, frame.height)
        let end = pages.contentSize.height > pages.bounds.height && pages.contentOffset.y + pages.bounds.height >= pages.contentSize.height - 2
        return positionAtImage(index, offset: Double(offset), atEnd: end)
    }
    private func positionAtImage(_ index: Int, offset: Double, atEnd: Bool = false) -> ReaderPosition {
        if settings.layout == .strip, let location = continuousPages.location(at: index, offset: offset, atEnd: atEnd) {
            return location.position
        }
        return ReaderPosition(imageIndex: index, offset: offset, atEnd: atEnd,
                       linkedPageID: images.indices.contains(index) ? ReaderPosition.linkedIdentity(in: images[index]) : nil,
                       linkedTailID: images.last.flatMap(ReaderPosition.linkedIdentity(in:)))
    }
    private func visibleStripImageIndex() -> Int {
        let visible = pages.indexPathsForVisibleItems.sorted { $0.item < $1.item }
        let index = visible.first(where: { (layout.layoutAttributesForItem(at: $0)?.frame.maxY ?? 0) > pages.contentOffset.y + 1 }) ?? visible.first
        if let index { return index.item }
        guard chapters.indices.contains(session.chapterIndex) else { return 0 }
        return continuousPages.globalIndex(for: chapters[session.chapterIndex], position: ReaderPosition(imageIndex: session.imageIndex, offset: 0)) ?? 0
    }
    private func synchronizeContinuousSession() {
        guard settings.layout == .strip, !loading, !restoring, !viewportTransitioning, pendingPosition == nil, !images.isEmpty,
              let location = continuousPages.location(at: visibleStripImageIndex()),
              let index = chapters.firstIndex(where: { ContinuousReaderPages.matches($0, location.chapter) }) else { return }
        let position = currentPosition()
        if index != session.chapterIndex {
            if let observed = lastObservedPosition,
               let oldIndex = chapters.firstIndex(where: { ContinuousReaderPages.matches($0, observed.chapter) }) {
                persistPosition(observed.position, chapter: chapters[oldIndex], chapterIndex: oldIndex)
            }
            session.loaded(chapter: location.chapter, in: chapters, imageCount: location.imageURLs.count, position: position)
            lastSaved = nil
            updateReaderHeading(chapters[index])
            updateLoadStatus()
        } else { session.updateImage(position.imageIndex) }
        lastObservedPosition = (chapters[index], position)
    }
    private func restore(_ position: ReaderPosition) {
        guard !images.isEmpty else { return }
        restoring = true
        pages.layoutIfNeeded()
        let chapter = chapters.indices.contains(session.chapterIndex) ? chapters[session.chapterIndex] : nil
        let activeImages = chapter.flatMap { continuousPages.segment(for: $0)?.imageURLs } ?? images
        let localIndex = position.index(in: activeImages)
        let index = settings.layout == .strip
            ? (chapter.flatMap { continuousPages.globalIndex(for: $0, position: position) } ?? localIndex) : localIndex
        if settings.layout == .paged {
            scrollToPage(index, animated: false)
        } else if let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame {
            let maxY = max(0, pages.contentSize.height - pages.bounds.height)
            let tailIndex = chapter.flatMap { continuousPages.segment(for: $0)?.range.last } ?? images.count - 1
            let chapterEnd = layout.layoutAttributesForItem(at: IndexPath(item: tailIndex, section: 0))?.frame.maxY ?? pages.contentSize.height
            let target = position.isAtEnd(in: activeImages) ? max(0, chapterEnd - pages.bounds.height) : frame.minY + frame.height * CGFloat(position.offset)
            pages.setContentOffset(CGPoint(x: 0, y: max(0, min(maxY, target))), animated: false)
        }
        session.updateImage(localIndex); restoring = false
        synchronizeContinuousSession(); updateBadge()
    }
    private func savePosition() {
        guard !loading, !restoring, !viewportTransitioning, !images.isEmpty, chapters.indices.contains(session.chapterIndex) else { return }
        synchronizeContinuousSession()
        let position = currentPosition()
        guard position != lastSaved else { return }
        if persistPosition(position, chapter: chapters[session.chapterIndex], chapterIndex: session.chapterIndex) { lastSaved = position }
    }
    @discardableResult
    private func persistPosition(_ position: ReaderPosition, chapter: Chapter, chapterIndex: Int) -> Bool {
        do {
            try environment.library.saveReading(comic, chapter: chapter, chapterIndex: chapterIndex, position: position)
            return true
        } catch { status.isHidden = false; status.setTitle("阅读位置保存失败：" + error.localizedDescription, for: .normal); return false }
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
        let chapter = chapters.indices.contains(session.chapterIndex) ? chapters[session.chapterIndex] : nil
        let chapterTitle = chapter?.title ?? ""
        let title = chapterTitle.count > 14 ? String(chapterTitle.prefix(13)) + "…" : chapterTitle
        let battery = UIDevice.current.batteryLevel
        let batteryText = battery >= 0 ? "  \(Int((battery * 100).rounded()))%" : ""
        badge.text = "\(title)  \(session.imageIndex + 1)/\(session.imageCount)  \(badgeTimeFormatter.string(from: Date()))\(batteryText)"
        chapterProgress.progress = Float(session.chapterIndex + 1) / Float(max(1, chapters.count))
        pages.accessibilityValue = "\(chapterTitle)，第 \(session.imageIndex + 1) 页，共 \(session.imageCount) 页"
        let index = settings.layout == .strip ? (chapter.flatMap { continuousPages.globalIndex(for: $0, position: ReaderPosition(imageIndex: session.imageIndex, offset: 0)) } ?? 0) : session.imageIndex
        let cell = pages.cellForItem(at: IndexPath(item: index, section: 0)) as? ReaderImageCell
        if settings.enhancementMode != ImageEnhancementPolicy.modeOff, let method = cell?.enhancementMethod,
           method == .neural || method == .fast || method == .fallback {
            enhancementBadge.isHidden = false
            enhancementBadge.text = method == .neural ? " AI 2X " : (method == .fallback ? " 增强（回退） " : " 增强 ")
        } else {
            enhancementBadge.isHidden = true
        }
    }
    @objc private func refreshBadge() { updateBadge() }
    private func updateReaderHeading(_ chapter: Chapter) {
        title = chapter.title
        readerHeading.text = comic.title.isEmpty ? chapter.title : comic.title + " · " + chapter.title
    }
    @objc private func returnToDetail() { navigationController?.popViewController(animated: true) }
    @objc private func retry() { retryAction?() }
    private func configureToolbarAction(_ button: UIButton, title: String, image: UIImage?) {
        var config = UIButton.Configuration.plain()
        config.title = title; config.image = image; config.imagePlacement = .top; config.imagePadding = 2
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes; result.font = .systemFont(ofSize: 11, weight: .medium); return result
        }
        button.configuration = config
        button.accessibilityLabel = title
    }
    private func updateMiddleButton() {
        let local = comic.sourceId == "local"
        configureToolbarAction(middleButton, title: local ? "详情" : "换源", image: (local ? ParityIcon.detail : .source).image(size: 20))
    }
    private func moveChapterFromToolbar(_ delta: Int) {
        guard !loading, !isZoomed, !pageAnimating else { return }
        environment.readingHabits.userDidRead()
        changeChapter(delta)
    }
    @objc private func backward() { moveChapterFromToolbar(-1) }
    @objc private func forward() { moveChapterFromToolbar(1) }
    private func move(_ delta: Int) {
        guard !loading, !isZoomed, !pageAnimating else { return }
        environment.readingHabits.userDidRead()
        session.updateImage(currentPosition().imageIndex)
        if settings.layout == .strip { changeChapter(delta); return }
        switch session.move(delta: delta) {
        case .image(let index):
            pageAnimating = !settings.disablePageAnimation && !settings.inkScreen
            scrollToPage(index, animated: pageAnimating)
            updateBadge()
            if settings.disablePageAnimation || settings.inkScreen { savePosition() }
        case .chapter(_, let atEnd): changeChapter(delta, atEnd: atEnd)
        case .boundary: boundary()
        case .unavailable: break
        }
    }
    private func scrollToPage(_ index: Int, animated: Bool) {
        pages.layoutIfNeeded()
        guard images.indices.contains(index) else { return }
        pages.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: animated)
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
            zoomed: isZoomed, direction: settings.pageDirection)
        switch action {
        case .none: break
        case .move(let delta): move(delta)
        case .toggleControls:
            environment.readingHabits.userDidRead()
            setFullscreen(!fullscreen, animated: true)
        }
    }
    private func setFullscreen(_ hidden: Bool, animated: Bool) {
        guard fullscreen != hidden else { return }
        fullscreen = hidden
        toolbar.isHidden = hidden; topChrome.isHidden = hidden; bottomChrome.isHidden = hidden
        chapterProgress.isHidden = !hidden || images.isEmpty
        badge.isHidden = !hidden || settings.fullyImmersive
        navigationController?.setNavigationBarHidden(hidden, animated: animated)
        setNeedsStatusBarAppearanceUpdate(); setNeedsUpdateOfHomeIndicatorAutoHidden()
        syncHabitOverlay()
    }
    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard settings.pinchZoom, !loading, !pageAnimating,
              let index = pages.indexPathForItem(at: gesture.location(in: pages)),
              let cell = pages.cellForItem(at: index) as? ReaderImageCell else { return }
        environment.readingHabits.userDidRead()
        cell.toggleZoom()
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            pagePanBeganAt = ProcessInfo.processInfo.systemUptime
            setFullscreen(true, animated: true)
        }
        if gesture.state == .cancelled || gesture.state == .failed { pagePanBeganAt = nil }
        guard gesture.state == .ended else { return }
        let began = pagePanBeganAt; pagePanBeganAt = nil
        guard let began, ProcessInfo.processInfo.systemUptime - began < 1,
              !isZoomed, settings.layout == .paged, settings.turnMode != .buttons else { return }
        let translation = gesture.translation(in: pages)
        guard abs(translation.x) > 36, abs(translation.x) > abs(translation.y) * 1.1 else { return }
        move(ReaderNavigation.swipeDelta(dx: Double(translation.x), direction: settings.pageDirection))
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.view === pages {
            let velocity = pan.velocity(in: pages)
            return settings.layout == .paged && settings.turnMode != .buttons && !isZoomed && abs(velocity.x) > abs(velocity.y) * 1.1
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
        controller.onClose = { [weak self] in self?.closeSheet() }
        controller.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        present(controller, animated: true)
        controller.presentationController?.delegate = self
    }
    @objc private func closeSheet() {
        guard let controller = presentedViewController else { return }
        dismiss(animated: true) { [weak self] in self?.sheetDidDismiss(controller) }
    }

    private func sheetDidDismiss(_ controller: UIViewController) {
        syncHabitOverlay()
        guard controller === downloadRepairController else { return }
        let repair = downloadRepairAction
        downloadRepairAction = nil; downloadRepairController = nil
        repair?()
    }
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
        let sheet = SourceSwitchSheet(comic: comic, environment: environment) { [weak self] targetDetail in
            guard let self else { return }
            self.applySwitchedSource(targetDetail: targetDetail)
        }
        let navigation = UINavigationController(rootViewController: sheet)
        navigation.navigationBar.tintColor = Palette.accent
        present(navigation, animated: true)
    }

    private func applySwitchedSource(targetDetail: ComicDetail) {
        guard let targetSource = environment.source(for: targetDetail.summary) else { return }
        savePosition()
        let currentTitle = chapters.indices.contains(session.chapterIndex) ? chapters[session.chapterIndex].title : ""
        let currentIndex = session.chapterIndex
        let targetChapters = targetDetail.chapters
        guard !targetChapters.isEmpty else { return }

        let matchedIndex = ChapterMatching.findMatchingChapterIndex(
            chapters: targetChapters,
            currentTitle: currentTitle,
            defaultIndex: currentIndex
        )

        self.comic = targetDetail.summary
        self.source = targetSource
        self.chapters = targetChapters
        self.incompleteDirectory = false
        self.session = ReaderSession(chapterCount: targetChapters.count, chapterIndex: matchedIndex)
        self.images = []
        self.lastObservedPosition = nil
        self.pages.reloadData()
        self.loadChapter(matchedIndex)
        self.updateMiddleButton()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        sheetDidDismiss(presentationController.presentedViewController)
    }
    private func syncHabitOverlay() {
        environment.readingHabits.overlayVisibilityChanged(isVisible: !fullscreen || presentedViewController != nil)
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { images.count }
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let footer = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "continuation", for: indexPath) as! ReaderContinuationFooter
        configureContinuationFooter(footer)
        return footer
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        settings.layout == .strip && !images.isEmpty ? CGSize(width: collectionView.bounds.width, height: 56) : .zero
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "image", for: indexPath) as! ReaderImageCell
        let url = images[indexPath.item]
        cell.onZoom = { [weak self] zoomed in
            guard let self else { return }; self.isZoomed = zoomed
            self.pages.isScrollEnabled = self.settings.layout == .strip && !zoomed
            if !zoomed { self.appendNextChapterIfNeeded() }
        }
        cell.onUserAction = { [weak self] in
            self?.environment.readingHabits.userDidRead(); self?.setFullscreen(true, animated: true)
        }
        cell.onSize = { [weak self] size in
            guard let self, self.images.contains(url) else { return }
            self.environment.readingHabits.contentBecameReadable()
            guard self.sizes[url] != size else { return }
            self.synchronizeContinuousSession()
            let position = self.currentPosition()
            self.sizes[url] = size
            if self.settings.layout == .strip {
                self.layout.invalidateLayout()
                if !self.viewportTransitioning { self.restore(position) }
            }
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
        cell.onEnhancement = { [weak self] in self?.updateBadge() }
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
        guard !restoring, !viewportTransitioning else { return }
        if settings.layout == .strip { synchronizeContinuousSession() }
        else { session.updateImage(currentPosition().imageIndex) }
        updateBadge()
        readerSeekBar.configure(currentPage: session.imageIndex, total: session.imageCount, sessionToken: Int64(session.chapterIndex))
        appendNextChapterIfNeeded()
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        environment.readingHabits.userDidRead(); setFullscreen(true, animated: true)
    }
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
final class ReaderImageCell: UICollectionViewCell, UIScrollViewDelegate {
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
    private var enhancementTask: Task<Void, Never>?
    private var enhancementGeneration = UUID()
    #if DEBUG
    private var comparisonEvents: [String] = []
    #endif
    private(set) var enhancementMethod: ReaderEnhancementEngine.Result.Method = .original
    var enhancer: @MainActor (String, UIImage, Int) async -> ReaderEnhancementEngine.Result = { url, image, mode in
        await ReaderEnhancementEngine.shared.enhanceResult(url: url, original: image, mode: mode)
    }
    var onEnhancement: (() -> Void)?
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
        image.isAccessibilityElement = true
        image.accessibilityIdentifier = "reader.image"
        image.accessibilityLabel = "阅读图片"
        contentView.addSubview(scroll); scroll.addSubview(image); contentView.addSubview(retry)
        retry.setTitle("正在加载图片…", for: .normal)
        retry.addTarget(self, action: #selector(reload), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        contentView.addGestureRecognizer(longPress)

        image.onLoaded = { [weak self] size in
            guard let self else { return }
            self.retry.isHidden = true
            if let raw = self.image.image { self.displayLoadedImage(raw) }
            let callback = self.onSize
            DispatchQueue.main.async { callback?(size) }
        }
        image.onFailure = { [weak self] in self?.retry.isHidden = false; self?.retry.setTitle("图片加载失败 · 点击重试", for: .normal) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func displayLoadedImage(_ raw: UIImage) {
        stopEnhancement()
        rawImage = raw
        image.image = raw
        updateImageAccessibility()
        guard currentMode != ImageEnhancementPolicy.modeOff else { return }
        let token = enhancementGeneration, sourceURL = url, mode = currentMode, enhance = enhancer
        enhancementTask = Task { [weak self] in
            let result = await enhance(sourceURL, raw, mode)
            guard let self, !Task.isCancelled, self.enhancementGeneration == token,
                  self.url == sourceURL, self.currentMode == mode, self.rawImage === raw else { return }
            self.enhancementMethod = result.method
            self.enhancedImage = result.image
            if !self.isComparing { self.image.image = result.image }
            self.updateImageAccessibility()
            self.onEnhancement?()
        }
    }

    private func updateImageAccessibility() {
        let method = isComparing ? "original" : enhancementMethod.rawValue
        let pixels = image.image?.cgImage
        image.accessibilityValue = "\(method):\(pixels?.width ?? 0)x\(pixels?.height ?? 0)"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), !comparisonEvents.isEmpty {
            image.accessibilityValue = (image.accessibilityValue ?? "") + ";comparison=" + comparisonEvents.joined(separator: ">")
        }
        #endif
    }

    private func stopEnhancement() {
        enhancementGeneration = UUID()
        enhancementTask?.cancel()
        enhancementTask = nil
        if let rawImage { image.image = rawImage }
        if isComparing { onComparing?(false) }
        enhancedImage = nil
        isComparing = false
        enhancementMethod = .original
        updateImageAccessibility()
    }

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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            comparisonEvents.append(isComparing ? "original" : enhancementMethod.rawValue)
            comparisonEvents = Array(comparisonEvents.suffix(8))
        }
        #endif
        updateImageAccessibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = contentView.bounds
        if scroll.zoomScale == 1 { image.frame = scroll.bounds; scroll.contentSize = scroll.bounds.size }
        retry.frame = CGRect(x: 0, y: max(0, bounds.midY - 22), width: bounds.width, height: 44)
    }
    func configure(url: String, referer: String, settings: ReaderPreferences, localPageImage: (@Sendable (URL) throws -> Data)? = nil) {
        stopEnhancement()
        rawImage = nil
        self.url = url; self.referer = referer
        self.localPageImage = localPageImage
        self.currentMode = settings.enhancementMode
        self.comparisonEnabled = settings.enhancementComparison
        scroll.setZoomScale(1, animated: false)
        apply(settings)
        reload()
    }
    func apply(_ settings: ReaderPreferences) {
        let changedMode = currentMode != settings.enhancementMode
        if changedMode { stopEnhancement() }
        self.currentMode = settings.enhancementMode
        self.comparisonEnabled = settings.enhancementComparison
        setZoomEnabled(settings.pinchZoom)
        image.setReaderEffects(crop: settings.cropWhiteMargins, vertical: settings.layout == .paged, ink: settings.inkScreen)
        if changedMode, let raw = rawImage { displayLoadedImage(raw) }
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
    func cancel() { stopEnhancement(); image.cancel() }
    override func prepareForReuse() {
        super.prepareForReuse()
        cancel()
        localPageImage = nil
        onSize = nil
        onZoom = nil
        onUserAction = nil
        onComparing = nil
        onEnhancement = nil
        rawImage = nil
        enhancedImage = nil
        isComparing = false
        #if DEBUG
        comparisonEvents.removeAll()
        #endif
        scroll.setZoomScale(1, animated: false)
    }
}
