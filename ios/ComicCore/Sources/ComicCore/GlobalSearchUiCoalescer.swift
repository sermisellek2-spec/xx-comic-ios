import Foundation

/// Injectable scheduling abstraction for `GlobalSearchUiCoalescer` enabling deterministic unit tests.
public protocol GlobalSearchScheduler: AnyObject {
    @discardableResult
    func postDelayed(_ action: @escaping () -> Void, delayMs: Int64) -> AnyObject
    func removeCallbacks(_ handle: AnyObject)
}

/// Default main-queue scheduler backed by `DispatchQueue.main` and `DispatchWorkItem`.
public final class MainQueueGlobalSearchScheduler: GlobalSearchScheduler {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    @discardableResult
    public func postDelayed(_ action: @escaping () -> Void, delayMs: Int64) -> AnyObject {
        let item = DispatchWorkItem(block: action)
        let clampedMs = max(0, delayMs)
        queue.asyncAfter(deadline: .now() + .milliseconds(Int(clampedMs)), execute: item)
        return item
    }

    public func removeCallbacks(_ handle: AnyObject) {
        if let item = handle as? DispatchWorkItem {
            item.cancel()
        }
    }
}

/// Thread-safe UI refresh coalescer for streaming global search results.
///
/// Flushes the first result (or forced updates) immediately, coalesces rapid intermediate source
/// callbacks inside a fixed 160ms window without starving continuous arrivals, and supports
/// immediate completion/cancel via `flushNow` and `cancel`.
public final class GlobalSearchUiCoalescer: @unchecked Sendable {
    public static let defaultWindowMs: Int64 = 160

    private let lock = NSLock()
    private let scheduler: GlobalSearchScheduler
    public let windowMs: Int64

    private var hasImmediateFlushed = false
    private var timerScheduled = false
    private var pendingAction: (() -> Void)?
    private var activeScheduledHandle: AnyObject?
    private var token: UInt64 = 0

    public init(
        scheduler: GlobalSearchScheduler = MainQueueGlobalSearchScheduler(),
        windowMs: Int64 = defaultWindowMs
    ) {
        self.scheduler = scheduler
        self.windowMs = max(0, windowMs)
    }

    public var hasPendingRefresh: Bool {
        lock.lock()
        let pending = timerScheduled && pendingAction != nil
        lock.unlock()
        return pending
    }

    /// Resets per-search-session state so the first result batch renders immediately and any
    /// leftover scheduled callback from a prior session is cancelled.
    public func beginSession() {
        lock.lock()
        token &+= 1
        hasImmediateFlushed = false
        pendingAction = nil
        timerScheduled = false
        let toRemove = activeScheduledHandle
        activeScheduledHandle = nil
        lock.unlock()

        if let toRemove {
            scheduler.removeCallbacks(toRemove)
        }
    }

    /// Requests a UI refresh. The first request of a session (or any call with `forceImmediate == true`)
    /// executes immediately and cancels pending scheduled work; subsequent bursts inside `windowMs`
    /// replace the pending action without resetting the active timer deadline.
    public func requestRefresh(forceImmediate: Bool, action: @escaping () -> Void) {
        var toRemove: AnyObject?
        var shouldSchedule = false
        var scheduledToken: UInt64 = 0
        var runImmediately = false

        lock.lock()
        if !hasImmediateFlushed || forceImmediate {
            token &+= 1
            hasImmediateFlushed = true
            pendingAction = nil
            timerScheduled = false
            toRemove = activeScheduledHandle
            activeScheduledHandle = nil
            runImmediately = true
        } else {
            pendingAction = action
            if !timerScheduled {
                timerScheduled = true
                scheduledToken = token
                shouldSchedule = true
            }
        }
        lock.unlock()

        if let toRemove {
            scheduler.removeCallbacks(toRemove)
        }
        if runImmediately {
            action()
        } else if shouldSchedule {
            let handle = scheduler.postDelayed({ [weak self] in
                self?.fireScheduled(expectedToken: scheduledToken)
            }, delayMs: windowMs)
            lock.lock()
            if scheduledToken == token && timerScheduled && activeScheduledHandle == nil {
                activeScheduledHandle = handle
                lock.unlock()
            } else {
                let expired = scheduledToken != token || !timerScheduled
                lock.unlock()
                if expired {
                    scheduler.removeCallbacks(handle)
                }
            }
        }
    }

    /// Cancels any pending scheduled refresh and immediately runs `finalAction` (or the pending
    /// action if `finalAction` is `nil`).
    public func flushNow(_ finalAction: (() -> Void)? = nil) {
        lock.lock()
        token &+= 1
        let toRemove = activeScheduledHandle
        activeScheduledHandle = nil
        timerScheduled = false
        let pending = pendingAction
        pendingAction = nil
        let toRun = finalAction ?? pending
        if toRun != nil {
            hasImmediateFlushed = true
        }
        lock.unlock()

        if let toRemove {
            scheduler.removeCallbacks(toRemove)
        }
        toRun?()
    }

    /// Cancels any pending scheduled timer and drops queued pending actions.
    public func cancel() {
        lock.lock()
        token &+= 1
        pendingAction = nil
        timerScheduled = false
        let toRemove = activeScheduledHandle
        activeScheduledHandle = nil
        lock.unlock()

        if let toRemove {
            scheduler.removeCallbacks(toRemove)
        }
    }

    private func fireScheduled(expectedToken: UInt64) {
        lock.lock()
        guard expectedToken == token else {
            lock.unlock()
            return
        }
        let toRun = pendingAction
        pendingAction = nil
        timerScheduled = false
        activeScheduledHandle = nil
        lock.unlock()

        toRun?()
    }
}
