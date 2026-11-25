@preconcurrency import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// File-backed blacklist store with O(1) snapshot lookup, atomic disk writes,
/// and corruption protection (never overwrites corrupted payloads until cleared/recovered).
public final class ComicBlacklistStore: @unchecked Sendable {
    public static let schemaVersion = 1
    public static let fileName = "comic_blacklist.json"

    private let storageFileURL: URL
    private let stateLock = NSLock()
    private let diskLock = NSLock()
    private let ioQueue: DispatchQueue?
    private var writeSequence: UInt64 = 0

    private var entriesByKey: [String: BlacklistEntry] = [:]
    private var entryOrder: [String] = []
    private var _entriesSnapshot: [String: BlacklistEntry] = [:]
    private var _sortedSnapshot: [BlacklistEntry] = []
    private var _corrupted = false

    public init(storageFile: URL, asyncPersistence: Bool = false) {
        self.storageFileURL = storageFile
        self.ioQueue = asyncPersistence
            ? DispatchQueue(label: "com.xxcomic.blacklist.io", qos: .utility)
            : nil
        stateLock.lock()
        loadLocked()
        stateLock.unlock()
    }

    public convenience init(directory: URL, asyncPersistence: Bool = false) {
        self.init(storageFile: directory.appendingPathComponent(Self.fileName), asyncPersistence: asyncPersistence)
    }

    // MARK: - O(1) Snapshot Reads

    public var entriesSnapshot: [String: BlacklistEntry] {
        stateLock.lock()
        let snapshot = _entriesSnapshot
        stateLock.unlock()
        return snapshot
    }

    public var sortedSnapshot: [BlacklistEntry] {
        stateLock.lock()
        let snapshot = _sortedSnapshot
        stateLock.unlock()
        return snapshot
    }

    public func isBlacklistedTitle(_ rawTitle: String?) -> Bool {
        let key = ComicTitleNormalizer.normalize(rawTitle)
        guard !key.isEmpty else { return false }
        return entriesSnapshot[key] != nil
    }

    public func isBlacklistedNormalizedTitle(_ normalizedTitle: String?) -> Bool {
        guard let normalizedTitle, !normalizedTitle.isEmpty else { return false }
        return entriesSnapshot[normalizedTitle] != nil
    }

    public func isBlacklistedSummary(_ summary: ComicSummary?) -> Bool {
        guard let summary else { return false }
        return isBlacklistedTitle(summary.title)
    }

    public func filterSummaries(_ summaries: [ComicSummary]) -> [ComicSummary] {
        guard !summaries.isEmpty else { return [] }
        let snapshot = entriesSnapshot
        if snapshot.isEmpty {
            return summaries
        }
        return summaries.filter { summary in
            let key = ComicTitleNormalizer.normalize(summary.title)
            return key.isEmpty || snapshot[key] == nil
        }
    }

    public func getEntry(_ normalizedTitle: String?) -> BlacklistEntry? {
        guard let normalizedTitle, !normalizedTitle.isEmpty else { return nil }
        return entriesSnapshot[normalizedTitle]
    }

    public func listEntries() -> [BlacklistEntry] {
        sortedSnapshot
    }

    public var size: Int {
        entriesSnapshot.count
    }

    public var isCorrupted: Bool {
        stateLock.lock()
        let value = _corrupted
        stateLock.unlock()
        return value
    }

    public var storageURL: URL {
        storageFileURL
    }

    // MARK: - Mutations

    @discardableResult
    public func add(_ entry: BlacklistEntry?) -> Bool {
        guard let entry, !entry.normalizedTitle.isEmpty else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        insertEntryLocked(entry)
        publishSnapshotsLocked()
        persistIfSafeLocked()
        return true
    }

    @discardableResult
    public func removeByNormalizedTitle(_ normalizedTitle: String?) -> Bool {
        guard let normalizedTitle, !normalizedTitle.isEmpty else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard entriesByKey.removeValue(forKey: normalizedTitle) != nil else { return false }
        entryOrder.removeAll { $0 == normalizedTitle }
        publishSnapshotsLocked()
        persistIfSafeLocked()
        return true
    }

