import UIKit
import WebKit
import ZIPFoundation
import ComicCore

/// Streaming text & mixed EPUB reader aligned with Android 2.0.55 `TextReaderView` & `TextReaderSettingsSheet`.
/// Uses `WKWebView` + custom `WKURLSchemeHandler` (`xxcomic-epub-text://`) to stream HTML/CSS/images directly
/// from the EPUB archive without extracting whole books onto disk, with strict path normalization and origin isolation.
@MainActor
final class TextReaderViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {

    enum ReaderThemeMode: Int, CaseIterable {
        case light = 0
        case sepia = 1
        case dark = 2
        case ink = 3

        var title: String {
            switch self {
            case .light: return "浅白"
            case .sepia: return "护眼"
            case .dark: return "夜空"
            case .ink: return "墨水屏"
            }
        }

        var backgroundColor: UIColor {
            switch self {
            case .light: return UIColor(red: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xFA / 255.0, alpha: 1)
            case .sepia: return UIColor(red: 0xF5 / 255.0, green: 0xEE / 255.0, blue: 0xDB / 255.0, alpha: 1)
            case .dark: return UIColor(red: 0x12 / 255.0, green: 0x16 / 255.0, blue: 0x1F / 255.0, alpha: 1)
            case .ink: return .white
            }
        }

        var panelBackgroundColor: UIColor {
            switch self {
            case .light: return .white
            case .sepia: return UIColor(red: 0xF5 / 255.0, green: 0xEC / 255.0, blue: 0xD7 / 255.0, alpha: 1)
            case .dark: return UIColor(red: 0x1A / 255.0, green: 0x1D / 255.0, blue: 0x24 / 255.0, alpha: 1)
            case .ink: return .white
            }
        }

        var cssBackgroundHex: String {
            switch self {
            case .light: return "#FAFAFA"
            case .sepia: return "#F5EEDB"
            case .dark: return "#12161F"
            case .ink: return "#FFFFFF"
            }
        }

        var cssTextHex: String {
            switch self {
            case .light: return "#23272E"
            case .sepia: return "#3F3222"
            case .dark: return "#C8D0E0"
            case .ink: return "#000000"
            }
        }

        var cssAccentHex: String {
            switch self {
            case .light: return "#4C78A8"
            case .sepia: return "#8C6239"
            case .dark: return "#5E81AC"
            case .ink: return "#000000"
            }
        }

        var isDarkAppearance: Bool {
            self == .dark
        }
    }

    struct Settings: Equatable {
        var fontSize: Int = 18
        var lineHeight: Double = 1.75
        var theme: ReaderThemeMode = .dark
        var pagedMode: Bool = false

        private static let keyFontSize = "text_reader.font_size_sp"
        private static let keyLineHeight = "text_reader.line_height"
        private static let keyTheme = "text_reader.reader_theme"
        private static let keyPagedMode = "text_reader.paged_mode"

        static func load(from defaults: UserDefaults, fallbackPrefs: ReaderPreferences? = nil) -> Settings {
            let fontRaw = defaults.object(forKey: keyFontSize) as? Int ?? 18
            let lineRaw = defaults.object(forKey: keyLineHeight) as? Double ?? 1.75
            let theme: ReaderThemeMode
            if let rawTheme = defaults.object(forKey: keyTheme) as? Int,
               let parsed = ReaderThemeMode(rawValue: rawTheme) {
                theme = parsed
            } else if let prefs = fallbackPrefs {
                if prefs.inkScreen {
                    theme = .ink
                } else {
                    switch prefs.theme {
                    case .light: theme = .light
                    case .dark: theme = .dark
                    case .system:
                        theme = UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
                    }
                }
            } else {
                theme = .dark
            }
            let paged = defaults.bool(forKey: keyPagedMode)
            return Settings(
                fontSize: max(12, min(32, fontRaw)),
                lineHeight: max(1.2, min(2.5, lineRaw)),
                theme: theme,
                pagedMode: paged
            )
        }

        func save(to defaults: UserDefaults) {
            defaults.set(max(12, min(32, fontSize)), forKey: Self.keyFontSize)
            defaults.set(max(1.2, min(2.5, lineHeight)), forKey: Self.keyLineHeight)
            defaults.set(theme.rawValue, forKey: Self.keyTheme)
            defaults.set(pagedMode, forKey: Self.keyPagedMode)
        }
    }

    // MARK: - Constants & Resource Streaming

    nonisolated static let urlScheme = "xxcomic-epub-text"
    nonisolated static let urlHost = "epub.local"
    nonisolated static let maxResourceBytes = 16 * 1024 * 1024

    enum Backend {
        case localLibrary(library: LocalLibrary, bookID: String, initialBook: LocalBook?)
        case directArchive(epubURL: URL)
    }

    private struct ChapterSourceSpec {
        let index: Int
        let chapter: Chapter
        let volumeBookID: String
        let publication: EpubPublication
        let spineEntryPaths: [String]
        let primarySpineIndex: Int
    }

    struct SpineSource {
        let entryPath: String
        let rawHtml: String
    }

    struct PreparedSpine {
        let entryPath: String
        let entryPaths: [String]
        let html: String
    }

    // MARK: - Properties

    private let comic: ComicSummary
    private var chapters: [Chapter]
    private var currentChapterIndex: Int
    private let backend: Backend
    private let defaults: UserDefaults
    private let libraryStore: LibraryStore?
    private let readingHabits: ReadingHabitTracker?

    private var settings: Settings
    private var loadGeneration: Int = 0
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var activeBookID: String
    private var activePublication: EpubPublication?
    private var loadedEntryPaths: [String] = []
    private var currentSpineIndex: Int = 0
    private var currentEntryPath: String = ""
    private var currentScrollPercent: Double = 0
    private var pendingRestoreLocator: TextLocator?
    private var hasLoadedHtml = false
    private var fullscreen = false
    private var isReleased = false

    private let schemeHandler: EpubSchemeHandler
    private let userContentController = WKUserContentController()
    private let webView: WKWebView

    private let topChrome = ReaderChromeGradientView(edge: .top)
    private let bottomChrome = ReaderChromeGradientView(edge: .bottom)
    private let toolbar = UIStackView()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let seekBar = ReaderSeekBar()
    private let tocButton = UIButton(type: .system)
    private let detailButton = UIButton(type: .system)
    private let typographyButton = UIButton(type: .system)
    private let themeButton = UIButton(type: .system)
    private let statusBadge = ReaderOverlayBadge()
    private let chapterProgress = UIProgressView(progressViewStyle: .bar)
    private let headerHeading = UILabel()
    private var headerWidthConstraint: NSLayoutConstraint?

    private let stateOverlay = UIView()
    private let badgeTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()
    private var oldInteractivePopEnabled: Bool?
    private var oldNavigationStyle: UIUserInterfaceStyle = .unspecified

    // MARK: - Initializers

