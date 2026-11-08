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
    private lazy var spreadStore = SpreadStateStore(defaults: environment.defaults)
    private lazy var doublePageStore = DoublePageStateStore(defaults: environment.defaults)
    private var rawChapterURLs: [String: [String]] = [:]
    private var spreadPlans: [String: SpreadPagePlan] = [:]
    private var doublePagePlans: [String: DoublePagePlan] = [:]
    private var virtualUnits: [String: SpreadPagePlan.Unit] = [:]
    private var scanTask: Task<Void, Never>?
    private var scanToken = UUID()
    private var spreadSamples: [String: SpreadDetector.Sample] = [:]
    private var doublePageSamples: [String: DoublePageDetector.Sample] = [:]
    private var scanStatusText: String?
    private var pendingAutoScanRefresh = false
    private weak var activeSettingsSheet: ReaderSettingsViewController?
    private var bookKey: String { "\(comic.sourceId):\(comic.comicId)" }
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
    private var pendingPositionNeedsContinuation = false
    private var lastSaved: ReaderPosition?
    private var pagedAnchor: ReaderPosition?
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
    private let extraDimOverlay = UIView()
    private let pullHintLabel = ReaderPullHintLabel()
    private var pullStartedAtTop = false
    private var pullReadyToRelease = false
    private var pullTargetChapterIndex: Int?
    private var savedSystemBrightness: CGFloat?
    private var oldInteractivePopEnabled: Bool?
    private var lastInteractionUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var pendingSaveTask: Task<Void, Never>?
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
    var onSourceChanged: ((ComicDetail) -> Void)?
#if DEBUG
    private var readerTrace: [String] = []
