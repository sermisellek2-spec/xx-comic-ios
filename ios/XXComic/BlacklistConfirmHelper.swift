import UIKit
import ComicCore

/// Confirmation alert and 5-second undo toast helper for adding comics to the global blacklist.
@MainActor
enum BlacklistConfirmHelper {
    static func buildMessage(title: String, inBookshelf: Bool) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = trimmed.isEmpty ? "该漫画" : trimmed
        let base = "拉黑后，所有站源里叫《\(safeTitle)》的漫画都不会再显示，可在 设置 › 黑名单列表 中恢复。"
        if inBookshelf {
            return base + "\n\n它会移到黑名单，恢复后回到书架原来的分组，阅读进度不变。"
        }
        return base
    }

    static func present(
        from presenter: UIViewController,
        title: String,
        inBookshelf: Bool,
        hasActiveDownloads: Bool,
        onConfirm: @escaping (_ pauseDownloads: Bool) -> Void
    ) {
        var message = buildMessage(title: title, inBookshelf: inBookshelf)
        if hasActiveDownloads {
            message += "\n\n检测到该漫画存在进行中的下载任务，可选择同时暂停下载（不删除已下载文件）。"
        }

        let alert = UIAlertController(title: "加入黑名单", message: message, preferredStyle: .alert)
        if hasActiveDownloads {
            alert.addAction(UIAlertAction(title: "加入黑名单并暂停下载", style: .destructive) { _ in
                onConfirm(true)
            })
            alert.addAction(UIAlertAction(title: "仅加入黑名单", style: .default) { _ in
                onConfirm(false)
            })
        } else {
            alert.addAction(UIAlertAction(title: "加入黑名单", style: .destructive) { _ in
                onConfirm(false)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        presenter.present(alert, animated: true)
    }

    static func presentAndAdd(
        from presenter: UIViewController,
        environment: AppEnvironment,
        comic: ComicSummary,
        sourceName: String,
        onBlacklisted: (() -> Void)? = nil
    ) {
        let inBookshelf = environment.library.entry(for: comic)?.isFavorite == true
        let activeDownloads = environment.hasActiveDownloads(forTitle: comic.title)
        present(
            from: presenter,
            title: comic.title,
            inBookshelf: inBookshelf,
            hasActiveDownloads: activeDownloads
        ) { [weak presenter] pauseDownloads in
            guard let entry = environment.addToBlacklist(
                title: comic.title,
                sourceId: comic.sourceId,
                sourceName: sourceName,
                comicId: comic.comicId,
                coverUrl: comic.coverUrl,
                pauseDownloads: pauseDownloads
            ) else {
                return
            }
            onBlacklisted?()
            let displayTitle = entry.displayTitle.isEmpty ? "该漫画" : entry.displayTitle
            RemToastView.show(
                message: "已拉黑《\(displayTitle)》",
                kind: .info,
                actionTitle: "撤销",
                duration: 5.0,
                in: presenter
            ) {
                environment.restoreFromBlacklist(normalizedTitle: entry.normalizedTitle)
            }
        }
    }
}