    init(
        comic: ComicSummary,
        chapters: [Chapter],
        chapterIndex: Int,
        environment: AppEnvironment,
        initialBook: LocalBook? = nil
    ) {
        self.comic = comic
        self.chapters = chapters
        self.currentChapterIndex = max(0, min(max(0, chapters.count - 1), chapterIndex))
        self.backend = .localLibrary(library: environment.localLibrary, bookID: comic.comicId, initialBook: initialBook)
        self.defaults = environment.defaults
        self.libraryStore = environment.library
        self.readingHabits = environment.readingHabits
        self.activeBookID = initialBook?.id ?? comic.comicId
        self.activePublication = initialBook?.epub
        self.settings = Settings.load(from: environment.defaults, fallbackPrefs: environment.preferences.load())
        self.schemeHandler = EpubSchemeHandler(backend: .localLibrary(library: environment.localLibrary, bookID: comic.comicId, initialBook: initialBook))

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.setURLSchemeHandler(schemeHandler, forURLScheme: Self.urlScheme)
        config.userContentController = userContentController
        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    init(
        epubURL: URL,
        title: String? = nil,
        chapterIndex: Int = 0,
        environment: AppEnvironment? = nil,
        defaults: UserDefaults = .standard
    ) {
        let resolvedDefaults = environment?.defaults ?? defaults
        let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? title!.trimmingCharacters(in: .whitespacesAndNewlines)
            : epubURL.deletingPathExtension().lastPathComponent
        let bookID = "direct:" + epubURL.lastPathComponent
        self.comic = ComicSummary(sourceId: "local", comicId: bookID, title: resolvedTitle, coverUrl: "", subtitle: "EPUB")
        self.chapters = []
        self.currentChapterIndex = max(0, chapterIndex)
        self.backend = .directArchive(epubURL: epubURL)
        self.defaults = resolvedDefaults
        self.libraryStore = environment?.library
        self.readingHabits = environment?.readingHabits
        self.activeBookID = bookID
        self.activePublication = nil
        self.settings = Settings.load(from: resolvedDefaults, fallbackPrefs: environment?.preferences.load())
        self.schemeHandler = EpubSchemeHandler(backend: .directArchive(epubURL: epubURL))

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.setURLSchemeHandler(schemeHandler, forURLScheme: Self.urlScheme)
        config.userContentController = userContentController
        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    deinit {
        loadTask?.cancel()
        saveTask?.cancel()
        schemeHandler.stopAll()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle {
        settings.theme.isDarkAppearance ? .lightContent : .darkContent
    }
    override var prefersHomeIndicatorAutoHidden: Bool { fullscreen }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationChrome()
        setupWebView()
        setupChromeViews()
        applyThemeAppearance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        readingHabits?.enterReader(comicID: comic.comicId, isLocal: true)
        loadCurrentChapter(restoreSavedLocator: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if oldInteractivePopEnabled == nil {
            oldInteractivePopEnabled = navigationController?.interactivePopGestureRecognizer?.isEnabled
        }
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        oldNavigationStyle = navigationController?.overrideUserInterfaceStyle ?? .unspecified
        applyThemeAppearance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flushPositionSave()
        if isMovingFromParent || parent?.isMovingFromParent == true {
            cleanupReaderResources()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let hostWidth = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 32
        headerWidthConstraint?.constant = max(44, hostWidth)
        if hasLoadedHtml {
            applyLiveDocumentStyle()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let savedPct = currentScrollPercent
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self, !self.isReleased, self.hasLoadedHtml else { return }
            self.applyLiveDocumentStyle()
            if savedPct > 0.005 {
                self.scrollToPercent(savedPct)
            }
        }
    }

    private func cleanupReaderResources() {
        guard !isReleased else { return }
        isReleased = true
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        saveTask?.cancel()
        saveTask = nil
        schemeHandler.stopAll()
        userContentController.removeScriptMessageHandler(forName: "TextBridge")
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
        if let oldPop = oldInteractivePopEnabled {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = oldPop
            oldInteractivePopEnabled = nil
        }
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationController?.overrideUserInterfaceStyle = oldNavigationStyle
        readingHabits?.exitReader()
    }

    @objc private func handleWillResignActive() {
        flushPositionSave()
    }

    // MARK: - Navigation & Chrome Setup

    private func hostNavigationItem() -> UINavigationItem {
        parent?.navigationItem ?? navigationItem
    }

    private func hostNavigationController() -> UINavigationController? {
        parent?.navigationController ?? navigationController
    }

    private func configureNavigationChrome() {
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true

        let navItem = hostNavigationItem()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navItem.standardAppearance = appearance
        navItem.scrollEdgeAppearance = appearance
        navItem.compactAppearance = appearance

        let back = UIButton(type: .system)
        back.setImage(ParityIcon.back.image(size: 20), for: .normal)
        back.tintColor = .label
        back.accessibilityIdentifier = "reader.back"
        back.accessibilityLabel = "返回"
        back.addTarget(self, action: #selector(returnToPrevious), for: .touchUpInside)
        back.widthAnchor.constraint(equalToConstant: 44).isActive = true
        back.heightAnchor.constraint(equalToConstant: 44).isActive = true

        headerHeading.font = .systemFont(ofSize: 13, weight: .medium)
        headerHeading.textColor = .label
        headerHeading.lineBreakMode = .byTruncatingTail
        headerHeading.accessibilityIdentifier = "reader.title"

        let header = UIStackView(arrangedSubviews: [back, headerHeading])
        header.alignment = .center
        header.spacing = 0
        header.translatesAutoresizingMaskIntoConstraints = false
        let widthC = header.widthAnchor.constraint(equalToConstant: 260)
        widthC.isActive = true
        headerWidthConstraint = widthC

        navItem.leftBarButtonItem = UIBarButtonItem(customView: header)
        navItem.titleView = UIView(frame: .zero)
    }

    private func setupWebView() {
        let userScript = WKUserScript(source: Self.bridgeScriptSource(), injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(userScript)
        userContentController.add(WeakScriptMessageHandler(delegate: self), name: "TextBridge")

        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = settings.theme.backgroundColor
        webView.scrollView.backgroundColor = settings.theme.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.bounces = true
        webView.accessibilityIdentifier = "text.reader.webview"
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupChromeViews() {
        stateOverlay.isHidden = true
        stateOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stateOverlay)

        toolbar.axis = .vertical
        toolbar.spacing = 0
        toolbar.accessibilityIdentifier = "reader.toolbar"

        // Row 1: Prev Chapter | SeekBar | Next Chapter
        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.alignment = .center
        row1.spacing = 10
        row1.isLayoutMarginsRelativeArrangement = true
        row1.layoutMargins = UIEdgeInsets(top: 2, left: 12, bottom: 0, right: 12)
        row1.heightAnchor.constraint(equalToConstant: 42).isActive = true

        previousButton.setTitle("上一章", for: .normal)
        previousButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        previousButton.tintColor = .label
        previousButton.accessibilityIdentifier = "reader.previous.chapter"
        previousButton.addTarget(self, action: #selector(previousChapterTapped), for: .touchUpInside)

        nextButton.setTitle("下一章", for: .normal)
        nextButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        nextButton.tintColor = .label
        nextButton.accessibilityIdentifier = "reader.next.chapter"
        nextButton.addTarget(self, action: #selector(nextChapterTapped), for: .touchUpInside)

        seekBar.onCommit = { [weak self] pct in
            guard let self else { return }
            self.readingHabits?.userDidRead()
            let fraction = Double(max(0, min(100, pct))) / 100.0
            self.currentScrollPercent = fraction
            self.scrollToPercent(fraction)
            self.recordScrollPosition(percent: fraction)
        }

        row1.addArrangedSubview(previousButton)
        row1.addArrangedSubview(seekBar)
        row1.addArrangedSubview(nextButton)
        previousButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        nextButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        previousButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        nextButton.heightAnchor.constraint(equalToConstant: 40).isActive = true

        // Row 2: 目录 | 详情 | 排版 | 主题
        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.distribution = .fillEqually
        row2.heightAnchor.constraint(equalToConstant: 46).isActive = true
        row2.isLayoutMarginsRelativeArrangement = true
        row2.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        configureToolbarButton(tocButton, title: "目录", icon: .chapterList, id: "reader.directory")
        tocButton.addTarget(self, action: #selector(showDirectoryTapped), for: .touchUpInside)

        configureToolbarButton(detailButton, title: "详情", icon: .detail, id: "text.reader.detail")
        detailButton.addTarget(self, action: #selector(returnToPrevious), for: .touchUpInside)

        configureToolbarButton(typographyButton, title: "排版", icon: .settings, id: "text.reader.settings")
        typographyButton.addTarget(self, action: #selector(showTypographySettingsTapped), for: .touchUpInside)

        configureToolbarButton(themeButton, title: "主题", icon: .moon, id: "text.reader.theme.cycle")
        themeButton.addTarget(self, action: #selector(cycleThemeTapped), for: .touchUpInside)

        [tocButton, detailButton, typographyButton, themeButton].forEach { row2.addArrangedSubview($0) }
        toolbar.addArrangedSubview(row1)
        toolbar.addArrangedSubview(row2)

        chapterProgress.isHidden = true
        chapterProgress.trackTintColor = .clear
        chapterProgress.progressTintColor = .systemBlue

        statusBadge.textAlignment = .right
        statusBadge.isHidden = true

        for v in [stateOverlay, topChrome, bottomChrome, toolbar, chapterProgress, statusBadge] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        NSLayoutConstraint.activate([
            stateOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            stateOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stateOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stateOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 88),

            topChrome.topAnchor.constraint(equalTo: view.topAnchor),
            topChrome.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            bottomChrome.topAnchor.constraint(equalTo: toolbar.topAnchor),
            bottomChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            chapterProgress.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            chapterProgress.heightAnchor.constraint(equalToConstant: 2),
            chapterProgress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chapterProgress.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            statusBadge.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            statusBadge.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            statusBadge.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
    }

    private func configureToolbarButton(_ button: UIButton, title: String, icon: ParityIcon, id: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = icon.image(size: 20)
        config.imagePlacement = .top
        config.imagePadding = 2
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var out = attrs
            out.font = .systemFont(ofSize: 11, weight: .medium)
            return out
        }
        button.configuration = config
        button.accessibilityLabel = title
        button.accessibilityIdentifier = id
    }

    // MARK: - Chapter Resolution & Streaming Load

    private func loadCurrentChapter(restoreSavedLocator: Bool) {
        guard !isReleased else { return }
        loadGeneration += 1
        let gen = loadGeneration
        loadTask?.cancel()

        let requestedIdx = currentChapterIndex
        let savedLocator: TextLocator? = restoreSavedLocator ? restoredLocator(forChapterIndex: requestedIdx) : nil
        pendingRestoreLocator = savedLocator
        currentScrollPercent = savedLocator?.scrollPercentage ?? 0

        showLoadingState("正在加载章节…")
        updateChapterNavButtons()

        let backendCopy = backend
        let chaptersCopy = chapters
        let comicTitle = comic.title

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (spec, resolvedChapters) = try await Task.detached(priority: .userInitiated) {
                    try await Self.resolveChapterSpec(
                        backend: backendCopy,
                        chapters: chaptersCopy,
                        requestedChapterIndex: requestedIdx,
                        fallbackTitle: comicTitle
                    )
                }.value
                try Task.checkCancellation()
                guard !self.isReleased, gen == self.loadGeneration else { return }

                if !resolvedChapters.isEmpty {
                    self.chapters = resolvedChapters
                }
                self.currentChapterIndex = spec.index
                self.activeBookID = spec.volumeBookID
                self.activePublication = spec.publication
                self.schemeHandler.updateActiveBookID(spec.volumeBookID)

                let css = self.generateCssBlock()
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try Self.prepareChapterHtml(
                        backend: backendCopy,
                        bookID: spec.volumeBookID,
                        spineEntryPaths: spec.spineEntryPaths,
                        cssBlock: css
                    )
                }.value
                try Task.checkCancellation()
                guard !self.isReleased, gen == self.loadGeneration else { return }

                self.currentSpineIndex = spec.primarySpineIndex
                self.currentEntryPath = prepared.entryPath
                self.loadedEntryPaths = prepared.entryPaths
                self.hasLoadedHtml = true
                self.hideStateOverlay()
                self.updateHeaderAndProgressUI()

                let baseURL = URL(string: "\(Self.urlScheme)://\(Self.urlHost)/\(Self.percentEncodePath(prepared.entryPath))")
                self.webView.loadHTMLString(prepared.html, baseURL: baseURL)
                self.readingHabits?.contentBecameReadable()
            } catch is CancellationError {
                return
            } catch {
                guard !self.isReleased, gen == self.loadGeneration else { return }
                self.showErrorState(error.localizedDescription) { [weak self] in
                    self?.loadCurrentChapter(restoreSavedLocator: restoreSavedLocator)
                }
            }
        }
    }

    nonisolated private static func resolveChapterSpec(
        backend: Backend,
        chapters: [Chapter],
        requestedChapterIndex: Int,
        fallbackTitle: String
    ) async throws -> (ChapterSourceSpec, [Chapter]) {
        try Task.checkCancellation()
        switch backend {
        case .directArchive(let epubURL):
            let publication = try EpubParser.parse(archive: epubURL)
            let ranges = try publication.chapterRanges()
            let resolvedChapters: [Chapter] = chapters.isEmpty
                ? ranges.enumerated().map { idx, range in
                    Chapter(chapterId: "direct_ch_\(idx)", title: range.title, url: "direct/\(idx)", chapterSlot: idx)
                }
                : chapters
            let safeIdx = max(0, min(max(0, resolvedChapters.count - 1), requestedChapterIndex))
            let spinePaths: [String]
            let primarySpineIndex: Int
            if ranges.indices.contains(safeIdx) {
                let range = ranges[safeIdx]
                spinePaths = (range.startIndex..<range.endIndex).compactMap {
                    publication.spine.indices.contains($0) ? publication.spine[$0].fullZipPath : nil
                }
                primarySpineIndex = range.startIndex
            } else if let first = publication.spine.first {
                spinePaths = [first.fullZipPath]
                primarySpineIndex = 0
            } else {
                throw EpubError.invalid("未找到可阅读的电子书章节")
            }
            let ch = resolvedChapters.indices.contains(safeIdx)
                ? resolvedChapters[safeIdx]
                : Chapter(chapterId: "direct_ch_0", title: fallbackTitle, url: "direct/0")
            return (ChapterSourceSpec(
                index: safeIdx,
                chapter: ch,
                volumeBookID: "direct:" + epubURL.lastPathComponent,
                publication: publication,
                spineEntryPaths: spinePaths,
                primarySpineIndex: primarySpineIndex
            ), resolvedChapters)

        case .localLibrary(let library, let seriesOrBookID, let initialBook):
            var workingChapters = chapters
            if workingChapters.isEmpty {
                workingChapters = (try? await library.chapters(for: seriesOrBookID)) ?? []
            }
            let safeIdx = max(0, min(max(0, workingChapters.count - 1), requestedChapterIndex))
            let chapter = workingChapters.indices.contains(safeIdx) ? workingChapters[safeIdx] : nil
            let parts = chapter?.url.split(separator: "/", omittingEmptySubsequences: false).map(String.init) ?? []
            let volumeID = (!parts.isEmpty && !parts[0].isEmpty) ? parts[0] : (initialBook?.id ?? seriesOrBookID)

            let book: LocalBook
            if let initialBook, initialBook.id == volumeID {
                book = initialBook
            } else {
                book = try library.book(id: volumeID)
            }
            guard let publication = book.epub else {
                throw EpubError.invalid("该本地书籍不是有效的 EPUB 文档")
            }
            guard !publication.hasDrm else {
                throw EpubError.invalid("该 EPUB 受到 DRM 加密保护，暂不支持阅读")
            }
            if workingChapters.isEmpty {
                workingChapters = library.chapters(for: book)
            }
            let finalIdx = max(0, min(max(0, workingChapters.count - 1), safeIdx))
            let finalChapter = workingChapters.indices.contains(finalIdx)
                ? workingChapters[finalIdx]
                : Chapter(chapterId: book.id, title: book.title, url: book.id)

            var spineIndices: [Int] = []
            if let bookChapter = book.chapters?.first(where: { $0.id == finalChapter.chapterId }) {
                for token in bookChapter.pages {
                    if let idx = book.pages.firstIndex(of: token), publication.spine.indices.contains(idx) {
                        spineIndices.append(idx)
                    } else if token.hasPrefix("spine-"), let idx = Int(token.dropFirst("spine-".count)),
                              publication.spine.indices.contains(idx) {
                        spineIndices.append(idx)
                    }
                }
            }
            if spineIndices.isEmpty {
                if let ranges = try? publication.chapterRanges(), ranges.indices.contains(finalIdx) {
                    spineIndices = Array(ranges[finalIdx].startIndex..<ranges[finalIdx].endIndex)
                } else {
                    spineIndices = Array(publication.spine.indices)
                }
            }
            let spinePaths = spineIndices.compactMap { idx in
                publication.spine.indices.contains(idx) ? publication.spine[idx].fullZipPath : nil
            }
            let primarySpine = spineIndices.first ?? 0
            return (ChapterSourceSpec(
                index: finalIdx,
                chapter: finalChapter,
                volumeBookID: book.id,
                publication: publication,
                spineEntryPaths: spinePaths,
                primarySpineIndex: primarySpine
            ), workingChapters)
        }
    }

    nonisolated private static func prepareChapterHtml(
        backend: Backend,
        bookID: String,
        spineEntryPaths: [String],
        cssBlock: String
    ) throws -> PreparedSpine {
        let normalized = normalizeSpineEntryPaths(spineEntryPaths)
        guard !normalized.isEmpty else {
            throw EpubError.invalid("未找到可阅读的电子书章节")
        }
        var sources: [SpineSource] = []
        sources.reserveCapacity(normalized.count)
        for path in normalized {
            try Task.checkCancellation()
            let data = try readResource(backend: backend, bookID: bookID, path: path, maxBytes: maxResourceBytes)
            let html = String(decoding: data, as: UTF8.self)
            sources.append(SpineSource(entryPath: path, rawHtml: html))
        }
        let merged = prepareMergedHtmlContent(sources: sources, cssBlock: cssBlock)
        return PreparedSpine(entryPath: sources[0].entryPath, entryPaths: sources.map(\.entryPath), html: merged)
    }

    nonisolated static func readResource(
        backend: Backend,
        bookID: String,
        path: String,
        maxBytes: Int = maxResourceBytes
    ) throws -> Data {
        let normalized = try normalizeZipPath(path)
        switch backend {
        case .localLibrary(let library, _, _):
            return try library.epubResource(bookID: bookID, path: normalized, maximumBytes: maxBytes)
        case .directArchive(let epubURL):
            let archive = try Archive(url: epubURL, accessMode: .read)
            guard let entry = findEntry(in: archive, normalizedPath: normalized) else {
                throw EpubError.invalid("缺少资源：\(normalized)")
            }
            guard entry.uncompressedSize <= UInt64(maxBytes) else {
                throw EpubError.limitExceeded("资源体积超出上限：\(normalized)")
            }
            var data = Data()
            data.reserveCapacity(Int(min(entry.uncompressedSize, UInt64(maxBytes))))
            _ = try archive.extract(entry, bufferSize: 64 * 1024, skipCRC32: false) { chunk in
                try Task.checkCancellation()
                guard data.count + chunk.count <= maxBytes else {
                    throw EpubError.limitExceeded("资源体积超出上限：\(normalized)")
                }
                data.append(chunk)
            }
            return data
        }
    }

    nonisolated private static func findEntry(in archive: Archive, normalizedPath: String) -> Entry? {
        if let direct = archive[normalizedPath] { return direct }
        if let decoded = normalizedPath.removingPercentEncoding, decoded != normalizedPath, let alt = archive[decoded] {
            return alt
        }
        return nil
    }

    // MARK: - Path Normalization & HTML/CSS Rewriting

    nonisolated static func normalizeZipPath(_ raw: String) throws -> String {
        let stripped = stripQueryAndFragment(raw).replacingOccurrences(of: "\\", with: "/")
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else {
            throw EpubError.invalid("资源路径非法：\(raw)")
        }
        let noLeadingSlash = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        guard !(noLeadingSlash.split(separator: "/").first?.contains(":") ?? false) else {
            throw EpubError.invalid("资源路径非法越界：\(raw)")
        }
        var parts: [Substring] = []
        for part in noLeadingSlash.split(separator: "/") {
            if part == "." || part.isEmpty { continue }
            if part == ".." {
                guard !parts.isEmpty else {
                    throw EpubError.invalid("ZIP 路径非法越界：\(raw)")
                }
                parts.removeLast()
            } else {
                parts.append(part)
            }
        }
        guard !parts.isEmpty else {
            throw EpubError.invalid("ZIP 路径为空：\(raw)")
        }
        return parts.joined(separator: "/")
    }

    nonisolated static func resolveZipPath(baseDir: String, relativePath: String) -> String {
        let cleanRel = stripQueryAndFragment(relativePath).replacingOccurrences(of: "\\", with: "/")
        var segments: [String] = []
        if !cleanRel.hasPrefix("/") && !baseDir.isEmpty {
            for part in baseDir.split(separator: "/") {
                let s = String(part)
                if s.isEmpty || s == "." { continue }
                if s == ".." {
                    if !segments.isEmpty { segments.removeLast() }
                } else {
                    segments.append(s)
                }
            }
        }
        for part in cleanRel.split(separator: "/") {
            let s = String(part)
            if s.isEmpty || s == "." { continue }
            if s == ".." {
                if !segments.isEmpty { segments.removeLast() }
            } else {
                segments.append(s)
            }
        }
        return segments.joined(separator: "/")
    }

    nonisolated static func normalizeSpineEntryPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in paths {
            let clean = stripQueryAndFragment(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized = try? normalizeZipPath(clean) else { continue }
            if seen.insert(normalized).inserted {
                out.append(normalized)
            }
        }
        return out
    }

    nonisolated private static func stripQueryAndFragment(_ value: String) -> String {
        var result = value
        if let hashIdx = result.firstIndex(of: "#") {
            result = String(result[..<hashIdx])
        }
        if let queryIdx = result.firstIndex(of: "?") {
            result = String(result[..<queryIdx])
        }
        return result
    }

    nonisolated private static func parentZipDir(of path: String) -> String {
        guard let lastSlash = path.lastIndex(of: "/") else { return "" }
        return String(path[...lastSlash])
    }

    nonisolated private static func percentEncodePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    nonisolated static func prepareMergedHtmlContent(sources: [SpineSource], cssBlock: String) -> String {
        let cspMeta = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src \(urlScheme): data:; style-src 'unsafe-inline' \(urlScheme):; font-src \(urlScheme): data:; script-src 'none';\"/>"
        guard !sources.isEmpty else {
            return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\"/>\(cspMeta)\(cssBlock)</head><body></body></html>"
        }

        var entryIndexByPath: [String: Int] = [:]
        for (i, source) in sources.enumerated() where !source.entryPath.isEmpty {
            entryIndexByPath[source.entryPath] = i
            if let decoded = source.entryPath.removingPercentEncoding, decoded != source.entryPath {
                entryIndexByPath[decoded] = i
            }
        }

        var headExtras: [String] = []
        var seenExtras = Set<String>()
        var bodySections = ""

        for (i, source) in sources.enumerated() {
            let parentDir = parentZipDir(of: source.entryPath)
            var cleaned = replaceRegex("(?is)<script\\b[^>]*>[\\s\\S]*?</script>", in: source.rawHtml, with: "")
            cleaned = replaceRegex("(?is)<script\\b[^>]*/>", in: cleaned, with: "")

            if let headInner = firstMatchGroup("(?is)<head\\b[^>]*>([\\s\\S]*?)</head>", in: cleaned, group: 1) {
                for styleTag in allMatches("(?is)<style\\b[^>]*>[\\s\\S]*?</style>", in: headInner) {
                    if seenExtras.insert(styleTag).inserted { headExtras.append(styleTag) }
                }
                for linkTag in allMatches("(?is)<link\\b[^>]*>", in: headInner) {
                    if linkTag.lowercased().contains("stylesheet") {
                        let rewrittenLink = rewriteTagAttrUrls(in: linkTag, tagName: nil, attrName: "href", parentDir: parentDir)
                        if seenExtras.insert(rewrittenLink).inserted { headExtras.append(rewrittenLink) }
                    }
                }
            }

            var bodyAttr = ""
            var bodyInner = ""
            if let bodyMatch = firstTwoMatchGroups("(?is)<body\\b([^>]*)>([\\s\\S]*?)</body>", in: cleaned) {
                bodyAttr = bodyMatch.0
                bodyInner = bodyMatch.1
            } else {
                bodyInner = replaceRegex("(?is)<!DOCTYPE[^>]*>", in: cleaned, with: "")
                bodyInner = replaceRegex("(?is)<head\\b[^>]*>[\\s\\S]*?</head>", in: bodyInner, with: "")
                bodyInner = replaceRegex("(?is)</?html\\b[^>]*>", in: bodyInner, with: "")
                bodyInner = replaceRegex("(?is)</?body\\b[^>]*>", in: bodyInner, with: "")
            }

            bodyInner = rewriteTagAttrUrls(in: bodyInner, tagName: "img", attrName: "src", parentDir: parentDir)
            bodyInner = rewriteTagAttrUrls(in: bodyInner, tagName: "image", attrName: "xlink:href", parentDir: parentDir)
            bodyInner = rewriteTagAttrUrls(in: bodyInner, tagName: "image", attrName: "href", parentDir: parentDir)
            bodyInner = rewriteAnchorHrefs(in: bodyInner, currentEntry: source.entryPath, parentDir: parentDir, entryIndexByPath: entryIndexByPath)

            var bodyIdAnchor = ""
            if let bodyId = firstMatchGroup("(?is)\\bid\\s*=\\s*([\"'])([^\"']+)\\1", in: bodyAttr, group: 2),
               !bodyId.isEmpty,
               !bodyInner.contains("id=\"\(bodyId)\""),
               !bodyInner.contains("id='\(bodyId)'") {
                bodyIdAnchor = "<span id=\"\(escapeHtmlAttr(bodyId))\"></span>"
            }

            bodySections += "<section class=\"xx-spine-section\" id=\"__xx_spine_\(i)\" data-entry=\"\(escapeHtmlAttr(source.entryPath))\">\(bodyIdAnchor)\(bodyInner)</section>\n"
        }

        var out = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/>"
        out += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\"/>\n"
        out += cspMeta + "\n"
        for extra in headExtras {
            out += extra + "\n"
        }
        out += cssBlock
        out += "</head><body>\n\(bodySections)</body></html>"
        return out
    }

    nonisolated private static func rewriteTagAttrUrls(
        in html: String,
        tagName: String?,
        attrName: String,
        parentDir: String
    ) -> String {
        let tagPrefix = tagName.map { "<" + NSRegularExpression.escapedPattern(for: $0) + "\\b" } ?? "<[a-zA-Z0-9:_-]+\\b"
        let pattern = "(?is)(\(tagPrefix)[^>]*\\s\(NSRegularExpression.escapedPattern(for: attrName))\\s*=\\s*)([\"'])([^\"']+)\\2([^>]*>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return html }
        let mutable = NSMutableString(string: html)
        for match in matches.reversed() {
            let before = ns.substring(with: match.range(at: 1))
            let quote = ns.substring(with: match.range(at: 2))
            let rawVal = ns.substring(with: match.range(at: 3))
            let after = ns.substring(with: match.range(at: 4))
            var replaced = rawVal
            if !isExternalOrSpecialScheme(rawVal) && !rawVal.hasPrefix("#") {
                let resolved = resolveZipPath(baseDir: parentDir, relativePath: rawVal)
                if !resolved.isEmpty {
                    replaced = "\(urlScheme)://\(urlHost)/\(percentEncodePath(resolved))"
                }
            }
            mutable.replaceCharacters(in: match.range, with: "\(before)\(quote)\(replaced)\(quote)\(after)")
        }
        return mutable as String
    }

    nonisolated private static func rewriteAnchorHrefs(
        in html: String,
        currentEntry: String,
        parentDir: String,
        entryIndexByPath: [String: Int]
    ) -> String {
        let pattern = "(?is)(<a\\b[^>]*\\shref\\s*=\\s*)([\"'])([^\"']+)\\2([^>]*>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return html }
        let mutable = NSMutableString(string: html)
        for match in matches.reversed() {
            let before = ns.substring(with: match.range(at: 1))
            let quote = ns.substring(with: match.range(at: 2))
            let rawHref = ns.substring(with: match.range(at: 3))
            let after = ns.substring(with: match.range(at: 4))
            let rewritten = rewriteSingleAnchorHref(rawHref, currentEntry: currentEntry, parentDir: parentDir, entryIndexByPath: entryIndexByPath)
            mutable.replaceCharacters(in: match.range, with: "\(before)\(quote)\(rewritten)\(quote)\(after)")
        }
        return mutable as String
    }

    nonisolated private static func rewriteSingleAnchorHref(
        _ rawHref: String,
        currentEntry: String,
        parentDir: String,
        entryIndexByPath: [String: Int]
    ) -> String {
        let trimmed = rawHref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return rawHref }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("javascript:") { return "#" }
        if isExternalOrSpecialScheme(trimmed) { return rawHref }

        let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let filePart = String(parts[0])
        let fragment = parts.count > 1 ? String(parts[1]) : ""
        let resolvedPath = filePart.isEmpty ? currentEntry : resolveZipPath(baseDir: parentDir, relativePath: filePart)
        let targetIdx = entryIndexByPath[resolvedPath] ?? resolvedPath.removingPercentEncoding.flatMap { entryIndexByPath[$0] }
        if let targetIdx, fragment.isEmpty {
            return "#__xx_spine_\(targetIdx)"
        }
        let encoded = percentEncodePath(resolvedPath)
        return "\(urlScheme)://\(urlHost)/\(encoded)" + (fragment.isEmpty ? "" : "#\(fragment)")
    }

    nonisolated private static func isExternalOrSpecialScheme(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("data:")
            || lower.hasPrefix("mailto:")
            || lower.hasPrefix("tel:")
    }

    nonisolated private static func escapeHtmlAttr(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    nonisolated private static func replaceRegex(_ pattern: String, in input: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return input }
        return regex.stringByReplacingMatches(in: input, range: NSRange(input.startIndex..., in: input), withTemplate: replacement)
    }

    nonisolated private static func allMatches(_ pattern: String, in input: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = input as NSString
        return regex.matches(in: input, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    nonisolated private static func firstMatchGroup(_ pattern: String, in input: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)),
              group < match.numberOfRanges,
              match.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: match.range(at: group))
    }

    nonisolated private static func firstTwoMatchGroups(_ pattern: String, in input: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 3 else { return nil }
        let r1 = match.range(at: 1)
        let r2 = match.range(at: 2)
        let g1 = r1.location != NSNotFound ? ns.substring(with: r1) : ""
        let g2 = r2.location != NSNotFound ? ns.substring(with: r2) : ""
        return (g1, g2)
    }

    // MARK: - CSS, JS & Theme Application

    private func generateCssBlock() -> String {
        "<style id=\"xx-reader-style\">\n\(generateCssBody())\n</style>\n"
    }

    private func generateCssBody() -> String {
        let bg = settings.theme.cssBackgroundHex
        let fg = settings.theme.cssTextHex
        let accent = settings.theme.cssAccentHex
        let insets = view.safeAreaInsets
        let padTop = max(22, Int(ceil(insets.top)) + 16)
        let padLeft = 18 + Int(ceil(insets.left))
        let padRight = 18 + Int(ceil(insets.right))
        let padBottom = max(90, Int(ceil(insets.bottom)) + 24)

        let pagedRules: String
        if settings.pagedMode {
            pagedRules = """
              html {
                width: 100vw !important;
                height: 100vh !important;
                overflow-x: auto !important;
                overflow-y: hidden !important;
              }
              body {
                height: 100vh !important;
                margin: 0 !important;
                padding: \(padTop)px \(padRight)px \(padBottom)px \(padLeft)px !important;
                column-width: calc(100vw - \(padLeft + padRight)px) !important;
                column-gap: \(padLeft + padRight)px !important;
                column-fill: auto !important;
              }
            """
        } else {
            pagedRules = """
              html {
                overflow-x: hidden !important;
                overflow-y: auto !important;
              }
              body {
                margin: 0 !important;
                padding: \(padTop)px \(padRight)px \(padBottom)px \(padLeft)px !important;
              }
            """
        }

        return """
          * { -webkit-tap-highlight-color: transparent; box-sizing: border-box; }
          html {
            background-color: \(bg) !important;
            margin: 0 !important;
            padding: 0 !important;
          }
          body {
            background-color: \(bg) !important;
            color: \(fg) !important;
            font-size: \(settings.fontSize)px !important;
            line-height: \(settings.lineHeight) !important;
            font-family: -apple-system, BlinkMacSystemFont, 'PingFang SC', 'Hiragino Sans GB', sans-serif !important;
            word-break: break-word;
            text-align: justify;
          }
          \(pagedRules)
          .xx-spine-section { display: block; }
          .xx-spine-section + .xx-spine-section { margin-top: 0.9em; }
          p {
            margin-top: 0 !important;
            margin-bottom: 0.9em !important;
            text-indent: 2em;
            line-height: \(settings.lineHeight) !important;
          }
          h1, h2, h3, h4, h5, h6 {
            color: \(fg) !important;
            text-indent: 0 !important;
            margin-top: 1.2em;
            margin-bottom: 0.6em;
            font-weight: bold;
          }
          img, svg image {
            max-width: 100% !important;
            height: auto !important;
          }
          img {
            display: block !important;
            margin: 14px auto !important;
            border-radius: 4px;
          }
          a { color: \(accent) !important; text-decoration: none; }
          blockquote { margin: 12px 0; padding: 6px 14px; border-left: 3px solid \(accent); opacity: 0.85; }
        """
    }

    private static func bridgeScriptSource() -> String {
        return """
        (function() {
          if (window.__xxTextReaderInstalled) return;
          window.__xxTextReaderInstalled = true;
          window.__xxPagedMode = false;
          let lastReported = 0;
          let scrollTrailingTimer = null;

          function computeScrollPercent() {
            if (window.__xxPagedMode) {
              let totalX = document.documentElement.scrollWidth - window.innerWidth;
              let pctX = totalX > 0 ? (window.pageXOffset / totalX) : 0;
              return Math.max(0, Math.min(1, pctX));
            }
            let total = document.documentElement.scrollHeight - window.innerHeight;
            let percent = total > 0 ? (window.pageYOffset / total) : 0;
            return Math.max(0, Math.min(1, percent));
          }

          function reportScrollPercent() {
            lastReported = Date.now();
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.TextBridge) {
              window.webkit.messageHandlers.TextBridge.postMessage({ type: 'scroll', percent: computeScrollPercent() });
            }
          }

          window.addEventListener('scroll', function() {
            let now = Date.now();
            if (now - lastReported > 100) {
              reportScrollPercent();
            }
            if (scrollTrailingTimer !== null) clearTimeout(scrollTrailingTimer);
            scrollTrailingTimer = setTimeout(function() {
              scrollTrailingTimer = null;
              reportScrollPercent();
            }, 120);
          }, { passive: true });

          function isInsideAnchor(node) {
            while (node) {
              if (node.nodeType === 1 && node.tagName && node.tagName.toUpperCase() === 'A') return true;
              node = node.parentNode;
            }
            return false;
          }

          let downX = 0, downY = 0, downTime = 0, multiTouch = false;
          document.addEventListener('touchstart', function(e) {
            if (e.touches.length > 1) { multiTouch = true; return; }
            if (e.touches.length === 1) {
              multiTouch = false;
              downX = e.touches[0].clientX;
              downY = e.touches[0].clientY;
              downTime = Date.now();
            }
          }, { passive: true });
          document.addEventListener('touchmove', function(e) {
            if (e.touches.length > 1) multiTouch = true;
          }, { passive: true });
          document.addEventListener('touchcancel', function() { multiTouch = true; }, { passive: true });
          document.addEventListener('touchend', function(e) {
            let wasMulti = multiTouch;
            if (e.touches.length === 0) multiTouch = false;
            if (wasMulti || e.touches.length > 0 || e.changedTouches.length !== 1) return;
            if (isInsideAnchor(e.target)) return;
            let dx = Math.abs(e.changedTouches[0].clientX - downX);
            let dy = Math.abs(e.changedTouches[0].clientY - downY);
            let duration = Date.now() - downTime;
            if (dx < 12 && dy < 12 && duration < 300) {
              let x = e.changedTouches[0].clientX;
              let w = window.innerWidth;
              let handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.TextBridge;
              if (!handler) return;
              if (x > w * 0.32 && x < w * 0.68) {
                handler.postMessage({ type: 'centerTap' });
              } else if (x <= w * 0.32) {
                let atStart = window.__xxPagedMode ? (window.pageXOffset <= 2) : (window.pageYOffset <= 2);
                handler.postMessage({ type: 'leftTap', atBoundary: atStart });
              } else {
                let atEnd;
                if (window.__xxPagedMode) {
                  atEnd = (window.pageXOffset + window.innerWidth) >= (document.documentElement.scrollWidth - 2);
                } else {
                  let docH = Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0);
                  atEnd = (window.pageYOffset + window.innerHeight) >= (docH - 2);
                }
                handler.postMessage({ type: 'rightTap', atBoundary: atEnd });
              }
            }
          }, { passive: true });
        })();
        """
    }

    private func applyThemeAppearance() {
        let style: UIUserInterfaceStyle = settings.theme.isDarkAppearance ? .dark : .light
        overrideUserInterfaceStyle = style
        hostNavigationController()?.overrideUserInterfaceStyle = style
        view.backgroundColor = settings.theme.backgroundColor
        webView.backgroundColor = settings.theme.backgroundColor
        webView.scrollView.backgroundColor = settings.theme.backgroundColor

        let themeIcon: ParityIcon = settings.theme == .dark ? .moon : (settings.theme == .light ? .sun : .automatic)
        configureToolbarButton(themeButton, title: "主题", icon: themeIcon, id: "text.reader.theme.cycle")

        webView.scrollView.isPagingEnabled = settings.pagedMode
        webView.scrollView.alwaysBounceHorizontal = settings.pagedMode
        webView.scrollView.alwaysBounceVertical = !settings.pagedMode

        setNeedsStatusBarAppearanceUpdate()
    }

    private func applyLiveDocumentStyle() {
        guard !isReleased else { return }
        let cssLiteral = jsStringLiteral(generateCssBody())
        let pagedLiteral = settings.pagedMode ? "true" : "false"
        let script = "(function(){window.__xxPagedMode=\(pagedLiteral);var s=document.getElementById('xx-reader-style');if(s){s.textContent=\(cssLiteral);}})();"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func jsStringLiteral(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "'\(escaped)'"
    }

    private func scrollToPercent(_ percent: Double) {
        guard !isReleased else { return }
        let clamped = max(0, min(1, percent))
        let script: String
        if settings.pagedMode {
            script = "(function(){var w=Math.max(1,window.innerWidth);var total=Math.max(0,document.documentElement.scrollWidth-w);var target=Math.round((total*\(clamped))/w)*w;window.scrollTo(Math.max(0,Math.min(total,target)),0);})();"
        } else {
            script = "(function(){var total=Math.max(0,document.documentElement.scrollHeight-window.innerHeight);window.scrollTo(0,Math.max(0,total*\(clamped)));})();"
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func scrollByPages(_ pageDelta: Int) {
        guard !isReleased else { return }
        let script: String
        if settings.pagedMode {
            script = "(function(){var step=window.innerWidth*\(pageDelta);window.scrollBy({left:step,top:0,behavior:'smooth'});})();"
        } else {
            script = "(function(){var step=window.innerHeight*0.88*\(pageDelta);window.scrollBy({top:step,left:0,behavior:'smooth'});})();"
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func scrollToAnchorInEntry(entryPath: String?, anchorId: String?) {
        guard !isReleased else { return }
        let hasEntry = !(entryPath?.isEmpty ?? true)
        let hasAnchor = !(anchorId?.isEmpty ?? true)
        guard hasEntry || hasAnchor else { return }
        let safeEntry = jsStringLiteral(hasEntry ? Self.stripQueryAndFragment(entryPath!) : "")
        let safeAnchor = jsStringLiteral(hasAnchor ? anchorId! : "")
        let script = """
        (function() {
          var entry = \(safeEntry);
          var id = \(safeAnchor);
          var scope = null;
          if (entry) {
            var sections = document.querySelectorAll('section[data-entry]');
            for (var i = 0; i < sections.length; i++) {
              if (sections[i].getAttribute('data-entry') === entry) { scope = sections[i]; break; }
            }
          }
          var el = null;
          if (scope && id) {
            var nodes = scope.querySelectorAll('[id],[name]');
            for (var j = 0; j < nodes.length; j++) {
              if (nodes[j].id === id || nodes[j].getAttribute('name') === id) { el = nodes[j]; break; }
            }
          }
          if (!el && id) {
            el = document.getElementById(id) || document.getElementsByName(id)[0];
          }
          if (!el && scope) el = scope;
          if (el) el.scrollIntoView();
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate & WKScriptMessageHandler

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isReleased else { return }
        if hasLoadedHtml {
            applyLiveDocumentStyle()
        }
        if let loc = pendingRestoreLocator {
            pendingRestoreLocator = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, !self.isReleased else { return }
                if !loc.anchorID.isEmpty {
                    self.scrollToAnchorInEntry(entryPath: loc.resourceHref, anchorId: loc.anchorID)
                } else if loc.scrollPercentage > 0.01 {
                    self.scrollToPercent(loc.scrollPercentage)
                }
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard !isReleased, let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == Self.urlScheme && url.host?.lowercased() == Self.urlHost {
            if navigationAction.navigationType == .linkActivated {
                let rawPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
                let fragment = url.fragment ?? ""
                let normalized = (try? Self.normalizeZipPath(rawPath)) ?? rawPath
                if !fragment.isEmpty && (loadedEntryPaths.contains(normalized) || rawPath.isEmpty) {
                    scrollToAnchorInEntry(entryPath: normalized, anchorId: fragment)
                    decisionHandler(.cancel)
                    return
                }
                if loadedEntryPaths.contains(normalized) {
                    scrollToAnchorInEntry(entryPath: normalized, anchorId: nil)
                    decisionHandler(.cancel)
                    return
                }
                if let targetChapterIdx = chapterIndex(forEntryPath: normalized) {
                    flushPositionSave()
                    currentChapterIndex = targetChapterIdx
                    pendingRestoreLocator = TextLocator(
                        bookID: activeBookID,
                        chapterIndex: targetChapterIdx,
                        spineIndex: 0,
                        resourceHref: normalized,
                        anchorID: fragment,
                        scrollPercentage: 0
                    )
                    loadCurrentChapter(restoreSavedLocator: false)
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            return
        }
        if scheme == "about" && navigationAction.navigationType != .linkActivated {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated {
            presentExternalLinkPrompt(url: url)
        }
        decisionHandler(.cancel)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !isReleased, message.name == "TextBridge",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "scroll":
            if let pct = body["percent"] as? Double, pct.isFinite {
                let clamped = max(0, min(1, pct))
                currentScrollPercent = clamped
                readingHabits?.userDidRead()
                updateHeaderAndProgressUI()
                schedulePositionSave(percent: clamped)
            }
        case "centerTap":
            readingHabits?.userDidRead()
            setFullscreen(!fullscreen, animated: true)
        case "leftTap":
            let atBoundary = (body["atBoundary"] as? Bool) ?? false
            handleEdgeTap(isLeft: true, atBoundary: atBoundary)
        case "rightTap":
            let atBoundary = (body["atBoundary"] as? Bool) ?? false
            handleEdgeTap(isLeft: false, atBoundary: atBoundary)
        default:
            break
        }
    }

    private func handleEdgeTap(isLeft: Bool, atBoundary: Bool) {
        if settings.pagedMode {
            if isLeft {
                if atBoundary { navigateChapter(-1) }
                else { scrollByPages(-1) }
            } else {
                if atBoundary { navigateChapter(1) }
                else { scrollByPages(1) }
            }
        } else if fullscreen == false {
            setFullscreen(true, animated: true)
        }
    }

    private func chapterIndex(forEntryPath path: String) -> Int? {
        guard let publication = activePublication,
              let spineIdx = publication.spine.firstIndex(where: { $0.fullZipPath == path }),
              let ranges = try? publication.chapterRanges() else { return nil }
        return ranges.firstIndex { spineIdx >= $0.startIndex && spineIdx < $0.endIndex }
    }

    private func presentExternalLinkPrompt(url: URL) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "外部链接提示",
            message: "该链接指向外部网络：\n\(url.absoluteString)\n\n是否在外部浏览器打开？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "打开", style: .default) { _ in
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    // MARK: - Persistence (`TextLocator` + `LibraryStore`)

    private func locatorDefaultsKey(bookID: String) -> String {
        "text_pos_\(bookID)"
    }

    private func restoredLocator(forChapterIndex chapterIndex: Int) -> TextLocator? {
        let keys = Set([comic.comicId, activeBookID])
        for key in keys {
            if let data = defaults.data(forKey: locatorDefaultsKey(bookID: key)),
               let decoded = try? JSONDecoder().decode(TextLocator.self, from: data),
               decoded.chapterIndex == chapterIndex {
                return decoded
            }
        }
        if chapters.indices.contains(chapterIndex),
           let pos = libraryStore?.position(for: comic, chapterID: chapters[chapterIndex].chapterId) {
            return TextLocator(
                bookID: activeBookID,
                chapterIndex: chapterIndex,
                spineIndex: pos.imageIndex,
                resourceHref: "",
                anchorID: "",
                scrollPercentage: pos.offset,
                charOffset: 0
            )
        }
        return nil
    }

    private func recordScrollPosition(percent: Double) {
        let locator = TextLocator(
            bookID: activeBookID,
            chapterIndex: currentChapterIndex,
            spineIndex: currentSpineIndex,
            resourceHref: currentEntryPath,
            anchorID: "",
            scrollPercentage: percent,
            charOffset: 0
        )
        if let encoded = try? JSONEncoder().encode(locator) {
            defaults.set(encoded, forKey: locatorDefaultsKey(bookID: activeBookID))
            if comic.comicId != activeBookID {
                defaults.set(encoded, forKey: locatorDefaultsKey(bookID: comic.comicId))
            }
        }
        guard chapters.indices.contains(currentChapterIndex), let libraryStore else { return }
        let chapter = chapters[currentChapterIndex]
        let position = ReaderPosition(imageIndex: currentSpineIndex, offset: percent, atEnd: percent >= 0.99)
        try? libraryStore.saveReading(comic, chapter: chapter, chapterIndex: currentChapterIndex, position: position)
    }

    private func schedulePositionSave(percent: Double) {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled, !self.isReleased else { return }
            self.saveTask = nil
            self.recordScrollPosition(percent: percent)
        }
    }

    private func flushPositionSave() {
        saveTask?.cancel()
        saveTask = nil
        guard hasLoadedHtml, !isReleased else { return }
        recordScrollPosition(percent: currentScrollPercent)
    }

    // MARK: - UI State & Controls

    private func updateHeaderAndProgressUI() {
        let chapterTitle = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : comic.title
        title = chapterTitle
        headerHeading.text = comic.title.isEmpty ? chapterTitle : "\(comic.title) · \(chapterTitle)"

        let pct = Int((currentScrollPercent * 100.0).rounded())
        seekBar.configure(currentPage: pct, total: 101, sessionToken: Int64(currentChapterIndex))
        chapterProgress.progress = Float(currentChapterIndex + 1) / Float(max(1, chapters.count))

        let shortTitle = chapterTitle.count > 14 ? String(chapterTitle.prefix(13)) + "…" : chapterTitle
        statusBadge.text = "\(shortTitle)  \(pct)%  \(badgeTimeFormatter.string(from: Date()))"
        updateChapterNavButtons()
    }

    private func updateChapterNavButtons() {
        previousButton.isEnabled = currentChapterIndex > 0
        nextButton.isEnabled = currentChapterIndex + 1 < chapters.count
        previousButton.alpha = previousButton.isEnabled ? 1.0 : 0.35
        nextButton.alpha = nextButton.isEnabled ? 1.0 : 0.35
    }

    private func setFullscreen(_ hidden: Bool, animated: Bool) {
        guard fullscreen != hidden else { return }
        fullscreen = hidden
        toolbar.isHidden = hidden
        topChrome.isHidden = hidden
        bottomChrome.isHidden = hidden
        chapterProgress.isHidden = !hidden || chapters.isEmpty
        statusBadge.isHidden = !hidden || !hasLoadedHtml
        hostNavigationController()?.setNavigationBarHidden(hidden, animated: animated)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        readingHabits?.overlayVisibilityChanged(isVisible: !hidden)
    }

    private func showLoadingState(_ message: String) {
        stateOverlay.subviews.forEach { $0.removeFromSuperview() }
        stateOverlay.backgroundColor = settings.theme.backgroundColor
        stateOverlay.isHidden = false

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Palette.accent
        spinner.startAnimating()

        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 14)
        label.textColor = Palette.secondaryText
        label.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stateOverlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: stateOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: stateOverlay.centerYAnchor)
        ])
    }

    private func showErrorState(_ message: String, onRetry: @escaping () -> Void) {
        stateOverlay.subviews.forEach { $0.removeFromSuperview() }
        stateOverlay.backgroundColor = settings.theme.backgroundColor
        stateOverlay.isHidden = false

        let card = UIView()
        card.backgroundColor = settings.theme.panelBackgroundColor
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = Palette.border.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "无法打开章节"
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.textAlignment = .center

        let detailLabel = UILabel()
        detailLabel.text = message
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = Palette.secondaryText
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        let retryBtn = UIButton(type: .system)
        retryBtn.setTitle("重试", for: .normal)
        retryBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        retryBtn.setTitleColor(.white, for: .normal)
        retryBtn.backgroundColor = Palette.accent
        retryBtn.layer.cornerRadius = 22
        retryBtn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 28, bottom: 10, right: 28)
        retryBtn.addAction(UIAction { _ in onRetry() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, retryBtn])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        stateOverlay.addSubview(card)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            retryBtn.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            card.centerXAnchor.constraint(equalTo: stateOverlay.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: stateOverlay.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: stateOverlay.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(lessThanOrEqualTo: stateOverlay.trailingAnchor, constant: -24)
        ])
    }

    private func hideStateOverlay() {
        stateOverlay.isHidden = true
        stateOverlay.subviews.forEach { $0.removeFromSuperview() }
    }

    // MARK: - Actions

    @objc private func returnToPrevious() {
        flushPositionSave()
        hostNavigationController()?.popViewController(animated: true)
    }

    @objc private func previousChapterTapped() {
        navigateChapter(-1)
    }

    @objc private func nextChapterTapped() {
        navigateChapter(1)
    }

    private func navigateChapter(_ delta: Int) {
        let nextIdx = currentChapterIndex + delta
        guard chapters.indices.contains(nextIdx) else {
            let msg = delta > 0 ? "已经是最后一章" : "已经是第一章"
            RemToastView.show(message: msg, kind: .info, in: self)
            return
        }
        flushPositionSave()
        currentChapterIndex = nextIdx
        loadCurrentChapter(restoreSavedLocator: false)
    }

    @objc private func showDirectoryTapped() {
        guard presentedViewController == nil, !chapters.isEmpty else { return }
        readingHabits?.userDidRead()
        let drawer = ChapterDrawerSheet(
            chapters: chapters,
            currentChapterIndex: currentChapterIndex,
            hasCurrent: true,
            isReader: true,
            isDarkReader: settings.theme.isDarkAppearance,
            isDesc: defaults.bool(forKey: "chapter.desc"),
            onOrderChanged: { [weak self] desc in
                self?.defaults.set(desc, forKey: "chapter.desc")
            }
        ) { [weak self] selectedIndex in
            guard let self, self.chapters.indices.contains(selectedIndex) else { return }
            self.flushPositionSave()
            self.currentChapterIndex = selectedIndex
            self.loadCurrentChapter(restoreSavedLocator: false)
        }
        present(drawer, animated: false)
    }

    @objc private func showTypographySettingsTapped() {
        guard presentedViewController == nil else { return }
        let sheet = TextReaderSettingsSheetController(settings: settings) { [weak self] updated in
            guard let self else { return }
            let pct = self.currentScrollPercent
            self.settings = updated
            updated.save(to: self.defaults)
            self.applyThemeAppearance()
            if self.hasLoadedHtml {
                self.applyLiveDocumentStyle()
                if pct > 0.005 {
                    self.scrollToPercent(pct)
                }
            }
        }
        present(sheet, animated: true)
    }

    @objc private func cycleThemeTapped() {
        let all = ReaderThemeMode.allCases
        let nextRaw = (settings.theme.rawValue + 1) % all.count
        settings.theme = ReaderThemeMode(rawValue: nextRaw) ?? .dark
        settings.save(to: defaults)
        applyThemeAppearance()
        if hasLoadedHtml {
            applyLiveDocumentStyle()
        }
    }
}

// MARK: - WeakScriptMessageHandler & WKURLSchemeHandler

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: (any WKScriptMessageHandler)?
    init(delegate: any WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

private final class EpubSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private enum SourceBackend: Sendable {
        case localLibrary(library: LocalLibrary, bookID: String)
        case directArchive(epubURL: URL)
    }

    private let lock = NSLock()
    private var backend: SourceBackend
    private var activeTasks = Set<ObjectIdentifier>()

    init(backend: TextReaderViewController.BackendAccess) {
        switch backend {
        case .localLibrary(let library, let bookID):
            self.backend = .localLibrary(library: library, bookID: bookID)
        case .directArchive(let epubURL):
            self.backend = .directArchive(epubURL: epubURL)
        }
    }

    func updateActiveBookID(_ bookID: String) {
        lock.lock()
        if case .localLibrary(let library, _) = backend {
            backend = .localLibrary(library: library, bookID: bookID)
        }
        lock.unlock()
    }

    func stopAll() {
        lock.lock()
        activeTasks.removeAll()
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme?.lowercased() == TextReaderViewController.urlScheme,
              url.host?.lowercased() == TextReaderViewController.urlHost else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }

        let taskID = ObjectIdentifier(urlSchemeTask)
        lock.lock()
        activeTasks.insert(taskID)
        let currentBackend = backend
        lock.unlock()

        let rawPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (normalized, data) = try await Task.detached(priority: .userInitiated) { () throws -> (String, Data) in
                    let normalized = try TextReaderViewController.normalizeZipPath(rawPath)
                    let data: Data
                    switch currentBackend {
                    case .localLibrary(let library, let bookID):
                        data = try library.epubResource(
                            bookID: bookID,
                            path: normalized,
                            maximumBytes: TextReaderViewController.maxResourceBytes
                        )
                    case .directArchive(let epubURL):
                        data = try TextReaderViewController.readDirectArchiveEntry(
                            epubURL: epubURL,
                            normalizedPath: normalized,
                            maxBytes: TextReaderViewController.maxResourceBytes
                        )
                    }
                    return (normalized, data)
                }.value

                guard self.consumeTask(taskID) else { return }
                let mime = Self.mimeType(for: normalized)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": mime,
                        "Content-Length": "\(data.count)",
                        "Cache-Control": "no-store"
                    ]
                )!
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard self.consumeTask(taskID) else { return }
                let notFound = HTTPURLResponse(
                    url: url,
                    statusCode: 404,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/plain; charset=utf-8"]
                )!
                urlSchemeTask.didReceive(notFound)
                urlSchemeTask.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        lock.lock()
        activeTasks.remove(taskID)
        lock.unlock()
    }

    private func consumeTask(_ id: ObjectIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeTasks.remove(id) != nil
    }

    private static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "xhtml": return "application/xhtml+xml; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        default: return "application/octet-stream"
        }
    }
}

private extension TextReaderViewController {
    enum BackendAccess {
        case localLibrary(library: LocalLibrary, bookID: String)
        case directArchive(epubURL: URL)
    }

    nonisolated static func readDirectArchiveEntry(epubURL: URL, normalizedPath: String, maxBytes: Int) throws -> Data {
        try readResource(backend: .directArchive(epubURL: epubURL), bookID: "", path: normalizedPath, maxBytes: maxBytes)
    }
}

private extension EpubSchemeHandler {
    convenience init(backend: TextReaderViewController.Backend) {
        switch backend {
        case .localLibrary(let library, let bookID, _):
            self.init(backend: .localLibrary(library: library, bookID: bookID))
        case .directArchive(let epubURL):
            self.init(backend: .directArchive(epubURL: epubURL))
        }
    }
}

// MARK: - TextReaderSettingsSheetController

@MainActor
private final class TextReaderSettingsSheetController: UIViewController {
    private var settings: TextReaderViewController.Settings
    private let onChanged: (TextReaderViewController.Settings) -> Void

    private let panel = UIView()
    private let titleLabel = UILabel()
    private let divider = UIView()
    private let fontTitleLabel = UILabel()
    private let fontValueLabel = UILabel()
    private let fontMinusButton = UIButton(type: .system)
    private let fontPlusButton = UIButton(type: .system)
    private let lineTitleLabel = UILabel()
    private var lineButtons: [UIButton] = []
    private let themeTitleLabel = UILabel()
    private var themeButtons: [UIButton] = []
    private let modeTitleLabel = UILabel()
    private var modeButtons: [UIButton] = []

    private let lineValues: [Double] = [1.5, 1.75, 2.0]
    private let lineTitles = ["紧凑", "标准", "宽松"]
    private let themes: [TextReaderViewController.ReaderThemeMode] = [.light, .sepia, .dark, .ink]

    init(settings: TextReaderViewController.Settings, onChanged: @escaping (TextReaderViewController.Settings) -> Void) {
        self.settings = settings
        self.onChanged = onChanged
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.42)

        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped(_:)))
        dismissTap.cancelsTouchesInView = false
        view.addGestureRecognizer(dismissTap)

        panel.layer.cornerRadius = 16
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.clipsToBounds = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let handle = UIView()
        handle.backgroundColor = Palette.border
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "文字排版设置"
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        // Font row
        fontTitleLabel.text = "字体大小"
        fontTitleLabel.font = .systemFont(ofSize: 13)
        fontMinusButton.setTitle("A-", for: .normal)
        fontMinusButton.accessibilityLabel = "减小字号"
        fontMinusButton.accessibilityIdentifier = "text.reader.font.minus"
        fontMinusButton.layer.cornerRadius = 8
        fontMinusButton.layer.borderWidth = 1
        fontMinusButton.addTarget(self, action: #selector(decreaseFont), for: .touchUpInside)

        fontValueLabel.text = "\(settings.fontSize) pt"
        fontValueLabel.font = .systemFont(ofSize: 13, weight: .bold)
        fontValueLabel.textAlignment = .center
        fontValueLabel.accessibilityIdentifier = "text.reader.font.value"

        fontPlusButton.setTitle("A+", for: .normal)
        fontPlusButton.accessibilityLabel = "增大字号"
        fontPlusButton.accessibilityIdentifier = "text.reader.font.plus"
        fontPlusButton.layer.cornerRadius = 8
        fontPlusButton.layer.borderWidth = 1
        fontPlusButton.addTarget(self, action: #selector(increaseFont), for: .touchUpInside)

        let fontControls = UIStackView(arrangedSubviews: [fontMinusButton, fontValueLabel, fontPlusButton])
        fontControls.spacing = 8
        fontControls.alignment = .center
        fontMinusButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        fontMinusButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        fontValueLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true
        fontPlusButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        fontPlusButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let fontRow = UIStackView(arrangedSubviews: [fontTitleLabel, fontControls])
        fontRow.alignment = .center

        // Line height row
        lineTitleLabel.text = "行间距"
        lineTitleLabel.font = .systemFont(ofSize: 13)
        let lineGroup = UIStackView()
        lineGroup.spacing = 6
        lineGroup.distribution = .fillEqually
        for (i, label) in lineTitles.enumerated() {
            let btn = makeChoiceButton(title: label, id: "text.reader.lineHeight.\(i)")
            btn.tag = i
            btn.addTarget(self, action: #selector(selectLineHeight(_:)), for: .touchUpInside)
            lineButtons.append(btn)
            lineGroup.addArrangedSubview(btn)
        }
        let lineRow = UIStackView(arrangedSubviews: [lineTitleLabel, lineGroup])
        lineRow.alignment = .center
        lineTitleLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true

        // Theme row
        themeTitleLabel.text = "阅读背景"
        themeTitleLabel.font = .systemFont(ofSize: 13)
        let themeGroup = UIStackView()
        themeGroup.spacing = 6
        themeGroup.distribution = .fillEqually
        for (i, mode) in themes.enumerated() {
            let btn = makeChoiceButton(title: mode.title, id: "text.reader.theme.\(i)")
            btn.tag = mode.rawValue
            btn.addTarget(self, action: #selector(selectTheme(_:)), for: .touchUpInside)
            themeButtons.append(btn)
            themeGroup.addArrangedSubview(btn)
        }
        let themeRow = UIStackView(arrangedSubviews: [themeTitleLabel, themeGroup])
        themeRow.alignment = .center
        themeTitleLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true

        // Mode row
        modeTitleLabel.text = "阅读模式"
        modeTitleLabel.font = .systemFont(ofSize: 13)
        let scrollBtn = makeChoiceButton(title: "连续滚动", id: "text.reader.mode.scroll")
        scrollBtn.tag = 0
        scrollBtn.addTarget(self, action: #selector(selectReadingMode(_:)), for: .touchUpInside)
        let pagedBtn = makeChoiceButton(title: "水平翻页", id: "text.reader.mode.paged")
        pagedBtn.tag = 1
        pagedBtn.addTarget(self, action: #selector(selectReadingMode(_:)), for: .touchUpInside)
        modeButtons = [scrollBtn, pagedBtn]
        let modeGroup = UIStackView(arrangedSubviews: modeButtons)
        modeGroup.spacing = 6
        modeGroup.distribution = .fillEqually
        let modeRow = UIStackView(arrangedSubviews: [modeTitleLabel, modeGroup])
        modeRow.alignment = .center
        modeTitleLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let bodyStack = UIStackView(arrangedSubviews: [titleLabel, divider, fontRow, lineRow, themeRow, modeRow])
        bodyStack.axis = .vertical
        bodyStack.spacing = 12
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(handle)
        panel.addSubview(bodyStack)

        let panelFill = panel.widthAnchor.constraint(equalTo: view.widthAnchor)
        panelFill.priority = .defaultHigh

        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            panelFill,
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            handle.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            handle.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 32),
            handle.heightAnchor.constraint(equalToConstant: 4),

            bodyStack.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 12),
            bodyStack.leadingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bodyStack.trailingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bodyStack.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        refreshPalette()
    }

    private func makeChoiceButton(title: String, id: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12)
        btn.layer.cornerRadius = 8
        btn.layer.borderWidth = 1
        btn.accessibilityIdentifier = id
        btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return btn
    }

    private func refreshPalette() {
        let dark = settings.theme.isDarkAppearance
        let panelBg = settings.theme.panelBackgroundColor
        let fg: UIColor = dark ? UIColor(red: 0xE2 / 255, green: 0xE8 / 255, blue: 0xF0 / 255, alpha: 1) : UIColor(red: 0x1E / 255, green: 0x29 / 255, blue: 0x3B / 255, alpha: 1)
        let subFg: UIColor = dark ? UIColor(red: 0x94 / 255, green: 0xA3 / 255, blue: 0xB8 / 255, alpha: 1) : UIColor(red: 0x64 / 255, green: 0x74 / 255, blue: 0x8B / 255, alpha: 1)
        let ctrlBg: UIColor = dark ? UIColor(red: 0x25 / 255, green: 0x2A / 255, blue: 0x34 / 255, alpha: 1) : UIColor(red: 0xF1 / 255, green: 0xF5 / 255, blue: 0xF9 / 255, alpha: 1)
        let border: UIColor = dark ? UIColor(red: 0x33 / 255, green: 0x3A / 255, blue: 0x48 / 255, alpha: 1) : UIColor(red: 0xDC / 255, green: 0xE6 / 255, blue: 0xF0 / 255, alpha: 1)
        let selBg: UIColor = dark ? UIColor(red: 0x1E / 255, green: 0x3A / 255, blue: 0x52 / 255, alpha: 1) : UIColor(red: 0xE0 / 255, green: 0xF2 / 255, blue: 0xFE / 255, alpha: 1)
        let selBorder: UIColor = dark ? UIColor(red: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255, alpha: 1) : UIColor(red: 0x02 / 255, green: 0x84 / 255, blue: 0xC7 / 255, alpha: 1)
        let selFg: UIColor = dark ? UIColor(red: 0x7D / 255, green: 0xD3 / 255, blue: 0xFC / 255, alpha: 1) : UIColor(red: 0x03 / 255, green: 0x69 / 255, blue: 0xA1 / 255, alpha: 1)

        panel.backgroundColor = panelBg
        divider.backgroundColor = border
        titleLabel.textColor = fg
        fontValueLabel.textColor = fg
        fontValueLabel.text = "\(settings.fontSize) pt"
        for lbl in [fontTitleLabel, lineTitleLabel, themeTitleLabel, modeTitleLabel] {
            lbl.textColor = subFg
        }

        for btn in [fontMinusButton, fontPlusButton] {
            btn.backgroundColor = ctrlBg
            btn.layer.borderColor = border.cgColor
            btn.setTitleColor(fg, for: .normal)
        }

        func style(_ btn: UIButton, selected: Bool) {
            btn.backgroundColor = selected ? selBg : ctrlBg
            btn.layer.borderColor = (selected ? selBorder : border).cgColor
            btn.setTitleColor(selected ? selFg : fg, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: selected ? .bold : .regular)
        }

        for (i, btn) in lineButtons.enumerated() {
            style(btn, selected: abs(settings.lineHeight - lineValues[i]) < 0.05)
        }
        for (i, btn) in themeButtons.enumerated() {
            style(btn, selected: settings.theme == themes[i])
        }
        if modeButtons.count == 2 {
            style(modeButtons[0], selected: !settings.pagedMode)
            style(modeButtons[1], selected: settings.pagedMode)
        }
    }

    @objc private func backdropTapped(_ gesture: UITapGestureRecognizer) {
        let loc = gesture.location(in: view)
        if !panel.frame.contains(loc) {
            dismiss(animated: true)
        }
    }

    @objc private func decreaseFont() {
        guard settings.fontSize > 12 else { return }
        settings.fontSize -= 1
        refreshPalette()
        onChanged(settings)
    }

    @objc private func increaseFont() {
        guard settings.fontSize < 32 else { return }
        settings.fontSize += 1
        refreshPalette()
        onChanged(settings)
    }

    @objc private func selectLineHeight(_ sender: UIButton) {
        guard lineValues.indices.contains(sender.tag) else { return }
        settings.lineHeight = lineValues[sender.tag]
        refreshPalette()
        onChanged(settings)
    }

    @objc private func selectTheme(_ sender: UIButton) {
        guard let theme = TextReaderViewController.ReaderThemeMode(rawValue: sender.tag) else { return }
        settings.theme = theme
        refreshPalette()
        onChanged(settings)
    }

    @objc private func selectReadingMode(_ sender: UIButton) {
        settings.pagedMode = (sender.tag == 1)
        refreshPalette()
        onChanged(settings)
    }
}
