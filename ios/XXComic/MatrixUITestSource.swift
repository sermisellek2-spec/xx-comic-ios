#if DEBUG
import UIKit
import Network
import ComicCore

/// Available only in an explicitly isolated Debug UI-test session.
@MainActor
enum MatrixUITestFixtures {
    private static var server: MatrixUITestHTTPServer?
    static func sources() throws -> [any ComicSource] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 384, height: 384), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 384, height: 384))
            UIColor.black.setStroke(); context.cgContext.setLineWidth(3)
            context.cgContext.stroke(CGRect(x: 20, y: 20, width: 344, height: 344))
            for n in 0..<8 {
                UIColor(hue: CGFloat(n) / 8, saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
                context.fill(CGRect(x: 40 + n * 36, y: 90, width: 24, height: 170))
            }
            ("XX Comic 2.0.40" as NSString).draw(at: CGPoint(x: 40, y: 300), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.black])
        }
        guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        server = try MatrixUITestHTTPServer(image: png)
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
        for source in environment.allSources where !arguments.contains("--matrix-empty-library") {
            guard let fixture = source as? MatrixUITestSource else { continue }
            if fixture.id == "mh160" {
                for comic in fixture.comics {
                    try environment.library.setFavorite(comic, favorite: true)
                    environment.favoriteUpdateCoordinator.recordObserved(sourceId: comic.sourceId, comicId: comic.comicId,
                        revision: FavoriteRevision.fromChapters(latestChapterName: "第6话", chapters: fixture.chapterList))
                }
                if let comic = fixture.comics.first {
                    try environment.library.saveReading(comic, chapter: fixture.chapterList[0], chapterIndex: 0, position: ReaderPosition(imageIndex: 0, offset: 0))
                }
            }
        }
        var preferences = environment.preferences.load()
        if arguments.contains("--matrix-paged-reader") { preferences.layout = .paged }
        preferences.enhancementMode = ImageEnhancementPolicy.modeSmart
        preferences.enhancementComparison = true
        preferences.theme = ProcessInfo.processInfo.arguments.contains("--dark-mode") ? .dark : .light
        environment.preferences.save(preferences)
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
    func nextDetail(_ comicID: String) -> Int {
        details[comicID, default: 0] += 1
        return details[comicID]!
    }
    func nextDirectory(_ comicID: String) -> Int {
        directories[comicID, default: 0] += 1
        return directories[comicID]!
    }
    func hasRequestedDirectory(_ comicID: String) -> Bool { directories[comicID, default: 0] > 0 }
}

struct MatrixUITestSource: ComicSource {
    let id: String
    private let requests = MatrixUITestRequests()
    var name: String { SourceConfigDefaults.defaultConfig(for: id)?.name ?? id }
    var supportsSearch: Bool { id != "cuimh" && id != "liumanhua" }
    var referer: String { "http://127.0.0.1:8767/" }
    var comics: [ComicSummary] {
        let titles = ["电锯人", "间谍过家家", "一人之下"] + (ProcessInfo.processInfo.arguments.contains("--matrix-large-bookshelf") ? (4...36).map { "验收漫画\($0)" } : [])
        return titles.enumerated().map { index, title in
            ComicSummary(sourceId: id, comicId: "\(id)_comic_\(index)", title: title,
                         coverUrl: "\(referer)cover-\(index).png", subtitle: "第3话", tags: ["连载中"])
        }
    }
    var chapterList: [Chapter] {
        (1...6).map { Chapter(chapterId: "\(id)_chapter_\($0)", title: "第\($0)话", url: "\(referer)\(id)/chapter/\($0)") }
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
        return ComicDetail(summary: comic, author: "验收作者", status: "连载中", description: "确定性同内容漫画：用于页面、交互与离线下载验收。", latestChapter: "第6话", chapters: ProcessInfo.processInfo.arguments.contains("--matrix-lazy-directory") ? [] : chapterList)
    }
    func chapters(comicId: String) async throws -> [Chapter] {
        let request = await requests.nextDirectory(comicId)
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
        return ChapterPage(chapterId: "\(id)_chapter_\(number)", title: "第\(number)话", imageUrls: (0..<4).map { "\(referer)page-\(number)-\($0).png" })
    }
    func filterGroups() async throws -> [SourceFilterGroup] {
        [SourceFilterGroup(key: "genre", label: "类型", options: [SourceFilterOption(label: "全部", value: ""), SourceFilterOption(label: "热血", value: "hot")])]
    }
    func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { try await latest(page: page) }
}
#endif
