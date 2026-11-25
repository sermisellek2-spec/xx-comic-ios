import UIKit
import ImageIO
import ComicCore

private final class Mh18RuleBrowserBridge: RuleBrowserSession, @unchecked Sendable {
    private weak var session: Mh18BrowserSession?

    init(session: Mh18BrowserSession) {
        self.session = session
    }

    func fetch(_ urlString: String) throws -> String {
        let cancelToken = RuleCancelToken.current
        try cancelToken?.throwIfCancelled()
        guard let url = URL(string: urlString) else {
            throw RuleError("地址格式无效")
        }
        let sema = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<String, Error>?

        let task = Task { @MainActor [weak self] in
            do {
                guard let session = self?.session else {
                    throw RuleError("验证会话不可用")
                }
                let html = try await session.fetch(url)
                lock.lock()
                result = .success(html)
                lock.unlock()
            } catch {
                lock.lock()
                result = .failure(error)
                lock.unlock()
            }
            sema.signal()
        }

        let handle = try cancelToken?.register {
            task.cancel()
        }
        defer {
            handle?.close()
            task.cancel()
        }

        let deadline = Date(timeIntervalSinceNow: 15.0)
        if Thread.isMainThread {
            while sema.wait(timeout: .now()) == .timedOut {
                try cancelToken?.throwIfCancelled()
                if Date() >= deadline {
                    throw RuleError("验证会话请求超时")
                }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        } else {
            while sema.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
                try cancelToken?.throwIfCancelled()
                if Date() >= deadline {
                    throw RuleError("验证会话请求超时")
                }
            }
        }
        try cancelToken?.throwIfCancelled()

        lock.lock()
        let finalResult = result
        lock.unlock()

        switch finalResult {
        case .success(let html):
            return html
        case .failure(let error):
            if (error as? Mh18SourceError) == .verificationRequired {
                throw RuleError("RULE_VERIFICATION_REQUIRED:需要验证")
            }
            if error is CancellationError {
                throw RuleCancelledError("规则调用已取消")
            }
            throw error
        case .none:
            throw RuleError("验证会话未返回响应")
        }
    }
}

@MainActor
final class AppEnvironment {
    let preferences: ReaderPreferencesStore
    let defaults: UserDefaults
    let mh18BrowserSession: Mh18BrowserSession
    private let ruleBrowserBridge: Mh18RuleBrowserBridge
    private var activeForegroundDetailTokens = Set<UUID>()
    private var foregroundDetailIdleObservers: [UUID: () -> Void] = [:]
    var isForegroundDetailBusy: Bool { !activeForegroundDetailTokens.isEmpty }

    func beginForegroundDetailLoad() -> UUID {
        let token = UUID()
        activeForegroundDetailTokens.insert(token)
        return token
    }

    func endForegroundDetailLoad(_ token: UUID) {
        guard activeForegroundDetailTokens.remove(token) != nil else { return }
        if activeForegroundDetailTokens.isEmpty {
            let callbacks = Array(foregroundDetailIdleObservers.values)
            for callback in callbacks {
                callback()
            }
        }
    }

    @discardableResult
    func observeForegroundDetailIdle(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        foregroundDetailIdleObservers[id] = handler
        return id
    }

    func removeForegroundDetailIdleObserver(_ id: UUID) {
        foregroundDetailIdleObservers.removeValue(forKey: id)
    }

    let readingHabits: ReadingHabitTracker
    let usageStats: UsageStatsClient
    private var usageStatsTask: Task<Void, Never>?
    private var usageStatsGeneration = UUID()
    let library: LibraryStore
    let localLibrary: LocalLibrary
    let bookshelfGroupStore: BookshelfGroupStore
    let sourceGroupStore: SourceGroupStore
    let blacklistStore: ComicBlacklistStore
    let recommendProfileStore: RecommendProfileStore
    let recommendCandidatePool: RecommendCandidatePool
    let recommendHarvester: RecommendHarvester
    let diskCacheStore: ComicDiskCacheStore
    let imageCacheTrimmer: ImageDiskCacheTrimmer
    let detailSourceSearch = DetailSourceSearch()
    private var cachedSummariesList: [ComicSummary] = []
    private var cachedSummaryOrder: [String] = []
    var cachedDetails: [String: ComicDiskCacheStore.CachedDetailEntry] = [:]
    private var cachedDetailOrder: [String] = []
    private var cachedChapterPages: [String: ChapterPage] = [:]
    private var cachedChapterPageOrder: [String] = []
    private static let maxCachedSummaries = 240
    private static let maxCachedDetails = 160
    private static let maxCachedChapterPages = 40
    let favoriteUpdateCoordinator: FavoriteUpdateCoordinator
    let favoriteUpdateChecker: FavoriteUpdateChecker
    let folderBookmarkStore: FolderBookmarkStore
    let folderSyncCoordinator: LocalFolderSyncCoordinator
    private var folderSyncTask: Task<Void, Never>?
    private var folderSyncGeneration = UUID()
    private var folderObservers: [NSObjectProtocol] = []
    private var folderRecoveryNeeded = true
    private(set) var folderSynchronizationError: String?
    private let localSource: LocalComicSource
    let ruleCatalog: RuleCatalog
    let usesLegacyBuiltinSources: Bool
    private(set) var allSources: [any ComicSource]
    let sourcePreferences: SourcePreferences
    let downloadStore: DownloadStore
    let downloadLocations: DownloadStorageLocations
    let downloadRuntime: DownloadRuntime
    let networkMonitor: any NetworkMonitoring
    let responseCache = HTTPResponseCache()
    lazy var downloadLifecycle = DownloadLifecycleController(runtime: downloadRuntime)
    lazy var localDeletion = LocalDeletionController(environment: self)
    private let environmentSourceResolver: EnvironmentSourceResolver
    var sources: [any ComicSource] { sourcePreferences.enabledIDs.compactMap { id in allSources.first { $0.id == id } } }
    var searchSources: [any ComicSource] { sources.filter(\.supportsSearch) }
    var discoverySources: [any ComicSource] { sourceGroupStore.visibleSources(sources, idExtractor: \.id) }
    static let libraryChanged = Notification.Name("XXComic.libraryChanged")
    static let sourcesChanged = Notification.Name("XXComic.sourcesChanged")
    static let blacklistChanged = Notification.Name("XXComic.blacklistChanged")
    static let recommendProfileChanged = Notification.Name("XXComic.recommendProfileChanged")
    private static let legacyBuiltinEnabledKey = "source.legacyBuiltinEnabled"

