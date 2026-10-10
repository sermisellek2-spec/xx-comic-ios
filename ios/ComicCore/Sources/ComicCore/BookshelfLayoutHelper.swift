import Foundation

public final class BookshelfLayoutHelper {
    public static let keyOnlineLayout = "bookshelf.online.layout"
    public static let keyLocalLayout = "bookshelf.local.layout"

    public static let layoutGrid = 0
    public static let layoutList = 1

    public static let colorUpdateBlue: UInt32 = 0xFF2B98D9
    public static let colorNoUpdateGray: UInt32 = 0xFF8A9AA8

    private init() {}

    public static func prefKey(scope: BookshelfScope) -> String {
        (scope == .online) ? keyOnlineLayout : keyLocalLayout
    }

    public static func isGridMode(defaults: UserDefaults?, scope: BookshelfScope) -> Bool {
        guard let defaults else { return true }
        return defaults.integer(forKey: prefKey(scope: scope)) == layoutGrid
    }

    public static func setGridMode(defaults: UserDefaults?, scope: BookshelfScope, isGrid: Bool) {
        guard let defaults else { return }
        defaults.set(isGrid ? layoutGrid : layoutList, forKey: prefKey(scope: scope))
    }

    public static func resolveBadgeColor(hasUpdate: Bool) -> UInt32 {
        hasUpdate ? colorUpdateBlue : colorNoUpdateGray
    }

    public static func formatUnreadBadgeText(count: Int) -> String {
        if count <= 0 { return "" }
        if count > 99 { return "99+" }
        return String(count)
    }

    public static func calculateOnlineUnreadCount(totalChapters: Int, savedChapter: Int, hasReadHistory: Bool) -> Int {
        if totalChapters <= 0 { return -1 }
        if !hasReadHistory { return totalChapters }
        let readCount = max(0, savedChapter + 1)
        return max(0, totalChapters - readCount)
    }

    public static func formatOnlineLatestChapter(_ latestChapter: String?) -> String {
        guard let latestChapter, !latestChapter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "暂无更新"
        }
        let trimmed = latestChapter.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("更新至") {
            return trimmed
        }
        return "更新至 " + trimmed
    }
}
