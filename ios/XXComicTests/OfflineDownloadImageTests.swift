import XCTest
import UIKit
import ComicCore
@testable import XXComic

@MainActor
final class OfflineDownloadImageTests: XCTestCase {
    func testDownloadedFileOutsideLocalImportsDecodesThroughRecordedDownloadAccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DownloadStore(directory: root)
        let runtime = DownloadRuntime(store: store, downloadsDirectory: root)
        let bookID = try DownloadModels.bookId(source: "fixture", comic: "offline")
        let taskID = try DownloadModels.key("fixture", "offline", "chapter")
        let chapter = root.appendingPathComponent(bookID).appendingPathComponent(taskID)
        try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 16), format: format).image {
            UIColor.blue.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        }
        let bytes = try XCTUnwrap(image.pngData()), file = chapter.appendingPathComponent("0.img")
        try bytes.write(to: file)
        store.save(task: DownloadTask(id: taskID, bookId: bookID, sourceId: "fixture", comicId: "offline", chapterId: "chapter", totalPages: 1, donePages: 1, state: .completed))
        store.savePage(task: taskID, page: DownloadPage(index: 0, url: "fixture", path: "\(bookID)/\(taskID)/0.img", hash: DownloadModels.sha256Hex(bytes), bytes: Int64(bytes.count)))

        let view = RemoteImageView(), loaded = expectation(description: "Offline download becomes an actual UIImage")
        view.onLoaded = { _ in loaded.fulfill() }
        view.onFailure = { XCTFail("A completed download must render outside the Local import directory") }
        view.load(file.absoluteString, referer: "", reader: true, localPageImage: { try runtime.offlineImageData(at: $0) })
        await fulfillment(of: [loaded], timeout: 5)
        XCTAssertEqual(view.image?.size, CGSize(width: 8, height: 16))
        XCTAssertFalse(view.needsReload)
    }
}
