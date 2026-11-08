import UIKit
import ComicCore

@MainActor
final class AppEnvironment {
    let preferences: ReaderPreferencesStore
    let defaults: UserDefaults
    let mh18BrowserSession: Mh18BrowserSession
    let readingHabits: ReadingHabitTracker
    let usageStats: UsageStatsClient
    private var usageStatsTask: Task<Void, Never>?
    private var usageStatsGeneration = UUID()
    let library: LibraryStore
    let localLibrary: LocalLibrary
    let bookshelfGroupStore: BookshelfGroupStore
    let sourceGroupStore: SourceGroupStore
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
                guard let ruleSource = catalog.source(entry.rule.id) else { continue }
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
        let downloadsDir = appDir.appendingPathComponent("Downloads", isDirectory: true)
        downloadStore = try DownloadStore(directory: downloadsDir)
        downloadLocations = try DownloadStorageLocations(file: appDir.appendingPathComponent("download-locations.json"), privateDirectory: downloadsDir)
        let resolver = EnvironmentSourceResolver(sources: available, ruleCatalog: ruleCatalog)
        environmentSourceResolver = resolver
        RemoteImageView.imageUrlResolver = { [weak resolver] imageUrl, force in
            guard let resolver else { return imageUrl.components(separatedBy: "#")[0] }
            return try await resolver.resolveImageUrl(sourceId: "", imageUrl: imageUrl, force: force)
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

    func source(for comic: ComicSummary) -> (any ComicSource)? { comic.sourceId == "local" ? localSource : allSources.first { $0.id == comic.sourceId } }
    func clearCaches() async throws -> HTTPResponseCacheUsage {
        try Task.checkCancellation()
        RemoteImageView.clearMemoryCache()
        ReaderEnhancementEngine.shared.clearCache()
        #if DEBUG
        let trace = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let started = ProcessInfo.processInfo.systemUptime
        if trace { print("CACHE_UI stage=begin") }
        #endif
        async let browser: Void = try mh18BrowserSession.clearCache()
        async let http: HTTPResponseCacheUsage = responseCache.clear()
        let (_, remaining) = try await (browser, http)
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
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.47",
            versionCode: Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "347") ?? 347,
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
        guard let source = sources.first(where: { $0.id == sourceId }) else {
            return ""
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
            let decoded = try RuleImages.decode(rawData, tagged: coverUrl)
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
