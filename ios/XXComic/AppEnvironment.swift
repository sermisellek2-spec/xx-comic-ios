import UIKit
import ComicCore

@MainActor
final class AppEnvironment {
    let preferences: ReaderPreferencesStore
    let textPreferences: TextReaderPreferencesStore
    let defaults: UserDefaults
    let mh18BrowserSession: Mh18BrowserSession
    let readingHabits: ReadingHabitTracker
    let library: LibraryStore
    let localLibrary: LocalLibrary
    let bookshelfGroupStore: BookshelfGroupStore
    let sourceGroupStore: SourceGroupStore
    let favoriteUpdateCoordinator: FavoriteUpdateCoordinator
    let favoriteUpdateChecker: FavoriteUpdateChecker
    let folderBookmarkStore: FolderBookmarkStore
    let folderSyncCoordinator: LocalFolderSyncCoordinator
    private let localSource: LocalComicSource
    private(set) var allSources: [any ComicSource]
    let sourcePreferences: SourcePreferences
    let downloadStore: DownloadStore
    let downloadRuntime: DownloadRuntime
    let networkMonitor: any NetworkMonitoring
    private let environmentSourceResolver: EnvironmentSourceResolver
    var sources: [any ComicSource] { sourcePreferences.enabledIDs.compactMap { id in allSources.first { $0.id == id } } }
    var searchSources: [any ComicSource] { sources.filter(\.supportsSearch) }
    var discoverySources: [any ComicSource] { sourceGroupStore.visibleSources(sources, idExtractor: \.id) }
    var discoverySearchSources: [any ComicSource] { discoverySources.filter(\.supportsSearch) }
    static let libraryChanged = Notification.Name("XXComic.libraryChanged")
    static let sourcesChanged = Notification.Name("XXComic.sourcesChanged")

