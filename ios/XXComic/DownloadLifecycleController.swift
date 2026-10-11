import UIKit
import ComicCore

/// Finishes foreground downloads within the system's allowance, then saves
/// resumable leases before suspension. It never resumes a user-paused task.
@MainActor
final class DownloadLifecycleController {
    typealias Begin = (@escaping () -> Void) -> UIBackgroundTaskIdentifier
    typealias End = (UIBackgroundTaskIdentifier) -> Void

    private let runtime: DownloadRuntime
    private let begin: Begin
    private let end: End
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var grantToken: UUID?
    private var isBackground = false
    private var expiryPending = false
    private var transition: Task<Void, Never>?
    private var observedRevision: UInt64 = 0

    init(runtime: DownloadRuntime, begin: Begin? = nil, end: End? = nil) {
        self.runtime = runtime
        self.begin = begin ?? { UIApplication.shared.beginBackgroundTask(withName: "完成离线下载", expirationHandler: $0) }
        self.end = end ?? { UIApplication.shared.endBackgroundTask($0) }
    }

    func start() {
        runtime.onActivityChanged = { [weak self] activity in
            Task { @MainActor [weak self] in self?.receive(activity) }
        }
        enqueueTransition(suspend: false)
    }

    func didEnterBackground() {
        isBackground = true
        // Protect the transition before reading the runtime snapshot on a
        // worker: file publication can hold its lock for a large cross-volume copy.
        if !expiryPending { requestAllowance() }
        if identifier == .invalid, !expiryPending {
            expiryPending = true
            enqueueTransition(suspend: true)
        } else {
            let runtime = runtime
            Task { [weak self] in
                let activity = await Task.detached(priority: .utility) { runtime.activity }.value
                self?.receive(activity)
            }
        }
    }

    func didBecomeActive() {
        isBackground = false
        expiryPending = false
        finishGrant()
        enqueueTransition(suspend: false)
    }

    private func receive(_ activity: DownloadRuntimeActivity) {
        guard activity.revision >= observedRevision else { return }
        observedRevision = activity.revision
        guard activity.activeWorkers > 0, !activity.suspendedForBackground else {
            finishGrant()
            if isBackground, !activity.suspendedForBackground, !expiryPending {
                expiryPending = true
                enqueueTransition(suspend: true)
            }
            return
        }
        guard !(isBackground && expiryPending), identifier == .invalid else { return }
        requestAllowance()
    }

    private func requestAllowance() {
        guard identifier == .invalid else { return }
        let token = UUID()
        grantToken = token
        identifier = begin { [weak self] in
            Task { @MainActor [weak self] in self?.expired(token) }
        }
        if identifier == .invalid { grantToken = nil }
    }

    private func expired(_ token: UUID) {
        guard grantToken == token else { return }
        expiryPending = true
        enqueueTransition(suspend: true, finishing: token)
    }

    private func enqueueTransition(suspend: Bool, finishing token: UUID? = nil) {
        let previous = transition, runtime = runtime
        transition = Task { [weak self] in
            // Ordered transitions prevent an old expiry from suspending a
            // download after the user has already returned to the foreground.
            await previous?.value
            let activity = await Task.detached(priority: .utility) {
                if suspend { runtime.suspendForBackground() }
                else { runtime.resumeFromBackground() }
                return runtime.activity
            }.value
            guard let self else { return }
            if let token, self.grantToken == token { self.finishGrant() }
            self.receive(activity)
        }
    }

    private func finishGrant() {
        let previous = identifier
        identifier = .invalid; grantToken = nil
        if previous != .invalid { end(previous) }
    }

    deinit {
        let identifier = identifier, end = end, runtime = runtime
        Task.detached(priority: .utility) { runtime.suspendForBackground() }
        if identifier != .invalid { Task { @MainActor in end(identifier) } }
    }
}
