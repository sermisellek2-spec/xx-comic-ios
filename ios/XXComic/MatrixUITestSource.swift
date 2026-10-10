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
        return ["mh160", "copy4000", "gmh"].map { MatrixUITestSource(id: $0) }
    }

    static func seed(environment: AppEnvironment) throws {
        for source in environment.allSources {
            guard let fixture = source as? MatrixUITestSource else { continue }
            if fixture.id == "mh160" {
                for comic in fixture.comics { try environment.library.setFavorite(comic, favorite: true) }
                if let comic = fixture.comics.first {
                    try environment.library.saveReading(comic, chapter: fixture.chapterList[0], chapterIndex: 0, position: ReaderPosition(imageIndex: 0, offset: 0))
                }
            }
        }
        var preferences = environment.preferences.load()
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

struct MatrixUITestSource: ComicSource {
    let id: String
    var name: String { ["mh160": "漫画160", "copy4000": "拷贝漫画", "gmh": "G社漫画"][id] ?? id }
    var referer: String { "http://127.0.0.1:8767/" }
    var comics: [ComicSummary] {
        ["电锯人", "间谍过家家", "一人之下"].enumerated().map { index, title in
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
        try Task.checkCancellation()
        guard let comic = comics.first(where: { $0.comicId == comicId }) else { throw URLError(.resourceUnavailable) }
        return ComicDetail(summary: comic, author: "验收作者", status: "连载中", description: "确定性同内容漫画：用于页面、交互与离线下载验收。", latestChapter: "第6话", chapters: chapterList)
    }
    func chapters(comicId: String) async throws -> [Chapter] { try Task.checkCancellation(); return chapterList }
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
