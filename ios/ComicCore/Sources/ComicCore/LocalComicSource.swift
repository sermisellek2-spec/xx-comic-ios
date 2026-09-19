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
        return ComicDetail(summary: try library.summary(for: book), author: "", status: "本地漫画",
                           description: "\(book.pages.count) 页", latestChapter: "", chapters: [])
    }
    public func chapters(comicId: String) async throws -> [Chapter] {
        try Task.checkCancellation()
        let book = try library.book(id: comicId)
        return [Chapter(chapterId: book.id, title: book.title, url: book.id)]
    }
    public func chapter(url: String) async throws -> ChapterPage {
        try Task.checkCancellation()
        let book = try library.book(id: url)
        return ChapterPage(chapterId: book.id, title: book.title, nextPageUrl: "", imageUrls: try library.pageURLs(for: book).map(\.absoluteString))
    }
    public func filterGroups() async throws -> [SourceFilterGroup] { [] }
    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { try await latest(page: page) }
}
