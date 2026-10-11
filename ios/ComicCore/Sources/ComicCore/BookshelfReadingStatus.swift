import Foundation

/// Presentation follows Android's calculateOnlineUnreadCount/resolveOnlineLatestChapter.
/// Missing directory evidence stays unknown; an update flag is never used as a count.
public struct BookshelfReadingStatus: Equatable, Sendable {
    public let unreadCount: Int
    public let latestChapter: String
    public let readingDescription: String

    public init(comic: ComicSummary, reading: ReadingRecord?, revision: FavoriteRevision?, detail: ComicDetail? = nil) {
        let total: Int
        if let detail, !detail.chapters.isEmpty { total = detail.chapters.count }
        else { total = revision?.chapterCount ?? -1 }
        unreadCount = BookshelfLayoutHelper.calculateOnlineUnreadCount(totalChapters: total, savedChapter: reading?.chapterIndex ?? 0, hasReadHistory: reading != nil)
        latestChapter = [detail?.latestChapter, comic.latestChapter, revision?.latestChapterName, detail?.chapters.last?.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        readingDescription = reading?.chapter.title ?? "未开始阅读"
    }
}
