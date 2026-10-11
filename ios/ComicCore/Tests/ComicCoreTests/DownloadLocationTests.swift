import XCTest
@testable import ComicCore

private struct LocationSource: DownloadSourceResolverProtocol {
    func resolveChapter(sourceId: String, url: String) async throws -> ChapterPage {
        ChapterPage(chapterId: "c1", title: "第一话", imageUrls: ["https://fixture.invalid/page"])
    }
    func resolveReferer(sourceId: String, chapterUrl: String) -> String { "" }
    func fetchCover(sourceId: String, coverUrl: String, destination: URL, check: @escaping () throws -> Void) async throws { try check() }
}
private struct LocationFetcher: DownloadImageFetcherProtocol {
    func fetch(sourceId: String, url: String, referer: String, destination: URL, check: @escaping () throws -> Void) async throws -> (bytes: Int64, hash: String) {
        try check(); let data = Data("actual offline fixture".utf8)
        try data.write(to: destination); try check()
        return (Int64(data.count), DownloadModels.sha256Hex(data))
    }
}
final class DownloadLocationTests: XCTestCase {
    private let access = DownloadStorageLocations.BookmarkAccess(create: { Data($0.path.utf8) }, resolve: {
        guard let path = String(data: $0, encoding: .utf8) else { throw DownloadLocationError.invalidStore }
        return URL(fileURLWithPath: path)
    }, start: { _ in true }, stop: { _ in })
    private func fixture() throws -> (URL, URL, URL, DownloadStorageLocations) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let internalRoot = base.appendingPathComponent("private")
        let external = base.appendingPathComponent("用户原目录")
        try FileManager.default.createDirectory(at: internalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let service = try DownloadStorageLocations(file: base.appendingPathComponent("locations.json"), privateDirectory: internalRoot, access: access)
        return (base, internalRoot, external, service)
    }
    private func detail(_ id: String = "comic") -> ComicDetail {
        ComicDetail(summary: ComicSummary(sourceId: "source", comicId: id, title: "作品/同名"), author: "", status: "", description: "", latestChapter: "",
                    chapters: [Chapter(chapterId: "c1", title: "第一话", url: "https://fixture.invalid/chapter")])
    }
    private func task(_ id: String = "comic") throws -> DownloadTask {
        DownloadTask(id: try DownloadModels.key("source", id, "c1"), bookId: try DownloadModels.bookId(source: "source", comic: id),
            sourceId: "source", comicId: id, chapterId: "c1", title: "第一话")
    }
    private func runtime(_ root: URL, locations: DownloadStorageLocations) throws -> DownloadRuntime {
        DownloadRuntime(store: try DownloadStore(directory: root), downloadsDirectory: root,
                        imageFetcher: LocationFetcher(), sourceResolver: LocationSource(), storageLocations: locations)
    }
    private func download(_ detail: ComicDetail, runtime: DownloadRuntime) async throws {
        let done = expectation(description: "files and completion published")
        runtime.onTaskCompleted = { _ in done.fulfill() }
        try await runtime.enqueueWithLocation(detail: detail, selectedChapterIds: ["c1"])
        await fulfillment(of: [done], timeout: 5)
    }
    func testSelectionPersistsPermissionBookmarkAndProbeIsRemoved() throws {
        let (base, internalRoot, external, locations) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let id = try locations.select(directory: external)
        let restored = try DownloadStorageLocations(file: base.appendingPathComponent("locations.json"), privateDirectory: internalRoot, access: access)
        XCTAssertEqual(restored.selectedID, id)
        XCTAssertEqual(restored.locations.first?.name, "用户原目录")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: external.appendingPathComponent("XXComic/downloads").path), [])
    }
    func testRealQueueWritesCustomPathAndRestartReadsOriginalAfterDefaultChanges() async throws {
        let (base, internalRoot, external, locations) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        try locations.select(directory: external)
        let runtime = try runtime(internalRoot, locations: locations)
        try await download(detail(), runtime: runtime)
        let first = try task()
        let directory = try locations.chapterDirectory(first)
        XCTAssertTrue(directory.path.hasPrefix(external.path + "/XXComic/downloads/"))
        XCTAssertTrue(directory.path.contains("作品_同名_source")); XCTAssertTrue(directory.lastPathComponent.contains("第一话"))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("0.img")), Data("actual offline fixture".utf8))
        try locations.useDefault()
        try await download(detail("second"), runtime: runtime)
        let second = try task("second")
        XCTAssertTrue(try locations.bookDirectory(bookID: second.bookId).path.hasPrefix(internalRoot.path + "/"))
        let restored = try DownloadStorageLocations(file: base.appendingPathComponent("locations.json"), privateDirectory: internalRoot, access: access)
        let reopened = try self.runtime(internalRoot, locations: restored)
        let chapter = try XCTUnwrap(reopened.localChapter(detail: detail(), chapterIndex: 0))
        XCTAssertEqual(chapter.imageUrls, [directory.appendingPathComponent("0.img").absoluteString])
    }
    func testLegacyPrivateBookKeepsIdentityAndFilesWhenNewDefaultIsExternal() throws {
        let (base, internalRoot, external, locations) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let task = try task(), old = internalRoot.appendingPathComponent(task.bookId, isDirectory: true).appendingPathComponent(task.id, isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: old.appendingPathComponent("0.img"))
        try locations.select(directory: external); try locations.prepare(task, comicTitle: "作品")
        XCTAssertEqual(try locations.chapterDirectory(task), old)
        XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent("0.img")), Data("legacy".utf8))
    }
    func testReauthorizationRejectsDifferentFolderAndKeepsOriginalMapping() throws {
        let (base, _, external, locations) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let id = try locations.select(directory: external), task = try task()
        try locations.prepare(task, comicTitle: "作品")
        let original = try locations.bookDirectory(bookID: task.bookId)
        let other = base.appendingPathComponent("another"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        XCTAssertThrowsError(try locations.select(directory: other, reauthorizing: id))
        XCTAssertEqual(locations.selectedID, id); XCTAssertEqual(try locations.bookDirectory(bookID: task.bookId), original)
        XCTAssertEqual(try locations.select(directory: external, reauthorizing: id), id)
    }
    func testPermissionLossRejectsEnqueueWithoutFallingBackOrChangingRecords() async throws {
        let (base, internalRoot, external, locations) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        try locations.select(directory: external)
        let denied = DownloadStorageLocations.BookmarkAccess(create: access.create, resolve: access.resolve, start: { _ in false }, stop: { _ in })
        let restored = try DownloadStorageLocations(file: base.appendingPathComponent("locations.json"), privateDirectory: internalRoot, access: denied)
        let runtime = try runtime(internalRoot, locations: restored)
        do { try await runtime.enqueueWithLocation(detail: detail(), selectedChapterIds: ["c1"]); XCTFail("Lost permission must be visible") }
        catch { XCTAssertTrue(error.localizedDescription.contains("重新授权")) }
        XCTAssertTrue(runtime.store.list().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: internalRoot.appendingPathComponent(try task().bookId).path))
    }
    func testUnknownExternalFilePreventsWholeDeletionThenKnownCopyDeletesOnlyItsBook() async throws {
        let (base, internalRoot, external, locations) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        try locations.select(directory: external); let runtime = try runtime(internalRoot, locations: locations)
        try await download(detail(), runtime: runtime)
        let first = try task(), book = try locations.bookDirectory(bookID: first.bookId)
        let original = book.appendingPathComponent("用户原文件.txt"); try Data("keep".utf8).write(to: original)
        do { try await runtime.deleteBook(bookId: first.bookId); XCTFail("Unknown original must survive") } catch { }
        XCTAssertEqual(try Data(contentsOf: original), Data("keep".utf8)); XCTAssertEqual(runtime.store.get(id: first.id)?.state, .completed)
        try await download(detail("second"), runtime: runtime)
        let second = try task("second"), secondBook = try locations.bookDirectory(bookID: second.bookId)
        try await runtime.deleteBook(bookId: second.bookId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondBook.path)); XCTAssertNil(runtime.store.get(id: second.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: book.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }
    func testSymbolicLinkBelowSelectedRootAndCorruptMappingArePreserved() throws {
        let (base, internalRoot, external, locations) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let outside = base.appendingPathComponent("outside"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: outside.appendingPathComponent("original"))
        try FileManager.default.createSymbolicLink(at: external.appendingPathComponent("XXComic"), withDestinationURL: outside)
        XCTAssertThrowsError(try locations.select(directory: external))
        XCTAssertEqual(try Data(contentsOf: outside.appendingPathComponent("original")), Data("keep".utf8))
        let corrupt = Data("{broken original record".utf8), file = base.appendingPathComponent("locations.json")
        try corrupt.write(to: file)
        XCTAssertThrowsError(try DownloadStorageLocations(file: file, privateDirectory: internalRoot, access: access))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
    func testCancelledPreparationAndVirtualTraversalCannotSelectPaths() async throws {
        let (base, _, _, locations) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let task = try task()
        XCTAssertThrowsError(try locations.bookDirectory(bookID: "../"))
        XCTAssertThrowsError(try locations.pageURL(DownloadPage(index: 0, url: "", path: "../original", hash: "", bytes: 0), task: task))
        let cancelled = Task { () throws -> Void in
            withUnsafeCurrentTask { $0?.cancel() }
            try locations.prepare(task, comicTitle: "作品")
        }
        do { try await cancelled.value; XCTFail("Cancelled task must not prepare") } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("locations.json").path))
    }
}
