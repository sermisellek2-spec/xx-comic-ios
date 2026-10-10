import XCTest
@testable import ComicCore

final class LocalFolderSyncTests: XCTestCase {
    private func createFixtureFolder(files: [String: UInt8]) throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = temp.appendingPathComponent("external_manga")
        for (relativePath, byte) in files {
            let fileURL = folder.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([byte]).write(to: fileURL)
        }
        return folder
    }

    func testLinkFolderAndSyncLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let externalFolder = try createFixtureFolder(files: [
            "01.jpg": 1,
            "02.jpg": 2
        ])
        defer { try? FileManager.default.removeItem(at: externalFolder.deletingLastPathComponent()) }

        let library = try LocalLibrary(directory: root.appendingPathComponent("Local"))
        let bookmarkStore = try FolderBookmarkStore(directory: root.appendingPathComponent("Bookmarks"))

        let coordinator = LocalFolderSyncCoordinator(
            store: bookmarkStore,
            library: library,
            isReadableImage: { _ in true }
        )

        // 1. Link folder
        let record = try await coordinator.linkFolder(url: externalFolder, title: "我的漫画")
        XCTAssertEqual(record.folderName, "我的漫画")
        XCTAssertEqual(record.fileCount, 2)
        XCTAssertEqual(record.status, .active)

        let initialSeries = try await library.series(id: record.seriesId)
        XCTAssertNotNil(initialSeries)
        XCTAssertEqual(initialSeries?.volumeIDs.count, 1)

        // 2. Sync with no changes -> up to date
        let sync1 = await coordinator.sync(id: record.id)
        XCTAssertEqual(sync1, .upToDate(fileCount: 2))

        // 3. Add a new file in external folder
        let newFile = externalFolder.appendingPathComponent("03.jpg")
        try Data([3]).write(to: newFile)

        let sync2 = await coordinator.sync(id: record.id)
        XCTAssertEqual(sync2, .updated(oldFileCount: 2, newFileCount: 3))

        let updatedSeries = try await library.series(id: record.seriesId)
        let updatedBook = try updatedSeries.flatMap { try library.volumes(for: $0).first }
        XCTAssertEqual(updatedBook?.pages.count, 3)

        // 4. Remove a file in external folder
        try FileManager.default.removeItem(at: externalFolder.appendingPathComponent("01.jpg"))

        let sync3 = await coordinator.sync(id: record.id)
        XCTAssertEqual(sync3, .updated(oldFileCount: 3, newFileCount: 2))

        let afterRemovalSeries = try await library.series(id: record.seriesId)
        let afterRemovalBook = try afterRemovalSeries.flatMap { try library.volumes(for: $0).first }
        XCTAssertEqual(afterRemovalBook?.pages.count, 2)

        // 5. External folder removed -> reports error and status
        try FileManager.default.removeItem(at: externalFolder)
        let sync4 = await coordinator.sync(id: record.id)
        guard case .error = sync4 else {
            return XCTFail("Expected error result when folder is missing")
        }
        let recordMissing = bookmarkStore.record(id: record.id)
        XCTAssertTrue(recordMissing?.status == .folderMissing || recordMissing?.status == .permissionRevoked)

        // 6. Unlink folder
        try await coordinator.unlinkFolder(id: record.id, deleteSeries: true)
        XCTAssertNil(bookmarkStore.record(id: record.id))
        let deletedSeries = try await library.series(id: record.seriesId)
        XCTAssertNil(deletedSeries)
    }

    func testSyncAllBatchesMultipleFolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let folder1 = try createFixtureFolder(files: ["01.jpg": 1])
        let folder2 = try createFixtureFolder(files: ["01.jpg": 2, "02.jpg": 3])
        defer {
            try? FileManager.default.removeItem(at: folder1.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: folder2.deletingLastPathComponent())
        }

        let library = try LocalLibrary(directory: root.appendingPathComponent("Local"))
        let bookmarkStore = try FolderBookmarkStore(directory: root.appendingPathComponent("Bookmarks"))
        let coordinator = LocalFolderSyncCoordinator(
            store: bookmarkStore,
            library: library,
            isReadableImage: { _ in true }
        )

        let rec1 = try await coordinator.linkFolder(url: folder1, title: "文件夹1")
        let rec2 = try await coordinator.linkFolder(url: folder2, title: "文件夹2")

        let results = await coordinator.syncAll()
        XCTAssertEqual(results[rec1.id], .upToDate(fileCount: 1))
        XCTAssertEqual(results[rec2.id], .upToDate(fileCount: 2))
    }

    func testFolderIdentityStabilityAndRollbackOnFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let externalFolder = try createFixtureFolder(files: ["01.jpg": 1])
        defer { try? FileManager.default.removeItem(at: externalFolder.deletingLastPathComponent()) }

        let library = try LocalLibrary(directory: root.appendingPathComponent("Local"))
        let bookmarkStore = try FolderBookmarkStore(directory: root.appendingPathComponent("Bookmarks"))
        let coordinator = LocalFolderSyncCoordinator(
            store: bookmarkStore,
            library: library,
            isReadableImage: { _ in true }
        )

        let record = try await coordinator.linkFolder(url: externalFolder, title: "稳定测试")
        let beforeSeries = try await library.series(id: record.seriesId)!
        let beforeChapters = try await library.chapters(for: beforeSeries.id)
        let source = LocalComicSource(library: library)
        let beforePage = try await source.chapter(url: beforeChapters[0].url)
        XCTAssertFalse(beforePage.imageUrls.isEmpty)

        // 1. Add file and sync: seriesId, volumeId, and chapterId must remain stable
        try Data([2]).write(to: externalFolder.appendingPathComponent("02.jpg"))
        let syncResult = await coordinator.sync(id: record.id)
        XCTAssertEqual(syncResult, .updated(oldFileCount: 1, newFileCount: 2))

        let afterSeries = try await library.series(id: record.seriesId)!
        let afterChapters = try await library.chapters(for: afterSeries.id)
        XCTAssertEqual(beforeSeries.id, afterSeries.id, "Series ID must be stable")
        XCTAssertEqual(beforeSeries.volumeIDs, afterSeries.volumeIDs, "Volume ID must be stable across sync")
        XCTAssertEqual(beforeChapters[0].chapterId, afterChapters[0].chapterId, "Chapter ID must be stable")

        // Old chapter URL must still be readable
        let readableAfter = try await source.chapter(url: beforeChapters[0].url)
        XCTAssertEqual(readableAfter.imageUrls.count, 2)

        // 2. Inject catalog write failure: original book on disk must remain readable
        let catalogFile = await library.catalogStore.fileURL
        try FileManager.default.removeItem(at: catalogFile)
        try FileManager.default.createDirectory(at: catalogFile, withIntermediateDirectories: true)

        try Data([3]).write(to: externalFolder.appendingPathComponent("03.jpg"))
        let failureSync = await coordinator.sync(id: record.id)
        guard case .error = failureSync else {
            return XCTFail("Sync should fail when catalog store cannot write")
        }

        // Previous volume must still exist and be readable on disk
        let stillExistingBook = try library.book(id: afterSeries.volumeIDs[0])
        XCTAssertEqual(stillExistingBook.id, afterSeries.volumeIDs[0])
        let stillReadable = try await source.chapter(url: beforeChapters[0].url)
        XCTAssertEqual(stillReadable.imageUrls.count, 2)
    }

    func testSingleWriterGateMutualExclusion() async {
        let gate = SingleWriterGate()
        actor OverlapTracker {
            var active = 0
            var maximum = 0
            func enter() {
                active += 1
                maximum = max(maximum, active)
            }
            func leave() {
                active -= 1
            }
        }
        let tracker = OverlapTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await gate.execute {
                        await tracker.enter()
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        await tracker.leave()
                    }
                }
            }
        }

        let maxOverlap = await tracker.maximum
        XCTAssertEqual(maxOverlap, 1, "SingleWriterGate must strictly enforce mutual exclusion (max 1 simultaneous block)")
    }

    func testInterruptedSyncRecoveryRestoresBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let externalFolder = try createFixtureFolder(files: [
            "01.jpg": 1,
            "02.jpg": 2
        ])
        defer { try? FileManager.default.removeItem(at: externalFolder.deletingLastPathComponent()) }

        let localPath = root.appendingPathComponent("Local")
        let library = try LocalLibrary(directory: localPath)

        let result = try await library.importFolderCoordinated(
            title: "RecoveryTest",
            folder: externalFolder,
            isReadableImage: { _ in true }
        )

        let volId = result.book.id
        let volumeDir = localPath.appendingPathComponent(volId)
        let backupDir = localPath.appendingPathComponent(".backup-" + volId + "-" + UUID().uuidString)

        // Simulate crash right after volume renamed to backup, before new publish completes
        try FileManager.default.moveItem(at: volumeDir, to: backupDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: volumeDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupDir.path))

        // Restart library and trigger recovery
        let restartedLibrary = try LocalLibrary(directory: localPath)
        try await restartedLibrary.recoverOrphans()

        // Verify volume was safely restored and readable
        XCTAssertTrue(FileManager.default.fileExists(atPath: volumeDir.path), "Target volume directory must be restored")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupDir.path), "Backup directory must be cleaned up after successful restore")

        let recoveredBook = try restartedLibrary.book(id: volId)
        XCTAssertEqual(recoveredBook.id, volId)
        XCTAssertEqual(recoveredBook.pages.count, 2)

        let recoveredSeries = try await restartedLibrary.series(id: result.series.id)
        XCTAssertEqual(recoveredSeries?.volumeIDs, [volId])
    }

    func testMalformedBackupDirectoryNamePreservesLibraryAndIgnored() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let externalFolder = try createFixtureFolder(files: ["01.jpg": 1])
        defer { try? FileManager.default.removeItem(at: externalFolder.deletingLastPathComponent()) }

        let localPath = root.appendingPathComponent("Local")
        let library = try LocalLibrary(directory: localPath)
        let result = try await library.importFolderCoordinated(
            title: "SafeBook",
            folder: externalFolder,
            isReadableImage: { _ in true }
        )

        // Inject malformed backup containing ".." path traversal
        let malformedBackup = localPath.appendingPathComponent(".backup-..-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: malformedBackup, withIntermediateDirectories: true)
        try Data([9]).write(to: malformedBackup.appendingPathComponent("dummy.txt"))

        try await library.recoverOrphans()

        // Verify library root and existing book are completely preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: localPath.path), "Local library root must not be deleted")
        let book = try library.book(id: result.book.id)
        XCTAssertEqual(book.id, result.book.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: malformedBackup.path), "Malformed backup directory must be left intact")
    }

    func testTargetMissingPageRestoresCompleteBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let externalFolder = try createFixtureFolder(files: [
            "01.jpg": 1,
            "02.jpg": 2
        ])
        defer { try? FileManager.default.removeItem(at: externalFolder.deletingLastPathComponent()) }

        let localPath = root.appendingPathComponent("Local")
        let library = try LocalLibrary(directory: localPath)
        let result = try await library.importFolderCoordinated(
            title: "MissingPageTest",
            folder: externalFolder,
            isReadableImage: { _ in true }
        )

        let volId = result.book.id
        let volumeDir = localPath.appendingPathComponent(volId)
        let backupDir = localPath.appendingPathComponent(".backup-" + volId + "-" + UUID().uuidString)

        // Make an exact intact copy as backup
        try FileManager.default.copyItem(at: volumeDir, to: backupDir)

        // Delete second page from the target volume to simulate corruption
        let pages = try library.pageURLs(for: result.book)
        let page2 = pages[1]
        try FileManager.default.removeItem(at: page2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: page2.path))

        // Run recovery
        try await library.recoverOrphans()

        // Page 2 must now exist because it was restored from the complete backup
        XCTAssertTrue(FileManager.default.fileExists(atPath: page2.path), "Missing page must be restored from intact backup")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupDir.path), "Intact backup must be consumed and moved to target")

        let recoveredBook = try library.book(id: volId)
        XCTAssertEqual(recoveredBook.pages.count, 2)
    }
}
