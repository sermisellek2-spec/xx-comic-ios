import XCTest
@testable import ComicCore

final class FavoriteUpdateCheckerTests: XCTestCase {
    private final class MockUpdateSource: ComicSource, @unchecked Sendable {
        let id: String = "mock_update"
        let name: String = "Mock Update"
        let referer: String = ""
        private let lock = NSLock()
        private var _chapterCount: Int = 10

        var chapterCount: Int {
            get { lock.lock(); defer { lock.unlock() }; return _chapterCount }
            set { lock.lock(); defer { lock.unlock() }; _chapterCount = newValue }
        }

        func setChapterCount(_ count: Int) {
            self.chapterCount = count
        }

        func latest(page: Int) async throws -> [ComicSummary] { [] }
        func search(keyword: String, page: Int) async throws -> [ComicSummary] { [] }
        func filterGroups() async throws -> [SourceFilterGroup] { [] }
        func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { [] }
        func chapters(comicId: String) async throws -> [Chapter] { [] }
        func chapter(url: String) async throws -> ChapterPage { ChapterPage(chapterId: "1", title: "1", nextPageUrl: "", imageUrls: []) }

        func detail(comicId: String) async throws -> ComicDetail {
            let count = chapterCount
            let chaps = (1...count).map {
                Chapter(chapterId: "\($0)", title: "第\($0)话", url: "https://test/\($0)", chapterSlot: $0)
            }
            return ComicDetail(
                summary: ComicSummary(sourceId: id, comicId: comicId, title: "测试漫画", coverUrl: ""),
                author: "作者",
                status: "连载",
                description: "简介",
                latestChapter: "第\(count)话",
                chapters: chaps
            )
        }
    }

    func testFavoriteUpdateCheckLifecycle() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = try LibraryStore(directory: tempDir)
        let coordinator = FavoriteUpdateCoordinator()
        let mockSource = MockUpdateSource()

        let comic = ComicSummary(sourceId: "mock_update", comicId: "test_comic_1", title: "测试漫画", coverUrl: "")
        try library.setFavorite(comic, favorite: true)

        let checker = FavoriteUpdateChecker(
            library: library,
            coordinator: coordinator,
            sourceProvider: { id in
                id == "mock_update" ? mockSource : nil
            }
        )

        // 1. Initial check - establishes baseline, does not light up
        let firstResults = await checker.checkAllFavorites()
        XCTAssertEqual(firstResults["mock_update:test_comic_1"], false)
        XCTAssertFalse(coordinator.hasPendingUpdate(sourceId: "mock_update", comicId: "test_comic_1"))

        // 2. User acknowledges / reads comic (sets baseline acknowledged)
        let chaps10 = (1...10).map { Chapter(chapterId: "\($0)", title: "第\($0)话", url: "https://test/\($0)", chapterSlot: $0) }
        coordinator.acknowledge(
            sourceId: "mock_update",
            comicId: "test_comic_1",
            revision: FavoriteRevision.fromChapters(latestChapterName: "第10话", chapters: chaps10)
        )
        XCTAssertFalse(coordinator.hasPendingUpdate(sourceId: "mock_update", comicId: "test_comic_1"))

        // 3. Check again with same chapter count -> no new update
        let secondResults = await checker.checkAllFavorites()
        XCTAssertEqual(secondResults["mock_update:test_comic_1"], false)
        XCTAssertFalse(coordinator.hasPendingUpdate(sourceId: "mock_update", comicId: "test_comic_1"))

        // 4. Source adds new chapter 11
        mockSource.setChapterCount(11)
        let thirdResults = await checker.checkAllFavorites()
        XCTAssertEqual(thirdResults["mock_update:test_comic_1"], true)
        XCTAssertTrue(coordinator.hasPendingUpdate(sourceId: "mock_update", comicId: "test_comic_1"))

        // 5. Acknowledge new chapter 11 -> update cleared
        let chaps11 = (1...11).map { Chapter(chapterId: "\($0)", title: "第\($0)话", url: "https://test/\($0)", chapterSlot: $0) }
        coordinator.acknowledge(
            sourceId: "mock_update",
            comicId: "test_comic_1",
            revision: FavoriteRevision.fromChapters(latestChapterName: "第11话", chapters: chaps11)
        )
        XCTAssertFalse(coordinator.hasPendingUpdate(sourceId: "mock_update", comicId: "test_comic_1"))
    }

    func testSplitDetailUpdateQueriesChaptersEndpoint() async throws {
        final class SplitMockSource: ComicSource, @unchecked Sendable {
            let id = "split_mock"
            let name = "Split Mock"
            let referer = ""
            var count = 10
            var chapterCalls = 0
            func latest(page: Int) async throws -> [ComicSummary] { [] }
            func search(keyword: String, page: Int) async throws -> [ComicSummary] { [] }
            func filterGroups() async throws -> [SourceFilterGroup] { [] }
            func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { [] }
            func detail(comicId: String) async throws -> ComicDetail {
                ComicDetail(summary: ComicSummary(sourceId: id, comicId: comicId, title: "Split Comic", coverUrl: ""), author: "", status: "", description: "", latestChapter: "", chapters: [])
            }
            func chapters(comicId: String) async throws -> [Chapter] {
                chapterCalls += 1
                return (1...count).map { Chapter(chapterId: "\($0)", title: "第\($0)话", url: "split/\($0)", chapterSlot: $0) }
            }
            func chapter(url: String) async throws -> ChapterPage {
                ChapterPage(chapterId: "", title: "", nextPageUrl: "", imageUrls: [])
            }
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = try LibraryStore(directory: tempDir)
        let coordinator = FavoriteUpdateCoordinator()
        let splitSource = SplitMockSource()

        let comic = ComicSummary(sourceId: "split_mock", comicId: "split_comic", title: "Split Comic", coverUrl: "")
        try library.setFavorite(comic, favorite: true)

        let checker = FavoriteUpdateChecker(
            library: library,
            coordinator: coordinator,
            sourceProvider: { id in id == "split_mock" ? splitSource : nil }
        )

        // Baseline run: queries chapters, sets baseline
        _ = await checker.checkAllFavorites()
        XCTAssertEqual(splitSource.chapterCalls, 1)
        XCTAssertFalse(coordinator.hasPendingUpdate(sourceId: "split_mock", comicId: "split_comic"))

        // Update run: chapter count increases, badge turns on
        splitSource.count = 11
        _ = await checker.checkAllFavorites()
        XCTAssertEqual(splitSource.chapterCalls, 2)
        XCTAssertTrue(coordinator.hasPendingUpdate(sourceId: "split_mock", comicId: "split_comic"))
    }
}
