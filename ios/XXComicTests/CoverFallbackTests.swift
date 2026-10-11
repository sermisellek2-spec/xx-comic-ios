import XCTest
import UIKit
import ComicCore
@testable import XXComic

@MainActor
final class CoverFallbackTests: XCTestCase {
    func testEmptyCoverUsesArtworkInsteadOfAnUnexplainedBlankCard() throws {
        let cover = RemoteImageView()
        cover.contentMode = .scaleAspectFill
        cover.load("", referer: "")
        let artwork = try XCTUnwrap(UIImage(named: "rem_no_image"))
        XCTAssertEqual(try XCTUnwrap(cover.image).pngData(), artwork.pngData())
        XCTAssertEqual(cover.contentMode, .scaleAspectFit)
    }

    func testReaderFailureKeepsItsOwnRetryStateWithoutCoverArtwork() {
        let page = RemoteImageView()
        var failed = false
        page.onFailure = { failed = true }
        page.load("", referer: "", reader: true)
        XCTAssertTrue(failed)
        XCTAssertNil(page.image)
    }

    func testSuccessfulImageReplacesFallbackAndRestoresTheCoverLayout() async throws {
        let cover = RemoteImageView()
        cover.contentMode = .scaleAspectFill
        cover.load("", referer: "")
        let loaded = expectation(description: "Decoded cover becomes visible")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 16), format: format).image {
            UIColor.red.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        }
        let data = try XCTUnwrap(image.pngData())
        cover.onLoaded = { _ in loaded.fulfill() }
        cover.load("xxcomic-epub://cover-fallback/0", referer: "", localPageImage: { _ in data })
        await fulfillment(of: [loaded], timeout: 5)
        XCTAssertEqual(cover.contentMode, .scaleAspectFill)
        XCTAssertEqual(cover.image?.size, CGSize(width: 8, height: 16))
        XCTAssertFalse(cover.needsReload)
    }

    func testLocalCoverUsesItsLibraryInstanceInsideAnIsolatedSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 16), format: format).image {
            UIColor.green.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        }
        let source = root.appendingPathComponent("cover.png")
        try XCTUnwrap(original.pngData()).write(to: source)
        let library = try LocalLibrary(directory: root.appendingPathComponent("session/Local"))
        let book = try library.importImages(title: "实际封面", files: [source])
        let cover = RemoteImageView(); cover.contentMode = .scaleAspectFill
        let loaded = expectation(description: "Local cover decodes through owned library")
        cover.onLoaded = { _ in loaded.fulfill() }
        cover.loadCover(try library.summary(for: book), referer: "", library: library)
        await fulfillment(of: [loaded], timeout: 5)
        XCTAssertEqual(cover.image?.size, original.size)
        XCTAssertEqual(cover.contentMode, .scaleAspectFill)
    }
}