    @discardableResult
    public func removeByNormalizedTitles(_ normalizedTitles: [String]) -> Int {
        guard !normalizedTitles.isEmpty else { return 0 }
        stateLock.lock()
        defer { stateLock.unlock() }
        var removedCount = 0
        for key in normalizedTitles where !key.isEmpty {
            if entriesByKey.removeValue(forKey: key) != nil {
                entryOrder.removeAll { $0 == key }
                removedCount += 1
            }
        }
        if removedCount > 0 {
            publishSnapshotsLocked()
            persistIfSafeLocked()
        }
        return removedCount
    }

    @discardableResult
    public func clearAll() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        let previousSize = entriesByKey.count
        entriesByKey.removeAll()
        entryOrder.removeAll()
        _corrupted = false
        publishSnapshotsLocked()
        persistIfSafeLocked()
        return previousSize
    }

    @discardableResult
    public func restoreEntries(_ entries: [BlacklistEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        stateLock.lock()
        defer { stateLock.unlock() }
        var restoredCount = 0
        for entry in entries where !entry.normalizedTitle.isEmpty {
            insertEntryLocked(entry)
            restoredCount += 1
        }
        if restoredCount > 0 {
            publishSnapshotsLocked()
            persistIfSafeLocked()
        }
        return restoredCount
    }

    public func flush() {
        ioQueue?.sync {}
    }

    // MARK: - Loading, Snapshot & Persistence

    private func insertEntryLocked(_ entry: BlacklistEntry) {
        if entriesByKey[entry.normalizedTitle] != nil {
            entryOrder.removeAll { $0 == entry.normalizedTitle }
        }
        entriesByKey[entry.normalizedTitle] = entry
        entryOrder.append(entry.normalizedTitle)
    }

    private func loadLocked() {
        let fm = FileManager.default
        let tmpURL = tmpFileURL()
        let exists = fm.fileExists(atPath: storageFileURL.path)

        if !exists {
            if let tmpBytes = nonEmptyDataIfExists(at: tmpURL),
               let recovered = try? parsePayload(tmpBytes) {
                applyParsedLocked(recovered)
                _corrupted = false
                publishSnapshotsLocked()
                try? moveReplace(from: tmpURL, to: storageFileURL)
                return
            }
            entriesByKey.removeAll()
            entryOrder.removeAll()
            _corrupted = false
            publishSnapshotsLocked()
            return
        }

        var rawBytes: Data?
        do {
            let data = try Data(contentsOf: storageFileURL)
            rawBytes = data
            let parsed = try parsePayload(data)
            applyParsedLocked(parsed)
            _corrupted = false
            publishSnapshotsLocked()
        } catch {
            if let raw = rawBytes, raw.isEmpty,
               let tmpBytes = nonEmptyDataIfExists(at: tmpURL),
               let recovered = try? parsePayload(tmpBytes) {
                applyParsedLocked(recovered)
                _corrupted = false
                publishSnapshotsLocked()
                try? moveReplace(from: tmpURL, to: storageFileURL)
                return
            }
            _corrupted = true
            entriesByKey.removeAll()
            entryOrder.removeAll()
            publishSnapshotsLocked()
            backupCorruptFileIfAbsent(rawBytes)
        }
    }

    private func applyParsedLocked(_ parsed: [(String, BlacklistEntry)]) {
        entriesByKey.removeAll()
        entryOrder.removeAll()
        for (key, entry) in parsed {
            insertEntryLocked(entry)
            _ = key
        }
    }

    private func parsePayload(_ rawBytes: Data) throws -> [(String, BlacklistEntry)] {
        guard !rawBytes.isEmpty else {
            throw StoreError.invalidPayload("Empty blacklist payload")
        }
        guard let text = String(data: rawBytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix("{"), text.hasSuffix("}") else {
            throw StoreError.invalidPayload("Malformed blacklist JSON root")
        }
        let jsonObject = try JSONSerialization.jsonObject(with: rawBytes, options: [])
        guard let root = jsonObject as? [String: Any] else {
            throw StoreError.invalidPayload("Malformed blacklist JSON root")
        }
        guard let versionVal = root["version"],
              let version = JsonValueHelper.strictInt(versionVal) else {
            throw StoreError.invalidPayload("Missing or invalid schema version")
        }
        guard version >= 1, version <= Self.schemaVersion else {
            throw StoreError.invalidPayload("Unsupported blacklist schema version: \(versionVal)")
        }
        guard let arr = root["entries"] as? [Any] else {
            throw StoreError.invalidPayload("Missing or invalid entries array")
        }
        var parsed: [(String, BlacklistEntry)] = []
        var seenIndex: [String: Int] = [:]
        for (index, elem) in arr.enumerated() {
            guard let dict = elem as? [String: Any] else {
                throw StoreError.invalidPayload("Invalid blacklist entry at index \(index)")
            }
            if let entry = BlacklistEntry.fromJSONObject(dict), !entry.normalizedTitle.isEmpty {
                if let existingIdx = seenIndex[entry.normalizedTitle] {
                    parsed[existingIdx] = (entry.normalizedTitle, entry)
                } else {
                    seenIndex[entry.normalizedTitle] = parsed.count
                    parsed.append((entry.normalizedTitle, entry))
                }
            }
        }
        return parsed
    }

    private func backupCorruptFileIfAbsent(_ rawBytes: Data?) {
        let backupURL = corruptBackupURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: backupURL.path) {
            return
        }
        let parent = backupURL.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if let rawBytes {
            writeSyncToFile(rawBytes, to: backupURL)
        } else if fm.fileExists(atPath: storageFileURL.path),
                  let existing = try? Data(contentsOf: storageFileURL) {
            writeSyncToFile(existing, to: backupURL)
        }
    }

    private func publishSnapshotsLocked() {
        _entriesSnapshot = entriesByKey
        var list: [BlacklistEntry] = []
        list.reserveCapacity(entryOrder.count)
        for key in entryOrder.reversed() {
            if let entry = entriesByKey[key] {
                list.append(entry)
            }
        }
        list.sort { $0.blacklistedAt > $1.blacklistedAt }
        _sortedSnapshot = list
    }

    private func persistIfSafeLocked() {
        if _corrupted {
            return
        }
        guard let payload = try? serializeLocked() else { return }
        writeSequence &+= 1
        let seq = writeSequence
        if let ioQueue {
            ioQueue.async { [weak self] in
                guard let self else { return }
                self.diskLock.lock()
                defer { self.diskLock.unlock() }
                self.stateLock.lock()
                let shouldWrite = (seq == self.writeSequence) && !self._corrupted
                self.stateLock.unlock()
                if shouldWrite {
                    try? self.writePayloadToDisk(payload)
                }
            }
            return
        }
        diskLock.lock()
        defer { diskLock.unlock() }
        if !_corrupted {
            try? writePayloadToDisk(payload)
        }
    }

    private func serializeLocked() throws -> Data {
        let root: [String: Any] = [
            "version": Self.schemaVersion,
            "entries": _sortedSnapshot.map { $0.toJSONObject() }
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [])
    }

    private func writePayloadToDisk(_ payload: Data) throws {
        let parent = storageFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let tmp = tmpFileURL()
        do {
            try writeDataAndSync(payload, to: tmp)
            try moveReplace(from: tmp, to: storageFileURL)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }

    private func tmpFileURL() -> URL {
        storageFileURL.deletingLastPathComponent()
            .appendingPathComponent(storageFileURL.lastPathComponent + ".tmp")
    }

    private func corruptBackupURL() -> URL {
        storageFileURL.deletingLastPathComponent()
            .appendingPathComponent(storageFileURL.lastPathComponent + ".corrupt")
    }

    private func nonEmptyDataIfExists(at url: URL) -> Data? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = (attrs[.size] as? NSNumber)?.int64Value, fileSize > 0 else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func writeSyncToFile(_ data: Data, to url: URL) {
        try? writeDataAndSync(data, to: url)
    }

    private func writeDataAndSync(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [])
        if let handle = try? FileHandle(forWritingTo: url) {
            try? handle.synchronize()
            try? handle.close()
        }
    }

    private func moveReplace(from source: URL, to target: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { srcPath -> Int32 in
            target.withUnsafeFileSystemRepresentation { dstPath -> Int32 in
                guard let srcPath, let dstPath else { return -1 }
                return rename(srcPath, dstPath)
            }
        }
        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
    }

    private enum StoreError: Error {
        case invalidPayload(String)
    }
}
