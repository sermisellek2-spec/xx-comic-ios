import Foundation

/// Persists the three bounded comic cache snapshots (`summaries_v1.json`, `details_v1.json`,
/// `chapters_v1.json`) inside `cacheDir` (e.g., `comic_caches/`) using `AtomicFileOps`,
/// preserving corrupt files under `<name>.corrupt-<ts>` instead of silently overwriting them.
public final class ComicDiskCacheStore: @unchecked Sendable {
    public static let summariesFileName = "summaries_v1.json"
    public static let detailsFileName = "details_v1.json"
    public static let chaptersFileName = "chapters_v1.json"
    public static let CHAPTER_CACHE_PARSER_REVISION = 3
    public static let chapterCacheParserRevision = CHAPTER_CACHE_PARSER_REVISION

    private static let corruptMarker = ".corrupt-"
    private static let emptyArrayData = Data("[]".utf8)

    public struct LegacyData: Sendable {
        public let summariesJson: String?
        public let detailsJson: String?
        public let chaptersJson: String?

        public init(summariesJson: String?, detailsJson: String?, chaptersJson: String?) {
            self.summariesJson = summariesJson
            self.detailsJson = detailsJson
            self.chaptersJson = chaptersJson
        }
    }

    public struct CachedDetailEntry: Codable, Equatable, Sendable {
        public var sourceParserRevision: Int?
        public var sourceRuleVersion: Int?
        public var summary: ComicSummary
        public var author: String
        public var status: String
        public var description: String
        public var latestChapter: String
        public var chapters: [Chapter]

        public init(
            sourceParserRevision: Int? = nil,
            sourceRuleVersion: Int? = nil,
            summary: ComicSummary,
            author: String,
            status: String,
            description: String,
            latestChapter: String,
            chapters: [Chapter]
        ) {
            self.sourceParserRevision = sourceParserRevision
            self.sourceRuleVersion = sourceRuleVersion
            self.summary = summary
            self.author = author
            self.status = status
            self.description = description
            self.latestChapter = latestChapter
            self.chapters = chapters
        }

        public init(
            detail: ComicDetail,
            sourceParserRevision: Int? = nil,
            sourceRuleVersion: Int? = nil
        ) {
            let local = ComicDiskCacheStore.isLocalSourceOrComic(detail)
            self.sourceParserRevision = local ? sourceParserRevision : (sourceParserRevision ?? ComicDiskCacheStore.CHAPTER_CACHE_PARSER_REVISION)
            self.sourceRuleVersion = (!local && (sourceRuleVersion ?? 0) > 0) ? sourceRuleVersion : nil
            self.summary = detail.summary
            self.author = detail.author
            self.status = detail.status
            self.description = detail.description
            self.latestChapter = detail.latestChapter
            self.chapters = detail.chapters
        }

        public var detail: ComicDetail {
            ComicDetail(
                summary: summary,
                author: author,
                status: status,
                description: description,
                latestChapter: latestChapter,
                chapters: chapters
            )
        }

        public func restoredWithRevisionCheck() -> CachedDetailEntry {
            let d = detail
            if ComicDiskCacheStore.isLocalSourceOrComic(d)
                || (sourceParserRevision ?? 0) >= ComicDiskCacheStore.CHAPTER_CACHE_PARSER_REVISION
                || chapters.isEmpty {
                return self
            }
            return CachedDetailEntry(
                sourceParserRevision: sourceParserRevision,
                sourceRuleVersion: nil,
                summary: summary,
                author: author,
                status: status,
                description: description,
                latestChapter: latestChapter,
                chapters: []
            )
        }
    }

    private enum Slot {
        case summaries
        case details
        case chapters
    }

    public let cacheDir: URL
    public let summariesFile: URL
    public let detailsFile: URL
    public let chaptersFile: URL

