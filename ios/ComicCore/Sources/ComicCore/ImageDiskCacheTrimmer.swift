import Foundation

/// Lock-free size tracking and single-stat LRU trimming for `cache/images`.
///
/// Captures each file's modification time and size once into an immutable `CacheEntry`
/// before sorting, then trims to an 80% hysteresis low-water mark.
public final class ImageDiskCacheTrimmer: @unchecked Sendable {
    public static let defaultMaxBytes: Int64 = 1000 * 1024 * 1024 // 1000 MiB
    public static let ACCESS_TIME_TOUCH_INTERVAL_MS: Int64 = 300_000
    public static let accessTimeTouchIntervalMs = ACCESS_TIME_TOUCH_INTERVAL_MS
    private static let uninitialized: Int64 = -1

    public struct CacheEntry: Equatable, Sendable {
        public let url: URL
        public let lastModifiedMs: Int64
        public let length: Int64

        public init(url: URL, lastModifiedMs: Int64, length: Int64) {
            self.url = url
            self.lastModifiedMs = lastModifiedMs
            self.length = length
        }
    }

    public let cacheDir: URL

    private let stateLock = NSLock()
    private let scanLock = NSLock()
    private var trackedBytesValue: Int64 = uninitialized
    private var trimInProgress = false
    private var trimPending = false

    public init(cacheDir: URL) {
        self.cacheDir = cacheDir
    }

    /// Returns `true` only when more than 5 minutes elapsed since `lastModifiedMs`.
    public static func shouldTouchAccessTime(lastModifiedMs: Int64, nowMs: Int64) -> Bool {
        nowMs - lastModifiedMs > ACCESS_TIME_TOUCH_INTERVAL_MS
    }

    /// Computes the 80% hysteresis low-water mark without overflowing near `Int64.max`.
    public static func lowWaterMarkBytes(_ maxBytes: Int64) -> Int64 {
        guard maxBytes > 0 else { return 0 }
        if maxBytes <= Int64.max / 4 {
            return (maxBytes * 4) / 5
        }
        return (maxBytes / 5) * 4 + ((maxBytes % 5) * 4) / 5
    }

