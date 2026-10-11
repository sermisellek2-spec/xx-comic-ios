import XCTest
import UIKit
import ComicCore
@testable import XXComic

private actor LifecycleFetcher: DownloadImageFetcherProtocol {
    let bytes: Data
    let pending: XCTestExpectation
    private var calls = 0
    init(bytes: Data, pending: XCTestExpectation) { self.bytes = bytes; self.pending = pending }
    func fetch(sourceId: String, url: String, referer: String, destination: URL, check: @escaping () throws -> Void) async throws -> (bytes: Int64, hash: String) {
        calls += 1
        if calls == 1 {
            pending.fulfill()
            while true { try await Task.sleep(nanoseconds: 50_000_000); try check() }
        }
        try check()
        try bytes.write(to: destination)
        return (Int64(bytes.count), DownloadModels.sha256Hex(bytes))
    }
}

private struct LifecycleResolver: DownloadSourceResolverProtocol {
    func resolveChapter(sourceId: String, url: String) async throws -> ChapterPage {
        ChapterPage(chapterId: "chapter", title: "第1话", imageUrls: ["https://fixture.invalid/page.png"])
    }
    func resolveReferer(sourceId: String, chapterUrl: String) -> String { "" }
    func fetchCover(sourceId: String, coverUrl: String, destination: URL, check: @escaping () throws -> Void) async throws { try check() }
}

@MainActor
final class DownloadLifecycleTests: XCTestCase {
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "The lifecycle transition must finish")
    }

    func testIdleBackgroundDoesNotKeepAnAllowanceOrResumeManualPause() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try DownloadStore(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let paused = DownloadTask(id: try DownloadModels.key("fixture", "comic", "paused"), bookId: try DownloadModels.bookId(source: "fixture", comic: "comic"), sourceId: "fixture", comicId: "comic", chapterId: "paused", state: .pausedUser)
        store.save(task: paused)
        let runtime = DownloadRuntime(store: store, downloadsDirectory: root.appendingPathComponent("files"))
        var requests = 0
        let controller = DownloadLifecycleController(runtime: runtime, begin: { _ in requests += 1; return .invalid }, end: { _ in XCTFail("No allowance was granted") })
        controller.start()
        controller.didEnterBackground()
        try await waitFor { runtime.activity.suspendedForBackground }
        XCTAssertGreaterThanOrEqual(requests, 1, "A transition must protect itself before reading a potentially locked runtime")
        controller.didBecomeActive()
        try await waitFor { !runtime.activity.suspendedForBackground }
        XCTAssertEqual(store.get(id: paused.id)?.state, .pausedUser)
    }

    func testExpirationPersistsLeaseAndForegroundResumptionCompletesRealFiles() async throws {
        try await checkRunningDownload(denyAllowance: false)
    }

    func testDeniedAllowanceSuspendsAndForegroundResumptionStillCompletes() async throws {
        try await checkRunningDownload(denyAllowance: true)
    }

    private func checkRunningDownload(denyAllowance: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try DownloadStore(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let bytes = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 12), format: format).image { UIColor.blue.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 8, height: 12)) }.pngData())
        let pending = expectation(description: "Actual download worker is running")
        let runtime = DownloadRuntime(store: store, downloadsDirectory: root.appendingPathComponent("files"), imageFetcher: LifecycleFetcher(bytes: bytes, pending: pending), sourceResolver: LifecycleResolver())
        let comic = ComicSummary(sourceId: "fixture", comicId: "comic", title: "后台下载验收")
        let chapter = Chapter(chapterId: "chapter", title: "第1话", url: "https://fixture.invalid/chapter")
        let detail = ComicDetail(summary: comic, author: "", status: "", description: "", latestChapter: "第1话", chapters: [chapter])
        let id = try DownloadModels.key("fixture", "comic", "chapter")
        var expirations: [() -> Void] = [], ended: [UIBackgroundTaskIdentifier] = []
        let grant = UIBackgroundTaskIdentifier(rawValue: 37)
        let controller = DownloadLifecycleController(runtime: runtime, begin: { expiry in
            expirations.append(expiry); return denyAllowance ? .invalid : grant
        }, end: { ended.append($0) })
        controller.start()
        runtime.enqueue(detail: detail, selectedChapterIds: [chapter.chapterId])
        await fulfillment(of: [pending], timeout: 5)
        try await waitFor { !expirations.isEmpty }
        let original = try XCTUnwrap(store.get(id: id))
        controller.didEnterBackground()
        if !denyAllowance { expirations[0]() }
        try await waitFor { runtime.activity.suspendedForBackground && runtime.activity.activeWorkers == 0 && (denyAllowance || ended.count == 1) }
        let suspended = try XCTUnwrap(store.get(id: id))
        XCTAssertEqual(suspended.state, .queued)
        XCTAssertNotEqual(suspended.generation, original.generation)
        if !denyAllowance { XCTAssertEqual(ended, [grant]) }
        else { XCTAssertTrue(ended.isEmpty) }
        let completed = expectation(description: "Foreground completes the same download")
        runtime.onTaskCompleted = { _ in completed.fulfill() }
        controller.didBecomeActive()
        await fulfillment(of: [completed], timeout: 5)
        try await waitFor { runtime.activity.activeWorkers == 0 }
        let restored = try DownloadStore(directory: root)
        XCTAssertEqual(restored.get(id: id)?.state, .completed)
        let page = try XCTUnwrap(restored.pages(task: id).first)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("files").appendingPathComponent(page.path)), bytes)
    }
}
