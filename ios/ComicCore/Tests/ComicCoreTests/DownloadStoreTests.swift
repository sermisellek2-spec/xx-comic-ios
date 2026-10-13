import XCTest
@testable import ComicCore

final class DownloadStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadStoreTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testEmptyStoreReturnsEmptyList() throws {
        let store = try DownloadStore(directory: tempDir)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertNil(store.get(id: "nonexistent"))
        XCTAssertNil(store.snapshot(id: "nonexistent"))
        XCTAssertTrue(store.pages(task: "nonexistent").isEmpty)
    }

    func testDownloadBookCreationDateIsDurableAndSnapshotRefreshCannotReorderIt() throws {
        let store = try DownloadStore(directory: tempDir)
        let comic = ComicSummary(sourceId: "source", comicId: "comic", title: "Creation date")
        let detail = ComicDetail(summary: comic, author: "", status: "", description: "", latestChapter: "", chapters: [])
        let id = try DownloadModels.bookId(source: "source", comic: "comic")
        XCTAssertTrue(store.saveSnapshot(detail, createdAt: 100))
        XCTAssertTrue(store.saveSnapshot(detail, createdAt: 200))
        XCTAssertEqual(store.bookCreationDate(id: id), 100)
        XCTAssertEqual(try DownloadStore(directory: tempDir).bookCreationDate(id: id), 100)
        try store.removeBook(id)
        XCTAssertNil(store.bookCreationDate(id: id))
        XCTAssertTrue(store.saveSnapshot(detail, createdAt: 300))
        XCTAssertEqual(store.bookCreationDate(id: id), 300)
    }

    func testLegacyDownloadSnapshotKeepsUnknownCreationDateAndOriginalFileOnRead() throws {
        let comic = ComicSummary(sourceId: "source", comicId: "comic", title: "Legacy")
        let detail = ComicDetail(summary: comic, author: "", status: "", description: "", latestChapter: "", chapters: [])
        let id = try DownloadModels.bookId(source: "source", comic: "comic")
        let original = try JSONEncoder().encode(DownloadStoreData(snapshots: [id: detail]))
        let file = tempDir.appendingPathComponent("downloads.json"); try original.write(to: file)
        let store = try DownloadStore(directory: tempDir)
        XCTAssertEqual(store.snapshot(id: id), detail)
        XCTAssertNil(store.bookCreationDate(id: id))
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertTrue(store.saveSnapshot(detail, createdAt: 500))
        XCTAssertNil(store.bookCreationDate(id: id), "A later refresh cannot invent the lost original creation time")
    }

    func testFailedSnapshotPublicationCannotLeaveAnUncommittedCreationDate() throws {
        let store = try DownloadStore(directory: tempDir)
        let detail = ComicDetail(summary: ComicSummary(sourceId: "source", comicId: "comic", title: "Failed"), author: "", status: "", description: "", latestChapter: "", chapters: [])
        let id = try DownloadModels.bookId(source: "source", comic: "comic")
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
        XCTAssertFalse(store.saveSnapshot(detail, createdAt: 100))
        XCTAssertNil(store.snapshot(id: id)); XCTAssertNil(store.bookCreationDate(id: id))
        try FileManager.default.removeItem(at: store.fileURL)
        XCTAssertTrue(store.saveSnapshot(detail, createdAt: 200))
        XCTAssertEqual(try DownloadStore(directory: tempDir).bookCreationDate(id: id), 200)
    }

    func testConfirmedTaskWriteFailureCannotInventOrReplaceQueueRecords() throws {
        let store = try DownloadStore(directory: tempDir)
        let original = DownloadTask(id: "existing", bookId: "book", sourceId: "source", comicId: "comic", chapterId: "chapter", state: .completed)
        try store.saveConfirmedTask(original)
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
        var changed = original; changed.state = .queued
        XCTAssertThrowsError(try store.saveConfirmedTask(changed))
        XCTAssertEqual(store.get(id: original.id), original)
        XCTAssertThrowsError(try store.saveConfirmedTask(DownloadTask(id: "new", state: .queued)))
        XCTAssertNil(store.get(id: "new"))
        XCTAssertEqual(store.list(), [original])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testPreservesFIFOOrderOnTaskUpdate() throws {
        let store = try DownloadStore(directory: tempDir)
        var t1 = DownloadTask(id: "task1", bookId: "b1", sourceId: "s1", comicId: "c1", chapterId: "ch1", title: "Chapter 1", order: 1)
        var t2 = DownloadTask(id: "task2", bookId: "b1", sourceId: "s1", comicId: "c1", chapterId: "ch2", title: "Chapter 2", order: 2)
        let t3 = DownloadTask(id: "task3", bookId: "b1", sourceId: "s1", comicId: "c1", chapterId: "ch3", title: "Chapter 3", order: 3)

        store.save(task: t1)
        store.save(task: t2)
        store.save(task: t3)

        var list = store.list()
        XCTAssertEqual(list.map(\.id), ["task1", "task2", "task3"])

        // Update task1 - should still remain first (FIFO)
        t1.state = .downloading
        t1.donePages = 5
        store.save(task: t1)

        list = store.list()
        XCTAssertEqual(list.map(\.id), ["task1", "task2", "task3"])
        XCTAssertEqual(list[0].state, .downloading)
        XCTAssertEqual(list[0].donePages, 5)

        // Update task2
        t2.state = .completed
        store.save(task: t2)
        list = store.list()
        XCTAssertEqual(list.map(\.id), ["task1", "task2", "task3"])
    }

    func testSnapshotPersistence() throws {
        let store = try DownloadStore(directory: tempDir)
        let summary = ComicSummary(sourceId: "sourceA", comicId: "comic1", title: "Test Comic", coverUrl: "https://example.com/cover.jpg")
        let ch1 = Chapter(chapterId: "c1", title: "Ep 1", url: "https://example.com/c1", sectionSlot: 0, chapterSlot: 0)
        let ch2 = Chapter(chapterId: "c2", title: "Ep 2", url: "https://example.com/c2", sectionSlot: 0, chapterSlot: 1)
        let detail = ComicDetail(summary: summary, author: "Author", status: "Ongoing", description: "Desc", latestChapter: "Ep 2", chapters: [ch1, ch2])

        store.saveSnapshot(detail)

        let bookId = try DownloadModels.bookId(source: "sourceA", comic: "comic1")
        let loaded = store.snapshot(id: bookId)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.summary.title, "Test Comic")
        XCTAssertEqual(loaded?.chapters.count, 2)
        XCTAssertEqual(loaded?.chapters[0].title, "Ep 1")
    }

    func testPageOperations() throws {
        let store = try DownloadStore(directory: tempDir)
        let p0 = DownloadPage(index: 0, url: "https://example.com/0.jpg", path: "b1/t1/0.img", hash: "h0", bytes: 100)
        let p1 = DownloadPage(index: 1, url: "https://example.com/1.jpg", path: "b1/t1/1.img", hash: "h1", bytes: 200)

        store.savePage(task: "task1", page: p1)
        store.savePage(task: "task1", page: p0)

        // Sorted by page index
        let pages = store.pages(task: "task1")
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].index, 0)
        XCTAssertEqual(pages[1].index, 1)

        // Replace pages
        let p2 = DownloadPage(index: 2, url: "https://example.com/2.jpg", path: "b1/t1/2.img", hash: "h2", bytes: 300)
        store.replacePages(task: "task1", pages: [p2])
        XCTAssertEqual(store.pages(task: "task1").count, 1)
        XCTAssertEqual(store.pages(task: "task1")[0].index, 2)

        // Clear pages
        store.clearPages(task: "task1")
        XCTAssertTrue(store.pages(task: "task1").isEmpty)
    }

    func testPersistenceAcrossReinitialization() throws {
        let file = tempDir.appendingPathComponent("downloads.json")
        do {
            let store1 = try DownloadStore(file: file)
            let task = DownloadTask(id: "task_persisted", bookId: "b1", sourceId: "s1", comicId: "c1", chapterId: "ch1", title: "Saved Chapter", order: 1)
            store1.save(task: task)

            let p0 = DownloadPage(index: 0, url: "https://example.com/0.jpg", path: "p0", hash: "h0", bytes: 100)
            store1.savePage(task: "task_persisted", page: p0)

            let detail = ComicDetail(summary: ComicSummary(sourceId: "s1", comicId: "c1", title: "Comic"), author: "A", status: "S", description: "D", latestChapter: "L", chapters: [])
            store1.saveSnapshot(detail)
            store1.close()
        }

        // Reopen in another instance
        let store2 = try DownloadStore(file: file)
        let tasks = store2.list()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, "task_persisted")
        XCTAssertEqual(tasks[0].title, "Saved Chapter")

        let pages = store2.pages(task: "task_persisted")
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].hash, "h0")

        let bookId = try DownloadModels.bookId(source: "s1", comic: "c1")
        let snapshot = store2.snapshot(id: bookId)
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.summary.title, "Comic")
    }

    func testCorruptedFileThrowsError() throws {
        let file = tempDir.appendingPathComponent("downloads.json")
        try "invalid json content { [".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try DownloadStore(file: file)) { error in
            guard let storeErr = error as? DownloadStoreError else {
                XCTFail("Expected DownloadStoreError but got \(error)")
                return
            }
            XCTAssertEqual(storeErr, .storeCorrupted)
        }
    }
}
