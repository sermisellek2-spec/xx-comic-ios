import XCTest
@testable import ComicCore

private final class ProviderProbe: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var active = 0
    private var entries: [(URL, FileAccessCoordinator.Access)] = []
    private var action: ((URL, FileAccessCoordinator.Access) throws -> Void)?
    var isInsideAccessor: Bool { lock.lock(); defer { lock.unlock() }; return active != 0 }
    var events: [(URL, FileAccessCoordinator.Access)] { lock.lock(); defer { lock.unlock() }; return entries }
    func setAction(_ action: @escaping (URL, FileAccessCoordinator.Access) throws -> Void) {
        lock.lock(); defer { lock.unlock() }; self.action = action
    }
    var coordinator: FileAccessCoordinator {
        FileAccessCoordinator { [self] url, access, body in
            lock.lock(); defer { lock.unlock() }
            entries.append((url, access)); active += 1; defer { active -= 1 }
            try action?(url, access)
            try body(url)
        }
    }
}
private final class StagedPageFetcher: DownloadImageFetcherProtocol, @unchecked Sendable {
    let privateRoot: URL
    let probe: ProviderProbe
    var afterFetch: (() -> Void)?
    static let bytes = Data("real file-provider fixture bytes".utf8)
    init(privateRoot: URL, probe: ProviderProbe) { self.privateRoot = privateRoot; self.probe = probe }
    func fetch(sourceId: String, url: String, referer: String, destination: URL, check: @escaping () throws -> Void) async throws -> (bytes: Int64, hash: String) {
        guard destination.path.hasPrefix(privateRoot.path + "/"), !probe.isInsideAccessor else {
            throw DownloadError.corruptedData("Network fetching must use private staging outside provider accessors")
        }
        try check(); try Self.bytes.write(to: destination); try check(); afterFetch?()
        return (Int64(Self.bytes.count), DownloadModels.sha256Hex(Self.bytes))
    }
}
private struct ProviderSource: DownloadSourceResolverProtocol {
    let privateRootPath: String
    let probe: ProviderProbe
    let failCover: Bool
    func resolveChapter(sourceId: String, url: String) async throws -> ChapterPage {
        ChapterPage(chapterId: "chapter", title: "第一话", imageUrls: ["https://fixture.invalid/page"])
    }
    func resolveReferer(sourceId: String, chapterUrl: String) -> String { "" }
    func fetchCover(sourceId: String, coverUrl: String, destination: URL, check: @escaping () throws -> Void) async throws {
        guard destination.path.hasPrefix(privateRootPath + "/"), !probe.isInsideAccessor else {
            throw DownloadError.corruptedData("Cover fetching must not hold a provider accessor")
        }
        try check(); try Data("owned cover".utf8).write(to: destination); try check()
        if failCover { throw DownloadError.corruptedData("Incomplete cover response") }
    }
}

final class DownloadFileCoordinationTests: XCTestCase {
    private struct Fixture {
        let base: URL, privateRoot: URL, external: URL
        let probe: ProviderProbe, locations: DownloadStorageLocations, runtime: DownloadRuntime
        let fetcher: StagedPageFetcher, detail: ComicDetail, taskID: String, bookID: String
    }
    private func fixture(failCover: Bool = false) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let privateRoot = base.appendingPathComponent("private", isDirectory: true), external = base.appendingPathComponent("Files", isDirectory: true)
        try FileManager.default.createDirectory(at: privateRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let access = DownloadStorageLocations.BookmarkAccess(create: { Data($0.path.utf8) }, resolve: {
            guard let path = String(data: $0, encoding: .utf8) else { throw DownloadLocationError.invalidStore }
            return URL(fileURLWithPath: path, isDirectory: true)
        }, start: { _ in true }, stop: { _ in })
        let probe = ProviderProbe()
        let locations = try DownloadStorageLocations(file: base.appendingPathComponent("locations.json"), privateDirectory: privateRoot, access: access, coordinator: probe.coordinator)
        try locations.select(directory: external)
        let fetcher = StagedPageFetcher(privateRoot: privateRoot, probe: probe)
        let runtime = DownloadRuntime(store: try DownloadStore(directory: privateRoot), downloadsDirectory: privateRoot, imageFetcher: fetcher,
            sourceResolver: ProviderSource(privateRootPath: privateRoot.path, probe: probe, failCover: failCover), storageLocations: locations)
        let summary = ComicSummary(sourceId: "source", comicId: "comic", title: "作品", coverUrl: "https://fixture.invalid/cover")
        let detail = ComicDetail(summary: summary, author: "", status: "", description: "", latestChapter: "", chapters: [Chapter(chapterId: "chapter", title: "第一话", url: "https://fixture.invalid/chapter")])
        return Fixture(base: base, privateRoot: privateRoot, external: external, probe: probe, locations: locations, runtime: runtime, fetcher: fetcher,
            detail: detail, taskID: try DownloadModels.key("source", "comic", "chapter"), bookID: try DownloadModels.bookId(source: "source", comic: "comic"))
    }
    private func download(_ fixture: Fixture) async throws {
        let done = expectation(description: "Queue published files and completed")
        fixture.runtime.onTaskCompleted = { _ in done.fulfill() }
        try await fixture.runtime.enqueueWithLocation(detail: fixture.detail, selectedChapterIds: ["chapter"])
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(fixture.runtime.store.get(id: fixture.taskID)?.state, .completed)
    }
    private func pageURL(_ fixture: Fixture) throws -> URL {
        let chapter = try XCTUnwrap(fixture.runtime.localChapter(detail: fixture.detail, chapterIndex: 0))
        return try XCTUnwrap(chapter.imageUrls.first.flatMap(URL.init(string:)))
    }

