import XCTest
@testable import ComicCore

/// Only backward-compatible decoding remains after the user removed text reading.
final class LegacyTextRecordTests: XCTestCase {
    private let comic = ComicSummary(sourceId: "local", comicId: "book", title: "旧文字书")
    private let chapter = Chapter(chapterId: "c2", title: "第二章", url: "OEBPS/chapter2.xhtml")
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func locator(chapterIndex: Int = 2, bookID: String = "book", href: String = "OEBPS/chapter2.xhtml") -> TextLocator {
        TextLocator(bookID: bookID, chapterIndex: chapterIndex, spineIndex: 5, resourceHref: href, anchorID: "section_1", scrollPercentage: 0.45, charOffset: 120)
    }
    func testLegacyPositionsSurviveFavoriteAndMangaUpdatesWithoutAnAutomaticMigration() throws {
        let folder = try directory(), file = folder.appendingPathComponent("library.json")
        let positions = ["c1": locator(chapterIndex: 0), "c2": locator()]
        let entry = LibraryEntry(summary: comic, favoriteAt: 7,
            reading: ReadingRecord(chapter: chapter, chapterIndex: 2, position: ReaderPosition(imageIndex: 0, offset: 0), updatedAt: 123),
            positions: [:], textPositions: positions)
        let entries = try JSONSerialization.jsonObject(with: JSONEncoder().encode(["5:localbook": entry]))
        let original = try JSONSerialization.data(withJSONObject: ["version": 1, "entries": entries])
        try original.write(to: file)
        let store = try LibraryStore(directory: folder)
        XCTAssertEqual(store.entry(for: comic)?.textPositions, positions)
        XCTAssertEqual(try Data(contentsOf: file), original)
        let imagePosition = ReaderPosition(imageIndex: 9, offset: 0.2)
        try store.saveReading(comic, chapter: chapter, chapterIndex: 2, position: imagePosition, now: 150)
        try store.setFavorite(comic, favorite: false)
        let reopened = try LibraryStore(directory: folder)
        XCTAssertEqual(reopened.entry(for: comic)?.textPositions, positions)
        XCTAssertEqual(reopened.position(for: comic, chapterID: "c2"), imagePosition)
        XCTAssertEqual(reopened.history.count, 1); XCTAssertTrue(reopened.favorites.isEmpty)
    }
    func testOldLibraryWithoutTextPositionsStillLoads() throws {
        let folder = try directory(), file = folder.appendingPathComponent("library.json")
        let original = Data("{\"version\":1,\"entries\":{\"5:localbook\":{\"summary\":{\"sourceId\":\"local\",\"comicId\":\"book\",\"title\":\"旧书\",\"coverUrl\":\"\",\"subtitle\":\"\",\"tags\":[]},\"positions\":{}}}}".utf8)
        try original.write(to: file)
        let store = try LibraryStore(directory: folder)
        XCTAssertNil(store.entry(for: comic)?.textPositions)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testLocatorNormalizesConstructorAndDecodedValues() throws {
        for (percentage, wanted) in [(-1.0, 0.0), (2.0, 1.0), (Double.nan, 0.0),
                                     (Double.infinity, 0.0), (-Double.infinity, 0.0)] {
            let value = TextLocator(bookID: "book", chapterIndex: -2, spineIndex: -5,
                                    resourceHref: "chapter.xhtml", scrollPercentage: percentage, charOffset: -10)
            XCTAssertEqual(value.chapterIndex, 0)
            XCTAssertEqual(value.spineIndex, 0)
            XCTAssertEqual(value.charOffset, 0)
            XCTAssertEqual(value.scrollPercentage, wanted)
        }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for (jsonPercentage, wanted) in [("-1", 0.0), ("2", 1.0), ("\"NaN\"", 0.0),
                                       ("\"Infinity\"", 0.0), ("\"-Infinity\"", 0.0)] {
            let json = "{\"chapterIndex\":-2,\"spineIndex\":-5,\"charOffset\":-10,\"scrollPercentage\":\(jsonPercentage)}"
            let value = try decoder.decode(TextLocator.self, from: Data(json.utf8))
            XCTAssertEqual(value.chapterIndex, 0)
            XCTAssertEqual(value.spineIndex, 0)
            XCTAssertEqual(value.charOffset, 0)
            XCTAssertEqual(value.scrollPercentage, wanted)
        }
    }

    func testLocatorAndroidKeysMissingFieldsRoundTripAndCorruptTypes() throws {
        let empty = try JSONDecoder().decode(TextLocator.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, TextLocator(bookID: "", chapterIndex: 0, spineIndex: 0, resourceHref: ""))
        let original = locator()
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["bookId"] as? String, "book")
        XCTAssertEqual(json["anchorId"] as? String, "section_1")
        XCTAssertNil(json["bookID"])
        XCTAssertNil(json["anchorID"])
        XCTAssertEqual(try JSONDecoder().decode(TextLocator.self, from: data), original)
        for json in ["{\"bookId\":5}", "{\"chapterIndex\":\"2\"}", "{\"spineIndex\":false}",
                     "{\"resourceHref\":[]}", "{\"anchorId\":{}}", "{\"scrollPercentage\":\"bad\"}", "{\"charOffset\":1.5}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(TextLocator.self, from: Data(json.utf8))) { error in
                XCTAssertTrue(error is DecodingError)
            }
        }
    }

    func testCorruptTextPositionDoesNotRebuildOrOverwriteLibrary() throws {
        let folder = try directory()
        let file = folder.appendingPathComponent("library.json")
        let json = """
        {"version":1,"entries":{"5:localbook":{"summary":{"sourceId":"local","comicId":"book","title":"文字书","coverUrl":"","subtitle":"","tags":[]},"positions":{},"textPositions":{"c2":{"chapterIndex":"broken"}}}}}
        """
        let original = Data(json.utf8)
        try original.write(to: file)
        XCTAssertThrowsError(try LibraryStore(directory: folder))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
