import XCTest
@testable import ComicCore

final class LinkedFolderLibraryTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=")!
    private var roots: [URL] = []
    override func tearDownWithError() throws {
        for root in roots { try FileManager.default.removeItem(at: root) }
    }
    private func fixture(paths: [String] = ["01.png", "02.png"], probe: @escaping @Sendable (URL) throws -> Bool = { _ in true },
                         writer: (@Sendable (Data, URL) throws -> Void)? = nil) throws -> (root: URL, external: URL, library: LocalLibrary, store: FolderBookmarkStore, coordinator: LocalFolderSyncCoordinator) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        roots.append(root)
        let external = root.appendingPathComponent("外部漫画", isDirectory: true)
        for path in paths {
            let file = external.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: file)
        }
        let library = try LocalLibrary(directory: root.appendingPathComponent("Local"))
        let store: FolderBookmarkStore
        if let writer { store = try FolderBookmarkStore(directory: root.appendingPathComponent("Bookmarks"), write: writer) }
        else { store = try FolderBookmarkStore(directory: root.appendingPathComponent("Bookmarks")) }
        return (root, external, library, store, LocalFolderSyncCoordinator(store: store, library: library, isReadableImage: probe))
    }
    private func firstBook(_ library: LocalLibrary, _ seriesID: String) async throws -> LocalBook {
        let loaded = try await library.series(id: seriesID)
        let series = try XCTUnwrap(loaded)
        return try library.book(id: XCTUnwrap(series.volumeIDs.first))
    }

    func testIndexOwnsOnlyMetadataAndOneCoverAndReadsPagesThroughRestart() async throws {
        let counter = ProbeControl()
        let f = try fixture(probe: { try counter.probe($0) })
        let record = try await f.coordinator.linkFolder(url: f.external)
        let book = try await firstBook(f.library, record.seriesId)
        let folder = try XCTUnwrap(book.linkedFolder)
        XCTAssertEqual(counter.count, 1, "Only the cover is decoded while indexing")
        XCTAssertEqual(folder.entries.map(\.relativePath), ["01.png", "02.png"])
        let files = try FileManager.default.contentsOfDirectory(atPath: f.library.directory.appendingPathComponent(book.id).path)
        XCTAssertEqual(Set(files), ["book.json", "cover.bin"])
        let urls = try f.library.pageURLs(for: book)
        XCTAssertTrue(urls.allSatisfy { $0.scheme == "xxcomic-folder" })
        XCTAssertEqual(try f.library.ownedImageData(at: urls[1]), png)
        let restarted = try LocalLibrary(directory: f.library.directory)
        XCTAssertEqual(try restarted.ownedImageData(at: urls[1]), png)
        try Data([9, 8, 7]).write(to: f.external.appendingPathComponent("02.png"))
        XCTAssertEqual(try restarted.ownedImageData(at: urls[1]), Data([9, 8, 7]), "Pages are read from the selected folder, not a stale private copy")
    }

    func testReauthorizationOfMovedFolderPreservesIDsAndSavedReading() async throws {
        let f = try fixture(paths: ["第1章/01.png", "第1章/02.png"])
        let record = try await f.coordinator.linkFolder(url: f.external, title: "原书名")
        _ = try await f.library.renameSeries(id: record.seriesId, newTitle: "自定义书名")
        let before = try await firstBook(f.library, record.seriesId)
        let chapters = try await f.library.chapters(for: record.seriesId)
        let beforeURLs = try f.library.pageURLs(for: before)
        let loadedSeries = try await f.library.series(id: record.seriesId)
        let series = try XCTUnwrap(loadedSeries)
        let summary = try f.library.summary(for: series)
        let history = try LibraryStore(directory: f.root.appendingPathComponent("History"))
        let position = ReaderPosition(imageIndex: 1, offset: 0.45)
        try history.saveReading(summary, chapter: chapters[0], chapterIndex: 0, position: position)
        let moved = f.root.appendingPathComponent("移动后的漫画", isDirectory: true)
        try FileManager.default.moveItem(at: f.external, to: moved)
        let updated = try await f.coordinator.reauthorize(id: record.id, url: moved)
        let after = try await firstBook(f.library, record.seriesId)
        let newChapters = try await f.library.chapters(for: record.seriesId)
        XCTAssertEqual(updated.id, record.id); XCTAssertEqual(updated.seriesId, record.seriesId)
        XCTAssertEqual(after.id, before.id); XCTAssertEqual(after.pages, before.pages)
        XCTAssertEqual(newChapters.map(\.chapterId), chapters.map(\.chapterId))
        XCTAssertEqual(try f.library.ownedImageData(at: beforeURLs[1]), png)
        let restored = try LibraryStore(directory: f.root.appendingPathComponent("History"))
        XCTAssertEqual(restored.position(for: summary, chapterID: chapters[0].chapterId), position)
        let loadedAfter = try await f.library.series(id: record.seriesId)
        let afterSeries = try XCTUnwrap(loadedAfter)
        XCTAssertEqual(afterSeries.displayTitle, "自定义书名")
    }

    func testAddedChapterDoesNotStealExistingChapterAndRenamedPageKeepsIdentity() async throws {
        let f = try fixture(paths: ["第2章/01.png", "第3章/01.png"])
        let record = try await f.coordinator.linkFolder(url: f.external)
        let before = try await firstBook(f.library, record.seriesId)
        let oldPage = try XCTUnwrap(before.linkedFolder?.entries.first { $0.relativePath == "第2章/01.png" })
        let oldChapters = try XCTUnwrap(before.chapters)
        let added = f.external.appendingPathComponent("第1章/01.png")
        try FileManager.default.createDirectory(at: added.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: added)
        try FileManager.default.moveItem(at: f.external.appendingPathComponent("第2章/01.png"), to: f.external.appendingPathComponent("第2章/02.png"))
        let result = await f.coordinator.sync(id: record.id)
        XCTAssertEqual(result, .updated(oldFileCount: 2, newFileCount: 3))
        let after = try await firstBook(f.library, record.seriesId)
        for old in oldChapters { XCTAssertEqual(after.chapters?.first { $0.title == old.title }?.id, old.id) }
        XCTAssertEqual(Set(after.chapters!.map(\.id)).count, 3)
        XCTAssertEqual(after.linkedFolder?.entries.first { $0.relativePath == "第2章/02.png" }?.pageID, oldPage.pageID)
        XCTAssertEqual(try f.library.ownedImageData(at: LinkedFolderPageURL.make(bookID: before.id, pageID: oldPage.pageID)), png)
    }

    func testAuthorizationWriteFailureRollsBackBookAndCatalog() async throws {
        let failure = WriteControl()
        let f = try fixture(writer: { try failure.write($0, $1) })
        let record = try await f.coordinator.linkFolder(url: f.external)
        let beforeBook = try await firstBook(f.library, record.seriesId)
        let beforeSeries = try await f.library.series(id: record.seriesId)
        try png.write(to: f.external.appendingPathComponent("03.png"))
        failure.shouldFail = true
        guard case .error = await f.coordinator.sync(id: record.id) else { return XCTFail("A failed authorization write must not report success") }
        XCTAssertEqual(f.store.record(id: record.id), record)
        XCTAssertEqual(try f.library.book(id: beforeBook.id), beforeBook)
        let afterSeries = try await f.library.series(id: record.seriesId)
        XCTAssertEqual(afterSeries, beforeSeries)
        XCTAssertEqual(try f.library.ownedImageData(at: f.library.pageURLs(for: beforeBook)[0]), png)
    }

    func testLegacyCopiedFolderMigratesWithoutChangingVolumeOrChapterIdentity() async throws {
        let f = try fixture(paths: ["第1章/01.png", "第2章/01.png"])
        let copied = try await f.library.importFolderCoordinated(title: "旧版文件夹", folder: f.external, isReadableImage: { _ in true })
        let record = SyncedFolderRecord(folderName: copied.series.displayTitle, bookmarkData: try BatchImportWorker.createBookmark(for: f.external),
                                        seriesId: copied.series.id, fileCount: copied.book.pages.count)
        try f.store.save(record: record)
        let result = await f.coordinator.sync(id: record.id)
        XCTAssertEqual(result, .updated(oldFileCount: 2, newFileCount: 2))
        let migrated = try await firstBook(f.library, record.seriesId)
        XCTAssertEqual(migrated.id, copied.book.id)
        XCTAssertEqual(migrated.chapters?.map(\.id), copied.book.chapters?.map(\.id))
        XCTAssertNotNil(migrated.linkedFolder)
        let files = try FileManager.default.contentsOfDirectory(atPath: f.library.directory.appendingPathComponent(migrated.id).path)
        XCTAssertEqual(Set(files), ["book.json", "cover.bin"])
        XCTAssertEqual(try f.library.ownedImageData(at: f.library.pageURLs(for: migrated)[1]), png)
    }

    func testCancellationDuringIndexKeepsOldBookAndAuthorizationRecord() async throws {
        let probe = ProbeControl()
        let f = try fixture(probe: { try probe.probe($0) })
        let record = try await f.coordinator.linkFolder(url: f.external)
        let before = try await firstBook(f.library, record.seriesId)
        try png.write(to: f.external.appendingPathComponent("03.png"))
        probe.blockNext = true
        let operation = Task { await f.coordinator.sync(id: record.id) }
        XCTAssertEqual(probe.entered.wait(timeout: .now() + 5), .success)
        operation.cancel(); probe.release.signal()
        guard case .error(let message) = await operation.value else { return XCTFail("Canceled scan must not report a committed update") }
        XCTAssertTrue(message.contains("取消"))
        XCTAssertEqual(try f.library.book(id: before.id), before)
        XCTAssertEqual(f.store.record(id: record.id), record)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: f.library.directory.path)
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".import-") || $0.hasPrefix(".backup-") })
    }

    func testUnlinkRetainsReadableBookAndRelinkDoesNotDuplicateIt() async throws {
        let f = try fixture()
        let record = try await f.coordinator.linkFolder(url: f.external)
        let before = try await firstBook(f.library, record.seriesId)
        let url = try f.library.pageURLs(for: before)[0]
        try await f.coordinator.unlinkFolder(id: record.id)
        XCTAssertNil(f.store.record(id: record.id))
        XCTAssertEqual(try f.library.ownedImageData(at: url), png)
        let relinked = try await f.coordinator.linkFolder(url: f.external)
        XCTAssertEqual(relinked.id, record.id); XCTAssertEqual(relinked.seriesId, record.seriesId)
        let all = try await f.library.series()
        XCTAssertEqual(all.count, 1)
    }

    func testConcurrentLinkUsesOneSeriesAndDeletionPreservesOriginalFiles() async throws {
        let f = try fixture()
        let records = try await withThrowingTaskGroup(of: SyncedFolderRecord.self) { group in
            for _ in 0..<4 { group.addTask { try await f.coordinator.linkFolder(url: f.external) } }
            var result: [SyncedFolderRecord] = []
            for try await record in group { result.append(record) }
            return result
        }
        XCTAssertEqual(Set(records.map(\.seriesId)).count, 1)
        let record = records[0]
        try await f.coordinator.deleteSeries(id: record.seriesId)
        XCTAssertTrue(f.store.list().isEmpty)
        XCTAssertEqual(try Data(contentsOf: f.external.appendingPathComponent("01.png")), png)
        XCTAssertEqual(try Data(contentsOf: f.external.appendingPathComponent("02.png")), png)
        let deleted = try await f.library.series(id: record.seriesId)
        XCTAssertNil(deleted)
        let restored = try await f.coordinator.linkFolder(url: f.external)
        XCTAssertEqual(restored.seriesId, record.seriesId, "Folder tombstones restore the stable series identity")
    }

    func testPageAccessRejectsLinksTraversalAndPrivateMetadata() async throws {
        let f = try fixture(paths: ["第1章/01.png"])
        let record = try await f.coordinator.linkFolder(url: f.external)
        let book = try await firstBook(f.library, record.seriesId)
        let page = try f.library.pageURLs(for: book)[0]
        let outside = f.root.appendingPathComponent("outside.png"); try png.write(to: outside)
        let image = f.external.appendingPathComponent("第1章/01.png")
        try FileManager.default.removeItem(at: image)
        try FileManager.default.createSymbolicLink(at: image, withDestinationURL: outside)
        XCTAssertThrowsError(try f.library.ownedImageData(at: page))
        XCTAssertThrowsError(try f.library.ownedImageData(at: f.library.directory.appendingPathComponent(book.id).appendingPathComponent("book.json")))
        for text in ["xxcomic-folder://page/../../outside.png", page.absoluteString + "?file=outside.png", page.absoluteString + "#fragment", page.absoluteString.replacingOccurrences(of: "//page/", with: "//user@page/")] {
            XCTAssertThrowsError(try f.library.ownedImageData(at: XCTUnwrap(URL(string: text))))
        }
    }

    func testOwnedCoverAndImageReaderUsesExactLibraryAndRejectsUnknownFile() throws {
        let f = try fixture()
        let book = try f.library.importImages(title: "拥有副本", files: [f.external.appendingPathComponent("01.png")])
        XCTAssertEqual(try f.library.ownedImageData(at: f.library.pageURLs(for: book)[0]), png)
        let unknown = f.library.directory.appendingPathComponent(book.id).appendingPathComponent("unknown.png")
        try png.write(to: unknown)
        XCTAssertThrowsError(try f.library.ownedImageData(at: unknown))
        XCTAssertThrowsError(try f.library.deleteOwnedDirectory(unknown.deletingLastPathComponent()))
        XCTAssertEqual(try Data(contentsOf: unknown), png)
        XCTAssertNotNil(try f.library.book(id: book.id))
    }

    func testSavedPageIdentityResumesTheSamePageAfterAnEarlierInsertion() async throws {
        let f = try fixture()
        let record = try await f.coordinator.linkFolder(url: f.external)
        let before = try await firstBook(f.library, record.seriesId)
        let oldURLs = try f.library.pageURLs(for: before).map(\.absoluteString)
        let position = ReaderPosition(imageIndex: 1, offset: 0.6, linkedPageID: ReaderPosition.linkedIdentity(in: oldURLs[1]))
        let ended = ReaderPosition(imageIndex: 1, offset: 0.6, atEnd: true,
                                   linkedPageID: position.linkedPageID, linkedTailID: position.linkedPageID)
        let bytes = try JSONEncoder().encode(position)
        let restored = try JSONDecoder().decode(ReaderPosition.self, from: bytes)
        try png.write(to: f.external.appendingPathComponent("00.png"))
        let result = await f.coordinator.sync(id: record.id)
        XCTAssertEqual(result, .updated(oldFileCount: 2, newFileCount: 3))
        let after = try await firstBook(f.library, record.seriesId)
        let newURLs = try f.library.pageURLs(for: after).map(\.absoluteString)
        XCTAssertEqual(restored.index(in: newURLs), 2)
        XCTAssertEqual(newURLs[restored.index(in: newURLs)], oldURLs[1])
        XCTAssertEqual(restored.offset, 0.6)
        let legacy = try JSONDecoder().decode(ReaderPosition.self, from: Data(#"{"imageIndex":1,"offset":0.6,"atEnd":false}"#.utf8))
        XCTAssertNil(legacy.linkedPageID)
        XCTAssertEqual(legacy.index(in: newURLs), 1)
        XCTAssertTrue(ended.isAtEnd(in: newURLs))
        try png.write(to: f.external.appendingPathComponent("03.png"))
        _ = await f.coordinator.sync(id: record.id)
        let appendedBook = try await firstBook(f.library, record.seriesId)
        let appended = try f.library.pageURLs(for: appendedBook).map(\.absoluteString)
        XCTAssertFalse(ended.isAtEnd(in: appended), "New pages must not be skipped by the old end marker")
        XCTAssertEqual(ended.index(in: appended), 2)
    }

    func testAddingAnotherFolderPreservesTheFormerWrapperChapter() async throws {
        let f = try fixture(paths: ["第2章/01.png", "第2章/02.png"])
        let record = try await f.coordinator.linkFolder(url: f.external)
        let before = try await firstBook(f.library, record.seriesId)
        let oldID = try XCTUnwrap(before.chapters?.first?.id)
        let added = f.external.appendingPathComponent("第1章/01.png")
        try FileManager.default.createDirectory(at: added.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: added)
        _ = await f.coordinator.sync(id: record.id)
        let after = try await firstBook(f.library, record.seriesId)
        XCTAssertEqual(after.chapters?.first { $0.title == "第2章" }?.id, oldID)
        XCTAssertEqual(Set(after.chapters!.map(\.id)).count, 2)
    }
}

private final class WriteControl: @unchecked Sendable {
    private let lock = NSLock()
    private var fail = false
    var shouldFail: Bool { get { lock.lock(); defer { lock.unlock() }; return fail } set { lock.lock(); fail = newValue; lock.unlock() } }
    func write(_ data: Data, _ url: URL) throws {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        try data.write(to: url, options: .atomic)
    }
}
private final class ProbeControl: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0, blocking = false
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var blockNext: Bool { get { lock.lock(); defer { lock.unlock() }; return blocking } set { lock.lock(); blocking = newValue; lock.unlock() } }
    func probe(_ url: URL) throws -> Bool {
        lock.lock(); calls += 1; let block = blocking; blocking = false; lock.unlock()
        if block { entered.signal(); _ = release.wait(timeout: .now() + 10) }
        try Task.checkCancellation()
        return true
    }
}
