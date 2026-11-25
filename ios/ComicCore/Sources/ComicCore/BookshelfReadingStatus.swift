import Foundation

/// Presentation follows Android's calculateOnlineUnreadCount/resolveOnlineLatestChapter.
/// Missing directory evidence stays unknown; an update flag is never used as a count.
public struct BookshelfReadingStatus: Equatable, Sendable {
    public let unreadCount: Int
    public let latestChapter: String
    public let readingDescription: String

    public static func resolveOnlineTotalChapters(cachedCount: Int, observedCount: Int) -> Int {
        max(cachedCount, observedCount)
    }

    public static func resolveOnlineLatestChapterText(
        pendingUpdate: Bool,
        observedLatest: String?,
        detailLatest: String?,
        summaryLatest: String?,
        lastChapterTitle: String?
    ) -> String? {
        if pendingUpdate, let observed = trimmedNonEmpty(observedLatest) {
            return observed
        }
        if let detail = trimmedNonEmpty(detailLatest) {
            return detail
        }
        if let summary = trimmedNonEmpty(summaryLatest) {
            return summary
        }
        if let observed = trimmedNonEmpty(observedLatest) {
            return observed
        }
        if let last = trimmedNonEmpty(lastChapterTitle) {
            return last
        }
        return nil
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public init(
        comic: ComicSummary,
        reading: ReadingRecord?,
        revision: FavoriteRevision?,
        detail: ComicDetail? = nil,
        pendingUpdate: Bool = false
    ) {
        let cachedCount = (detail != nil && !(detail!.chapters.isEmpty)) ? detail!.chapters.count : -1
        let observedCount = (revision != nil && revision!.chapterCount > 0) ? revision!.chapterCount : -1
        let total = Self.resolveOnlineTotalChapters(cachedCount: cachedCount, observedCount: observedCount)
        unreadCount = BookshelfLayoutHelper.calculateOnlineUnreadCount(totalChapters: total, savedChapter: reading?.chapterIndex ?? 0, hasReadHistory: reading != nil)
        latestChapter = Self.resolveOnlineLatestChapterText(
            pendingUpdate: pendingUpdate,
            observedLatest: revision?.latestChapterName,
            detailLatest: detail?.latestChapter,
            summaryLatest: comic.latestChapter,
            lastChapterTitle: detail?.chapters.last?.title
        ) ?? ""
        readingDescription = reading?.chapter.title ?? "未开始阅读"
    }
}
