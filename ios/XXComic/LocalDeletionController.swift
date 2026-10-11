import UIKit
import ComicCore

@MainActor
final class LocalDeletionController {
    struct Request {
        let target: LocalDeletionTarget
        let title: String
        let groupComicID: String
    }
    private unowned let environment: AppEnvironment
    private var requests: [LocalDeletionTarget: Request] = [:]
    private(set) var hidden = Set<LocalDeletionTarget>()
    private var waiting = Set<LocalDeletionTarget>()
    private var failed = Set<LocalDeletionTarget>()
    private var failureMessage = "删除未完成，请重试"
    private weak var window: UIWindow?
    private var messageTask: Task<Void, Never>?
    private let banner = UIView()
    private let message = UILabel()
    private let action = UIButton(type: .system)

    private lazy var queue: DeferredDeletionQueue = {
        let folders = environment.folderSyncCoordinator, downloads = environment.downloadRuntime
        return DeferredDeletionQueue(operation: { target in
            switch target {
            case .localSeries(let id): try await folders.deleteSeries(id: id)
            case .downloadBook(let id): try await downloads.deleteBook(bookId: id)
            }
        }, onChange: { [weak self] waiting, committing in
            Task { @MainActor [weak self] in self?.changed(waiting: waiting, committing: committing) }
        }, onResult: { [weak self] target, result in
            Task { @MainActor [weak self] in self?.finished(target, result: result) }
        })
    }()

    init(environment: AppEnvironment) {
        self.environment = environment
        banner.backgroundColor = Palette.card; banner.layer.cornerRadius = 12
        banner.layer.borderWidth = 1; banner.layer.borderColor = Palette.border.cgColor
        banner.accessibilityIdentifier = "local.deletion.feedback"
        message.font = .systemFont(ofSize: 13, weight: .medium); message.numberOfLines = 2; message.textColor = Palette.text
        message.accessibilityIdentifier = "local.deletion.message"
        action.accessibilityIdentifier = "local.deletion.action"
        action.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        let illustration = UIImageView(image: UIImage(named: "rem_empty")); illustration.contentMode = .scaleAspectFit
        let row = UIStackView(arrangedSubviews: [illustration, message, action]); row.spacing = 10; row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false; banner.addSubview(row)
        NSLayoutConstraint.activate([illustration.widthAnchor.constraint(equalToConstant: 32), illustration.heightAnchor.constraint(equalToConstant: 32),
            action.widthAnchor.constraint(equalToConstant: 56), action.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            row.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12), row.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: banner.topAnchor, constant: 6), row.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -6)])
    }

    func schedule(_ items: [Request], from presenter: UIViewController) {
        guard !items.isEmpty else { return }
        window = presenter.view.window ?? window
        for item in items { requests[item.target] = item; hidden.insert(item.target); waiting.insert(item.target); failed.remove(item.target) }
        messageTask?.cancel(); updateWaitingBanner(); environment.notifyLibraryChanged()
        let targets = items.map(\.target), queue = queue
        Task { await queue.schedule(targets) }
    }
    func containsLocalSeries(_ id: String) -> Bool { hidden.contains(.localSeries(id)) }
    func containsDownloadBook(_ id: String) -> Bool { hidden.contains(.downloadBook(id)) }

    private func changed(waiting: Set<LocalDeletionTarget>, committing: Set<LocalDeletionTarget>) {
        self.waiting = waiting; hidden = waiting.union(committing)
        environment.notifyLibraryChanged()
        if !hidden.isEmpty { updateWaitingBanner() }
        else if !failed.isEmpty { showFailureBanner() }
    }
    private func updateWaitingBanner() {
        message.textColor = Palette.text
        let title = hidden.count == 1 ? requests[hidden.first!]?.title : nil
        message.text = waiting.isEmpty ? "正在删除 App 副本…" : (title.map { "已移出《\($0)》· 稍后删除副本" } ?? "已移出 \(hidden.count) 本漫画 · 稍后删除副本")
        action.setTitle("撤销", for: .normal); action.isEnabled = !waiting.isEmpty
        showBanner()
    }
    @objc private func actionTapped() {
        let queue = queue
        if !waiting.isEmpty {
            let targets = Array(waiting)
            Task { [weak self] in
                let restored = await queue.undo(targets)
                guard let self else { return }
                if !self.failed.isEmpty { self.showFailureBanner(); return }
                self.message.text = restored.isEmpty ? "正在删除，无法撤销" : "已撤销删除"
                self.action.isEnabled = false; self.environment.notifyLibraryChanged(); self.hideMessageLater()
            }
        } else if !failed.isEmpty {
            let targets = Array(failed); failed.removeAll()
            for target in targets { hidden.insert(target); waiting.insert(target) }
            messageTask?.cancel(); updateWaitingBanner(); environment.notifyLibraryChanged()
            Task { await queue.schedule(targets) }
        }
    }
    private func finished(_ target: LocalDeletionTarget, result: Result<Void, Error>) {
        switch result {
        case .success:
            if let request = requests[target] {
                let hasOtherDownload: Bool
                if case .downloadBook = target {
                    hasOtherDownload = environment.downloadStore.list().contains { $0.comicId == request.groupComicID && $0.state == .completed }
                } else { hasOtherDownload = false }
                if !hasOtherDownload { environment.bookshelfGroupStore.removeComicFromAllGroups(scope: .local, comicId: request.groupComicID) }
            }
            requests.removeValue(forKey: target)
            if hidden.isEmpty && failed.isEmpty { message.text = "已删除 App 副本 · 原文件和阅读记录已保留"; action.isEnabled = false; showBanner(); hideMessageLater() }
            else if hidden.isEmpty { showFailureBanner() }
        case .failure(let error):
            failed.insert(target)
            failureMessage = "删除未完成：" + error.localizedDescription
            if hidden.isEmpty { showFailureBanner() }
        }
        environment.notifyLibraryChanged()
    }
    private func showFailureBanner() {
        message.text = failureMessage; message.textColor = .systemRed
        action.setTitle("重试", for: .normal); action.isEnabled = true; showBanner()
    }
    private func showBanner() {
        guard let window else { return }
        if banner.superview !== window {
            banner.removeFromSuperview(); banner.translatesAutoresizingMaskIntoConstraints = false; window.addSubview(banner)
            NSLayoutConstraint.activate([banner.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                banner.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                banner.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -72)])
        }
        window.bringSubviewToFront(banner)
    }
    private func hideMessageLater() {
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            guard let self, self.hidden.isEmpty, self.failed.isEmpty else { return }
            self.banner.removeFromSuperview()
        }
    }
}