    static func resolveLegacyBuiltinEnabled(defaults: UserDefaults, appDirectory: URL) -> Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--matrix-empty-sources") {
            return false
        }
        let env = ProcessInfo.processInfo.environment
        if args.contains("--ui-testing") || env["XCTestConfigurationFilePath"] != nil || env["XXCOMIC_NATIVE_TEST_HOST"] == "1" {
            return true
        }
        #endif
        if let saved = defaults.object(forKey: legacyBuiltinEnabledKey) as? Bool {
            return saved
        }
        let hasLegacyDefaults = defaults.object(forKey: "source.order") != nil
            || defaults.object(forKey: "theme.mode") != nil
            || defaults.object(forKey: "reader.page.mode") != nil
            || BuiltinSourceCatalog.activeIDs.contains { id in
                defaults.object(forKey: "source.\(id).enabled") != nil || defaults.data(forKey: "source.\(id).config") != nil
            }
        let hasLegacyLibrary = FileManager.default.fileExists(atPath: appDirectory.appendingPathComponent("library.json").path)
        let isUpgrade = hasLegacyDefaults || hasLegacyLibrary
        defaults.set(isUpgrade, forKey: legacyBuiltinEnabledKey)
        return isUpgrade
    }

    static func explicitlyConfiguredBuiltinIDs(in defaults: UserDefaults) -> [String] {
        BuiltinSourceCatalog.activeIDs.filter { id in
            if defaults.data(forKey: "source.\(id).config") != nil { return true }
            for alias in SourcePreferences.legacyAliases(for: id) where defaults.data(forKey: "source.\(alias).config") != nil {
                return true
            }
            return false
        }
    }

    static func computeAvailableSourceIDs(
        defaults: UserDefaults,
        usesLegacyBuiltinSources: Bool,
        ruleCatalog: RuleCatalog
    ) -> [String] {
        let builtinIDs = usesLegacyBuiltinSources ? BuiltinSourceCatalog.activeIDs : explicitlyConfiguredBuiltinIDs(in: defaults)
        let ruleIDs = ruleCatalog.entries()
            .filter { !$0.removed && !ruleCatalog.hidden($0.rule.id) }
            .map(\.rule.id)
        var seen = Set<String>()
        return (builtinIDs + ruleIDs).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func requiresVpn(sourceId: String) -> Bool {
        SourceVpnPolicy.requiresVpn(sourceId: sourceId, ruleCatalog: ruleCatalog)
    }

    func fetchAppRelease() async throws -> AppRelease {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments
        if flags.contains("--ui-testing"), flags.contains("--matrix-fixtures"), flags.contains("--matrix-update-fixture") {
            return try await AppUpdateChecker.shared.fetchRelease(url: URL(string: "http://127.0.0.1:8767/ios-release.json")!)
        }
        #endif
        return try await AppUpdateChecker.shared.fetchRelease()
    }

    static func createSources(
        preferences: SourcePreferences,
        browserSession: (any ComicBrowserSession)?,
        ruleCatalog: RuleCatalog? = nil
    ) -> [any ComicSource] {
        var result: [any ComicSource] = [
            Mh160ComicSource(config: preferences.config(for: "mh160") ?? SourceConfigDefaults.mh160()),
            GmhComicSource(config: preferences.config(for: "gmh") ?? SourceConfigDefaults.gmh()),
            Mh18ComicSource(config: preferences.config(for: "mh18") ?? SourceConfigDefaults.mh18(), browserSession: browserSession),
            MkzhanComicSource(config: preferences.config(for: "mkzhan") ?? SourceConfigDefaults.mkzhan()),
            HiperdexComicSource(config: preferences.config(for: "hiperdex") ?? SourceConfigDefaults.hiperdex()),
            ManhuaguiComicSource(config: preferences.config(for: "manhuagui") ?? SourceConfigDefaults.manhuagui()),
            D5d6ComicSource(config: preferences.config(for: "d5d6") ?? SourceConfigDefaults.d5d6()),
            ManbenComicSource(config: preferences.config(for: "manben") ?? SourceConfigDefaults.manben()),
            FiveUmComicSource(site: .manhuazhan, config: preferences.config(for: "manhuazhan") ?? SourceConfigDefaults.manhuazhan()),
            FiveUmComicSource(site: .bbyin, config: preferences.config(for: "bbyin") ?? SourceConfigDefaults.bbyin()),
            AntbywComicSource(config: preferences.config(for: "antbyw") ?? SourceConfigDefaults.antbyw()),
            CuimhComicSource(config: preferences.config(for: "cuimh") ?? SourceConfigDefaults.cuimh()),
            LiumanhuaComicSource(config: preferences.config(for: "liumanhua") ?? SourceConfigDefaults.liumanhua()),
            CopyMangaComicSource(config: preferences.config(for: "copy4000") ?? SourceConfigDefaults.copy4000()),
            ManwaComicSource(config: preferences.config(for: "manwa") ?? SourceConfigDefaults.manwa()),
            DingManhuaComicSource(config: preferences.config(for: "dingmanhua") ?? SourceConfigDefaults.dingmanhua()),
            DongmanLaComicSource(config: preferences.config(for: "dongmanla") ?? SourceConfigDefaults.dongmanla()),
            ZaimanhuaComicSource(config: preferences.config(for: "zaimanhua") ?? SourceConfigDefaults.zaimanhua()),
            GuaziComicSource(config: preferences.config(for: "guazi") ?? SourceConfigDefaults.guazi()),
            XinmanhuaComicSource(config: preferences.config(for: "xinmanhua") ?? SourceConfigDefaults.xinmanhua()),
            JmComicSource(config: preferences.config(for: "jmcomic") ?? SourceConfigDefaults.jmcomic(), browserSession: browserSession),
            Hanman18ComicSource(config: preferences.config(for: "hanman18") ?? SourceConfigDefaults.hanman18())
        ]
        for id in PublicSourceRegistry.ids() {
            let config = preferences.config(for: id) ?? PublicSourceRegistry.config(id)
            result.append(PublicSourceRegistry.create(config))
        }
        let active = BuiltinSourceCatalog.activeIDs.compactMap { id in result.first { $0.id == id } }
        let extraSources: [any ComicSource] = [
            KalamanhuaComicSource(config: preferences.config(for: "kalamanhua") ?? KalamanhuaComicSource.defaultConfig()),
            MangaDexComicSource(config: preferences.config(for: "mangadex") ?? MangaDexComicSource.defaultConfig()),
            XcomicComicSource(config: preferences.config(for: "xcomic") ?? XcomicComicSource.defaultConfig()),
            HipmhComicSource(config: preferences.config(for: "hipmh") ?? HipmhComicSource.defaultConfig()),
            GalleryComicSource(config: preferences.config(for: "nhentai") ?? GalleryComicSource.defaultConfig(id: "nhentai")),
            GalleryComicSource(config: preferences.config(for: "wnacg") ?? GalleryComicSource.defaultConfig(id: "wnacg"))
        ]
        var combined: [any ComicSource] = active
        var seenIDs = Set(combined.map(\.id))
        if let catalog = ruleCatalog {
            for entry in catalog.entries() where !entry.removed && !catalog.hidden(entry.rule.id) {
                guard let ruleSource = catalog.comicSource(entry.rule.id) ?? catalog.source(entry.rule.id) else { continue }
                if let existingIdx = combined.firstIndex(where: { $0.id == ruleSource.id }) {
                    if entry.enabled || !preferences.availableIDs.contains(ruleSource.id) || catalog.entry(for: ruleSource.id) != nil {
                        combined[existingIdx] = ruleSource
                    }
                } else if seenIDs.insert(ruleSource.id).inserted {
                    combined.append(ruleSource)
                }
            }
        }
        for src in extraSources where preferences.config(for: src.id) != nil && seenIDs.insert(src.id).inserted {
            combined.append(src)
        }
        return combined + [
            RetiredComicSource(id: "baozimh", name: "包子漫画（已移除）"),
            RetiredComicSource(id: "mhua5", name: "漫画屋（已下线）")
        ]
    }

    init(defaults: UserDefaults, storageDirectory: URL? = nil, forceFreshInstall: Bool = false) throws {
        self.defaults = defaults
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let suffix = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "XXComic-UITests" : "XXComic"
        let sessionBase = EpubUITestFixtures.sessionID.map {
            base.appendingPathComponent("UITestSessions", isDirectory: true).appendingPathComponent($0, isDirectory: true)
        } ?? base
        let appDir = storageDirectory ?? sessionBase.appendingPathComponent(suffix, isDirectory: true)
        if storageDirectory != nil || ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            ruleCatalog = RuleCatalog(directory: appDir.appendingPathComponent("source-rules", isDirectory: true))
        } else {
            ruleCatalog = RuleCatalog.shared
        }
        usesLegacyBuiltinSources = forceFreshInstall ? false : Self.resolveLegacyBuiltinEnabled(defaults: defaults, appDirectory: appDir)
        mh18BrowserSession = Mh18BrowserSession(defaults: defaults)
        let browserBridge = Mh18RuleBrowserBridge(session: mh18BrowserSession)
        ruleBrowserBridge = browserBridge
        for origin in ["https://18mh.org", "https://www.18mh.org", "https://18comic.vip", "https://18comic.org", "https://jmcomic-zzz.org", "https://jmcomic-zzz.one"] {
            try? RuleWebSessions.fallback(origin, browserBridge)
        }
        let initialAvailableIDs = Self.computeAvailableSourceIDs(
            defaults: defaults,
            usesLegacyBuiltinSources: usesLegacyBuiltinSources,
            ruleCatalog: ruleCatalog
        )
        sourcePreferences = SourcePreferences(defaults: defaults, defaultIDs: initialAvailableIDs, importableIDs: BuiltinSourceCatalog.activeIDs)
        for entry in ruleCatalog.entries() where !entry.removed && !ruleCatalog.hidden(entry.rule.id) {
            sourcePreferences.setEnabled(entry.enabled, id: entry.rule.id)
        }
        var available = Self.createSources(preferences: sourcePreferences, browserSession: mh18BrowserSession, ruleCatalog: ruleCatalog)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--matrix-fixtures"),
           !ProcessInfo.processInfo.arguments.contains("--matrix-empty-sources") {
            available = try MatrixUITestFixtures.sources(defaults: defaults)
        }
        #endif
        allSources = available
        preferences = ReaderPreferencesStore(defaults: defaults)
        let habits = ReadingHabitTracker()
        habits.restore(from: defaults)
        readingHabits = habits
        usageStats = UsageStatsClient(directory: storageDirectory != nil || ProcessInfo.processInfo.arguments.contains("--ui-testing") ? appDir : base)
        library = try LibraryStore(directory: appDir)
        localLibrary = try LocalLibrary(directory: appDir.appendingPathComponent("Local", isDirectory: true))
        localSource = LocalComicSource(library: localLibrary)
        let useAsyncGroupPersistence = storageDirectory == nil && !ProcessInfo.processInfo.arguments.contains("--ui-testing")
        bookshelfGroupStore = BookshelfGroupStore(
            file: appDir.appendingPathComponent("bookshelf_groups.json"),
            asyncPersistence: useAsyncGroupPersistence
        )
        bookshelfGroupStore.migrateLegacyDataIfNeeded(legacyOnlineFavorites: library.favorites.map(\.summary.comicId), legacyLocalBookIds: nil)
        sourceGroupStore = SourceGroupStore(directory: appDir)
        blacklistStore = ComicBlacklistStore(directory: appDir, asyncPersistence: useAsyncGroupPersistence)
        recommendProfileStore = RecommendProfileStore(directory: appDir, asyncPersistence: useAsyncGroupPersistence)
        recommendHarvester = RecommendHarvester(filesDir: appDir)
        recommendCandidatePool = recommendHarvester.candidatePool
        diskCacheStore = ComicDiskCacheStore(cacheDir: appDir.appendingPathComponent("comic_caches", isDirectory: true))
        imageCacheTrimmer = RemoteImageView.configureDiskCache(directory: RemoteImageView.diskCacheDirectory(in: appDir))

        let initialSummaries = diskCacheStore.readSummaries()
        cachedSummariesList = initialSummaries
        cachedSummaryOrder = initialSummaries.map { Self.detailCacheKey(sourceId: $0.sourceId, comicId: $0.comicId) }
        for entry in diskCacheStore.readDetailEntries() {
            let key = Self.detailCacheKey(sourceId: entry.summary.sourceId, comicId: entry.summary.comicId)
            cachedDetails[key] = entry
            cachedDetailOrder.append(key)
        }
        for page in diskCacheStore.readChapters() where !page.chapterId.isEmpty {
            cachedChapterPages[page.chapterId] = page
            cachedChapterPageOrder.append(page.chapterId)
        }

        let downloadsDir = appDir.appendingPathComponent("Downloads", isDirectory: true)
        downloadStore = try DownloadStore(directory: downloadsDir)
        downloadLocations = try DownloadStorageLocations(file: appDir.appendingPathComponent("download-locations.json"), privateDirectory: downloadsDir)
        let resolver = EnvironmentSourceResolver(sources: available, ruleCatalog: ruleCatalog)
        environmentSourceResolver = resolver
        RemoteImageView.imageUrlResolver = { [weak resolver] imageUrl, force in
            guard let resolver else { return imageUrl.components(separatedBy: "#")[0] }
            return try await resolver.resolveImageUrl(sourceId: "", imageUrl: imageUrl, force: force)
        }
        RemoteImageView.refererResolver = { [weak resolver] sourceId, url in
            guard let resolver else { return nil }
            let resolved = resolver.resolveReferer(sourceId: sourceId, chapterUrl: url)
            return resolved.isEmpty ? nil : resolved
        }
        downloadRuntime = DownloadRuntime(store: downloadStore, downloadsDirectory: downloadsDir, sourceResolver: resolver, storageLocations: downloadLocations)
        downloadRuntime.isWifiOnly = defaults.object(forKey: "downloads.wifiOnly") as? Bool ?? true

        favoriteUpdateCoordinator = FavoriteUpdateCoordinator(defaults: defaults)
        favoriteUpdateChecker = FavoriteUpdateChecker(
            library: library,
            coordinator: favoriteUpdateCoordinator,
            sourceProvider: { [weak resolver] id in
                resolver?.source(for: id)
            }
        )
        folderBookmarkStore = try FolderBookmarkStore(directory: appDir)
        folderSyncCoordinator = LocalFolderSyncCoordinator(
            store: folderBookmarkStore,
            library: localLibrary,
            isReadableImage: LocalImageProbe.isReadable
        )

        networkMonitor = SystemNetworkMonitor()
        downloadRuntime.updateNetworkStatus(isConnected: networkMonitor.isConnected, isWifi: networkMonitor.isWifi)
        networkMonitor.onStatusChange = { [weak downloadRuntime] isConnected, isWifi in
            #if DEBUG
            let flags = ProcessInfo.processInfo.arguments
            if flags.contains("--ui-testing"), flags.contains("--matrix-fixtures"), flags.contains("--matrix-download-network") {
                downloadRuntime?.updateNetworkStatus(isConnected: true, isWifi: true)
                return
            }
            #endif
            downloadRuntime?.updateNetworkStatus(isConnected: isConnected, isWifi: isWifi)
        }
        networkMonitor.start()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("--matrix-fixtures") {
                try MatrixUITestFixtures.seed(environment: self)
                try EpubUITestFixtures.seed(library: localLibrary)
            } else if ProcessInfo.processInfo.arguments.contains("--epub-fixtures") {
                try EpubUITestFixtures.seed(library: localLibrary)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--reader-ai-fixture") {
            var settings = preferences.load()
            settings.enhancementMode = ImageEnhancementPolicy.modeSmart
            settings.enhancementComparison = true
            preferences.save(settings)
        }
        #endif
        habits.onChange = { [weak habits, weak defaults] in
            guard let habits, let defaults else { return }
            habits.save(to: defaults)
        }
        downloadRuntime.onTaskCompleted = { [weak self] _ in
            Task { @MainActor [weak self] in
                // A repaired page keeps its file URL; discard images decoded before publication.
                RemoteImageView.clearMemoryCache()
                ReaderEnhancementEngine.shared.clearCache()
                self?.notifyLibraryChanged()
            }
        }

        folderObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.startFolderSynchronization() }
        })
        folderObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelFolderSynchronization()
                self?.bookshelfGroupStore.flush()
                self?.blacklistStore.flush()
                self?.recommendProfileStore.flush()
            }
        })
        startFolderSynchronization(recover: true)
        #if DEBUG
        if LinkedFolderUITestFixtures.enabled {
            Task { [weak self] in
                guard let self else { return }
                do { try await LinkedFolderUITestFixtures.seed(environment: self) }
                catch { self.folderSynchronizationError = "文件夹验收数据准备失败：" + error.localizedDescription; self.notifyLibraryChanged() }
            }
        }
        #endif
        downloadLifecycle.start()
    }

    deinit {
        folderSyncTask?.cancel()
        for token in folderObservers { NotificationCenter.default.removeObserver(token) }
        usageStatsTask?.cancel()
    }

    // MARK: - Blacklist & Visibility Helpers

    func visibleHistory() -> [LibraryEntry] {
        library.history.filter { !blacklistStore.isBlacklistedTitle($0.summary.title) }
    }

    func visibleFavorites() -> [LibraryEntry] {
        library.favorites.filter { !blacklistStore.isBlacklistedTitle($0.summary.title) }
    }

    func isRetiredSource(_ sourceId: String) -> Bool {
        RetiredComicSource.isBuiltinRetired(sourceId)
            || BuiltinSourceCatalog.retiredIDs.contains(sourceId)
            || ruleCatalog.isRetiredSource(sourceId)
    }

    func hasActiveDownloads(forTitle title: String) -> Bool {
        !matchingPausableBookIds(forTitle: title).isEmpty
    }

    private func matchingPausableBookIds(forTitle title: String) -> [String] {
        let targetKey = ComicTitleNormalizer.normalize(title)
        guard !targetKey.isEmpty else { return [] }
        var bookIds = Set<String>()
        for task in downloadStore.list() where DownloadModels.active(task.state) || task.state == .queued || task.state == .waitingNetwork {
            if let detail = downloadStore.snapshot(id: task.bookId),
               ComicTitleNormalizer.normalize(detail.summary.title) == targetKey {
                bookIds.insert(task.bookId)
            }
        }
        return Array(bookIds)
    }

    @discardableResult
    func addToBlacklist(
        title: String,
        sourceId: String,
        sourceName: String,
        comicId: String,
        coverUrl: String,
        pauseDownloads: Bool
    ) -> BlacklistEntry? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = ComicTitleNormalizer.normalize(trimmedTitle)
        guard !normalized.isEmpty else { return nil }

        let groupSummary: String
        if !comicId.isEmpty {
            let scope: BookshelfScope = sourceId == "local" ? .local : .online
            let customGroups = bookshelfGroupStore.getGroupsForComic(scope: scope, comicId: comicId)
                .filter { !$0.isBuiltin }
                .map(\.name)
            groupSummary = customGroups.joined(separator: "、")
        } else {
            groupSummary = ""
        }

        let resolvedSourceName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (allSources.first(where: { $0.id == sourceId })?.name ?? sourceId)
            : sourceName
        let entry = BlacklistEntry(
            normalizedTitle: normalized,
            displayTitle: trimmedTitle,
            coverUrl: coverUrl,
            comicId: comicId,
            sourceId: sourceId,
            sourceName: resolvedSourceName,
            originScope: sourceId == "local" ? "local" : "online",
            originLabel: resolvedSourceName,
            groupSummary: groupSummary,
            blacklistedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        guard blacklistStore.add(entry) else { return nil }
        if pauseDownloads {
            let bookIds = matchingPausableBookIds(forTitle: trimmedTitle)
            if !bookIds.isEmpty {
                downloadRuntime.pauseTasks(forBookIds: bookIds)
            }
        }
        NotificationCenter.default.post(name: Self.blacklistChanged, object: self)
        notifyLibraryChanged()
        return entry
    }

    @discardableResult
    func restoreFromBlacklist(normalizedTitle: String) -> Bool {
        let removed = blacklistStore.removeByNormalizedTitle(normalizedTitle)
        if removed {
            NotificationCenter.default.post(name: Self.blacklistChanged, object: self)
            notifyLibraryChanged()
        }
        return removed
    }

    @discardableResult
    func restoreFromBlacklist(normalizedTitles: [String]) -> Int {
        let count = blacklistStore.removeByNormalizedTitles(normalizedTitles)
        if count > 0 {
            NotificationCenter.default.post(name: Self.blacklistChanged, object: self)
            notifyLibraryChanged()
        }
        return count
    }

    @discardableResult
    func clearBlacklist() -> Int {
        let count = blacklistStore.clearAll()
        if count > 0 {
            NotificationCenter.default.post(name: Self.blacklistChanged, object: self)
            notifyLibraryChanged()
        }
        return count
    }

    // MARK: - Bounded Comic Disk Cache Helpers

    private static func detailCacheKey(sourceId: String, comicId: String) -> String {
        "\(sourceId)\n\(comicId)"
    }

    func cachedSummary(sourceId: String, comicId: String) -> ComicSummary? {
        cachedSummariesList.first { $0.sourceId == sourceId && $0.comicId == comicId }
    }

    func saveCachedSummary(_ summary: ComicSummary) {
        let key = Self.detailCacheKey(sourceId: summary.sourceId, comicId: summary.comicId)
        cachedSummariesList.removeAll { Self.detailCacheKey(sourceId: $0.sourceId, comicId: $0.comicId) == key }
        cachedSummaryOrder.removeAll { $0 == key }
        cachedSummariesList.append(summary)
        cachedSummaryOrder.append(key)
        while cachedSummariesList.count > Self.maxCachedSummaries, let oldest = cachedSummaryOrder.first {
            cachedSummaryOrder.removeFirst()
            cachedSummariesList.removeAll { Self.detailCacheKey(sourceId: $0.sourceId, comicId: $0.comicId) == oldest }
        }
        persistDiskCachesAsync()
    }

    func cachedDetail(sourceId: String, comicId: String) -> ComicDetail? {
        let key = Self.detailCacheKey(sourceId: sourceId, comicId: comicId)
        return cachedDetails[key]?.restoredWithRevisionCheck().detail
    }

    func saveCachedDetail(_ detail: ComicDetail) {
        let key = Self.detailCacheKey(sourceId: detail.summary.sourceId, comicId: detail.summary.comicId)
        let ruleVersion = ruleCatalog.entry(for: detail.summary.sourceId)?.rule.version
        let entry = ComicDiskCacheStore.CachedDetailEntry(detail: detail, sourceRuleVersion: ruleVersion)
        cachedDetails[key] = entry
        cachedDetailOrder.removeAll { $0 == key }
        cachedDetailOrder.append(key)
        while cachedDetailOrder.count > Self.maxCachedDetails {
            let evicted = cachedDetailOrder.removeFirst()
            cachedDetails.removeValue(forKey: evicted)
        }
        persistDiskCachesAsync()
    }

    func cachedChapterPage(chapterId: String) -> ChapterPage? {
        cachedChapterPages[chapterId]
    }

    func saveCachedChapterPage(_ page: ChapterPage) {
        guard !page.chapterId.isEmpty else { return }
        cachedChapterPages[page.chapterId] = page
        cachedChapterPageOrder.removeAll { $0 == page.chapterId }
        cachedChapterPageOrder.append(page.chapterId)
        while cachedChapterPageOrder.count > Self.maxCachedChapterPages {
            let evicted = cachedChapterPageOrder.removeFirst()
            cachedChapterPages.removeValue(forKey: evicted)
        }
        persistDiskCachesAsync()
    }

    func invalidateChapterCachesForUpdatedRules(_ updatedRuleIds: Set<String>) {
        var ruleVersions: [String: Int] = [:]
        for entry in ruleCatalog.entries() {
            ruleVersions[entry.rule.id] = entry.rule.version
        }
        var invalidatedChapterKeys = Set<String>()
        for key in cachedDetails.keys {
            guard let entry = cachedDetails[key] else { continue }
            if ComicDiskCacheStore.isLocalSourceOrComic(entry.detail) || entry.chapters.isEmpty { continue }
            let srcId = entry.summary.sourceId
            let newVer = ruleVersions[srcId] ?? 0
            let cachedVer = entry.sourceRuleVersion ?? 0
            if updatedRuleIds.contains(srcId) || (cachedVer > 0 && newVer > cachedVer) {
                for ch in entry.chapters {
                    if !ch.chapterId.isEmpty { invalidatedChapterKeys.insert(ch.chapterId) }
                    if !ch.url.isEmpty { invalidatedChapterKeys.insert(ch.url) }
                }
                var updated = entry
                updated.chapters = []
                updated.sourceRuleVersion = nil
                cachedDetails[key] = updated
            }
        }
        for key in invalidatedChapterKeys {
            cachedChapterPages.removeValue(forKey: key)
            cachedChapterPageOrder.removeAll { $0 == key }
        }
        let store = diskCacheStore
        let ids = updatedRuleIds
        let versions = ruleVersions
        Task.detached(priority: .utility) {
            store.invalidateDetailsAndChapters(forSourceIds: ids, ruleVersions: versions)
        }
    }

    private func persistDiskCachesAsync() {
        let summaries = cachedSummariesList
        let details = cachedDetailOrder.compactMap { cachedDetails[$0] }
        let chapters = cachedChapterPageOrder.compactMap { cachedChapterPages[$0] }
        let store = diskCacheStore
        Task.detached(priority: .utility) {
            try? store.writeSnapshots(summaries: summaries, details: details, chapters: chapters)
        }
    }

    // MARK: - Folder Sync & Library Mutations

    func cancelFolderSynchronization() {
        folderSyncGeneration = UUID()
        folderSyncTask?.cancel(); folderSyncTask = nil
    }

    func startFolderSynchronization(recover: Bool = false) {
        guard folderSyncTask == nil else { return }
        let token = UUID(); folderSyncGeneration = token
        let coordinator = folderSyncCoordinator
        let requiresRecovery = recover || folderRecoveryNeeded
        let worker = Task.detached(priority: .utility) {
            if requiresRecovery { try await coordinator.recoverInterruptedSyncs() }
            try Task.checkCancellation()
            return await coordinator.syncAll()
        }
        folderSyncTask = Task { [weak self] in
            defer { if self?.folderSyncGeneration == token { self?.folderSyncTask = nil } }
            do {
                let results = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, self.folderSyncGeneration == token, !Task.isCancelled else { return }
                self.folderSynchronizationError = nil
                self.folderRecoveryNeeded = false
                self.folderSynchronizationFinished(results)
            } catch is CancellationError {
                // An interrupted scan preserves the previous index and resumes on activation.
            } catch {
                guard let self, self.folderSyncGeneration == token, !Task.isCancelled else { return }
                self.folderSynchronizationError = "关联文件夹恢复失败：" + error.localizedDescription
                self.notifyLibraryChanged()
            }
        }
    }

    func folderSynchronizationFinished(_ results: [String: LocalFolderSyncCoordinator.SyncResult]) {
        if results.values.contains(where: { if case .updated = $0 { return true }; return false }) {
            RemoteImageView.clearMemoryCache(); ReaderEnhancementEngine.shared.clearCache()
        }
        if !results.isEmpty { notifyLibraryChanged() }
    }

    struct FavoriteUndoSnapshot {
        let comic: ComicSummary
        let previousEntry: LibraryEntry?
        let groupIds: Set<String>
    }

    struct SourceReplacementSnapshot {
        let original: ComicSummary
        let target: ComicSummary
        let originalEntry: LibraryEntry?
        let targetEntry: LibraryEntry?
        let originalGroupIds: Set<String>
        let targetGroupIds: Set<String>
    }

    func setFavorite(_ comic: ComicSummary, favorite: Bool) throws {
        try library.setFavorite(comic, favorite: favorite)
        if favorite {
            bookshelfGroupStore.addToScope(scope: .online, comicId: comic.comicId)
        } else {
            bookshelfGroupStore.removeComicFromAllGroups(scope: .online, comicId: comic.comicId)
            favoriteUpdateCoordinator.clearState(sourceId: comic.sourceId, comicId: comic.comicId)
        }
        notifyLibraryChanged()
    }

    func removeFavoriteWithSnapshot(_ comic: ComicSummary) throws -> FavoriteUndoSnapshot {
        let snapshot = FavoriteUndoSnapshot(
            comic: comic,
            previousEntry: library.entry(for: comic),
            groupIds: Set(bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: comic.comicId).map(\.id))
        )
        try setFavorite(comic, favorite: false)
        return snapshot
    }

    func restoreFavorite(_ snapshot: FavoriteUndoSnapshot) throws {
        if let previous = snapshot.previousEntry {
            try library.restoreEntries([(snapshot.comic, previous)])
        } else {
            try library.setFavorite(snapshot.comic, favorite: true)
        }
        bookshelfGroupStore.addToScope(scope: .online, comicId: snapshot.comic.comicId)
        if !snapshot.groupIds.isEmpty {
            bookshelfGroupStore.updateComicGroups(scope: .online, comicId: snapshot.comic.comicId, targetGroupIds: snapshot.groupIds)
        }
        notifyLibraryChanged()
    }

    func captureSourceReplacementSnapshot(original: ComicSummary, target: ComicSummary) -> SourceReplacementSnapshot {
        SourceReplacementSnapshot(
            original: original,
            target: target,
            originalEntry: library.entry(for: original),
            targetEntry: library.entry(for: target),
            originalGroupIds: Set(bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: original.comicId).map(\.id)),
            targetGroupIds: Set(bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: target.comicId).map(\.id))
        )
    }

    func undoSourceReplacement(_ snapshot: SourceReplacementSnapshot) throws {
        try library.restoreEntries([
            (snapshot.original, snapshot.originalEntry),
            (snapshot.target, snapshot.targetEntry)
        ])
        if snapshot.originalGroupIds.isEmpty {
            bookshelfGroupStore.removeComicFromAllGroups(scope: .online, comicId: snapshot.original.comicId)
        } else {
            bookshelfGroupStore.updateComicGroups(scope: .online, comicId: snapshot.original.comicId, targetGroupIds: snapshot.originalGroupIds)
        }
        if snapshot.targetGroupIds.isEmpty {
            bookshelfGroupStore.removeComicFromAllGroups(scope: .online, comicId: snapshot.target.comicId)
        } else {
            bookshelfGroupStore.updateComicGroups(scope: .online, comicId: snapshot.target.comicId, targetGroupIds: snapshot.targetGroupIds)
        }
        if snapshot.targetEntry?.isFavorite != true {
            favoriteUpdateCoordinator.clearState(sourceId: snapshot.target.sourceId, comicId: snapshot.target.comicId)
        }
        notifyLibraryChanged()
    }

    func replaceSource(original: ComicSummary, target: ComicDetail, matchingChapter: Chapter? = nil, matchingChapterIndex: Int = 0) throws {
        let oldGroups = bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: original.comicId).map(\.id)
        // Confirm the library transaction before changing independently saved
        // group/update state. A failed write must leave the old membership intact.
        try library.replaceSource(original: original, target: target.summary, matchingChapter: matchingChapter, matchingChapterIndex: matchingChapterIndex)
        var targetGroups = Set(oldGroups)
        for g in bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: target.summary.comicId) {
            targetGroups.insert(g.id)
        }
        bookshelfGroupStore.addToScope(scope: .online, comicId: target.summary.comicId)
        bookshelfGroupStore.updateComicGroups(scope: .online, comicId: target.summary.comicId, targetGroupIds: targetGroups)
        bookshelfGroupStore.removeComicFromAllGroups(scope: .online, comicId: original.comicId)

        favoriteUpdateCoordinator.clearState(sourceId: original.sourceId, comicId: original.comicId)
        if let rev = FavoriteRevision.fromDetail(target) {
            favoriteUpdateCoordinator.acknowledge(sourceId: target.summary.sourceId, comicId: target.summary.comicId, revision: rev)
        }

        notifyLibraryChanged()
    }

    func replaceSource(from original: ComicSummary, to target: ComicDetail, matchingChapter: Chapter? = nil, matchingChapterIndex: Int = 0) throws {
        try replaceSource(original: original, target: target, matchingChapter: matchingChapter, matchingChapterIndex: matchingChapterIndex)
    }

    func setSourceEnabled(_ enabled: Bool, id: String) {
        if ruleCatalog.entry(for: id) != nil {
            try? ruleCatalog.store().change(ids: [id], action: enabled ? "enable" : "disable")
            ruleCatalog.refresh()
        }
        sourcePreferences.setEnabled(enabled, id: id)
        reloadSources()
    }

    func reloadSources() {
        ruleCatalog.refresh()
        let nextAvailable = Self.computeAvailableSourceIDs(
            defaults: defaults,
            usesLegacyBuiltinSources: usesLegacyBuiltinSources,
            ruleCatalog: ruleCatalog
        )
        sourcePreferences.updateAvailableIDs(nextAvailable)
        for entry in ruleCatalog.entries() where !entry.removed && !ruleCatalog.hidden(entry.rule.id) {
            sourcePreferences.setEnabled(entry.enabled, id: entry.rule.id)
        }
        #if DEBUG
        // Test sources stay deterministic when settings or cache operations reload the registry,
        // unless --matrix-empty-sources is explicitly testing dynamic rule installation.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--matrix-fixtures"),
           !ProcessInfo.processInfo.arguments.contains("--matrix-empty-sources") {
            NotificationCenter.default.post(name: Self.sourcesChanged, object: self)
            return
        }
        #endif
        allSources = Self.createSources(preferences: sourcePreferences, browserSession: mh18BrowserSession, ruleCatalog: ruleCatalog)
        environmentSourceResolver.updateSources(allSources)
        NotificationCenter.default.post(name: Self.sourcesChanged, object: self)
    }

    func source(for comic: ComicSummary) -> (any ComicSource)? {
        if comic.sourceId == "local" {
            return localSource
        }
        if let found = allSources.first(where: { $0.id == comic.sourceId }) {
            return found
        }
        if RetiredComicSource.isBuiltinRetired(comic.sourceId) || ruleCatalog.isRetiredSource(comic.sourceId) {
            let retiredName = RetiredComicSource.builtinRetiredName(for: comic.sourceId)
                ?? ruleCatalog.retiredSourceName(comic.sourceId)
            return RetiredComicSource(id: comic.sourceId, name: retiredName.isEmpty ? comic.sourceId : retiredName)
        }
        return nil
    }

    func totalCacheBytes() async throws -> (memoryBytes: Int64, diskBytes: Int64, totalBytes: Int64) {
        let http = try await responseCache.usage()
        let diskStore = diskCacheStore
        let trimmer = imageCacheTrimmer
        let extraDisk = await Task.detached(priority: .utility) {
            diskStore.totalBytes() + trimmer.getTrackedBytes()
        }.value
        let combinedDisk = http.diskBytes + extraDisk
        return (memoryBytes: http.memoryBytes, diskBytes: combinedDisk, totalBytes: http.memoryBytes + combinedDisk)
    }

    func clearCaches() async throws -> HTTPResponseCacheUsage {
        try Task.checkCancellation()
        RemoteImageView.clearMemoryCache()
        ReaderEnhancementEngine.shared.clearCache()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        #if DEBUG
        let trace = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let started = ProcessInfo.processInfo.systemUptime
        if trace { print("CACHE_UI stage=begin") }
        #endif
        cachedSummariesList.removeAll()
        cachedSummaryOrder.removeAll()
        cachedDetails.removeAll()
        cachedDetailOrder.removeAll()
        cachedChapterPages.removeAll()
        cachedChapterPageOrder.removeAll()

        let diskStore = diskCacheStore
        let trimmer = imageCacheTrimmer
        let extraRemainingTask = Task.detached(priority: .utility) { () -> Int64 in
            _ = diskStore.clear()
            RemoteImageView.clearDiskCacheFiles(using: trimmer)
            return diskStore.totalBytes() + trimmer.getTrackedBytes()
        }

        async let browser: Void = try mh18BrowserSession.clearCache()
        async let http: HTTPResponseCacheUsage = responseCache.clear()
        let (_, httpRemaining, extraDisk) = try await (browser, http, extraRemainingTask.value)
        let remaining = HTTPResponseCacheUsage(
            memoryBytes: httpRemaining.memoryBytes,
            diskBytes: httpRemaining.diskBytes + extraDisk
        )
        #if DEBUG
        if trace { print("CACHE_UI stage=finished elapsed=\(ProcessInfo.processInfo.systemUptime - started) memory=\(remaining.memoryBytes) disk=\(remaining.diskBytes)") }
        #endif
        reloadSources()
        return remaining
    }

    func setUsageStatsEnabled(_ enabled: Bool) throws {
        try usageStats.setEnabled(enabled)
        if enabled { reportUsageStatsIfNeeded() }
        else { cancelUsageStatsReport() }
    }

    func reportUsageStatsIfNeeded() {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        let testEnvironment = ProcessInfo.processInfo.environment
        guard testEnvironment["XXCOMIC_NATIVE_TEST_HOST"] != "1", testEnvironment["XCTestConfigurationFilePath"] == nil else { return }
        #endif
        guard usageStatsTask == nil else { return }
        let info = UsageStatsApplicationInfo(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.56",
            versionCode: Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "356") ?? 356,
            osVersion: UIDevice.current.systemVersion, deviceModel: "Apple " + UIDevice.current.model)
        let client = usageStats
        let token = UUID(); usageStatsGeneration = token
        usageStatsTask = Task.detached(priority: .utility) { [weak self] in
            _ = await client.reportIfNeeded(info: info)
            await self?.finishUsageStatsReport(token)
        }
    }

    private func finishUsageStatsReport(_ token: UUID) { if usageStatsGeneration == token { usageStatsTask = nil } }
    func cancelUsageStatsReport() { usageStatsGeneration = UUID(); usageStatsTask?.cancel(); usageStatsTask = nil }
    func notifyLibraryChanged() { NotificationCenter.default.post(name: Self.libraryChanged, object: nil) }
}

