import XCTest
@testable import ComicCore

final class LocalLibraryTests: XCTestCase {
    func testImportedImagesAreCopiedSortedAndSurviveReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let two = root.appendingPathComponent("2.jpg"), ten = root.appendingPathComponent("10.jpg")
        try Data([2]).write(to: two); try Data([10]).write(to: ten)
        let directory = root.appendingPathComponent("library")
        let library = try LocalLibrary(directory: directory)
        let book = try library.importImages(title: "测试漫画", files: [ten, two])
        try FileManager.default.removeItem(at: two)
        let reopened = try LocalLibrary(directory: directory)
        XCTAssertEqual(try reopened.books(), [book])
        let pages = try reopened.pageURLs(for: book)
        XCTAssertEqual(try Data(contentsOf: pages[0]), Data([2]))
        XCTAssertEqual(try Data(contentsOf: pages[1]), Data([10]))
        XCTAssertEqual(book.title, "测试漫画")
        let source = LocalComicSource(library: reopened)
        let chapters = try await source.chapters(comicId: book.id)
        let page = try await source.chapter(url: chapters[0].url)
        XCTAssertEqual(page.imageUrls, pages.map(\.absoluteString))
        let detail = try await source.detail(comicId: book.id)
        XCTAssertEqual(detail.summary.sourceId, "local")
        XCTAssertEqual(detail.summary.coverUrl, pages[0].absoluteString)
    }
    func testFailedImportDoesNotPublishPartialBookOrModifyExistingBook() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try LocalLibrary(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("one.jpg")
        try Data([1]).write(to: source)
        let book = try library.importImages(title: "保留", files: [source])
        XCTAssertThrowsError(try library.importImages(title: "失败", files: [source, root.appendingPathComponent("missing.jpg")]))
        XCTAssertEqual(try library.books(), [book])
        XCTAssertThrowsError(try library.importImages(title: "空", files: []))
    }
    func testManifestCannotEscapeItsBookDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try LocalLibrary(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let book = LocalBook(id: UUID().uuidString, title: "无效", createdAt: 0, pages: ["../private.jpg"])
        XCTAssertThrowsError(try library.pageURLs(for: book))
    }
    func testOversizedImageIsRejectedBeforeBookIsPublished() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try LocalLibrary(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("large.jpg")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 128 * 1024 * 1024 + 1)
        try handle.close()
        XCTAssertThrowsError(try library.importImages(title: "大图", files: [file])) { error in
            guard case LocalLibraryError.imageTooLarge = error else { return XCTFail("unexpected error: \(error)") }
        }
        XCTAssertTrue(try library.books().isEmpty)
        XCTAssertEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, 128 * 1024 * 1024 + 1)
    }

    func testAndroidSingleImageByteBoundaryIsAcceptedAndPreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"))
        let file = root.appendingPathComponent("boundary.jpg")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 128 * 1024 * 1024)
        try handle.close()
        let book = try library.importImages(title: "边界", files: [file])
        let copy = try XCTUnwrap(library.pageURLs(for: book).first)
        XCTAssertEqual(try copy.resourceValues(forKeys: [.fileSizeKey]).fileSize, 128 * 1024 * 1024)
        XCTAssertEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, 128 * 1024 * 1024)
        XCTAssertEqual(try library.books(), [book])
    }

    func testCancellationDuringCopyRemovesStagingAndPreservesSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("large.jpg")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 4 * 1024 * 1024)
        try handle.close()
        let secondReadStarted = expectation(description: "second copy chunk started")
        let reader = BlockingLocalCopyReader(blocked: secondReadStarted)
        let library = try LocalLibrary(directory: root.appendingPathComponent("library"), readChunk: { handle, count in
            try reader.read(handle, count: count)
        })

        let task = Task.detached(priority: .background) {
            try library.importImages(title: "复制中取消", files: [file])
        }
        await fulfillment(of: [secondReadStarted], timeout: 2)
        let staging = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: library.directory, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent.hasPrefix(".import-") }))
        let partialSize = try XCTUnwrap(staging.appendingPathComponent("0.jpg").resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertGreaterThan(partialSize, 0)
        XCTAssertLessThan(partialSize, 4 * 1024 * 1024)
        task.cancel()
        reader.resume()

        do {
            _ = try await task.value
            XCTFail("复制期间取消不应发布书籍")
        } catch {
            XCTAssertTrue(error is CancellationError, "unexpected error: \(error)")
        }
        XCTAssertTrue(try library.books().isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path), [])
        XCTAssertEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, 4 * 1024 * 1024)
    }
}

private final class BlockingLocalCopyReader: @unchecked Sendable {
    private let blocked: XCTestExpectation
    private let semaphore = DispatchSemaphore(value: 0)
    private var reads = 0

    init(blocked: XCTestExpectation) { self.blocked = blocked }

    func read(_ handle: FileHandle, count: Int) throws -> Data? {
        let data = try handle.read(upToCount: count)
        reads += 1
        if reads == 2 {
            blocked.fulfill()
            semaphore.wait()
        }
        return data
    }

    func resume() { semaphore.signal() }
}