    static func createSources(preferences: SourcePreferences, browserSession: (any ComicBrowserSession)?) -> [any ComicSource] {
        var result: [any ComicSource] = [
            BaoziComicSource(config: preferences.config(for: "baozimh") ?? SourceConfigDefaults.baozi()),
            Mh160ComicSource(config: preferences.config(for: "mh160") ?? SourceConfigDefaults.mh160()),
            GmhComicSource(config: preferences.config(for: "gmh") ?? SourceConfigDefaults.gmh()),
            Mh18ComicSource(config: preferences.config(for: "mh18") ?? SourceConfigDefaults.mh18(), browserSession: browserSession),
            MkzhanComicSource(config: preferences.config(for: "mkzhan") ?? SourceConfigDefaults.mkzhan()),
            HiperdexComicSource(),
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
        return result
    }

    init(defaults: UserDefaults) throws {
        self.defaults = defaults
        mh18BrowserSession = Mh18BrowserSession(defaults: defaults)
        let defaultIDs = ["baozimh", "mh160", "gmh", "mh18", "mkzhan", "hiperdex", "hanman18", "manhuagui", "d5d6", "manben", "manhuazhan", "bbyin", "antbyw", "cuimh", "liumanhua", "copy4000", "manwa", "dingmanhua", "dongmanla", "zaimanhua", "guazi", "xinmanhua", "jmcomic"] + PublicSourceRegistry.ids()
        sourcePreferences = SourcePreferences(defaults: defaults, defaultIDs: defaultIDs)
        let available = Self.createSources(preferences: sourcePreferences, browserSession: mh18BrowserSession)
        allSources = available
        preferences = ReaderPreferencesStore(defaults: defaults)
        textPreferences = TextReaderPreferencesStore(defaults: defaults)
        let habits = ReadingHabitTracker()
        habits.restore(from: defaults)
        readingHabits = habits
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let suffix = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "XXComic-UITests" : "XXComic"
        let sessionBase = EpubUITestFixtures.sessionID.map {
            base.appendingPathComponent("UITestSessions", isDirectory: true).appendingPathComponent($0, isDirectory: true)
        } ?? base
        let appDir = sessionBase.appendingPathComponent(suffix, isDirectory: true)
        library = try LibraryStore(directory: appDir)
        localLibrary = try LocalLibrary(directory: appDir.appendingPathComponent("Local", isDirectory: true))
        localSource = LocalComicSource(library: localLibrary)
        bookshelfGroupStore = BookshelfGroupStore(file: appDir.appendingPathComponent("bookshelf_groups.json"))
        bookshelfGroupStore.migrateLegacyDataIfNeeded(legacyOnlineFavorites: library.favorites.map(\.summary.comicId), legacyLocalBookIds: nil)
        sourceGroupStore = SourceGroupStore(directory: appDir)
        let downloadsDir = appDir.appendingPathComponent("Downloads", isDirectory: true)
        downloadStore = try DownloadStore(directory: downloadsDir)
        let resolver = EnvironmentSourceResolver(sources: available)
        environmentSourceResolver = resolver
        RemoteImageView.imageUrlResolver = { [weak resolver] imageUrl, force in
            guard let resolver else { return imageUrl.components(separatedBy: "#")[0] }
            return try await resolver.resolveImageUrl(sourceId: "", imageUrl: imageUrl, force: force)
        }
        downloadRuntime = DownloadRuntime(store: downloadStore, downloadsDirectory: downloadsDir, sourceResolver: resolver)
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
            downloadRuntime?.updateNetworkStatus(isConnected: isConnected, isWifi: isWifi)
        }
        networkMonitor.start()

        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--epub-fixtures") {
            try EpubUITestFixtures.seed(library: localLibrary)
        }
        habits.onChange = { [weak habits, weak defaults] in
            guard let habits, let defaults else { return }
            habits.save(to: defaults)
        }
        downloadRuntime.onTaskCompleted = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.notifyLibraryChanged()
            }
        }

        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                let results = await self.folderSyncCoordinator.syncAll()
                let hasChanges = results.values.contains {
                    if case .updated = $0 { return true }
                    return false
                }
                if hasChanges {
                    await MainActor.run {
                        self.notifyLibraryChanged()
                    }
                }
            }
        }
        #endif
        let syncCoordinator = folderSyncCoordinator
        Task {
            await syncCoordinator.recoverInterruptedSyncs()
        }
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

    func replaceSource(original: ComicSummary, target: ComicDetail, matchingChapter: Chapter? = nil, matchingChapterIndex: Int = 0) throws {
        let oldGroups = bookshelfGroupStore.getGroupsForComic(scope: .online, comicId: original.comicId).map(\.id)
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

        try library.replaceSource(original: original, target: target.summary, matchingChapter: matchingChapter, matchingChapterIndex: matchingChapterIndex)
        notifyLibraryChanged()
    }

    func replaceSource(from original: ComicSummary, to target: ComicDetail, matchingChapter: Chapter? = nil, matchingChapterIndex: Int = 0) throws {
        try replaceSource(original: original, target: target, matchingChapter: matchingChapter, matchingChapterIndex: matchingChapterIndex)
    }

    func reloadSources() {
        allSources = Self.createSources(preferences: sourcePreferences, browserSession: mh18BrowserSession)
        environmentSourceResolver.updateSources(allSources)
    }

    func source(for comic: ComicSummary) -> (any ComicSource)? { comic.sourceId == "local" ? localSource : allSources.first { $0.id == comic.sourceId } }
    func notifyLibraryChanged() { NotificationCenter.default.post(name: Self.libraryChanged, object: nil) }
}

final class EnvironmentSourceResolver: DownloadSourceResolverProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _sources: [any ComicSource]

    init(sources: [any ComicSource]) {
        self._sources = sources
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
        if PublicSourceRegistry.contains(sourceId) {
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
        let cleanCoverUrl = PublicSourceImages.strip(coverUrl)
        guard let url = URL(string: cleanCoverUrl) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let fallbackRef = sources.first(where: { $0.id == sourceId })?.referer ?? ""
        let effectiveRef = PublicSourceImages.referer(coverUrl, fallback: fallbackRef)
        if !effectiveRef.isEmpty {
            request.setValue(effectiveRef, forHTTPHeaderField: "Referer")
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
        if !PublicSourceImages.sourceId(coverUrl).isEmpty || PublicSourceRegistry.contains(sourceId) {
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