#endif

    private func recordReaderTrace(_ event: String) {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        let pending = pendingPosition.map { String($0.imageIndex) } ?? "nil"
        let point = pages.contentOffset, size = pages.bounds.size, content = pages.contentSize
        readerTrace.append("\(event) mode=\(settings.readingMode.rawValue) page=\(session.imageIndex) pending=\(pending) offset=\(point.x),\(point.y) size=\(size.width),\(size.height) content=\(content.width),\(content.height) restoring=\(restoring) animating=\(pageAnimating) fullscreen=\(fullscreen)")
        if readerTrace.count > 96 { readerTrace.removeFirst(readerTrace.count - 96) }
        pages.accessibilityLabel = readerTrace.joined(separator: "\n")
#endif
    }

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
    deinit {
        loadTask?.cancel(); directoryTask?.cancel(); continuationTask?.cancel(); scanTask?.cancel()
        pendingSaveTask?.cancel()
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                UIApplication.shared.isIdleTimerDisabled = false
                if let saved = savedSystemBrightness {
                    UIScreen.main.brightness = saved
                }
            }
        }
    }
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
            self.pendingPosition = nil; self.pendingPositionNeedsContinuation = false
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

        extraDimOverlay.backgroundColor = .black
        extraDimOverlay.alpha = 0
        extraDimOverlay.isHidden = true
        extraDimOverlay.isUserInteractionEnabled = false
        extraDimOverlay.accessibilityIdentifier = "reader.extra.dim"

        pullHintLabel.isHidden = true
        pullHintLabel.alpha = 0
        pullHintLabel.isUserInteractionEnabled = false
        pullHintLabel.accessibilityIdentifier = "reader.pull.hint"

        for item in [pages, extraDimOverlay, pullHintLabel, topChrome, bottomChrome, toolbar, chapterProgress, status, badge, enhancementBadge] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        NSLayoutConstraint.activate([
            pages.topAnchor.constraint(equalTo: view.topAnchor), pages.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pages.leadingAnchor.constraint(equalTo: view.leadingAnchor), pages.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            extraDimOverlay.topAnchor.constraint(equalTo: view.topAnchor), extraDimOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            extraDimOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor), extraDimOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pullHintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            pullHintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pullHintLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
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
        if oldInteractivePopEnabled == nil {
            oldInteractivePopEnabled = navigationController?.interactivePopGestureRecognizer?.isEnabled
        }
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        noteUserInteraction()
        applyKeepScreenPolicy(active: true)
        applyBrightnessPolicy(active: true)
        habitTimer?.invalidate()
        habitTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.environment.readingHabits.tick()
            self?.checkKeepScreenIdleExpiration()
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
            cancelScan()
            cancelContinuation()
            pages.visibleCells.forEach { ($0 as? ReaderImageCell)?.cancel() }
            if let oldPop = oldInteractivePopEnabled {
                navigationController?.interactivePopGestureRecognizer?.isEnabled = oldPop
                oldInteractivePopEnabled = nil
            }
            applyKeepScreenPolicy(active: false)
            applyBrightnessPolicy(active: false)
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
        if let position = pendingPosition, !restoring, !viewportTransitioning, !images.isEmpty, pages.bounds.width > 0 {
            recordReaderTrace("layout.pending")
            // Reload/layout callbacks must still see the requested logical
            // position until the new axis has been laid out and restored.
            if restore(position) {
                pendingPosition = nil
                synchronizeContinuousSession(); updateBadge()
                recordReaderTrace("layout.restored")
            }
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
        recordReaderTrace("settings.begin")
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
        pages.alwaysBounceVertical = settings.layout == .strip
        let style: UIUserInterfaceStyle = settings.theme == .system ? UIScreen.main.traitCollection.userInterfaceStyle : (settings.theme == .dark ? .dark : .light)
        overrideUserInterfaceStyle = style
        navigationController?.overrideUserInterfaceStyle = style
        pages.backgroundColor = .systemBackground; view.backgroundColor = .systemBackground
        toolbar.backgroundColor = .clear
        badge.isHidden = !fullscreen || settings.fullyImmersive
        presentedViewController?.overrideUserInterfaceStyle = style
        let isActiveWindow = viewIfLoaded?.window != nil && UIApplication.shared.applicationState == .active
        applyKeepScreenPolicy(active: isActiveWindow)
        applyBrightnessPolicy(active: isActiveWindow)
        for cell in pages.visibleCells { (cell as? ReaderImageCell)?.apply(settings) }
        if previousSettings.readingMode != settings.readingMode {
            pendingPositionNeedsContinuation = false
            if settings.layout == .paged { pagedAnchor = position }
            cancelContinuation()
            if chapters.indices.contains(session.chapterIndex), let segment = continuousPages.segment(for: chapters[session.chapterIndex]) {
                images = segment.imageURLs
                continuousPages = ContinuousReaderPages()
                continuousPages.append(chapter: chapters[session.chapterIndex], imageURLs: images)
                session.loaded(imageCount: images.count, position: position)
            }
            pendingPosition = position
            layout.invalidateLayout(); pages.reloadData()
            view.setNeedsLayout()
            recordReaderTrace("settings.pending(\(position.imageIndex),\(position.offset))")
        }
        updateContinuationFooter()
        setNeedsStatusBarAppearanceUpdate()
        recordReaderTrace("settings.end")
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
        pendingPosition = nil; pendingPositionNeedsContinuation = false
        cancelScan()
        cancelContinuation()
        lastObservedPosition = nil
        pagedAnchor = nil
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
                let sourcePos = atEnd ? ReaderPosition(imageIndex: page.imageUrls.count - 1, offset: 0, atEnd: true)
                    : (saved ?? ReaderPosition(imageIndex: 0, offset: 0))
                let plan = self.buildPresentationPlan(for: chapter, rawURLs: page.imageUrls)
                let position = self.displayPosition(from: sourcePos, plan: plan)
                guard self.session.loaded(chapter: chapter, in: self.chapters, imageCount: plan.displayKeys.count, position: position) else { throw ReaderError.chapterMissing }
                self.session.updateImage(position.index(in: plan.displayKeys))
                self.images = plan.displayKeys; self.sizes = [:]
                self.pagedAnchor = position.forPagedImage(at: self.session.imageIndex, in: self.images)
                self.continuousPages = ContinuousReaderPages()
                self.continuousPages.append(chapter: chapter, imageURLs: plan.displayKeys)
                self.title = chapter.title
                self.updateReaderHeading(chapter)
                self.loadState.chapterFinished(); self.updateLoadStatus(); self.lastSaved = nil
                self.pendingPosition = position
                self.pages.reloadData(); self.layout.invalidateLayout()
                self.view.setNeedsLayout()
                self.updateBadge()
                self.readerSeekBar.configure(currentPage: self.session.imageIndex, total: self.images.count, sessionToken: Int64(self.session.chapterIndex))
                self.updateContinuationFooter()
                self.startPresentationScan(for: chapter, plan: plan, anchor: sourcePos.index(in: page.imageUrls))
            } catch {
                guard let self, self.requestID == token, !Task.isCancelled else { return }
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
        guard settings.layout == .strip, !loading, !restoring, !viewportTransitioning,
              (pendingPosition == nil || pendingPositionNeedsContinuation), !isZoomed, !leavingReader,
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
                let plan = self.buildPresentationPlan(for: chapter, rawURLs: page.imageUrls)
                guard self.continuousPages.append(chapter: chapter, imageURLs: plan.displayKeys) else { throw ReaderError.noImages }
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
                        if self.pendingPosition != nil {
                            self.view.setNeedsLayout(); self.view.layoutIfNeeded()
                        }
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
            if (error as? LocalLibraryError) == .unsupportedTextContent {
                text = "下一章包含文字内容，暂不支持阅读"
            } else if let error = error as? DownloadError, case .corruptedData(let message) = error {
                text = message + " · 打开下载中心"
            } else { text = "下一章加载失败 · 点击重试" }
            canRetry = (error as? LocalLibraryError) != .unsupportedTextContent
        } else if continuationTask != nil { text = "正在加载下一章…"; canRetry = false }
        else if incompleteDirectory { text = "等待章节目录"; canRetry = false }
        else if nextContinuousChapterIndex != nil { text = "继续向下阅读"; canRetry = true }
        else { text = "已到最后一章"; canRetry = false }
        footer.configure(text: text, loading: continuationTask != nil, canRetry: canRetry) { [weak self] in
            guard let self else { return }
            if let error = self.continuationError as? DownloadError, case .corruptedData = error {
                self.showDownloadCenter(forContinuation: true); return
            }
            self.continuationError = nil; self.appendNextChapterIfNeeded(); self.updateContinuationFooter()
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
        if (failure.error as? LocalLibraryError) == .unsupportedTextContent {
            status.setTitle(failure.error.localizedDescription, for: .normal)
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
            let target = max(0, min(images.count - 1, index))
            let anchor = pagedAnchor ?? positionAtImage(target, offset: 0, atEnd: target == images.count - 1)
            let position = anchor.forPagedImage(at: target, in: images)
            pagedAnchor = position
            return position
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
    @discardableResult
    private func restore(_ position: ReaderPosition) -> Bool {
        guard !images.isEmpty else { return false }
        recordReaderTrace("restore.begin(\(position.imageIndex),\(position.offset))")
        let wasRestoring = restoring
        restoring = true
        defer { restoring = wasRestoring }
        layout.prepareForPositionRestore()
        pendingPositionNeedsContinuation = false
        let chapter = chapters.indices.contains(session.chapterIndex) ? chapters[session.chapterIndex] : nil
        let activeImages = chapter.flatMap { continuousPages.segment(for: $0)?.imageURLs } ?? images
        let localIndex = position.index(in: activeImages)
        let index = settings.layout == .strip
            ? (chapter.flatMap { continuousPages.globalIndex(for: $0, position: position) } ?? localIndex) : localIndex
        if settings.layout == .paged {
            guard layout.scrollToLogicalPage(index, animated: false) else { return false }
            pagedAnchor = position.forPagedImage(at: localIndex, in: activeImages)
        } else if let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame {
            let maxY = max(0, pages.contentSize.height - pages.bounds.height)
            let tailIndex = chapter.flatMap { continuousPages.segment(for: $0)?.range.last } ?? images.count - 1
            let chapterEnd = layout.layoutAttributesForItem(at: IndexPath(item: tailIndex, section: 0))?.frame.maxY ?? pages.contentSize.height
            let target = position.isAtEnd(in: activeImages) ? max(0, chapterEnd - pages.bounds.height) : frame.minY + frame.height * CGFloat(position.offset)
            pages.setContentOffset(CGPoint(x: 0, y: max(0, min(maxY, target))), animated: false)
            if target > maxY + 0.5, nextContinuousChapterIndex != nil {
                // Decoding an image can shrink a strip that was already restored.
                // Preserve that anchor too: the next chapter supplies the missing
                // height, and the temporary clamp must not become a saved position.
                pendingPosition = position
                pendingPositionNeedsContinuation = true
                session.updateImage(localIndex); updateBadge()
                recordReaderTrace("restore.waiting-for-continuation")
                return false
            }
        } else { return false }
        session.updateImage(localIndex)
        updateBadge()
        recordReaderTrace("restore.end")
        return true
    }
    private func scheduleSavePosition() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.pendingSaveTask = nil
            self.savePosition()
        }
    }
    private func savePosition() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        guard !loading, !restoring, !viewportTransitioning, !images.isEmpty, chapters.indices.contains(session.chapterIndex) else { return }
        synchronizeContinuousSession()
        let position = currentPosition()
        guard position != lastSaved else { return }
        if persistPosition(position, chapter: chapters[session.chapterIndex], chapterIndex: session.chapterIndex) { lastSaved = position }
    }
    @discardableResult
    private func persistPosition(_ position: ReaderPosition, chapter: Chapter, chapterIndex: Int) -> Bool {
        do {
            let sourcePos = sourcePosition(from: position, chapter: chapter)
            try environment.library.saveReading(comic, chapter: chapter, chapterIndex: chapterIndex, position: sourcePos)
            return true
        } catch { status.isHidden = false; status.setTitle("阅读位置保存失败：" + error.localizedDescription, for: .normal); return false }
    }
    @objc private func saveBeforeBackground() {
        savePosition()
        applyKeepScreenPolicy(active: false)
        applyBrightnessPolicy(active: false)
    }
    @objc private func refreshReaderTheme() {
        noteUserInteraction()
        if viewIfLoaded?.window != nil { applySettings() }
    }
    private func noteUserInteraction() {
        lastInteractionUptime = ProcessInfo.processInfo.systemUptime
        let minutes = ReaderComfortPolicy.normalizeKeepScreenMinutes(settings.keepScreenMinutes)
        if minutes != ReaderComfortPolicy.keepScreenSystem,
           viewIfLoaded?.window != nil,
           UIApplication.shared.applicationState == .active,
           !UIApplication.shared.isIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
    private func checkKeepScreenIdleExpiration() {
        let minutes = ReaderComfortPolicy.normalizeKeepScreenMinutes(settings.keepScreenMinutes)
        if ReaderComfortPolicy.isKeepScreenIdleExpired(
            minutes: minutes,
            lastInteractionUptime: lastInteractionUptime,
            nowUptime: ProcessInfo.processInfo.systemUptime
        ) {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    private func applyKeepScreenPolicy(active: Bool) {
        guard active else {
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        let minutes = ReaderComfortPolicy.normalizeKeepScreenMinutes(settings.keepScreenMinutes)
        switch minutes {
        case ReaderComfortPolicy.keepScreenSystem:
            UIApplication.shared.isIdleTimerDisabled = false
        case ReaderComfortPolicy.keepScreenAlways:
            UIApplication.shared.isIdleTimerDisabled = true
        default:
            let expired = ReaderComfortPolicy.isKeepScreenIdleExpired(
                minutes: minutes,
                lastInteractionUptime: lastInteractionUptime,
                nowUptime: ProcessInfo.processInfo.systemUptime
            )
            UIApplication.shared.isIdleTimerDisabled = !expired
        }
    }
    private func applyBrightnessPolicy(active: Bool) {
        let dimAlpha = ReaderComfortPolicy.resolveExtraDimAlpha(readerVisible: active, dim: settings.brightnessDim)
        extraDimOverlay.alpha = CGFloat(dimAlpha)
        extraDimOverlay.isHidden = dimAlpha <= 0.001

        guard active else {
            if let saved = savedSystemBrightness {
                UIScreen.main.brightness = saved
                savedSystemBrightness = nil
            }
            return
        }
        if settings.brightnessFollowSystem {
            if let saved = savedSystemBrightness {
                UIScreen.main.brightness = saved
                savedSystemBrightness = nil
            }
        } else {
            if savedSystemBrightness == nil {
                savedSystemBrightness = UIScreen.main.brightness
            }
            let target = CGFloat(ReaderComfortPolicy.clampBrightness(settings.brightnessLevel))
            if abs(UIScreen.main.brightness - target) > 0.005 {
                UIScreen.main.brightness = target
            }
        }
    }
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
        readerHeading.accessibilityValue = source.name
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
        recordReaderTrace("move.request(\(delta))")
        guard !loading, !isZoomed, !pageAnimating else { return }
        environment.readingHabits.userDidRead()
        session.updateImage(currentPosition().imageIndex)
        if settings.layout == .strip { changeChapter(delta); return }
        switch session.move(delta: delta) {
        case .image(let index):
            pageAnimating = !settings.disablePageAnimation && !settings.inkScreen
            scrollToPage(index, animated: pageAnimating)
            recordReaderTrace("move.page(\(index))")
            updateBadge()
            if settings.disablePageAnimation || settings.inkScreen { savePosition() }
        case .chapter(_, let atEnd): changeChapter(delta, atEnd: atEnd)
        case .boundary: boundary()
        case .unavailable: break
        }
    }
    private func scrollToPage(_ index: Int, animated: Bool) {
        guard images.indices.contains(index) else { return }
        layout.scrollToLogicalPage(index, animated: animated)
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
        noteUserInteraction()
        let location = gesture.location(in: pages)
        if let indexPath = pages.indexPathForItem(at: location),
           let cell = pages.cellForItem(at: indexPath) as? ReaderImageCell,
           cell.retryIfFailed() {
            environment.readingHabits.userDidRead()
            recordReaderTrace("tap.retry(\(indexPath.item))")
            return
        }
        let action = ReaderNavigation.tapAction(
            x: Double((location.x - pages.bounds.minX) / max(1, pages.bounds.width)),
            y: Double((location.y - pages.bounds.minY) / max(1, pages.bounds.height)),
            // The current three reading modes support taps and horizontal turns.
            // Keep archived input preferences without reviving the retired
            // button-only mode, whose separate page buttons no longer exist.
            controlsVisible: !fullscreen, layout: settings.layout, mode: .tap,
            zoomed: isZoomed, direction: settings.pageDirection)
        recordReaderTrace("tap(\(location.x),\(location.y)): \(action)")
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
              !isZoomed, settings.layout == .paged else { return }
        let translation = gesture.translation(in: pages)
        guard abs(translation.x) > 36, abs(translation.x) > abs(translation.y) * 1.1 else { return }
        move(ReaderNavigation.swipeDelta(dx: Double(translation.x), direction: settings.pageDirection))
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.view === pages {
            let velocity = pan.velocity(in: pages)
            guard settings.layout == .paged && !isZoomed && abs(velocity.x) > abs(velocity.y) * 1.1 else { return false }
            let location = pan.location(in: pages)
            if let indexPath = pages.indexPathForItem(at: location),
               let cell = pages.cellForItem(at: indexPath) as? ReaderImageCell,
               cell.canPanHorizontally(dx: velocity.x) {
                return false
            }
            return true
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

    // MARK: - Virtual Presentation Plan (Spread & Double-Page)

    private func chapterPositionKey(_ chapter: Chapter) -> String {
        chapter.chapterId.isEmpty ? chapter.url : chapter.chapterId
    }

    private func currentSpreadStatusText() -> String {
        guard spreadStore.enabled(bookKey) else {
            return "当前按原页显示，开启后可自动识别和手动调整"
        }
        return scanStatusText ?? "只合并接缝明确的相邻图片，按本书记忆"
    }

    private func currentDoublePageStatusText() -> String {
        guard doublePageStore.enabled(bookKey) else {
            return "当前按原页显示，开启后会在本机识别宽页并切成左右两页"
        }
        return scanStatusText ?? "宽图自动切为左右两页，按本书记忆"
    }

    private func buildPresentationPlan(for chapter: Chapter, rawURLs: [String]) -> SpreadPagePlan {
        let posKey = chapterPositionKey(chapter)
        rawChapterURLs[posKey] = rawURLs
        let book = bookKey
        let plan: SpreadPagePlan
        do {
            if doublePageStore.enabled(book) {
                let identity = DoublePagePlan(chapterIdentity: posKey, originals: rawURLs, enabled: false, rightFirst: doublePageStore.rightFirst(book))
                let manual = try doublePageStore.manual(book: book, revision: identity.revision)
                let automatic = doublePageStore.automatic(book: book, revision: identity.revision)
                let doublePlan = DoublePagePlan(chapterIdentity: posKey, originals: rawURLs, enabled: true, rightFirst: doublePageStore.rightFirst(book), manual: manual, automatic: automatic)
                doublePagePlans[posKey] = doublePlan
                plan = SpreadPagePlan.fromDoublePagePlan(doublePlan)
            } else if spreadStore.enabled(book) {
                doublePagePlans.removeValue(forKey: posKey)
                let identity = SpreadPagePlan(chapterIdentity: posKey, originals: rawURLs, enabled: false)
                let manual = try spreadStore.manual(book: book, revision: identity.revision)
                let automatic = spreadStore.automatic(book: book, revision: identity.revision)
                plan = SpreadPagePlan(chapterIdentity: posKey, originals: rawURLs, enabled: true, manual: manual, automatic: automatic)
            } else {
                doublePagePlans.removeValue(forKey: posKey)
                plan = SpreadPagePlan(chapterIdentity: posKey, originals: rawURLs, enabled: false)
            }
        } catch {
            if doublePageStore.enabled(book) {
                let fallback = DoublePagePlan(chapterIdentity: posKey, originals: rawURLs, enabled: false, rightFirst: doublePageStore.rightFirst(book))
                doublePagePlans[posKey] = fallback
                plan = SpreadPagePlan.fromDoublePagePlan(fallback)
            } else {
                doublePagePlans.removeValue(forKey: posKey)
                plan = SpreadPagePlan(chapterIdentity: posKey, originals: rawURLs, enabled: false)
            }
        }
        spreadPlans[posKey] = plan
        for unit in plan.units where unit.isSpread || unit.isDoublePage {
            virtualUnits[unit.key] = unit
        }
        return plan
    }

    private func displayPosition(from sourcePosition: ReaderPosition, plan: SpreadPagePlan) -> ReaderPosition {
        guard !plan.units.isEmpty else { return sourcePosition }
        if plan.units.count == plan.originals.count && plan.displayKeys == plan.originals {
            return sourcePosition
        }
        let sourceIdx = sourcePosition.index(in: plan.originals)
        let displayIdx = sourcePosition.atEnd && sourceIdx >= plan.originals.count - 1
            ? max(0, plan.units.count - 1)
            : plan.displayForSource(sourceIdx)
        return ReaderPosition(
            imageIndex: displayIdx,
            offset: sourcePosition.offset,
            atEnd: sourcePosition.atEnd,
            linkedPageID: plan.displayKeys.indices.contains(displayIdx) ? ReaderPosition.linkedIdentity(in: plan.displayKeys[displayIdx]) : nil,
            linkedTailID: plan.displayKeys.last.flatMap(ReaderPosition.linkedIdentity(in:))
        )
    }

    private func sourcePosition(from displayPosition: ReaderPosition, chapter: Chapter) -> ReaderPosition {
        guard let plan = spreadPlans[chapterPositionKey(chapter)], !plan.originals.isEmpty else {
            return displayPosition
        }
        if plan.units.count == plan.originals.count && plan.displayKeys == plan.originals {
            return displayPosition
        }
        let displayIdx = displayPosition.index(in: plan.displayKeys)
        let sourceIdx = plan.unit(displayIdx)?.first ?? min(displayIdx, plan.originals.count - 1)
        return ReaderPosition(
            imageIndex: sourceIdx,
            offset: displayPosition.offset,
            atEnd: displayPosition.atEnd,
            linkedPageID: plan.originals.indices.contains(sourceIdx) ? ReaderPosition.linkedIdentity(in: plan.originals[sourceIdx]) : nil,
            linkedTailID: plan.originals.last.flatMap(ReaderPosition.linkedIdentity(in:))
        )
    }

    private func activeSpreadPlan() -> SpreadPagePlan? {
        guard chapters.indices.contains(session.chapterIndex) else { return nil }
        return spreadPlans[chapterPositionKey(chapters[session.chapterIndex])]
    }

    private func activeDoublePagePlan() -> DoublePagePlan? {
        guard chapters.indices.contains(session.chapterIndex) else { return nil }
        return doublePagePlans[chapterPositionKey(chapters[session.chapterIndex])]
    }

    private func currentDisplayIndex() -> Int {
        guard let plan = activeSpreadPlan(), !plan.units.isEmpty else { return 0 }
        let pos = currentPosition()
        return max(0, min(plan.units.count - 1, pos.imageIndex))
    }

    private func reloadCurrentChapterPresentation() {
        guard !loading, chapters.indices.contains(session.chapterIndex) else { return }
        synchronizeContinuousSession()
        let activeChapter = chapters[session.chapterIndex]
        let posKey = chapterPositionKey(activeChapter)
        guard let activeRaw = rawChapterURLs[posKey], !activeRaw.isEmpty else { return }
        let sourcePos = sourcePosition(from: currentPosition(), chapter: activeChapter)

        let activePlan = buildPresentationPlan(for: activeChapter, rawURLs: activeRaw)
        let newDisplayPos = displayPosition(from: sourcePos, plan: activePlan)

        if settings.layout == .strip && continuousPages.segments.count > 1 {
            let loadedChapters = continuousPages.segments.map(\.chapter)
            var rebuilt = ContinuousReaderPages()
            for ch in loadedChapters {
                let chKey = chapterPositionKey(ch)
                if let chRaw = rawChapterURLs[chKey], !chRaw.isEmpty {
                    let chPlan = ContinuousReaderPages.matches(ch, activeChapter) ? activePlan : buildPresentationPlan(for: ch, rawURLs: chRaw)
                    rebuilt.append(chapter: ch, imageURLs: chPlan.displayKeys)
                }
            }
            continuousPages = rebuilt
            images = rebuilt.imageURLs
        } else {
            continuousPages = ContinuousReaderPages()
            continuousPages.append(chapter: activeChapter, imageURLs: activePlan.displayKeys)
            images = activePlan.displayKeys
        }

        _ = session.loaded(chapter: activeChapter, in: chapters, imageCount: activePlan.displayKeys.count, position: newDisplayPos)
        session.updateImage(newDisplayPos.index(in: activePlan.displayKeys))
        pagedAnchor = newDisplayPos.forPagedImage(at: session.imageIndex, in: activePlan.displayKeys)
        pendingPosition = newDisplayPos
        pendingPositionNeedsContinuation = false
        layout.invalidateLayout()
        pages.reloadData()
        view.setNeedsLayout()
        updateBadge()
        readerSeekBar.configure(currentPage: session.imageIndex, total: activePlan.displayKeys.count, sessionToken: Int64(session.chapterIndex))
        updateContinuationFooter()
        startPresentationScan(for: activeChapter, plan: activePlan, anchor: sourcePos.index(in: activeRaw))
    }

    private func cancelScan() {
        scanToken = UUID()
        scanTask?.cancel()
        scanTask = nil
        pendingAutoScanRefresh = false
    }

    private func updateSettingsScanStatus() {
        activeSettingsSheet?.spreadStatus = currentSpreadStatusText()
        activeSettingsSheet?.doublePageStatus = currentDoublePageStatusText()
    }

    private func scheduleAutoPresentationRefresh(expectedBook: String, expectedChapterKey: String) {
        guard !pendingAutoScanRefresh else { return }
        pendingAutoScanRefresh = true
        Task { @MainActor [weak self] in
            while let self, !self.leavingReader {
                guard self.bookKey == expectedBook,
                      self.chapters.indices.contains(self.session.chapterIndex),
                      self.chapterPositionKey(self.chapters[self.session.chapterIndex]) == expectedChapterKey else {
                    self.pendingAutoScanRefresh = false
                    return
                }
                if self.isZoomed || self.pageAnimating || self.pages.isDragging || self.pages.isDecelerating {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                self.pendingAutoScanRefresh = false
                self.reloadCurrentChapterPresentation()
                return
            }
            self?.pendingAutoScanRefresh = false
        }
    }

    private func startPresentationScan(for chapter: Chapter, plan: SpreadPagePlan, anchor: Int) {
        cancelScan()
        let book = bookKey
        let posKey = chapterPositionKey(chapter)
        let referer = source.referer
        let localLoader = localPageImage
        let token = scanToken

        if doublePageStore.enabled(book) {
            guard let doublePlan = doublePagePlans[posKey], !doublePlan.originals.isEmpty else { return }
            if doublePageStore.complete(book: book, revision: doublePlan.revision) {
                scanStatusText = "本章识别完成，可手动修正"
                updateSettingsScanStatus()
                return
            }
            scanStatusText = "正在本机识别双页，原页可继续阅读"
            updateSettingsScanStatus()
            let total = doublePlan.originals.count
            var order: [Int] = []
            var added = Set<Int>()
            for i in max(0, anchor - 4)..<min(total, anchor + 12) {
                order.append(i); added.insert(i)
            }
            for i in 0..<total where !added.contains(i) { order.append(i) }

            scanTask = Task { [weak self] in
                guard let self else { return }
                var found: [Int: DoublePageDetector.Sample] = [:]
                var checked = 0
                var failures = 0
                for idx in order {
                    if Task.isCancelled || self.scanToken != token || !self.doublePageStore.enabled(book) { return }
                    let url = doublePlan.originals[idx]
                    let sampleKey = doublePlan.revision + "\n" + url
                    if let cached = self.doublePageSamples[sampleKey] {
                        found[idx] = cached
                    } else {
                        do {
                            if let dims = try await RemoteImageView.probeImageDimensions(url: url, referer: referer, localPageImage: localLoader),
                               let sample = DoublePageDetector.measure(width: Int(dims.width), height: Int(dims.height)) {
                                self.doublePageSamples[sampleKey] = sample
                                found[idx] = sample
                            } else {
                                failures += 1
                            }
                        } catch {
                            if Task.isCancelled || self.scanToken != token { return }
                            failures += 1
                        }
                    }
                    checked += 1
                    self.scanStatusText = "正在识别双页 · \(checked) / \(total)"
                    self.updateSettingsScanStatus()
                }
                guard !Task.isCancelled, self.scanToken == token, self.doublePageStore.enabled(book) else { return }
                let allSamples: [DoublePageDetector.Sample?] = (0..<total).map { found[$0] }
                let median = DoublePageDetector.median(allSamples)
                var decisions: [Int: DoublePagePlan.Decision] = [:]
                for i in 0..<total {
                    if let s = allSamples[i] {
                        let d = DoublePageDetector.decide(sample: s, chapterMedian: median, index: i, count: total)
                        decisions[i] = DoublePagePlan.Decision(split: d.split, score: d.score, aspect: d.aspect)
                    }
                }
                self.doublePageStore.saveAutomatic(book: book, revision: doublePlan.revision, decisions: decisions, complete: failures == 0)
                self.scanStatusText = failures == 0 ? "本章识别完成，可手动修正" : "部分图片未能识别，可重新识别本章"
                self.updateSettingsScanStatus()
                let nextPlan = DoublePagePlan(
                    chapterIdentity: posKey,
                    originals: doublePlan.originals,
                    enabled: true,
                    rightFirst: self.doublePageStore.rightFirst(book),
                    manual: self.doublePageStore.manualRules(book: book, revision: doublePlan.revision),
                    automatic: decisions
                )
                if nextPlan.displayKeys != doublePlan.displayKeys {
                    self.scheduleAutoPresentationRefresh(expectedBook: book, expectedChapterKey: posKey)
                }
            }
            return
        }

        guard spreadStore.enabled(book), plan.originals.count >= 2 else { return }
        if spreadStore.complete(book: book, revision: plan.revision) {
            scanStatusText = "本章识别完成，可手动修正"
            updateSettingsScanStatus()
            return
        }
        scanStatusText = "正在本机识别跨页，原页可继续阅读"
        updateSettingsScanStatus()
        let pairs = plan.originals.count - 1
        var order: [Int] = []
        var added = Set<Int>()
        for i in max(0, anchor - 8)..<min(pairs, anchor + 32) {
            order.append(i); added.insert(i)
        }
        for i in 0..<pairs where !added.contains(i) { order.append(i) }

        scanTask = Task { [weak self] in
            guard let self else { return }
            var decisions = self.spreadStore.automatic(book: book, revision: plan.revision)
            var checked = 0
            var failures = 0
            var lastPublished = decisions.count

            @MainActor func loadSample(_ url: String) async throws -> SpreadDetector.Sample? {
                let key = plan.revision + "\n" + url
                if let cached = self.spreadSamples[key] { return cached }
                let img = try await RemoteImageView.fetchDecodedImage(url: url, referer: referer, reader: true, maxPixelArea: 2_000_000, localPageImage: localLoader)
                try Task.checkCancellation()
                let sample = await Task.detached(priority: .utility) { () -> SpreadDetector.Sample? in
                    guard let pixels = SpreadBitmapComposer.extractPixels(from: img) else { return nil }
                    return SpreadDetector.Sample.read(pixels)
                }.value
                if let sample {
                    if self.spreadSamples.count >= 64, let firstKey = self.spreadSamples.keys.first {
                        self.spreadSamples.removeValue(forKey: firstKey)
                    }
                    self.spreadSamples[key] = sample
                }
                return sample
            }

            for idx in order {
                if Task.isCancelled || self.scanToken != token || !self.spreadStore.enabled(book) { return }
                do {
                    let a = try await loadSample(plan.originals[idx])
                    if Task.isCancelled || self.scanToken != token { return }
                    let b = try await loadSample(plan.originals[idx + 1])
                    if let a, let b {
                        let res = await Task.detached(priority: .utility) {
                            SpreadDetector.detect(a, b)
                        }.value
                        if res.merge {
                            decisions[idx] = SpreadPagePlan.Decision(
                                firstOnLeft: res.firstOnLeft,
                                score: res.firstOnLeft ? res.forward.score : res.reverse.score
                            )
                        } else {
                            decisions.removeValue(forKey: idx)
                        }
                    } else {
                        failures += 1
                    }
                } catch {
                    if Task.isCancelled || self.scanToken != token { return }
                    failures += 1
                }
                checked += 1
                let finished = checked == pairs
                self.scanStatusText = finished
                    ? (failures == 0 ? "本章识别完成，可手动修正" : "部分图片未能识别，可重新识别本章")
                    : "正在识别跨页 · \(checked) / \(pairs)"
                self.updateSettingsScanStatus()
                if finished || (checked % 16 == 0 && decisions.count != lastPublished) {
                    lastPublished = decisions.count
                    self.spreadStore.saveAutomatic(book: book, revision: plan.revision, decisions: decisions, complete: finished && failures == 0)
                    let nextPlan = SpreadPagePlan(
                        chapterIdentity: posKey,
                        originals: plan.originals,
                        enabled: true,
                        manual: self.spreadStore.manualRules(book: book, revision: plan.revision),
                        automatic: decisions
                    )
                    if let current = self.activeSpreadPlan(), nextPlan.displayKeys != current.displayKeys {
                        self.scheduleAutoPresentationRefresh(expectedBook: book, expectedChapterKey: posKey)
                    }
                }
            }
        }
    }

    @objc private func showSettings() {
        guard presentedViewController == nil else { return }
        savePosition()
        environment.readingHabits.userDidRead()
        environment.readingHabits.overlayVisibilityChanged(isVisible: true)
        let book = bookKey
        let spreadEnabled = spreadStore.enabled(book)
        let doublePageEnabled = doublePageStore.enabled(book)
        let autoScale = environment.defaults.bool(forKey: "reader.auto.scale.enabled")
        let scaleMode = ReaderScalePolicy.normalize(environment.defaults.integer(forKey: "reader.scale.mode"))
        let controller = ReaderSettingsViewController(
            store: environment.preferences,
            spreadEnabled: spreadEnabled,
            spreadStatus: currentSpreadStatusText(),
            doublePageEnabled: doublePageEnabled,
            doublePageStatus: currentDoublePageStatusText(),
            autoScaleEnabled: autoScale,
            scaleMode: scaleMode
        )
        activeSettingsSheet = controller
        controller.onChange = { [weak self] in self?.applySettings() }
        controller.onAutoScaleChanged = { [weak self] (enabled: Bool, mode: Int) in
            guard let self else { return }
            let normalized = ReaderScalePolicy.normalize(mode)
            self.environment.defaults.set(enabled, forKey: "reader.auto.scale.enabled")
            self.environment.defaults.set(normalized, forKey: "reader.scale.mode")
            let pos = self.currentPosition()
            self.pendingPosition = pos
            self.layout.invalidateLayout()
            self.pages.reloadData()
            self.view.setNeedsLayout()
        }
        controller.onSpreadEnabledChanged = { [weak self] (enabled: Bool) in
            guard let self else { return }
            self.savePosition()
            if enabled {
                self.doublePageStore.setEnabled(book, enabled: false)
                self.environment.defaults.set(false, forKey: "reader.double.page.enabled")
            }
            self.spreadStore.setEnabled(book, enabled: enabled)
            self.environment.defaults.set(enabled, forKey: "reader.spread.enabled")
            self.scanStatusText = nil
            self.reloadCurrentChapterPresentation()
            self.updateSettingsScanStatus()
        }
        controller.onSpreadActions = { [weak self] in
            self?.presentSpreadActionsSheet(bookKey: book)
        }
        controller.onDoublePageEnabledChanged = { [weak self] (enabled: Bool) in
            guard let self else { return }
            self.savePosition()
            if enabled {
                self.spreadStore.setEnabled(book, enabled: false)
                self.environment.defaults.set(false, forKey: "reader.spread.enabled")
            }
            self.doublePageStore.setEnabled(book, enabled: enabled)
            self.environment.defaults.set(enabled, forKey: "reader.double.page.enabled")
            self.scanStatusText = nil
            self.reloadCurrentChapterPresentation()
            self.updateSettingsScanStatus()
        }
        controller.onDoublePageActions = { [weak self] in
            self?.presentDoublePageActionsSheet(bookKey: book)
        }
        controller.onClose = { [weak self] in self?.closeSheet() }
        controller.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        present(controller, animated: true)
        controller.presentationController?.delegate = self
    }

    private func applySpreadRule(book: String, plan: SpreadPagePlan, index: Int, direction: Int?) {
        guard book == bookKey, spreadStore.enabled(book), activeSpreadPlan()?.revision == plan.revision else { return }
        savePosition()
        do {
            try spreadStore.setManual(book: book, revision: plan.revision, index: index, direction: direction)
            reloadCurrentChapterPresentation()
        } catch {
            showError(error)
        }
    }

    private func showSpreadPreview(book: String, plan: SpreadPagePlan, first: Int) {
        guard book == bookKey, spreadStore.enabled(book), activeSpreadPlan()?.revision == plan.revision else { return }
        guard first >= 0, first + 1 < plan.originals.count else { return }
        if plan.unit(plan.displayForSource(first))?.isSpread == true || plan.unit(plan.displayForSource(first + 1))?.isSpread == true {
            let alert = UIAlertController(title: nil, message: "相邻页面已属于跨页，请先拆开该组", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }
        let isDark = settings.theme == .dark || (settings.theme == .system && traitCollection.userInterfaceStyle == .dark)
        let preview = ReaderSpreadSheet.showPreview(from: self, dark: isDark, first: first)
        preview.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        var firstOnLeft = settings.pageDirection != .rightToLeft
        var loadRevision = 0
        var previewTask: Task<Void, Never>?
        let referer = source.referer
        let localLoader = localPageImage
        let urlA = plan.originals[first]
        let urlB = plan.originals[first + 1]

        let redraw: @MainActor () -> Void = { [weak self, weak preview] in
            guard let self, let preview else { return }
            loadRevision += 1
            let rev = loadRevision
            let leftFirst = firstOnLeft
            previewTask?.cancel()
            preview.loading(firstOnLeft: leftFirst)
            previewTask = Task { @MainActor [weak self, weak preview] in
                guard let self, let preview else { return }
                do {
                    async let imgA = RemoteImageView.fetchDecodedImage(url: urlA, referer: referer, reader: true, maxPixelArea: 4_000_000, localPageImage: localLoader)
                    async let imgB = RemoteImageView.fetchDecodedImage(url: urlB, referer: referer, reader: true, maxPixelArea: 4_000_000, localPageImage: localLoader)
                    let (a, b) = try await (imgA, imgB)
                    try Task.checkCancellation()
                    let composed = try await Task.detached(priority: .userInitiated) {
                        try SpreadBitmapComposer.compose(first: a, second: b, firstOnLeft: leftFirst, maxPixels: 2_500_000, maxBytes: 10 * 1024 * 1024)
                    }.value
                    guard rev == loadRevision, !Task.isCancelled else { return }
                    preview.loaded(composed.image)
                } catch {
                    guard rev == loadRevision, !Task.isCancelled else { return }
                    preview.failed()
                }
                _ = self
            }
        }
        preview.onSwap = {
            firstOnLeft.toggle()
            redraw()
        }
        preview.onRetry = {
            redraw()
        }
        preview.onConfirm = { [weak self] in
            self?.applySpreadRule(book: book, plan: plan, index: first, direction: firstOnLeft ? 1 : -1)
        }
        preview.onDismiss = {
            previewTask?.cancel()
            previewTask = nil
        }
        redraw()
    }

    private func presentSpreadActionsSheet(bookKey: String) {
        guard spreadStore.enabled(bookKey), let plan = activeSpreadPlan(), let unit = plan.unit(currentDisplayIndex()) else { return }
        let isDark = settings.theme == .dark || (settings.theme == .system && traitCollection.userInterfaceStyle == .dark)
        let finish: (@escaping () -> Void) -> Void = { [weak self] work in
            if let presented = self?.presentedViewController {
                presented.dismiss(animated: true, completion: work)
            } else {
                work()
            }
        }
        finish { [weak self] in
            guard let self else { return }
            var currentActions: [ReaderSpreadAction] = []
            if unit.isSpread {
                currentActions.append(ReaderSpreadAction(
                    title: "左右互换",
                    subtitle: "调整这两页的显示顺序",
                    parityIcon: .swap
                ) { [weak self] in
                    self?.applySpreadRule(book: bookKey, plan: plan, index: unit.first, direction: unit.firstOnLeft ? -1 : 1)
                })
                currentActions.append(ReaderSpreadAction(
                    title: "拆开，保持原页",
                    subtitle: "分别阅读原页 \(unit.first + 1) 和 \(unit.last + 1)",
                    parityIcon: .readerPage
                ) { [weak self] in
                    self?.applySpreadRule(book: bookKey, plan: plan, index: unit.first, direction: 0)
                })
                currentActions.append(ReaderSpreadAction(
                    title: "恢复这组自动判断",
                    subtitle: "移除这组的手动合并、拆开和顺序调整",
                    parityIcon: .automatic
                ) { [weak self] in
                    self?.applySpreadRule(book: bookKey, plan: plan, index: unit.first, direction: nil)
                })
            } else {
                if unit.first > 0 {
                    currentActions.append(ReaderSpreadAction(
                        title: "与前一页合并",
                        subtitle: "预览原页 \(unit.first)–\(unit.first + 1)",
                        parityIcon: .back
                    ) { [weak self] in
                        self?.showSpreadPreview(book: bookKey, plan: plan, first: unit.first - 1)
                    })
                }
                if unit.first + 1 < plan.originals.count {
                    currentActions.append(ReaderSpreadAction(
                        title: "与后一页合并",
                        subtitle: "预览原页 \(unit.first + 1)–\(unit.first + 2)",
                        icon: UIImage(systemName: "chevron.right")
                    ) { [weak self] in
                        self?.showSpreadPreview(book: bookKey, plan: plan, first: unit.first)
                    })
                }
                currentActions.append(ReaderSpreadAction(
                    title: "恢复此页附近自动判断",
                    subtitle: "移除当前页与相邻页的手动调整",
                    parityIcon: .automatic
                ) { [weak self] in
                    guard let self, self.activeSpreadPlan()?.revision == plan.revision else { return }
                    self.savePosition()
                    try? self.spreadStore.setManual(book: bookKey, revision: plan.revision, index: unit.first, direction: nil)
                    if unit.first > 0 {
                        try? self.spreadStore.setManual(book: bookKey, revision: plan.revision, index: unit.first - 1, direction: nil)
                    }
                    self.reloadCurrentChapterPresentation()
                })
            }

            let referer = self.source.referer
            let maintenance: [ReaderSpreadAction] = [
                ReaderSpreadAction(
                    title: "重试当前图片",
                    subtitle: "重新加载当前页的原始图片",
                    parityIcon: .history
                ) { [weak self] in
                    guard let self else { return }
                    RemoteImageView.removeCachedReaderImage(forKey: unit.key, referer: referer)
                    if let u1 = unit.firstUrl { RemoteImageView.removeCachedReaderImage(forKey: u1, referer: referer) }
                    if let u2 = unit.secondUrl { RemoteImageView.removeCachedReaderImage(forKey: u2, referer: referer) }
                    self.reloadCurrentChapterPresentation()
                },
                ReaderSpreadAction(
                    title: "重新识别本章",
                    subtitle: "重新检查接缝，保留人工修正",
                    parityIcon: .automatic
                ) { [weak self] in
                    guard let self else { return }
                    self.cancelScan()
                    self.spreadSamples.removeAll()
                    self.spreadStore.retry(book: bookKey, revision: plan.revision)
                    self.reloadCurrentChapterPresentation()
                },
                ReaderSpreadAction(
                    title: "清除本书人工修正",
                    subtitle: "移除本书的手动调整，采用自动识别结果",
                    parityIcon: .trash,
                    destructive: true
                ) { [weak self] in
                    guard let self else { return }
                    self.savePosition()
                    self.spreadStore.clearManual(book: bookKey)
                    self.reloadCurrentChapterPresentation()
                }
            ]

            let orderText = unit.firstOnLeft
                ? "\(unit.first + 1) 在左，\(unit.last + 1) 在右"
                : "\(unit.last + 1) 在左，\(unit.first + 1) 在右"
            let sheet = ReaderSpreadSheet.showActions(
                from: self,
                dark: isDark,
                pageLabel: unit.pageLabel(),
                spread: unit.isSpread,
                order: orderText,
                status: self.currentSpreadStatusText(),
                current: currentActions,
                maintenance: maintenance
            )
            sheet.overrideUserInterfaceStyle = self.overrideUserInterfaceStyle
        }
    }

    private func presentDoublePageActionsSheet(bookKey: String) {
        guard doublePageStore.enabled(bookKey),
              let presentation = activeSpreadPlan(),
              let doublePlan = activeDoublePagePlan() else { return }
        let displayIdx = currentDisplayIndex()
        guard let displayUnit = presentation.unit(displayIdx),
              let unit = doublePlan.unit(displayIdx) else { return }
        let isDark = settings.theme == .dark || (settings.theme == .system && traitCollection.userInterfaceStyle == .dark)
        let finish: (@escaping () -> Void) -> Void = { [weak self] work in
            if let presented = self?.presentedViewController {
                presented.dismiss(animated: true, completion: work)
            } else {
                work()
            }
        }
        finish { [weak self] in
            guard let self else { return }
            let rightFirst = doublePlan.rightFirst
            let sourceIdx = unit.source
            let currentActions: [ReaderSpreadAction] = [
                ReaderSpreadAction(
                    title: rightFirst ? "右页在前" : "左页在前",
                    subtitle: rightFirst ? "按本书记忆，点击切换为左页在前" : "按本书记忆，点击切换为右页在前",
                    parityIcon: .swap
                ) { [weak self] in
                    guard let self, self.activeDoublePagePlan()?.revision == doublePlan.revision else { return }
                    self.savePosition()
                    self.doublePageStore.setRightFirst(bookKey, rightFirst: !rightFirst)
                    self.reloadCurrentChapterPresentation()
                },
                ReaderSpreadAction(
                    title: unit.split ? "当前页保持整页" : "当前页强制切分",
                    subtitle: unit.split ? "取消当前页的左右切分，按原图显示" : "忽略自动判断，将当前原图切成左右两页",
                    parityIcon: unit.split ? .readerPage : .automatic
                ) { [weak self] in
                    guard let self, self.activeDoublePagePlan()?.revision == doublePlan.revision else { return }
                    self.savePosition()
                    try? self.doublePageStore.setManual(book: bookKey, revision: doublePlan.revision, index: sourceIdx, mode: unit.split ? -1 : 1)
                    self.reloadCurrentChapterPresentation()
                },
                ReaderSpreadAction(
                    title: "恢复当前页自动判断",
                    subtitle: "移除当前页的强制切分或保持整页设置",
                    parityIcon: .automatic
                ) { [weak self] in
                    guard let self, self.activeDoublePagePlan()?.revision == doublePlan.revision else { return }
                    self.savePosition()
                    try? self.doublePageStore.setManual(book: bookKey, revision: doublePlan.revision, index: sourceIdx, mode: nil)
                    self.reloadCurrentChapterPresentation()
                }
            ]

            let referer = self.source.referer
            let maintenance: [ReaderSpreadAction] = [
                ReaderSpreadAction(
                    title: "重试当前图片",
                    subtitle: "重新加载当前原图并切分显示",
                    parityIcon: .history
                ) { [weak self] in
                    guard let self else { return }
                    RemoteImageView.removeCachedReaderImage(forKey: displayUnit.key, referer: referer)
                    RemoteImageView.removeCachedReaderImage(forKey: unit.originalUrl, referer: referer)
                    self.reloadCurrentChapterPresentation()
                },
                ReaderSpreadAction(
                    title: "重新识别本章",
                    subtitle: "重新检查本章页面尺寸，保留人工修正",
                    parityIcon: .automatic
                ) { [weak self] in
                    guard let self else { return }
                    self.cancelScan()
                    self.doublePageSamples.removeAll()
                    self.doublePageStore.retry(book: bookKey, revision: doublePlan.revision)
                    self.reloadCurrentChapterPresentation()
                },
                ReaderSpreadAction(
                    title: "清除本书人工修正",
                    subtitle: "所有页面恢复为自动判断结果",
                    parityIcon: .trash,
                    destructive: true
                ) { [weak self] in
                    guard let self else { return }
                    self.savePosition()
                    self.doublePageStore.clearManual(book: bookKey)
                    self.reloadCurrentChapterPresentation()
                }
            ]

            let orderText = rightFirst ? "右页在前，左页在后" : "左页在前，右页在后"
            let summary = unit.split ? "已切分为左右两页 · \(orderText)" : "当前按原图整页显示 · \(orderText)"
            let sheet = ReaderSpreadSheet.showActions(
                from: self,
                dark: isDark,
                title: "自动切分双页",
                pageLabel: unit.pageLabel(),
                stateSummary: summary,
                status: self.currentDoublePageStatusText(),
                current: currentActions,
                maintenance: maintenance
            )
            sheet.overrideUserInterfaceStyle = self.overrideUserInterfaceStyle
        }
    }
    @objc private func closeSheet() {
        guard let controller = presentedViewController else { return }
        dismiss(animated: true) { [weak self] in self?.sheetDidDismiss(controller) }
    }

    private func sheetDidDismiss(_ controller: UIViewController) {
        if controller === activeSettingsSheet { activeSettingsSheet = nil }
        syncHabitOverlay()
        guard controller === downloadRepairController else { return }
        let repair = downloadRepairAction
        downloadRepairAction = nil; downloadRepairController = nil
        repair?()
    }
    @objc private func showDirectory() {
        guard presentedViewController == nil, chapters.indices.contains(session.chapterIndex) else { return }
        environment.readingHabits.userDidRead()
        environment.readingHabits.overlayVisibilityChanged(isVisible: true)
        let isDark = settings.theme == .dark || (settings.theme == .system && traitCollection.userInterfaceStyle == .dark)
        let drawer = ChapterDrawerSheet(
            chapters: chapters,
            currentChapterIndex: session.chapterIndex,
            hasCurrent: true,
            isReader: true,
            isDarkReader: isDark,
            isDesc: environment.defaults.bool(forKey: "chapter.desc"),
            onOrderChanged: { [weak self] descending in
                self?.environment.defaults.set(descending, forKey: "chapter.desc")
            }
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
        guard presentedViewController == nil else { return }
        savePosition()
        let previousComic = comic
        let previousChapters = chapters
        let previousChapterIndex = session.chapterIndex
        let previousIncomplete = incompleteDirectory
        let sheet = SourceSwitchSheet(comic: comic, environment: environment) { [weak self] targetDetail in
            guard let self else { return }
            self.applySwitchedSource(targetDetail: targetDetail)
        }
        sheet.onUndoSourceReplaced = { [weak self] _ in
            guard let self, let restoredSource = self.environment.source(for: previousComic) else { return }
            self.loadTask?.cancel(); self.directoryTask?.cancel(); self.directoryTask = nil
            self.cancelScan()
            self.cancelContinuation(); self.pendingPosition = nil; self.pendingPositionNeedsContinuation = false
            self.rawChapterURLs.removeAll(); self.spreadPlans.removeAll(); self.doublePagePlans.removeAll(); self.virtualUnits.removeAll()
            self.spreadSamples.removeAll(); self.doublePageSamples.removeAll(); self.scanStatusText = nil
            self.lastSaved = nil; self.sizes = [:]
            self.comic = previousComic
            self.source = restoredSource
            self.chapters = previousChapters
            self.incompleteDirectory = previousIncomplete
            let restoredIdx = previousChapters.indices.contains(previousChapterIndex) ? previousChapterIndex : 0
            self.session = ReaderSession(chapterCount: previousChapters.count, chapterIndex: restoredIdx)
            self.images = []
            self.lastObservedPosition = nil
            self.pagedAnchor = nil
            self.pages.reloadData()
            let fallbackDetail = ComicDetail(
                summary: previousComic,
                author: "",
                status: "",
                description: "",
                latestChapter: previousChapters.last?.title,
                chapters: previousChapters
            )
            self.onSourceChanged?(fallbackDetail)
            self.loadChapter(restoredIdx, atEnd: false, restoreSaved: true)
            self.updateMiddleButton()
        }
        let navigation = UINavigationController(rootViewController: sheet)
        navigation.navigationBar.tintColor = Palette.accent
        present(navigation, animated: true)
    }

    private func applySwitchedSource(targetDetail: ComicDetail) {
        guard let targetSource = environment.source(for: targetDetail.summary) else { return }
        let currentTitle = chapters.indices.contains(session.chapterIndex) ? chapters[session.chapterIndex].title : ""
        let currentIndex = session.chapterIndex
        let targetChapters = targetDetail.chapters
        guard !targetChapters.isEmpty else { return }

        let matchedIndex = ChapterMatching.findMatchingChapterIndex(
            chapters: targetChapters,
            currentTitle: currentTitle,
            defaultIndex: currentIndex
        )

        loadTask?.cancel(); directoryTask?.cancel(); directoryTask = nil
        cancelScan()
        cancelContinuation(); pendingPosition = nil; pendingPositionNeedsContinuation = false
        rawChapterURLs.removeAll(); spreadPlans.removeAll(); doublePagePlans.removeAll(); virtualUnits.removeAll()
        spreadSamples.removeAll(); doublePageSamples.removeAll(); scanStatusText = nil
        lastSaved = nil; sizes = [:]
        self.comic = targetDetail.summary
        self.source = targetSource
        self.chapters = targetChapters
        self.incompleteDirectory = false
        self.session = ReaderSession(chapterCount: targetChapters.count, chapterIndex: matchedIndex)
        self.images = []
        self.lastObservedPosition = nil
        self.pagedAnchor = nil
        self.pages.reloadData()
        self.onSourceChanged?(targetDetail)
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
        let autoScale = environment.defaults.bool(forKey: "reader.auto.scale.enabled")
        let scaleMode = ReaderScalePolicy.normalize(environment.defaults.integer(forKey: "reader.scale.mode"))
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
                if self.pendingPosition != nil { self.view.setNeedsLayout() }
            }
            self.scheduleSavePosition()
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
        cell.configure(
            url: url,
            virtualUnit: virtualUnits[url],
            referer: source.referer,
            settings: settings,
            autoScaleEnabled: autoScale,
            scaleMode: scaleMode,
            viewportHeight: max(1, collectionView.bounds.height),
            localPageImage: localPageImage
        )
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ReaderImageCell)?.cancel()
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = max(1, collectionView.bounds.width)
        let viewportHeight = max(1, collectionView.bounds.height)
        if settings.layout == .paged { return CGSize(width: width, height: viewportHeight) }
        let size = sizes[images[indexPath.item]] ?? CGSize(width: 3, height: 4)
        if environment.defaults.bool(forKey: "reader.auto.scale.enabled") {
            let mode = ReaderScalePolicy.normalize(environment.defaults.integer(forKey: "reader.scale.mode"))
            let screenScale = max(1, UIScreen.main.scale)
            let iw = size.width <= 4 ? Int(max(1, size.width * 100)) : Int(max(1, (size.width / screenScale).rounded()))
            let ih = size.height <= 4 ? Int(max(1, size.height * 100)) : Int(max(1, (size.height / screenScale).rounded()))
            let dims = ReaderScalePolicy.stripDimensions(
                enabled: true,
                mode: mode,
                viewportWidth: Int(width.rounded()),
                viewportHeight: Int(viewportHeight.rounded()),
                imageWidth: iw,
                imageHeight: ih
            )
            if dims.count >= 2, dims[0] > 0, dims[1] > 0 {
                return CGSize(width: width, height: CGFloat(dims[1]))
            }
        }
        return CGSize(width: width, height: max(1, width * size.height / max(1, size.width)))
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if restoring || pendingPosition != nil || !pageAnimating { recordReaderTrace("scroll") }
        guard !restoring, !viewportTransitioning else { return }
        if settings.layout == .strip { synchronizeContinuousSession() }
        else { session.updateImage(currentPosition().imageIndex) }
        updateBadge()
        readerSeekBar.configure(currentPage: session.imageIndex, total: session.imageCount, sessionToken: Int64(session.chapterIndex))
        appendNextChapterIfNeeded()
        updatePullPreviousChapterHint(scrollView)
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        noteUserInteraction()
        if pendingPositionNeedsContinuation {
            pendingPosition = nil; pendingPositionNeedsContinuation = false
            synchronizeContinuousSession()
        }
        pullStartedAtTop = settings.layout == .strip && !loading && (scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 4)
        pullReadyToRelease = false
        pullTargetChapterIndex = nil
        environment.readingHabits.userDidRead(); setFullscreen(true, animated: true)
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        hidePullHint(animated: true)
        savePosition()
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        pageAnimating = false; savePosition()
        recordReaderTrace("animation.end")
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let shouldTriggerPrevious = pullStartedAtTop && pullReadyToRelease
        let targetChapter = pullTargetChapterIndex
        pullStartedAtTop = false
        pullReadyToRelease = false
        pullTargetChapterIndex = nil
        hidePullHint(animated: true)
        if shouldTriggerPrevious, let targetChapter, chapters.indices.contains(targetChapter), !loading {
            savePosition()
            loadChapter(targetChapter, atEnd: false, restoreSaved: false)
            return
        }
        if !decelerate { savePosition() }
    }
    private func topLoadedChapterIndex() -> Int {
        if let firstSeg = continuousPages.segments.first,
           let idx = chapters.firstIndex(where: { $0.chapterId == firstSeg.chapter.chapterId }) {
            return idx
        }
        return session.chapterIndex
    }
    private func updatePullPreviousChapterHint(_ scrollView: UIScrollView) {
        guard scrollView.isDragging, settings.layout == .strip, !loading, pullStartedAtTop else {
            if !scrollView.isDragging { hidePullHint(animated: true) }
            return
        }
        let pullDistance = -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        if pullDistance < -6 {
            pullStartedAtTop = false
            pullReadyToRelease = false
            pullTargetChapterIndex = nil
            hidePullHint(animated: false)
            return
        }
        let topIdx = topLoadedChapterIndex()
        var hintText: String?
        var ready = false
        if topIdx > 0 {
            if pullDistance >= 68 {
                hintText = "松手加载上一章"
                ready = true
                pullTargetChapterIndex = topIdx - 1
            } else if pullDistance >= 20 {
                hintText = "继续下拉加载上一章"
                pullTargetChapterIndex = topIdx - 1
            } else {
                pullTargetChapterIndex = nil
            }
        } else if pullDistance >= 36 {
            hintText = "已经是第一章"
            pullTargetChapterIndex = nil
        }
        pullReadyToRelease = ready
        guard let hintText else {
            hidePullHint(animated: true)
            return
        }
        let isDark = overrideUserInterfaceStyle == .dark
        pullHintLabel.applyStyle(text: hintText, isDark: isDark, ready: ready)
        pullHintLabel.isHidden = false
        pullHintLabel.alpha = 1
        let ty = min(18, max(0, (pullDistance - 20) * 0.25))
        pullHintLabel.transform = CGAffineTransform(translationX: 0, y: ty)
    }
    private func hidePullHint(animated: Bool) {
        guard !pullHintLabel.isHidden else { return }
        if animated {
            UIView.animate(withDuration: 0.16, animations: {
                self.pullHintLabel.alpha = 0
                self.pullHintLabel.transform = .identity
            }, completion: { _ in
                if self.pullHintLabel.alpha < 0.05 {
                    self.pullHintLabel.isHidden = true
                }
            })
        } else {
            pullHintLabel.alpha = 0
            pullHintLabel.transform = .identity
            pullHintLabel.isHidden = true
        }
    }
}

@MainActor
private final class ReaderPullHintLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 12, weight: .semibold)
        textAlignment = .center
        layer.cornerRadius = 17
        layer.borderWidth = 1
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(width: base.width + 28, height: max(34, base.height + 12))
    }
    func applyStyle(text: String, isDark: Bool, ready: Bool) {
        self.text = text
        if ready {
            backgroundColor = isDark
                ? UIColor(red: 22/255, green: 54/255, blue: 83/255, alpha: 0.96)
                : UIColor(red: 234/255, green: 244/255, blue: 255/255, alpha: 0.96)
            layer.borderColor = UIColor(red: 64/255, green: 153/255, blue: 237/255, alpha: 1).cgColor
            textColor = isDark
                ? UIColor(red: 140/255, green: 203/255, blue: 255/255, alpha: 1)
                : UIColor(red: 9/255, green: 105/255, blue: 218/255, alpha: 1)
        } else {
            backgroundColor = isDark
                ? UIColor(red: 28/255, green: 33/255, blue: 40/255, alpha: 0.94)
                : UIColor(white: 1.0, alpha: 0.95)
            layer.borderColor = isDark
                ? UIColor(red: 68/255, green: 76/255, blue: 86/255, alpha: 1).cgColor
                : UIColor(red: 208/255, green: 215/255, blue: 222/255, alpha: 1).cgColor
            textColor = isDark
                ? UIColor(red: 230/255, green: 237/255, blue: 243/255, alpha: 1)
                : UIColor(red: 31/255, green: 35/255, blue: 40/255, alpha: 1)
        }
    }
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
    private var virtualUnit: SpreadPagePlan.Unit?
    private var virtualTask: Task<Void, Never>?
    private var virtualToken = UUID()
    private var localPageImage: (@Sendable (URL) throws -> Data)?
    private var rawImage: UIImage?
    private var enhancedImage: UIImage?
    private var isComparing = false
    private var currentMode = 0
    private var comparisonEnabled = false
    private var isStripLayout = true
    private var autoScaleEnabled = false
    private var scaleMode = ReaderScalePolicy.SMART
    private var readerViewportHeight: CGFloat = 1
    private(set) var isFailed = false
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
        scroll.alwaysBounceVertical = false
        scroll.alwaysBounceHorizontal = false
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
            self.isFailed = false
            self.retry.isHidden = true
            if let raw = self.image.image { self.displayLoadedImage(raw) }
            self.applyGeometryLayout()
            let callback = self.onSize
            DispatchQueue.main.async { callback?(size) }
        }
        image.onFailure = { [weak self] in
            guard let self else { return }
            self.isFailed = true
            self.retry.isHidden = false
            self.retry.setTitle("图片加载失败 · 点击重试", for: .normal)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func canPanHorizontally(dx: CGFloat) -> Bool {
        guard scroll.contentSize.width > scroll.bounds.width + 1 else { return false }
        if dx > 0 {
            return scroll.contentOffset.x > 1
        }
        if dx < 0 {
            return scroll.contentOffset.x < scroll.contentSize.width - scroll.bounds.width - 1
        }
        return false
    }

    func retryIfFailed() -> Bool {
        guard isFailed else { return false }
        reload()
        return true
    }

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
        var base = "\(method):\(pixels?.width ?? 0)x\(pixels?.height ?? 0)"
        if let unit = virtualUnit {
            if unit.isSpread {
                base += ";spread=\(unit.pageLabel())"
            } else if unit.isDoublePage {
                base += ";double=\(unit.pageLabel())"
            }
        }
        image.accessibilityValue = base
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

    private func applyGeometryLayout() {
        guard scroll.zoomScale == 1, scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
        guard autoScaleEnabled, let displayed = image.image, displayed.size.width > 0, displayed.size.height > 0 else {
            image.contentMode = .scaleAspectFit
            image.frame = scroll.bounds
            scroll.contentSize = scroll.bounds.size
            scroll.isScrollEnabled = !isStripLayout
            return
        }
        let screenScale = max(1, UIScreen.main.scale)
        let pixelW = CGFloat(displayed.cgImage?.width ?? Int(displayed.size.width * displayed.scale))
        let pixelH = CGFloat(displayed.cgImage?.height ?? Int(displayed.size.height * displayed.scale))
        let iw = max(1, Int((pixelW / screenScale).rounded()))
        let ih = max(1, Int((pixelH / screenScale).rounded()))
        let vw = max(1, Int(scroll.bounds.width.rounded()))
        let vh = max(1, Int((isStripLayout ? readerViewportHeight : scroll.bounds.height).rounded()))
        let g = ReaderScalePolicy.geometry(
            enabled: true,
            mode: scaleMode,
            scroll: isStripLayout,
            imageWidth: iw,
            imageHeight: ih,
            viewportWidth: vw,
            viewportHeight: vh
        )
        let targetW = max(1, CGFloat(g.width))
        let targetH = max(1, CGFloat(g.height))
        let x = max(0, CGFloat(g.left))
        let y = isStripLayout ? 0 : max(0, CGFloat(g.top))
        image.contentMode = .scaleToFill
        image.frame = CGRect(x: x, y: y, width: targetW, height: targetH)
        let contentW = max(scroll.bounds.width, x + targetW)
        let contentH = isStripLayout ? scroll.bounds.height : max(scroll.bounds.height, y + targetH)
        scroll.contentSize = CGSize(width: contentW, height: contentH)
        scroll.isScrollEnabled = !isStripLayout || contentW > scroll.bounds.width + 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = contentView.bounds
        applyGeometryLayout()
        retry.frame = CGRect(x: 0, y: max(0, bounds.midY - 22), width: bounds.width, height: 44)
    }

    func configure(
        url: String,
        virtualUnit: SpreadPagePlan.Unit? = nil,
        referer: String,
        settings: ReaderPreferences,
        autoScaleEnabled: Bool = false,
        scaleMode: Int = ReaderScalePolicy.SMART,
        viewportHeight: CGFloat = 1,
        localPageImage: (@Sendable (URL) throws -> Data)? = nil
    ) {
        stopEnhancement()
        virtualToken = UUID()
        virtualTask?.cancel()
        virtualTask = nil
        rawImage = nil
        isFailed = false
        self.url = url
        self.virtualUnit = virtualUnit
        self.referer = referer
        self.localPageImage = localPageImage
        self.currentMode = settings.enhancementMode
        self.comparisonEnabled = settings.enhancementComparison
        self.isStripLayout = settings.layout == .strip
        self.autoScaleEnabled = autoScaleEnabled
        self.scaleMode = ReaderScalePolicy.normalize(scaleMode)
        self.readerViewportHeight = max(1, viewportHeight)
        scroll.setZoomScale(1, animated: false)
        scroll.contentOffset = .zero
        apply(settings)
        reload()
    }

    func apply(_ settings: ReaderPreferences) {
        let changedMode = currentMode != settings.enhancementMode
        if changedMode { stopEnhancement() }
        self.currentMode = settings.enhancementMode
        self.comparisonEnabled = settings.enhancementComparison
        self.isStripLayout = settings.layout == .strip
        setZoomEnabled(settings.pinchZoom)
        image.setReaderEffects(crop: settings.cropWhiteMargins, vertical: settings.layout == .paged, ink: settings.inkScreen)
        applyGeometryLayout()
        if changedMode, let raw = rawImage { displayLoadedImage(raw) }
    }

    func setZoomEnabled(_ enabled: Bool) {
        if !enabled { scroll.setZoomScale(1, animated: false) }
        scroll.maximumZoomScale = enabled ? 4 : 1
    }

    func toggleZoom() { scroll.setZoomScale(scroll.zoomScale > 1.05 ? 1 : min(2, scroll.maximumZoomScale), animated: true) }

    @objc private func reload() {
        isFailed = false
        retry.isHidden = false
        retry.setTitle("正在加载图片…", for: .normal)
        virtualToken = UUID()
        virtualTask?.cancel()
        virtualTask = nil

        guard let unit = virtualUnit, unit.isSpread || unit.isDoublePage else {
            image.load(url, referer: referer, reader: true, localPageImage: localPageImage)
            return
        }

        image.prepareForVirtualReaderLoad()
        if let cached = RemoteImageView.cachedReaderImage(forKey: unit.key) {
            image.displayPreloadedReaderImage(cached)
            return
        }

        let token = virtualToken
        let ref = referer
        let localLoader = localPageImage
        virtualTask = Task { [weak self] in
            do {
                let composedImage: UIImage
                if unit.isSpread {
                    guard let u1 = unit.firstUrl, let u2 = unit.secondUrl else {
                        throw SpreadBitmapError.imageNotLoaded("跨页地址无效")
                    }
                    async let imgA = RemoteImageView.fetchDecodedImage(url: u1, referer: ref, reader: true, maxPixelArea: 8_000_000, localPageImage: localLoader)
                    async let imgB = RemoteImageView.fetchDecodedImage(url: u2, referer: ref, reader: true, maxPixelArea: 8_000_000, localPageImage: localLoader)
                    let (a, b) = try await (imgA, imgB)
                    try Task.checkCancellation()
                    composedImage = try await Task.detached(priority: .userInitiated) {
                        try SpreadBitmapComposer.compose(first: a, second: b, firstOnLeft: unit.firstOnLeft).image
                    }.value
                } else {
                    guard let origURL = unit.doubleOriginalUrl else {
                        throw SpreadBitmapError.imageNotLoaded("双页原图地址无效")
                    }
                    let whole = try await RemoteImageView.fetchDecodedImage(url: origURL, referer: ref, reader: true, localPageImage: localLoader)
                    try Task.checkCancellation()
                    composedImage = try await Task.detached(priority: .userInitiated) {
                        try SpreadBitmapComposer.cropDoublePage(image: whole, leftHalf: unit.doubleLeftHalf)
                    }.value
                }
                try Task.checkCancellation()
                guard let self, self.virtualToken == token else { return }
                RemoteImageView.cacheReaderImage(composedImage, forKey: unit.key)
                self.image.displayPreloadedReaderImage(composedImage)
            } catch {
                guard let self, self.virtualToken == token, !Task.isCancelled else { return }
                self.image.onFailure?()
            }
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { onZoom?(scrollView.zoomScale > 1.05) }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { onUserAction?() }
    func cancel() {
        virtualToken = UUID()
        virtualTask?.cancel()
        virtualTask = nil
        stopEnhancement()
        image.cancel()
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        cancel()
        virtualUnit = nil
        localPageImage = nil
        onSize = nil
        onZoom = nil
        onUserAction = nil
        onComparing = nil
        onEnhancement = nil
        rawImage = nil
        enhancedImage = nil
        isComparing = false
        isFailed = false
        #if DEBUG
        comparisonEvents.removeAll()
        #endif
        scroll.setZoomScale(1, animated: false)
        scroll.contentOffset = .zero
    }
}
