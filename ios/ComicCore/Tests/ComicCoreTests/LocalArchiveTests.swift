import XCTest
import ZIPFoundation
@testable import ComicCore

final class LocalArchiveTests: XCTestCase {
    func testStoredAndDeflatedPagesReopenInNaturalChapterOrderBeyondFolderDepthLimit() async throws {
        let entries: [ZIPFixture.Item] = [
            .init("a/b/c/d/e/f/book/第10话/1.jpg", [10], deflate: true),
            .init("a/b/c/d/e/f/book/第2话/10.jpg", [3]),
            .init("a/b/c/d/e/f/book/第2话/2.jpg", [2], deflate: true),
            .init("a/b/c/d/e/f/book/1.jpg", [1]),
            .init("__MACOSX/._bad.jpg", [99]), .init("notes.txt", [99])
        ]
        let (root, archive, library) = try fixture(ZIPFixture.make(entries))
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: archive)
        let book = try library.importArchive(title: "  压缩漫画  ", archive: archive, isReadableImage: { _ in true })
        let reopened = try LocalLibrary(directory: library.directory)
        XCTAssertEqual(try reopened.books(), [book])
        XCTAssertEqual(book.title, "压缩漫画")
        let source = LocalComicSource(library: reopened)
        let chapters = try await source.chapters(comicId: book.id)
        XCTAssertEqual(chapters.map(\.title), ["未分章", "第2话", "第10话"])
        var bytes: [[UInt8]] = []
        for chapter in chapters {
            let page = try await source.chapter(url: chapter.url)
            bytes.append(try page.imageUrls.map { try Data(contentsOf: XCTUnwrap(URL(string: $0))).first! })
        }
        XCTAssertEqual(bytes, [[1], [2, 3], [10]])
        XCTAssertEqual(try Data(contentsOf: archive), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
    }

