import Foundation
import ComicCore

final class SplitDetailSource: ComicSource, @unchecked Sendable {
    let id = "split-detail-probe"
    let name = "Probe"
    let referer = ""
    var count = 10
    var chapterCalls = 0
    func latest(page: Int) async throws -> [ComicSummary] { [] }
    func search(keyword: String, page: Int) async throws -> [ComicSummary] { [] }
    func filterGroups() async throws -> [SourceFilterGroup] { [] }
    func category(filters: [String:String], page: Int) async throws -> [ComicSummary] { [] }
    func detail(comicId: String) async throws -> ComicDetail {
        ComicDetail(summary: ComicSummary(sourceId: id, comicId: comicId, title: "Probe", coverUrl: ""), author: "", status: "", description: "", latestChapter: "", chapters: [])
    }
    func chapters(comicId: String) async throws -> [Chapter] {
        chapterCalls += 1
        return (1...count).map { Chapter(chapterId: "\($0)", title: "第\($0)话", url: "probe/\($0)", chapterSlot: $0) }
    }
    func chapter(url: String) async throws -> ChapterPage {
        ChapterPage(chapterId: "", title: "", nextPageUrl: "", imageUrls: [])
    }
}

@main struct RiskProbe {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xxcomic-review-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var findings: [String: Any] = [:]

        let external = root.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data([1]).write(to: external.appendingPathComponent("01.jpg"))
        let local = try LocalLibrary(directory: root.appendingPathComponent("Local"))
        let bookmarks = try FolderBookmarkStore(directory: root.appendingPathComponent("Bookmarks"))
        let sync = LocalFolderSyncCoordinator(store: bookmarks, library: local, isReadableImage: {_ in true})
        let record = try await sync.linkFolder(url: external)
        let before = try await local.series(id: record.seriesId)!
        let beforeChapters = try await local.chapters(for: before.id)
        let source = LocalComicSource(library: local)
        _ = try await source.chapter(url: beforeChapters[0].url)
        try Data([2]).write(to: external.appendingPathComponent("02.jpg"))
        _ = await sync.sync(id: record.id)
        let after = try await local.series(id: record.seriesId)!
        let afterChapters = try await local.chapters(for: after.id)
        var previousChapterStillReadable = true
        do { _ = try await source.chapter(url: beforeChapters[0].url) }
        catch { previousChapterStillReadable = false }
        findings["folderIdentity"] = ["seriesIdStable": before.id == after.id, "volumeIdStable": before.volumeIDs == after.volumeIDs, "chapterIdStable": beforeChapters[0].chapterId == afterChapters[0].chapterId, "previousChapterStillReadable": previousChapterStillReadable]

        // Inject a catalog write failure by replacing this probe's own catalog file with a directory.
        let catalog = await local.catalogStore.fileURL
        try FileManager.default.removeItem(at: catalog)
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        try Data([3]).write(to: external.appendingPathComponent("03.jpg"))
        let failureResult = await sync.sync(id: record.id)
        var previousVolumeStillReadable = true
        do { _ = try local.book(id: after.volumeIDs[0]) }
        catch { previousVolumeStillReadable = false }
        let afterFailure = try await local.series(id: record.seriesId)!
        findings["folderWriteFailure"] = ["result": String(describing: failureResult), "catalogStillReferencesPreviousVolume": afterFailure.volumeIDs == after.volumeIDs, "previousVolumeStillReadable": previousVolumeStillReadable]

        let library = try LibraryStore(directory: root.appendingPathComponent("FavoriteLibrary"))
        let updates = FavoriteUpdateCoordinator()
        let split = SplitDetailSource()
        try library.setFavorite(ComicSummary(sourceId: split.id, comicId: "book", title: "Probe", coverUrl: ""), favorite: true)
        let checker = FavoriteUpdateChecker(library: library, coordinator: updates, sourceProvider: { _ in split })
        _ = await checker.checkAllFavorites()
        split.count = 11
        _ = await checker.checkAllFavorites()
        findings["splitDetailUpdate"] = ["chapterEndpointCalls": split.chapterCalls, "badgeAfterNewChapter": updates.hasPendingUpdate(sourceId: split.id, comicId: "book")]
        let data = try JSONSerialization.data(withJSONObject: findings, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
