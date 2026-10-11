import XCTest
@testable import ComicCore

private struct DeletionSource: DownloadSourceResolverProtocol {
    func resolveChapter(sourceId: String, url: String) async throws -> ChapterPage {
        ChapterPage(chapterId: "chapter", title: "Chapter", imageUrls: ["https://fixture.invalid/page"])
    }
    func resolveReferer(sourceId: String, chapterUrl: String) -> String { "" }
    func fetchCover(sourceId: String, coverUrl: String, destination: URL, check: @escaping () throws -> Void) async throws { try check() }
}
private struct DeletionImageFetcher: DownloadImageFetcherProtocol {
    let started: XCTestExpectation
    func fetch(sourceId: String, url: String, referer: String, destination: URL,
               check: @escaping () throws -> Void) async throws -> (bytes: Int64, hash: String) {
        try check()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("in progress".utf8).write(to: destination)
        started.fulfill()
        // The worker must observe its invalidated lease and release its files.
        while true { try await Task.sleep(nanoseconds: 10_000_000); try check() }
    }
}

final class DownloadDeletionTests: XCTestCase {
    private func fixture() throws -> (URL, DownloadRuntime, DownloadTask) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try DownloadStore(directory: root)
        let downloads = root.appendingPathComponent("copies")
        let runtime = DownloadRuntime(store: store, downloadsDirectory: downloads)
        let task = DownloadTask(id: try DownloadModels.key("source", "comic", "chapter"), bookId: try DownloadModels.bookId(source: "source", comic: "comic"),
            sourceId: "source", comicId: "comic", chapterId: "chapter", state: .completed)
        store.save(task: task)
        let path = downloads.appendingPathComponent(task.bookId).appendingPathComponent(task.id)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try Data("page".utf8).write(to: path.appendingPathComponent("0.img"))
        return (root, runtime, task)
    }

    func testDeleteRemovesOnlyConfirmedBookAndPersistsTaskRemoval() async throws {
        let (root, runtime, task) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let unknown = runtime.downloadsDirectory.appendingPathComponent("unrelated-original.txt")
        try Data("keep".utf8).write(to: unknown)
        try await runtime.deleteBook(bookId: task.bookId)
        XCTAssertNil(runtime.store.get(id: task.id))
        XCTAssertNil(try DownloadStore(directory: root).get(id: task.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.downloadsDirectory.appendingPathComponent(task.bookId).path))
        XCTAssertEqual(try Data(contentsOf: unknown), Data("keep".utf8))
    }

    func testUnknownFileRefusesDeletionAndKeepsCompletedBookReadable() async throws {
        let (root, runtime, task) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let unknown = runtime.downloadsDirectory.appendingPathComponent(task.bookId).appendingPathComponent("user-original.txt")
        try Data("keep".utf8).write(to: unknown)
        do { try await runtime.deleteBook(bookId: task.bookId); XCTFail("Unknown files must not be recursively removed") } catch { }
        XCTAssertEqual(runtime.store.get(id: task.id)?.state, .completed)
        XCTAssertEqual(try Data(contentsOf: unknown), Data("keep".utf8))
    }
    func testUnknownChapterFileKeepsRecordAndReturnsVisibleDeletionFailure() async throws {
        let (root, runtime, task) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = runtime.downloadsDirectory.appendingPathComponent(task.bookId).appendingPathComponent(task.id).appendingPathComponent("original.txt")
        try Data("keep".utf8).write(to: original)
        do { try await runtime.cancel(id: task.id); XCTFail("Unknown chapter original must not disappear") } catch { }
        XCTAssertEqual(runtime.store.get(id: task.id)?.state, .completed)
        XCTAssertEqual(try Data(contentsOf: original), Data("keep".utf8))
    }
    func testChapterRemovalPersistenceFailureDoesNotDropDatabaseRecord() async throws {
        let (root, runtime, task) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let database = runtime.store.fileURL
        try FileManager.default.removeItem(at: database)
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: false)
        XCTAssertThrowsError(try runtime.store.removeConfirmedTask(task.id))
        XCTAssertNotNil(runtime.store.get(id: task.id))
    }
    func testCancellingActiveChapterWaitsForActualWriterBeforeRemovingPartFiles() async throws {
        let (root, runtime, task) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        runtime.store.remove(task: task.id)
        let started = expectation(description: "partial file is being written")
        runtime.imageFetcher = DeletionImageFetcher(started: started); runtime.sourceResolver = DeletionSource()
        let chapter = Chapter(chapterId: "chapter", title: "Chapter", url: "https://fixture.invalid/chapter")
        runtime.enqueue(detail: ComicDetail(summary: ComicSummary(sourceId: "source", comicId: "comic", title: "Test"),
            author: "", status: "", description: "", latestChapter: "", chapters: [chapter]), selectedChapterIds: ["chapter"])
        await fulfillment(of: [started], timeout: 3)
        try await runtime.cancel(id: task.id)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(runtime.store.get(id: task.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.downloadsDirectory.appendingPathComponent(task.bookId).appendingPathComponent(task.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.downloadsDirectory.appendingPathComponent(task.bookId).path))
    }

    func testBookDirectorySymlinkCannotDeleteExternalOriginal() async throws {
        let (root, runtime, task) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let book = runtime.downloadsDirectory.appendingPathComponent(task.bookId)
        try FileManager.default.removeItem(at: book)
        let external = root.appendingPathComponent("originals")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: external.appendingPathComponent("original.txt"))
        try FileManager.default.createSymbolicLink(at: book, withDestinationURL: external)
        do { try await runtime.deleteBook(bookId: task.bookId); XCTFail("Symlink deletion must be refused") } catch { }
        XCTAssertEqual(runtime.store.get(id: task.id)?.state, .completed)
        XCTAssertEqual(try Data(contentsOf: external.appendingPathComponent("original.txt")), Data("keep".utf8))
    }
    func testChapterDeletionCannotFollowBookAncestorSymbolicLink() async throws {
        let (root, runtime, task) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let book = runtime.downloadsDirectory.appendingPathComponent(task.bookId)
        try FileManager.default.removeItem(at: book)
        let external = root.appendingPathComponent("originals"), chapter = external.appendingPathComponent(task.id)
        try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true)
        let original = chapter.appendingPathComponent("0.img"); try Data("original image".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: book, withDestinationURL: external)
        do { try await runtime.deleteChapter(id: task.id); XCTFail("Parent link cannot authorize deleting a known-looking image") } catch { }
        XCTAssertEqual(runtime.store.get(id: task.id)?.state, .completed)
        XCTAssertEqual(try Data(contentsOf: original), Data("original image".utf8))
    }

    func testCorruptIdentityCannotSelectParentOrUnknownDirectory() async throws {
        let (root, runtime, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let task = DownloadTask(id: "malformed", bookId: "../", sourceId: "source", comicId: "comic", chapterId: "chapter")
        runtime.store.save(task: task)
        do { try await runtime.deleteBook(bookId: "../"); XCTFail("Invalid identity must be refused") } catch { }
        XCTAssertNotNil(runtime.store.get(id: "malformed"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testDeletingActiveBookWaitsForWorkerAndCannotRecreateFiles() async throws {
        let (root, runtime, task) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        runtime.store.remove(task: task.id)
        let started = expectation(description: "actual partial file opened")
        runtime.imageFetcher = DeletionImageFetcher(started: started); runtime.sourceResolver = DeletionSource()
        let comic = ComicSummary(sourceId: "source", comicId: "comic", title: "Test")
        let chapter = Chapter(chapterId: "chapter", title: "Chapter", url: "https://fixture.invalid/chapter")
        let detail = ComicDetail(summary: comic, author: "", status: "", description: "", latestChapter: "", chapters: [chapter])
        runtime.enqueue(detail: detail, selectedChapterIds: [chapter.chapterId])
        await fulfillment(of: [started], timeout: 3)
        try await runtime.deleteBook(bookId: task.bookId)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(runtime.store.get(id: task.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.downloadsDirectory.appendingPathComponent(task.bookId).path))
        XCTAssertNil(runtime.store.snapshot(id: task.bookId))
    }
}