    func testBadFirstImageIsSkippedAndNextImageBecomesCover() throws {
        let (root, archive, library) = try fixture(ZIPFixture.make([.init("wrapper/1.jpg", [0]), .init("wrapper/2.jpg", [2])]))
        defer { try? FileManager.default.removeItem(at: root) }
        let book = try library.importArchive(title: "", archive: archive, isReadableImage: { try Data(contentsOf: $0) != Data([0]) })
        XCTAssertEqual(book.chapters?.map(\.title), ["正文"])
        XCTAssertEqual(book.pages.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(URL(string: library.summary(for: book).coverUrl))), Data([2]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.appendingPathComponent(book.id).path).count, 3)
    }

    func testGB18030FallbackIsGlobalButFlaggedNamesRemainUTF8() throws {
        var chinese = ZIPFixture.Item("", [1]); chinese.name = Data([0xb5, 0xda, 0x32, 0xbb, 0xb0]) + Data("/1.jpg".utf8)
        let flagged = ZIPFixture.Item("第10话/1.jpg", [2], flags: 0x800)
        // C2 A1 is valid UTF-8 (¡), but global GB18030 fallback must decode it as 隆.
        var ambiguous = ZIPFixture.Item("", [3]); ambiguous.name = Data([0xc2, 0xa1]) + Data("/1.jpg".utf8)
        let (root, archive, library) = try fixture(ZIPFixture.make([flagged, chinese, ambiguous]))
        defer { try? FileManager.default.removeItem(at: root) }
        let book = try library.importArchive(title: "中文", archive: archive, isReadableImage: { _ in true })
        XCTAssertEqual(book.chapters?.map(\.title), ["第2话", "第10话", "隆"])
        chinese.flags = 0x800
        try assertRejected(ZIPFixture.make([flagged, chinese]))
    }

    func testUnsafeNonImageAndMetadataPathsAndNormalizedDuplicatesRejectEntireArchive() throws {
        for path in ["../bad.txt", "/bad.txt", "C:bad.txt", "a\\..\\bad.txt", "a/..hidden.txt", "../__MACOSX/ignored.jpg"] {
            try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), .init(path, [2])]))
        }
        for paths in [["ch/1.jpg", "ch/./1.jpg"], ["ch//1.jpg", "ch\\1.jpg"], ["__MACOSX/a", "__MACOSX/./a"], [".DS_Store", "./.DS_Store"]] {
            try assertRejected(ZIPFixture.make([.init("1.jpg", [1])] + paths.map { .init($0, [2]) }))
        }
        var link = ZIPFixture.Item("link.jpg", [1]); link.externalAttributes = 0xa1ff << 16
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), link]))
    }

    func testMetadataUsesAndroidRawNameRuleAfterValidation() throws {
        let (root, archive, library) = try fixture(ZIPFixture.make([
            .init("prefix__MACOSX/1.jpg", [99]), .init("__MACOSX\\2.jpg", [2]), .init("1.jpg", [1])
        ]))
        defer { try? FileManager.default.removeItem(at: root) }
        let book = try library.importArchive(title: "metadata", archive: archive, isReadableImage: { _ in true })
        XCTAssertEqual(try library.pageURLs(for: book).map { try Data(contentsOf: $0).first! }, [1, 2])
    }

    func testDeclaredEntryAndTotalBudgetsIncludeDirectoriesAndMetadata() throws {
        var tooBig = ZIPFixture.Item("__MACOSX/ignored", []); tooBig.size = 128 * 1024 * 1024 + 1
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), tooBig]), budgetExceeded: true)
        tooBig.name = Data("directory/".utf8)
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), tooBig]), budgetExceeded: true)
        let many = (0..<161).map { index -> ZIPFixture.Item in
            var item = ZIPFixture.Item("__MACOSX/\(index)", [], deflate: true); item.size = 128 * 1024 * 1024; return item
        }
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1])] + many), budgetExceeded: true)
    }

    func testEntryCountIncludesDirectoriesAndMetadataAndRejects50001() throws {
        let entries = [.init("1.jpg", [1])] + (0..<49_999).map { ZIPFixture.Item("__MACOSX/\($0)/", []) }
        let (root, archive, library) = try fixture(ZIPFixture.make(entries))
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(try library.importArchive(title: "limit", archive: archive, isReadableImage: { _ in true }).pages.count, 1)
        try assertRejected(ZIPFixture.make(entries + [.init("__MACOSX/extra/", [])]), budgetExceeded: true)
    }

    func testCorruptCRCTruncatedStreamAndFalseActualLengthNeverPublish() throws {
        var bad = ZIPFixture.Item("2.jpg", [2], deflate: true); bad.crc = 123
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), bad]))
        bad.crc = nil; bad.payload = Data([0xff, 0xff])
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), bad]))
        bad.payload = nil; bad.size = 0
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), bad]))
        var truncated = try ZIPFixture.make([.init("1.jpg", [1])]); truncated.removeLast(4)
        try assertRejected(truncated)
    }

    func testTrailingEncryptedUnsupportedAndDamagedCentralEntriesCannotSilentlyTruncate() throws {
        var bad = ZIPFixture.Item("notes.txt", [2], flags: 1)
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), bad]))
        bad.flags = 0; bad.method = 99
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), bad]))
        bad.method = 0; bad.centralSignature = 0
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), bad]))
        bad.centralSignature = 0x02014b50; bad.disk = 1
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), bad]))
        bad.disk = 0; bad.localSignature = 0
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1]), bad]))
    }

    func testDeflateCannotReadBeyondDeclaredCompressedData() throws {
        var item = ZIPFixture.Item("1.jpg", Array(repeating: 42, count: 1024), deflate: true)
        item.packedSize = 1
        try assertRejected(ZIPFixture.make([item]))
    }

    func testDeflateRejectsTrailingBytesAfterStreamEnd() throws {
        var item = ZIPFixture.Item("1.jpg", [1], deflate: true)
        item.extraPayload = Data([0, 0])
        try assertRejected(ZIPFixture.make([item]))
    }

    func testDeflateLargerThanInputChunkWithShortFinalChunkPreservesBytes() throws {
        var seed: UInt32 = 1234
        let bytes = (0..<400_001).map { _ -> UInt8 in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: seed >> 24)
        }
        let (root, archive, library) = try fixture(ZIPFixture.make([.init("1.jpg", bytes, deflate: true), .init("empty.txt", [], deflate: true)]))
        defer { try? FileManager.default.removeItem(at: root) }
        let book = try library.importArchive(title: "large", archive: archive, isReadableImage: { _ in true })
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(library.pageURLs(for: book).first)), Data(bytes))
    }

    func testZIP64CountsAndMultidiskBoundsAreValidated() throws {
        let bytes = try ZIPFixture.make([.init("1.jpg", [1])], zip64: true)
        let (root, archive, library) = try fixture(bytes)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(try library.importArchive(title: "zip64", archive: archive, isReadableImage: { _ in true }).pages.count, 1)
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1])], zip64: true, countOverride: 2))
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1])], zip64: true, countOverride: 50_001))
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1])], disk: 1))
        try assertRejected(ZIPFixture.make([.init("1.jpg", [1])], countOverride: 0))
    }

    func testZIP64LocalSizeFieldsAndDataDescriptorsRemainReadable() throws {
        var forced = ZIPFixture.Item("1.jpg", [1], deflate: true); forced.localZIP64 = true
        let (root, archive, library) = try fixture(ZIPFixture.make([
            forced, .init("2.jpg", [2], deflate: true, flags: 8), .init("3.jpg", [3], flags: 8),
            .init("4.jpg", Array(repeating: 4, count: 1_048_576), deflate: true)
        ]))
        defer { try? FileManager.default.removeItem(at: root) }
        let book = try library.importArchive(title: "zip64 local", archive: archive, isReadableImage: { _ in true })
        let bytes = try library.pageURLs(for: book).map { try Data(contentsOf: $0) }
        XCTAssertEqual(bytes.map(\.count), [1, 1, 1, 1_048_576])
        XCTAssertEqual(bytes.map(\.first), [1, 2, 3, 4])
    }

    func testCancellationAfterExtractionAndEmptyImportCleanStagingAndKeepOriginal() async throws {
        let (root, archive, library) = try fixture(ZIPFixture.make([.init("1.jpg", [1]), .init("2.jpg", [2])]))
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: archive)
        let task = Task {
            try library.importArchive(title: "cancel", archive: archive, isReadableImage: { _ in
                withUnsafeCurrentTask { $0?.cancel() }; return true
            })
        }
        do { _ = try await task.value; XCTFail("Cancelled import published") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertThrowsError(try library.importArchive(title: "bad", archive: archive, isReadableImage: { _ in false }))
        XCTAssertTrue(try library.books().isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [])
        XCTAssertEqual(try Data(contentsOf: archive), original)
    }

    func testFilesystemReadErrorIsPreservedAndStagingIsRemoved() throws {
        let (root, _, library) = try fixture(ZIPFixture.make([.init("1.jpg", [1])]))
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try library.importArchive(title: "missing", archive: root.appendingPathComponent("missing.cbz"), isReadableImage: { _ in true })) { error in
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [])
    }

    #if canImport(ImageIO)
    func testRealImageProbeSkipsSignatureOnlyFirstImage() throws {
        let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
        let (root, archive, library) = try fixture(ZIPFixture.make([.init("1.png", [137, 80, 78, 71, 13, 10, 26, 10]), .init("2.gif", Array(gif), deflate: true)]))
        defer { try? FileManager.default.removeItem(at: root) }
        let book = try library.importArchive(title: "ImageIO", archive: archive, isReadableImage: LocalImageProbe.isReadable)
        XCTAssertEqual(book.pages.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(library.pageURLs(for: book).first)), gif)
    }
    #endif

    private func fixture(_ data: Data) throws -> (URL, URL, LocalLibrary) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("input.cbz")
        try data.write(to: archive)
        return (root, archive, try LocalLibrary(directory: root.appendingPathComponent("library")))
    }
    private func assertRejected(_ bytes: @autoclosure () throws -> Data, budgetExceeded: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
        let original = try bytes()
        let (root, archive, library) = try fixture(original)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try library.importArchive(title: "invalid", archive: archive, isReadableImage: { _ in true }), file: file, line: line) { error in
            if budgetExceeded {
                guard case LocalLibraryError.archiveTooLarge = error else { return XCTFail("Expected archive budget error, got \(error)", file: file, line: line) }
            }
        }
        XCTAssertEqual(try library.books(), [], file: file, line: line)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [], file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: archive), original, file: file, line: line)
    }
}

