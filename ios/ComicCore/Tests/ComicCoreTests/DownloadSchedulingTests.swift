import XCTest
@testable import ComicCore

private let schedulingPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=")!

private actor SchedulingFetcher: DownloadImageFetcherProtocol {
    enum Mode { case normal, failFirst, holdSecond }
    let mode: Mode
    let reached: XCTestExpectation?
    private(set) var calls: [String: Int] = [:]
    private var active = 0
    private(set) var maximumActive = 0

    init(_ mode: Mode = .normal, reached: XCTestExpectation? = nil) { self.mode = mode; self.reached = reached }

    func fetch(sourceId: String, url: String, referer: String, destination: URL, check: @escaping () throws -> Void) async throws -> (bytes: Int64, hash: String) {
        try check()
        calls[url, default: 0] += 1
        active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if calls.values.reduce(0, +) == 1, mode == .failFirst {
            reached?.fulfill()
            throw DownloadHTTPError(statusCode: 429, retryAfterMs: 0)
        }
        if url.hasSuffix("second.png"), calls[url] == 1, mode == .holdSecond {
            reached?.fulfill()
            while true { try await Task.sleep(nanoseconds: 80_000_000); try check() }
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try schedulingPNG.write(to: destination)
        return (Int64(schedulingPNG.count), DownloadModels.sha256Hex(schedulingPNG))
    }

    func count(_ url: String) -> Int { calls[url, default: 0] }
}

private struct SchedulingResolver: DownloadSourceResolverProtocol {
    func resolveChapter(sourceId: String, url: String) async throws -> ChapterPage {
        ChapterPage(chapterId: "first", title: "第1话", imageUrls: ["https://fixture.invalid/first.png", "https://fixture.invalid/second.png"])
    }
    func resolveReferer(sourceId: String, chapterUrl: String) -> String { "" }
    func fetchCover(sourceId: String, coverUrl: String, destination: URL, check: @escaping () throws -> Void) async throws { try check() }
}

final class DownloadSchedulingTests: XCTestCase {
    private struct Context {
        let root: URL
        let files: URL
        let store: DownloadStore
        let runtime: DownloadRuntime
        let detail: ComicDetail
        let id: String
        let pausedID: String
    }

    private func context(fetcher: SchedulingFetcher, restoreActive: Bool = false) throws -> Context {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try DownloadStore(directory: root)
        let files = root.appendingPathComponent("files")
        let comic = ComicSummary(sourceId: "fixture", comicId: "comic", title: "下载调度验收")
        let chapter = Chapter(chapterId: "first", title: "第1话", url: "https://fixture.invalid/chapter")
        let detail = ComicDetail(summary: comic, author: "验收作者", status: "连载中", description: "确定性真实图片下载", latestChapter: "第1话", chapters: [chapter])
        let id = try DownloadModels.key("fixture", "comic", "first")
        let pausedID = try DownloadModels.key("fixture", "comic", "manual")
        let book = try DownloadModels.bookId(source: "fixture", comic: "comic")
        store.saveSnapshot(detail)
        store.save(task: DownloadTask(id: pausedID, bookId: book, sourceId: "fixture", comicId: "comic", chapterId: "manual", state: .pausedUser))
        if restoreActive {
            store.save(task: DownloadTask(id: id, bookId: book, sourceId: "fixture", comicId: "comic", chapterId: "first", url: chapter.url, generation: 4, state: .downloading))
        }
        let runtime = DownloadRuntime(store: store, downloadsDirectory: files, imageFetcher: fetcher, sourceResolver: SchedulingResolver())
        return Context(root: root, files: files, store: store, runtime: runtime, detail: detail, id: id, pausedID: pausedID)
    }

    private func waitUntilIdle(_ context: Context) async throws {
        for _ in 0..<300 where context.runtime.activity.activeWorkers > 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(context.runtime.activity.activeWorkers, 0)
    }

    private func verifyPublishedPages(_ context: Context) throws {
        XCTAssertEqual(context.store.get(id: context.id)?.state, .completed)
        XCTAssertEqual(context.store.get(id: context.pausedID)?.state, .pausedUser)
        let pages = context.store.pages(task: context.id)
        XCTAssertEqual(pages.count, 2)
        for page in pages {
            XCTAssertEqual(try Data(contentsOf: context.files.appendingPathComponent(page.path)), schedulingPNG)
            XCTAssertEqual(page.hash, DownloadModels.sha256Hex(schedulingPNG))
        }
        let reopened = try DownloadStore(directory: context.root)
        XCTAssertEqual(reopened.get(id: context.id)?.state, .completed)
        XCTAssertEqual(reopened.get(id: context.pausedID)?.state, .pausedUser)
    }

    func testRestoredWorkStartsWithAnUnchangedAllowedNetworkAndKeepsManualPause() async throws {
        let context = try context(fetcher: SchedulingFetcher(), restoreActive: true)
        defer { context.runtime.suspendForBackground(); try? FileManager.default.removeItem(at: context.root) }
        XCTAssertEqual(context.store.get(id: context.id)?.state, .queued)
        let completed = expectation(description: "Restored download completes without opening a page")
        context.runtime.onTaskCompleted = { _ in completed.fulfill() }
        context.runtime.updateNetworkStatus(isConnected: true, isWifi: true)
        await fulfillment(of: [completed], timeout: 5)
        try await waitUntilIdle(context)
        try verifyPublishedPages(context)
    }

    func testRateLimitRetryRunsWithoutPagePollingOrAnotherKick() async throws {
        let fetcher = SchedulingFetcher(.failFirst)
        let context = try context(fetcher: fetcher)
        defer { context.runtime.suspendForBackground(); try? FileManager.default.removeItem(at: context.root) }
        let completed = expectation(description: "Automatic retry reaches completion")
        context.runtime.onTaskCompleted = { _ in completed.fulfill() }
        context.runtime.enqueue(detail: context.detail, selectedChapterIds: ["first"])
        await fulfillment(of: [completed], timeout: 7)
        try await waitUntilIdle(context)
        let firstCalls = await fetcher.count("https://fixture.invalid/first.png")
        XCTAssertEqual(firstCalls, 2)
        try verifyPublishedPages(context)
    }

    func testChangingWifiPolicyStartsWaitingWorkWithoutManualRetry() async throws {
        let context = try context(fetcher: SchedulingFetcher())
        defer { context.runtime.suspendForBackground(); try? FileManager.default.removeItem(at: context.root) }
        context.runtime.updateNetworkStatus(isConnected: true, isWifi: false)
        context.runtime.enqueue(detail: context.detail, selectedChapterIds: ["first"])
        XCTAssertEqual(context.store.get(id: context.id)?.state, .waitingNetwork)
        let completed = expectation(description: "Allowed cellular download completes")
        context.runtime.onTaskCompleted = { _ in completed.fulfill() }
        context.runtime.updateWifiOnly(false)
        await fulfillment(of: [completed], timeout: 5)
        try await waitUntilIdle(context)
        try verifyPublishedPages(context)
    }

    func testSuspensionInvalidatesLeaseAndImmediateResumptionReusesPublishedPages() async throws {
        let held = expectation(description: "Second page is actually in flight")
        let fetcher = SchedulingFetcher(.holdSecond, reached: held)
        let context = try context(fetcher: fetcher)
        defer { context.runtime.suspendForBackground(); try? FileManager.default.removeItem(at: context.root) }
        let completed = expectation(description: "Resumed download completes")
        context.runtime.onTaskCompleted = { _ in completed.fulfill() }
        context.runtime.enqueue(detail: context.detail, selectedChapterIds: ["first"])
        await fulfillment(of: [held], timeout: 5)
        let lease = try XCTUnwrap(context.store.get(id: context.id))
        XCTAssertEqual(lease.donePages, 1)
        context.runtime.suspendForBackground()
        let saved = try XCTUnwrap(context.store.get(id: context.id))
        XCTAssertEqual(saved.state, .queued)
        XCTAssertNotEqual(saved.generation, lease.generation)
        XCTAssertEqual(context.store.pages(task: context.id).count, 1)
        context.runtime.resumeFromBackground()
        await fulfillment(of: [completed], timeout: 5)
        try await waitUntilIdle(context)
        let firstCalls = await fetcher.count("https://fixture.invalid/first.png")
        let secondCalls = await fetcher.count("https://fixture.invalid/second.png")
        let maximum = await fetcher.maximumActive
        XCTAssertEqual(firstCalls, 1, "A published page must survive suspension")
        XCTAssertEqual(secondCalls, 2)
        XCTAssertEqual(maximum, 1, "A new lease must wait until the old worker releases the same task ID")
        try verifyPublishedPages(context)
    }

    func testSuspendedRuntimeDoesNotStartOnNetworkChangesOrManualKick() async throws {
        let fetcher = SchedulingFetcher()
        let context = try context(fetcher: fetcher)
        defer { context.runtime.suspendForBackground(); try? FileManager.default.removeItem(at: context.root) }
        context.runtime.suspendForBackground()
        context.runtime.enqueue(detail: context.detail, selectedChapterIds: ["first"])
        context.runtime.updateNetworkStatus(isConnected: true, isWifi: true)
        context.runtime.kick()
        try await Task.sleep(nanoseconds: 200_000_000)
        let calls = await fetcher.count("https://fixture.invalid/first.png")
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(context.store.get(id: context.id)?.state, .queued)
        let completed = expectation(description: "Foreground resumption starts eligible work")
        context.runtime.onTaskCompleted = { _ in completed.fulfill() }
        context.runtime.resumeFromBackground()
        await fulfillment(of: [completed], timeout: 5)
        try await waitUntilIdle(context)
        try verifyPublishedPages(context)
    }

    func testBackgroundSuspensionKeepsRetryDeadlineAndStopsTimerUntilForeground() async throws {
        let failed = expectation(description: "The first request is rate limited")
        let fetcher = SchedulingFetcher(.failFirst, reached: failed)
        let context = try context(fetcher: fetcher)
        defer { context.runtime.suspendForBackground(); try? FileManager.default.removeItem(at: context.root) }
        context.runtime.enqueue(detail: context.detail, selectedChapterIds: ["first"])
        await fulfillment(of: [failed], timeout: 5)
        for _ in 0..<200 where context.store.get(id: context.id)?.state != .queued { try await Task.sleep(nanoseconds: 10_000_000) }
        let waiting = try XCTUnwrap(context.store.get(id: context.id))
        XCTAssertEqual(waiting.state, .queued)
        XCTAssertGreaterThan(waiting.nextAttempt, 0)
        context.runtime.suspendForBackground()
        try await Task.sleep(nanoseconds: 2_100_000_000)
        let calls = await fetcher.count("https://fixture.invalid/first.png")
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(context.store.get(id: context.id)?.nextAttempt, waiting.nextAttempt)
        let completed = expectation(description: "Eligible retry resumes in the foreground")
        context.runtime.onTaskCompleted = { _ in completed.fulfill() }
        context.runtime.resumeFromBackground()
        await fulfillment(of: [completed], timeout: 5)
        try await waitUntilIdle(context)
        try verifyPublishedPages(context)
    }
}
