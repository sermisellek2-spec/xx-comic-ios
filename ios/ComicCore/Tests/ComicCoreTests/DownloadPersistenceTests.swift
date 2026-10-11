import XCTest
@testable import ComicCore

private final class DownloadWriteBlocker: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private var original: Data?
    init(file: URL) { self.file = file }
    func block() throws {
        lock.lock(); defer { lock.unlock() }
        guard original == nil else { return }
        original = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    }
    func restore() throws {
        lock.lock(); defer { lock.unlock() }
        guard let original else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              try FileManager.default.contentsOfDirectory(atPath: file.path).isEmpty else {
            throw DownloadStoreError.persistenceFailed
        }
        try FileManager.default.removeItem(at: file)
        try original.write(to: file, options: .atomic)
        self.original = nil
    }
}

private let persistencePNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!

private actor PersistenceFetcher: DownloadImageFetcherProtocol {
    private let blocker: DownloadWriteBlocker?
    private var counts: [String: Int] = [:]
    init(blocker: DownloadWriteBlocker? = nil) { self.blocker = blocker }
    func fetch(sourceId: String, url: String, referer: String, destination: URL, check: @escaping () throws -> Void) async throws -> (bytes: Int64, hash: String) {
        try check()
        counts[url, default: 0] += 1
        if url.hasSuffix("second.png"), counts[url] == 1 { try blocker?.block() }
        try persistencePNG.write(to: destination)
        return (Int64(persistencePNG.count), DownloadModels.sha256Hex(persistencePNG))
    }
    func count(_ url: String) -> Int { counts[url, default: 0] }
}

private struct PersistenceResolver: DownloadSourceResolverProtocol {
    func resolveChapter(sourceId: String, url: String) async throws -> ChapterPage {
        ChapterPage(chapterId: "chapter", title: "第一话", imageUrls: ["https://fixture.invalid/first.png", "https://fixture.invalid/second.png"])
    }
    func resolveReferer(sourceId: String, chapterUrl: String) -> String { "" }
    func fetchCover(sourceId: String, coverUrl: String, destination: URL, check: @escaping () throws -> Void) async throws { try check() }
}

