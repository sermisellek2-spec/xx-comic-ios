import Foundation
import XCTest
import ZIPFoundation
@testable import ComicCore

final class EpubParserTests: XCTestCase {
    private let container = "<container><rootfiles><rootfile full-path='OEBPS/content.opf' media-type='application/oebps-package+xml'/></rootfiles></container>"
    private func item(_ id: String, _ href: String, _ media: String = "application/xhtml+xml", _ properties: String = "") -> String {
        "<item id='\(id)' href='\(href)' media-type='\(media)' properties='\(properties)'/>"
    }
    private func opf(_ manifest: String, _ spine: String, metadata: String = "<dc:title>测试书</dc:title>") -> String {
        "<package xmlns:dc='http://purl.org/dc/elements/1.1/'><metadata>\(metadata)</metadata><manifest>\(manifest)</manifest><spine>\(spine)</spine></package>"
    }
    private func fixture(_ opf: String, files: [(String, String)] = [], container: String? = nil,
                         compression: CompressionMethod = .none) throws -> URL {
        try zip([("META-INF/container.xml", Data((container ?? self.container).utf8)), ("OEBPS/content.opf", Data(opf.utf8))] + files.map { ($0.0, Data($0.1.utf8)) }, compression: compression)
    }
    private func zip(_ files: [(String, Data)], compression: CompressionMethod = .none) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("book.epub")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: compression,
                                 provider: { position, count in data.subdata(in: Int(position)..<min(Int(position) + count, data.count)) })
        }
        return url
    }

    func testSpineOrderRetainsNonlinearEntriesAndManifestOrder() throws {
        let url = try fixture(opf(item("ten", "text/10.xhtml") + item("two", "text/02.xhtml") + item("one", "text/01.xhtml"),
                                  "<itemref idref='one'/><itemref idref='two' linear='no'/><itemref idref='ten'/>"),
                              files: [("OEBPS/text/10.xhtml", "<p>十</p>"), ("OEBPS/text/02.xhtml", "<p>二</p>"), ("OEBPS/text/01.xhtml", "<p>一</p>")])
        let publication = try EpubParser.parse(archive: url)
        XCTAssertEqual(publication.spine.map(\.fullZipPath), ["OEBPS/text/01.xhtml", "OEBPS/text/02.xhtml", "OEBPS/text/10.xhtml"])
        XCTAssertEqual(publication.spine.map(\.linear), [true, false, true])
        XCTAssertEqual(publication.manifest.map(\.id), ["ten", "two", "one"])
    }

    func testTextNovelClassificationAndMetadata() throws {
        let url = try fixture(opf(item("ch", "chapter.xhtml"), "<itemref idref='ch'/>",
                                  metadata: "<dc:title> 从零开始的异世界生活 </dc:title><dc:creator>长月达平</dc:creator><dc:description>正文</dc:description><dc:language>zh</dc:language>"),
                              files: [("OEBPS/chapter.xhtml", "<html><body><p>菜月昴突然被召唤到了异世界。</p></body></html>")])
        let publication = try EpubParser.parse(archive: url)
        XCTAssertTrue(publication.isReflowableText)
        XCTAssertFalse(publication.isPurePictureEpub)
        XCTAssertEqual(publication.title, "从零开始的异世界生活")
        XCTAssertEqual(publication.author, "长月达平")
        XCTAssertEqual(publication.description, "正文")
        XCTAssertEqual(publication.language, "zh")
    }

    private var textManifest: String { item("a", "a.xhtml") + item("b", "b.xhtml") + item("c", "c.xhtml") }
    private var textSpine: String { "<itemref idref='a'/><itemref idref='b'/><itemref idref='c'/>" }
    private var textFiles: [(String, String)] { [("OEBPS/a.xhtml", "<p>甲</p>"), ("OEBPS/b.xhtml", "<p>乙</p>"), ("OEBPS/c.xhtml", "<p>丙</p>")] }
    private func nav(_ links: String) -> String { "<html xmlns:epub='http://www.idpf.org/2007/ops'><nav epub:type='toc'><ol>\(links)</ol></nav></html>" }
    private func link(_ href: String, _ title: String) -> String { "<li><a href='\(href)'>\(title)</a></li>" }
    private var ncx: String { "<ncx><navMap><navPoint><navLabel><text>第一章：初始</text></navLabel><content src='a.xhtml'/></navPoint><navPoint><navLabel><text>第二章：重逢</text></navLabel><content src='c.xhtml#start'/></navPoint></navMap></ncx>" }

    func testNCXCreatesHalfOpenChapterRanges() throws {
        let url = try fixture(opf(textManifest + item("toc", "toc.ncx", "application/x-dtbncx+xml"), textSpine), files: textFiles + [("OEBPS/toc.ncx", ncx)])
        let publication = try EpubParser.parse(archive: url)
        XCTAssertEqual(publication.navItems.map(\.spineIndex), [0, 2])
        XCTAssertEqual(try publication.chapterRanges().map(\.title), ["第一章：初始", "第二章：重逢"])
        XCTAssertEqual(try publication.chapterRanges().map(\.startIndex), [0, 2])
        XCTAssertEqual(try publication.chapterRanges().map(\.endIndex), [2, 3])
        XCTAssertEqual(try JSONDecoder().decode(EpubPublication.self, from: JSONEncoder().encode(publication)), publication)
    }

    func testNavPreferredNestedFirstSpineMatchAndStableDeduplication() throws {
        let nested = "<li><a href='b.xhtml'>乙章</a><ol>\(link("c.xhtml", "丙章"))</ol></li>" + link("b.xhtml#again", "重复") + link("missing.xhtml", "未映射")
        let url = try fixture(opf(textManifest + item("nav", "nav.xhtml", "application/xhtml+xml", "nav") + item("toc", "toc.ncx", "application/x-dtbncx+xml"), textSpine + "<itemref idref='b'/>"), files: textFiles + [("OEBPS/nav.xhtml", nav(nested)), ("OEBPS/toc.ncx", ncx)])
        let publication = try EpubParser.parse(archive: url)
        XCTAssertEqual(publication.navItems.map(\.title), ["乙章", "重复", "未映射"])
        XCTAssertEqual(publication.navItems.map(\.spineIndex), [1, 1, -1])
        XCTAssertEqual(publication.navItems.first?.children.first?.spineIndex, 2)
        XCTAssertEqual(try publication.chapterRanges().map(\.title), ["封面与序言", "乙章", "丙章"])
        XCTAssertEqual(try publication.chapterRanges().map(\.endIndex), [1, 2, 4])
        XCTAssertEqual(try publication.chapterRanges(overrideTitle: "  单卷  ").map(\.title), ["单卷"])
    }

    func testPseudoPageNavigationCollapsesAndEmptyTitleDefaults() throws {
        for (title, links, expected) in [("书名", link("a.xhtml", "第001页") + link("b.xhtml", "Page #2") + link("c.xhtml", "结尾"), "书名"),
                                        ("", link("a.xhtml", "1") + link("c.xhtml", "p 3.xhtml"), "全本"), ("", "", "全 1 卷")] {
            let url = try fixture(opf(textManifest + item("nav", "nav.xhtml", "application/xhtml+xml", "nav"), textSpine, metadata: "<dc:title>\(title)</dc:title>"), files: textFiles + [("OEBPS/nav.xhtml", nav(links))])
            let publication = try EpubParser.parse(archive: url)
            XCTAssertEqual(try publication.chapterRanges().map(\.title), [expected])
            XCTAssertEqual(try publication.chapterRanges().map(\.endIndex), [3])
        }
    }

    func testImageWrappersSVGDirectImagesAndAndroidTextWithSingleImage() throws {
        let manifest = item("a", "a.xhtml") + item("b", "b.xhtml") + item("c", "3.png", "image/png") + item("one", "1.jpg", "image/jpeg") + item("two", "2.jpg", "image/jpeg")
        let files = [("OEBPS/a.xhtml", "<p>正文</p><img src='1.jpg'/><p>图后正文</p>"), ("OEBPS/b.xhtml", "<svg><image xlink:href='2.jpg'/></svg>"), ("OEBPS/1.jpg", "image1"), ("OEBPS/2.jpg", "image2"), ("OEBPS/3.png", "image3")]
        let publication = try EpubParser.parse(archive: fixture(opf(manifest, textSpine), files: files))
        XCTAssertEqual(publication.spine.map(\.resolvedImageEntry), ["OEBPS/1.jpg", "OEBPS/2.jpg", "OEBPS/3.png"])
        XCTAssertTrue(publication.isPurePictureEpub)
        XCTAssertFalse(publication.isReflowableText)
        XCTAssertEqual(publication.coverEntry, "OEBPS/1.jpg")
    }

    func testMultipleOrMissingImagesRemainTextAndMixedClassification() throws {
        let manifest = item("a", "a.xhtml") + item("b", "b.xhtml") + item("one", "1.jpg", "image/jpeg") + item("two", "2.jpg", "image/jpeg")
        let publication = try EpubParser.parse(archive: fixture(opf(manifest, "<itemref idref='a'/><itemref idref='b'/>"), files: [("OEBPS/a.xhtml", "<img src='1.jpg'/><img src='2.jpg'/>"), ("OEBPS/b.xhtml", "<img src='missing.jpg'/>"), ("OEBPS/1.jpg", "one"), ("OEBPS/2.jpg", "two")]))
        XCTAssertEqual(publication.spine.map(\.resolvedImageEntry), [nil, nil])
        XCTAssertFalse(publication.isPurePictureEpub)
        XCTAssertFalse(publication.isReflowableText)
    }

    func testCoverPriorityPropertiesMetadataWrapperFirstSpineAndFilename() throws {
        let files = textFiles + [("OEBPS/wrapper.xhtml", "<img src='meta.jpg'/>"), ("OEBPS/prop.jpg", "p"), ("OEBPS/meta.jpg", "m"), ("OEBPS/COVER.jpg", "c"), ("OEBPS/first.jpg", "f")]
        let variants: [(String, String, String, String)] = [
            (item("p", "prop.jpg", "image/jpeg", "cover-image") + item("m", "meta.jpg", "image/jpeg"), "<meta name='cover' content='m'/>", "a", "OEBPS/prop.jpg"),
            (item("m", "meta.jpg", "image/jpeg"), "<meta name='cover' content='m'/>", "a", "OEBPS/meta.jpg"),
            (item("m", "wrapper.xhtml"), "<meta name='cover' content='m'/>", "a", "OEBPS/meta.jpg"),
            (item("f", "first.jpg", "image/jpeg"), "", "f", "OEBPS/first.jpg"),
            (item("cover", "COVER.jpg", "image/jpeg"), "", "a", "OEBPS/COVER.jpg")]
        for (manifest, metadata, first, expected) in variants {
            let publication = try EpubParser.parse(archive: fixture(opf(textManifest + manifest, "<itemref idref='\(first)'/>", metadata: metadata), files: files))
            XCTAssertEqual(publication.coverEntry, expected)
        }
    }

    func testFixedLayoutMetadataAndManifestFlags() throws {
        for (properties, metadata) in [("", "<meta property='rendition:layout'> pre-paginated </meta>"), ("rendition:layout-pre-paginated", "")] {
            let publication = try EpubParser.parse(archive: fixture(opf(item("a", "a.xhtml", "application/xhtml+xml", properties), "<itemref idref='a'/>", metadata: metadata), files: textFiles))
            XCTAssertTrue(publication.isFixedLayout)
        }
    }

    func testFontObfuscationAndDRMAreDistinctAndDRMRefusesChapters() throws {
        for (algorithm, path, font) in [("http://www.idpf.org/2008/embedding", "font.bin", true), ("http://ns.adobe.com/pdf/enc/mono/", "font.bin", true), ("other", "font.woff2", true), ("aes128-cbc", "a.xhtml", false)] {
            let encryption = "<encryption><EncryptedData><EncryptionMethod Algorithm='\(algorithm)'/><CipherData><CipherReference URI='\(path)'/></CipherData></EncryptedData></encryption>"
            let publication = try EpubParser.parse(archive: fixture(opf(textManifest, textSpine), files: textFiles + [("META-INF/encryption.xml", encryption)]))
            XCTAssertEqual(publication.hasFontObfuscation, font)
            XCTAssertEqual(publication.hasDrm, !font)
            if font { XCTAssertNoThrow(try publication.chapterRanges()) }
            else { XCTAssertNotNil(publication.unsupportedReason); XCTAssertThrowsError(try publication.chapterRanges()) { XCTAssertTrue($0.localizedDescription.contains("DRM")) } }
        }
    }

    func testMissingStructureDuplicateIDsAndInvalidReferencesFailClearly() throws {
        let missing = try zip([("mimetype", Data("application/epub+zip".utf8))])
        XCTAssertThrowsError(try EpubParser.parse(archive: missing)) { XCTAssertTrue($0.localizedDescription.contains("container.xml")) }
        for (xml, reason) in [("<package><manifest>\(item("a", "a.xhtml"))</manifest></package>", "spine"), (opf(textManifest, ""), "spine"), (opf("", textSpine), "manifest"), (opf(item("a", "a.xhtml") + item("a", "b.xhtml"), textSpine), "重复"), (opf(textManifest, "<itemref idref='missing'/>"), "missing"), (opf(textManifest, "<itemref/>"), "idref"), (opf(item("", "a.xhtml"), textSpine), "id"), (opf(item("a", ""), textSpine), "href")] {
            let url = try fixture(xml)
            XCTAssertThrowsError(try EpubParser.parse(archive: url)) { XCTAssertTrue($0.localizedDescription.contains(reason), "\($0)") }
        }
    }

    func testContainerSelectionBOMAndJavaWhitespaceURLDecoding() throws {
        let path = "OEBPS/书 名+\u{00a0}.xhtml"
        let xml = opf(item(" a ", "书+名%2B%C2%A0.xhtml%23anchor"), "<itemref idref=' a '/>", metadata: "<dc:title> \u{00a0}书名\u{00a0} </dc:title>")
        let container = "<container><rootfile full-path='missing.opf'/><rootfile full-path='old.opf' media-type='application/oebps-package+xml'/><rootfile full-path='OEBPS/content.opf' media-type='APPLICATION/OEBPS-PACKAGE+XML'/><rootfile full-path='ignored.opf'/></container>"
        let url = try zip([("META-INF/container.xml", Data(container.utf8)), ("OEBPS/content.opf", Data([0xef, 0xbb, 0xbf]) + Data(xml.utf8)), (path, Data("<p>正文</p>".utf8))])
        let publication = try EpubParser.parse(archive: url)
        XCTAssertEqual(publication.opfPath, "OEBPS/content.opf")
        XCTAssertEqual(publication.title, "\u{00a0}书名\u{00a0}")
        XCTAssertEqual(publication.spine.first?.fullZipPath, path)
    }

    func testUnsafeResourceAndArchivePathsAreRejected() throws {
        for href in ["../../etc/passwd", "/absolute", "C:\\absolute", "%00bad", "https://host/book", "%zz"] {
            let url = try fixture(opf(item("a", href), "<itemref idref='a'/>"))
            XCTAssertThrowsError(try EpubParser.parse(archive: url), href)
        }
        for path in ["../escape", "/absolute", "C:\\absolute", "OEBPS/../OEBPS/content.opf"] {
            let url = try fixture(opf(textManifest, textSpine), files: [(path, "bad")])
            XCTAssertThrowsError(try EpubParser.parse(archive: url), path)
        }
        let url = try fixture(opf(textManifest, textSpine), files: [("OEBPS/a.xhtml", "<img src='../../escape.jpg'/>")])
        XCTAssertThrowsError(try EpubParser.parse(archive: url))
    }

    func testMalformedNavFallsBackToNCXButMalformedEncryptionFails() throws {
        for badNav in ["<html><nav>", "<html/>"] {
            let url = try fixture(opf(textManifest + item("nav", "nav.xhtml", "application/xhtml+xml", "nav") + item("toc", "toc.ncx", "application/x-dtbncx+xml"), textSpine), files: textFiles + [("OEBPS/nav.xhtml", badNav), ("OEBPS/toc.ncx", ncx)])
            XCTAssertEqual(try EpubParser.parse(archive: url).navItems.map(\.spineIndex), [0, 2])
        }
        let url = try fixture(opf(textManifest, textSpine), files: textFiles + [("META-INF/encryption.xml", "<encryption><EncryptedData>")])
        XCTAssertThrowsError(try EpubParser.parse(archive: url)) { XCTAssertTrue($0.localizedDescription.contains("encryption.xml")) }
    }

    func testUnsafeXMLRejectedAcrossUTF8UTF16UTF32AndOptionalNav() throws {
        let malicious = "<!DOCTYPE package [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]>" + opf(textManifest, textSpine, metadata: "<dc:title>&xxe;</dc:title>")
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            let url = try zip([("META-INF/container.xml", Data(container.utf8)), ("OEBPS/content.opf", try XCTUnwrap(malicious.data(using: encoding)))])
            XCTAssertThrowsError(try EpubParser.parse(archive: url)) { XCTAssertEqual($0 as? EpubError, .unsafeXML) }
        }
        let url = try fixture(opf(textManifest + item("nav", "nav.xhtml", "application/xhtml+xml", "nav") + item("toc", "toc.ncx", "application/x-dtbncx+xml"), textSpine), files: textFiles + [("OEBPS/nav.xhtml", malicious), ("OEBPS/toc.ncx", ncx)])
        XCTAssertThrowsError(try EpubParser.parse(archive: url)) { XCTAssertEqual($0 as? EpubError, .unsafeXML) }
    }

    func testXMLReadDepthAndNodeLimits() throws {
        let inputs = [String(repeating: " ", count: 8 * 1024 * 1024 + 1), String(repeating: "<n>", count: 129) + String(repeating: "</n>", count: 129), "<r>" + String(repeating: "<n/>", count: 100_000) + "</r>"]
        for xml in inputs {
            let url = try fixture(xml)
            XCTAssertThrowsError(try EpubParser.parse(archive: url)) { guard case .limitExceeded = $0 as? EpubError else { return XCTFail("\($0)") } }
        }
    }

    func testDeflatedEPUBAndCorruptWrapperCRC() throws {
        let publication = try EpubParser.parse(archive: fixture(opf(textManifest, textSpine), files: textFiles, compression: .deflate))
        XCTAssertTrue(publication.isReflowableText)
        let url = try fixture(opf(textManifest, textSpine), files: [("OEBPS/a.xhtml", "<p>UNIQUE_PAYLOAD</p>")])
        var data = try Data(contentsOf: url)
        let range = try XCTUnwrap(data.range(of: Data("UNIQUE_PAYLOAD".utf8)))
        data[range.lowerBound] ^= 1
        try data.write(to: url)
        XCTAssertThrowsError(try EpubParser.parse(archive: url)) { XCTAssertTrue($0.localizedDescription.contains("ZIP")) }
    }

    func testCancelledParsePropagatesCancellation() async throws {
        let url = try fixture(opf(textManifest, textSpine), files: textFiles)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try EpubParser.parse(archive: url)
        }
        do { _ = try await task.value; XCTFail("取消不能作为成功或空书返回") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testWrapperPrefixKeepsAndroidInspectionButChecksCRCAfterPrefix() throws {
        let html = "<img src='one.jpg'/>" + String(repeating: " ", count: 1024 * 1024) + "<img src='two.jpg'/>TAIL_CHECKSUM"
        let url = try fixture(opf(item("a", "a.xhtml"), "<itemref idref='a'/>"), files: [("OEBPS/a.xhtml", html), ("OEBPS/one.jpg", "1"), ("OEBPS/two.jpg", "2")])
        XCTAssertEqual(try EpubParser.parse(archive: url).spine.first?.resolvedImageEntry, "OEBPS/one.jpg")
        var data = try Data(contentsOf: url)
        let tail = try XCTUnwrap(data.range(of: Data("TAIL_CHECKSUM".utf8)))
        data[tail.lowerBound] ^= 1
        try data.write(to: url)
        XCTAssertThrowsError(try EpubParser.parse(archive: url)) { XCTAssertTrue($0.localizedDescription.contains("CRC")) }
    }

    func testRepeatedPrefixReadsCountFullInflatedBytesAgainstBudget() throws {
        let url = try zip([("resource", Data(repeating: 0x61, count: 8 * 1024 * 1024))], compression: .deflate)
        let archive = try EpubArchive(url: url)
        for _ in 0..<32 { XCTAssertEqual(try archive.read("resource", maximumBytes: 1, prefixOnly: true), Data([0x61])) }
        XCTAssertThrowsError(try archive.read("resource", maximumBytes: 1, prefixOnly: true)) {
            guard case .limitExceeded = $0 as? EpubError else { return XCTFail("\($0)") }
        }
    }

    func testOversizedNavigationDoesNotFallBackAndRootfileCannotEscape() throws {
        let url = try fixture(opf(textManifest + item("nav", "nav.xhtml", "application/xhtml+xml", "nav") + item("toc", "toc.ncx", "application/x-dtbncx+xml"), textSpine), files: textFiles + [("OEBPS/nav.xhtml", String(repeating: " ", count: 8 * 1024 * 1024 + 1)), ("OEBPS/toc.ncx", ncx)])
        XCTAssertThrowsError(try EpubParser.parse(archive: url)) { guard case .limitExceeded = $0 as? EpubError else { return XCTFail("\($0)") } }
        for container in ["<container><rootfile full-path='../outside.opf'/></container>", "<container><rootfile full-path=' '/></container>", "<container/>"] {
            let url = try fixture(opf(textManifest, textSpine), container: container)
            XCTAssertThrowsError(try EpubParser.parse(archive: url)) { XCTAssertTrue($0.localizedDescription.contains("越界") || $0.localizedDescription.contains("rootfile")) }
        }
    }

    func testArchiveSymlinkAndNulNamesAreRejected() throws {
        let url = try fixture(opf(textManifest, textSpine))
        do {
            let archive = try Archive(url: url, accessMode: .update)
            let target = Data("/etc/passwd".utf8)
            try archive.addEntry(with: "link", type: .symlink, uncompressedSize: Int64(target.count), provider: { position, count in target.subdata(in: Int(position)..<min(Int(position) + count, target.count)) })
        }
        XCTAssertThrowsError(try EpubParser.parse(archive: url)) { XCTAssertTrue($0.localizedDescription.contains("符号链接")) }
        let nul = try zip([("bad\0name", Data())])
        XCTAssertThrowsError(try EpubParser.parse(archive: nul))
    }

    func testGlobalGB18030FallbackRetainsFlaggedUTF8Entries() throws {
        let xml = opf(item("a", "你.xhtml") + item("b", "漏.xhtml") + item("c", "书.xhtml"), textSpine)
        let url = try fixture(xml, files: [("OEBPS/zz.xhtml", "<p>一</p>"), ("OEBPS/©.xhtml", "<p>二</p>"), ("OEBPS/书.xhtml", "<p>三</p>")])
        var bytes = try Data(contentsOf: url)
        // Mutate only fixture filename bytes and their UTF-8 flags in the two ZIP headers.
        // C4 E3 = 你; C2 A9 is valid UTF-8 © but GB18030 漏, proving global fallback.
        for (old, new) in [(Data("OEBPS/zz.xhtml".utf8), Data("OEBPS/".utf8) + Data([0xc4, 0xe3]) + Data(".xhtml".utf8)), (Data("OEBPS/©.xhtml".utf8), Data("OEBPS/©.xhtml".utf8))] {
            var offset = 0
            while let range = bytes.range(of: old, in: offset..<bytes.count) {
                let local = range.lowerBound >= 30 && bytes.subdata(in: range.lowerBound - 30..<range.lowerBound - 26) == Data([0x50, 0x4b, 3, 4])
                let flag = range.lowerBound - (local ? 24 : 38)
                bytes[flag + 1] &= 0xf7
                bytes.replaceSubrange(range, with: new)
                offset = range.upperBound
            }
        }
        try bytes.write(to: url)
        let publication = try EpubParser.parse(archive: url)
        XCTAssertEqual(publication.spine.map(\.fullZipPath), ["OEBPS/你.xhtml", "OEBPS/漏.xhtml", "OEBPS/书.xhtml"])
        let archive = try EpubArchive(url: url)
        XCTAssertEqual(String(decoding: try archive.read("OEBPS/你.xhtml"), as: UTF8.self), "<p>一</p>")
        XCTAssertEqual(String(decoding: try archive.read("OEBPS/漏.xhtml"), as: UTF8.self), "<p>二</p>")
        XCTAssertEqual(String(decoding: try archive.read("OEBPS/书.xhtml"), as: UTF8.self), "<p>三</p>")
    }

    func testDublinCoreMetadataTakesPriorityAndPseudoPageWhitespaceMatchesJava() throws {
        let metadata = "<other:title xmlns:other='urn:other'>错误标题</other:title><dc:title>正确标题</dc:title>"
        let url = try fixture(opf(textManifest + item("nav", "nav.xhtml", "application/xhtml+xml", "nav"), textSpine, metadata: metadata),
                              files: textFiles + [("OEBPS/nav.xhtml", nav(link("a.xhtml", "Page\u{00a0}1") + link("c.xhtml", "Page\u{00a0}2")))])
        let publication = try EpubParser.parse(archive: url)
        XCTAssertEqual(publication.title, "正确标题")
        XCTAssertEqual(try publication.chapterRanges().map(\.title), ["Page\u{00a0}1", "Page\u{00a0}2"])
    }

    func testMalformedWrapperMatchingHasTotalBudget() throws {
        // Keep RED inputs small: the old quadratic matcher must not receive a full 1 MiB.
        for tag in ["<img ", "<image "] {
            let url = try fixture(opf(item("a", "a.xhtml"), "<itemref idref='a'/>"),
                                  files: [("OEBPS/a.xhtml", String(repeating: tag, count: 6144))])
            XCTAssertThrowsError(try EpubParser.parse(archive: url)) {
                guard case .limitExceeded = $0 as? EpubError else { return XCTFail("\($0)") }
            }
        }
    }

    func testMalformedWrapperMatchingRespondsToRunningCancellation() async throws {
        for tag in ["<img ", "<image "] {
            let url = try fixture(opf(item("a", "a.xhtml"), "<itemref idref='a'/>"),
                                  files: [("OEBPS/a.xhtml", String(repeating: tag, count: 6144))])
            let started = expectation(description: "解析任务已启动")
            let task = Task.detached {
                started.fulfill()
                return try EpubParser.parse(archive: url)
            }
            await fulfillment(of: [started], timeout: 2)
            // This small stored ZIP reaches matching well before cancellation; no pre-cancel shortcut.
            try await Task.sleep(nanoseconds: 50_000_000)
            let cancelledAt = ContinuousClock.now
            task.cancel()
            do { _ = try await task.value; XCTFail("运行中取消不能返回成功") }
            catch { XCTAssertTrue(error is CancellationError, "\(error)") }
            XCTAssertLessThan(cancelledAt.duration(to: .now), .milliseconds(250), "\(tag) 匹配期间必须响应取消")
        }
    }
}
