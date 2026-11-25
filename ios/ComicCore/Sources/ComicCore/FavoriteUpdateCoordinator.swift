import Foundation

public final class FavoriteUpdateCoordinator: @unchecked Sendable {
    public static let prefKey = "favorite.update.states"
    public static let persistDebounceMs: Int64 = 300

    public typealias BadgeChangeListener = @Sendable (String, String, Bool) -> Void

    private let lock = NSLock()
    private let defaults: UserDefaults?
    private let persistQueue: DispatchQueue
    private var states: [String: FavoriteUpdateState] = [:]
    private var checkedInSession = Set<String>()
    private var visitEpochs: [String: Int] = [:]
    private var favoriteEpochs: [String: Int] = [:]
    private var persistDirty = false
    private var pendingPersistWorkItem: DispatchWorkItem?
    private var activeBatchTasks = 0

    public var onBadgeChanged: BadgeChangeListener?
    public var onRevisionObserved: (@Sendable (String, String) -> Void)?

    public init(
        defaults: UserDefaults? = nil,
        persistQueue: DispatchQueue = DispatchQueue(label: "com.xxcomic.favoriteUpdatePersist")
    ) {
        self.defaults = defaults
        self.persistQueue = persistQueue
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
        cancelPendingPersistLocked()
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(states) {
            defaults.set(data, forKey: Self.prefKey)
        }
    }

    private func cancelPendingPersistLocked() {
        persistDirty = false
        pendingPersistWorkItem?.cancel()
        pendingPersistWorkItem = nil
    }

