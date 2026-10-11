#if DEBUG
import UIKit
import Network
import ComicCore

/// Available only in an explicitly isolated Debug UI-test session.
@MainActor
enum MatrixUITestFixtures {
    private static var server: MatrixUITestHTTPServer?
    static func sources() throws -> [any ComicSource] {
        server = try MatrixUITestHTTPServer(image: MatrixSharedFixture.png)
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
        environment.defaults.set(true, forKey: "ui.matrix.library.seeded")
        if !environment.defaults.bool(forKey: "ui.matrix.preferences.seeded") {
            var preferences = environment.preferences.load()
            if arguments.contains("--matrix-paged-reader") { preferences.layout = .paged }
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
    init(image: Data) throws {
        listener = try NWListener(using: .tcp, on: 8767)
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue.global(qos: .utility))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, error in
                guard error == nil else { connection.cancel(); return }
                var response = Data("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(image.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(image)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
    }
    deinit { listener.cancel() }
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
        (1...MatrixSharedFixture.document.chapterCount).map { Chapter(chapterId: "\(id)_chapter_\($0)", title: "第\($0)话", url: "\(referer)\(id)/chapter/\($0)") }
    }
    func latest(page: Int) async throws -> [ComicSummary] { try Task.checkCancellation(); return page == 1 ? comics : [] }
    func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try await Task.sleep(nanoseconds: 30_000_000)
        return page == 1 ? comics.filter { $0.title.contains(keyword) } : []
    }
    func detail(comicId: String) async throws -> ComicDetail {
        let request = await requests.nextDetail(comicId)
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
        return ComicDetail(summary: comic, author: fixture.author, status: fixture.status, description: fixture.description, latestChapter: fixture.latestChapter, chapters: ProcessInfo.processInfo.arguments.contains("--matrix-lazy-directory") ? [] : chapterList)
    }
    func chapters(comicId: String) async throws -> [Chapter] {
        let request = await requests.nextDirectory(comicId)
        let flags = ProcessInfo.processInfo.arguments
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
