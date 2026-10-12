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

    func testTextVolumeCannotBeAppendedAndExistingComicTargetsStayStable() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let zip = try createTestZip(name: "comic.zip", entries: ["0.png": [11, 22]])
        let prep = try library.prepareArchive(title: "漫画部分", archive: zip, isReadableImage: { _ in true })
        let (series, volume) = try await library.publishImport(prep)
        let before = try await library.chapters(for: series.id), input = try createTestEpub(name: "novel.epub"), original = try Data(contentsOf: input)
        XCTAssertThrowsError(try library.prepareEpub(title: "文字部分", archive: input, isReadableImage: { _ in true })) {
            XCTAssertEqual($0 as? LocalLibraryError, .unsupportedTextContent)
        }
        let after = try await library.chapters(for: series.id)
        XCTAssertEqual(after, before)
        let target = try await library.readingTarget(seriesId: series.id, chapterIndex: 0)
        XCTAssertEqual(target.volumeId, volume.id); XCTAssertEqual(target.kind, .comic)
        XCTAssertEqual(try Data(contentsOf: input), original)
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

    func testLegacyTextReadingTargetRejectsAndKeepsMetadataAndOriginal() async throws {
        let library = try LocalLibrary(directory: tempDirectory), input = try createTestEpub(name: "old-novel.epub")
        let book = try LegacyEpubFixture.persist(library: library, archive: input, title: "旧文字卷")
        let folder = library.directory.appendingPathComponent(book.id), metadata = try Data(contentsOf: folder.appendingPathComponent("book.json")), original = try Data(contentsOf: input)
        let chapters = try await library.chapters(for: book.id)
        do { _ = try await library.readingTarget(seriesId: book.id, chapterId: chapters[1].chapterId); XCTFail("旧记录不能打开文字阅读器") }
        catch { XCTAssertEqual(error as? LocalLibraryError, .unsupportedTextContent) }
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("book.json")), metadata)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("content.epub")), original)
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
