import XCTest
@testable import ComicCore

final class TextReadingTests: XCTestCase {
    private let comic = ComicSummary(sourceId: "local", comicId: "book", title: "文字书")
    private let chapter = Chapter(chapterId: "c2", title: "第二章", url: "OEBPS/chapter2.xhtml")

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func defaults() -> UserDefaults {
        let name = "TextReadingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func locator(chapterIndex: Int = 2, bookID: String = "book", href: String = "OEBPS/chapter2.xhtml") -> TextLocator {
        TextLocator(bookID: bookID, chapterIndex: chapterIndex, spineIndex: 5,
                    resourceHref: href, anchorID: "section_1", scrollPercentage: 0.45, charOffset: 120)
    }

    func testDefaultPreferencesAndIndependentPersistenceAcrossStores() {
        let defaults = defaults()
        let store = TextReaderPreferencesStore(defaults: defaults)
        let initial = store.load()
        XCTAssertEqual(initial.fontSize, 18)
        XCTAssertEqual(initial.lineHeight, 1.75)
        XCTAssertEqual(initial.theme, .dark)
        XCTAssertFalse(initial.pagedMode)
        var manga = ReaderPreferences()
        manga.theme = .light
        manga.layout = .paged
        ReaderPreferencesStore(defaults: defaults).save(manga)
        var settings = initial
        settings.fontSize = 24
        settings.lineHeight = 2
        settings.theme = .sepia
        settings.pagedMode = true
        store.save(settings)
        XCTAssertEqual(TextReaderPreferencesStore(defaults: defaults).load(), settings)
        XCTAssertEqual(ReaderPreferencesStore(defaults: defaults).load(), manga)
        XCTAssertEqual(defaults.integer(forKey: "text.reader.fontSize"), 24)
        XCTAssertEqual(defaults.double(forKey: "text.reader.lineHeight"), 2)
        XCTAssertEqual(defaults.integer(forKey: "text.reader.theme"), 1)
        XCTAssertTrue(defaults.bool(forKey: "text.reader.pagedMode"))
        manga.theme = .dark
        ReaderPreferencesStore(defaults: defaults).save(manga)
        XCTAssertEqual(store.load(), settings)
    }

