import Foundation
import XCTest
import ZIPFoundation
@testable import ComicCore

final class LocalImportFingerprintTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=")!
    // Deterministic 182-byte store ZIP containing "page.png".
    // SHA256 precomputed independently via Node crypto: 86c9526b28ce28990b60a10b0b6b2119d813b1d3ebaef28d3c9d4d478f85a8ed
    private let deterministicZip = Data(base64Encoded: "UEsDBAoAAAAAAAAAAADKTj3RRAAAAEQAAAAIAAAAcGFnZS5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBAAAALUcDAIAAAALSURBVHjaY/z/HwADAwIA75pfWwAAAABJRU5ErkJgglBLAQIUAAoAAAAAAAAAAADKTj3RRAAAAEQAAAAIAAAAAAAAAAAAAAAAAAAAAABwYWdlLnBuZ1BLBQYAAAAAAQABADYAAABqAAAAAAA=")!
    // Deterministic 597-byte EPUB containing container.xml, book.opf, and page.png.
    // SHA256 precomputed independently via Node crypto: c5b711d9af53f068de79069a33188b0d25d781e26a983d72f7b52c567eb9e981
    private let deterministicEpub = Data(base64Encoded: "UEsDBAoAAAAAAAAAAACb+KmfOwAAADsAAAAWAAAATUVUQS1JTkYvY29udGFpbmVyLnhtbDxjb250YWluZXI+PHJvb3RmaWxlIGZ1bGwtcGF0aD0nT1BTL2Jvb2sub3BmJy8+PC9jb250YWluZXI+UEsDBAoAAAAAAAAAAAB4J4nsgAAAAIAAAAAMAAAAT1BTL2Jvb2sub3BmPHBhY2thZ2U+PG1hbmlmZXN0PjxpdGVtIGlkPSdwJyBocmVmPSdwYWdlLnBuZycgbWVkaWEtdHlwZT0naW1hZ2UvcG5nJy8+PC9tYW5pZmVzdD48c3BpbmU+PGl0ZW1yZWYgaWRyZWY9J3AnLz48L3NwaW5lPjwvcGFja2FnZT5QSwMECgAAAAAAAAAAAMpOPdFEAAAARAAAAAwAAABPUFMvcGFnZS5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBAAAALUcDAIAAAALSURBVHjaY/z/HwADAwIA75pfWwAAAABJRU5ErkJgglBLAQIUAAoAAAAAAAAAAACb+KmfOwAAADsAAAAWAAAAAAAAAAAAAAAAAAAAAABNRVRBLUlORi9jb250YWluZXIueG1sUEsBAhQACgAAAAAAAAAAAHgnieyAAAAAgAAAAAwAAAAAAAAAAAAAAAAAbwAAAE9QUy9ib29rLm9wZlBLAQIUAAoAAAAAAAAAAADKTj3RRAAAAEQAAAAMAAAAAAAAAAAAAAAAABkBAABPUFMvcGFnZS5wbmdQSwUGAAAAAAMAAwC4AAAAhwEAAAAA")!

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func image(_ directory: URL, name: String, data: Data? = nil) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data ?? png).write(to: url)
        return url
    }

    private func archive(_ directory: URL, name: String = "book.cbz") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try deterministicZip.write(to: url)
        return url
    }

    private func epub(_ directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("book.epub")
        try deterministicEpub.write(to: url)
        return url
    }

    // A minimal real MOBI7 record; Comic SHA256 precomputed independently with Python: 25ca18d45f08e29b774ac2f2a57c07cd0377c6deec4844e4d0cfe0fc45ddd81e
    private func kindle(_ directory: URL) throws -> URL {
        func put(_ data: inout Data, _ offset: Int, _ value: UInt32) {
            data.replaceSubrange(offset..<offset + 4, with: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
        }
        let text = Data("<img recindex='1'/>".utf8), url = directory.appendingPathComponent("book.mobi")
        var header = Data(repeating: 0, count: 256)
        header[1] = 1; header[9] = 1; put(&header, 4, UInt32(text.count))
        header.replaceSubrange(16..<20, with: Data("MOBI".utf8)); put(&header, 20, 232); put(&header, 24, 2); put(&header, 28, 65001); put(&header, 36, 6)
        put(&header, 108, 2); put(&header, 168, .max); put(&header, 172, .max)
        var data = Data(repeating: 0, count: 102)
        data.replaceSubrange(0..<4, with: Data("Book".utf8)); data.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8)); data[77] = 3
        put(&data, 78, 102); put(&data, 86, 358); put(&data, 94, UInt32(358 + text.count)); data += header; data += text; data += png
        try data.write(to: url)
        return url
    }

    func testFolderPersistsOriginalPathManifestHashAfterExternalSourceChanges() throws {
        let root = try directory(), input = root.appendingPathComponent("input"), library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
        let two = try image(input, name: "2.png", data: Data("abc".utf8))
        let ten = try image(input, name: "10.png", data: Data())
        let prepared = try library.prepareFolder(title: "folder", folder: input) { _ in true }
        try Data("changed".utf8).write(to: two); try Data("changed".utf8).write(to: ten)
        let book = try library.publishPrepared(prepared), reopened = try LocalLibrary(directory: library.directory)
        XCTAssertEqual(book.importFormat, .folder)
        // Fixed Node crypto SHA256 of "2.png:<sha256(abc)>\n10.png:<sha256('')>\n"
        XCTAssertEqual(book.fingerprint, "289a7e9d8b7639baa049ca4aed2c3fc55cf31ec0056560ea3459ff175cc325d3")
        XCTAssertEqual(try reopened.book(id: book.id).fingerprint, book.fingerprint)
        XCTAssertEqual(try reopened.pageURLs(for: book).map { try Data(contentsOf: $0) }, [Data("abc".utf8), Data()])
    }

    func testFolderRelativePathChangeAltersManifestFingerprint() throws {
        let root = try directory(), input = root.appendingPathComponent("input"), library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
        _ = try image(input, name: "3.png", data: Data("abc".utf8))
        _ = try image(input, name: "10.png", data: Data())
        let book = try library.importFolder(title: "folder", folder: input) { _ in true }
        XCTAssertEqual(book.importFormat, .folder)
        XCTAssertNotEqual(book.fingerprint, "289a7e9d8b7639baa049ca4aed2c3fc55cf31ec0056560ea3459ff175cc325d3")
    }

    func testArchiveCopiesOriginalBeforeProbeAndPersistsItsHash() throws {
        let root = try directory(), input = try archive(root), original = try Data(contentsOf: input)
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let book = try library.importArchive(title: "archive", archive: input) { _ in
            try Data("external replacement".utf8).write(to: input)
            return true
        }
        let reopened = try LocalLibrary(directory: library.directory), folder = library.directory.appendingPathComponent(book.id)
        XCTAssertEqual(book.importFormat, .cbz)
        // Fixed Node crypto SHA256 of deterministicZip:
        XCTAssertEqual(book.fingerprint, "86c9526b28ce28990b60a10b0b6b2119d813b1d3ebaef28d3c9d4d478f85a8ed")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("source.archive")), original)
        XCTAssertEqual(try reopened.pageURLs(for: book).map { try Data(contentsOf: $0) }, [png])
    }

    func testEpubPdfAndKindlePersistHashesOfTheirOwnedOriginalFiles() throws {
        let root = try directory(), library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let epubSource = try epub(root), pdfSource = try image(root, name: "book.pdf", data: Data("PDF storage fixture".utf8)), kindleSource = try kindle(root)
        let ebook = try library.importEpub(title: "epub", archive: epubSource) { try Data(contentsOf: $0) == self.png }
        let pdf = try library.importPdf(title: "pdf", file: pdfSource, inspect: { _ in PdfPublication(pages: [.init(width: 1, height: 1)]) }, renderCover: { _ in nil })
        let kindle = try library.importKindle(title: "kindle", source: kindleSource, format: .mobi) { try Data(contentsOf: $0) == self.png }
        let reopened = try LocalLibrary(directory: library.directory)
        // Fixed independent Node crypto expectations
        let expected: [(LocalBook, LocalImportFormat, String, String)] = [
            (ebook, .epub, "content.epub", "c5b711d9af53f068de79069a33188b0d25d781e26a983d72f7b52c567eb9e981"),
            (pdf, .pdf, "content.pdf", "33e1382aea3ec9c4621ed0c77e29bd2b0df6c5c9de3d557fbc276153458aab4b"),
            (kindle, .mobi, "source.kindle", "25ca18d45f08e29b774ac2f2a57c07cd0377c6deec4844e4d0cfe0fc45ddd81e")
        ]
        for (book, format, name, expectedHash) in expected {
            let stored = library.directory.appendingPathComponent(book.id).appendingPathComponent(name)
            XCTAssertEqual(book.importFormat, format)
            XCTAssertEqual(book.fingerprint, expectedHash)
            XCTAssertEqual(try ContentFingerprint.file(stored), expectedHash)
            XCTAssertEqual(try reopened.book(id: book.id), book)
        }
    }

    func testImagesImportHasImagesFormatAndNilFingerprint() throws {
        let root = try directory(), library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let one = try image(root, name: "1.png"), two = try image(root, name: "2.png")
        let book = try library.importImages(title: "images", files: [one, two])
        XCTAssertEqual(book.importFormat, .images)
        XCTAssertNil(book.fingerprint)
        let reopened = try library.book(id: book.id)
        XCTAssertEqual(reopened.importFormat, .images)
        XCTAssertNil(reopened.fingerprint)
    }

    func testLegacyManifestWithoutFingerprintOrFormatRemainsReadable() throws {
        let root = try directory(), library = try LocalLibrary(directory: root.appendingPathComponent("library")), id = UUID().uuidString
        let folder = library.directory.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try png.write(to: folder.appendingPathComponent("0.png"))
        let manifest = try JSONEncoder().encode(LocalBook(id: id, title: "legacy", createdAt: 1, pages: ["0.png"]))
        try manifest.write(to: folder.appendingPathComponent("book.json"))
        XCTAssertEqual(try JSONDecoder().decode(LocalBook.self, from: manifest).id, id)
        let legacy = try LocalLibrary(directory: library.directory).book(id: id)
        XCTAssertNil(legacy.importFormat)
        XCTAssertNil(legacy.fingerprint)
    }

    func testMetadataValidationRejectsInvalidFingerprintAndFormatCombinations() throws {
        let id = UUID().uuidString
        // Uppercase hex in fingerprint
        let uppercase = LocalBook(id: id, title: "bad", createdAt: 1, pages: ["0.png"],
                                  importFormat: .folder, fingerprint: "289A7E9D8B7639BAA049CA4AED2C3FC55CF31EC0056560EA3459FF175CC325D3")
        XCTAssertThrowsError(try uppercase.validateMetadata())
        // Invalid length
        let short = LocalBook(id: id, title: "bad", createdAt: 1, pages: ["0.png"],
                              importFormat: .folder, fingerprint: "289a7e")
        XCTAssertThrowsError(try short.validateMetadata())
        // Images format cannot have fingerprint
        let imagesWithFP = LocalBook(id: id, title: "bad", createdAt: 1, pages: ["0.png"],
                                     importFormat: .images, fingerprint: "289a7e9d8b7639baa049ca4aed2c3fc55cf31ec0056560ea3459ff175cc325d3")
        XCTAssertThrowsError(try imagesWithFP.validateMetadata())
        // Folder format cannot have nil fingerprint
        let folderWithoutFP = LocalBook(id: id, title: "bad", createdAt: 1, pages: ["0.png"],
                                        importFormat: .folder, fingerprint: nil)
        XCTAssertThrowsError(try folderWithoutFP.validateMetadata())
    }

    func testArchiveRequiresOwnedSourceArchiveFileOnReopening() throws {
        let root = try directory(), library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let input = try archive(root)
        let book = try library.importArchive(title: "archive", archive: input) { _ in true }
        let archiveFile = library.directory.appendingPathComponent(book.id).appendingPathComponent("source.archive")
        // Remove source.archive
        try FileManager.default.removeItem(at: archiveFile)
        XCTAssertThrowsError(try library.book(id: book.id))
        // Replace with symlink
        let fake = try image(root, name: "fake.zip")
        try FileManager.default.createSymbolicLink(at: archiveFile, withDestinationURL: fake)
        XCTAssertThrowsError(try library.book(id: book.id))
    }

    func testCancellationDuringPreparationCleansStaging() async throws {
        let root = try directory(), library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let input = root.appendingPathComponent("input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
        _ = try image(input, name: "1.png")
        let task = Task {
            try library.prepareFolder(title: "cancel", folder: input) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return true
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [])
    }
}
