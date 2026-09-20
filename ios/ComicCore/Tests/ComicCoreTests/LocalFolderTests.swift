import XCTest
@testable import ComicCore

final class LocalFolderTests: XCTestCase {
    func testEntryLimitCountsDirectoriesAndPreservesSourcesWhenExceeded() throws {
        let root = try fixture(["1.jpg": 42, "__MACOSX/ignored.jpg": 7, ".DS_Store": 9])
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input")
        for index in 0..<49_999 {
            try FileManager.default.createDirectory(at: input.appendingPathComponent("dir\(index)"), withIntermediateDirectories: false)
        }
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let book = try library.importFolder(title: "边界", folder: input, isReadableImage: { _ in true })
        XCTAssertEqual(book.pages.count, 1)
        try FileManager.default.createDirectory(at: input.appendingPathComponent("one-too-many"), withIntermediateDirectories: false)
        XCTAssertThrowsError(try library.importFolder(title: "超限", folder: input, isReadableImage: { _ in true })) { error in
            guard case LocalLibraryError.folderTooLarge = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try library.books(), [book])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [book.id])
        XCTAssertEqual(try Data(contentsOf: input.appendingPathComponent("1.jpg")), Data([42]))
    }

    func testWrapperIsRemovedAndChapterPagesKeepNaturalPathOrderAfterReopening() async throws {
        let root = try fixture(["wrapper/book/2.jpg": 0, "wrapper/book/第10话/1.jpg": 10, "wrapper/book/第2话/10.jpg": 3, "wrapper/book/第2话/2.jpg": 2, "wrapper/book/第2话/附录/1.jpg": 4, "wrapper/book/notes.txt": 99])
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let book = try library.importFolder(title: "目录漫画", folder: root.appendingPathComponent("input"), isReadableImage: { _ in true })
        let reopened = try LocalLibrary(directory: library.directory)
        let source = LocalComicSource(library: reopened)
        let chapters = try await source.chapters(comicId: book.id)
        XCTAssertEqual(chapters.map(\.title), ["未分章", "第2话", "第10话"])
        XCTAssertEqual(chapters.map(\.chapterSlot), [0, 1, 2])
        var contents: [[UInt8]] = []
        for chapter in chapters {
            let page = try await source.chapter(url: chapter.url)
            contents.append(try page.imageUrls.map { try Data(contentsOf: XCTUnwrap(URL(string: $0))).first! })
        }
        XCTAssertEqual(contents, [[0], [2, 3, 4], [10]])
        XCTAssertEqual(try reopened.books(), [book])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("input/wrapper/book/第2话/2.jpg").path))
    }

    func testSingleNestedFolderBecomesBodyAndUnreadableOrMetadataAreSkipped() async throws {
        let root = try fixture(["wrapper/chapter/10.PNG": 10, "wrapper/chapter/2.jpeg": 2, "wrapper/chapter/bad.jpg": 0, "__MACOSX/garbage.jpg": 88, "Thumbs.db": 99])
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let book = try library.importFolder(title: "正文", folder: root.appendingPathComponent("input"), isReadableImage: { $0.lastPathComponent != "bad.jpg" })
        let source = LocalComicSource(library: library)
        let chapters = try await source.chapters(comicId: book.id)
        XCTAssertEqual(chapters.map(\.title), ["正文"])
        let page = try await source.chapter(url: chapters[0].url)
        XCTAssertEqual(try page.imageUrls.map { try Data(contentsOf: XCTUnwrap(URL(string: $0))).first! }, [2, 10])
    }

    func testLegacyManifestAndBookIDChapterURLRemainReadable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString
        let folder = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([42]).write(to: folder.appendingPathComponent("0.jpg"))
        try Data("{\"id\":\"\(id)\",\"title\":\"旧书\",\"createdAt\":1,\"pages\":[\"0.jpg\"]}".utf8).write(to: folder.appendingPathComponent("book.json"))
        let source = LocalComicSource(library: try LocalLibrary(directory: root))
        let chapters = try await source.chapters(comicId: id)
        XCTAssertEqual(chapters, [.init(chapterId: id, title: "旧书", url: id)])
        let page = try await source.chapter(url: id)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(URL(string: page.imageUrls[0]))), Data([42]))
    }

    func testTooDeepAndSymlinkFoldersDoNotPublishOrTouchSources() throws {
        let root = try fixture(["a/b/c/d/e/f/1.jpg": 1])
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        XCTAssertThrowsError(try library.importFolder(title: "过深", folder: root.appendingPathComponent("input"), isReadableImage: { _ in true }))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("input"))
        XCTAssertThrowsError(try library.importFolder(title: "链接", folder: link, isReadableImage: { _ in true }))
        XCTAssertTrue(try library.books().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("input/a/b/c/d/e/f/1.jpg").path))
    }

    func testCancelledAndEmptyFolderNeverPublish() async throws {
        let root = try fixture(["1.jpg": 1])
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try library.importFolder(title: "取消", folder: root.appendingPathComponent("input"), isReadableImage: { _ in true })
        }
        do { _ = try await task.value; XCTFail("cancelled folder published") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertThrowsError(try library.importFolder(title: "全坏图", folder: root.appendingPathComponent("input"), isReadableImage: { _ in false }))
        XCTAssertTrue(try library.books().isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [])
    }

    func testInvalidChapterManifestIsRejectedBeforeDictionaryConstruction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalLibrary(directory: root)
        let id = UUID().uuidString
        let duplicate = LocalBook(id: id, title: "重复页", createdAt: 0, pages: ["0.jpg", "0.jpg"], chapters: [.init(id: id + "_ch_0", title: "章", pages: ["0.jpg"])])
        XCTAssertThrowsError(try library.pageURLs(for: duplicate))
        let escape = LocalBook(id: id, title: "坏章节", createdAt: 0, pages: ["0.jpg"], chapters: [.init(id: "../chapter", title: "章", pages: ["0.jpg"])])
        XCTAssertThrowsError(try library.pageURLs(for: escape))
        let missing = LocalBook(id: id, title: "缺页", createdAt: 0, pages: ["0.jpg"], chapters: [.init(id: "chapter", title: "章", pages: ["not-in-book.jpg"])])
        XCTAssertThrowsError(try library.pageURLs(for: missing))
        let repeated = LocalBook(id: id, title: "重复分章", createdAt: 0, pages: ["0.jpg", "1.jpg"], chapters: [
            .init(id: "chapter-1", title: "第一章", pages: ["0.jpg"]),
            .init(id: "chapter-2", title: "第二章", pages: ["0.jpg", "1.jpg"])
        ])
        XCTAssertThrowsError(try library.pageURLs(for: repeated))
        let omitted = LocalBook(id: id, title: "遗漏分章", createdAt: 0, pages: ["0.jpg", "1.jpg"], chapters: [
            .init(id: "chapter", title: "第一章", pages: ["0.jpg"])
        ])
        XCTAssertThrowsError(try library.pageURLs(for: omitted))
    }

    private func fixture(_ files: [String: UInt8]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (path, byte) in files {
            let url = root.appendingPathComponent("input").appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([byte]).write(to: url)
        }
        return root
    }
}
