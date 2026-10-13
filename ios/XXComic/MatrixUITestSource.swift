#if DEBUG
import UIKit
import Network
import ComicCore

/// Available only in an explicitly isolated Debug UI-test session.
@MainActor
enum MatrixUITestFixtures {
    private static var server: MatrixUITestHTTPServer?
    static func sources(defaults: UserDefaults) throws -> [any ComicSource] {
        server = try MatrixUITestHTTPServer(image: MatrixSharedFixture.png, defaults: defaults)
        let ids = ProcessInfo.processInfo.arguments.contains("--matrix-catalog-fixtures")
            ? BuiltinSourceCatalog.activeIDs : ["mh160", "copy4000", "gmh"]
        return ids.map { MatrixUITestSource(id: $0) }
    }

    static func seed(environment: AppEnvironment) throws {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--matrix-download-network") {
            environment.downloadRuntime.updateNetworkStatus(isConnected: true, isWifi: true)
        }
        if arguments.contains("--matrix-empty-group") || arguments.contains("--matrix-single-source-group") {
            let ids = arguments.contains("--matrix-empty-group") ? [] : ["mh160"]
            let group = try environment.sourceGroupStore.create(name: "验收发现分组", sourceIds: ids)
            try environment.sourceGroupStore.select(id: group.id)
        }
        if arguments.contains("--matrix-disabled-statistics") { try environment.usageStats.setEnabled(false) }
        if arguments.contains("--matrix-error-log-fixture"), !environment.defaults.bool(forKey: "ui.matrix.errors.seeded") {
            ErrorLogStore.shared.clear()
            ErrorLogStore.shared.append(title: "验收导入错误", detail: "文件校验失败\nAuthorization: Bearer TEST_AUTH_FIELD\nCookie: session=TEST_COOKIE_FIELD\nhttps://fixture.invalid/comic?token=TEST_TOKEN_FIELD")
            environment.defaults.set(true, forKey: "ui.matrix.errors.seeded")
        } else if !environment.defaults.bool(forKey: "ui.matrix.library.seeded") {
            ErrorLogStore.shared.clear()
        }
        for source in environment.allSources where !arguments.contains("--matrix-empty-library") && !environment.defaults.bool(forKey: "ui.matrix.library.seeded") {
            guard let fixture = source as? MatrixUITestSource else { continue }
            if fixture.id == "mh160" {
                for (index, comic) in fixture.comics.enumerated() {
                    try environment.library.setFavorite(comic, favorite: true, now: 1000 + Double(index))
                    environment.favoriteUpdateCoordinator.recordObserved(sourceId: comic.sourceId, comicId: comic.comicId,
                        revision: FavoriteRevision.fromChapters(latestChapterName: "第6话", chapters: fixture.chapterList))
                }
                if let comic = fixture.comics.first {
                    let index = MatrixSharedFixture.document.readChapterIndex
                    try environment.library.saveReading(comic, chapter: fixture.chapterList[index], chapterIndex: index, position: ReaderPosition(imageIndex: 0, offset: 0), now: 2000)
                }
            }
        }
        print("MATRIX_LIBRARY seeded=\(environment.defaults.bool(forKey: "ui.matrix.library.seeded")) favorites=\(environment.library.favorites.count) history=\(environment.library.history.count)")
        environment.defaults.set(true, forKey: "ui.matrix.library.seeded")
        if !environment.defaults.bool(forKey: "ui.matrix.preferences.seeded") {
            var preferences = environment.preferences.load()
            if arguments.contains("--matrix-paged-reader") { preferences.layout = .paged }
            if arguments.contains("--matrix-legacy-button-reader") {
                // Exercise the archived state that previously disabled page
                // navigation, through the real persistent preferences store.
                preferences.readingMode = .normal
                preferences.turnMode = .buttons
                environment.defaults.set(true, forKey: "reader.button.mode")
            }
            let originalPixels = arguments.contains("--matrix-reader-original")
            preferences.enhancementMode = originalPixels ? ImageEnhancementPolicy.modeOff : ImageEnhancementPolicy.modeSmart
            preferences.enhancementComparison = !originalPixels
            preferences.theme = ProcessInfo.processInfo.arguments.contains("--dark-mode") ? .dark : .light
            environment.preferences.save(preferences)
            environment.defaults.set(true, forKey: "ui.matrix.preferences.seeded")
        }
        seedCorruptDownloadIfRequested(environment: environment)
    }

    private static func seedCorruptDownloadIfRequested(environment: AppEnvironment) {
        let flags = ProcessInfo.processInfo.arguments
        let chapterIndex: Int
        if flags.contains("--matrix-corrupt-first-download") { chapterIndex = 0 }
        else if flags.contains("--matrix-corrupt-next-download") { chapterIndex = 1 }
        else { return }
        guard !environment.defaults.bool(forKey: "ui.matrix.corrupt.download.seeded"),
              let source = environment.allSources.first(where: { $0.id == "mh160" }) as? MatrixUITestSource,
              let comic = source.comics.first, source.chapterList.indices.contains(chapterIndex) else { return }
        let document = MatrixSharedFixture.document
        let detail = ComicDetail(summary: comic, author: document.author, status: document.status,
                                 description: document.description, latestChapter: document.latestChapter, chapters: source.chapterList)
        let chapter = detail.chapters[chapterIndex]
        let store = environment.downloadStore, locations = environment.downloadLocations
        let image = MatrixSharedFixture.png, referer = source.referer
        Task { [weak environment] in
            do {
                try await Task.detached(priority: .utility) {
                    let taskID = try DownloadModels.key(comic.sourceId, comic.comicId, chapter.chapterId)
                    let bookID = try DownloadModels.bookId(source: comic.sourceId, comic: comic.comicId)
                    let task = DownloadTask(id: taskID, bookId: bookID, sourceId: comic.sourceId, comicId: comic.comicId,
                                            chapterId: chapter.chapterId, title: chapter.title, url: chapter.url,
                                            totalPages: document.pagesPerChapter, donePages: document.pagesPerChapter,
                                            generation: 1, state: .completed)
                    try locations.prepare(task, comicTitle: comic.title)
                    let directory = try locations.chapterDirectory(task, create: true)
                    let hash = DownloadModels.sha256Hex(image)
                    let pages = try (0..<document.pagesPerChapter).map { index in
                        let file = directory.appendingPathComponent("\(index).img")
                        // Real owned files and metadata deliberately disagree on
                        // page zero. Production verification must detect this.
                        let bytes = index == 0 ? Data(image.prefix(12)) : image
                        try bytes.write(to: file, options: .atomic)
                        return DownloadPage(index: index, url: "\(referer)page-\(chapterIndex + 1)-\(index).png",
                                            path: "\(bookID)/\(taskID)/\(index).img", hash: hash, bytes: Int64(image.count))
                    }
                    store.saveSnapshot(detail); store.replacePages(task: taskID, pages: pages)
                    try store.saveConfirmedTask(task)
                }.value
                environment?.defaults.set(true, forKey: "ui.matrix.corrupt.download.seeded")
                environment?.notifyLibraryChanged()
            } catch {
                ErrorLogStore.shared.append(title: "损坏下载验收文件准备失败", error: error)
            }
        }
    }
}

