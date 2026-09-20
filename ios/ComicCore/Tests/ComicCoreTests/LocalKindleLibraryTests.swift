import Foundation
import XCTest
@testable import ComicCore

final class LocalKindleLibraryTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=")!

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    // Real uncompressed MOBI7 records, also used to test byte-based DRM/KF8 rejection.
    private func mobi(body: String = "<h1>第一章</h1><p>小说正文甲</p><mbp:pagebreak/><h1>第二章</h1><p>小说正文乙</p>",
                      images: [Data] = [], version: UInt32 = 6, drm: UInt8 = 0) -> Data {
        func put(_ data: inout Data, _ offset: Int, _ value: UInt32) {
            data.replaceSubrange(offset..<offset + 4, with: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
        }
        let text = Data(body.utf8)
        var header = Data(repeating: 0, count: 256)
        header[1] = 1; header[9] = 1; header[13] = drm
        put(&header, 4, UInt32(text.count))
        header.replaceSubrange(16..<20, with: Data("MOBI".utf8))
        put(&header, 20, 232); put(&header, 24, 2); put(&header, 28, 65001); put(&header, 36, version)
        put(&header, 108, images.isEmpty ? .max : 2); put(&header, 168, .max); put(&header, 172, .max)
        let records = [header, text] + images
        var data = Data(repeating: 0, count: 78 + records.count * 8)
        data.replaceSubrange(0..<4, with: Data("Book".utf8)); data.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        data[77] = UInt8(records.count)
        var offset = data.count
        for (index, record) in records.enumerated() { put(&data, 78 + index * 8, UInt32(offset)); offset += record.count }
        for record in records { data += record }
        return data
    }

    private func input(_ data: Data) throws -> URL {
        let url = try directory().appendingPathComponent("input.mobi")
        try data.write(to: url)
        return url
    }

    func testPersistedKindleCanReopenAndReadWhenOnlyDerivedArchiveIsMissing() throws {
        let source = try input(mobi()), root = try directory()
        let derived = root.appendingPathComponent("derived.epub")
        _ = try KindlePublicationAdapter.convert(source: source, to: derived)
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let book = try library.importEpub(title: "小说", archive: derived) { _ in true }
        let folder = library.directory.appendingPathComponent(book.id), manifest = folder.appendingPathComponent("book.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        json["kindleFormat"] = "mobi"
        try JSONSerialization.data(withJSONObject: json).write(to: manifest)
        try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent("source.kindle"))
        let path = try XCTUnwrap(book.epub?.spine.first?.fullZipPath)
        let before = try library.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("content.epub"))
        let reopened = try LocalLibrary(directory: library.directory)
        XCTAssertEqual(try reopened.book(id: book.id).epub, book.epub)
        XCTAssertEqual(try reopened.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024), before)
    }

    func testImportPreservesOwnedOriginalMetadataAndTextHistoryAcrossRecovery() async throws {
        let bytes = mobi(), source = try input(bytes), library = try LocalLibrary(directory: directory())
        let book = try library.importKindle(title: " 小说 ", source: source, format: .mobi) { _ in true }
        XCTAssertEqual(book.kindleFormat, .mobi); XCTAssertEqual(book.title, "小说"); XCTAssertNil(book.pdf)
        let folder = library.directory.appendingPathComponent(book.id)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["source.kindle", "content.epub", "book.json"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("source.kindle")), bytes)
        try FileManager.default.removeItem(at: source)
        let reopened = try LocalLibrary(directory: library.directory), local = LocalComicSource(library: reopened)
        XCTAssertEqual(try reopened.book(id: book.id), book)
        let chapters = try await local.chapters(comicId: book.id)
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        let detail = try await local.detail(comicId: book.id)
        XCTAssertEqual(detail.status, "MOBI")
        let path = try XCTUnwrap(book.epub?.spine[1].fullZipPath)
        let before = try reopened.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024)
        XCTAssertTrue(String(decoding: before, as: UTF8.self).contains("小说正文乙"))
        let historyDirectory = try directory(), history = try LibraryStore(directory: historyDirectory)
        let summary = try reopened.summary(for: book)
        let position = TextLocator(bookID: book.id, chapterIndex: 1, spineIndex: 1, resourceHref: path, anchorID: "p1", scrollPercentage: 0.6)
        try history.saveTextReading(summary, chapter: chapters[1], chapterIndex: 1, locator: position, now: 12)
        let manifest = try Data(contentsOf: folder.appendingPathComponent("book.json"))
        let saved = try Data(contentsOf: historyDirectory.appendingPathComponent("library.json"))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("content.epub"))
        XCTAssertEqual(try reopened.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024), before)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("book.json")), manifest)
        XCTAssertEqual(try Data(contentsOf: historyDirectory.appendingPathComponent("library.json")), saved)
        XCTAssertEqual(try LibraryStore(directory: historyDirectory).textPosition(for: summary, chapterID: chapters[1].chapterId), position)
        XCTAssertEqual(try reopened.book(id: book.id), book)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
    }

    func testComicAndMixedKindleReadActualImageBytesAndExtensionOnlyLabels() async throws {
        for format in [LocalKindleFormat.azw, .azw3] {
            let library = try LocalLibrary(directory: directory()), bytes = mobi(body: "<img recindex='1'/>", images: [png, png, png])
            let book = try library.importKindle(title: "漫画", source: input(bytes), format: format) { try Data(contentsOf: $0) == self.png }
            XCTAssertTrue(try XCTUnwrap(book.epub).isPurePictureEpub)
            let local = LocalComicSource(library: library), detail = try await local.detail(comicId: book.id)
            XCTAssertEqual(detail.status, format.rawValue.uppercased())
            let chapters = try await local.chapters(comicId: book.id)
            let page = try await local.chapter(url: chapters[0].url)
            XCTAssertEqual(page.imageUrls.count, 3)
            try FileManager.default.removeItem(at: library.directory.appendingPathComponent(book.id).appendingPathComponent("content.epub"))
            for url in page.imageUrls { XCTAssertEqual(try library.epubImageData(pageURL: XCTUnwrap(URL(string: url))), png) }
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(URL(string: library.summary(for: book).coverUrl))), png)
        }
        let library = try LocalLibrary(directory: directory())
        let book = try library.importKindle(title: "图文", source: input(mobi(body: "<p>图文正文</p><img recindex='1'/><img recindex='2'/>", images: [png, png])), format: .mobi) { _ in true }
        XCTAssertFalse(try XCTUnwrap(book.epub).isPurePictureEpub)
        let path = try XCTUnwrap(book.epub?.manifest.first(where: { $0.mediaType == "image/png" })?.href)
        XCTAssertEqual(try library.epubResource(bookID: book.id, path: path, maximumBytes: 1000), png)
    }

    func testUnsupportedDamagedAndUnreadableImagesNeverPublishAndKeepOriginal() throws {
        let library = try LocalLibrary(directory: directory())
        let old = try library.importKindle(title: "保留", source: input(mobi()), format: .mobi) { _ in true }
        for (bytes, reason) in [(mobi(drm: 2), "DRM"), (mobi(version: 8), "KF8"), (Data([1, 2, 3]), "")] {
            let source = try input(bytes)
            XCTAssertThrowsError(try library.importKindle(title: "失败", source: source, format: .azw3) { _ in true }) {
                if !reason.isEmpty { XCTAssertTrue($0.localizedDescription.contains(reason), "\($0)") }
            }
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertEqual(try library.books(), [old])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [old.id])
        }
        XCTAssertThrowsError(try library.importKindle(title: "坏图", source: input(mobi(body: "<img recindex='1'/>", images: [png, png, png])), format: .mobi) { _ in false })
        XCTAssertEqual(try library.books(), [old])
    }

    func testLegacyMetadataAndOrdinaryEpubMissingArchiveAreNotKindle() throws {
        let id = UUID().uuidString
        let old = try JSONDecoder().decode(LocalBook.self, from: Data("{\"id\":\"\(id)\",\"title\":\"旧书\",\"createdAt\":1,\"pages\":[\"0.jpg\"]}".utf8))
        XCTAssertNil(old.kindleFormat)
        let root = try directory(), epub = root.appendingPathComponent("book.epub")
        _ = try KindlePublicationAdapter.convert(source: input(mobi()), to: epub)
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let book = try library.importEpub(title: "EPUB", archive: epub) { _ in true }
        XCTAssertNil(book.kindleFormat)
        try FileManager.default.removeItem(at: library.directory.appendingPathComponent(book.id).appendingPathComponent("content.epub"))
        XCTAssertThrowsError(try library.book(id: book.id))
        XCTAssertThrowsError(try library.pageURLs(for: LocalBook(id: id, title: "坏标记", createdAt: 0, pages: ["0.jpg"], kindleFormat: .mobi)))
    }

    func testMissingSymlinkOriginalAndDerivedMismatchRefuseRecovery() throws {
        for mutation in ["missing", "symlink", "dangling", "changed", "derived-symlink", "corrupt"] {
            let library = try LocalLibrary(directory: directory())
            let book = try library.importKindle(title: "校验", source: input(mobi()), format: .mobi) { _ in true }
            let folder = library.directory.appendingPathComponent(book.id), source = folder.appendingPathComponent("source.kindle"), derived = folder.appendingPathComponent("content.epub")
            try FileManager.default.removeItem(at: derived)
            switch mutation {
            case "missing": try FileManager.default.removeItem(at: source)
            case "symlink", "dangling":
                try FileManager.default.removeItem(at: source)
                let target = mutation == "symlink" ? try input(mobi()) : folder.appendingPathComponent("missing")
                try FileManager.default.createSymbolicLink(at: source, withDestinationURL: target)
            case "changed": try mobi(body: "<h1>另一章</h1><p>另一书</p>").write(to: source)
            case "derived-symlink": try FileManager.default.createSymbolicLink(at: derived, withDestinationURL: folder.appendingPathComponent("missing"))
            default: try Data([1, 2, 3]).write(to: derived)
            }
            let before = try Data(contentsOf: folder.appendingPathComponent("book.json"))
            XCTAssertThrowsError(try library.epubResource(bookID: book.id, path: XCTUnwrap(book.epub?.spine.first?.fullZipPath), maximumBytes: 10000), mutation)
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("book.json")), before)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
            if mutation == "corrupt" { XCTAssertEqual(try Data(contentsOf: derived), Data([1, 2, 3])) }
        }
    }

    func testCancellationDuringOriginalCopyAndImageProbeNeverPublishes() async throws {
        for inCopy in [true, false] {
            let source = try input(mobi(body: "<img recindex='1'/>", images: [png, png, png])), bytes = try Data(contentsOf: source)
            let library = try LocalLibrary(directory: directory(), readChunk: { handle, count in
                let data = try handle.read(upToCount: count)
                if inCopy { withUnsafeCurrentTask { $0?.cancel() } }
                return data
            })
            let worker = Task.detached {
                try library.importKindle(title: "取消", source: source, format: .mobi) { _ in
                    withUnsafeCurrentTask { $0?.cancel() }; return true
                }
            }
            do { _ = try await worker.value; XCTFail("取消不应发布") }
            catch { XCTAssertTrue(error is CancellationError, "\(error)") }
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [])
        }
    }

    private func recoveringBook() throws -> (LocalLibrary, LocalBook, String) {
        let library = try LocalLibrary(directory: directory())
        let book = try library.importKindle(title: "真实长篇", source: input(mobi(body: "<h1>长篇</h1><p>" + String(repeating: "正文", count: 500_000) + "</p>")), format: .mobi) { _ in true }
        try FileManager.default.removeItem(at: library.directory.appendingPathComponent(book.id).appendingPathComponent("content.epub"))
        return (library, book, try XCTUnwrap(book.epub?.spine.first?.fullZipPath))
    }

    private func awaitScratch(_ library: LocalLibrary, count: Int = 1) async throws {
        for _ in 0..<3000 {
            if try FileManager.default.contentsOfDirectory(atPath: library.directory.path).filter({ $0.hasPrefix(".restore-") }).count >= count { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("真实恢复未进入独立 scratch 阶段")
    }

    func testConcurrentActualResourceRequestsRebuildWithoutOverwriteOrResidue() async throws {
        let (library, book, path) = try recoveringBook()
        let a = Task.detached { try library.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024) }
        let b = Task.detached { try library.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024) }
        try await awaitScratch(library, count: 2)
        let first = try await a.value, second = try await b.value
        XCTAssertEqual(first, second); XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("长篇"))
        XCTAssertEqual(try library.book(id: book.id), book)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
    }

    func testCancellationOrDeletedBookDuringActualRecoveryDoesNotResurrectBook() async throws {
        for cancel in [true, false] {
            let (library, book, path) = try recoveringBook()
            let worker = Task.detached { try library.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024) }
            try await awaitScratch(library)
            if cancel { worker.cancel() }
            else { try FileManager.default.removeItem(at: library.directory.appendingPathComponent(book.id)) }
            do { _ = try await worker.value; XCTFail("取消或已删除书不能发布") }
            catch { if cancel { XCTAssertTrue(error is CancellationError, "\(error)") } }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), cancel ? [book.id] : [])
            if cancel {
                XCTAssertEqual(try library.book(id: book.id), book)
                XCTAssertFalse(FileManager.default.fileExists(atPath: library.directory.appendingPathComponent(book.id).appendingPathComponent("content.epub").path))
            }
        }
    }

    func testRecoveryOnlyReusesAnOwnedMatchingConcurrentWinner() async throws {
        for winner in ["matching", "different", "symlink"] {
            let (library, book, path) = try recoveringBook()
            let original = library.directory.appendingPathComponent(book.id).appendingPathComponent("source.kindle")
            let candidate = try directory().appendingPathComponent("winner.epub")
            _ = try KindlePublicationAdapter.convert(source: winner == "matching" ? original : input(mobi()), to: candidate)
            let worker = Task.detached { try library.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024) }
            try await awaitScratch(library)
            let target = library.directory.appendingPathComponent(book.id).appendingPathComponent("content.epub")
            if winner == "symlink" { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: candidate) }
            else { try FileManager.default.copyItem(at: candidate, to: target) }
            let bytes = try Data(contentsOf: candidate)
            do {
                let actual = try await worker.value
                XCTAssertEqual(winner, "matching")
                XCTAssertTrue(String(decoding: actual, as: UTF8.self).contains("长篇"))
            } catch { XCTAssertNotEqual(winner, "matching", "\(error)") }
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
        }
    }

    func testOldRecoveryCannotPublishIntoReplacedBookOrExternalSymlinkDirectory() async throws {
        for symlink in [false, true] {
            let (library, book, path) = try recoveringBook()
            let folder = library.directory.appendingPathComponent(book.id), parked = try directory().appendingPathComponent("old-book")
            let worker = Task.detached { try library.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024) }
            try await awaitScratch(library)
            try FileManager.default.moveItem(at: folder, to: parked)
            if symlink { try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: parked) }
            else { try FileManager.default.copyItem(at: parked, to: folder) }
            do { _ = try await worker.value; XCTFail("旧 worker 不能发布到新目录") } catch { }
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("content.epub").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: parked.appendingPathComponent("content.epub").path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
        }
    }

    func testImportValidatesOwnedOriginalAndDerivedTogetherBeforeShelfPublication() throws {
        let bytes = mobi(body: "<img recindex='1'/>", images: [png, png, png]), source = try input(bytes)
        let library = try LocalLibrary(directory: directory())
        var probed = false
        let book = try library.importKindle(title: "原子导入", source: source, format: .mobi) { probe in
            probed = true
            XCTAssertTrue(try library.books().isEmpty)
            let staging = probe.deletingLastPathComponent()
            XCTAssertEqual(try Data(contentsOf: staging.appendingPathComponent("source.kindle")), bytes)
            XCTAssertTrue(FileManager.default.fileExists(atPath: staging.appendingPathComponent("content.epub").path))
            return true
        }
        XCTAssertTrue(probed); XCTAssertEqual(try library.books(), [book])
        let oversized = try directory().appendingPathComponent("oversized.mobi")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(LocalLibrary.maximumImportBytes) + 1); try handle.close()
        XCTAssertThrowsError(try library.importKindle(title: "超大", source: oversized, format: .mobi) { _ in true })
        let link = try directory().appendingPathComponent("linked.mobi")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try library.importKindle(title: "链接", source: link, format: .mobi) { _ in true })
        XCTAssertEqual(try library.books(), [book])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
    }

    func testFinalPublishBoundaryRejectsReplacedSymlinkMovedAndDeletedDirectoriesWithoutWritingElsewhere() throws {
        for change in ["replacement", "external-symlink", "moved", "deleted"] {
            let library = try LocalLibrary(directory: directory())
            let book = try library.importKindle(title: "发布边界", source: input(mobi()), format: .mobi) { _ in true }
            let folder = library.directory.appendingPathComponent(book.id)
            try FileManager.default.removeItem(at: folder.appendingPathComponent("content.epub"))
            let parked = try directory().appendingPathComponent("original-book")
            let external = try directory().appendingPathComponent("different-book")
            try FileManager.default.copyItem(at: folder, to: external)
            let original = try Data(contentsOf: external.appendingPathComponent("source.kindle"))
            let metadata = try Data(contentsOf: external.appendingPathComponent("book.json"))
            let boundary = expectation(description: "owner validation completed before \(change)")
            boundary.assertForOverFulfill = true
            let recovering = try LocalLibrary(directory: library.directory, readChunk: { try $0.read(upToCount: $1) }, beforeKindlePublish: {
                boundary.fulfill()
                if change == "deleted" { try FileManager.default.removeItem(at: folder) }
                else { try FileManager.default.moveItem(at: folder, to: parked) }
                if change == "replacement" { try FileManager.default.copyItem(at: external, to: folder) }
                if change == "external-symlink" { try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: external) }
            })
            XCTAssertThrowsError(try recovering.epubResource(bookID: book.id, path: XCTUnwrap(book.epub?.spine.first?.fullZipPath), maximumBytes: 8 * 1024 * 1024), change)
            wait(for: [boundary], timeout: 1)
            for candidate in [folder, parked, external] {
                XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.appendingPathComponent("content.epub").path), "\(change): \(candidate.path)")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    XCTAssertEqual(try Data(contentsOf: candidate.appendingPathComponent("source.kindle")), original)
                    XCTAssertEqual(try Data(contentsOf: candidate.appendingPathComponent("book.json")), metadata)
                }
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), ["replacement", "external-symlink"].contains(change) ? [book.id] : [])
        }
    }

    func testFinalPublishBoundaryPreservesConcurrentWinnerOnSuccessFailureAndCancellation() async throws {
        for mode in ["matching", "invalid", "cancelled"] {
            let library = try LocalLibrary(directory: directory())
            let book = try library.importKindle(title: "发布赢家", source: input(mobi()), format: .mobi) { _ in true }
            let folder = library.directory.appendingPathComponent(book.id), target = folder.appendingPathComponent("content.epub")
            let winner = mode == "invalid" ? Data([1, 2, 3]) : try Data(contentsOf: target)
            let original = try Data(contentsOf: folder.appendingPathComponent("source.kindle"))
            let metadata = try Data(contentsOf: folder.appendingPathComponent("book.json"))
            let path = try XCTUnwrap(book.epub?.spine.first?.fullZipPath)
            let expected = try library.epubResource(bookID: book.id, path: path, maximumBytes: 10000)
            try FileManager.default.removeItem(at: target)
            let boundary = expectation(description: "winner created immediately before \(mode) publish")
            boundary.assertForOverFulfill = true
            let recovering = try LocalLibrary(directory: library.directory, readChunk: { try $0.read(upToCount: $1) }, beforeKindlePublish: {
                try winner.write(to: target, options: .withoutOverwriting)
                boundary.fulfill()
                if mode == "cancelled" { withUnsafeCurrentTask { $0?.cancel() } }
            })
            let worker = Task.detached { try recovering.epubResource(bookID: book.id, path: path, maximumBytes: 10000) }
            do {
                let bytes = try await worker.value
                XCTAssertEqual(mode, "matching"); XCTAssertEqual(bytes, expected)
            } catch {
                XCTAssertNotEqual(mode, "matching", "\(error)")
                if mode == "cancelled" { XCTAssertTrue(error is CancellationError, "\(error)") }
            }
            await fulfillment(of: [boundary], timeout: 1)
            XCTAssertEqual(try Data(contentsOf: target), winner)
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("source.kindle")), original)
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("book.json")), metadata)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
        }
    }
}
