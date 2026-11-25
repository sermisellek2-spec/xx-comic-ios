import Foundation

/// Short-lived detail-page alternative-source title search cache with delayed start,
/// per-job execution timeout, 3-slot concurrency limit, and background call priority.
public final class DetailSourceSearch: @unchecked Sendable {
    public typealias Listener = @Sendable (_ items: [ComicSummary], _ loading: Bool) -> Void
    public typealias CallbackExecutor = @Sendable (@escaping @Sendable () -> Void) -> Void

    private static let cacheFreshNanos: UInt64 = 5 * 60 * 1_000_000_000

    private final class Job {
        var workTask: Task<Void, Never>?
        var timeoutItem: DispatchWorkItem?
    }

    private final class PendingStart {
        let token: Int
        let query: String
        let sources: [any ComicSource]
        var timerItem: DispatchWorkItem?

        init(token: Int, query: String, sources: [any ComicSource]) {
            self.token = token
            self.query = query
            self.sources = sources
        }
    }

    private final class AsyncSlotPool: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var available: Int
        private var waiters: [CheckedContinuation<Bool, Never>] = []
        private var closed = false

        init(limit: Int) {
            self.limit = max(1, limit)
            self.available = self.limit
        }

        func acquire() async -> Bool {
            if Task.isCancelled { return false }
            lock.lock()
            if closed {
                lock.unlock()
                return false
            }
            if available > 0 {
                available -= 1
                lock.unlock()
                return true
            }
            lock.unlock()
            return await withCheckedContinuation { cont in
                lock.lock()
                if closed {
                    lock.unlock()
                    cont.resume(returning: false)
                    return
                }
                if available > 0 {
                    available -= 1
                    lock.unlock()
                    cont.resume(returning: true)
                    return
                }
                waiters.append(cont)
                lock.unlock()
            }
        }

