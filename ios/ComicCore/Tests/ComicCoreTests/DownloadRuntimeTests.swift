import XCTest
@testable import ComicCore

private final class MockImageFetcher: DownloadImageFetcherProtocol, @unchecked Sendable {
    var fetchCount = 0
    var shouldFailWith429 = false
    var shouldFailWith403 = false

    func fetch(sourceId: String,
               url: String,
               referer: String,
               destination: URL,
               check: @escaping () throws -> Void) async throws -> (bytes: Int64, hash: String) {
        try check()
        if shouldFailWith429 {
            throw DownloadHTTPError(statusCode: 429, retryAfterMs: 5000)
        }
        if shouldFailWith403 {
            throw DownloadHTTPError(statusCode: 403, retryAfterMs: 0)
        }
        fetchCount += 1
        let dummyData = "Image content for \(url)".data(using: .utf8)!
        let destDir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try dummyData.write(to: destination)
        let hash = DownloadModels.sha256Hex(dummyData)
        return (bytes: Int64(dummyData.count), hash: hash)
    }
}

private final class MockSourceResolver: DownloadSourceResolverProtocol, @unchecked Sendable {
    var chapterPages: [String: [String]] = [:]

    func resolveChapter(sourceId: String, url: String) async throws -> ChapterPage {
        let urls = chapterPages[url] ?? ["https://example.com/p1.jpg", "https://example.com/p2.jpg"]
        return ChapterPage(chapterId: "ch1", title: "Chapter 1", nextPageUrl: "", imageUrls: urls)
    }

    func resolveReferer(sourceId: String, chapterUrl: String) -> String {
        "https://example.com/referer"
    }

    func fetchCover(sourceId: String, coverUrl: String, destination: URL, check: @escaping () throws -> Void) async throws {
        try check()
        let data = "cover data".data(using: .utf8)!
        let destDir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try data.write(to: destination)
    }
}

final class DownloadRuntimeTests: XCTestCase {
    private var tempDir: URL!
    private var store: DownloadStore!
    private var mockFetcher: MockImageFetcher!
    private var mockResolver: MockSourceResolver!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadRuntimeTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try DownloadStore(directory: tempDir)
        mockFetcher = MockImageFetcher()
        mockResolver = MockSourceResolver()
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testEnqueueAndDownloadCompletion() async throws {
        let runtime = DownloadRuntime(store: store,
                                      downloadsDirectory: tempDir.appendingPathComponent("Downloads"),
                                      imageFetcher: mockFetcher,
                                      sourceResolver: mockResolver)

        let summary = ComicSummary(sourceId: "mockSource", comicId: "comic123", title: "Test Comic")
        let ch1 = Chapter(chapterId: "ch_01", title: "First Chapter", url: "https://example.com/ch1")
        let detail = ComicDetail(summary: summary, author: "Author", status: "Ongoing", description: "Desc", latestChapter: "First Chapter", chapters: [ch1])

        let exp = expectation(description: "Task completed")
        runtime.onTaskCompleted = { task in
            if task.chapterId == "ch_01" {
                exp.fulfill()
            }
        }

        runtime.enqueue(detail: detail, selectedChapterIds: ["ch_01"])

        await fulfillment(of: [exp], timeout: 5.0)

        let taskId = try DownloadModels.key("mockSource", "comic123", "ch_01")
        let completedTask = store.get(id: taskId)
        XCTAssertNotNil(completedTask)
        XCTAssertEqual(completedTask?.state, .completed)
        XCTAssertEqual(completedTask?.donePages, 2)
        XCTAssertEqual(completedTask?.totalPages, 2)

        // Verify offline reading
        let localPage = try runtime.localChapter(detail: detail, chapterIndex: 0)
        XCTAssertNotNil(localPage)
        XCTAssertEqual(localPage?.imageUrls.count, 2)
        XCTAssertTrue(localPage?.imageUrls[0].hasPrefix("file://") == true)
    }

    func testResumeSkipsAlreadyDownloadedPages() async throws {
        let runtime = DownloadRuntime(store: store,
                                      downloadsDirectory: tempDir.appendingPathComponent("Downloads"),
                                      imageFetcher: mockFetcher,
                                      sourceResolver: mockResolver)

        let summary = ComicSummary(sourceId: "mockSource", comicId: "comic123", title: "Test Comic")
        let ch1 = Chapter(chapterId: "ch_01", title: "First Chapter", url: "https://example.com/ch1")
        let detail = ComicDetail(summary: summary, author: "Author", status: "Ongoing", description: "Desc", latestChapter: "First Chapter", chapters: [ch1])

        let exp1 = expectation(description: "First run completed")
        runtime.onTaskCompleted = { _ in exp1.fulfill() }
        runtime.enqueue(detail: detail, selectedChapterIds: ["ch_01"])
        await fulfillment(of: [exp1], timeout: 5.0)

        XCTAssertEqual(mockFetcher.fetchCount, 2)

        // Now run again on the same task - pages exist and are valid, fetchCount should not increase
        let taskId = try DownloadModels.key("mockSource", "comic123", "ch_01")
        var task = store.get(id: taskId)!
        task.state = .queued
        store.save(task: task)

        let exp2 = expectation(description: "Second run completed without refetching")
        runtime.onTaskCompleted = { _ in exp2.fulfill() }
        runtime.kick()
        await fulfillment(of: [exp2], timeout: 5.0)

        XCTAssertEqual(mockFetcher.fetchCount, 2) // No new fetches
    }

    func testPauseAndResume() async throws {
        let runtime = DownloadRuntime(store: store,
                                      downloadsDirectory: tempDir.appendingPathComponent("Downloads"),
                                      imageFetcher: mockFetcher,
                                      sourceResolver: mockResolver)

        runtime.pauseAll() // Set to pause
        let taskId = try DownloadModels.key("mockSource", "comic123", "ch_01")
        let task = DownloadTask(id: taskId, bookId: "b1", sourceId: "mockSource", comicId: "comic123", chapterId: "ch_01", title: "Ch1", state: .pausedUser)
        store.save(task: task)

        runtime.resumeAll()
        let currentState = store.get(id: taskId)?.state
        XCTAssertTrue(currentState == .queued || currentState == .resolving)
    }

    func testDeleteChapterCleansFilesAndStore() async throws {
        let downloadsDir = tempDir.appendingPathComponent("Downloads")
        let runtime = DownloadRuntime(store: store,
                                      downloadsDirectory: downloadsDir,
                                      imageFetcher: mockFetcher,
                                      sourceResolver: mockResolver)

        let summary = ComicSummary(sourceId: "mockSource", comicId: "comic123", title: "Test Comic")
        let ch1 = Chapter(chapterId: "ch_01", title: "First Chapter", url: "https://example.com/ch1")
        let detail = ComicDetail(summary: summary, author: "Author", status: "Ongoing", description: "Desc", latestChapter: "First Chapter", chapters: [ch1])

        let exp = expectation(description: "Task completed")
        runtime.onTaskCompleted = { _ in exp.fulfill() }
        runtime.enqueue(detail: detail, selectedChapterIds: ["ch_01"])
        await fulfillment(of: [exp], timeout: 5.0)

        let taskId = try DownloadModels.key("mockSource", "comic123", "ch_01")
        let bookId = try DownloadModels.bookId(source: "mockSource", comic: "comic123")
        let taskDir = downloadsDir.appendingPathComponent(bookId).appendingPathComponent(taskId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskDir.path))

        runtime.deleteChapter(id: taskId)

        XCTAssertNil(store.get(id: taskId))
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskDir.path))
    }
}
