import Foundation
import XCTest
import ZIPFoundation
@testable import ComicCore

final class LocalEpubLibraryTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func fixture(text: Bool = false, extra: [(String, Data)] = [], payloads: [String: Data] = [:],
                         compression: CompressionMethod = .deflate, opfTransform: (String) -> String = { $0 }) throws -> URL {
        let folder = try temporaryDirectory(), url = folder.appendingPathComponent("book.epub")
        let media = text ? "application/xhtml+xml" : "image/jpeg"
        let opf = "<package xmlns:dc='http://purl.org/dc/elements/1.1/'><metadata><dc:title>内置标题</dc:title><dc:creator>作者</dc:creator><dc:description>简介</dc:description></metadata><manifest><item id='b' href='b' media-type='\(media)'/><item id='a' href='a' media-type='\(media)'/><item id='nav' href='nav' media-type='application/xhtml+xml' properties='nav'/></manifest><spine><itemref idref='a'/><itemref idref='b'/><itemref idref='a'/></spine></package>"
        let files: [(String, Data)] = [
            ("META-INF/container.xml", Data("<container><rootfile full-path='OPS/content.opf'/></container>".utf8)),
            ("OPS/content.opf", Data(opfTransform(opf).utf8)),
            ("OPS/a", Data((text ? "<p>正文甲</p>" : "IMAGE_A").utf8)),
            ("OPS/b", Data((text ? "<p>正文乙</p>" : "IMAGE_B").utf8)),
            ("OPS/nav", Data("<html><nav><ol><li><a href='a'>第一章</a></li><li><a href='b'>第二章</a></li></ol></nav></html>".utf8))
        ] + extra
        let archive = try Archive(url: url, accessMode: .create)
        for (path, original) in files {
            let data = payloads[path] ?? original
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: compression,
                                 provider: { position, count in data.subdata(in: Int(position)..<min(Int(position) + count, data.count)) })
        }
        return url
    }

    func testReopenedEpubUsesLogicalPageURLsAndSavedCover() throws {
        let source = try fixture(), library = try LocalLibrary(directory: temporaryDirectory())
        let id = UUID().uuidString, folder = library.directory.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent("content.epub"))
        try Data("IMAGE_A".utf8).write(to: folder.appendingPathComponent("cover.bin"))
        let publication = try EpubParser.parse(archive: source)
        let metadata = try JSONSerialization.jsonObject(with: JSONEncoder().encode(publication))
        let manifest: [String: Any] = ["id": id, "title": "文件名标题", "createdAt": 1, "pages": ["spine-0", "spine-1", "spine-2"],
            "epub": metadata, "coverName": "cover.bin", "chapters": [
                ["id": id + "_ch_0", "title": "第一章", "pages": ["spine-0"]],
                ["id": id + "_ch_1", "title": "第二章", "pages": ["spine-1", "spine-2"]]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("book.json"))
        let book = try library.book(id: id)
        XCTAssertEqual(try library.pageURLs(for: book).map(\.absoluteString), (0..<3).map { "xxcomic-epub://page/\(id)/\($0)" })
        XCTAssertEqual(try library.summary(for: book).coverUrl, folder.appendingPathComponent("cover.bin").absoluteString)
    }

    func testImportPreservesArchiveSpineChaptersAndLoadsActualBytes() async throws {
        let input = try fixture(), original = try Data(contentsOf: input)
        let library = try LocalLibrary(directory: temporaryDirectory())
        var probes: [Data] = []
        let book = try library.importEpub(title: "文件名标题", archive: input) { url in
            probes.append(try Data(contentsOf: url)); return true
        }
        let reopened = try LocalLibrary(directory: library.directory)
        XCTAssertEqual(try reopened.book(id: book.id), book)
        XCTAssertEqual(book.pages, ["spine-0", "spine-1", "spine-2"])
        XCTAssertEqual(book.chapters?.map(\.pages), [["spine-0"], ["spine-1", "spine-2"]])
        XCTAssertEqual(probes, [Data("IMAGE_A".utf8), Data("IMAGE_B".utf8)])
        XCTAssertEqual(try Data(contentsOf: input), original)
        let folder = library.directory.appendingPathComponent(book.id)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("content.epub")), original)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["content.epub", "book.json", "cover.bin"])
        let urls = try reopened.pageURLs(for: book)
        XCTAssertEqual(try urls.map { try reopened.epubImageData(pageURL: $0) }, [Data("IMAGE_A".utf8), Data("IMAGE_B".utf8), Data("IMAGE_A".utf8)])
        XCTAssertEqual(try reopened.epubResource(bookID: book.id, path: "OPS/b", maximumBytes: 7), Data("IMAGE_B".utf8))
        XCTAssertThrowsError(try reopened.epubResource(bookID: book.id, path: "OPS/b", maximumBytes: 6))
        let source = LocalComicSource(library: reopened)
        let detail = try await source.detail(comicId: book.id)
        XCTAssertEqual(detail.author, "作者"); XCTAssertEqual(detail.description, "简介"); XCTAssertEqual(detail.status, "EPUB")
        let chapters = try await source.chapters(comicId: book.id)
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        let second = try await source.chapter(url: chapters[1].url)
        XCTAssertEqual(second.imageUrls, Array(urls.dropFirst()).map(\.absoluteString))
    }

    func testTextImportIsRejectedAndLegacyBookRefusesImageReaderWithoutDeletingFiles() async throws {
        let library = try LocalLibrary(directory: temporaryDirectory()), input = try fixture(text: true)
        let original = try Data(contentsOf: input)
        XCTAssertThrowsError(try library.importEpub(title: "小说", archive: input) { _ in XCTFail("文字不应进入图片探测"); return true }) {
            XCTAssertEqual($0 as? LocalLibraryError, .unsupportedTextContent)
        }
        XCTAssertTrue(try library.books().isEmpty)
        XCTAssertEqual(try Data(contentsOf: input), original)
        let book = try LegacyEpubFixture.persist(library: library, archive: input, title: "旧小说")
        let folder = library.directory.appendingPathComponent(book.id), metadata = try Data(contentsOf: folder.appendingPathComponent("book.json"))
        let source = LocalComicSource(library: library), chapters = try await source.chapters(comicId: book.id)
        do { _ = try await source.chapter(url: chapters[0].url); XCTFail("旧文字记录不能进入漫画阅读") }
        catch { XCTAssertEqual(error as? LocalLibraryError, .unsupportedTextContent) }
        XCTAssertEqual(try library.book(id: book.id), book)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("content.epub")), original)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("book.json")), metadata)
    }

    func testLegacyJSONAndMixedLibraryRemainReadable() throws {
        let library = try LocalLibrary(directory: temporaryDirectory())
        let id = UUID().uuidString, folder = library.directory.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data([42]).write(to: folder.appendingPathComponent("0.jpg"))
        try Data("{\"id\":\"\(id)\",\"title\":\"旧书\",\"createdAt\":1,\"pages\":[\"0.jpg\"]}".utf8).write(to: folder.appendingPathComponent("book.json"))
        let old = try library.book(id: id)
        XCTAssertNil(old.epub); XCTAssertNil(old.coverName)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(library.pageURLs(for: old).first)), Data([42]))
        let epub = try library.importEpub(title: "新书", archive: fixture()) { _ in true }
        XCTAssertEqual(try library.books().map(\.id), [epub.id, old.id])
    }

    func testUnsafePageURLsAndResourcePathsAreRejected() throws {
        let library = try LocalLibrary(directory: temporaryDirectory())
        let book = try library.importEpub(title: "安全", archive: fixture()) { _ in true }
        for string in ["xxcomic-epub://page/invalid/0", "xxcomic-epub://page/\(book.id)/3", "xxcomic-epub://page/\(book.id)/-1",
                       "xxcomic-epub://page/\(book.id)/0?q=1", "xxcomic-epub://page/\(book.id)/0#x", "xxcomic-epub://user@page/\(book.id)/0",
                       "xxcomic-epub://page:1/\(book.id)/0", "xxcomic-epub://page/\(book.id)/%30", "xxcomic-epub://page/\(book.id)/0/",
                       "xxcomic-epub://PAGE/\(book.id)/0", "xxcomic-epub://%70age/\(book.id)/0", "XXCOMIC-EPUB://page/\(book.id)/0", "file://page/\(book.id)/0",
                       "xxcomic-epub://page/\(book.id)/999999999999999999999999999", "xxcomic-epub://page/\(book.id)/+0"] {
            XCTAssertThrowsError(try library.epubImageData(pageURL: XCTUnwrap(URL(string: string))), string)
        }
        for path in ["../OPS/a", "/OPS/a", "OPS/../OPS/a", "OPS//a", "OPS\\a", "OPS/missing"] {
            XCTAssertThrowsError(try library.epubResource(bookID: book.id, path: path, maximumBytes: 100), path)
        }
        XCTAssertThrowsError(try library.epubResource(bookID: book.id, path: "OPS/a", maximumBytes: -1))
    }

    func testResourcePreviouslyReadAsTextStillRequiresImageProbe() throws {
        let library = try LocalLibrary(directory: temporaryDirectory())
        let input = try fixture(text: true, opfTransform: {
            $0.replacingOccurrences(of: "</manifest>", with: "<item id='image-alias' href='a' media-type='image/jpeg'/></manifest>")
                .replacingOccurrences(of: "</spine>", with: "<itemref idref='image-alias'/></spine>")
        })
        XCTAssertThrowsError(try library.importEpub(title: "类型复用", archive: input) { _ in false })
        XCTAssertTrue(try library.books().isEmpty)
    }

    func testBadImagesDRMAndMissingResourcesNeverPublishOrAlterExistingBooks() throws {
        let library = try LocalLibrary(directory: temporaryDirectory()), input = try fixture()
        let old = try library.importEpub(title: "保留", archive: input) { _ in true }
        let bytes = try Data(contentsOf: input)
        XCTAssertThrowsError(try library.importEpub(title: "坏图", archive: input) { try Data(contentsOf: $0) != Data("IMAGE_B".utf8) })
        let drm = try fixture(extra: [("META-INF/encryption.xml", Data("<encryption><EncryptedData><EncryptionMethod Algorithm='DRM'/><CipherReference URI='OPS/a'/></EncryptedData></encryption>".utf8))])
        XCTAssertThrowsError(try library.importEpub(title: "DRM", archive: drm) { _ in true })
        let missing = try fixture()
        do {
            let archive = try Archive(url: missing, accessMode: .update)
            try archive.remove(XCTUnwrap(archive["OPS/b"]))
        }
        XCTAssertThrowsError(try library.importEpub(title: "缺资源", archive: missing) { _ in true })
        XCTAssertEqual(try library.books(), [old])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [old.id])
        XCTAssertEqual(try Data(contentsOf: input), bytes)
    }

    func testCancellationDuringCopyAndProbeCleansOnlyStaging() async throws {
        for cancelInCopy in [true, false] {
            let input = try fixture(), original = try Data(contentsOf: input), directory = try temporaryDirectory()
            let library = try LocalLibrary(directory: directory, readChunk: { handle, count in
                let data = try handle.read(upToCount: count)
                if cancelInCopy { withUnsafeCurrentTask { $0?.cancel() } }
                return data
            })
            let task = Task.detached {
                try library.importEpub(title: "取消", archive: input) { _ in
                    withUnsafeCurrentTask { $0?.cancel() }; return true
                }
            }
            do { _ = try await task.value; XCTFail("取消不得发布") }
            catch { XCTAssertTrue(error is CancellationError, "\(error)") }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }

    private func mutateManifest(_ book: LocalBook, _ library: LocalLibrary, mutation: (inout [String: Any]) -> Void) throws {
        let url = library.directory.appendingPathComponent(book.id).appendingPathComponent("book.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        mutation(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    func testCorruptMetadataAndOwnedFileSymlinksAreRejected() throws {
        let library = try LocalLibrary(directory: temporaryDirectory())
        let input = try fixture()
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["pages"] = ["spine-0"] }, { $0["coverName"] = "../cover.bin" },
            { $0["chapters"] = [] },
            { json in var epub = json["epub"] as! [String: Any]; epub["opfPath"] = "../outside"; json["epub"] = epub },
            { json in var epub = json["epub"] as! [String: Any]; epub["hasDrm"] = true; json["epub"] = epub }
        ]
        for mutation in mutations {
            let book = try library.importEpub(title: "损坏", archive: input) { _ in true }
            try mutateManifest(book, library, mutation: mutation)
            XCTAssertThrowsError(try library.book(id: book.id))
            XCTAssertThrowsError(try library.books())
            try JSONEncoder().encode(book).write(to: library.directory.appendingPathComponent(book.id).appendingPathComponent("book.json"))
        }
        for name in ["content.epub", "cover.bin", "book.json"] {
            let book = try library.importEpub(title: "链接", archive: input) { _ in true }
            let target = library.directory.appendingPathComponent(book.id).appendingPathComponent(name)
            let outside = try temporaryDirectory().appendingPathComponent(name)
            try FileManager.default.moveItem(at: target, to: outside)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
            XCTAssertThrowsError(try library.book(id: book.id), name)
            XCTAssertThrowsError(try library.epubResource(bookID: book.id, path: "OPS/a", maximumBytes: 100), name)
        }
        let book = try library.importEpub(title: "目录链接", archive: input) { _ in true }
        let folder = library.directory.appendingPathComponent(book.id), outside = try temporaryDirectory().appendingPathComponent("book")
        try FileManager.default.moveItem(at: folder, to: outside)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
        XCTAssertThrowsError(try library.book(id: book.id))
    }

    func testCoverPriorityAndUnreadableOptionalCoverFallback() throws {
        for readableCover in [true, false] {
            let library = try LocalLibrary(directory: temporaryDirectory())
            let input = try fixture(extra: [("OPS/cover", Data("COVER".utf8))], opfTransform: {
                $0.replacingOccurrences(of: "</manifest>", with: "<item id='cover' href='cover' media-type='image/jpeg' properties='cover-image'/></manifest>")
            })
            let book = try library.importEpub(title: "封面", archive: input) {
                try Data(contentsOf: $0) != Data("COVER".utf8) || readableCover
            }
            let cover = try XCTUnwrap(URL(string: library.summary(for: book).coverUrl))
            XCTAssertEqual(try Data(contentsOf: cover), Data((readableCover ? "COVER" : "IMAGE_A").utf8))
        }
        for readableCover in [true, false] {
            let library = try LocalLibrary(directory: temporaryDirectory())
            let input = try fixture(text: true, extra: [("OPS/front", Data("FRONT".utf8))], opfTransform: {
                $0.replacingOccurrences(of: "</manifest>", with: "<item id='front' href='front' media-type='image/jpeg'/></manifest>")
            })
            XCTAssertThrowsError(try library.importEpub(title: "文字封面", archive: input) { _ in readableCover }) {
                XCTAssertEqual($0 as? LocalLibraryError, .unsupportedTextContent)
            }
            XCTAssertTrue(try library.books().isEmpty)
        }
    }

    func testImportImageValidationCanExceedParserDefaultBudget() throws {
        let library = try LocalLibrary(directory: temporaryDirectory())
        let large = Data(repeating: 0x41, count: 90 * 1024 * 1024)
        let input = try fixture(extra: [("OPS/c", large)], payloads: ["OPS/a": large, "OPS/b": large], opfTransform: {
            $0.replacingOccurrences(of: "</manifest>", with: "<item id='c' href='c' media-type='image/jpeg'/></manifest>")
                .replacingOccurrences(of: "</spine>", with: "<itemref idref='c'/></spine>")
        })
        let book = try library.importEpub(title: "270 MiB", archive: input) {
            try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize == 90 * 1024 * 1024
        }
        XCTAssertEqual(book.pages, ["spine-0", "spine-1", "spine-2", "spine-3"])
        XCTAssertEqual(try library.books(), [book])
    }

    func testOriginalArchiveCopyCanExceedSingleImageLimit() throws {
        let library = try LocalLibrary(directory: temporaryDirectory())
        let padding = Data(repeating: 0, count: 65 * 1024 * 1024)
        let input = try fixture(extra: [("padding1", padding), ("padding2", padding)], compression: .none)
        let size = try XCTUnwrap(input.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertGreaterThan(size, LocalLibrary.maximumImageBytes)
        let book = try library.importEpub(title: "大原包", archive: input) { _ in true }
        let copy = library.directory.appendingPathComponent(book.id).appendingPathComponent("content.epub")
        XCTAssertEqual(try copy.resourceValues(forKeys: [.fileSizeKey]).fileSize, size)
    }

    func testStreamingWriteAndReadShareBudgetAndRemovePartialOutput() throws {
        let input = try fixture(), output = try temporaryDirectory().appendingPathComponent("probe")
        let archive = try EpubArchive(url: input, maximumReadBytes: 14)
        try archive.write("OPS/a", to: output)
        XCTAssertEqual(try Data(contentsOf: output), Data("IMAGE_A".utf8))
        XCTAssertEqual(try archive.read("OPS/b", maximumBytes: 7), Data("IMAGE_B".utf8))
        XCTAssertThrowsError(try archive.write("OPS/a", to: output)) {
            guard case .limitExceeded = $0 as? EpubError else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCRCFailureAndCancellationNeverReturnPartialResource() async throws {
        let library = try LocalLibrary(directory: temporaryDirectory()), input = try fixture(compression: .none)
        let book = try library.importEpub(title: "CRC", archive: input) { _ in true }
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try library.epubResource(bookID: book.id, path: "OPS/a", maximumBytes: 100)
        }
        do { _ = try await task.value; XCTFail("取消不能返回资源") }
        catch { XCTAssertTrue(error is CancellationError) }
        let content = library.directory.appendingPathComponent(book.id).appendingPathComponent("content.epub")
        var bytes = try Data(contentsOf: content)
        let marker = try XCTUnwrap(bytes.range(of: Data("IMAGE_A".utf8)))
        bytes[marker.lowerBound] ^= 1
        try bytes.write(to: content)
        XCTAssertThrowsError(try library.epubResource(bookID: book.id, path: "OPS/a", maximumBytes: 100)) {
            guard case .invalid(let message) = $0 as? EpubError else { return XCTFail("\($0)") }
            XCTAssertTrue(message.contains("CRC"))
        }
        let badInput = try temporaryDirectory().appendingPathComponent("corrupt.epub")
        try bytes.write(to: badInput)
        XCTAssertThrowsError(try library.importEpub(title: "损坏", archive: badInput) { _ in true })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
        XCTAssertEqual(try Data(contentsOf: badInput), bytes)
    }

    private func manifestFixture(count: Int) throws -> URL {
        let items = (0..<count).map { "<item id='image-\($0)' href='a' media-type='image/jpeg'/>" }.joined()
        let input = try fixture(opfTransform: { _ in
            "<package><metadata/><manifest>\(items)</manifest><spine><itemref idref='image-0'/></spine></package>"
        })
        let archive = try Archive(url: input, accessMode: .update)
        // Three physical ZIP entries, independent of the number of OPF manifest items.
        try archive.remove(XCTUnwrap(archive["OPS/b"]))
        try archive.remove(XCTUnwrap(archive["OPS/nav"]))
        return input
    }

    func testOversizedManifestIsRejectedBeforePublishingAndPreservesShelf() throws {
        let library = try LocalLibrary(directory: temporaryDirectory())
        let existing = try library.importEpub(title: "原书", archive: fixture()) { _ in true }
        let input = try manifestFixture(count: 50_001), original = try Data(contentsOf: input)
        XCTAssertThrowsError(try library.importEpub(title: "过多条目", archive: input) { _ in true })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [existing.id])
        XCTAssertEqual(try library.books(), [existing])
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testManifestAtLimitImportsAndReopens() throws {
        let library = try LocalLibrary(directory: temporaryDirectory())
        let input = try manifestFixture(count: 50_000), original = try Data(contentsOf: input)
        let book = try library.importEpub(title: "边界条目", archive: input) { _ in true }
        let reopened = try LocalLibrary(directory: library.directory)
        XCTAssertEqual(book.epub?.manifest.count, 50_000)
        XCTAssertEqual(book.pages, ["spine-0"])
        XCTAssertEqual(try reopened.book(id: book.id), book)
        XCTAssertEqual(try reopened.books(), [book])
        XCTAssertEqual(try reopened.epubImageData(pageURL: XCTUnwrap(reopened.pageURLs(for: book).first)), Data("IMAGE_A".utf8))
        XCTAssertEqual(try Data(contentsOf: input), original)
    }
}
