import Foundation
import XCTest
import ZIPFoundation
@testable import ComicCore
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
#endif

final class LocalImportPreparationTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=")!

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func image() throws -> URL {
        let url = try directory().appendingPathComponent("1.png")
        try png.write(to: url)
        return url
    }

    private func epub() throws -> URL {
        let url = try directory().appendingPathComponent("book.epub")
        let archive = try Archive(url: url, accessMode: .create)
        let entries = [
            "META-INF/container.xml": Data("<container><rootfile full-path='OPS/book.opf'/></container>".utf8),
            "OPS/book.opf": Data("<package><manifest><item id='p' href='page.png' media-type='image/png'/></manifest><spine><itemref idref='p'/></spine></package>".utf8),
            "OPS/page.png": png
        ]
        for (path, data) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) {
                data.subdata(in: Int($0)..<Int($0) + $1)
            }
        }
        return url
    }

    func testPreparedImagesAndRealEpubStayInvisibleUntilPublishedAndReopen() throws {
        let library = try LocalLibrary(directory: directory())
        let picture = try library.prepareImages(title: "图片", files: [image()])
        let ebook = try library.prepareEpub(title: "EPUB", archive: epub()) { try Data(contentsOf: $0) == self.png }
        XCTAssertEqual(try library.books(), [])
        for prepared in [picture, ebook] {
            XCTAssertEqual(try JSONDecoder().decode(LocalBook.self, from: Data(contentsOf: prepared.staging.appendingPathComponent("book.json"))), prepared.book)
        }
        XCTAssertEqual(try Data(contentsOf: picture.staging.appendingPathComponent("0.png")), png)
        XCTAssertEqual(try Data(contentsOf: ebook.staging.appendingPathComponent("cover.bin")), png)
        let pictureBook = try library.publishPrepared(picture), epubBook = try library.publishPrepared(ebook)
        let reopened = try LocalLibrary(directory: library.directory)
        XCTAssertEqual(try reopened.book(id: pictureBook.id), pictureBook)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.pageURLs(for: pictureBook).first)), png)
        XCTAssertEqual(try reopened.epubImageData(pageURL: XCTUnwrap(reopened.pageURLs(for: epubBook).first)), png)
        XCTAssertFalse(FileManager.default.fileExists(atPath: picture.staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ebook.staging.path))
    }

    func testFolderAndRealZipKeepNaturalChapterOrderThroughPreparation() throws {
        let input = try directory(), zip = try directory().appendingPathComponent("book.cbz")
        let archive = try Archive(url: zip, accessMode: .create)
        for path in ["第10话/1.png", "第2话/10.png", "第2话/2.png"] {
            let url = input.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            let data = png
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) {
                data.subdata(in: Int($0)..<Int($0) + $1)
            }
        }
        let library = try LocalLibrary(directory: directory())
        let folder = try library.prepareFolder(title: "目录", folder: input) { try Data(contentsOf: $0) == self.png }
        let zipped = try library.prepareArchive(title: "ZIP", archive: zip) { try Data(contentsOf: $0) == self.png }
        XCTAssertTrue(try library.books().isEmpty)
        for prepared in [folder, zipped] {
            XCTAssertEqual(prepared.book.chapters?.map(\.title), ["第2话", "第10话"])
            XCTAssertEqual(prepared.book.chapters?.map { $0.pages.count }, [2, 1])
            let book = try library.publishPrepared(prepared)
            XCTAssertEqual(try library.pageURLs(for: book).map { try Data(contentsOf: $0) }, [png, png, png])
        }
    }

    // Same minimal real MOBI7 record layout as LocalKindleLibraryTests; no parser double.
    private func kindle() throws -> URL {
        func put(_ data: inout Data, _ offset: Int, _ value: UInt32) {
            data.replaceSubrange(offset..<offset + 4, with: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
        }
        let text = Data("<h1>第一章</h1><p>准备后的真实正文</p>".utf8)
        var header = Data(repeating: 0, count: 256)
        header[1] = 1; header[9] = 1
        put(&header, 4, UInt32(text.count))
        header.replaceSubrange(16..<20, with: Data("MOBI".utf8))
        put(&header, 20, 232); put(&header, 24, 2); put(&header, 28, 65001); put(&header, 36, 6)
        put(&header, 108, .max); put(&header, 168, .max); put(&header, 172, .max)
        var data = Data(repeating: 0, count: 94)
        data.replaceSubrange(0..<4, with: Data("Book".utf8))
        data.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        data[77] = 2
        put(&data, 78, 94); put(&data, 86, 350)
        data += header; data += text
        let url = try directory().appendingPathComponent("book.mobi")
        try data.write(to: url)
        return url
    }

    func testRealKindleRetainsOriginalAndDerivedArchiveBeforePublishingText() throws {
        let library = try LocalLibrary(directory: directory()), input = try kindle()
        let prepared = try library.prepareKindle(title: "小说", source: input, format: .mobi) { _ in XCTFail("纯文字不应探测图片"); return false }
        XCTAssertTrue(try library.books().isEmpty)
        XCTAssertEqual(try Data(contentsOf: prepared.staging.appendingPathComponent("source.kindle")), try Data(contentsOf: input))
        XCTAssertEqual(try EpubParser.parse(archive: prepared.staging.appendingPathComponent("content.epub")), prepared.book.epub)
        let book = try library.publishPrepared(prepared), reopened = try LocalLibrary(directory: library.directory)
        let text = try reopened.epubResource(bookID: book.id, path: XCTUnwrap(book.epub?.spine.first?.fullZipPath), maximumBytes: 10000)
        XCTAssertTrue(String(decoding: text, as: UTF8.self).contains("准备后的真实正文"))
    }

    func testPdfInjectedStoragePreparationCopiesBeforeInspectAndOnlyRendersAtImport() throws {
        let input = try directory().appendingPathComponent("book.pdf"), bytes = Data("PDF storage fixture; not PDF parsing evidence".utf8)
        try bytes.write(to: input)
        let library = try LocalLibrary(directory: directory())
        var inspected = 0, rendered = 0
        let prepared = try library.preparePdf(title: "PDF", file: input, inspect: { owned in
            inspected += 1
            XCTAssertNotEqual(owned, input)
            XCTAssertEqual(try Data(contentsOf: owned), bytes)
            return PdfPublication(pages: [.init(width: 80, height: 120)])
        }, renderCover: { _ in rendered += 1; return self.png })
        XCTAssertTrue(try library.books().isEmpty)
        XCTAssertEqual(try Data(contentsOf: prepared.staging.appendingPathComponent("cover.bin")), png)
        let book = try library.publishPrepared(prepared), reopened = try LocalLibrary(directory: library.directory)
        XCTAssertEqual(try reopened.book(id: book.id), book)
        XCTAssertEqual(inspected, 1); XCTAssertEqual(rendered, 1)
        XCTAssertEqual(try reopened.pdfPageData(pageURL: XCTUnwrap(reopened.pageURLs(for: book).first)) { owned, index in
            XCTAssertEqual(try Data(contentsOf: owned), bytes); XCTAssertEqual(index, 0)
            return self.png
        }, png)
    }

    func testNativePdfPreparationAndPublicationUseRealRenderer() throws {
        #if canImport(CoreGraphics) && canImport(ImageIO)
        let input = try directory().appendingPathComponent("native.pdf")
        var bounds = CGRect(x: 0, y: 0, width: 80, height: 120)
        let context = try XCTUnwrap(CGContext(input as CFURL, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
        context.endPDFPage(); context.closePDF()
        let library = try LocalLibrary(directory: directory())
        let prepared = try library.preparePdf(title: "真实 PDF", file: input, inspect: PdfRenderer.inspect,
            renderCover: { try PdfRenderer.render($0, pageIndex: 0, maximumDimension: 720) })
        XCTAssertTrue(try library.books().isEmpty)
        XCTAssertEqual(prepared.book.pdf?.pages, [.init(width: 80, height: 120)])
        let book = try library.publishPrepared(prepared), reopened = try LocalLibrary(directory: library.directory)
        let rendered = try reopened.pdfPageData(pageURL: XCTUnwrap(reopened.pageURLs(for: book).first)) { try PdfRenderer.render($0, pageIndex: $1) }
        XCTAssertFalse(rendered.isEmpty)
        #else
        throw XCTSkip("Real PDF prepare/publish requires Apple CoreGraphics and ImageIO; Linux injection checks storage only.")
        #endif
    }

    func testDiscardIsIdempotentAndCannotRemoveAnotherPreparationOrPublishedBook() throws {
        let library = try LocalLibrary(directory: directory()), input = try image()
        let first = try library.prepareImages(title: "放弃", files: [input])
        let second = try library.prepareImages(title: "保留", files: [input])
        try library.discardPrepared(first); try library.discardPrepared(first)
        XCTAssertThrowsError(try library.publishPrepared(first))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.staging.appendingPathComponent("book.json").path))
        let book = try library.publishPrepared(second)
        try library.discardPrepared(second); try library.discardPrepared(second)
        XCTAssertThrowsError(try library.publishPrepared(second))
        XCTAssertEqual(try library.books(), [book])
        XCTAssertEqual(try Data(contentsOf: input), png)
    }

    func testCrossLibraryIncludingSameDirectoryCannotPublishOrDiscardPreparation() throws {
        let library = try LocalLibrary(directory: directory()), prepared = try library.prepareImages(title: "归属", files: [image()])
        for other in [try LocalLibrary(directory: directory()), try LocalLibrary(directory: library.directory)] {
            XCTAssertThrowsError(try other.publishPrepared(prepared))
            XCTAssertThrowsError(try other.discardPrepared(prepared))
            XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.staging.path))
        }
        let copiedLibrary = library
        XCTAssertEqual(try copiedLibrary.publishPrepared(prepared), prepared.book)
    }

    func testReplacedMovedAndExternalSymlinkStagingIsNeitherPublishedNorDeleted() throws {
        for mode in ["replacement", "symlink", "moved"] {
            let library = try LocalLibrary(directory: directory()), prepared = try library.prepareImages(title: mode, files: [image()])
            let parked = try directory().appendingPathComponent("parked")
            try FileManager.default.moveItem(at: prepared.staging, to: parked)
            if mode == "replacement" { try FileManager.default.copyItem(at: parked, to: prepared.staging) }
            if mode == "symlink" { try FileManager.default.createSymbolicLink(at: prepared.staging, withDestinationURL: parked) }
            XCTAssertThrowsError(try library.publishPrepared(prepared), mode)
            XCTAssertThrowsError(try library.discardPrepared(prepared), mode)
            XCTAssertTrue(try library.books().isEmpty)
            XCTAssertEqual(try Data(contentsOf: parked.appendingPathComponent("0.png")), png)
            if mode != "moved" { XCTAssertEqual(try Data(contentsOf: prepared.staging.appendingPathComponent("0.png")), png) }
        }
    }

    func testManifestIdentityTamperingAndMissingOrSymlinkResourcesAreRejectedAndCleaned() throws {
        for mode in ["id", "manifest", "missing", "resource-link", "manifest-link"] {
            let library = try LocalLibrary(directory: directory()), input = try image()
            let prepared = try library.prepareImages(title: mode, files: [input]), manifest = prepared.staging.appendingPathComponent("book.json")
            if mode == "id" || mode == "manifest" {
                var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
                json[mode == "id" ? "id" : "pages"] = mode == "id" ? UUID().uuidString : ["outside.png"]
                try JSONSerialization.data(withJSONObject: json).write(to: manifest)
            } else {
                let target = mode == "manifest-link" ? manifest : prepared.staging.appendingPathComponent("0.png")
                try FileManager.default.removeItem(at: target)
                if mode != "missing" { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: input) }
            }
            XCTAssertThrowsError(try library.publishPrepared(prepared), mode)
            if mode == "resource-link" || mode == "manifest-link" {
                // The introduced link is not our file, even at a formerly owned filename.
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [prepared.staging.lastPathComponent])
                let link = mode == "manifest-link" ? manifest : prepared.staging.appendingPathComponent("0.png")
                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), input.path)
            } else { XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), []) }
            XCTAssertEqual(try Data(contentsOf: input), png)
        }
    }

    func testCancellationInPreparationAndAfterPreparationCleansOnlyCurrentImport() async throws {
        let root = try directory(), input = try image()
        let library = try LocalLibrary(directory: root), other = try library.prepareImages(title: "保留暂存", files: [input])
        let old = try library.importImages(title: "保留书", files: [input])
        let cancelledCopy = try LocalLibrary(directory: root, readChunk: { handle, count in
            let data = try handle.read(upToCount: count)
            withUnsafeCurrentTask { $0?.cancel() }
            return data
        })
        let first = Task.detached { try cancelledCopy.prepareImages(title: "复制取消", files: [input]) }
        do { _ = try await first.value; XCTFail("准备取消仍返回") } catch { XCTAssertTrue(error is CancellationError) }
        let prepared = try library.prepareImages(title: "发布前取消", files: [input])
        let second = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try library.publishPrepared(prepared)
        }
        do { _ = try await second.value; XCTFail("取消仍发布") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), [old.id, other.staging.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: input), png)
        try library.discardPrepared(other)
    }

    func testFinalPublishBoundaryRejectsReplacementSymlinkAndManifestMutation() throws {
        for mode in ["replacement", "symlink", "manifest", "resource-link"] {
            let root = try directory(), parked = try directory().appendingPathComponent("parked"), outside = try image()
            let library = try LocalLibrary(directory: root, readChunk: { try $0.read(upToCount: $1) }, beforeImportPublish: {
                let staging = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
                if mode == "manifest" {
                    try Data("{}".utf8).write(to: staging.appendingPathComponent("book.json"))
                } else if mode == "resource-link" {
                    let resource = staging.appendingPathComponent("0.png")
                    try FileManager.default.removeItem(at: resource)
                    try FileManager.default.createSymbolicLink(at: resource, withDestinationURL: outside)
                } else {
                    try FileManager.default.moveItem(at: staging, to: parked)
                    if mode == "replacement" { try FileManager.default.copyItem(at: parked, to: staging) }
                    else { try FileManager.default.createSymbolicLink(at: staging, withDestinationURL: parked) }
                }
            })
            let prepared = try library.prepareImages(title: mode, files: [image()])
            XCTAssertThrowsError(try library.publishPrepared(prepared), mode)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(prepared.book.id).path))
            if mode == "replacement" || mode == "symlink" {
                XCTAssertEqual(try Data(contentsOf: parked.appendingPathComponent("0.png")), png)
                XCTAssertEqual(try Data(contentsOf: prepared.staging.appendingPathComponent("0.png")), png)
            } else if mode == "resource-link" {
                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: prepared.staging.appendingPathComponent("0.png").path), outside.path)
            } else { XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), []) }
            XCTAssertEqual(try Data(contentsOf: outside), png)
        }
    }

    func testGrownManifestCannotExpandThePreparationReadBudget() throws {
        let library = try LocalLibrary(directory: directory()), prepared = try library.prepareImages(title: "元数据上限", files: [image()])
        let manifest = prepared.staging.appendingPathComponent("book.json")
        var data = try Data(contentsOf: manifest)
        data += Data(repeating: 0x20, count: 1024 * 1024)
        try data.write(to: manifest)
        XCTAssertThrowsError(try library.publishPrepared(prepared))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [])
    }

    func testFinalPublishBoundaryPreservesExistingTargetsIncludingEmptyDirectoryAndSymlink() throws {
        for mode in ["empty", "file", "symlink"] {
            let root = try directory(), outside = try image()
            let library = try LocalLibrary(directory: root, readChunk: { try $0.read(upToCount: $1) }, beforeImportPublish: {
                let staging = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
                let target = root.appendingPathComponent(String(staging.lastPathComponent.dropFirst(8)))
                if mode == "empty" { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
                if mode == "file" { try Data("winner".utf8).write(to: target) }
                if mode == "symlink" { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside) }
            })
            let prepared = try library.prepareImages(title: "输家", files: [image()])
            XCTAssertThrowsError(try library.publishPrepared(prepared))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [prepared.book.id])
            let target = root.appendingPathComponent(prepared.book.id)
            if mode == "empty" { XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), []) }
            else { XCTAssertEqual(try Data(contentsOf: target), mode == "file" ? Data("winner".utf8) : png) }
            XCTAssertEqual(try Data(contentsOf: outside), png)
        }
    }

    func testRealManifestWriteFailureRetainsForeignDirectoryAndReportsFailure() throws {
        let library = try LocalLibrary(directory: directory()), input = try image()
        XCTAssertThrowsError(try library.preparePdf(title: "写入失败", file: input, inspect: { _ in
            PdfPublication(pages: [.init(width: 80, height: 120)])
        }, renderCover: { owned in
            try FileManager.default.createDirectory(at: owned.deletingLastPathComponent().appendingPathComponent("book.json"), withIntermediateDirectories: false)
            return nil
        }))
        let staging = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: library.directory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.appendingPathComponent("book.json").path), [])
        XCTAssertEqual(try Data(contentsOf: input), png)
    }

    func testDiscardIOFailureIsReportedAndDoesNotRecurseIntoForeignContents() throws {
        let library = try LocalLibrary(directory: directory()), prepared = try library.prepareImages(title: "回收失败", files: [image()])
        let nested = prepared.staging.appendingPathComponent("unexpected"), file = nested.appendingPathComponent("keep")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try png.write(to: file)
        XCTAssertThrowsError(try library.discardPrepared(prepared))
        XCTAssertEqual(try Data(contentsOf: file), png)
        try FileManager.default.removeItem(at: nested)
        try library.discardPrepared(prepared)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [])
    }

    func testCancellationAtFinalPublishBoundaryStillReclaimsPreparedDirectory() async throws {
        let root = try directory(), input = try image()
        let library = try LocalLibrary(directory: root, readChunk: { try $0.read(upToCount: $1) }, beforeImportPublish: {
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let prepared = try library.prepareImages(title: "最终取消", files: [input])
        let worker = Task.detached { try library.publishPrepared(prepared) }
        do { _ = try await worker.value; XCTFail("最终取消仍发布") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        XCTAssertEqual(try Data(contentsOf: input), png)
    }

    func testReplacedLibraryRootCannotPublishOrDeleteReplacementOrParkedPreparation() throws {
        let parent = try directory(), root = parent.appendingPathComponent("library"), parked = parent.appendingPathComponent("parked")
        let library = try LocalLibrary(directory: root), prepared = try library.prepareImages(title: "根替换", files: [image()])
        try FileManager.default.moveItem(at: root, to: parked)
        try FileManager.default.copyItem(at: parked, to: root)
        XCTAssertThrowsError(try library.publishPrepared(prepared))
        XCTAssertThrowsError(try library.discardPrepared(prepared))
        for folder in [root, parked] {
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(prepared.staging.lastPathComponent).appendingPathComponent("0.png")), png)
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(prepared.book.id).path))
        }
    }

    func testConcurrentPublishAndDiscardCopiesHaveOneTerminalOutcome() async throws {
        let library = try LocalLibrary(directory: directory()), prepared = try library.prepareImages(title: "并发终态", files: [image()])
        let published = Task.detached { try? library.publishPrepared(prepared) }
        let discarded = Task.detached { try library.discardPrepared(prepared) }
        let book = await published.value
        try await discarded.value
        XCTAssertEqual(try library.books(), book.map { [$0] } ?? [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.staging.path))
        try library.discardPrepared(prepared)
    }

    func testForeignDirectFileAndEmptyDirectorySurviveDiscardAndFailedPublication() throws {
        for publishing in [false, true] {
            for directoryEntry in [false, true] {
                let library = try LocalLibrary(directory: directory())
                let prepared = try library.prepareImages(title: "外来项", files: [image()])
                let foreign = prepared.staging.appendingPathComponent(directoryEntry ? "foreign" : "foreign.txt")
                if directoryEntry { try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false) }
                else { try png.write(to: foreign) }
                if publishing {
                    try FileManager.default.createDirectory(at: library.directory.appendingPathComponent(prepared.book.id), withIntermediateDirectories: false)
                    XCTAssertThrowsError(try library.publishPrepared(prepared))
                } else { XCTAssertThrowsError(try library.discardPrepared(prepared)) }
                XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path), "未知直接项必须保留")
                if FileManager.default.fileExists(atPath: foreign.path) {
                    if directoryEntry { XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: foreign.path), []) }
                    else { XCTAssertEqual(try Data(contentsOf: foreign), png) }
                }
            }
        }
    }

    func testForeignEntriesAndReplacedOwnedFileSurvivePreparationFailure() throws {
        for mode in ["file", "directory", "replacement"] {
            let library = try LocalLibrary(directory: directory()), input = try epub()
            let parked = try directory().appendingPathComponent("original-probe")
            var retained: URL?
            XCTAssertThrowsError(try library.prepareEpub(title: "中途失败", archive: input) { probe in
                let target = mode == "replacement" ? probe : probe.deletingLastPathComponent().appendingPathComponent(mode == "file" ? "foreign.txt" : "foreign")
                retained = target
                if mode == "directory" { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
                else {
                    if mode == "replacement" { try FileManager.default.moveItem(at: target, to: parked) }
                    try self.png.write(to: target)
                }
                throw CocoaError(.fileWriteOutOfSpace)
            })
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(retained).path), mode)
        }
    }

    func testKnownFilenameReplacementIsNotOwnedForDiscardOrFailureCleanup() throws {
        for publishing in [false, true] {
            let library = try LocalLibrary(directory: directory()), prepared = try library.prepareImages(title: "替换", files: [image()])
            let page = prepared.staging.appendingPathComponent("0.png"), parked = try directory().appendingPathComponent("owned.png")
            try FileManager.default.moveItem(at: page, to: parked)
            try Data("foreign replacement".utf8).write(to: page)
            if publishing { XCTAssertThrowsError(try library.publishPrepared(prepared)) }
            else { XCTAssertThrowsError(try library.discardPrepared(prepared)) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: page.path))
            if FileManager.default.fileExists(atPath: page.path) { XCTAssertEqual(try Data(contentsOf: page), Data("foreign replacement".utf8)) }
            XCTAssertEqual(try Data(contentsOf: parked), png)
        }
    }
}