        func release() {
            lock.lock()
            if closed {
                lock.unlock()
                return
            }
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                lock.unlock()
                next.resume(returning: true)
                return
            }
            if available < limit {
                available += 1
            }
            lock.unlock()
        }

        func shutdown() {
            lock.lock()
            closed = true
            let pending = waiters
            waiters.removeAll()
            lock.unlock()
            for cont in pending {
                cont.resume(returning: false)
            }
        }
    }

    private let lock = NSLock()
    private let callbackExecutor: CallbackExecutor
    private let timeoutMs: Int64
    private let slotPool: AsyncSlotPool
    private let timerQueue = DispatchQueue(label: "com.xxcomic.detail-source-search-timer", qos: .utility)

    private var matches: [String: ComicSummary] = [:]
    private var jobs: [String: Job] = [:]
    private var completed = Set<String>()
    private var sourceIds: [String] = []
    private var title = ""
    private var initialSource = ""
    private var cacheStartedNanos: UInt64 = 0
    private var revision = 0
    private var listenerToken = 0
    private var pendingStartToken = 0
    private var pendingStart: PendingStart?
    private var listener: Listener?
    private var titleExcludeFilter: (@Sendable (String) -> Bool)?
    private var closed = false

    public convenience init(
        timeoutMs: Int64 = 10_000,
        maxConcurrency: Int = 3,
        callbackQueue: DispatchQueue = .main
    ) {
        self.init(
            callbackExecutor: { block in callbackQueue.async(execute: block) },
            timeoutMs: timeoutMs,
            maxConcurrency: maxConcurrency
        )
    }

    public init(
        callbackExecutor: @escaping CallbackExecutor,
        timeoutMs: Int64 = 10_000,
        maxConcurrency: Int = 3
    ) {
        self.callbackExecutor = callbackExecutor
        self.timeoutMs = timeoutMs
        self.slotPool = AsyncSlotPool(limit: maxConcurrency)
    }

    deinit {
        close()
    }

    public static func effectiveTimeoutMs(source: any ComicSource, timeoutMs: Int64) -> Int64 {
        FailoverComicSource.isFailoverChain(source) ? max(timeoutMs, 16_000) : timeoutMs
    }

    public func setTitleExcludeFilter(_ titleExcludeFilter: (@Sendable (String) -> Bool)?) {
        lock.lock()
        self.titleExcludeFilter = titleExcludeFilter
        lock.unlock()
    }

    public func start(
        current: ComicSummary,
        sources: [any ComicSource],
        listener: @escaping Listener
    ) {
        lock.lock()
        let existingFilter = titleExcludeFilter
        lock.unlock()
        startInternal(delayMs: 0, current: current, sources: sources, titleExcludeFilter: existingFilter, listener: listener)
    }

    public func start(
        current: ComicSummary,
        sources: [any ComicSource],
        titleExcludeFilter: (@Sendable (String) -> Bool)?,
        listener: @escaping Listener
    ) {
        startInternal(delayMs: 0, current: current, sources: sources, titleExcludeFilter: titleExcludeFilter, listener: listener)
    }

    public func startDelayed(
        delayMs: Int64 = 1200,
        current: ComicSummary,
        sources: [any ComicSource],
        listener: @escaping Listener
    ) {
        lock.lock()
        let existingFilter = titleExcludeFilter
        lock.unlock()
        startInternal(delayMs: max(0, delayMs), current: current, sources: sources, titleExcludeFilter: existingFilter, listener: listener)
    }

    public func startDelayed(
        delayMs: Int64 = 1200,
        current: ComicSummary,
        sources: [any ComicSource],
        titleExcludeFilter: (@Sendable (String) -> Bool)?,
        listener: @escaping Listener
    ) {
        startInternal(delayMs: max(0, delayMs), current: current, sources: sources, titleExcludeFilter: titleExcludeFilter, listener: listener)
    }

    public func flushPendingStartNow() {
        lock.lock()
        guard !closed, let pending = pendingStart else {
            lock.unlock()
            return
        }
        pendingStart = nil
        pending.timerItem?.cancel()
        submitSourcesLocked(query: pending.query, sources: pending.sources)
        publishLocked()
        lock.unlock()
    }

    private func startInternal(
        delayMs: Int64,
        current: ComicSummary,
        sources: [any ComicSource],
        titleExcludeFilter: (@Sendable (String) -> Bool)?,
        listener: @escaping Listener
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }

        self.titleExcludeFilter = titleExcludeFilter
        let query = SearchRules.trim(current.title)
        var ids = [String]()
        for source in sources where source.supportsSearch {
            ids.append(source.id)
        }
        let nowNanos = DispatchTime.now().uptimeNanoseconds
        let cacheFresh = (title == query)
            && (sourceIds == ids)
            && (cacheStartedNanos > 0)
            && (nowNanos &- cacheStartedNanos <= Self.cacheFreshNanos)
        if !cacheFresh {
            detachLocked()
            matches.removeAll()
            completed.removeAll()
            title = query
            sourceIds = ids
            initialSource = current.sourceId
            cacheStartedNanos = nowNanos
        }
        listenerToken &+= 1
        self.listener = listener
        matches[current.sourceId] = current
        completed.insert(current.sourceId)

        var toSearch = [any ComicSource]()
        if !query.isEmpty {
            for source in sources where source.supportsSearch {
                let id = source.id
                if completed.contains(id) || jobs[id] != nil { continue }
                toSearch.append(source)
            }
        }

        if toSearch.isEmpty {
            cancelPendingStartLocked()
            publishLocked()
            return
        }

        if delayMs <= 0 {
            cancelPendingStartLocked()
            submitSourcesLocked(query: query, sources: toSearch)
            publishLocked()
            return
        }

        if pendingStart == nil || pendingStart?.query != query {
            cancelPendingStartLocked()
            pendingStartToken += 1
            let pending = PendingStart(token: pendingStartToken, query: query, sources: toSearch)
            pendingStart = pending
            let item = DispatchWorkItem { [weak self] in
                self?.executePendingStart(pending)
            }
            pending.timerItem = item
            timerQueue.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs)), execute: item)
        }
        publishLocked()
    }

    private func executePendingStart(_ pending: PendingStart) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, pendingStart === pending else { return }
        pendingStart = nil
        submitSourcesLocked(query: pending.query, sources: pending.sources)
        publishLocked()
    }

    private func cancelPendingStartLocked() {
        if let pending = pendingStart {
            pending.timerItem?.cancel()
            pendingStart = nil
        }
    }

    private func submitSourcesLocked(query: String, sources: [any ComicSource]) {
        guard !closed, !query.isEmpty else { return }
        for source in sources where source.supportsSearch {
            let id = source.id
            if completed.contains(id) || jobs[id] != nil { continue }
            let job = Job()
            jobs[id] = job
            let baseTimeoutMs = timeoutMs
            let task = Task { [weak self] in
                guard let self else { return }
                let acquired = await self.slotPool.acquire()
                guard acquired else { return }
                defer { self.slotPool.release() }

                if Task.isCancelled { return }
                let effectiveMs = Self.effectiveTimeoutMs(source: source, timeoutMs: baseTimeoutMs)
                self.lock.lock()
                if self.closed || self.jobs[id] !== job {
                    self.lock.unlock()
                    return
                }
                let timeoutWork = DispatchWorkItem { [weak self] in
                    self?.finish(id: id, job: job, match: nil)
                }
                job.timeoutItem = timeoutWork
                self.timerQueue.asyncAfter(deadline: .now() + .milliseconds(Int(effectiveMs)), execute: timeoutWork)
                self.lock.unlock()

                let match: ComicSummary? = await RuleCallPriority.withBackgroundPriority {
                    do {
                        let results = try await source.search(keyword: query, page: 1)
                        return Self.firstExactMatch(title: query, results: results, sourceId: id)
                    } catch {
                        // Failed or verification-required sources do not interrupt the detail screen.
                        return nil
                    }
                }
                self.finish(id: id, job: job, match: match)
            }
            job.workTask = task
        }
    }

    private func finish(id: String, job: Job, match: ComicSummary?) {
        lock.lock()
        defer { lock.unlock() }
        guard jobs[id] === job else { return }
        jobs.removeValue(forKey: id)
        completed.insert(id)
        job.timeoutItem?.cancel()
        job.workTask?.cancel()
        if let match, !isTitleExcludedLocked(match.title) {
            matches[id] = match
        }
        publishLocked()
    }

    private func isTitleExcludedLocked(_ comicTitle: String) -> Bool {
        titleExcludeFilter?(comicTitle) ?? false
    }

    private func publishLocked() {
        guard let target = listener else { return }
        var result = [ComicSummary]()
        if let initialItem = matches[initialSource], !isTitleExcludedLocked(initialItem.title) {
            result.append(initialItem)
        }
        for id in sourceIds where id != initialSource {
            if let candidate = matches[id], !isTitleExcludedLocked(candidate.title) {
                result.append(candidate)
            }
        }
        let snapshotResult = result
        let loading = !jobs.isEmpty || pendingStart != nil
        revision &+= 1
        let token = revision
        let expectedListenerToken = listenerToken
        callbackExecutor { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldDeliver = !self.closed
                && self.listener != nil
                && self.listenerToken == expectedListenerToken
                && self.revision == token
            self.lock.unlock()
            if shouldDeliver {
                target(snapshotResult, loading)
            }
        }
    }

    public func detach() {
        lock.lock()
        detachLocked()
        lock.unlock()
    }

    private func detachLocked() {
        listener = nil
        listenerToken &+= 1
        revision &+= 1
        let cancelledUnstartedPending = pendingStart != nil && jobs.isEmpty && completed.count <= 1
        cancelPendingStartLocked()
        if cancelledUnstartedPending {
            title = ""
            sourceIds.removeAll()
            cacheStartedNanos = 0
        }
        for job in jobs.values {
            job.timeoutItem?.cancel()
            job.workTask?.cancel()
        }
        jobs.removeAll()
    }

    public func close() {
        lock.lock()
        detachLocked()
        closed = true
        lock.unlock()
        slotPool.shutdown()
    }

    private static func firstExactMatch(
        title: String,
        results: [ComicSummary],
        sourceId: String
    ) -> ComicSummary? {
        let expected = SearchRules.trim(title)
        guard !expected.isEmpty else { return nil }
        for item in results {
            if item.sourceId == sourceId && !item.comicId.isEmpty && SearchRules.isExact(title: item.title, query: expected) {
                return item
            }
        }
        return nil
    }
}