private final class MatrixUITestHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "XXComic.UITest.HTTP")
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let holdDownloadOnce: Bool
    private let flags = ProcessInfo.processInfo.arguments
    private var updateRequests = 0
    private var heldConnections: [ObjectIdentifier: NWConnection] = [:]
    init(image: Data, defaults: UserDefaults) throws {
        self.defaults = defaults
        holdDownloadOnce = ProcessInfo.processInfo.arguments.contains("--matrix-held-download-once")
        listener = try NWListener(using: .tcp, on: 8767)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            self.receiveHeaders(connection, image: image, buffer: Data())
        }
        listener.start(queue: queue)
    }

    private func receiveHeaders(_ connection: NWConnection, image: Data, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] bytes, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var headers = buffer
            if let bytes { headers.append(bytes) }
            guard headers.count <= 16_384 else { connection.cancel(); return }
            guard headers.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if complete { connection.cancel() }
                else { self.receiveHeaders(connection, image: image, buffer: headers) }
                return
            }
            let request = String(decoding: headers, as: UTF8.self)
            if request.hasPrefix("GET /verification-catalog "), self.flags.contains("--verification-timeout-then-local-response") {
                let body = Data("<a href=\"/manga/fixture\"><img src=\"local.png\"><h3 class=\"cardtitle\">漫画验收</h3></a>".utf8)
                var reply = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                reply.append(body)
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            if request.hasPrefix("GET /ios-release.json ") {
                self.sendRelease(connection)
                return
            }
            if self.shouldHold(request) {
                let key = ObjectIdentifier(connection)
                self.lock.lock(); self.heldConnections[key] = connection; self.lock.unlock()
                // No fabricated progress: the real downloader must publish its
                // first page before this second HTTP response remains pending.
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, _, _ in
                    if let self {
                        self.lock.lock()
                        self.heldConnections.removeValue(forKey: key)
                        self.lock.unlock()
                    }
                    connection.cancel()
                }
                return
            }
            var response = Data("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(image.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(image)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func sendRelease(_ connection: NWConnection) {
        guard flags.contains("--matrix-update-fixture") else { connection.cancel(); return }
        lock.lock(); updateRequests += 1; let count = updateRequests; lock.unlock()
        if count == 1, flags.contains("--matrix-update-hold-once") {
            let key = ObjectIdentifier(connection)
            lock.lock(); heldConnections[key] = connection; lock.unlock()
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, _, _ in
                if let self { self.lock.lock(); self.heldConnections.removeValue(forKey: key); self.lock.unlock() }
                connection.cancel()
            }
            return
        }
        let fail = count == 1 && flags.contains("--matrix-update-fail-once")
        let current = flags.contains("--matrix-update-current")
        let release = AppRelease(versionName: current ? "2.0.40" : "2.0.41", versionCode: current ? 340 : 350,
                                 releaseNotes: "验收新版本说明", downloadUrl: "https://github.com/sermisellek2-spec/xx-comic-ios/releases/tag/2.0.41")
        guard let body = try? JSONEncoder().encode(release) else { connection.cancel(); return }
        let status = fail ? "503 Service Unavailable" : "200 OK"
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func shouldHold(_ request: String) -> Bool {
        guard holdDownloadOnce, request.hasPrefix("GET /page-1-1.png "), request.contains("CPU iPhone OS") else { return false }
        lock.lock(); defer { lock.unlock() }
        let key = "ui.matrix.download.held.consumed"
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        // This explicit Debug-only marker must survive the process termination
        // exercised by the recovery test. Download results are still real files.
        defaults.synchronize()
        return true
    }
    deinit {
        listener.cancel()
        for connection in heldConnections.values { connection.cancel() }
    }
}