final class DownloadPersistenceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("download-write-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }
    private func detail() -> ComicDetail {
        ComicDetail(summary: ComicSummary(sourceId: "fixture", comicId: "comic", title: "下载保存验收"),
                    author: "验收作者", status: "连载中", description: "真实文件与持久记录", latestChapter: "第一话",
                    chapters: [Chapter(chapterId: "chapter", title: "第一话", url: "https://fixture.invalid/chapter")])
    }
    private func task(state: DownloadState = .queued) throws -> DownloadTask {
        DownloadTask(id: try DownloadModels.key("fixture", "comic", "chapter"),
                     bookId: try DownloadModels.bookId(source: "fixture", comic: "comic"),
                     sourceId: "fixture", comicId: "comic", chapterId: "chapter", title: "第一话",
                     url: "https://fixture.invalid/chapter", generation: 1, state: state)
    }

    func testAllMutationsRollBackAndKeepErrorUntilActualExplicitRetry() throws {
        let store = try DownloadStore(directory: root), original = try task(state: .completed)
        let detail = detail(), page = DownloadPage(index: 0, url: "first", path: "first.img", hash: "old", bytes: 3)
        XCTAssertTrue(store.save(task: original))
        XCTAssertTrue(store.saveSnapshot(detail))
        XCTAssertTrue(store.savePage(task: original.id, page: page))
        let durable = try Data(contentsOf: store.fileURL)
        let blocker = DownloadWriteBlocker(file: store.fileURL)
        try blocker.block()
        var changed = original; changed.donePages = 10; changed.state = .queued
        XCTAssertFalse(store.save(task: changed))
        XCTAssertFalse(store.save(tasks: [changed, DownloadTask(id: "new")]))
        let changedDetail = ComicDetail(summary: ComicSummary(sourceId: "fixture", comicId: "comic", title: "不得假报保存成功"),
            author: detail.author, status: detail.status, description: detail.description, latestChapter: detail.latestChapter, chapters: detail.chapters)
        XCTAssertFalse(store.saveSnapshot(changedDetail))
        XCTAssertFalse(store.savePage(task: original.id, page: DownloadPage(index: 1, url: "second", path: "second.img", hash: "new", bytes: 4)))
        XCTAssertFalse(store.replacePages(task: original.id, pages: []))
        XCTAssertFalse(store.clearPages(task: original.id))
        XCTAssertFalse(store.remove(task: original.id))
        XCTAssertThrowsError(try store.removeBook(original.bookId))
        XCTAssertEqual(store.list(), [original])
        XCTAssertEqual(store.pages(task: original.id), [page])
        XCTAssertEqual(store.snapshot(id: original.bookId)?.summary.title, detail.summary.title)
        XCTAssertEqual(store.persistenceError, .persistenceFailed)
        XCTAssertThrowsError(try store.retryPersistence())
        try blocker.restore()
        XCTAssertEqual(try Data(contentsOf: store.fileURL), durable)
        XCTAssertNotNil(store.persistenceError)
        try store.retryPersistence()
        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(try DownloadStore(directory: root).list(), [original])
    }

    func testClaimAndCompletionCannotAdvanceWhenTheirWriteFails() throws {
        let store = try DownloadStore(directory: root), original = try task()
        XCTAssertTrue(store.save(task: original))
        let queue = DownloadCoordinator(repository: store), blocker = DownloadWriteBlocker(file: store.fileURL)
        try blocker.block()
        XCTAssertNil(queue.claim(now: 100, connected: true, wifi: true, wifiOnly: true))
        XCTAssertEqual(store.get(id: original.id), original)
        try blocker.restore(); try store.retryPersistence()
        let lease = try XCTUnwrap(queue.claim(now: 100, connected: true, wifi: true, wifiOnly: true))
        try blocker.block()
        XCTAssertFalse(queue.update(lease: lease, state: .downloading, done: 2, total: 2, bytes: 100))
        XCTAssertFalse(queue.complete(lease: lease))
        XCTAssertEqual(store.get(id: lease.id), lease)
        XCTAssertEqual(store.persistenceError, .persistenceFailed)
        try blocker.restore(); try store.retryPersistence()
        XCTAssertTrue(queue.complete(lease: lease))
        XCTAssertEqual(try DownloadStore(directory: root).get(id: lease.id)?.state, .completed)
    }

    func testFailedUserPauseKeepsDurableStateAndRetryActuallyPersistsPause() throws {
        let store = try DownloadStore(directory: root), original = try task()
        XCTAssertTrue(store.save(task: original))
        let queue = DownloadCoordinator(repository: store), blocker = DownloadWriteBlocker(file: store.fileURL)
        try blocker.block(); queue.pause(id: original.id)
        XCTAssertEqual(store.get(id: original.id), original)
        XCTAssertNotNil(store.persistenceError)
        try blocker.restore(); try store.retryPersistence()
        queue.pause(id: original.id)
        XCTAssertEqual(try DownloadStore(directory: root).get(id: original.id)?.state, .pausedUser)
        queue.recover(); queue.recoverNetwork()
        XCTAssertEqual(store.get(id: original.id)?.state, .pausedUser)
    }

    func testEnqueueReportsWriteFailureWithoutInventingQueuedTasks() async throws {
        let store = try DownloadStore(directory: root)
        XCTAssertTrue(store.close())
        let blocker = DownloadWriteBlocker(file: store.fileURL)
        try blocker.block()
        let runtime = DownloadRuntime(store: store, downloadsDirectory: root.appendingPathComponent("images"), imageFetcher: PersistenceFetcher(), sourceResolver: PersistenceResolver())
        defer { runtime.suspendForBackground() }
        do {
            try await runtime.enqueueWithLocation(detail: detail(), selectedChapterIds: ["chapter"])
            XCTFail("Enqueue must report the actual filesystem failure")
        } catch { XCTAssertEqual(error as? DownloadStoreError, .persistenceFailed) }
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertEqual(runtime.activity.activeWorkers, 0)
        XCTAssertEqual(runtime.storageError, .persistenceFailed)
        XCTAssertThrowsError(try runtime.retryStorage())
        try blocker.restore(); try runtime.retryStorage()
        let completed = expectation(description: "Recovered storage accepts a real download")
        runtime.onTaskCompleted = { _ in completed.fulfill() }
        try await runtime.enqueueWithLocation(detail: detail(), selectedChapterIds: ["chapter"])
        await fulfillment(of: [completed], timeout: 5)
        try await waitUntilIdle(runtime)
        XCTAssertEqual(try DownloadStore(directory: root).get(id: try task().id)?.state, .completed)
    }

    func testPageWriteFailureKeepsFirstPageAndResumesOnlyAfterExplicitStorageRetry() async throws {
        let store = try DownloadStore(directory: root)
        XCTAssertTrue(store.close())
        let blocker = DownloadWriteBlocker(file: store.fileURL), images = root.appendingPathComponent("images")
        let fetcher = PersistenceFetcher(blocker: blocker)
        let runtime = DownloadRuntime(store: store, downloadsDirectory: images, imageFetcher: fetcher, sourceResolver: PersistenceResolver())
        defer { runtime.suspendForBackground() }
        try await runtime.enqueueWithLocation(detail: detail(), selectedChapterIds: ["chapter"])
        for _ in 0..<300 {
            if runtime.storageError != nil, runtime.activity.activeWorkers == 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let id = try task().id
        XCTAssertEqual(runtime.storageError, .persistenceFailed)
        XCTAssertNotEqual(store.get(id: id)?.state, .completed)
        XCTAssertEqual(store.get(id: id)?.donePages, 1)
        let first = try XCTUnwrap(store.pages(task: id).first)
        XCTAssertEqual(store.pages(task: id).count, 1)
        XCTAssertEqual(try Data(contentsOf: images.appendingPathComponent(first.path)), persistencePNG)
        let second = images.appendingPathComponent(first.path).deletingLastPathComponent().appendingPathComponent("1.img")
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path), "Unpersisted ownership must not publish a final page")
        runtime.updateNetworkStatus(isConnected: true, isWifi: true)
        runtime.suspendForBackground(); runtime.resumeFromBackground(); runtime.kick()
        XCTAssertEqual(runtime.activity.activeWorkers, 0)
        let secondCountBeforeRetry = await fetcher.count("https://fixture.invalid/second.png")
        XCTAssertEqual(secondCountBeforeRetry, 1)
        try blocker.restore()
        let completed = expectation(description: "Explicit storage retry resumes the actual durable page")
        runtime.onTaskCompleted = { _ in completed.fulfill() }
        try runtime.retryStorage()
        await fulfillment(of: [completed], timeout: 5)
        try await waitUntilIdle(runtime)
        XCTAssertNil(runtime.storageError)
        let firstCount = await fetcher.count("https://fixture.invalid/first.png")
        let secondCount = await fetcher.count("https://fixture.invalid/second.png")
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 2)
        XCTAssertEqual(try DownloadStore(directory: root).get(id: id)?.state, .completed)
        XCTAssertEqual(try runtime.offlineImageData(at: second), persistencePNG)
    }

    private func waitUntilIdle(_ runtime: DownloadRuntime) async throws {
        for _ in 0..<300 where runtime.activity.activeWorkers > 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(runtime.activity.activeWorkers, 0)
    }
}
