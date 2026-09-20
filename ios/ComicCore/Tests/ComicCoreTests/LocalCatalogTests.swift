import XCTest
@testable import ComicCore

final class LocalCatalogTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testNonExistentCatalogInitializesEmptyAndNotOnDisk() async throws {
        let store = try LocalCatalogStore(directory: tempDirectory)
        let exists = await store.existsOnDisk()
        XCTAssertFalse(exists)
        let series = await store.listSeries()
        XCTAssertEqual(series, [])
        let tombstones = await store.listTombstones()
        XCTAssertEqual(tombstones, [])
    }

    func testCommitNewSeriesPersistsAtomicallyAndCanBeReloaded() async throws {
        let store = try LocalCatalogStore(directory: tempDirectory)
        let now = Date().timeIntervalSince1970
        let series = LocalSeriesRecord(id: UUID().uuidString, originalTitle: "测试漫画", userTitle: "自定义标题",
                                       volumeIDs: [UUID().uuidString], createdAt: now, updatedAt: now)
        try await store.commitNewSeries(series)

        let exists = await store.existsOnDisk()
        XCTAssertTrue(exists)

        // Reload from disk in a fresh store instance
        let reloadedStore = try LocalCatalogStore(directory: tempDirectory)
        let reloadedSeries = await reloadedStore.listReadySeries()
        XCTAssertEqual(reloadedSeries.count, 1)
        XCTAssertEqual(reloadedSeries.first?.id, series.id)
        XCTAssertEqual(reloadedSeries.first?.originalTitle, "测试漫画")
        XCTAssertEqual(reloadedSeries.first?.userTitle, "自定义标题")
        XCTAssertEqual(reloadedSeries.first?.displayTitle, "自定义标题")
        XCTAssertEqual(reloadedSeries.first?.volumeIDs, series.volumeIDs)
    }

    func testUnsupportedVersionThrowsAndKeepsFile() async throws {
        let file = tempDirectory.appendingPathComponent("catalog.json")
        let unsupported = LocalCatalog(version: 99, series: [], tombstones: [])
        let data = try JSONEncoder().encode(unsupported)
        try data.write(to: file)

        do {
            _ = try LocalCatalogStore(directory: tempDirectory)
            XCTFail("Should throw unsupportedVersion")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .unsupportedVersion)
        }

        // Verify original file is kept intact
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let remainingData = try Data(contentsOf: file)
        XCTAssertEqual(remainingData, data)
    }

    func testCorruptedCatalogThrowsAndKeepsFile() async throws {
        let file = tempDirectory.appendingPathComponent("catalog.json")
        let badData = Data("INVALID_JSON_CORRUPTED".utf8)
        try badData.write(to: file)

        do {
            _ = try LocalCatalogStore(directory: tempDirectory)
            XCTFail("Should throw catalogCorrupted")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .catalogCorrupted)
        }

        // Verify original file was preserved, not overwritten as empty catalog
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let remainingData = try Data(contentsOf: file)
        XCTAssertEqual(remainingData, badData)
    }

    func testFileExceeding16MiBThrowsCatalogTooLarge() async throws {
        let file = tempDirectory.appendingPathComponent("catalog.json")
        // Create sparse file or 16MiB + 1 byte
        let oversizedSize = LocalCatalog.maxFileBytes + 1
        let handle = try FileHandle(forWritingTo: {
            FileManager.default.createFile(atPath: file.path, contents: nil)
            return file
        }())
        try handle.truncate(atOffset: UInt64(oversizedSize))
        try handle.close()

        do {
            _ = try LocalCatalogStore(directory: tempDirectory)
            XCTFail("Should throw catalogTooLarge")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .catalogTooLarge)
        }
    }

    func testWriteFailureRollsBackMemoryState() async throws {
        // Create store pointing to a valid directory
        let store = try LocalCatalogStore(directory: tempDirectory)
        let now = Date().timeIntervalSince1970
        let series1 = LocalSeriesRecord(id: "s1", originalTitle: "一", userTitle: nil, volumeIDs: ["v1"],
                                        createdAt: now, updatedAt: now)
        try await store.commitNewSeries(series1)

        // Make the catalog file a directory to force atomic write failure
        let catalogFile = tempDirectory.appendingPathComponent("catalog.json")
        try FileManager.default.removeItem(at: catalogFile)
        try FileManager.default.createDirectory(at: catalogFile, withIntermediateDirectories: false)

        let series2 = LocalSeriesRecord(id: "s2", originalTitle: "二", userTitle: nil, volumeIDs: ["v2"],
                                        createdAt: now, updatedAt: now)

        do {
            try await store.commitNewSeries(series2)
            XCTFail("Should fail write")
        } catch {
            // Write failed
        }

        // Memory should be rolled back to series1 only
        let currentSeries = await store.listSeries()
        XCTAssertEqual(currentSeries.map(\.id), ["s1"])
    }

    func testRenameSeriesValidatesAndroidTrimAndRejectsEmpty() async throws {
        let store = try LocalCatalogStore(directory: tempDirectory)
        let now = Date().timeIntervalSince1970
        let series = LocalSeriesRecord(id: "s1", originalTitle: "原始标题", userTitle: nil, volumeIDs: ["v1"],
                                       createdAt: now, updatedAt: now)
        try await store.commitNewSeries(series)

        // Empty string rejects
        do {
            _ = try await store.renameSeries(id: "s1", newTitle: "")
            XCTFail("Should throw titleEmpty")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .titleEmpty)
        }

        // Whitespace only rejects
        do {
            _ = try await store.renameSeries(id: "s1", newTitle: "   \n\t  ")
            XCTFail("Should throw titleEmpty")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .titleEmpty)
        }

        // Trims leading/trailing whitespace
        let updated = try await store.renameSeries(id: "s1", newTitle: "  新标题  ")
        XCTAssertEqual(updated.userTitle, "新标题")
        XCTAssertEqual(updated.displayTitle, "新标题")
    }

    func testReorderVolumesEnforcesFullPermutation() async throws {
        let store = try LocalCatalogStore(directory: tempDirectory)
        let now = Date().timeIntervalSince1970
        let series = LocalSeriesRecord(id: "s1", originalTitle: "书", userTitle: nil, volumeIDs: ["v1", "v2", "v3"],
                                       createdAt: now, updatedAt: now)
        try await store.commitNewSeries(series)

        // Missing item rejected
        do {
            try await store.reorderVolumes(seriesId: "s1", newVolumeIDs: ["v1", "v2"])
            XCTFail("Should throw invalidPermutation")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .invalidPermutation)
        }

        // Duplicate item rejected
        do {
            try await store.reorderVolumes(seriesId: "s1", newVolumeIDs: ["v1", "v2", "v2"])
            XCTFail("Should throw invalidPermutation")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .invalidPermutation)
        }

        // External unknown item rejected
        do {
            try await store.reorderVolumes(seriesId: "s1", newVolumeIDs: ["v1", "v2", "v99"])
            XCTFail("Should throw invalidPermutation")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .invalidPermutation)
        }

        // Valid permutation succeeds
        try await store.reorderVolumes(seriesId: "s1", newVolumeIDs: ["v3", "v1", "v2"])
        let updated = await store.getSeries(id: "s1")
        XCTAssertEqual(updated?.volumeIDs, ["v3", "v1", "v2"])
    }

    func testTombstoneCreationAndQuery() async throws {
        let store = try LocalCatalogStore(directory: tempDirectory)
        let now = Date().timeIntervalSince1970
        let series = LocalSeriesRecord(id: "s1", originalTitle: "作品", userTitle: "用户名", volumeIDs: ["v1"],
                                       createdAt: now, updatedAt: now)
        try await store.commitNewSeries(series)

        let fp = String(repeating: "a", count: 64)
        let tombstone = LocalDeletedFingerprintRecord(fingerprint: fp, seriesId: "s1", volumeId: "v1", userTitle: "用户名", deletedAt: now)
        try await store.completeSeriesDeletion(seriesId: "s1", newTombstones: [tombstone])

        let activeSeries = await store.getSeries(id: "s1")
        XCTAssertNil(activeSeries)

        let queriedTombstone = await store.findTombstone(byFingerprint: fp)
        XCTAssertNotNil(queriedTombstone)
        XCTAssertEqual(queriedTombstone?.seriesId, "s1")
        XCTAssertEqual(queriedTombstone?.volumeId, "v1")
        XCTAssertEqual(queriedTombstone?.userTitle, "用户名")

        // Clearing tombstone
        try await store.removeTombstone(seriesId: "s1")
        let afterClear = await store.findTombstone(byFingerprint: fp)
        XCTAssertNil(afterClear)
    }
}
