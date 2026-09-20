import Foundation

public protocol DownloadRepository: AnyObject, Sendable {
    func list() -> [DownloadTask]
    func get(id: String) -> DownloadTask?
    func save(task: DownloadTask)
}

public final class DownloadCoordinator: @unchecked Sendable {
    private static let lock = NSLock()
    private static var generationCounter: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    public static func nextGeneration() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        generationCounter += 1
        return generationCounter
    }

    private let repository: DownloadRepository
    private let stateLock = NSLock()

    public init(repository: DownloadRepository) {
        self.repository = repository
    }

    public func enqueue(source: String, comic: String, chapters: [Chapter], selected: [String]) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let wanted = Set(selected)
        for (i, ch) in chapters.enumerated() {
            guard wanted.contains(ch.chapterId) else { continue }
            guard let id = try? DownloadModels.key(source, comic, ch.chapterId),
                  let bookId = try? DownloadModels.bookId(source: source, comic: comic) else { continue }
            if repository.get(id: id) != nil { continue }
            let t = DownloadTask(
                id: id,
                bookId: bookId,
                sourceId: source,
                comicId: comic,
                chapterId: ch.chapterId,
                title: ch.title,
                url: ch.url,
                order: i,
                state: .queued
            )
            repository.save(task: t)
        }
    }

    public func enqueueFiles(source: String, comic: String, files: [FileResource], selected: [String]) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let wanted = Set(selected)
        let sortedFiles = files.sorted { $0.order < $1.order }
        for (i, f) in sortedFiles.enumerated() {
            guard wanted.contains(f.fileId) else { continue }
            guard let id = try? DownloadModels.fileTaskId(source: source, comic: comic, file: f.fileId),
                  let bookId = try? DownloadModels.fileBookId(source: source, comic: comic, file: f.fileId) else { continue }
            if let existing = repository.get(id: id) {
                if existing.state != .completed || (existing.revision == f.revision && existing.sha256 == f.sha256) {
                    continue
                }
            }
            let t = DownloadTask(
                id: id,
                bookId: bookId,
                sourceId: source,
                comicId: comic,
                chapterId: f.fileId,
                title: f.title,
                url: "",
                order: f.order >= 0 ? f.order : i,
                totalPages: 1,
                donePages: 0,
                state: .queued,
                isFileTask: true,
                fileId: f.fileId,
                revision: f.revision,
                expectedFormat: f.expectedFormat,
                sha256: f.sha256,
                expiresAt: f.expiresAt,
                expectedBytes: f.bytes
            )
            repository.save(task: t)
        }
    }

    public func claim(now: Int64, connected: Bool, wifi: Bool, wifiOnly: Bool) -> DownloadTask? {
        claim(now: now, connected: connected, wifi: wifi, wifiOnly: wifiOnly, maxActive: 1, maxPerSource: 1)
    }

    public func claim(now: Int64, connected: Bool, wifi: Bool, wifiOnly: Bool, maxActive: Int, maxPerSource: Int) -> DownloadTask? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let tasks = repository.list()
        var activeCount = 0
        var sourceCounts: [String: Int] = [:]
        for t in tasks {
            if DownloadModels.active(t.state) {
                activeCount += 1
                sourceCounts[t.sourceId, default: 0] += 1
            }
        }
        guard activeCount < max(1, maxActive) else { return nil }

        for original in tasks {
            guard original.state == .queued || original.state == .waitingNetwork else { continue }
            if let count = sourceCounts[original.sourceId], count >= max(1, maxPerSource) {
                continue
            }
            var t = original
            if !connected || (wifiOnly && !wifi) {
                t.state = .waitingNetwork
                repository.save(task: t)
                continue
            }
            if t.nextAttempt > now { continue }
            t.state = .resolving
            t.generation = Self.nextGeneration()
            repository.save(task: t)
            return t
        }
        return nil
    }

    public func isCurrent(_ lease: DownloadTask) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let t = repository.get(id: lease.id) else { return false }
        return t.generation == lease.generation && DownloadModels.active(t.state)
    }

    @discardableResult
    public func update(lease: DownloadTask, state: DownloadState, done: Int, total: Int, bytes: Int64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let t = repository.get(id: lease.id), t.generation == lease.generation, DownloadModels.active(t.state) else {
            return false
        }
        var updated = t
        updated.state = state
        updated.donePages = done
        updated.totalPages = total
        updated.bytes = bytes
        repository.save(task: updated)
        return true
    }

    @discardableResult
    public func complete(lease: DownloadTask) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let t = repository.get(id: lease.id), t.generation == lease.generation, DownloadModels.active(t.state) else {
            return false
        }
        var updated = t
        updated.state = .completed
        updated.error = ""
        repository.save(task: updated)
        return true
    }

    private func change(id: String, state: DownloadState, reset: Bool) {
        guard let found = repository.get(id: id), found.state != .completed, found.state != .deleting else { return }
        var t = found
        t.generation = Self.nextGeneration()
        t.state = state
        if reset {
            t.failures = 0
            t.nextAttempt = 0
            t.error = ""
        }
        repository.save(task: t)
    }

    public func pause(id: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        change(id: id, state: .pausedUser, reset: false)
    }

    public func resume(id: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        change(id: id, state: .queued, reset: true)
    }

    public func cancel(id: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        change(id: id, state: .cancelled, reset: false)
    }

    public func waitForNetwork(_ lease: DownloadTask) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let t = repository.get(id: lease.id), t.generation == lease.generation && DownloadModels.active(t.state) {
            change(id: lease.id, state: .waitingNetwork, reset: false)
        }
    }

    public func waitForVerification(_ lease: DownloadTask) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let t = repository.get(id: lease.id), t.generation == lease.generation && DownloadModels.active(t.state) else { return }
        for item in repository.list() {
            if item.sourceId == lease.sourceId && (DownloadModels.active(item.state) || item.state == .queued || item.state == .waitingNetwork) {
                change(id: item.id, state: .waitingVerification, reset: false)
            }
        }
    }

    public func verificationReady(source: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        for t in repository.list() where t.sourceId == source && t.state == .waitingVerification {
            change(id: t.id, state: .queued, reset: true)
        }
    }

    public func failed(lease: DownloadTask, now: Int64, error: String, retryAfter: Int64) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let current = repository.get(id: lease.id), current.generation == lease.generation && DownloadModels.active(current.state) else { return }
        var t = current
        t.failures += 1
        t.generation = Self.nextGeneration()
        t.error = error
        let delays: [Int64] = [2000, 5000, 15000]
        t.state = t.failures > delays.count ? .failed : .queued
        let baseDelay: Int64 = t.failures <= delays.count ? delays[t.failures - 1] : 0
        let boundedRetryAfter = min(Int64(15 * 60 * 1000), max(0, retryAfter))
        t.nextAttempt = now + max(baseDelay, boundedRetryAfter)
        repository.save(task: t)

        if retryAfter > 0 {
            for other in repository.list() {
                if other.sourceId == t.sourceId && (other.state == .queued || other.state == .waitingNetwork) {
                    var delayed = other
                    delayed.nextAttempt = max(delayed.nextAttempt, t.nextAttempt)
                    repository.save(task: delayed)
                }
            }
        }
    }

    public func recover() {
        stateLock.lock()
        defer { stateLock.unlock() }
        for t in repository.list() where DownloadModels.active(t.state) {
            change(id: t.id, state: .queued, reset: false)
        }
    }

    public func recoverNetwork() {
        stateLock.lock()
        defer { stateLock.unlock() }
        for t in repository.list() where t.state == .waitingNetwork {
            change(id: t.id, state: .queued, reset: false)
        }
    }
}