    private let ioLock = NSLock()
    private var summariesCorrupted = false
    private var detailsCorrupted = false
    private var chaptersCorrupted = false
    private var summariesBackupFailed = false
    private var detailsBackupFailed = false
    private var chaptersBackupFailed = false

    public init(cacheDir: URL) {
        self.cacheDir = cacheDir
        self.summariesFile = cacheDir.appendingPathComponent(Self.summariesFileName)
        self.detailsFile = cacheDir.appendingPathComponent(Self.detailsFileName)
        self.chaptersFile = cacheDir.appendingPathComponent(Self.chaptersFileName)
    }

    public var hasAnyCacheFile: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: summariesFile.path)
            || fm.fileExists(atPath: detailsFile.path)
            || fm.fileExists(atPath: chaptersFile.path)
    }

    public var isCorrupted: Bool {
        ioLock.lock(); defer { ioLock.unlock() }
        return summariesCorrupted || detailsCorrupted || chaptersCorrupted
    }

    public var isSummariesCorrupted: Bool {
        ioLock.lock(); defer { ioLock.unlock() }
        return summariesCorrupted
    }

    public var isDetailsCorrupted: Bool {
        ioLock.lock(); defer { ioLock.unlock() }
        return detailsCorrupted
    }

    public var isChaptersCorrupted: Bool {
        ioLock.lock(); defer { ioLock.unlock() }
        return chaptersCorrupted
    }

    public static func isLocalSourceOrComic(_ detail: ComicDetail?) -> Bool {
        guard let detail else { return true }
        return detail.summary.sourceId == "local" || detail.summary.comicId.hasPrefix("local_")
    }

    public static func restoreDetailWithRevisionCheck(_ detail: ComicDetail, cachedParserRevision: Int) -> ComicDetail {
        if isLocalSourceOrComic(detail)
            || cachedParserRevision >= CHAPTER_CACHE_PARSER_REVISION
            || detail.chapters.isEmpty {
            return detail
        }
        return ComicDetail(
            summary: detail.summary,
            author: detail.author,
            status: detail.status,
            description: detail.description,
            latestChapter: detail.latestChapter,
            chapters: []
        )
    }

    public static func retainedSummaryIdsForCacheClear(
        favoriteIds: Set<String>?,
        lastViewedKeys: Set<String>?,
        progressKeys: Set<String>?
    ) -> Set<String> {
        var retained = Set<String>()
        if let favoriteIds { retained.formUnion(favoriteIds) }
        if let lastViewedKeys { retained.formUnion(lastViewedKeys) }
        if let progressKeys { retained.formUnion(progressKeys) }
        return retained
    }

    public func readSummaries() -> [ComicSummary] {
        readSlot([ComicSummary].self, slot: .summaries) ?? []
    }

    public func readDetailEntries() -> [CachedDetailEntry] {
        (readSlot([CachedDetailEntry].self, slot: .details) ?? []).map { $0.restoredWithRevisionCheck() }
    }

    public func readDetails() -> [ComicDetail] {
        readDetailEntries().map(\.detail)
    }

    public func readChapters() -> [ChapterPage] {
        readSlot([ChapterPage].self, slot: .chapters) ?? []
    }

    @discardableResult
    public func migrateFromLegacyIfNeeded(
        supply: () -> LegacyData?,
        onMigrated: (() -> Void)? = nil
    ) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }

        let corruptFlag = summariesCorrupted || detailsCorrupted || chaptersCorrupted
        if hasAnyCacheFile || corruptFlag || hasAnyCorruptBackupFileLocked() {
            return false
        }
        guard let legacy = supply() else { return false }
        let sNorm = normalizeOrNil(legacy.summariesJson)
        let dNorm = normalizeOrNil(legacy.detailsJson)
        let cNorm = normalizeOrNil(legacy.chaptersJson)
        if sNorm == nil && dNorm == nil && cNorm == nil {
            return false
        }

        guard let sData = (sNorm ?? "[]").data(using: .utf8),
              let dData = (dNorm ?? "[]").data(using: .utf8),
              let cData = (cNorm ?? "[]").data(using: .utf8),
              let sArr = (try? JSONSerialization.jsonObject(with: sData)) as? [Any],
              let dArr = (try? JSONSerialization.jsonObject(with: dData)) as? [Any],
              let cArr = (try? JSONSerialization.jsonObject(with: cData)) as? [Any] else {
            return false
        }
        if sArr.isEmpty && dArr.isEmpty && cArr.isEmpty {
            return false
        }

        var written: [URL] = []
        do {
            try ensureCacheDirLocked()
            try AtomicFileOps.writeAtomically(sData, to: summariesFile)
            written.append(summariesFile)
            try AtomicFileOps.writeAtomically(dData, to: detailsFile)
            written.append(detailsFile)
            try AtomicFileOps.writeAtomically(cData, to: chaptersFile)
            written.append(chaptersFile)
        } catch {
            for file in written {
                try? FileManager.default.removeItem(at: file)
            }
            return false
        }

        summariesCorrupted = false
        detailsCorrupted = false
        chaptersCorrupted = false
        summariesBackupFailed = false
        detailsBackupFailed = false
        chaptersBackupFailed = false
        onMigrated?()
        return true
    }

    public func writeSnapshots(
        summaries: [ComicSummary],
        details: [CachedDetailEntry],
        chapters: [ChapterPage]
    ) throws {
        let encoder = JSONEncoder()
        let sData = try encoder.encode(summaries)
        let dData = try encoder.encode(details)
        let cData = try encoder.encode(chapters)
        ioLock.lock()
        defer { ioLock.unlock() }
        try ensureCacheDirLocked()
        try writeSlotSnapshotLocked(.summaries, data: sData)
        try writeSlotSnapshotLocked(.details, data: dData)
        try writeSlotSnapshotLocked(.chapters, data: cData)
    }

    public func writeSnapshots(
        summaries: [ComicSummary],
        details: [ComicDetail],
        chapters: [ChapterPage],
        ruleVersions: [String: Int] = [:]
    ) throws {
        let entries = details.map { detail in
            let ver = ruleVersions[detail.summary.comicId] ?? ruleVersions[detail.summary.sourceId]
            return CachedDetailEntry(detail: detail, sourceRuleVersion: ver)
        }
        try writeSnapshots(summaries: summaries, details: entries, chapters: chapters)
    }

    public func writeSnapshots(
        summariesJson: String?,
        detailsJson: String?,
        chaptersJson: String?
    ) throws {
        ioLock.lock()
        defer { ioLock.unlock() }
        try ensureCacheDirLocked()
        try writeSlotSnapshotLocked(.summaries, data: normalizedPayloadData(summariesJson))
        try writeSlotSnapshotLocked(.details, data: normalizedPayloadData(detailsJson))
        try writeSlotSnapshotLocked(.chapters, data: normalizedPayloadData(chaptersJson))
    }

    /// Clears managed cache files. When `retainingSummaryIds` is provided, keeps summaries whose
    /// `comicId` is in `retainingSummaryIds` (removing details and chapters). Leaves corrupt backups
    /// and unrelated files untouched.
    @discardableResult
    public func clear(retainingSummaryIds: Set<String>? = nil) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }

        var ok = true
        if let retainingSummaryIds {
            if retainingSummaryIds.isEmpty {
                ok = ok && deleteIfRegularFile(summariesFile)
            } else if FileManager.default.fileExists(atPath: summariesFile.path) {
                if let existing = try? decodeSlotArray([ComicSummary].self, file: summariesFile) {
                    let retained = existing.filter { retainingSummaryIds.contains($0.comicId) }
                    if retained.isEmpty {
                        ok = ok && deleteIfRegularFile(summariesFile)
                    } else if let data = try? JSONEncoder().encode(retained) {
                        do {
                            try writeSlotSnapshotLocked(.summaries, data: data)
                        } catch {
                            ok = false
                        }
                    } else {
                        ok = false
                    }
                } else {
                    // Existing summaries file is corrupt/unreadable: back up instead of silently wiping.
                    let backedUp = backupCorruptFileLocked(summariesFile)
                    setCorruptStateLocked(.summaries, corrupted: true, backupFailed: !backedUp)
                    ok = backedUp
                }
            }
        } else {
            ok = ok && deleteIfRegularFile(summariesFile)
            summariesCorrupted = false
            summariesBackupFailed = false
        }

        ok = ok && deleteIfRegularFile(detailsFile)
        ok = ok && deleteIfRegularFile(chaptersFile)
        detailsCorrupted = false
        chaptersCorrupted = false
        detailsBackupFailed = false
        chaptersBackupFailed = false
        return ok
    }

    /// Invalidates cached chapter lists in `details_v1.json` and corresponding chapter pages in
    /// `chapters_v1.json` for `sourceIds` or where `ruleVersions[sourceId] > entry.sourceRuleVersion`.
    @discardableResult
    public func invalidateDetailsAndChapters(
        forSourceIds sourceIds: Set<String>,
        ruleVersions: [String: Int] = [:]
    ) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }

        var detailEntries = (try? decodeSlotArray([CachedDetailEntry].self, file: detailsFile)) ?? []
        guard !detailEntries.isEmpty else { return false }

        var invalidatedChapterIds = Set<String>()
        var invalidatedUrls = Set<String>()
        var changed = false

        for idx in detailEntries.indices {
            let entry = detailEntries[idx]
            if Self.isLocalSourceOrComic(entry.detail) || entry.chapters.isEmpty { continue }
            let srcId = entry.summary.sourceId
            let newVer = ruleVersions[srcId] ?? 0
            let cachedVer = entry.sourceRuleVersion ?? 0
            let versionUpdated = cachedVer > 0 && newVer > cachedVer
            if sourceIds.contains(srcId) || versionUpdated {
                for ch in entry.chapters {
                    if !ch.chapterId.isEmpty { invalidatedChapterIds.insert(ch.chapterId) }
                    if !ch.url.isEmpty { invalidatedUrls.insert(ch.url) }
                }
                detailEntries[idx].chapters = []
                detailEntries[idx].sourceRuleVersion = nil
                changed = true
            }
        }
        guard changed else { return false }

        let encoder = JSONEncoder()
        do {
            try ensureCacheDirLocked()
            let dData = try encoder.encode(detailEntries)
            try writeSlotSnapshotLocked(.details, data: dData)

            if FileManager.default.fileExists(atPath: chaptersFile.path),
               let chapterPages = try? decodeSlotArray([ChapterPage].self, file: chaptersFile) {
                let filtered = chapterPages.filter {
                    !invalidatedChapterIds.contains($0.chapterId) && !invalidatedUrls.contains($0.chapterId)
                }
                if filtered.count != chapterPages.count {
                    let cData = try encoder.encode(filtered)
                    try writeSlotSnapshotLocked(.chapters, data: cData)
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// Returns O(1) total byte size of the three cache files without parsing JSON.
    public func totalBytes() -> Int64 {
        fileLength(summariesFile) + fileLength(detailsFile) + fileLength(chaptersFile)
    }

    // MARK: - Private

    private func readSlot<T: Decodable>(_ type: T.Type, slot: Slot) -> T? {
        ioLock.lock()
        defer { ioLock.unlock() }

        let file = fileFor(slot)
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return nil }
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else {
            setCorruptStateLocked(slot, corrupted: true, backupFailed: true)
            return nil
        }
        do {
            let decoded = try decodeSlotArray(type, file: file)
            setCorruptStateLocked(slot, corrupted: false, backupFailed: false)
            return decoded
        } catch {
            let backedUp = backupCorruptFileLocked(file)
            setCorruptStateLocked(slot, corrupted: true, backupFailed: !backedUp)
            return nil
        }
    }

    private func decodeSlotArray<T: Decodable>(_ type: T.Type, file: URL) throws -> T {
        let data = try Data(contentsOf: file)
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try JSONDecoder().decode(type, from: Data(raw.utf8))
    }

    private func writeSlotSnapshotLocked(_ slot: Slot, data: Data) throws {
        let target = fileFor(slot)
        let isEmptyPayload = (String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "[]")
        if isBackupFailedLocked(slot) && FileManager.default.fileExists(atPath: target.path) && isEmptyPayload {
            // Never overwrite a damaged file with an empty array when backing it up failed.
            return
        }
        try AtomicFileOps.writeAtomically(data, to: target)
        setCorruptStateLocked(slot, corrupted: false, backupFailed: false)
    }

    private func fileFor(_ slot: Slot) -> URL {
        switch slot {
        case .summaries: return summariesFile
        case .details: return detailsFile
        case .chapters: return chaptersFile
        }
    }

    private func setCorruptStateLocked(_ slot: Slot, corrupted: Bool, backupFailed: Bool) {
        switch slot {
        case .summaries:
            summariesCorrupted = corrupted
            summariesBackupFailed = backupFailed
        case .details:
            detailsCorrupted = corrupted
            detailsBackupFailed = backupFailed
        case .chapters:
            chaptersCorrupted = corrupted
            chaptersBackupFailed = backupFailed
        }
    }

    private func isBackupFailedLocked(_ slot: Slot) -> Bool {
        switch slot {
        case .summaries: return summariesBackupFailed
        case .details: return detailsBackupFailed
        case .chapters: return chaptersBackupFailed
        }
    }

    private func hasAnyCorruptBackupFileLocked() -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return false
        }
        for url in entries {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let name = url.lastPathComponent
            if name.hasPrefix(Self.summariesFileName + Self.corruptMarker)
                || name.hasPrefix(Self.detailsFileName + Self.corruptMarker)
                || name.hasPrefix(Self.chaptersFileName + Self.corruptMarker) {
                return true
            }
        }
        return false
    }

    private func backupCorruptFileLocked(_ file: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path),
              (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return false
        }
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let backup = allocateCorruptBackupFile(file, timestampMs: ts)
        do {
            try AtomicFileOps.moveReplace(from: file, to: backup)
            return !fm.fileExists(atPath: file.path) && fm.fileExists(atPath: backup.path)
        } catch {
            if fm.fileExists(atPath: backup.path),
               let size = (try? fm.attributesOfItem(atPath: backup.path)[.size] as? NSNumber)?.int64Value,
               size == 0 {
                try? fm.removeItem(at: backup)
            }
            return false
        }
    }

    private func allocateCorruptBackupFile(_ file: URL, timestampMs: Int64) -> URL {
        let parent = file.deletingLastPathComponent()
        let baseName = file.lastPathComponent + Self.corruptMarker + "\(timestampMs)"
        var candidate = parent.appendingPathComponent(baseName)
        let fm = FileManager.default
        var suffix = 1
        while fm.fileExists(atPath: candidate.path) && suffix < 1000 {
            candidate = parent.appendingPathComponent("\(baseName)-\(suffix)")
            suffix += 1
        }
        return candidate
    }

    private func ensureCacheDirLocked() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDir.path) {
            try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    private func normalizeOrNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func normalizedPayloadData(_ rawJson: String?) -> Data {
        guard let rawJson, !rawJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.emptyArrayData
        }
        return Data(rawJson.utf8)
    }

    private func deleteIfRegularFile(_ file: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return true }
        guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return false
        }
        do {
            try fm.removeItem(at: file)
            return true
        } catch {
            return false
        }
    }

    private func fileLength(_ file: URL) -> Int64 {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize else {
            return 0
        }
        return Int64(max(0, size))
    }
}
