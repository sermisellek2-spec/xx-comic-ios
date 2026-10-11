import Foundation

public enum ComicDirectoryError: LocalizedError, Equatable {
    case empty

    public var errorDescription: String? { "暂无章节，请稍后重试" }
}

public extension ComicDetail {
    func ensuringChapters(load: () async throws -> [Chapter]) async throws -> ComicDetail {
        try Task.checkCancellation()
        if !chapters.isEmpty { return self }
        let loaded = try await load()
        try Task.checkCancellation()
        guard !loaded.isEmpty else { throw ComicDirectoryError.empty }
        return ComicDetail(summary: summary, author: author, status: status,
                           description: description, latestChapter: latestChapter,
                           chapters: loaded)
    }
}