    func testPreferencesNormalizeBothLoadedAndSavedValues() {
        let defaults = defaults()
        let store = TextReaderPreferencesStore(defaults: defaults)
        for (font, height, wantedFont, wantedHeight) in [(-1, -1.0, 12, 1.2), (99, 9.0, 32, 2.5),
                                                      (18, Double.nan, 18, 1.75), (18, .infinity, 18, 1.75),
                                                      (18, -.infinity, 18, 1.75)] {
            defaults.set(font, forKey: "text.reader.fontSize")
            defaults.set(height, forKey: "text.reader.lineHeight")
            defaults.set(99, forKey: "text.reader.theme")
            XCTAssertEqual(store.load().fontSize, wantedFont)
            XCTAssertEqual(store.load().lineHeight, wantedHeight)
            XCTAssertEqual(store.load().theme, .dark)
            var settings = TextReaderPreferences()
            settings.fontSize = font
            settings.lineHeight = height
            store.save(settings)
            XCTAssertEqual(defaults.integer(forKey: "text.reader.fontSize"), wantedFont)
            XCTAssertEqual(defaults.double(forKey: "text.reader.lineHeight"), wantedHeight)
        }
        for (raw, theme) in [(0, TextReaderTheme.light), (1, .sepia), (2, .dark)] {
            defaults.set(raw, forKey: "text.reader.theme")
            XCTAssertEqual(store.load().theme, theme)
        }
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

    func testOldLibraryJSONCanAddTextPositionWithoutLosingMangaPosition() throws {
        let folder = try directory()
        let json = """
        {"version":1,"entries":{"5:localbook":{"summary":{"sourceId":"local","comicId":"book","title":"文字书","coverUrl":"","subtitle":"","tags":[]},"favoriteAt":7,"positions":{"c2":{"imageIndex":8,"offset":0.3,"atEnd":false}}}}}
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent("library.json"))
        let store = try LibraryStore(directory: folder)
        XCTAssertNil(store.entry(for: comic)?.textPositions)
        try store.saveTextReading(comic, chapter: chapter, chapterIndex: 2, locator: locator(), now: 123)
        let restored = try LibraryStore(directory: folder)
        XCTAssertEqual(restored.textPosition(for: comic, chapterID: chapter.chapterId), locator())
        XCTAssertEqual(restored.entry(for: comic)?.favoriteAt, 7)
        XCTAssertEqual(restored.position(for: comic, chapterID: "c2"), ReaderPosition(imageIndex: 8, offset: 0.3))
    }

    func testTwoTextChaptersSurviveMangaUpdatesAndRemovingFavorite() throws {
        let folder = try directory()
        let store = try LibraryStore(directory: folder)
        let firstChapter = Chapter(chapterId: "c1", title: "第一章", url: "chapter1.xhtml")
        try store.setFavorite(comic, favorite: true, now: 7)
        try store.saveTextReading(comic, chapter: firstChapter, chapterIndex: 0, locator: locator(chapterIndex: 0), now: 100)
        try store.saveTextReading(comic, chapter: chapter, chapterIndex: 2, locator: locator(), now: 123)
        XCTAssertEqual(store.entry(for: comic)?.favoriteAt, 7)
        XCTAssertEqual(store.entry(for: comic)?.reading?.chapter, chapter)
        XCTAssertEqual(store.entry(for: comic)?.reading?.chapterIndex, 2)
        XCTAssertEqual(store.entry(for: comic)?.reading?.updatedAt, 123)
        XCTAssertEqual(store.entry(for: comic)?.reading?.position, ReaderPosition(imageIndex: 0, offset: 0))
        XCTAssertTrue(store.entry(for: comic)?.positions.isEmpty == true)
        let imagePosition = ReaderPosition(imageIndex: 9, offset: 0.2)
        try store.saveReading(comic, chapter: chapter, chapterIndex: 2, position: imagePosition, now: 150)
        try store.setFavorite(comic, favorite: false, now: 200)
        let restored = try LibraryStore(directory: folder)
        XCTAssertTrue(restored.favorites.isEmpty)
        XCTAssertEqual(restored.history.count, 1)
        XCTAssertEqual(restored.textPosition(for: comic, chapterID: "c1"), locator(chapterIndex: 0))
        XCTAssertEqual(restored.textPosition(for: comic, chapterID: "c2"), locator())
        XCTAssertEqual(restored.position(for: comic, chapterID: "c2"), imagePosition)
    }

    func testTextSaveRejectsMismatchedIdentityChapterAndMissingResourceWithoutMutation() throws {
        let folder = try directory()
        let store = try LibraryStore(directory: folder)
        try store.saveTextReading(comic, chapter: chapter, chapterIndex: 2, locator: locator(), now: 123)
        let before = store.entry(for: comic)
        let file = folder.appendingPathComponent("library.json")
        let data = try Data(contentsOf: file)
        let online = ComicSummary(sourceId: "online", comicId: "book", title: "同名书")
        let cases: [(ComicSummary, TextLocator, LibraryError)] = [
            (online, locator(), .textReadingRequiresLocalBook),
            (comic, locator(bookID: "other"), .textBookMismatch),
            (comic, locator(chapterIndex: 1), .textChapterMismatch),
            (comic, locator(href: ""), .missingTextResource)
        ]
        for (summary, value, expected) in cases {
            XCTAssertThrowsError(try store.saveTextReading(summary, chapter: chapter, chapterIndex: 2, locator: value)) { error in
                XCTAssertEqual(error as? LibraryError, expected)
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
            XCTAssertEqual(store.entry(for: comic), before)
            XCTAssertNil(store.entry(for: online))
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
        try store.saveTextReading(comic, chapter: chapter, chapterIndex: -1, locator: locator(chapterIndex: 0))
        XCTAssertEqual(store.entry(for: comic)?.reading?.chapterIndex, 0)
    }

    func testFailedTextWriteLeavesWholeInMemoryEntryUnchanged() throws {
        let folder = try directory()
        let store = try LibraryStore(directory: folder)
        try store.setFavorite(comic, favorite: true, now: 7)
        try store.saveTextReading(comic, chapter: chapter, chapterIndex: 2, locator: locator(), now: 123)
        let before = store.entry(for: comic)
        try FileManager.default.removeItem(at: folder)
        try Data("not a directory".utf8).write(to: folder)
        XCTAssertThrowsError(try store.saveTextReading(comic, chapter: chapter, chapterIndex: 3, locator: locator(chapterIndex: 3), now: 999))
        XCTAssertEqual(store.entry(for: comic), before)
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
