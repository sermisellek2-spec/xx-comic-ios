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
        XCTAssertEqual(recordMissing?.status, .folderMissing)

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
}