    private func scheduleBatchPersistLocked(forceDebounce: Bool = false) {
        if !forceDebounce && activeBatchTasks == 0 {
            saveLocked()
            return
        }
        persistDirty = true
        pendingPersistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if self.persistDirty {
                self.saveLocked()
            }
            self.lock.unlock()
        }
        pendingPersistWorkItem = item
        persistQueue.asyncAfter(deadline: .now() + .milliseconds(Int(Self.persistDebounceMs)), execute: item)
    }

    private func flushPendingPersistIfIdleLocked() {
        if persistDirty && activeBatchTasks == 0 {
            saveLocked()
        }
    }

    public func flushPendingPersist() {
        lock.lock()
        if persistDirty {
            saveLocked()
        } else {
            cancelPendingPersistLocked()
        }
        lock.unlock()
    }

    public func state(sourceId: String, comicId: String) -> FavoriteUpdateState? {
        lock.lock(); defer { lock.unlock() }
        return states[key(sourceId: sourceId, comicId: comicId)]
    }

    public func hasPendingUpdate(sourceId: String, comicId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return states[key(sourceId: sourceId, comicId: comicId)]?.pendingUpdate ?? false
    }

    public func shouldShowBadge(sourceId: String, comicId: String) -> Bool {
        guard !comicId.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        let k = key(sourceId: sourceId, comicId: comicId)
        guard let s = states[k] else { return false }
        return s.pendingUpdate && checkedInSession.contains(k)
    }

    public func shouldShowBadge(comicId: String) -> Bool {
        guard !comicId.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        for (k, s) in states where s.comicId == comicId {
            if s.pendingUpdate && checkedInSession.contains(k) {
                return true
            }
        }
        return false
    }

    public func visitEpoch(sourceId: String, comicId: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return visitEpochs[key(sourceId: sourceId, comicId: comicId)] ?? 0
    }

    public func favoriteEpoch(sourceId: String, comicId: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return favoriteEpochs[key(sourceId: sourceId, comicId: comicId)] ?? 0
    }

    public func acknowledge(sourceId: String, comicId: String, revision: FavoriteRevision?) {
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)
        visitEpochs[k] = (visitEpochs[k] ?? 0) + 1
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
        checkedInSession.insert(k)
        saveLocked()
        lock.unlock()

        if wasPending {
            onBadgeChanged?(sourceId, comicId, false)
        }
        onRevisionObserved?(sourceId, comicId)
    }

    public func onUserEnterDetail(sourceId: String, comicId: String) {
        guard !comicId.isEmpty else { return }
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)
        visitEpochs[k] = (visitEpochs[k] ?? 0) + 1
        if var s = states[k] {
            s.pendingUpdate = false
            if let observed = s.observedRevision {
                s.acknowledgedRevision = observed
            }
            states[k] = s
            saveLocked()
        } else if persistDirty {
            saveLocked()
        }
        lock.unlock()
        onBadgeChanged?(sourceId, comicId, false)
    }

    public func onDetailChaptersObserved(sourceId: String, comicId: String, detail: ComicDetail) {
        guard !comicId.isEmpty, !detail.chapters.isEmpty,
              let rev = FavoriteRevision.fromDetail(detail) else {
            return
        }
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)
        visitEpochs[k] = (visitEpochs[k] ?? 0) + 1
        if var s = states[k] {
            s.observedRevision = rev
            s.acknowledgedRevision = rev
            s.pendingUpdate = false
            states[k] = s
        } else {
            states[k] = FavoriteUpdateState(
                sourceId: sourceId,
                comicId: comicId,
                pendingUpdate: false,
                observedRevision: rev,
                acknowledgedRevision: rev
            )
        }
        checkedInSession.insert(k)
        saveLocked()
        lock.unlock()
        onBadgeChanged?(sourceId, comicId, false)
        onRevisionObserved?(sourceId, comicId)
    }

    public func onFavoriteAdded(sourceId: String, comicId: String, detail: ComicDetail? = nil) {
        guard !comicId.isEmpty else { return }
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)
        favoriteEpochs[k] = (favoriteEpochs[k] ?? 0) + 1
        checkedInSession.remove(k)
        let rev = FavoriteRevision.fromDetail(detail)
        states[k] = FavoriteUpdateState(
            sourceId: sourceId,
            comicId: comicId,
            pendingUpdate: false,
            observedRevision: rev,
            acknowledgedRevision: rev
        )
        saveLocked()
        lock.unlock()
    }

    public func onFavoriteRemoved(sourceId: String, comicId: String) {
        guard !comicId.isEmpty else { return }
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)
        favoriteEpochs[k] = (favoriteEpochs[k] ?? 0) + 1
        states.removeValue(forKey: k)
        checkedInSession.remove(k)
        saveLocked()
        lock.unlock()
        onBadgeChanged?(sourceId, comicId, false)
    }

    public func recordObserved(sourceId: String, comicId: String, revision: FavoriteRevision) {
        recordObserved(
            sourceId: sourceId,
            comicId: comicId,
            revision: revision,
            startVisitEpoch: nil,
            startFavoriteEpoch: nil,
            deferPersist: false
        )
    }

    public func recordObserved(
        sourceId: String,
        comicId: String,
        revision: FavoriteRevision,
        startVisitEpoch: Int?,
        startFavoriteEpoch: Int?,
        deferPersist: Bool
    ) {
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)

        if let startFavoriteEpoch, (favoriteEpochs[k] ?? 0) != startFavoriteEpoch {
            flushPendingPersistIfIdleLocked()
            lock.unlock()
            return
        }

        var badgeNotify: Bool? = nil
        var stateChanged = false

        if var s = states[k] {
            if s.acknowledgedRevision == nil {
                s.acknowledgedRevision = revision
                s.observedRevision = revision
                s.pendingUpdate = false
                states[k] = s
                checkedInSession.insert(k)
                stateChanged = true
            } else {
                let currentVisitEpoch = visitEpochs[k] ?? 0
                if let startVisitEpoch, currentVisitEpoch > startVisitEpoch {
                    // User opened detail while check was in flight: advance baseline silently, do not light up
                    if s.acknowledgedRevision?.mode == FavoriteRevision.modeLatestChapter
                        || FavoriteRevision.hasNewChapters(baseline: s.acknowledgedRevision, candidate: revision) {
                        s.acknowledgedRevision = revision
                        s.observedRevision = revision
                    }
                    s.pendingUpdate = false
                    states[k] = s
                    checkedInSession.insert(k)
                    stateChanged = true
                } else {
                    let isNew = FavoriteRevision.hasNewChapters(baseline: s.acknowledgedRevision, candidate: revision)
                    let changed = (s.pendingUpdate != isNew)
                    s.observedRevision = revision
                    s.pendingUpdate = isNew
                    states[k] = s
                    checkedInSession.insert(k)
                    stateChanged = true
                    if changed {
                        badgeNotify = isNew
                    }
                }
            }
        } else {
            // First observation establishes baseline, do not light up star
            let s = FavoriteUpdateState(
                sourceId: sourceId,
                comicId: comicId,
                pendingUpdate: false,
                observedRevision: revision,
                acknowledgedRevision: revision
            )
            states[k] = s
            checkedInSession.insert(k)
            stateChanged = true
        }

        if stateChanged {
            scheduleBatchPersistLocked(forceDebounce: deferPersist)
        } else {
            flushPendingPersistIfIdleLocked()
        }
        lock.unlock()

        if let visible = badgeNotify {
            onBadgeChanged?(sourceId, comicId, visible)
        }
        onRevisionObserved?(sourceId, comicId)
    }

    public func clearState(sourceId: String, comicId: String) {
        lock.lock()
        let k = key(sourceId: sourceId, comicId: comicId)
        favoriteEpochs[k] = (favoriteEpochs[k] ?? 0) + 1
        checkedInSession.remove(k)
        let removed = states.removeValue(forKey: k)
        if removed != nil { saveLocked() }
        lock.unlock()

        if removed?.pendingUpdate == true {
            onBadgeChanged?(sourceId, comicId, false)
        }
    }

    private func prepareStartupQueue(
        favorites: [(sourceId: String, comicId: String)],
        sourceProvider: @escaping @Sendable (String) -> (any ComicSource)?,
        cachedDetails: [String: ComicDetail]
    ) -> [(sourceId: String, comicId: String, source: any ComicSource, startVisitEpoch: Int, startFavoriteEpoch: Int)] {
        lock.lock()
        defer { lock.unlock() }
        for item in favorites {
            let k = key(sourceId: item.sourceId, comicId: item.comicId)
            if states[k] == nil,
               let detail = cachedDetails[item.comicId] ?? cachedDetails[k],
               !detail.chapters.isEmpty,
               let rev = FavoriteRevision.fromDetail(detail) {
                states[k] = FavoriteUpdateState(
                    sourceId: item.sourceId,
                    comicId: item.comicId,
                    pendingUpdate: false,
                    observedRevision: rev,
                    acknowledgedRevision: rev
                )
            }
        }
        saveLocked()

        var queue: [(sourceId: String, comicId: String, source: any ComicSource, startVisitEpoch: Int, startFavoriteEpoch: Int)] = []
        for item in favorites {
            guard item.sourceId != "local", let source = sourceProvider(item.sourceId) else { continue }
            let k = key(sourceId: item.sourceId, comicId: item.comicId)
            queue.append((
                sourceId: item.sourceId,
                comicId: item.comicId,
                source: source,
                startVisitEpoch: visitEpochs[k] ?? 0,
                startFavoriteEpoch: favoriteEpochs[k] ?? 0
            ))
        }
        activeBatchTasks = queue.count
        return queue
    }

    private func decrementBatchTasksAndShouldDefer() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        activeBatchTasks = max(0, activeBatchTasks - 1)
        return activeBatchTasks > 0
    }

    private func finishStartupCheckBatch() {
        lock.lock()
        activeBatchTasks = 0
        flushPendingPersistIfIdleLocked()
        lock.unlock()
    }

    private func flushIfIdle() {
        lock.lock()
        flushPendingPersistIfIdleLocked()
        lock.unlock()
    }

    /// Runs a bounded startup check (max 2 concurrent, max 1 per source) under
    /// `RuleCallPriority.withBackgroundPriority`, applying `visitEpoch`/`favoriteEpoch` guards
    /// and 300ms debounced persistence.
    @discardableResult
    public func startStartupCheck(
        favorites: [(sourceId: String, comicId: String)],
        sourceProvider: @escaping @Sendable (String) -> (any ComicSource)?,
        cachedDetails: [String: ComicDetail] = [:]
    ) -> Task<Void, Never> {
        let queue = prepareStartupQueue(
            favorites: favorites,
            sourceProvider: sourceProvider,
            cachedDetails: cachedDetails
        )

        return Task { [weak self] in
            guard let self else { return }
            defer { self.finishStartupCheckBatch() }
            var pending = queue
            var runningSources = Set<String>()

            await withTaskGroup(of: String.self) { group in
                func launchAvailable() {
                    while runningSources.count < 2 {
                        guard let idx = pending.firstIndex(where: { !runningSources.contains($0.sourceId) }) else {
                            break
                        }
                        let next = pending.remove(at: idx)
                        runningSources.insert(next.sourceId)
                        group.addTask { [weak self] in
                            guard let self else { return next.sourceId }
                            let baseline = self.state(sourceId: next.sourceId, comicId: next.comicId)?.acknowledgedRevision
                            let newRev = await RuleCallPriority.withBackgroundPriority {
                                await FavoriteUpdateChecker.check(
                                    source: next.source,
                                    comicId: next.comicId,
                                    baseline: baseline
                                )
                            }
                            let shouldDefer = self.decrementBatchTasksAndShouldDefer()
                            if let newRev {
                                self.recordObserved(
                                    sourceId: next.sourceId,
                                    comicId: next.comicId,
                                    revision: newRev,
                                    startVisitEpoch: next.startVisitEpoch,
                                    startFavoriteEpoch: next.startFavoriteEpoch,
                                    deferPersist: shouldDefer
                                )
                            } else {
                                self.flushIfIdle()
                            }
                            return next.sourceId
                        }
                    }
                }

                launchAvailable()
                for await finishedSource in group {
                    runningSources.remove(finishedSource)
                    if Task.isCancelled { break }
                    launchAvailable()
                }
            }
        }
    }
}