    func testPageAndCoverStagePrivatelyThenCoordinatedFilesCanReadAndDelete() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.base) }
        try await download(f)
        let page = try pageURL(f), book = try f.locations.bookDirectory(bookID: f.bookID)
        XCTAssertTrue(page.path.hasPrefix(f.external.path + "/"))
        XCTAssertEqual(try f.runtime.offlineImageData(at: page), StagedPageFetcher.bytes)
        XCTAssertEqual(try Data(contentsOf: book.appendingPathComponent("cover.img")), Data("owned cover".utf8))
        XCTAssertTrue(f.probe.events.contains { $0.0.path == book.path && $0.1 == .read })
        XCTAssertTrue(f.probe.events.contains { $0.0.path == book.path && $0.1 == .write })
        try await f.runtime.deleteBook(bookId: f.bookID)
        XCTAssertTrue(f.probe.events.contains { $0.0.path == book.path && $0.1 == .delete })
        XCTAssertFalse(FileManager.default.fileExists(atPath: book.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.external.path))
        XCTAssertNil(f.runtime.store.get(id: f.taskID))
    }

    func testProviderRefusesPublicationKeepsOldBytesAndReportsFailedTask() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.base) }
        try await download(f)
        let page = try pageURL(f), book = try f.locations.bookDirectory(bookID: f.bookID)
        let previous = Data("damaged bytes that must survive a failed replacement".utf8)
        try previous.write(to: page)
        let probe = f.probe
        f.fetcher.afterFetch = {
            probe.setAction { url, mode in
                if url.path == book.path && mode == .write { throw DownloadLocationError.permissionRequired("Files") }
            }
        }
        f.runtime.onTaskCompleted = { _ in XCTFail("Denied publication cannot become a completed download") }
        var task = try XCTUnwrap(f.runtime.store.get(id: f.taskID)); task.state = .queued; f.runtime.store.save(task: task)
        f.runtime.kick()
        for _ in 0..<200 {
            if f.runtime.store.get(id: f.taskID)?.state == .failed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(f.runtime.store.get(id: f.taskID)?.state, .failed)
        XCTAssertTrue(f.runtime.store.get(id: f.taskID)?.error.contains("重新授权") == true)
        XCTAssertEqual(try Data(contentsOf: page), previous)
        XCTAssertEqual(f.runtime.store.pages(task: f.taskID).count, 1)
    }

    func testUnknownFileAppearingWhileWaitingForDeletionPreventsRemoval() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.base) }
        try await download(f)
        let book = try f.locations.bookDirectory(bookID: f.bookID), original = book.appendingPathComponent("用户原文件.txt")
        f.probe.setAction { url, mode in
            if url.path == book.path && mode == .delete { try Data("keep original".utf8).write(to: original) }
        }
        do { try await f.runtime.deleteBook(bookId: f.bookID); XCTFail("Deletion must validate inside its accessor") } catch { }
        XCTAssertEqual(try Data(contentsOf: original), Data("keep original".utf8))
        XCTAssertEqual(f.runtime.store.get(id: f.taskID)?.state, .completed)
    }

    func testPageReplacedBySymlinkWhileWaitingForReadCannotExposeOriginal() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.base) }
        try await download(f)
        let page = try pageURL(f), book = try f.locations.bookDirectory(bookID: f.bookID)
        let original = f.base.appendingPathComponent("original"); try StagedPageFetcher.bytes.write(to: original)
        f.probe.setAction { url, mode in
            if url.path == book.path && mode == .read {
                try FileManager.default.removeItem(at: page)
                try FileManager.default.createSymbolicLink(at: page, withDestinationURL: original)
            }
        }
        XCTAssertThrowsError(try f.runtime.offlineImageData(at: page))
        XCTAssertEqual(try Data(contentsOf: original), StagedPageFetcher.bytes)
        XCTAssertEqual(f.runtime.store.get(id: f.taskID)?.state, .completed)
    }

    func testOfflineReadReportsProviderDenialWithoutDroppingCompletedRecords() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.base) }
        try await download(f)
        let page = try pageURL(f), book = try f.locations.bookDirectory(bookID: f.bookID)
        f.probe.setAction { url, mode in
            if url.path == book.path && mode == .read { throw DownloadLocationError.permissionRequired("Files") }
        }
        XCTAssertThrowsError(try f.runtime.offlineImageData(at: page)) { error in XCTAssertTrue(error.localizedDescription.contains("重新授权")) }
        XCTAssertEqual(f.runtime.store.get(id: f.taskID)?.state, .completed)
        XCTAssertEqual(try Data(contentsOf: page), StagedPageFetcher.bytes)
    }

    func testCoverNetworkFailureDoesNotPublishPartialCoverOrInvalidateChapter() async throws {
        let f = try fixture(failCover: true); defer { try? FileManager.default.removeItem(at: f.base) }
        try await download(f)
        let page = try pageURL(f), book = try f.locations.bookDirectory(bookID: f.bookID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: book.appendingPathComponent("cover.img").path))
        XCTAssertEqual(try f.runtime.offlineImageData(at: page), StagedPageFetcher.bytes)
    }

    func testOfflineReaderRejectsUnrecordedFilesAndSameSizeChangedBytes() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.base) }
        try await download(f)
        let page = try pageURL(f), book = try f.locations.bookDirectory(bookID: f.bookID)
        let original = book.appendingPathComponent("original.img"); try StagedPageFetcher.bytes.write(to: original)
        XCTAssertThrowsError(try f.runtime.offlineImageData(at: original))
        try Data(repeating: 0, count: StagedPageFetcher.bytes.count).write(to: page)
        XCTAssertThrowsError(try f.runtime.offlineImageData(at: page))
        XCTAssertEqual(try Data(contentsOf: original), StagedPageFetcher.bytes)
    }

    func testCompletedChapterCanRedownloadDamagedBytesWithSameLocationAndIdentity() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.base) }
        try await download(f)
        let page = try pageURL(f), previous = try XCTUnwrap(f.runtime.store.get(id: f.taskID))
        try Data("corrupt".utf8).write(to: page)
        XCTAssertThrowsError(try f.runtime.offlineImageData(at: page))
        try f.locations.useDefault()
        let completed = expectation(description: "Redownload repaired the original chapter")
        f.runtime.onTaskCompleted = { _ in completed.fulfill() }
        try await f.runtime.redownloadChapter(id: f.taskID)
        await fulfillment(of: [completed], timeout: 5)
        let repaired = try XCTUnwrap(f.runtime.store.get(id: f.taskID))
        XCTAssertEqual(repaired.state, .completed); XCTAssertNotEqual(repaired.generation, previous.generation)
        XCTAssertEqual(repaired.bookId, previous.bookId); XCTAssertEqual(repaired.chapterId, previous.chapterId)
        XCTAssertEqual(try pageURL(f), page)
        XCTAssertEqual(try f.runtime.offlineImageData(at: page), StagedPageFetcher.bytes)
        XCTAssertEqual(f.runtime.store.pages(task: f.taskID).count, 1)
    }

    func testRedownloadCannotDeleteAnUnknownOriginalInsideItsChapter() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.base) }
        try await download(f)
        let page = try pageURL(f), original = page.deletingLastPathComponent().appendingPathComponent("original.txt")
        try Data("keep original".utf8).write(to: original)
        do { try await f.runtime.redownloadChapter(id: f.taskID); XCTFail("Redownload uses the same precise deletion protection") } catch { }
        XCTAssertEqual(f.runtime.store.get(id: f.taskID)?.state, .completed)
        XCTAssertEqual(try f.runtime.offlineImageData(at: page), StagedPageFetcher.bytes)
        XCTAssertEqual(try Data(contentsOf: original), Data("keep original".utf8))
    }

    func testStartupCleanupOnlyRemovesConfirmedStagingAndPreservesUserPartFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DownloadStore(directory: root)
        let task = DownloadTask(id: try DownloadModels.key("source", "comic", "chapter"), bookId: try DownloadModels.bookId(source: "source", comic: "comic"), sourceId: "source", comicId: "comic", chapterId: "chapter", generation: 42, state: .completed)
        store.save(task: task)
        let stage = root.appendingPathComponent("stage_" + task.id + "_41", isDirectory: true)
        let unknown = root.appendingPathComponent("stage_" + task.id + "_40", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: stage.appendingPathComponent("0.part"))
        let original = root.appendingPathComponent("original.part"), nested = unknown.appendingPathComponent("original.part")
        try Data("keep".utf8).write(to: original); try Data("keep nested".utf8).write(to: nested)
        let runtime = DownloadRuntime(store: store, downloadsDirectory: root)
        for _ in 0..<200 {
            if !FileManager.default.fileExists(atPath: stage.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.path))
        XCTAssertEqual(try Data(contentsOf: original), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: nested), Data("keep nested".utf8))
        XCTAssertEqual(runtime.store.get(id: task.id)?.state, .completed)
    }
}
