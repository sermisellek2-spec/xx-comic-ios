import Foundation

/// Thread-safe bounded LRU cache used by failover registries.
private final class BoundedLRUMap<Key: Hashable, Value> {
    private final class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private let maxEntries: Int
    private var map: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?

    init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
    }

    func get(_ key: Key) -> Value? {
        guard let node = map[key] else { return nil }
        touch(node)
        return node.value
    }

    func put(_ key: Key, value: Value) {
        if let existing = map[key] {
            existing.value = value
            touch(existing)
            return
        }
        let node = Node(key: key, value: value)
        insertAtTail(node)
        map[key] = node
        while map.count > maxEntries, let eldest = head {
            unlink(eldest)
            map.removeValue(forKey: eldest.key)
        }
    }

    @discardableResult
    func remove(_ key: Key) -> Value? {
        guard let node = map.removeValue(forKey: key) else { return nil }
        unlink(node)
        return node.value
    }

    private func touch(_ node: Node) {
        guard tail !== node else { return }
        unlink(node)
        insertAtTail(node)
    }

    private func insertAtTail(_ node: Node) {
        node.prev = tail
        node.next = nil
        if let tail {
            tail.next = node
        } else {
            head = node
        }
        tail = node
    }

    private func unlink(_ node: Node) {
        let prev = node.prev
        let next = node.next
        if let prev {
            prev.next = next
        } else {
            head = next
        }
        if let next {
            next.prev = prev
        } else {
            tail = prev
        }
        node.prev = nil
        node.next = nil
    }
}

/// In-memory & debounced persistent registry of failover member cooldowns, book/chapter metadata, and chapter caches.
public final class FailoverContextRegistry: @unchecked Sendable {
    public static let defaultCooldownMs: Int64 = 180_000
    public static let maxPersistedCooldownMs: Int64 = 600_000
    public static let chapterCacheTtlMs: Int64 = 600_000
    private static let persistVersion = 1
    private static let persistDebounceMs = 150
    private static let maxHealthFileBytes = 1024 * 1024
    private static let maxBooks = 1024
    private static let maxChapterContexts = 8192
    private static let maxChapterCaches = 256

    public struct BookContext: Sendable {
        public let title: String
        public let author: String
        public let latestChapter: String
        public let referenceChapters: [Chapter]

        public init(title: String, author: String, latestChapter: String, referenceChapters: [Chapter]) {
            self.title = title
            self.author = author
            self.latestChapter = latestChapter
            self.referenceChapters = referenceChapters
        }
    }

    public struct ChapterContext: Sendable {
        public let comicId: String
        public let ownerMemberId: String
        public let canonicalChapter: Chapter?
        public let ownerRawUrl: String

        public init(comicId: String, ownerMemberId: String, canonicalChapter: Chapter?, ownerRawUrl: String) {
            self.comicId = comicId
            self.ownerMemberId = ownerMemberId
            self.canonicalChapter = canonicalChapter
            self.ownerRawUrl = ownerRawUrl
        }
    }

    private struct CachedChapterList {
        let chapters: [Chapter]
        let expiresAtMs: Int64
    }

    private let cooldownMs: Int64
    private let clockMs: @Sendable () -> Int64
    private let healthFileURL: URL?

    private let persistQueue = DispatchQueue(label: "com.xxcomic.failover-health-persist", qos: .utility)
    private let persistLock = NSLock()
    private let writeLock = NSLock()
    private let dataLock = NSLock()

    private var unhealthyUntil: [String: Int64] = [:]
    private var pendingPersistSeq: Int64 = 0
    private var flushedPersistSeq: Int64 = 0
    private var persistScheduled = false
    private var corruptOnLoad = false
    private var internalLastPersistenceError = ""

    private let books = BoundedLRUMap<String, BookContext>(maxEntries: maxBooks)
    private let chapters = BoundedLRUMap<String, ChapterContext>(maxEntries: maxChapterContexts)
    private let memberChapterCaches = BoundedLRUMap<String, CachedChapterList>(maxEntries: maxChapterCaches)

    public convenience init(healthFileURL: URL?) {
        self.init(cooldownMs: Self.defaultCooldownMs, healthFileURL: healthFileURL)
    }

    public init(
        cooldownMs: Int64 = defaultCooldownMs,
        clockMs: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        healthFileURL: URL? = nil
    ) {
        self.cooldownMs = max(0, cooldownMs)
        self.clockMs = clockMs
        self.healthFileURL = healthFileURL
        loadHealthFromDisk()
    }

    public var lastPersistenceError: String {
        persistLock.lock()
        defer { persistLock.unlock() }
        return internalLastPersistenceError
    }