    /// Lists `dir` regular files and returns immutable `CacheEntry` instances sorted by
    /// ascending `lastModifiedMs`, reading file attributes at most once per file.
    public static func collectSortedEntries(in dir: URL) -> (entries: [CacheEntry], totalBytes: Int64) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
            options: []
        ) else {
            return ([], 0)
        }
        var entries: [CacheEntry] = []
        entries.reserveCapacity(urls.count)
        var total: Int64 = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }
            let mtimeMs = Int64(((values.contentModificationDate?.timeIntervalSince1970) ?? 0) * 1000)
            let len = Int64(max(0, values.fileSize ?? 0))
            entries.append(CacheEntry(url: url, lastModifiedMs: mtimeMs, length: len))
            total += len
        }
        entries.sort {
            if $0.lastModifiedMs == $1.lastModifiedMs {
                return $0.url.path < $1.url.path
            }
            return $0.lastModifiedMs < $1.lastModifiedMs
        }
        return (entries, total)
    }

    /// Scans `cacheDir` once to initialize or refresh `trackedBytes`.
    @discardableResult
    public func recalculateBytes() -> Int64 {
        scanLock.lock()
        defer { scanLock.unlock() }
        let total = Self.scanDirectoryBytes(in: cacheDir)
        stateLock.lock()
        trackedBytesValue = total
        stateLock.unlock()
        return total
    }

    public func getTrackedBytes() -> Int64 {
        stateLock.lock()
        let current = trackedBytesValue
        stateLock.unlock()
        if current >= 0 {
            return current
        }
        return recalculateBytes()
    }

    public func peekTrackedBytes() -> Int64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return trackedBytesValue
    }

    public func resetTrackedBytes(_ bytes: Int64) {
        stateLock.lock()
        trackedBytesValue = max(0, bytes)
        stateLock.unlock()
    }

    /// Incrementally applies a completed write/delete delta when `trackedBytes` has already
    /// been initialized; leaves uninitialized `-1` intact so the first scan does not double-count.
    @discardableResult
    public func recordWrite(deltaBytes: Int64) -> Int64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        if trackedBytesValue >= 0 {
            trackedBytesValue = max(0, trackedBytesValue + deltaBytes)
        }
        return trackedBytesValue
    }

    /// Touches modification date on `url` only when more than 5 minutes elapsed since its last touch.
    public func touchAccessTimeIfNeeded(at url: URL, now: Date = Date()) {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
              values.isRegularFile == true else {
            return
        }
        let mtimeMs = Int64(((values.contentModificationDate?.timeIntervalSince1970) ?? 0) * 1000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard Self.shouldTouchAccessTime(lastModifiedMs: mtimeMs, nowMs: nowMs) else { return }
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }

    @discardableResult
    public func trimIfNeededAsync(
        maxBytes: Int64 = ImageDiskCacheTrimmer.defaultMaxBytes,
        queue: DispatchQueue = DispatchQueue.global(qos: .utility)
    ) -> Bool {
        guard maxBytes >= 0 else { return false }
        stateLock.lock()
        let current = trackedBytesValue
        if current >= 0 && current <= maxBytes {
            stateLock.unlock()
            return false
        }
        if trimInProgress {
            trimPending = true
            stateLock.unlock()
            return false
        }
        trimInProgress = true
        stateLock.unlock()

        queue.async { [self] in
            runTrimLoop(maxBytes: maxBytes)
        }
        return true
    }

    @discardableResult
    public func trimSync(maxBytes: Int64 = ImageDiskCacheTrimmer.defaultMaxBytes) -> Int64 {
        guard maxBytes >= 0 else { return getTrackedBytes() }
        stateLock.lock()
        if trimInProgress {
            trimPending = true
            let current = trackedBytesValue
            stateLock.unlock()
            return current < 0 ? 0 : current
        }
        trimInProgress = true
        stateLock.unlock()

        runTrimLoop(maxBytes: maxBytes)
        return getTrackedBytes()
    }

    private func runTrimLoop(maxBytes: Int64) {
        while true {
            stateLock.lock()
            trimPending = false
            stateLock.unlock()

            performTrim(maxBytes: maxBytes)

            stateLock.lock()
            if !trimPending {
                trimInProgress = false
                stateLock.unlock()
                break
            }
            let current = trackedBytesValue
            if current >= 0 && current <= maxBytes {
                trimInProgress = false
                stateLock.unlock()
                break
            }
            stateLock.unlock()
        }
    }

    private func performTrim(maxBytes: Int64) {
        scanLock.lock()
        defer { scanLock.unlock() }

        let (entries, scannedTotal) = Self.collectSortedEntries(in: cacheDir)
        stateLock.lock()
        trackedBytesValue = scannedTotal
        stateLock.unlock()

        guard scannedTotal > maxBytes, !entries.isEmpty else { return }
        let targetBytes = Self.lowWaterMarkBytes(maxBytes)
        var remaining = scannedTotal
        let fm = FileManager.default
        for entry in entries {
            if remaining <= targetBytes { break }
            do {
                try fm.removeItem(at: entry.url)
                remaining = max(0, remaining - entry.length)
                let fallback = remaining
                stateLock.lock()
                trackedBytesValue = trackedBytesValue < 0 ? fallback : max(0, trackedBytesValue - entry.length)
                stateLock.unlock()
            } catch {
                // Keep scanning older entries if an entry cannot be removed.
            }
        }
    }

    private static func scanDirectoryBytes(in dir: URL) -> Int64 {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            return 0
        }
        var total: Int64 = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }
            total += Int64(max(0, values.fileSize ?? 0))
        }
        return total
    }
}