final class EnvironmentSourceResolver: DownloadSourceResolverProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _sources: [any ComicSource]
    private let ruleCatalog: RuleCatalog

    init(sources: [any ComicSource], ruleCatalog: RuleCatalog = .shared) {
        self._sources = sources
        self.ruleCatalog = ruleCatalog
    }

    func updateSources(_ sources: [any ComicSource]) {
        lock.lock()
        _sources = sources
        lock.unlock()
    }

    private var sources: [any ComicSource] {
        lock.lock()
        defer { lock.unlock() }
        return _sources
    }

    func source(for id: String) -> (any ComicSource)? {
        lock.lock()
        defer { lock.unlock() }
        return _sources.first { $0.id == id }
    }

    func resolveChapter(sourceId: String, url: String) async throws -> ChapterPage {
        guard let source = sources.first(where: { $0.id == sourceId }) else {
            throw DownloadError.corruptedData("未找到站源: \(sourceId)")
        }
        return try await source.chapter(url: url)
    }

    func resolveReferer(sourceId: String, chapterUrl: String) -> String {
        if let source = sources.first(where: { $0.id == sourceId }) {
            if let failover = source as? FailoverComicSource {
                return failover.referer(forUrl: chapterUrl) ?? source.referer
            }
            if source is ScriptComicSource || PublicSourceRegistry.contains(sourceId) {
                return source.referer.isEmpty ? chapterUrl : source.referer
            }
            if sourceId == "baozimh" || sourceId == "mkzhan" || sourceId == "hiperdex" ||
               sourceId == "hanman18" || sourceId == "d5d6" || sourceId == "antbyw" ||
               sourceId == "xinmanhua" || sourceId == "zaimanhua" ||
               sourceId == "jmcomic" || chapterUrl.isEmpty {
                return source.referer
            }
            return chapterUrl
        }
        if sourceId.isEmpty, !chapterUrl.isEmpty, let host = URL(string: chapterUrl)?.host?.lowercased() {
            for src in sources {
                if let failover = src as? FailoverComicSource {
                    for member in failover.members where member.rule.allows(host) {
                        return failover.referer(forUrl: chapterUrl) ?? member.referer
                    }
                } else if let script = src as? ScriptComicSource, script.rule.allows(host) {
                    return script.referer
                }
            }
        }
        return ""
    }

    func resolveImageUrl(sourceId: String, imageUrl: String, force: Bool) async throws -> String {
        if RuleImages.isRule(imageUrl) {
            let catalog = ruleCatalog
            return try await Task.detached(priority: .userInitiated) {
                try RuleImages.resolve(catalog: catalog, tagged: imageUrl, force: force).taggedUrl
            }.value
        }
        let pubSourceId = PublicSourceImages.sourceId(imageUrl)
        if !pubSourceId.isEmpty, let pub = sources.first(where: { $0.id == pubSourceId }) as? PublicComicSource {
            return try await pub.resolveImageUrl(imageUrl, force: force)
        }
        if PublicSourceRegistry.contains(sourceId), let pub = sources.first(where: { $0.id == sourceId }) as? PublicComicSource {
            return try await pub.resolveImageUrl(imageUrl, force: force)
        }
        if imageUrl.contains("#xx-zai=") || sourceId == "zaimanhua" {
            if let zai = sources.first(where: { $0.id == "zaimanhua" }) as? ZaimanhuaComicSource {
                return try await zai.resolveImageUrl(imageUrl, force: force)
            }
        }
        return PublicSourceImages.strip(imageUrl)
    }

    func fetchCover(sourceId: String, coverUrl: String, destination: URL, check: @escaping () throws -> Void) async throws {
        try check()
        let fallbackRef = sources.first(where: { $0.id == sourceId })?.referer ?? ""
        let ruleInfo: (url: String, referer: String, headers: [String: String], cookieHeader: String?)?
        if RuleImages.isRule(coverUrl) {
            let catalog = ruleCatalog
            ruleInfo = try? await Task.detached(priority: .userInitiated) {
                try RuleImages.requestHeaders(catalog: catalog, tagged: coverUrl, fallbackReferer: fallbackRef)
            }.value
        } else {
            ruleInfo = nil
        }
        let cleanCoverUrl = ruleInfo?.url ?? RuleImages.strip(PublicSourceImages.strip(coverUrl))
        guard let url = URL(string: cleanCoverUrl) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let effectiveRef = ruleInfo?.referer ?? PublicSourceImages.referer(coverUrl, fallback: fallbackRef)
        if !effectiveRef.isEmpty {
            request.setValue(effectiveRef, forHTTPHeaderField: "Referer")
        }
        if let ruleInfo {
            if let cookieHeader = ruleInfo.cookieHeader, !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            for (k, v) in ruleInfo.headers {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        try check()
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }
        let destDir = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destDir.path) {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        if RuleImages.isRule(coverUrl) {
            let rawData = try Data(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            var decoded = try RuleImages.decode(rawData, tagged: coverUrl)
            if let tx = try? RuleImages.transformation(coverUrl), !tx.isEmpty,
               let src = CGImageSourceCreateWithData(decoded as CFData, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
               let restored = try? JmImageTransform.restore(cg, imageURL: coverUrl),
               let png = UIImage(cgImage: restored).pngData() {
                decoded = png
            }
            try decoded.write(to: destination, options: .atomic)
        } else if !PublicSourceImages.sourceId(coverUrl).isEmpty || PublicSourceRegistry.contains(sourceId) {
            let rawData = try Data(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            let decoded = try PublicSourceImages.decodeForSource(sourceId: sourceId, url: coverUrl, data: rawData)
            try decoded.write(to: destination, options: .atomic)
        } else if XinmanhuaImageDecoder.usesImageHost(coverUrl) {
            let rawData = try Data(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            let decoded = try XinmanhuaImageDecoder.decode(rawData)
            try decoded.write(to: destination, options: .atomic)
        } else if ManwaImageDecoder.usesImageHost(coverUrl) {
            let rawData = try Data(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            let decoded = try ManwaImageDecoder.decode(rawData)
            try decoded.write(to: destination, options: .atomic)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destination)
        }
    }
}

extension UIViewController {
    func showError(_ error: Error) {
        guard !(error is CancellationError), presentedViewController == nil else { return }
        let alert = UIAlertController(title: "操作失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
