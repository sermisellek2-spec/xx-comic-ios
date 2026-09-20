import Foundation
import XCTest
import ZIPFoundation
@testable import ComicCore

final class QuickPublicationInfoTests: XCTestCase {
    private let container = "<container><rootfiles><rootfile full-path='OPS/book.opf' media-type='application/oebps-package+xml'/></rootfiles></container>"
    private func package(_ contents: String) -> String {
        "<package xmlns='http://www.idpf.org/2007/opf' xmlns:dc='http://purl.org/dc/elements/1.1/'>\(contents)</package>"
    }
    private func temporaryFile(_ name: String = "book.epub") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent(name)
    }
    private func zip(_ entries: [(String, Data)], compression: CompressionMethod = .none) throws -> URL {
        let url = try temporaryFile()
        let archive = try Archive(url: url, accessMode: .create)
        for (path, bytes) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count), compressionMethod: compression,
                                 provider: { position, count in bytes.subdata(in: Int(position)..<min(Int(position) + count, bytes.count)) })
        }
        return url
    }
    private func epub(_ contents: String, files: [(String, Data)] = []) throws -> URL {
        try zip([("META-INF/container.xml", Data(container.utf8)), ("OPS/book.opf", Data(package(contents).utf8))] + files)
    }
    private func corrupt(_ url: URL, payload: String) throws {
        var bytes = try Data(contentsOf: url)
        let range = try XCTUnwrap(bytes.range(of: Data(payload.utf8)))
        bytes[range.lowerBound] ^= 1
        try bytes.write(to: url)
    }
    private func mobi(version: UInt32 = 6, encryption: UInt8 = 0) throws -> URL {
        let title = Data("头部标题".utf8)
        let recordOffset = 94, titleOffset = 248
        var bytes = Data(repeating: 0, count: recordOffset + titleOffset + title.count + 1)
        func put(_ offset: Int, _ value: UInt32) {
            bytes.replaceSubrange(offset..<offset + 4, with: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
        }
        bytes.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        bytes[77] = 2
        put(78, UInt32(recordOffset)); put(86, UInt32(bytes.count - 1))
        bytes[recordOffset + 1] = 2
        bytes[recordOffset + 9] = 1
        bytes[recordOffset + 13] = encryption
        bytes.replaceSubrange(recordOffset + 16..<recordOffset + 20, with: Data("MOBI".utf8))
        put(recordOffset + 20, 232); put(recordOffset + 24, 2)
        put(recordOffset + 28, 65001); put(recordOffset + 36, version)
        put(recordOffset + 84, UInt32(titleOffset)); put(recordOffset + 88, UInt32(title.count))
        bytes.replaceSubrange(recordOffset + titleOffset..<bytes.count - 1, with: title)
        // Invalid PalmDOC body: metadata scanning must never decode this text record.
        bytes[bytes.count - 1] = 0x80
        let url = try temporaryFile("book.mobi")
        try bytes.write(to: url)
        return url
    }

    func testMetadataScanAcceptsMissingBodyAndCoverWithCalibreSeries() throws {
        let url = try epub("""
            <metadata><dc:title> 夏日列车 </dc:title><meta name='calibre:series' content='四季故事'/>
            <meta name='calibre:series_index' content='2.5'/><meta name='cover' content='cover'/></metadata>
            <manifest><item id='cover' href='../Images/cover%20art.jpg' media-type='image/jpeg'/>
            <item id='body' href='missing.xhtml' media-type='application/xhtml+xml'/></manifest>
            <spine><itemref idref='body'/></spine>
            """)
        let original = try Data(contentsOf: url)
        let info = try QuickPublicationInfo.read(url)
        XCTAssertEqual(info.title, "夏日列车")
        XCTAssertEqual(info.seriesTitle, "四季故事")
        XCTAssertEqual(info.volumeNumber, "2.5")
        XCTAssertEqual(info.coverEntry, "Images/cover art.jpg")
        XCTAssertTrue(info.isReadable)
        XCTAssertNil(info.unsupportedReason)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testFirstMetadataFirstTitleAndLastCalibreValuesKeepDecimalText() throws {
        let info = try QuickPublicationInfo.read(epub("""
            <metadata><other:title xmlns:other='urn:other'> \u{00a0}首标题\u{00a0} </other:title><dc:title>后标题</dc:title>
            <meta name='calibre:series' content='旧系列'/><meta name='calibre:series_index' content='1'/>
            <meta property='belongs-to-collection' id='set'>不能覆盖</meta><meta refines='#set' property='collection-type'>series</meta>
            <meta name='calibre:series' content=' 新系列 '/><meta name='calibre:series_index' content=' 9007199254740993.000100 '/></metadata>
            <metadata><title>其他metadata</title><meta name='calibre:series' content='错误系列'/></metadata>
            """))
        XCTAssertEqual(info.title, "\u{00a0}首标题\u{00a0}")
        XCTAssertEqual(info.seriesTitle, "新系列")
        XCTAssertEqual(info.volumeNumber, "9007199254740993.000100")
    }

    func testEpub3RefinementsUseLastValuesAndFirstMatchingSeries() throws {
        let info = try QuickPublicationInfo.read(epub("""
            <metadata><meta name='calibre:series' content='旧系列'/><meta name='calibre:series' content=' '/>
            <meta name='calibre:series_index' content='99'/><meta property='belongs-to-collection'>无ID</meta>
            <meta property='belongs-to-collection' id='skip'>丛书</meta><meta refines='#skip' property='collection-type'>set</meta>
            <meta refines='#set' property='collection-type'>set</meta><meta refines='#set' property='group-position'>1</meta>
            <meta property='belongs-to-collection' id='set'> 长篇 </meta><meta refines='#set' property='collection-type'> series </meta>
            <meta refines='#set' property='group-position'> 3.000000000000000001 </meta>
            <meta property='belongs-to-collection' id='later'>后系列</meta><meta refines='#later' property='collection-type'>series</meta>
            </metadata><manifest><item href='cover+one.png' properties='nav&#x9;cover-image'/></manifest>
            """), formatOrFileName: "backup.BOOK.EPUB")
        XCTAssertEqual(info.seriesTitle, "长篇")
        XCTAssertEqual(info.volumeNumber, "3.000000000000000001")
        XCTAssertEqual(info.coverEntry, "OPS/cover+one.png")
    }

    func testMissingMetadataReturnsEmptyFieldsAndStillFindsGlobalCoverItem() throws {
        let empty = try QuickPublicationInfo.read(epub("<manifest/><spine/>"))
        XCTAssertEqual(empty.title, ""); XCTAssertEqual(empty.seriesTitle, "")
        XCTAssertEqual(empty.volumeNumber, ""); XCTAssertEqual(empty.coverEntry, "")
        XCTAssertTrue(empty.isReadable)
        let info = try QuickPublicationInfo.read(epub("<item href='first.jpg' properties='not-cover-image'/><item href='second.jpg' properties='cover-image'/><item href='third.jpg' properties='cover-image'/>"))
        XCTAssertEqual(info.coverEntry, "OPS/second.jpg")
    }

    func testCoverUsesFirstGlobalMatchAndLastCoverIdWithoutOpeningIt() throws {
        let info = try QuickPublicationInfo.read(epub("""
            <metadata><meta name='cover' content='old'/><meta name='cover' content='new'/></metadata>
            <item id='old' href='old.jpg'/><item id='new' href='wrapper.xhtml'/><item href='later.jpg' properties='cover-image'/>
            """))
        XCTAssertEqual(info.coverEntry, "OPS/wrapper.xhtml")
    }

    func testCollectionAndCoverIDsMatchJavaWithoutUnicodeCanonicalFolding() throws {
        let info = try QuickPublicationInfo.read(epub("""
            <metadata><meta property='belongs-to-collection' id='Café'>错误系列</meta>
            <meta refines='#Cafe\u{301}' property='collection-type'>series</meta>
            <meta property='belongs-to-collection' id='correct'>正确系列</meta>
            <meta refines='#correct' property='collection-type'>series</meta>
            <meta name='cover' content='Café'/></metadata>
            <item id='Cafe\u{301}' href='wrong.jpg'/><item id='Café' href='correct.jpg'/>
            """))
        XCTAssertEqual(info.seriesTitle, "正确系列")
        XCTAssertEqual(info.coverEntry, "OPS/correct.jpg")
    }

    func testCoverPropertiesSplitCRLFButNotNonbreakingSpace() throws {
        let info = try QuickPublicationInfo.read(epub("<item href='wrong.jpg' properties='nav&#xA0;cover-image'/><item href='correct.jpg' properties='nav&#xD;&#xA;cover-image'/><item href='later.jpg' properties='cover-image'/>"))
        XCTAssertEqual(info.coverEntry, "OPS/correct.jpg")
    }

    func testRootfileSelectionAndSingleDecodePreserveLiteralPlus() throws {
        let roots = "<container><rootfile full-path='first.opf'/><rootfile full-path='older.opf' media-type='application/oebps-package+xml'/><rootfile full-path=' OPS/a+b%20c%2520.opf ' media-type='application/oebps-package+xml'/><rootfile full-path='ignored.opf' media-type='APPLICATION/OEBPS-PACKAGE+XML'/></container>"
        let url = try zip([("META-INF/container.xml", Data(roots.utf8)), ("OPS/a+b c%20.opf", Data(package("<metadata><title>选中</title></metadata><item properties='cover-image' href='../Images/cover+art%20%2B%2520.jpg'/>").utf8))])
        let info = try QuickPublicationInfo.read(url)
        XCTAssertEqual(info.title, "选中")
        XCTAssertEqual(info.coverEntry, "Images/cover+art +%20.jpg")
        let fallback = try zip([("META-INF/container.xml", Data("<container><rootfile full-path=' '/><rootfile full-path='first.opf'/><rootfile full-path='ignored.opf'/></container>".utf8)), ("first.opf", Data(package("<metadata><title>首个非空</title></metadata>").utf8))])
        XCTAssertEqual(try QuickPublicationInfo.read(fallback).title, "首个非空")
    }

    func testCorruptBodyCoverNavigationAndEncryptionAreNeverRead() throws {
        let files = [("OPS/body.xhtml", "BODY_PAYLOAD"), ("OPS/cover.jpg", "COVER_PAYLOAD"), ("OPS/nav.xhtml", "NAV_PAYLOAD"), ("META-INF/encryption.xml", "ENCRYPTION_PAYLOAD")]
        let url = try epub("<metadata><title>只扫描元数据</title></metadata><manifest><item id='body' href='body.xhtml'/><item href='cover.jpg' properties='cover-image'/><item href='nav.xhtml' properties='nav'/></manifest><spine><itemref idref='body'/></spine>", files: files.map { ($0.0, Data($0.1.utf8)) })
        for (_, payload) in files { try corrupt(url, payload: payload) }
        let original = try Data(contentsOf: url)
        let info = try QuickPublicationInfo.read(url)
        XCTAssertEqual(info.title, "只扫描元数据")
        XCTAssertEqual(info.coverEntry, "OPS/cover.jpg")
        XCTAssertTrue(info.isReadable)
        // Prove each resource really fails CRC if opened.
        let archive = try EpubArchive(url: url)
        for (path, _) in files { XCTAssertThrowsError(try archive.read(path)) }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testMetadataCRCCorruptionFailsAndRetainsOriginalFile() throws {
        for payload in ["rootfiles", "UNIQUE_METADATA"] {
            let url = try epub("<metadata><title>UNIQUE_METADATA</title></metadata>")
            try corrupt(url, payload: payload)
            let original = try Data(contentsOf: url)
            XCTAssertThrowsError(try QuickPublicationInfo.read(url)) { XCTAssertTrue($0.localizedDescription.contains("CRC")) }
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testDoctypeRejectedInBothMetadataFilesAcrossUTFEncodings() throws {
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            for target in ["META-INF/container.xml", "OPS/book.opf"] {
                let malicious = "<!DOCTYPE package [<!ENTITY secret SYSTEM 'file:///never-read-this'>]>" + (target.hasSuffix(".opf") ? package("") : container)
                let url = try zip([("META-INF/container.xml", target.hasSuffix(".xml") ? try XCTUnwrap(malicious.data(using: encoding)) : Data(container.utf8)), ("OPS/book.opf", target.hasSuffix(".opf") ? try XCTUnwrap(malicious.data(using: encoding)) : Data(package("").utf8))])
                XCTAssertThrowsError(try QuickPublicationInfo.read(url)) { XCTAssertEqual($0 as? EpubError, .unsafeXML) }
            }
        }
    }

    func testCompressedMetadataOneMiBLimitAndTwoMiBCombinedBoundary() throws {
        let maximum = 1024 * 1024
        let opf = package("<metadata><title>边界</title></metadata>")
        let paddedContainer = Data(container.utf8) + Data(repeating: 32, count: maximum - container.utf8.count)
        let paddedOPF = Data(opf.utf8) + Data(repeating: 32, count: maximum - opf.utf8.count)
        let valid = try zip([("META-INF/container.xml", paddedContainer), ("OPS/book.opf", paddedOPF)], compression: .deflate)
        XCTAssertEqual(try QuickPublicationInfo.read(valid).title, "边界")
        for target in ["META-INF/container.xml", "OPS/book.opf"] {
            let url = try zip([("META-INF/container.xml", paddedContainer + (target.hasSuffix(".xml") ? Data([32]) : Data())), ("OPS/book.opf", paddedOPF + (target.hasSuffix(".opf") ? Data([32]) : Data()))], compression: .deflate)
            XCTAssertThrowsError(try QuickPublicationInfo.read(url)) {
                guard case .limitExceeded = $0 as? EpubError else { return XCTFail("\($0)") }
            }
        }
    }

    func testInvalidRootfileAndCoverPathsFailBeforeNormalization() throws {
        for path in ["", "../../escape", "/absolute", "%2Fabsolute", "\\absolute", "C:\\absolute", "https://host/book", "safe/name:bad", "safe/../bad:part/../cover.jpg", "%00bad", "%xx", "%", "%2"] {
            let cover = try epub("<item properties='cover-image' href='\(path)'/>")
            XCTAssertThrowsError(try QuickPublicationInfo.read(cover), "cover: \(path)")
            let root = try zip([("META-INF/container.xml", Data("<container><rootfile full-path='\(path)'/></container>".utf8))])
            XCTAssertThrowsError(try QuickPublicationInfo.read(root), "root: \(path)")
        }
    }

    func testMissingMalformedAndOverdeepMetadataFail() throws {
        for entries: [(String, Data)] in [[], [("META-INF/container.xml", Data(container.utf8))], [("META-INF/container.xml", Data("<container/>".utf8))], [("META-INF/container.xml", Data("<container>".utf8))]] {
            XCTAssertThrowsError(try QuickPublicationInfo.read(zip(entries)))
        }
        for xml in ["<package>", String(repeating: "<n>", count: 129) + String(repeating: "</n>", count: 129), "<r>" + String(repeating: "<n/>", count: 100_000) + "</r>"] {
            let url = try zip([("META-INF/container.xml", Data(container.utf8)), ("OPS/book.opf", Data(xml.utf8))])
            XCTAssertThrowsError(try QuickPublicationInfo.read(url))
        }
    }

    func testArchiveSymlinkIsRejectedEvenForMissingCover() throws {
        let url = try epub("<item href='link' properties='cover-image'/>")
        do {
            let archive = try Archive(url: url, accessMode: .update)
            let target = Data("/etc/passwd".utf8)
            try archive.addEntry(with: "OPS/link", type: .symlink, uncompressedSize: Int64(target.count), provider: { position, count in target.subdata(in: Int(position)..<min(Int(position) + count, target.count)) })
        }
        XCTAssertThrowsError(try QuickPublicationInfo.read(url)) { XCTAssertTrue($0.localizedDescription.contains("符号链接")) }
    }

    func testKindleFormatsKeepHeaderTitleAndUnsupportedStatusWithoutDecodingBody() throws {
        for format in ["mobi", "AZW", "book.azw3", "backup.book.PRC"] {
            let readable = try QuickPublicationInfo.read(mobi(), formatOrFileName: format)
            XCTAssertEqual(readable.title, "头部标题")
            XCTAssertTrue(readable.isReadable); XCTAssertNil(readable.unsupportedReason)
            XCTAssertEqual(readable.seriesTitle, ""); XCTAssertEqual(readable.volumeNumber, ""); XCTAssertEqual(readable.coverEntry, "")
            let kf8 = try QuickPublicationInfo.read(mobi(version: 8), formatOrFileName: format)
            XCTAssertEqual(kf8.title, "头部标题")
            XCTAssertFalse(kf8.isReadable); XCTAssertTrue(kf8.unsupportedReason?.contains("KF8") == true)
        }
        let drm = try QuickPublicationInfo.read(mobi(encryption: 2))
        XCTAssertEqual(drm.title, "头部标题")
        XCTAssertFalse(drm.isReadable); XCTAssertTrue(drm.unsupportedReason?.contains("DRM") == true)
        let corrupt = try temporaryFile("bad.mobi")
        try Data([0]).write(to: corrupt)
        let bad = try QuickPublicationInfo.read(corrupt)
        XCTAssertFalse(bad.isReadable); XCTAssertNotNil(bad.unsupportedReason)
    }

    func testFormatDefaultsOverridesAndUnsupportedErrors() throws {
        let url = try epub("<metadata><title>明确格式</title></metadata>")
        let renamed = url.deletingLastPathComponent().appendingPathComponent("data.bin")
        try FileManager.default.copyItem(at: url, to: renamed)
        XCTAssertEqual(try QuickPublicationInfo.read(renamed, formatOrFileName: "EPUB").title, "明确格式")
        XCTAssertThrowsError(try QuickPublicationInfo.read(renamed)) { XCTAssertTrue($0.localizedDescription.contains("不支持") && $0.localizedDescription.contains("bin")) }
        for format in ["", "book.", "pdf", "cbz"] { XCTAssertThrowsError(try QuickPublicationInfo.read(url, formatOrFileName: format)) }
        XCTAssertThrowsError(try QuickPublicationInfo.read(url.appendingPathExtension("missing"), formatOrFileName: "epub"))
    }

    func testCancellationPropagatesForEPUBAndKindleAndKeepsFiles() async throws {
        for url in [try epub("<metadata><title>取消</title></metadata>"), try mobi()] {
            let original = try Data(contentsOf: url)
            let task = Task.detached {
                withUnsafeCurrentTask { $0?.cancel() }
                return try QuickPublicationInfo.read(url)
            }
            do { _ = try await task.value; XCTFail("取消不能返回空扫描结果") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }
}
