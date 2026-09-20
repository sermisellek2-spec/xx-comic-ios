import Foundation
import XCTest
@testable import ComicCore

final class KindleFormatTests: XCTestCase {
    // All offsets here are record-0 relative, hand-checked against the Android contract.
    private func word(_ value: UInt32) -> Data {
        Data([UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
              UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }
    private func put(_ data: inout Data, _ offset: Int, _ value: UInt32) {
        data.replaceSubrange(offset..<offset + 4, with: word(value))
    }
    private func record(title: Data = Data("  我的经典小说\n".utf8), encoding: UInt32 = 65001,
                        version: UInt32 = 6, entries: [(UInt32, Data)] = [(100, Data(" 测试作者\n".utf8)), (201, Data([0, 0, 0, 0]))]) -> Data {
        var data = Data(repeating: 0, count: 512)
        data[1] = 2
        data.replaceSubrange(16..<20, with: Data("MOBI".utf8))
        put(&data, 20, 232)
        put(&data, 24, 2)
        put(&data, 28, encoding)
        put(&data, 36, version)
        put(&data, 84, 448)
        put(&data, 88, UInt32(title.count))
        put(&data, 108, 2)
        put(&data, 144, 0x40)
        put(&data, 168, .max)
        put(&data, 172, .max)
        var exth = Data("EXTH".utf8) + word(12) + word(UInt32(entries.count))
        for (type, payload) in entries { exth += word(type) + word(UInt32(8 + payload.count)) + payload }
        put(&exth, 4, UInt32(exth.count))
        data.replaceSubrange(248..<248 + exth.count, with: exth)
        data.replaceSubrange(448..<448 + title.count, with: title)
        return data
    }
    private func pdb(_ record: Data, count: Int = 4) -> Data {
        var data = Data(repeating: 0, count: 78 + count * 8)
        data.replaceSubrange(0..<10, with: Data(" PDB name ".utf8))
        data.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        data[76] = UInt8(truncatingIfNeeded: count >> 8)
        data[77] = UInt8(truncatingIfNeeded: count)
        put(&data, 78, UInt32(data.count))
        for index in 1..<count { put(&data, 78 + index * 8, UInt32(78 + count * 8 + record.count + index - 1)) }
        return data + record + Data(repeating: 0, count: count - 1)
    }
    private func file(_ data: Data, extension ext: String = "mobi") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try data.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func detect(_ data: Data, extension ext: String = "mobi") throws -> KindleDetection {
        try KindleFormatDetector.detect(file(data, extension: ext))
    }

    func testMobi7ChineseMetadataAndExtensionSpoofing() throws {
        let result = try detect(pdb(record()), extension: "png")
        XCTAssertEqual(result.variant, .mobi7)
        XCTAssertEqual(result.drm, .none)
        XCTAssertTrue(result.isReadable)
        XCTAssertNil(result.unsupportedReason)
        XCTAssertEqual(result.title, "我的经典小说")
        XCTAssertEqual(result.author, "测试作者")
        XCTAssertEqual(result.encoding, "UTF-8")
        XCTAssertEqual(result.compression, 2)
        XCTAssertEqual(result.recordCount, 4)
        XCTAssertEqual(result.firstImageRecord, 2)
        XCTAssertEqual(result.coverRecordIndex, 2)
        XCTAssertEqual(result.kf8BoundaryRecord, -1)
    }
    func testLatin1TitlesAndWindows1252EncodingMarker() throws {
        let result = try detect(pdb(record(title: Data([32, 67, 97, 102, 233, 32]), encoding: 1252)))
        XCTAssertEqual(result.title, "Café")
        XCTAssertEqual(result.encoding, "Windows-1252")
        var bytes = pdb(Data([0, 1]) + Data(repeating: 0, count: 14))
        bytes.replaceSubrange(0..<6, with: Data([32, 67, 97, 102, 233, 0]))
        XCTAssertEqual(try detect(bytes).title, "Café")
    }
    func testPalmDocWithAndWithoutMobiMagicAndPdbTypeOrCreator() throws {
        for length in [16, 23, 40] {
            var body = Data(repeating: 0, count: length)
            body[1] = 1
            let result = try detect(pdb(body))
            XCTAssertEqual(result.variant, .palmDoc)
            XCTAssertTrue(result.isReadable)
            XCTAssertEqual(result.title, "PDB name")
            XCTAssertEqual(result.encoding, "Windows-1252")
            body[13] = 2
            XCTAssertEqual(try detect(pdb(body)).drm, .mobipocket)
            XCTAssertFalse(try detect(pdb(body)).isReadable)
        }
        for identity in ["BOOKxxxx", "TEXtxxxx", "xxxxMOBI"] {
            var bytes = pdb(record())
            bytes.replaceSubrange(60..<68, with: Data(identity.utf8))
            XCTAssertEqual(try detect(bytes).variant, .mobi7)
        }
        var unknown = pdb(record())
        unknown.replaceSubrange(60..<68, with: Data("xxxxxxxx".utf8))
        XCTAssertEqual(try detect(unknown).variant, .unknown)
    }
    func testKf8TypeOrVersionAndValidComboBoundaryPrecedence() throws {
        var type248 = record()
        put(&type248, 24, 248)
        for bytes in [record(version: 8), type248] {
            let result = try detect(pdb(bytes))
            XCTAssertEqual(result.variant, .kf8)
            XCTAssertFalse(result.isReadable)
            XCTAssertTrue(result.unsupportedReason?.contains("KF8") == true)
        }
        let combo = try detect(pdb(record(version: 8, entries: [(121, word(3))])))
        XCTAssertEqual(combo.variant, .combo)
        XCTAssertTrue(combo.isReadable)
        XCTAssertEqual(combo.kf8BoundaryRecord, 3)
        for boundary: UInt32 in [0, 4, .max] {
            XCTAssertEqual(try detect(pdb(record(entries: [(121, word(boundary))]))).variant, .mobi7)
        }
    }
    func testContainerMagicPrecedesPdbAndIgnoresExtension() throws {
        for (magic, variant, drm): (Data, KindleVariant, KindleDRM) in [
            (Data([0xEA, 75, 70, 88]), .kfx, .kfx), (Data("TPZ".utf8), .topaz, .amazon), (Data("azw1".utf8), .topaz, .amazon)
        ] {
            let result = try detect(magic + Data(repeating: 0, count: 8 - magic.count))
            XCTAssertEqual(result.variant, variant)
            XCTAssertEqual(result.drm, drm)
            XCTAssertFalse(result.isReadable)
            XCTAssertNotNil(result.unsupportedReason)
        }
        XCTAssertEqual(try detect(Data([0xEA, 75, 70, 88])).variant, .corrupt)
    }
    func testDrmDocumentedOffsetsSentinelsAndEncryptionPriority() throws {
        var bytes = record()
        put(&bytes, 188, 1)
        put(&bytes, 196, 1)
        XCTAssertEqual(try detect(pdb(bytes)).drm, .none)
        put(&bytes, 168, 5)
        put(&bytes, 172, 1)
        put(&bytes, 176, 16)
        let protected = try detect(pdb(bytes))
        XCTAssertEqual(protected.drm, .amazon)
        XCTAssertFalse(protected.isReadable)
        XCTAssertTrue(protected.unsupportedReason?.contains("DRM") == true)
        bytes[13] = 1
        XCTAssertEqual(try detect(pdb(bytes)).drm, .mobipocket)
        for offset in [168, 172, 176] {
            var sentinel = bytes
            sentinel[13] = 0
            put(&sentinel, offset, .max)
            XCTAssertEqual(try detect(pdb(sentinel)).drm, .none)
        }
        var encrypted = record()
        encrypted[13] = 2
        XCTAssertEqual(try detect(pdb(encrypted)).drm, .amazon)
    }
    func testCorruptHeadersAndRecordTables() throws {
        for size in [0, 3, 7, 8, 50, 77] {
            XCTAssertEqual(try detect(Data(repeating: 0, count: size)).variant, .corrupt)
        }
        var empty = pdb(record())
        empty[77] = 0
        XCTAssertEqual(try detect(empty).variant, .corrupt)
        XCTAssertEqual(try detect(Data(pdb(record()).prefix(90))).variant, .corrupt)
        for (offset, value): (Int, UInt32) in [(78, 109), (78, .max), (86, 110), (86, 109), (102, 625)] {
            var bytes = pdb(record())
            put(&bytes, offset, value)
            XCTAssertEqual(try detect(bytes).variant, .corrupt, "table offset \(offset), value \(value)")
        }
        XCTAssertEqual(try detect(pdb(Data(repeating: 0, count: 15))).variant, .corrupt)
    }
    func testUnsupportedCompressionAndMobiHeaderBounds() throws {
        for compression: UInt16 in [0, 3, 17480] {
            var bytes = record()
            bytes[0] = UInt8(truncatingIfNeeded: compression >> 8)
            bytes[1] = UInt8(truncatingIfNeeded: compression)
            let result = try detect(pdb(bytes))
            XCTAssertEqual(result.variant, .unknown)
            XCTAssertFalse(result.isReadable)
            XCTAssertTrue(result.unsupportedReason?.contains("HUFF") == true)
        }
        for length: UInt32 in [0, 15, 497, 65537, .max] {
            var bytes = record()
            put(&bytes, 20, length)
            XCTAssertEqual(try detect(pdb(bytes)).variant, .corrupt)
        }
        var shortest = record()
        put(&shortest, 20, 16)
        XCTAssertEqual(try detect(pdb(Data(shortest.prefix(32)))).variant, .mobi7)
    }
    func testTitleRecordRelativePriorityMobiFallbackAndRecordBoundary() throws {
        var bytes = record(title: Data("Primary".utf8))
        bytes.replaceSubrange(464..<471, with: Data("Ignored".utf8))
        XCTAssertEqual(try detect(pdb(bytes)).title, "Primary")
        bytes.replaceSubrange(448..<455, with: Data(repeating: 0, count: 7))
        XCTAssertEqual(try detect(pdb(bytes)).title, "Ignored")
        for (offset, length): (UInt32, UInt32) in [(510, 3), (.max, 3), (448, 65537), (448, .max), (0, 7)] {
            var bad = record()
            put(&bad, 84, offset)
            put(&bad, 88, length)
            var container = pdb(bad)
            container[110 + 512] = 90 // Would leak "Z" into a title spanning record 0 and record 1.
            XCTAssertEqual(try detect(container).title, "PDB name")
        }
    }
    func testExthTotalBoundsMalformedEntriesAndUnflaggedMetadata() throws {
        for length: UInt32 in [0, 11, 265, .max] {
            var bytes = record()
            put(&bytes, 252, length)
            XCTAssertEqual(try detect(pdb(bytes)).variant, .corrupt)
        }
        for entryLength: UInt32 in [0, 7, 65537, .max, 200] {
            var bytes = record()
            put(&bytes, 264, entryLength)
            let result = try detect(pdb(bytes))
            XCTAssertEqual(result.variant, .mobi7)
            XCTAssertEqual(result.author, "")
            XCTAssertEqual(result.coverRecordIndex, -1)
        }
        var unflagged = record()
        put(&unflagged, 144, 0)
        XCTAssertEqual(try detect(pdb(unflagged)).author, "测试作者")
        // A header in record 1 must not be interpreted as record-0 metadata.
        var noMetadata = Data(record().prefix(248))
        put(&noMetadata, 84, 0)
        var outside = pdb(noMetadata)
        outside.replaceSubrange(358..<outside.count, with: Data("EXTH".utf8) + word(25) + word(1) + word(100) + word(13) + Data("Wrong".utf8))
        XCTAssertEqual(try detect(outside).author, "")
        let shortValues = try detect(pdb(record(entries: [(121, Data([1])), (201, Data([1]))])))
        XCTAssertEqual(shortValues.kf8BoundaryRecord, -1)
        XCTAssertEqual(shortValues.coverRecordIndex, -1)
    }
    func testCoverIndicesRejectUnsignedSentinelsAndOverflow() throws {
        for (first, cover, expected): (UInt32, UInt32, Int) in [(2, 1, 3), (2, 2, -1), (0, 0, -1), (.max, 0, -1),
                                                             (2, .max, -1), (0x7fffffff, 0x7fffffff, -1)] {
            var bytes = record(entries: [(201, word(cover))])
            put(&bytes, 108, first)
            XCTAssertEqual(try detect(pdb(bytes)).coverRecordIndex, expected)
        }
    }
    func testMaximumHeaderTitleAndExthEntryLengthsAreAccepted() throws {
        var header = Data(record().prefix(248)) + Data(repeating: 0, count: 65536 + 16 - 248)
        put(&header, 20, 65536)
        put(&header, 84, 0)
        XCTAssertEqual(try detect(pdb(header, count: 1)).variant, .mobi7)

        var title = Data(record().prefix(448)) + Data(repeating: 65, count: 65536)
        put(&title, 88, 65536)
        XCTAssertEqual(try detect(pdb(title)).title, String(repeating: "A", count: 65536))

        var author = Data(record().prefix(248))
        author += Data("EXTH".utf8) + word(65548) + word(1) + word(100) + word(65536)
        author += Data(repeating: 66, count: 65528)
        put(&author, 84, 0)
        XCTAssertEqual(try detect(pdb(author)).author, String(repeating: "B", count: 65528))
    }
    func testPrimaryTitleComparedUsingJavaCodeUnitsBeforeFallback() throws {
        var body = record(title: Data("Cafe\u{301}".utf8))
        body.replaceSubrange(464..<470, with: Data("Wrong!".utf8))
        var bytes = pdb(body)
        bytes.replaceSubrange(0..<6, with: Data([67, 97, 102, 233, 0, 0]))
        XCTAssertEqual(Array(try detect(bytes).title.utf8), [67, 97, 102, 101, 204, 129])
    }
    func testMissingFileThrowsIOError() throws {
        XCTAssertThrowsError(try KindleFormatDetector.detect(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))) {
            XCTAssertFalse($0 is CancellationError)
        }
    }
    func testDetectionCancellationIsNotCorrupt() async throws {
        let url = try file(pdb(record()))
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try KindleFormatDetector.detect(url)
        }
        do { _ = try await worker.value; XCTFail("取消应抛出") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testDetectionCancellationDuringLargeRecordTable() async throws {
        let url = try file(pdb(record(), count: 65535))
        let started = expectation(description: "worker entered file inspection")
        let worker = Task.detached {
            started.fulfill()
            return try KindleFormatDetector.detect(url)
        }
        await fulfillment(of: [started], timeout: 2)
        try await Task.sleep(nanoseconds: 10_000_000)
        worker.cancel()
        do { _ = try await worker.value; XCTFail("扫描记录表时应响应取消") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testPalmDocLiteralSpaceAndIndependentBackreferenceOracle() throws {
        XCTAssertEqual(try PalmDoc.decompress(Data([65, 66, 67, 0x80, 0x18])), Data("ABCABC".utf8))
        XCTAssertEqual(try PalmDoc.decompress(Data([0, 3, 1, 128, 255, 9, 127, 0xC1])), Data([0, 1, 128, 255, 9, 127, 32, 65]))
        XCTAssertEqual(try PalmDoc.decompress(Data([65, 0x80, 0x0F])), Data("AAAAAAAAAAA".utf8))
        let first = Data("Hello World!".utf8) + Data([0x80]), second = Data([0x63])
        XCTAssertEqual(try PalmDoc.decompress(first + second), Data("Hello World!Hello ".utf8))
        // Data slices can have a non-zero startIndex.
        XCTAssertEqual(try PalmDoc.decompress(Data([0, 65, 66]).dropFirst()), Data("AB".utf8))
    }
    func testPalmDocRejectsTruncatedLiteralsAndInvalidBackreferences() {
        for bytes: [UInt8] in [[0x80], [0x80, 0], [0x80, 8], [2, 65], [65, 0x80, 16]] {
            XCTAssertThrowsError(try PalmDoc.decompress(Data(bytes)))
        }
    }
    func testPalmDocAllBranchesRespectDeclaredOutputAndIgnorePadding() throws {
        XCTAssertEqual(try PalmDoc.decompress(Data([0xC1]), maximumOutputBytes: 1), Data([32]))
        XCTAssertEqual(try PalmDoc.decompress(Data([0, 0x80]), maximumOutputBytes: 1), Data([0]))
        XCTAssertEqual(try PalmDoc.decompress(Data([2, 65, 66, 0x80]), maximumOutputBytes: 1), Data([65]))
        XCTAssertEqual(try PalmDoc.decompress(Data([65, 0x80, 0x0F, 0x80]), maximumOutputBytes: 3), Data("AAA".utf8))
        XCTAssertEqual(try PalmDoc.decompress(Data([65, 66, 67, 0x80]), maximumOutputBytes: 3), Data("ABC".utf8))
        for limit in [0, -1, Int.min] { XCTAssertEqual(try PalmDoc.decompress(Data([0x80]), maximumOutputBytes: limit), Data()) }
        XCTAssertEqual(try PalmDoc.decompress(Data()), Data())
    }
    func testPalmDocInputAndOutputMaximumBoundaries() throws {
        let maximum = 8 * 1024 * 1024
        let bytes = Data(repeating: 65, count: maximum + 1)
        let result = try PalmDoc.decompress(bytes, maximumOutputBytes: Int.max)
        XCTAssertEqual(result.count, maximum)
        XCTAssertTrue(result.allSatisfy { $0 == 65 })
        XCTAssertEqual(try PalmDoc.decompress(Data(repeating: 0xC1, count: maximum / 2 + 1)).count, maximum)
        XCTAssertEqual(try PalmDoc.decompress(Data(repeating: 65, count: 16 * 1024 * 1024), maximumOutputBytes: 1), Data([65]))
        XCTAssertThrowsError(try PalmDoc.decompress(Data(repeating: 65, count: 16 * 1024 * 1024 + 1)))
    }
    func testPalmDocPreCancellationAndCancellationDuringLargeInput() async throws {
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try PalmDoc.decompress(Data([65]))
        }
        do { _ = try await cancelled.value; XCTFail("取消应抛出") } catch { XCTAssertTrue(error is CancellationError) }
        let started = expectation(description: "worker entered decompression")
        let bytes = Data(repeating: 65, count: 16 * 1024 * 1024)
        let worker = Task.detached {
            started.fulfill()
            return try PalmDoc.decompress(bytes)
        }
        await fulfillment(of: [started], timeout: 2)
        // Give the synchronous decoder time to enter its loop before cancelling.
        try await Task.sleep(nanoseconds: 10_000_000)
        worker.cancel()
        do { _ = try await worker.value; XCTFail("运行中取消应抛出") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
