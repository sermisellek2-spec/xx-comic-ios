import Foundation

public actor LocalComicSource: ComicSource {
    public nonisolated let id = "local"
    public nonisolated let name = "本地书架"
    public nonisolated let referer = ""
    private let library: LocalLibrary
    public init(library: LocalLibrary) { self.library = library }
    public func latest(page: Int) async throws -> [ComicSummary] {
        try Task.checkCancellation()
        return page == 1 ? try library.books().map { try library.summary(for: $0) } : []
    }
    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try await latest(page: page).filter { $0.title.localizedCaseInsensitiveContains(keyword) }
    }
    public func detail(comicId: String) async throws -> ComicDetail {
        try Task.checkCancellation()
        let book = try library.book(id: comicId)
        return ComicDetail(summary: try library.summary(for: book), author: book.epub?.author ?? "", status: book.kindleFormat?.rawValue.uppercased() ?? (book.pdf != nil ? "PDF" : (book.epub == nil ? "本地漫画" : "EPUB")),
                           description: book.epub?.description ?? "\(book.pages.count) 页", latestChapter: "", chapters: [])
    }
    public func chapters(comicId: String) async throws -> [Chapter] {
        try Task.checkCancellation()
        let book = try library.book(id: comicId)
        _ = try library.pageURLs(for: book)
        if let chapters = book.chapters {
            return chapters.enumerated().map { index, chapter in
                Chapter(chapterId: chapter.id, title: chapter.title, url: book.id + "/" + chapter.id, chapterSlot: index)
            }
        }
        return [Chapter(chapterId: book.id, title: book.title, url: book.id)]
    }
    public func chapter(url: String) async throws -> ChapterPage {
        try Task.checkCancellation()
        let parts = url.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { throw LocalLibraryError.invalidBook }
        let book = try library.book(id: String(parts[0]))
        let allURLs = try library.pageURLs(for: book)
        if parts.count == 2 {
            guard let chapter = book.chapters?.first(where: { $0.id == parts[1] }) else { throw LocalLibraryError.invalidBook }
            try requireImagePages(chapter.pages, in: book)
            let pages = Dictionary(uniqueKeysWithValues: zip(book.pages, allURLs))
            return ChapterPage(chapterId: chapter.id, title: chapter.title, nextPageUrl: "", imageUrls: try chapter.pages.map { name in
                guard let url = pages[name] else { throw LocalLibraryError.invalidBook }
                return url.absoluteString
            })
        }
        try requireImagePages(book.pages, in: book)
        return ChapterPage(chapterId: book.id, title: book.title, nextPageUrl: "", imageUrls: allURLs.map(\.absoluteString))
    }
    private func requireImagePages(_ pages: [String], in book: LocalBook) throws {
        guard let publication = book.epub else { return }
        let selected = Set(pages)
        for (index, token) in book.pages.enumerated() where selected.contains(token) {
            guard publication.spine[index].resolvedImageEntry != nil else { throw LocalLibraryError.requiresTextReader }
        }
    }
    public func filterGroups() async throws -> [SourceFilterGroup] { [] }
    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { try await latest(page: page) }
}
