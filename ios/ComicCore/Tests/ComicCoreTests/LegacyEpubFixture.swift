import Foundation
@testable import ComicCore

/// Writes the pre-removal persisted format directly, without enabling text imports.
enum LegacyEpubFixture {
    static func persist(library: LocalLibrary, archive: URL, title: String,
                        kindleSource: URL? = nil) throws -> LocalBook {
        let publication = try EpubParser.parse(archive: archive)
        let id = UUID().uuidString, pages = publication.spine.indices.map { "spine-\($0)" }
        let chapters = try publication.chapterRanges().enumerated().map { index, range in
            LocalBookChapter(id: id + "_ch_\(index)", title: range.title, pages: Array(pages[range.startIndex..<range.endIndex]))
        }
        let book = LocalBook(id: id, title: title, createdAt: 1, pages: pages, chapters: chapters,
                             epub: publication, kindleFormat: kindleSource == nil ? nil : .mobi)
        let folder = library.directory.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: archive, to: folder.appendingPathComponent("content.epub"))
        if let kindleSource { try FileManager.default.copyItem(at: kindleSource, to: folder.appendingPathComponent("source.kindle")) }
        try JSONEncoder().encode(book).write(to: folder.appendingPathComponent("book.json"))
        return try library.book(id: id)
    }
}