/// Deterministic ZIP records allow corrupt fixtures without a shell or checked-in binary blobs.
enum ZIPFixture {
    struct Item {
        var name: Data, data: Data, flags: UInt16, method: UInt16
        var size: UInt32?, packedSize: UInt32?, crc: UInt32?, payload: Data?
        var extraPayload = Data()
        var localZIP64 = false
        var externalAttributes: UInt32 = 0, disk: UInt16 = 0
        var centralSignature: UInt32 = 0x02014b50, localSignature: UInt32 = 0x04034b50
        init(_ name: String, _ bytes: [UInt8], deflate: Bool = false, flags: UInt16 = 0) {
            self.name = Data(name.utf8); data = Data(bytes); self.flags = flags; method = deflate ? 8 : 0
        }
    }
    static func make(_ items: [Item], zip64: Bool = false, countOverride: UInt64? = nil, disk: UInt16 = 0) throws -> Data {
        var local = Data(), central = Data()
        for item in items {
            let offset = UInt32(local.count)
            var payload = item.data
            if item.method == 8 {
                payload = Data()
                _ = try Data.compress(size: Int64(item.data.count), bufferSize: 32_768, provider: { position, count in
                    item.data.subdata(in: Int(position)..<min(Int(position) + count, item.data.count))
                }, consumer: { payload.append($0) })
            }
            payload = item.payload ?? payload
            payload.append(item.extraPayload)
            let crc = item.crc ?? checksum(item.data), size = item.size ?? UInt32(item.data.count)
            let packedSize = item.packedSize ?? UInt32(payload.count), descriptor = item.flags & 8 != 0
            var extra = Data()
            if item.localZIP64 { extra.le(UInt16(1)); extra.le(UInt16(16)); extra.le(UInt64(size)); extra.le(UInt64(packedSize)) }
            local.le(item.localSignature); local.le(UInt16(item.localZIP64 ? 45 : 20)); local.le(item.flags); local.le(item.method)
            local.le(UInt32(0)); local.le(descriptor ? UInt32(0) : crc)
            local.le(item.localZIP64 ? UInt32.max : (descriptor ? 0 : packedSize))
            local.le(item.localZIP64 ? UInt32.max : (descriptor ? 0 : size))
            local.le(UInt16(item.name.count)); local.le(UInt16(extra.count)); local.append(item.name); local.append(extra); local.append(payload)
            if descriptor { local.le(UInt32(0x08074b50)); local.le(crc); local.le(packedSize); local.le(size) }
            central.le(item.centralSignature); central.le(UInt16(0x0314)); central.le(UInt16(20))
            central.le(item.flags); central.le(item.method); central.le(UInt32(0)); central.le(crc)
            central.le(item.packedSize ?? UInt32(payload.count)); central.le(size); central.le(UInt16(item.name.count))
            central.le(UInt16(0)); central.le(UInt16(0)); central.le(item.disk); central.le(UInt16(0))
            central.le(item.externalAttributes); central.le(offset); central.append(item.name)
        }
        let start = UInt64(local.count), size = UInt64(central.count), count = countOverride ?? UInt64(items.count)
        local.append(central)
        if zip64 {
            let record = UInt64(local.count)
            local.le(UInt32(0x06064b50)); local.le(UInt64(44)); local.le(UInt16(45)); local.le(UInt16(45))
            local.le(UInt32(disk)); local.le(UInt32(disk)); local.le(count); local.le(count); local.le(size); local.le(start)
            local.le(UInt32(0x07064b50)); local.le(UInt32(0)); local.le(record); local.le(UInt32(1))
        }
        local.le(UInt32(0x06054b50)); local.le(disk); local.le(disk)
        local.le(zip64 ? UInt16.max : UInt16(count)); local.le(zip64 ? UInt16.max : UInt16(count))
        local.le(zip64 ? UInt32.max : UInt32(size)); local.le(zip64 ? UInt32.max : UInt32(start)); local.le(UInt16(0))
        return local
    }
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return crc ^ 0xffffffff
    }
}
extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
