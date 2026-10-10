import Foundation

public final class FavoriteUpdateCoordinator: @unchecked Sendable {
    public static let prefKey = "favorite.update.states"

    public typealias BadgeChangeListener = @Sendable (String, String, Bool) -> Void

    private let lock = NSLock()
    private let defaults: UserDefaults?
    private var states: [String: FavoriteUpdateState] = [:]
    public var onBadgeChanged: BadgeChangeListener?

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let defaults, let data = defaults.data(forKey: Self.prefKey) {
            if let decoded = try? JSONDecoder().decode([String: FavoriteUpdateState].self, from: data) {
                self.states = decoded
            }
        }
    }

    private func key(sourceId: String, comicId: String) -> String {
        "\(sourceId):\(comicId)"
    }

    private func saveLocked() {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(states) {
            defaults.set(data, forKey: Self.prefKey)
        }
    }

    public func state(sourceId: String, comicId: String) -> FavoriteUpdateState? {
        lock.lock(); defer { lock.unlock() }
        return states[key(sourceId: sourceId, comicId: comicId)]
    }

    public func hasPendingUpdate(sourceId: String, comicId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return states[key(sourceId: sourceId, comicId: comicId)]?.pendingUpdate ?? false
    }

    public func acknowledge(sourceId: String, comicId: String, revision: FavoriteRevision?) {
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)
        var s = states[k] ?? FavoriteUpdateState(sourceId: sourceId, comicId: comicId,
                                                 pendingUpdate: false, observedRevision: revision,
                                                 acknowledgedRevision: revision)
        let wasPending = s.pendingUpdate
        s.pendingUpdate = false
        if let revision {
            s.acknowledgedRevision = revision
            s.observedRevision = revision
        }
        states[k] = s
        saveLocked()
        lock.unlock()

        if wasPending {
            onBadgeChanged?(sourceId, comicId, false)
        }
    }

    public func recordObserved(sourceId: String, comicId: String, revision: FavoriteRevision) {
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)
        var s = states[k] ?? FavoriteUpdateState(sourceId: sourceId, comicId: comicId,
                                                 pendingUpdate: false, observedRevision: nil,
                                                 acknowledgedRevision: nil)
        s.observedRevision = revision
        let isNew = FavoriteRevision.hasNewChapters(baseline: s.acknowledgedRevision, candidate: revision)
        let changed = (s.pendingUpdate != isNew)
        s.pendingUpdate = isNew
        states[k] = s
        saveLocked()
        lock.unlock()

        if changed {
            onBadgeChanged?(sourceId, comicId, isNew)
        }
    }

    public func clearState(sourceId: String, comicId: String) {
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)
        let removed = states.removeValue(forKey: k)
        if removed != nil { saveLocked() }
        lock.unlock()

        if removed?.pendingUpdate == true {
            onBadgeChanged?(sourceId, comicId, false)
        }
    }
}
