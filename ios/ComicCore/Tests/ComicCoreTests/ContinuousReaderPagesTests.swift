import XCTest
@testable import ComicCore

final class ContinuousReaderPagesTests: XCTestCase {
    private let first = Chapter(chapterId: "first", title: "第一章", url: "https://fixture.invalid/1")
    private let second = Chapter(chapterId: "second", title: "第二章", url: "https://fixture.invalid/2")

    func testCrossChapterPositionAndSeekStayLocalEvenWhenImageURLsRepeat() throws {
        var strip = ContinuousReaderPages()
        XCTAssertTrue(strip.append(chapter: first, imageURLs: ["shared.png", "1-last.png"]))
        XCTAssertTrue(strip.append(chapter: second, imageURLs: ["shared.png", "2-middle.png", "2-last.png"]))
        let location = try XCTUnwrap(strip.location(at: 3, offset: 0.37))
        XCTAssertEqual(location.chapter, second)
        XCTAssertEqual(location.position, ReaderPosition(imageIndex: 1, offset: 0.37))
        XCTAssertEqual(location.imageURLs.count, 3)
        XCTAssertEqual(strip.globalIndex(for: second, position: location.position), 3)
        XCTAssertEqual(strip.globalIndex(for: first, position: ReaderPosition(imageIndex: 1, offset: 0)), 1)
        XCTAssertEqual(strip.location(at: 2)?.position.imageIndex, 0)
        XCTAssertEqual(strip.imageURLs.count, 5)
    }

    func testEmptyOrRepeatedChapterCannotRemoveOrDuplicateReadablePages() {
        var strip = ContinuousReaderPages()
        XCTAssertTrue(strip.append(chapter: first, imageURLs: ["1.png", "2.png"]))
        XCTAssertFalse(strip.append(chapter: second, imageURLs: []))
        XCTAssertEqual(strip.lastChapter, first)
        XCTAssertFalse(strip.append(chapter: first, imageURLs: ["unexpected.png"]))
        let renamed = Chapter(chapterId: first.chapterId, title: "新标题", url: "https://fixture.invalid/new-route")
        XCTAssertFalse(strip.append(chapter: renamed, imageURLs: ["unexpected.png"]))
        XCTAssertEqual(strip.imageURLs, ["1.png", "2.png"])
        XCTAssertTrue(strip.append(chapter: second, imageURLs: ["3.png"]))
        XCTAssertEqual(strip.lastChapter, second)
    }

    func testExpandedOrReorderedDirectoryResolvesUsingChapterIdentity() throws {
        var strip = ContinuousReaderPages()
        XCTAssertTrue(strip.append(chapter: second, imageURLs: ["a.png", "b.png"]))
        let location = try XCTUnwrap(strip.location(at: 1, offset: 0.2))
        var session = ReaderSession(chapterCount: 1, chapterIndex: 0)
        let renamed = Chapter(chapterId: second.chapterId, title: "第二章修订", url: second.url)
        XCTAssertTrue(session.loaded(chapter: location.chapter, in: [first, renamed], imageCount: location.imageURLs.count, position: location.position))
        XCTAssertEqual(session.chapterIndex, 1)
        XCTAssertEqual(session.imageIndex, 1)
        XCTAssertEqual(strip.globalIndex(for: renamed, position: location.position), 1)
        XCTAssertTrue(session.loaded(chapter: location.chapter, in: [renamed, first], imageCount: location.imageURLs.count, position: location.position))
        XCTAssertEqual(session.chapterIndex, 0)
        XCTAssertNil(strip.globalIndex(for: first, position: location.position))
    }

    func testLinkedPageAndTailIdentityBelongToTheirOwnChapter() throws {
        let book = UUID().uuidString
        let a = UUID().uuidString, b = UUID().uuidString, c = UUID().uuidString
        func page(_ id: String) throws -> String {
            // Use the production URL encoder rather than a made-up linked URL.
            try LinkedFolderPageURL.make(bookID: book, pageID: id).absoluteString
        }
        var strip = ContinuousReaderPages()
        XCTAssertTrue(try strip.append(chapter: first, imageURLs: [page(a), page(b)]))
        XCTAssertTrue(try strip.append(chapter: second, imageURLs: [page(c)]))
        let location = try XCTUnwrap(strip.location(at: 1, atEnd: true))
        XCTAssertEqual(location.position.linkedPageID, b)
        XCTAssertEqual(location.position.linkedTailID, b)
        XCTAssertTrue(location.position.isAtEnd(in: location.imageURLs))
        XCTAssertFalse(location.position.isAtEnd(in: strip.imageURLs))
        var refreshed = ContinuousReaderPages()
        XCTAssertTrue(try refreshed.append(chapter: first, imageURLs: [page(b), page(a)]))
        XCTAssertEqual(refreshed.globalIndex(for: first, position: location.position), 0)
        XCTAssertFalse(location.position.isAtEnd(in: refreshed.imageURLs))
    }

    func testBoundaryAndLegacyPositionNeverSelectAnotherChapter() {
        var strip = ContinuousReaderPages()
        XCTAssertNil(strip.location(at: 0))
        XCTAssertTrue(strip.append(chapter: first, imageURLs: ["a", "b"]))
        XCTAssertTrue(strip.append(chapter: second, imageURLs: ["c"]))
        XCTAssertNil(strip.location(at: -1))
        XCTAssertNil(strip.location(at: 3))
        XCTAssertEqual(strip.globalIndex(for: first, position: ReaderPosition(imageIndex: 999, offset: 1)), 1)
        XCTAssertEqual(strip.globalIndex(for: second, position: ReaderPosition(imageIndex: 999, offset: 1)), 2)
        XCTAssertEqual(strip.location(at: 2)?.position.imageIndex, 0)
    }
}