    public func isHealthy(_ memberId: String?) -> Bool {
        guard let memberId, !memberId.isEmpty else { return false }
        persistLock.lock()
        defer { persistLock.unlock() }
        guard let until = unhealthyUntil[memberId] else { return true }
        let now = clockMs()
        if now >= until {
            unhealthyUntil.removeValue(forKey: memberId)
            schedulePersistLocked()
            return true
        }
        return false
    }

    public func markUnhealthy(_ memberId: String?) {
        guard let memberId, !memberId.isEmpty, cooldownMs > 0 else { return }
        let until = Self.saturatingAdd(clockMs(), cooldownMs)
        persistLock.lock()
        let prev = unhealthyUntil.updateValue(until, forKey: memberId)
        if prev == nil || prev != until {
            schedulePersistLocked()
        }
        persistLock.unlock()
    }

    public func markHealthy(_ memberId: String?) {
        guard let memberId, !memberId.isEmpty else { return }
        persistLock.lock()
        if unhealthyUntil.removeValue(forKey: memberId) != nil {
            schedulePersistLocked()
        }
        persistLock.unlock()
    }

    public func clearHealth() {
        persistLock.lock()
        if !unhealthyUntil.isEmpty {
            unhealthyUntil.removeAll()
            schedulePersistLocked()
        }
        persistLock.unlock()
    }

    public func unhealthyRemainingMs(_ memberId: String?) -> Int64 {
        guard let memberId, !memberId.isEmpty else { return 0 }
        persistLock.lock()
        let until = unhealthyUntil[memberId]
        persistLock.unlock()
        guard let until else { return 0 }
        return max(0, until - clockMs())
    }

    public func flushPersistenceForTesting() {
        guard healthFileURL != nil else { return }
        persistLock.lock()
        let targetSeq = pendingPersistSeq
        persistLock.unlock()
        if targetSeq == 0 { return }
        while true {
            persistLock.lock()
            let done = flushedPersistSeq >= targetSeq
            persistLock.unlock()
            if done { return }
            writePendingOnce()
        }
    }

    private func loadHealthFromDisk() {
        guard let healthFileURL else { return }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: healthFileURL.path, isDirectory: &isDir), !isDir.boolValue else {
            return
        }
        do {
            let attrs = try fm.attributesOfItem(atPath: healthFileURL.path)
            if let size = attrs[.size] as? NSNumber, size.intValue > Self.maxHealthFileBytes {
                persistLock.lock()
                corruptOnLoad = true
                internalLastPersistenceError = "健康状态文件超过大小限制"
                persistLock.unlock()
                return
            }
            let data = try Data(contentsOf: healthFileURL)
            if data.count > Self.maxHealthFileBytes {
                persistLock.lock()
                corruptOnLoad = true
                internalLastPersistenceError = "健康状态文件超过大小限制"
                persistLock.unlock()
                return
            }
            let raw = String(decoding: data, as: UTF8.self)
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                persistLock.lock()
                corruptOnLoad = true
                internalLastPersistenceError = "健康状态文件为空"
                persistLock.unlock()
                return
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                persistLock.lock()
                corruptOnLoad = true
                internalLastPersistenceError = "健康状态文件格式错误"
                persistLock.unlock()
                return
            }
            guard (root["version"] as? Int) == Self.persistVersion else {
                persistLock.lock()
                corruptOnLoad = true
                internalLastPersistenceError = "健康状态文件版本不支持"
                persistLock.unlock()
                return
            }
            guard let entries = root["unhealthyUntil"] as? [String: Any] else {
                persistLock.lock()
                corruptOnLoad = true
                internalLastPersistenceError = "健康状态文件缺少记录字段"
                persistLock.unlock()
                return
            }

