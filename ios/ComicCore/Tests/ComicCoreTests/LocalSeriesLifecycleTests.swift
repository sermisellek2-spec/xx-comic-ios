import XCTest
@testable import ComicCore

final class LocalSeriesLifecycleTests: XCTestCase {
    private var tempDirectory: URL!
    private var outsideDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalSeriesLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        outsideDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalSeriesOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
        if let outsideDirectory { try? FileManager.default.removeItem(at: outsideDirectory) }
        try super.tearDownWithError()
    }

    private func createTestZip(name: String, entries: [String: [UInt8]]) throws -> URL {
        let zipURL = outsideDirectory.appendingPathComponent(name)
        let items = entries.map { ZIPFixture.Item($0.key, $0.value) }
        let data = try ZIPFixture.make(items)
        try data.write(to: zipURL)
        return zipURL
    }

    func testLegacySingleVolumeBooksDiscoveredAsImplicitSeries() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip1 = try createTestZip(name: "book1.zip", entries: ["0.png": [1, 2], "1.png": [3, 4]])
        let legacyBook = try library.importArchive(title: "旧单卷", archive: zip1, isReadableImage: { _ in true })

        // catalog.json does not exist yet
        let exists = await library.catalogStore.existsOnDisk()
        XCTAssertFalse(exists)

        let seriesList = try await library.series()
        XCTAssertEqual(seriesList.count, 1)
        let s = try XCTUnwrap(seriesList.first)
        XCTAssertEqual(s.id, legacyBook.id)
        XCTAssertEqual(s.originalTitle, "旧单卷")
        XCTAssertEqual(s.volumeIDs, [legacyBook.id])

        let summary = try library.summary(for: s)
        XCTAssertEqual(summary.comicId, legacyBook.id)
        XCTAssertEqual(summary.title, "旧单卷")
        XCTAssertEqual(summary.subtitle, "2 页")
    }

    func testConcurrentImportWithSameFingerprintReturnsExistingSeries() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip = try createTestZip(name: "comic.zip", entries: ["page.png": [10, 20, 30]])

        let prep1 = try library.prepareArchive(title: "首次导入", archive: zip, isReadableImage: { _ in true })
        let prep2 = try library.prepareArchive(title: "再次导入", archive: zip, isReadableImage: { _ in true })

        XCTAssertNotNil(prep1.book.fingerprint)
        XCTAssertEqual(prep1.book.fingerprint, prep2.book.fingerprint)

        let (series1, book1) = try await library.publishImport(prep1)
        XCTAssertEqual(series1.volumeIDs, [book1.id])

        // Second import of identical content returns existing series
        let (series2, book2) = try await library.publishImport(prep2)
        XCTAssertEqual(series2.id, series1.id)
        XCTAssertEqual(book2.id, book1.id)

        // Only one physical volume exists on disk
        let diskBooks = try library.books()
        XCTAssertEqual(diskBooks.count, 1)
        XCTAssertEqual(diskBooks.first?.id, book1.id)
    }

    func testExplicitAppendWithSameFingerprintToDifferentSeriesThrowsAlreadyImported() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zipA = try createTestZip(name: "bookA.zip", entries: ["0.png": [1, 1, 1]])
        let zipB = try createTestZip(name: "bookB.zip", entries: ["0.png": [2, 2, 2]])

        let prepA = try library.prepareArchive(title: "作品A", archive: zipA, isReadableImage: { _ in true })
        let (seriesA, _) = try await library.publishImport(prepA)

        let prepB = try library.prepareArchive(title: "作品B", archive: zipB, isReadableImage: { _ in true })
        let (seriesB, _) = try await library.publishImport(prepB)

        // Now prepare zipA again and attempt to append to seriesB
        let prepA2 = try library.prepareArchive(title: "作品A再来", archive: zipA, isReadableImage: { _ in true })
        do {
            _ = try await library.publishImport(prepA2, targetSeriesId: seriesB.id)
            XCTFail("Should throw alreadyImported")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .alreadyImported)
        }

        // Series A retains its volume, series B is not polluted
        let refreshedA = try await library.series(id: seriesA.id)
        XCTAssertEqual(refreshedA?.volumeIDs.count, 1)
        let refreshedB = try await library.series(id: seriesB.id)
        XCTAssertEqual(refreshedB?.volumeIDs.count, 1)
    }

    func testAppendToNonExistentOrDeletingSeriesFailsAndDiscardsStaging() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip = try createTestZip(name: "vol.zip", entries: ["p.png": [5, 6, 7]])
        let prep = try library.prepareArchive(title: "追加", archive: zip, isReadableImage: { _ in true })

        do {
            _ = try await library.publishImport(prep, targetSeriesId: "NON_EXISTENT_SERIES_ID")
            XCTFail("Should throw targetNotFound")
        } catch let error as LocalCatalogError {
            XCTAssertEqual(error, .targetNotFound)
        }

        // Verify staging directory was cleaned
        let entries = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(entries.filter { $0.hasPrefix(".import-") }, [])
    }

    func testAppendVolumeIncreasesVolumeCountAndPreservesStableChapterIDs() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip1 = try createTestZip(name: "vol1.zip", entries: ["0.png": [1], "1.png": [2]])
        let zip2 = try createTestZip(name: "vol2.zip", entries: ["0.png": [3], "1.png": [4], "2.png": [5]])

        let prep1 = try library.prepareArchive(title: "合集第1卷", archive: zip1, isReadableImage: { _ in true })
        let (series, vol1) = try await library.publishImport(prep1, explicitTitle: "多卷漫画")

        let prep2 = try library.prepareArchive(title: "合集第2卷", archive: zip2, isReadableImage: { _ in true })
        let (updatedSeries, vol2) = try await library.publishImport(prep2, targetSeriesId: series.id)

        XCTAssertEqual(updatedSeries.volumeIDs, [vol1.id, vol2.id])
        XCTAssertEqual(updatedSeries.originalTitle, "多卷漫画")

        let summary = try library.summary(for: updatedSeries)
        XCTAssertEqual(summary.subtitle, "2 卷 · 5 页")

        // Reordering volumes
        try await library.reorderVolumes(seriesId: series.id, newVolumeIDs: [vol2.id, vol1.id])
        let reorderedOpt = try await library.series(id: series.id)
        let reordered = try XCTUnwrap(reorderedOpt)
        XCTAssertEqual(reordered.volumeIDs, [vol2.id, vol1.id])

        // Verify books and chapters retain stable IDs
        let book1Reloaded = try library.book(id: vol1.id)
        let book2Reloaded = try library.book(id: vol2.id)
        XCTAssertEqual(book1Reloaded.id, vol1.id)
        XCTAssertEqual(book2Reloaded.id, vol2.id)
        XCTAssertEqual(book1Reloaded.chapters?.first?.id, "\(vol1.id)_ch_0")
        XCTAssertEqual(book2Reloaded.chapters?.first?.id, "\(vol2.id)_ch_0")
    }

    func testSeriesDeletionRemovesPhysicalFilesAndCreatesTombstone() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip = try createTestZip(name: "to_delete.zip", entries: ["0.png": [9, 8, 7]])

        let prep = try library.prepareArchive(title: "将被删除的漫画", archive: zip, isReadableImage: { _ in true })
        let fp = try XCTUnwrap(prep.book.fingerprint)
        let (series, book) = try await library.publishImport(prep)

        // Rename series
        _ = try await library.renameSeries(id: series.id, newTitle: "用户自定义标题")

        // Delete series
        try await library.deleteSeries(id: series.id)

        // Physical volume directory removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(book.id).path))

        // Outside user file kept intact!
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))

        // Catalog records tombstone
        let tombstone = await library.catalogStore.findTombstone(byFingerprint: fp)
        XCTAssertNotNil(tombstone)
        XCTAssertEqual(tombstone?.seriesId, series.id)
        XCTAssertEqual(tombstone?.volumeId, book.id)
        XCTAssertEqual(tombstone?.userTitle, "用户自定义标题")
    }

    func testReimportingSameFingerprintRestoresSeriesIDVolumeIDAndUserTitle() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip = try createTestZip(name: "reimport.zip", entries: ["0.png": [11, 22, 33, 44]])

        let prep1 = try library.prepareArchive(title: "初次标题", archive: zip, isReadableImage: { _ in true })
        let fp = try XCTUnwrap(prep1.book.fingerprint)
        let (series1, book1) = try await library.publishImport(prep1)
        _ = try await library.renameSeries(id: series1.id, newTitle: "记忆中的标题")

        // Delete series
        try await library.deleteSeries(id: series1.id)
        let deletedSeries = try await library.series(id: series1.id)
        XCTAssertNil(deletedSeries)

        // Re-import the exact same content
        let prep2 = try library.prepareArchive(title: "初次标题", archive: zip, isReadableImage: { _ in true })
        let (restoredSeries, restoredBook) = try await library.publishImport(prep2)

        // Identity and user custom title restored!
        XCTAssertEqual(restoredSeries.id, series1.id)
        XCTAssertEqual(restoredBook.id, book1.id)
        XCTAssertEqual(restoredSeries.userTitle, "记忆中的标题")
        XCTAssertEqual(restoredSeries.displayTitle, "记忆中的标题")

        // Chapters have exact same ID as before
        XCTAssertEqual(restoredBook.chapters?.first?.id, "\(book1.id)_ch_0")

        // Tombstone has been cleared
        let tombstoneAfter = await library.catalogStore.findTombstone(byFingerprint: fp)
        XCTAssertNil(tombstoneAfter)
    }

    func testSingleVolumeDeletionInMultiVolumeSeriesDeletesOnlyTargetVolume() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip1 = try createTestZip(name: "part1.zip", entries: ["0.png": [100]])
        let zip2 = try createTestZip(name: "part2.zip", entries: ["0.png": [200]])

        let prep1 = try library.prepareArchive(title: "两卷书", archive: zip1, isReadableImage: { _ in true })
        let (series, vol1) = try await library.publishImport(prep1)

        let prep2 = try library.prepareArchive(title: "第二卷", archive: zip2, isReadableImage: { _ in true })
        let (_, vol2) = try await library.publishImport(prep2, targetSeriesId: series.id)

        // Delete first volume vol1
        try await library.deleteVolume(seriesId: series.id, volumeId: vol1.id)

        // Physical vol1 removed, physical vol2 remains
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(vol1.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(vol2.id).path))

        // Series ID is preserved!
        let updatedSeriesOpt = try await library.series(id: series.id)
        let updatedSeries = try XCTUnwrap(updatedSeriesOpt)
        XCTAssertEqual(updatedSeries.id, series.id)
        XCTAssertEqual(updatedSeries.volumeIDs, [vol2.id])

        // Delete remaining volume vol2 -> deletes whole series
        try await library.deleteVolume(seriesId: series.id, volumeId: vol2.id)
        let afterDeleteOpt = try await library.series(id: series.id)
        XCTAssertNil(afterDeleteOpt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(vol2.id).path))
    }

    func testStartupOrphanRecoveryCleansAbandonedStagingAndUncommittedVolumes() async throws {
        let library = try LocalLibrary(directory: tempDirectory)

        // 1. Create a legitimate series in catalog
        let zip = try createTestZip(name: "legit.zip", entries: ["0.png": [55, 66]])
        let prep = try library.prepareArchive(title: "正经书", archive: zip, isReadableImage: { _ in true })
        let (_, legitBook) = try await library.publishImport(prep)

        // Crash simulation uses the production preparation/publication writers.
        // The previous fixture's arbitrary trash/lost files had no app ownership.
        var abandoned: PreparedLocalImport? = try library.prepareArchive(title: "中断准备", archive: zip, isReadableImage: { _ in true })
        let abandonedStaging = try XCTUnwrap(abandoned?.staging)
        abandoned = nil // Release the live transaction lock, as a process exit would.
        var uncommitted: PreparedLocalImport? = try library.prepareArchive(title: "未提交", archive: zip, isReadableImage: { _ in true })
        let pending = try library.publishPrepared(XCTUnwrap(uncommitted), pendingCatalog: true)
        let uncommittedVolume = tempDirectory.appendingPathComponent(pending.id)
        uncommitted = nil

        // Recover orphans
        let restarted = try LocalLibrary(directory: tempDirectory)
        try await restarted.recoverOrphans()

        // Abandoned staging and uncommitted volume cleaned
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandonedStaging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: uncommittedVolume.path))

        // Legit book untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(legitBook.id).path))
        XCTAssertEqual(try restarted.book(id: legitBook.id), legitBook)
        try await restarted.recoverOrphans() // Recovery is repeatable.
    }
}
