import Foundation
import XCTest
import ZIPFoundation
@testable import ComicCore

final class LocalReadingRoutingTests: XCTestCase {
    private var tempDirectory: URL!
    private var outsideDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalReadingRoutingTests-\(UUID().uuidString)", isDirectory: true)
        outsideDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalReadingOutside-\(UUID().uuidString)", isDirectory: true)
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

    private func createTestEpub(name: String) throws -> URL {
        let url = outsideDirectory.appendingPathComponent(name)
        let files = [
            "META-INF/container.xml": "<container><rootfile full-path='OPS/book.opf'/></container>",
            "OPS/book.opf": "<package><metadata/><manifest><item id='a' href='a.xhtml' media-type='application/xhtml+xml'/><item id='b' href='b.xhtml' media-type='application/xhtml+xml'/><item id='nav' href='nav.xhtml' media-type='application/xhtml+xml' properties='nav'/></manifest><spine><itemref idref='a'/><itemref idref='b'/></spine></package>",
            "OPS/nav.xhtml": "<html><nav><ol><li><a href='a.xhtml'>第1节</a></li><li><a href='b.xhtml'>第2节</a></li></ol></nav></html>",
            "OPS/a.xhtml": "<html><body><p id='a'>正文A</p></body></html>",
            "OPS/b.xhtml": "<html><body><p id='b'>正文B</p></body></html>"
        ]
        let archive = try Archive(url: url, accessMode: .create)
        for (path, value) in files {
            let data = Data(value.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), provider: {
                position, count in data.subdata(in: Int(position)..<min(Int(position) + count, data.count))
            })
        }
        return url
    }

    func testSingleVolumeSeriesChaptersEnumeration() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip = try createTestZip(name: "single.zip", entries: ["ch1/0.png": [1, 2], "ch2/0.png": [3, 4]])
        let prep = try library.prepareArchive(title: "单卷书", archive: zip, isReadableImage: { _ in true })
        let (series, vol) = try await library.publishImport(prep)

        let chapters = try await library.chapters(for: series.id)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].chapterSlot, 0)
        XCTAssertEqual(chapters[1].chapterSlot, 1)
        XCTAssertEqual(chapters[0].url, "\(vol.id)/\(vol.chapters![0].id)")
        XCTAssertEqual(chapters[1].url, "\(vol.id)/\(vol.chapters![1].id)")
    }

    func testMultiVolumeSeriesChaptersConcatenationPreservesVolumeOrder() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip1 = try createTestZip(name: "v1.zip", entries: ["ch1/0.png": [10], "ch2/0.png": [20]])
        let zip2 = try createTestZip(name: "v2.zip", entries: ["ch3/0.png": [30], "ch4/0.png": [40], "ch5/0.png": [50]])

        let prep1 = try library.prepareArchive(title: "第一卷", archive: zip1, isReadableImage: { _ in true })
        let (series, vol1) = try await library.publishImport(prep1)

        let prep2 = try library.prepareArchive(title: "第二卷", archive: zip2, isReadableImage: { _ in true })
        let (_, vol2) = try await library.publishImport(prep2, targetSeriesId: series.id)

        let chapters = try await library.chapters(for: series.id)
        XCTAssertEqual(chapters.count, 5)

        // Volume 1 chapters
        XCTAssertEqual(chapters[0].chapterSlot, 0)
        XCTAssertEqual(chapters[0].sectionSlot, 0)
        XCTAssertEqual(chapters[0].url, "\(vol1.id)/\(vol1.chapters![0].id)")

        XCTAssertEqual(chapters[1].chapterSlot, 1)
        XCTAssertEqual(chapters[1].sectionSlot, 0)
        XCTAssertEqual(chapters[1].url, "\(vol1.id)/\(vol1.chapters![1].id)")

        // Volume 2 chapters
        XCTAssertEqual(chapters[2].chapterSlot, 2)
        XCTAssertEqual(chapters[2].sectionSlot, 1)
        XCTAssertEqual(chapters[2].url, "\(vol2.id)/\(vol2.chapters![0].id)")

        XCTAssertEqual(chapters[3].chapterSlot, 3)
        XCTAssertEqual(chapters[3].sectionSlot, 1)
        XCTAssertEqual(chapters[3].url, "\(vol2.id)/\(vol2.chapters![1].id)")

        XCTAssertEqual(chapters[4].chapterSlot, 4)
        XCTAssertEqual(chapters[4].sectionSlot, 1)
        XCTAssertEqual(chapters[4].url, "\(vol2.id)/\(vol2.chapters![2].id)")
    }

    func testReadingTargetResolutionByChapterIdAndIndex() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip1 = try createTestZip(name: "target1.zip", entries: ["ch1/0.png": [1], "ch2/0.png": [2]])
        let zip2 = try createTestZip(name: "target2.zip", entries: ["ch3/0.png": [3]])

        let prep1 = try library.prepareArchive(title: "卷一", archive: zip1, isReadableImage: { _ in true })
        let (series, vol1) = try await library.publishImport(prep1)

        let prep2 = try library.prepareArchive(title: "卷二", archive: zip2, isReadableImage: { _ in true })
        let (_, vol2) = try await library.publishImport(prep2, targetSeriesId: series.id)

        // Query by global index 1 (vol 1, chapter 1)
        let target1 = try await library.readingTarget(seriesId: series.id, chapterIndex: 1)
        XCTAssertEqual(target1.volumeId, vol1.id)
        XCTAssertEqual(target1.volumeChapterIndex, 1)
        XCTAssertEqual(target1.globalChapterIndex, 1)
        XCTAssertEqual(target1.kind, .comic)
        XCTAssertEqual(target1.totalChapters, 3)

        // Query by chapterId in volume 2
        let vol2ChapterId = vol2.chapters![0].id
        let target2 = try await library.readingTarget(seriesId: series.id, chapterId: vol2ChapterId)
        XCTAssertEqual(target2.volumeId, vol2.id)
        XCTAssertEqual(target2.volumeChapterIndex, 0)
        XCTAssertEqual(target2.globalChapterIndex, 2)
        XCTAssertEqual(target2.kind, .comic)
        XCTAssertEqual(target2.totalChapters, 3)
    }

    func testMixedFormatSeriesReaderKindDetection() async throws {
        let library = try LocalLibrary(directory: tempDirectory)

        // Volume 1: Comic ZIP
        let zip = try createTestZip(name: "comic.zip", entries: ["0.png": [11, 22]])
        let prepZip = try library.prepareArchive(title: "漫画部分", archive: zip, isReadableImage: { _ in true })
        let (series, vol1) = try await library.publishImport(prepZip)

        // Volume 2: Text EPUB
        let epubURL = try createTestEpub(name: "novel.epub")
        let prepEpub = try library.prepareEpub(title: "文字部分", archive: epubURL, isReadableImage: { _ in true })
        let (_, vol2) = try await library.publishImport(prepEpub, targetSeriesId: series.id)

        let chapters = try await library.chapters(for: series.id)
        XCTAssertEqual(chapters.count, 3) // 1 comic chapter + 2 epub chapters

        // Target for Volume 1 -> Comic
        let targetComic = try await library.readingTarget(seriesId: series.id, chapterIndex: 0)
        XCTAssertEqual(targetComic.volumeId, vol1.id)
        XCTAssertEqual(targetComic.kind, .comic)

        // Target for Volume 2 chapters -> Text
        let targetText1 = try await library.readingTarget(seriesId: series.id, chapterIndex: 1)
        XCTAssertEqual(targetText1.volumeId, vol2.id)
        XCTAssertEqual(targetText1.kind, .text)

        let targetText2 = try await library.readingTarget(seriesId: series.id, chapterIndex: 2)
        XCTAssertEqual(targetText2.volumeId, vol2.id)
        XCTAssertEqual(targetText2.kind, .text)
    }

    func testVolumeReorderingUpdatesReadingTargetIndicesWithoutChangingChapterIDs() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip1 = try createTestZip(name: "ord1.zip", entries: ["ch1/0.png": [1]])
        let zip2 = try createTestZip(name: "ord2.zip", entries: ["ch2/0.png": [2]])

        let prep1 = try library.prepareArchive(title: "前卷", archive: zip1, isReadableImage: { _ in true })
        let (series, vol1) = try await library.publishImport(prep1)

        let prep2 = try library.prepareArchive(title: "后卷", archive: zip2, isReadableImage: { _ in true })
        let (_, vol2) = try await library.publishImport(prep2, targetSeriesId: series.id)

        let vol1ChapterId = vol1.chapters![0].id
        let vol2ChapterId = vol2.chapters![0].id

        // Before reorder: vol1 at index 0, vol2 at index 1
        let beforeVol2 = try await library.readingTarget(seriesId: series.id, chapterId: vol2ChapterId)
        XCTAssertEqual(beforeVol2.globalChapterIndex, 1)

        // Reorder: [vol2, vol1]
        try await library.reorderVolumes(seriesId: series.id, newVolumeIDs: [vol2.id, vol1.id])

        // After reorder: vol2 is now at index 0, vol1 is now at index 1
        let afterVol2 = try await library.readingTarget(seriesId: series.id, chapterId: vol2ChapterId)
        XCTAssertEqual(afterVol2.globalChapterIndex, 0)
        XCTAssertEqual(afterVol2.volumeId, vol2.id)
        XCTAssertEqual(afterVol2.volumeChapterIndex, 0)

        let afterVol1 = try await library.readingTarget(seriesId: series.id, chapterId: vol1ChapterId)
        XCTAssertEqual(afterVol1.globalChapterIndex, 1)
        XCTAssertEqual(afterVol1.volumeId, vol1.id)
        XCTAssertEqual(afterVol1.volumeChapterIndex, 0)
    }

    func testTextLocatorTranslationBetweenSeriesAndVolumeScope() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let epubURL = try createTestEpub(name: "series_novel.epub")
        let prepEpub = try library.prepareEpub(title: "小说卷", archive: epubURL, isReadableImage: { _ in true })
        let (series, vol) = try await library.publishImport(prepEpub)

        // Volume internal locator created by EpubTextSession
        let session = try EpubTextSession(book: vol, chapterIndex: 1, locator: nil)
        let volLocator = session.locator(anchorID: "b", percent: 0.75, charOffset: 42)
        XCTAssertEqual(volLocator.bookID, vol.id)
        XCTAssertEqual(volLocator.chapterIndex, 1)
        XCTAssertEqual(volLocator.scrollPercentage, 0.75)

        // Convert to series locator for saving in LibraryStore
        let globalIndex = 1
        let seriesLocator = volLocator.toSeriesLocator(seriesId: series.id, globalChapterIndex: globalIndex)
        XCTAssertEqual(seriesLocator.bookID, series.id)
        XCTAssertEqual(seriesLocator.chapterIndex, globalIndex)
        XCTAssertEqual(seriesLocator.anchorID, "b")
        XCTAssertEqual(seriesLocator.scrollPercentage, 0.75)

        // Save in LibraryStore
        let storeDir = outsideDirectory.appendingPathComponent("Store")
        let store = try LibraryStore(directory: storeDir)
        let summary = try library.summary(for: series)
        let chapters = try await library.chapters(for: series.id)

        try store.saveTextReading(summary, chapter: chapters[globalIndex], chapterIndex: globalIndex, locator: seriesLocator)

        // Retrieve and convert back to volume locator
        let loadedSeriesLocator = try XCTUnwrap(store.textPosition(for: summary, chapterID: chapters[globalIndex].chapterId))
        XCTAssertEqual(loadedSeriesLocator.bookID, series.id)
        XCTAssertEqual(loadedSeriesLocator.chapterIndex, globalIndex)

        let restoredVolLocator = loadedSeriesLocator.toVolumeLocator(volumeId: vol.id, volumeChapterIndex: 1)
        XCTAssertEqual(restoredVolLocator.bookID, vol.id)
        XCTAssertEqual(restoredVolLocator.chapterIndex, 1)

        // Restore into EpubTextSession
        let restoredSession = try EpubTextSession(book: vol, chapterIndex: 1, locator: restoredVolLocator)
        XCTAssertEqual(restoredSession.spineIndex, session.spineIndex)
    }

    func testLegacySingleBookFallbackReadingTarget() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip = try createTestZip(name: "legacy_single.zip", entries: ["0.png": [1, 2, 3]])
        let legacyBook = try library.importArchive(title: "旧单行本", archive: zip, isReadableImage: { _ in true })

        // Target queried by legacy book id
        let target = try await library.readingTarget(seriesId: legacyBook.id, chapterIndex: 0)
        XCTAssertEqual(target.volumeId, legacyBook.id)
        XCTAssertEqual(target.volumeChapterIndex, 0)
        XCTAssertEqual(target.globalChapterIndex, 0)
        XCTAssertEqual(target.kind, .comic)
        XCTAssertEqual(target.totalChapters, 1)
    }

    func testInvalidChapterOrSeriesThrowsTargetNotFound() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip = try createTestZip(name: "err.zip", entries: ["0.png": [1]])
        let prep = try library.prepareArchive(title: "测试", archive: zip, isReadableImage: { _ in true })
        let (series, _) = try await library.publishImport(prep)

        // Non-existent series ID
        do {
            _ = try await library.readingTarget(seriesId: "non-existent-id", chapterIndex: 0)
            XCTFail("Should have thrown")
        } catch let err as LocalCatalogError {
            XCTAssertEqual(err, .targetNotFound)
        }

        // Non-existent chapter ID
        do {
            _ = try await library.readingTarget(seriesId: series.id, chapterId: "invalid-ch-id")
            XCTFail("Should have thrown")
        } catch let err as LocalCatalogError {
            XCTAssertEqual(err, .targetNotFound)
        }

        // Out of bounds index
        do {
            _ = try await library.readingTarget(seriesId: series.id, chapterIndex: 999)
            XCTFail("Should have thrown")
        } catch let err as LocalCatalogError {
            XCTAssertEqual(err, .targetNotFound)
        }
    }
}