            let now = clockMs()
            let maxUntil = Self.saturatingAdd(now, Self.maxPersistedCooldownMs)
            persistLock.lock()
            for (memberId, value) in entries {
                guard !memberId.isEmpty,
                      !JsonValueHelper.isJsonBoolean(value),
                      let num = value as? NSNumber else {
                    continue
                }
                let until = num.int64Value
                if until <= now { continue }
                let clampedUntil = min(until, maxUntil)
                if clampedUntil > now {
                    unhealthyUntil[memberId] = clampedUntil
                }
            }
            persistLock.unlock()
        } catch {
            // Corrupt or unreadable health cache must never crash or overwrite the original file on load.
            persistLock.lock()
            corruptOnLoad = true
            internalLastPersistenceError = error.localizedDescription
            persistLock.unlock()
        }
    }

    private func schedulePersistLocked() {
        guard healthFileURL != nil else { return }
        pendingPersistSeq += 1
        if !persistScheduled {
            persistScheduled = true
            schedulePersistTask(delayMs: Self.persistDebounceMs)
        }
    }

    private func schedulePersistTask(delayMs: Int) {
        persistQueue.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
            self?.writePendingOnce()
        }
    }

    private func writePendingOnce() {
        guard healthFileURL != nil else { return }
        writeLock.lock()
        defer { writeLock.unlock() }

        persistLock.lock()
        persistScheduled = false
        if flushedPersistSeq >= pendingPersistSeq {
            persistLock.unlock()
            return
        }
        let targetSeq = pendingPersistSeq
        let snapshot = snapshotUnhealthyForPersistLocked()
        let needsCorruptBackup = corruptOnLoad
        persistLock.unlock()

        var writeError: String?
        do {
            try writeHealthFileAtomically(snapshot: snapshot, backupCorruptIfNeeded: needsCorruptBackup)
            if needsCorruptBackup {
                persistLock.lock()
                corruptOnLoad = false
                persistLock.unlock()
            }
        } catch {
            writeError = error.localizedDescription
        }

        persistLock.lock()
        if let writeError {
            internalLastPersistenceError = writeError
        }
        if targetSeq > flushedPersistSeq {
            flushedPersistSeq = targetSeq
        }
        if flushedPersistSeq < pendingPersistSeq && !persistScheduled {
            persistScheduled = true
            schedulePersistTask(delayMs: Self.persistDebounceMs)
        }
        persistLock.unlock()
    }

    private func snapshotUnhealthyForPersistLocked() -> [String: Int64] {
        let now = clockMs()
        let maxUntil = Self.saturatingAdd(now, Self.maxPersistedCooldownMs)
        var out = [String: Int64]()
        var expired = [String]()
        for (memberId, until) in unhealthyUntil {
            if until <= now {
                expired.append(memberId)
            } else {
                out[memberId] = min(until, maxUntil)
            }
        }
        for key in expired {
            unhealthyUntil.removeValue(forKey: key)
        }
        return out
    }

    private func writeHealthFileAtomically(snapshot: [String: Int64], backupCorruptIfNeeded: Bool) throws {
        guard let healthFileURL else { return }
        let fm = FileManager.default
        let parentURL = healthFileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentURL.path) {
            try fm.createDirectory(at: parentURL, withIntermediateDirectories: true, attributes: nil)
        }
        if backupCorruptIfNeeded {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: healthFileURL.path, isDirectory: &isDir), !isDir.boolValue {
                let backupURL = parentURL.appendingPathComponent(healthFileURL.lastPathComponent + ".corrupt")
                if !fm.fileExists(atPath: backupURL.path) {
                    try? AtomicFileOps.copyFile(from: healthFileURL, to: backupURL)
                }
            }
        }

        var entries = [String: NSNumber]()
        for (memberId, until) in snapshot {
            entries[memberId] = NSNumber(value: until)
        }
        let root: [String: Any] = [
            "version": Self.persistVersion,
            "unhealthyUntil": entries
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        try AtomicFileOps.writeAtomically(data, to: healthFileURL)
    }

    private static func saturatingAdd(_ base: Int64, _ delta: Int64) -> Int64 {
        if delta <= 0 { return base }
        if base > Int64.max - delta { return Int64.max }
        return base + delta
    }

    public func recordSummary(identitySourceId: String, summary: ComicSummary?) {
        guard let summary, !summary.comicId.isEmpty else { return }
        let key = Self.key(identitySourceId, summary.comicId)
        dataLock.lock()
        defer { dataLock.unlock() }
        let existing = books.get(key)
        let title = Self.pick(summary.title, fallback: existing?.title ?? "")
        let author = Self.pick(existing?.author ?? "", fallback: summary.subtitle)
        let latest = Self.pick(summary.latestChapter, fallback: existing?.latestChapter ?? "")
        let refs = existing?.referenceChapters ?? []
        books.put(key, value: BookContext(title: title, author: author, latestChapter: latest, referenceChapters: refs))
    }

    public func recordDetail(
        identitySourceId: String,
        canonicalComicId: String,
        detail: ComicDetail?,
        fromNativePrimary: Bool
    ) {
        guard let detail, !canonicalComicId.isEmpty else { return }
        let key = Self.key(identitySourceId, canonicalComicId)
        dataLock.lock()
        defer { dataLock.unlock() }
        let existing = books.get(key)
        let detailTitle = detail.summary.title
        let detailLatest = !detail.latestChapter.isEmpty ? detail.latestChapter : (detail.summary.latestChapter ?? "")
        let title = Self.pick(detailTitle, fallback: existing?.title ?? "")
        let author = Self.pick(detail.author, fallback: existing?.author ?? "")
        let latest = Self.pick(detailLatest, fallback: existing?.latestChapter ?? "")
        var refs = existing?.referenceChapters ?? []
        if fromNativePrimary && !detail.chapters.isEmpty {
            refs = detail.chapters
        }
        books.put(key, value: BookContext(title: title, author: author, latestChapter: latest, referenceChapters: refs))
    }

    public func recordChapters(
        identitySourceId: String,
        canonicalComicId: String,
        list: [Chapter]?,
        fromNativePrimary: Bool
    ) {
        guard !canonicalComicId.isEmpty, let list, !list.isEmpty else { return }
        let key = Self.key(identitySourceId, canonicalComicId)
        dataLock.lock()
        defer { dataLock.unlock() }
        let existing = books.get(key)
        if !fromNativePrimary && existing != nil { return }
        let refs = fromNativePrimary ? list : (existing?.referenceChapters ?? [])
        books.put(
            key,
            value: BookContext(
                title: existing?.title ?? "",
                author: existing?.author ?? "",
                latestChapter: existing?.latestChapter ?? "",
                referenceChapters: refs
            )
        )
    }

    public func findBook(identitySourceId: String, canonicalComicId: String?) -> BookContext? {
        guard let canonicalComicId, !canonicalComicId.isEmpty else { return nil }
        let key = Self.key(identitySourceId, canonicalComicId)
        dataLock.lock()
        defer { dataLock.unlock() }
        return books.get(key)
    }

    public func recordChapter(
        identitySourceId: String,
        observedUrl: String?,
        canonicalComicId: String?,
        ownerMemberId: String?,
        canonicalChapter: Chapter?,
        ownerRawUrl: String
    ) {
        guard let observedUrl, !observedUrl.isEmpty,
              let canonicalComicId, !canonicalComicId.isEmpty,
              let ownerMemberId, !ownerMemberId.isEmpty else {
            return
        }
        let key = Self.key(identitySourceId, observedUrl)
        dataLock.lock()
        defer { dataLock.unlock() }
        chapters.put(
            key,
            value: ChapterContext(
                comicId: canonicalComicId,
                ownerMemberId: ownerMemberId,
                canonicalChapter: canonicalChapter,
                ownerRawUrl: ownerRawUrl
            )
        )
    }

    public func findChapter(identitySourceId: String, chapterUrl: String?) -> ChapterContext? {
        guard let chapterUrl, !chapterUrl.isEmpty else { return nil }
        let key = Self.key(identitySourceId, chapterUrl)
        dataLock.lock()
        defer { dataLock.unlock() }
        return chapters.get(key)
    }

    public func putMemberChapters(
        identitySourceId: String,
        canonicalComicId: String?,
        memberId: String?,
        list: [Chapter]?
    ) {
        guard let canonicalComicId, !canonicalComicId.isEmpty,
              let memberId, !memberId.isEmpty,
              let list else {
            return
        }
        let cacheKey = Self.memberCacheKey(identitySourceId, canonicalComicId, memberId)
        let expiresAt = clockMs() + Self.chapterCacheTtlMs
        dataLock.lock()
        defer { dataLock.unlock() }
        memberChapterCaches.put(cacheKey, value: CachedChapterList(chapters: list, expiresAtMs: expiresAt))
    }

    public func getMemberChapters(
        identitySourceId: String,
        canonicalComicId: String?,
        memberId: String?
    ) -> [Chapter]? {
        guard let canonicalComicId, !canonicalComicId.isEmpty,
              let memberId, !memberId.isEmpty else {
            return nil
        }
        let cacheKey = Self.memberCacheKey(identitySourceId, canonicalComicId, memberId)
        dataLock.lock()
        defer { dataLock.unlock() }
        guard let cached = memberChapterCaches.get(cacheKey) else { return nil }
        if clockMs() >= cached.expiresAtMs {
            memberChapterCaches.remove(cacheKey)
            return nil
        }
        return cached.chapters
    }

    public func invalidateMemberChapters(
        identitySourceId: String,
        canonicalComicId: String?,
        memberId: String?
    ) {
        guard let canonicalComicId, !canonicalComicId.isEmpty,
              let memberId, !memberId.isEmpty else {
            return
        }
        let cacheKey = Self.memberCacheKey(identitySourceId, canonicalComicId, memberId)
        dataLock.lock()
        defer { dataLock.unlock() }
        memberChapterCaches.remove(cacheKey)
    }

    private static func key(_ identitySourceId: String, _ itemKey: String) -> String {
        "\(identitySourceId)\0\(itemKey)"
    }

    private static func memberCacheKey(_ identitySourceId: String, _ canonicalComicId: String, _ memberId: String) -> String {
        "\(identitySourceId)\0\(canonicalComicId)\0\(memberId)"
    }

    private static func pick(_ preferred: String?, fallback: String) -> String {
        if let preferred, !preferred.isEmpty {
            return preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallback
    }
}
