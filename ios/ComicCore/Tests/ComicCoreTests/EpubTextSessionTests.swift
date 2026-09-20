import Foundation
import XCTest
import ZIPFoundation
@testable import ComicCore

final class EpubTextSessionTests: XCTestCase {
    private func book() throws -> LocalBook {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("real.epub")
        let files = [
            "META-INF/container.xml": "<container><rootfile full-path='OPS/book.opf'/></container>",
            "OPS/book.opf": "<package><metadata/><manifest><item id='a' href='a.xhtml' media-type='application/xhtml+xml'/><item id='b' href='b.xhtml' media-type='application/xhtml+xml'/><item id='image' href='image.png' media-type='image/png'/><item id='nav' href='nav.xhtml' media-type='application/xhtml+xml' properties='nav'/></manifest><spine><itemref idref='a'/><itemref idref='b'/><itemref idref='image'/><itemref idref='a'/></spine></package>",
            "OPS/nav.xhtml": "<html><nav><ol><li><a href='a.xhtml'>第一章</a></li><li><a href='image.png'>第二章</a></li></ol></nav></html>",
            "OPS/a.xhtml": "<html><body><p id='a'>正文甲</p></body></html>",
            "OPS/b.xhtml": "<html><body><p>正文乙</p></body></html>",
            "OPS/image.png": "image probe fixture"
        ]
        let archive = try Archive(url: url, accessMode: .create)
        for (path, value) in files {
            let data = Data(value.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), provider: {
                position, count in data.subdata(in: Int(position)..<min(Int(position) + count, data.count))
            })
        }
        return try LocalLibrary(directory: root.appendingPathComponent("library")).importEpub(title: "测试", archive: url) { _ in true }
    }

    func testEverySpineIncludingMixedImageAndRepeatedHrefIsReachable() throws {
        let book = try book()
        XCTAssertEqual(book.chapters?.map(\.pages), [["spine-0", "spine-1"], ["spine-2", "spine-3"]])
        var session = try EpubTextSession(book: book, chapterIndex: -1, locator: nil)
        XCTAssertEqual(session.spineIndex, 0)
        XCTAssertFalse(session.moveSpine(delta: -1))
        XCTAssertFalse(session.moveSpine(delta: 2))
        XCTAssertTrue(session.moveSpine(delta: 1))
        XCTAssertEqual(session.spineIndex, 1)
        XCTAssertEqual(session.chapterIndex, 0)
        XCTAssertTrue(session.moveSpine(delta: 1))
        XCTAssertEqual(session.entry.mediaType, "image/png")
        XCTAssertEqual(session.chapterIndex, 1)
        XCTAssertTrue(session.moveSpine(delta: 1))
        XCTAssertEqual(session.entry.fullZipPath, "OPS/a.xhtml")
        XCTAssertFalse(session.moveSpine(delta: 1))
        XCTAssertEqual(session.spineIndex, 3)
        XCTAssertTrue(session.moveSpine(delta: -1))
        try session.selectChapter(0)
        XCTAssertEqual(session.spineIndex, 0)
        XCTAssertThrowsError(try session.selectChapter(2))
        XCTAssertEqual(session.spineIndex, 0)
    }

    func testLocatorMustMatchBookChapterIndexAndPathIncludingDuplicateHref() throws {
        let book = try book()
        let valid = TextLocator(bookID: book.id, chapterIndex: 1, spineIndex: 3, resourceHref: "OPS/a.xhtml", anchorID: "a", scrollPercentage: 0.6)
        var restored = try EpubTextSession(book: book, chapterIndex: 1, locator: valid)
        XCTAssertEqual(restored.spineIndex, 3)
        XCTAssertTrue(restored.navigate(path: "OPS/a.xhtml"))
        XCTAssertEqual(restored.spineIndex, 3)
        XCTAssertEqual(restored.locator(anchorID: "a", percent: 0.6), valid)
        for locator in [
            TextLocator(bookID: "other", chapterIndex: 1, spineIndex: 3, resourceHref: "OPS/a.xhtml"),
            TextLocator(bookID: book.id, chapterIndex: 0, spineIndex: 3, resourceHref: "OPS/a.xhtml"),
            TextLocator(bookID: book.id, chapterIndex: 1, spineIndex: 0, resourceHref: "OPS/a.xhtml"),
            TextLocator(bookID: book.id, chapterIndex: 1, spineIndex: 99, resourceHref: "OPS/a.xhtml"),
            TextLocator(bookID: book.id, chapterIndex: 1, spineIndex: 3, resourceHref: "OPS/b.xhtml")
        ] {
            XCTAssertEqual(try EpubTextSession(book: book, chapterIndex: 99, locator: locator).spineIndex, 2)
        }
        for path in ["OPS/../OPS/a.xhtml", "/OPS/a.xhtml", "OPS/a.xhtml#x", "https://example.com", "OPS/missing"] {
            XCTAssertFalse(restored.navigate(path: path))
            XCTAssertEqual(restored.spineIndex, 3)
        }
        XCTAssertTrue(restored.navigate(path: "OPS/b.xhtml"))
        XCTAssertEqual(restored.chapterIndex, 0)
        XCTAssertTrue(restored.navigate(path: "OPS/a.xhtml"))
        XCTAssertEqual(restored.spineIndex, 0)
    }

    func testMalformedPartitionsAndMissingPublicationAreRejected() throws {
        let valid = try book()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        let original = json
        for mutation in 0..<8 {
            json = original
            if mutation == 0 { json.removeValue(forKey: "epub") }
            if mutation == 1 { json["chapters"] = [["id": "bad", "title": "bad", "pages": ["spine-0"]]] }
            if mutation == 2 { json["pages"] = ["spine-0", "spine-0", "spine-2", "spine-3"] }
            if mutation == 3 || mutation == 4 {
                var epub = json["epub"] as! [String: Any]
                if mutation == 3 { epub["hasDrm"] = true } else { epub["spine"] = [] }
                json["epub"] = epub
            }
            if mutation == 5 { json.removeValue(forKey: "chapters") }
            if mutation == 6 { json["chapters"] = [["id": "duplicate", "title": "a", "pages": ["spine-0", "spine-1"]], ["id": "duplicate", "title": "b", "pages": ["spine-2", "spine-3"]]] }
            if mutation == 7 { json["chapters"] = [["id": "a", "title": "a", "pages": ["spine-1", "spine-0"]], ["id": "b", "title": "b", "pages": ["spine-2", "spine-3"]]] }
            let invalid = try JSONDecoder().decode(LocalBook.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertThrowsError(try EpubTextSession(book: invalid, chapterIndex: 0, locator: nil))
        }
    }
}
