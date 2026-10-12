import Foundation
import XCTest
import ZIPFoundation
@testable import ComicCore
#if canImport(ImageIO)
import ImageIO
#endif

// Format and recovery tests explicitly exercise legacy conversion. New imports use
// the default comic-only policy, verified below with real Kindle records.
final class KindlePublicationTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=")!
    // A real 1x1 JPEG, exported with Windows System.Drawing (not a magic-only placeholder).
    private let jpeg = Data(base64Encoded: "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD50ooor8MP9Uz/2Q==")!

    private func word(_ value: UInt32) -> Data {
        Data([UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }
    private func put(_ bytes: inout Data, _ offset: Int, _ value: UInt32) {
        bytes.replaceSubrange(offset..<offset + 4, with: word(value))
    }
    private func fixture(text: [Data], images: [Data] = [], compression: UInt8 = 1, declared: UInt32? = nil,
                         encoding: UInt32 = 65001, cover: UInt32? = nil, boundary: UInt32? = nil,
                         palm: Bool = false, version: UInt32 = 6, encryption: UInt8 = 0, count: Int? = nil) -> Data {
        var header = Data(repeating: 0, count: palm ? 16 : 512)
        header[1] = compression; header[13] = encryption
        put(&header, 4, declared ?? UInt32(text.reduce(0) { $0 + $1.count }))
        let textCount = count ?? text.count
        header[8] = UInt8(truncatingIfNeeded: textCount >> 8); header[9] = UInt8(truncatingIfNeeded: textCount)
        if !palm {
            header.replaceSubrange(16..<20, with: Data("MOBI".utf8))
            put(&header, 20, 232); put(&header, 24, 2); put(&header, 28, encoding); put(&header, 36, version)
            put(&header, 84, 448)
            let title = Data("书名 & <测试> \"甲\"".utf8)
            put(&header, 88, UInt32(title.count)); header.replaceSubrange(448..<448 + title.count, with: title)
            put(&header, 108, images.isEmpty ? .max : UInt32(1 + text.count))
            put(&header, 168, .max); put(&header, 172, .max)
            var entries: [(UInt32, Data)] = [(100, Data("作者 & <乙>".utf8))]
            if let cover { entries.append((201, word(cover))) }
            if let boundary { entries.append((121, word(boundary))) }
            var exth = Data("EXTH".utf8) + word(12) + word(UInt32(entries.count))
            for (type, value) in entries { exth += word(type) + word(UInt32(8 + value.count)) + value }
            put(&exth, 4, UInt32(exth.count)); header.replaceSubrange(248..<248 + exth.count, with: exth)
        }
        let records = [header] + text + images
        var pdb = Data(repeating: 0, count: 78 + records.count * 8)
        pdb.replaceSubrange(0..<4, with: Data("Book".utf8)); pdb.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        pdb[76] = UInt8(truncatingIfNeeded: records.count >> 8); pdb[77] = UInt8(truncatingIfNeeded: records.count)
        var offset = pdb.count
        for (index, record) in records.enumerated() { put(&pdb, 78 + index * 8, UInt32(offset)); offset += record.count }
        for record in records { pdb += record }
        return pdb
    }
    private func files(_ data: Data) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mobi"), target = dir.appendingPathComponent("derived.epub")
        try data.write(to: source)
        return (source, target)
    }
    private func html(_ publication: EpubPublication, _ target: URL, index: Int = 0) throws -> String {
        String(decoding: try EpubArchive(url: target).read(publication.spine[index].fullZipPath), as: UTF8.self)
    }
    private func assertClean(_ source: URL, _ target: URL, _ original: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try Data(contentsOf: source), original, file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), file: file, line: line)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path).contains { $0.hasPrefix(".kindle-") }, file: file, line: line)
    }

    func testDefaultConversionRejectsNovelAndMixedContentWithoutChangingOriginal() throws {
        for body in ["<p>小说正文</p>", "<p>图文正文</p><img recindex=1/>"] {
            let original = fixture(text: [Data(body.utf8)], images: [png])
            let (source, target) = try files(original)
            XCTAssertThrowsError(try KindlePublicationAdapter.convert(source: source, to: target)) {
                XCTAssertEqual($0 as? LocalLibraryError, .unsupportedTextContent)
            }
            try assertClean(source, target, original)
        }
    }
    func testDefaultConversionAcceptsImageComicAndPreservesActualImageBytes() throws {
        let original = fixture(text: [Data("<img recindex=1/>".utf8)], images: [png, jpeg, png])
        let (source, target) = try files(original)
        let publication = try KindlePublicationAdapter.convert(source: source, to: target)
        XCTAssertTrue(publication.isPurePictureEpub)
        XCTAssertEqual(publication.spine.count, 3)
        XCTAssertEqual(try EpubArchive(url: target).read("OEBPS/images/img_1.png"), png)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
    func testTwoChapterNovelMetadataAndActualStoredMimetype() throws {
        let original = fixture(text: [Data("<h1>第一章</h1><p>第一章正文</p><mbp:pagebreak/><h2>第二章</h2><p>第二章正文</p>".utf8)])
        let (source, target) = try files(original)
        let publication = try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)
        XCTAssertEqual(publication, try EpubParser.parse(archive: target))
        XCTAssertEqual(publication.spine.count, 2)
        XCTAssertEqual(try publication.chapterRanges().map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(publication.title, "书名 & <测试> \"甲\"")
        XCTAssertEqual(publication.author, "作者 & <乙>")
        XCTAssertTrue(try html(publication, target).contains("第一章正文"))
        XCTAssertTrue(try html(publication, target, index: 1).contains("第二章正文"))
        let zip = try Archive(url: target, accessMode: .read)
        XCTAssertEqual(Array(zip).first?.path, "mimetype"); XCTAssertFalse(try XCTUnwrap(zip["mimetype"]).isCompressed)
        XCTAssertEqual(try EpubArchive(url: target).read("mimetype"), Data("application/epub+zip".utf8))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
    func testComicLayoutWhitespaceImageBytesIndexHolesAndExplicitCover() throws {
        let whitespace = String(repeating: " \t\n\r\u{000B}\u{000C}\u{00A0}\u{3000}&nbsp;&#0160;&#x00A0;", count: 100)
        let (source, target) = try files(fixture(text: [Data(("<img recindex=1/>" + whitespace).utf8)], images: [jpeg, Data("BOUNDARY".utf8), png, jpeg], cover: 2))
        let publication = try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)
        XCTAssertTrue(publication.isPurePictureEpub); XCTAssertEqual(publication.spine.count, 3)
        XCTAssertEqual(try publication.chapterRanges().count, 1)
        XCTAssertEqual(publication.navItems.map(\.title), ["Page 1", "Page 2", "Page 3"])
        XCTAssertEqual(publication.coverEntry, "OEBPS/images/img_3.png")
        let zip = try Archive(url: target, accessMode: .read), archive = try EpubArchive(url: target)
        for (index, bytes, ext) in [(1, jpeg, "jpg"), (3, png, "png"), (4, jpeg, "jpg")] {
            let path = "OEBPS/images/img_\(index).\(ext)"
            XCTAssertEqual(try archive.read(path), bytes); XCTAssertFalse(try XCTUnwrap(zip[path]).isCompressed)
        }
        XCTAssertFalse(archive.contains("OEBPS/images/img_2.jpg"))
        XCTAssertEqual(publication.spine.map(\.resolvedImageEntry), ["OEBPS/images/img_1.jpg", "OEBPS/images/img_3.png", "OEBPS/images/img_4.jpg"])
    }
    func testMixedTextMapsRecindexDropsMissingImageAndFallsBackCover() throws {
        let body = "<h2>A & B</h2><p>正文</p><img recindex='1'/><image recindex=3/><img recindex=2/><h2>不另分章</h2>"
        let (source, target) = try files(fixture(text: [Data(body.utf8)], images: [png, Data("EOF!".utf8), jpeg], cover: 1))
        let publication = try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)
        XCTAssertEqual(publication.spine.count, 1); XCTAssertEqual(publication.navItems.first?.title, "A & B")
        let chapter = try html(publication, target)
        XCTAssertTrue(chapter.contains("正文")); XCTAssertTrue(chapter.contains("不另分章"))
        XCTAssertTrue(chapter.contains("../images/img_1.png")); XCTAssertTrue(chapter.contains("../images/img_3.jpg"))
        XCTAssertFalse(chapter.contains("recindex")); XCTAssertFalse(chapter.contains("img_2"))
        XCTAssertEqual(publication.coverEntry, "OEBPS/images/img_1.png")
        XCTAssertEqual(publication.manifest.first { $0.properties == "cover-image" }?.href, publication.coverEntry)
    }
    func testWindows1252PalmDocAndMobiText() throws {
        for palm in [false, true] {
            let (source, target) = try files(fixture(text: [Data([0x93, 67, 97, 102, 0xE9, 0x94, 32, 0x80])], encoding: 1252, palm: palm))
            XCTAssertTrue(try html(KindlePublicationAdapter.convert(source: source, to: target, requireComic: false), target).contains("“Café” €"))
        }
    }
    func testCompressionBackreferenceSpansRecordsAndDeclaredLengthDropsPadding() throws {
        for (records, length, expected): ([Data], UInt32, String) in [
            ([Data("Hello World!".utf8) + Data([0x80]), Data([0x63])], 18, "Hello World!Hello "),
            ([Data([65, 66, 67, 0x80])], 3, "ABC")
        ] {
            let (source, target) = try files(fixture(text: records, compression: 2, declared: length))
            XCTAssertTrue(try html(KindlePublicationAdapter.convert(source: source, to: target, requireComic: false), target).contains(expected))
        }
        let (source, target) = try files(fixture(text: [Data("ABCpadding".utf8)], declared: 3))
        let result = try html(KindlePublicationAdapter.convert(source: source, to: target, requireComic: false), target)
        XCTAssertTrue(result.contains("ABC")); XCTAssertFalse(result.contains("padding"))
    }
    func testComboStopsBeforeBoundary() throws {
        let (source, target) = try files(fixture(text: [Data("Old text".utf8), Data("BOUNDARY".utf8), Data("New KF8".utf8)], boundary: 2, version: 8))
        let result = try html(KindlePublicationAdapter.convert(source: source, to: target, requireComic: false), target)
        XCTAssertTrue(result.contains("Old text")); XCTAssertFalse(result.contains("BOUNDARY")); XCTAssertFalse(result.contains("New KF8"))
    }
    func testTextPreservesSupplementaryUnicodeAcrossCopyChunks() throws {
        let body = String(repeating: "a", count: 32767) + "😀结尾"
        let (source, target) = try files(fixture(text: [Data(("<img recindex=1/>" + body).utf8)], images: [png]))
        let chapter = try html(KindlePublicationAdapter.convert(source: source, to: target, requireComic: false), target)
        XCTAssertTrue(chapter.contains(body)); XCTAssertFalse(chapter.contains("�"))
    }
    func testHeadingMustBeSameLineAndLessThanFiftyUTF16Units() throws {
        let body = "<h1>line\nbreak</h1><pagebreak/><h2>\(String(repeating: "😀", count: 25))</h2><pagebreak/><h3><b>名称</b></h3>"
        let (source, target) = try files(fixture(text: [Data(body.utf8)]))
        let publication = try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)
        XCTAssertEqual(publication.navItems.map(\.title), ["第 1 章", "第 2 章", "名称"])
    }
    func testEmptyUnsupportedInvalidEncodingAndTruncatedTextFailCleanly() throws {
        for bytes in [fixture(text: []), fixture(text: [Data("<p> &nbsp; </p>".utf8)]),
                      fixture(text: [Data([0xFF])]), fixture(text: [Data([0x80])], compression: 2),
                      fixture(text: [Data("x".utf8)], encryption: 2), fixture(text: [Data("x".utf8)], version: 8),
                      fixture(text: [Data("x".utf8)], count: 3)] {
            let (source, target) = try files(bytes)
            XCTAssertThrowsError(try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false))
            try assertClean(source, target, bytes)
        }
    }
    func testExistingTargetAndSourceAreNeverOverwritten() throws {
        let original = fixture(text: [Data("正文".utf8)])
        let (source, target) = try files(original), existing = Data("keep me".utf8)
        try existing.write(to: target)
        XCTAssertThrowsError(try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false))
        XCTAssertThrowsError(try KindlePublicationAdapter.convert(source: source, to: source, requireComic: false))
        XCTAssertEqual(try Data(contentsOf: target), existing); XCTAssertEqual(try Data(contentsOf: source), original)
    }
    func testReconversionProducesEqualPublication() throws {
        let (source, first) = try files(fixture(text: [Data("<h2>章节</h2>文字<img recindex=1/>".utf8)], images: [jpeg]))
        let second = first.deletingLastPathComponent().appendingPathComponent("second.epub")
        XCTAssertEqual(try KindlePublicationAdapter.convert(source: source, to: first, requireComic: false),
                       try KindlePublicationAdapter.convert(source: source, to: second, requireComic: false))
    }
    func testComicThresholdCountsUTF16RatherThanGraphemes() throws {
        let (source, target) = try files(fixture(text: [Data(String(repeating: "😀", count: 150).utf8)], images: [png, jpeg, png]))
        let publication = try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)
        XCTAssertEqual(publication.spine.count, 1); XCTAssertFalse(publication.isPurePictureEpub)
    }
    func testZeroAndSignedSentinelDeclaredLengthsUseAvailableText() throws {
        for declared: UInt32 in [0, UInt32(Int32.max), .max] {
            let (source, target) = try files(fixture(text: [Data("ABC".utf8)], declared: declared))
            XCTAssertTrue(try html(KindlePublicationAdapter.convert(source: source, to: target, requireComic: false), target).contains("ABC"))
        }
    }
    func testMaximumBodyPlusWrapperCannotExceedReaderCapacity() throws {
        let block = Data(repeating: 65, count: 4 * 1024 * 1024)
        let bytes = fixture(text: [block, block, Data("TRAILER".utf8)], declared: 0)
        let (source, target) = try files(bytes)
        XCTAssertThrowsError(try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)) {
            XCTAssertTrue($0.localizedDescription.contains("正文资源超过 8 MiB"))
        }
        try assertClean(source, target, bytes)
    }
    func testTotalBodyIsCappedAtEightMiBAcrossRecordsAndTwoChapters() throws {
        let first = Data(repeating: 65, count: 4 * 1024 * 1024)
        let marker = Data("<pagebreak/>".utf8)
        let second = marker + Data(repeating: 66, count: 4 * 1024 * 1024 - marker.count)
        let (source, target) = try files(fixture(text: [first, second, Data("TRAILER".utf8)], declared: 0))
        let publication = try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)
        XCTAssertEqual(publication.spine.count, 2)
        let archive = try EpubArchive(url: target)
        let one = try archive.read(publication.spine[0].fullZipPath), two = try archive.read(publication.spine[1].fullZipPath)
        XCTAssertEqual(one.filter { $0 == 65 }.count, 4 * 1024 * 1024)
        XCTAssertEqual(two.filter { $0 == 66 }.count, 4 * 1024 * 1024 - marker.count)
        XCTAssertFalse(String(decoding: two, as: UTF8.self).contains("TRAILER"))
    }
    func testAllSupportedImageSignaturesBecomeLocalManifestResources() throws {
        // Only classification is under test here; JPEG/PNG are real decode fixtures above.
        let images = [Data("GIF89a".utf8), Data("RIFFxxxxWEBP".utf8), Data("BMxx".utf8)]
        let (source, target) = try files(fixture(text: [], images: images))
        let publication = try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)
        XCTAssertEqual(publication.spine.count, 3)
        XCTAssertEqual(publication.manifest.filter { $0.mediaType.hasPrefix("image/") }.map(\.mediaType), ["image/gif", "image/webp", "image/bmp"])
    }
    func testImageBudgetIncludesUnrecognizedControlRecords() throws {
        let recordSize = 16 * 1024 * 1024, recordCount = 33
        var bytes = fixture(text: [Data("x".utf8)], images: Array(repeating: Data([0]), count: recordCount))
        let firstImageOffset = 78 + (2 + recordCount) * 8 + 512 + 1
        for index in 0..<recordCount { put(&bytes, 78 + (index + 2) * 8, UInt32(firstImageOffset + index * recordSize)) }
        let (source, target) = try files(bytes), handle = try FileHandle(forWritingTo: source)
        let size = UInt64(firstImageOffset + recordCount * recordSize)
        try handle.truncate(atOffset: size); try handle.close()
        XCTAssertThrowsError(try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)) {
            XCTAssertTrue($0.localizedDescription.contains("512 MiB"))
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        XCTAssertEqual(try input.seekToEnd(), size)
        try input.seek(toOffset: 0)
        XCTAssertEqual(try input.read(upToCount: bytes.count), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path), ["source.mobi"])
    }
    func testTextAndImageRecordBudgetsFailCleanly() throws {
        let hugeText = Data(repeating: 65, count: 8 * 1024 * 1024 + 1)
        let hugeImage = Data(repeating: 0, count: 16 * 1024 * 1024 + 1)
        for bytes in [fixture(text: [hugeText], declared: 1), fixture(text: [Data("x".utf8)], images: [hugeImage]),
                      fixture(text: [Data(hugeText.prefix(8 * 1024 * 1024)), Data(hugeText.prefix(8 * 1024 * 1024)), Data([65])], compression: 2, declared: 1)] {
            let (source, target) = try files(bytes)
            XCTAssertThrowsError(try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false))
            try assertClean(source, target, bytes)
        }
    }
    func testManifestBudgetRejectsTooManyChapters() throws {
        let bytes = fixture(text: [Data(String(repeating: "x<pagebreak/>", count: 50_000).utf8)])
        let (source, target) = try files(bytes)
        XCTAssertThrowsError(try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)) {
            XCTAssertTrue($0.localizedDescription.contains("manifest"))
        }
        try assertClean(source, target, bytes)
    }
    func testMaliciousHTMLHasBoundedRuntimeAndCleanup() throws {
        let bytes = fixture(text: [Data(String(repeating: "<", count: 300_000).utf8)])
        let (source, target) = try files(bytes), start = ContinuousClock.now
        XCTAssertThrowsError(try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)) {
            XCTAssertTrue($0.localizedDescription.contains("2 秒"))
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(6))
        try assertClean(source, target, bytes)
    }
    func testCancellationDuringHTMLScanningCleansScratch() async throws {
        let bytes = fixture(text: [Data(String(repeating: "<", count: 300_000).utf8)])
        let (source, target) = try files(bytes)
        let worker = Task.detached { try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false) }
        // Wait for the real conversion scratch directory, then cancel its in-flight regex.
        for _ in 0..<100 {
            if try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path).contains(where: { $0.hasPrefix(".kindle-") }) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        worker.cancel()
        do { _ = try await worker.value; XCTFail("应取消转换") } catch { XCTAssertTrue(error is CancellationError) }
        try assertClean(source, target, bytes)
    }
    func testPreCancelledConversionPreservesSource() async throws {
        let bytes = fixture(text: [Data("正文".utf8)]), (source, target) = try files(bytes)
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false)
        }
        do { _ = try await worker.value; XCTFail("应取消转换") } catch { XCTAssertTrue(error is CancellationError) }
        try assertClean(source, target, bytes)
    }
    func testCancellationWhileStagingLargeImagesCleansOnlyOwnedScratch() async throws {
        let large = png + Data(repeating: 0, count: 16 * 1024 * 1024 - png.count)
        let bytes = fixture(text: [], images: Array(repeating: large, count: 8))
        let (source, target) = try files(bytes), parent = source.deletingLastPathComponent()
        let unrelated = parent.appendingPathComponent(".kindle-unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let worker = Task.detached { try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false) }
        var sawImage = false
        for _ in 0..<400 {
            let scratch = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".kindle-") && $0 != unrelated }
            if scratch.contains(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("img_2.png").path) }) { sawImage = true; break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        worker.cancel()
        do { _ = try await worker.value; XCTFail("应取消图片暂存") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(sawImage)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: parent.path)), ["source.mobi", ".kindle-unrelated"])
    }
    func testDestinationCreatedDuringConversionIsPreserved() async throws {
        let large = jpeg + Data(repeating: 0, count: 16 * 1024 * 1024 - jpeg.count)
        let bytes = fixture(text: [], images: [large, large, large])
        let (source, target) = try files(bytes), parent = source.deletingLastPathComponent()
        let worker = Task.detached { try KindlePublicationAdapter.convert(source: source, to: target, requireComic: false) }
        var entered = false
        for _ in 0..<400 {
            if try FileManager.default.contentsOfDirectory(atPath: parent.path).contains(where: { $0.hasPrefix(".kindle-") }) { entered = true; break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(entered)
        let existing = Data("created by someone else".utf8)
        try existing.write(to: target, options: .withoutOverwriting)
        do { _ = try await worker.value; XCTFail("不得替换转换期间创建的目标") } catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: target), existing)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: parent.path)), ["source.mobi", "derived.epub"])
    }
    #if canImport(ImageIO)
    func testFixtureImagesActuallyDecodeWithImageIO() throws {
        for bytes in [png, jpeg] {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 1); XCTAssertEqual(image.height, 1)
        }
    }
    #endif
}