private actor MatrixUITestRequests {
    private var details: [String: Int] = [:]
    private var directories: [String: Int] = [:]
    private var pages: [String: Int] = [:]
    func nextDetail(_ comicID: String) -> Int {
        details[comicID, default: 0] += 1
        return details[comicID]!
    }
    func nextDirectory(_ comicID: String) -> Int {
        directories[comicID, default: 0] += 1
        return directories[comicID]!
    }
    func hasRequestedDirectory(_ comicID: String) -> Bool { directories[comicID, default: 0] > 0 }
    func nextChapter(_ url: String) -> Int {
        pages[url, default: 0] += 1
        return pages[url]!
    }
}

struct MatrixUITestSource: ComicSource {
    let id: String
    private let requests = MatrixUITestRequests()
    var name: String { SourceConfigDefaults.defaultConfig(for: id)?.name ?? id }
    var supportsSearch: Bool { id != "cuimh" && id != "liumanhua" }
    var referer: String { "http://127.0.0.1:8767/" }
    var comics: [ComicSummary] {
        let titles = MatrixSharedFixture.document.titles + (ProcessInfo.processInfo.arguments.contains("--matrix-large-bookshelf") ? (4...36).map { "验收漫画\($0)" } : [])
        return titles.enumerated().map { index, title in
            ComicSummary(sourceId: id, comicId: "\(id)_comic_\(index)", title: title,
                         coverUrl: "\(referer)cover-\(index).png", subtitle: MatrixSharedFixture.document.subtitle, tags: MatrixSharedFixture.document.tags)
        }
    }
    var chapterList: [Chapter] {
        let count = ProcessInfo.processInfo.arguments.contains("--matrix-large-directory") ? 200 : MatrixSharedFixture.document.chapterCount
        return (1...count).map { Chapter(chapterId: "\(id)_chapter_\($0)", title: "第\($0)话", url: "\(referer)\(id)/chapter/\($0)") }
    }
    func latest(page: Int) async throws -> [ComicSummary] { try Task.checkCancellation(); return page == 1 ? comics : [] }
    func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try await Task.sleep(nanoseconds: 30_000_000)
        if (id == "gmh" && ProcessInfo.processInfo.arguments.contains("--matrix-switch-similar-title")) || (id != "mh160" && ProcessInfo.processInfo.arguments.contains("--matrix-switch-no-match")) {
            return [ComicSummary(sourceId: id, comicId: id + "_similar", title: keyword + "外传")]
        }
        return page == 1 ? comics.filter { $0.title.contains(keyword) } : []
    }
    func detail(comicId: String) async throws -> ComicDetail {
        let request = await requests.nextDetail(comicId)
        if id == "copy4000", request == 1, ProcessInfo.processInfo.arguments.contains("--matrix-switch-held-until-cancel") {
            while true { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        if id == "copy4000", request == 1, ProcessInfo.processInfo.arguments.contains("--matrix-initial-detail-after-directory") {
            // Hold only the initial request; download's detail completes first.
            // This scenario opens an unfavorited copy4000 discovery result, so
            // bookshelf auto-update cannot consume its first detail request.
            // Cancellation is checked on each suspension, including when no
            // directory is requested because the user has left the page.
            while !(await requests.hasRequestedDirectory(comicId)) {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        try Task.checkCancellation()
        guard let comic = comics.first(where: { $0.comicId == comicId }) else { throw URLError(.resourceUnavailable) }
        let fixture = MatrixSharedFixture.document
        let lazy = ProcessInfo.processInfo.arguments.contains("--matrix-lazy-directory") || (id == "copy4000" && ProcessInfo.processInfo.arguments.contains("--matrix-switch-empty-once"))
        return ComicDetail(summary: comic, author: fixture.author, status: fixture.status, description: fixture.description, latestChapter: fixture.latestChapter, chapters: lazy ? [] : chapterList)
    }
    func chapters(comicId: String) async throws -> [Chapter] {
        let request = await requests.nextDirectory(comicId)
        let flags = ProcessInfo.processInfo.arguments
        if id == "copy4000", request == 1, flags.contains("--matrix-switch-empty-once") { return [] }
        let holdCount = flags.contains("--matrix-directory-held-twice-until-cancel") ? 2 : (flags.contains("--matrix-directory-held-until-cancel") ? 1 : 0)
        if request <= holdCount {
            // A deterministic pending request lets XCTest verify actual cancellation,
            // independent of accessibility/animation timing on either simulator.
            while true { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        if ProcessInfo.processInfo.arguments.contains("--matrix-directory-delay") {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        try Task.checkCancellation()
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--matrix-empty-directory") || (request == 1 && arguments.contains("--matrix-directory-empty-once")) ? [] : chapterList
    }
    func chapter(url: String) async throws -> ChapterPage {
        try Task.checkCancellation()
        let number = URL(string: url)?.lastPathComponent ?? "1"
        let request = await requests.nextChapter(url)
        if number == "2", request == 1 {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--matrix-continuation-fail-once") {
                try await Task.sleep(nanoseconds: 100_000_000)
                throw URLError(.networkConnectionLost)
            }
            if arguments.contains("--matrix-continuation-held-once") {
                while true { try await Task.sleep(nanoseconds: 50_000_000) }
            }
        }
        try Task.checkCancellation()
        return ChapterPage(chapterId: "\(id)_chapter_\(number)", title: "第\(number)话", imageUrls: (0..<MatrixSharedFixture.document.pagesPerChapter).map { "\(referer)page-\(number)-\($0).png" })
    }
    func filterGroups() async throws -> [SourceFilterGroup] {
        let fixture = MatrixSharedFixture.document
        return [SourceFilterGroup(key: fixture.filterKey, label: fixture.filterLabel,
                                  options: fixture.filterOptions.map { SourceFilterOption(label: $0.label, value: $0.value) })]
    }
    func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { try await latest(page: page) }
}
#endif
