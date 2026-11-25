@preconcurrency import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Persistent candidate pool (`recommend_candidate_pool.json`) shared
/// across initial recommendation harvesting and endless multi-source stream pagination.
public final class RecommendCandidatePool: @unchecked Sendable {
    public static let schemaVersion = 1
    public static let maxPoolCandidates = 2400
    public static let defaultPoolTtlMs: Int64 = 24 * 60 * 60 * 1000
    public static let fileName = "recommend_candidate_pool.json"

    private let lock = NSLock()
    private let filesDirURL: URL
    private let poolFileURL: URL
    private let poolTtlMs: Int64
    private let maxCandidates: Int

    private var entries: [String: SourceCandidate] = [:]
    private var entryOrder: [String] = []
    private var loaded = false

    public init(
        filesDir: URL,
        poolTtlMs: Int64 = defaultPoolTtlMs,
        maxCandidates: Int = maxPoolCandidates
    ) {
        self.filesDirURL = filesDir
        self.poolFileURL = filesDir.appendingPathComponent(Self.fileName)
        self.poolTtlMs = max(0, poolTtlMs)
        self.maxCandidates = max(1, maxCandidates)
    }

    @discardableResult
    public func merge(
        _ additions: [SourceCandidate],
        titleNormalizer: ((String) -> String)? = nil,
        nowMillis: Int64? = nil
    ) -> Int {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        let now = (nowMillis ?? 0) > 0 ? nowMillis! : Self.currentMillis()
        pruneExpiredLocked(nowMillis: now)
        guard !additions.isEmpty else { return 0 }
        let normalizer = titleNormalizer ?? { ComicTitleNormalizer.normalize($0) }

        var changedCount = 0
        for raw in additions {
            let title = SearchRules.trim(raw.summary.title)
            if title.isEmpty { continue }
            var sourceId = raw.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            if sourceId.isEmpty {
                sourceId = raw.summary.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if sourceId.isEmpty { continue }

            let effectiveFetchedAt = raw.fetchedAt > 0 ? raw.fetchedAt : now
            if isExpired(fetchedAt: effectiveFetchedAt, nowMillis: now) {
                continue
            }

            var normTitle = normalizer(title)
            if normTitle.isEmpty {
                normTitle = ComicTitleNormalizer.normalize(title)
            }
            if normTitle.isEmpty {
                normTitle = title
            }
            let key = "\(sourceId)\u{0000}\(normTitle)"

            let incoming: SourceCandidate
            if raw.fetchedAt == effectiveFetchedAt && sourceId == raw.sourceId {
                incoming = raw
            } else {
                incoming = SourceCandidate(
                    summary: raw.summary,
                    sourceId: sourceId,
                    sourceName: raw.sourceName,
                    sourceChannel: raw.sourceChannel,
                    featuredCategoryLabel: raw.featuredCategoryLabel,
                    rankInList: raw.rankInList,
                    author: raw.author,
                    genres: raw.genres,
                    matchedQueryGenre: raw.matchedQueryGenre,
                    matchedQueryAuthor: raw.matchedQueryAuthor,
                    fetchedAt: effectiveFetchedAt
                )
            }

            if let existing = entries[key] {
                let merged = mergeCandidate(cur: existing, inc: incoming)
                if merged.enriched {
                    entries[key] = merged.candidate
                    changedCount += 1
                }
            } else {
                entries[key] = incoming
                entryOrder.append(key)
                changedCount += 1
            }
        }

        if entries.count > maxCandidates {
            trimToMaxLocked()
        }
        return changedCount
    }

    @discardableResult
    public func mergeAndPersist(
        _ additions: [SourceCandidate],
        titleNormalizer: ((String) -> String)? = nil,
        nowMillis: Int64? = nil
    ) -> Int {
        lock.lock()
        defer { lock.unlock() }
        // Call locked merge logic
        let changed = mergeLocked(additions, titleNormalizer: titleNormalizer, nowMillis: nowMillis)
        if changed > 0 || !FileManager.default.fileExists(atPath: poolFileURL.path) {
            persistLocked()
        }
        return changed
    }

    public func persistNow() {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        persistLocked()
    }

    public func snapshotForSources(allowedSourceIds: Set<String>?, nowMillis: Int64? = nil) -> [SourceCandidate] {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        let now = (nowMillis ?? 0) > 0 ? nowMillis! : Self.currentMillis()
        pruneExpiredLocked(nowMillis: now)
        if entries.isEmpty { return [] }
        let allowAll = allowedSourceIds == nil || allowedSourceIds!.isEmpty
        var out: [SourceCandidate] = []
        out.reserveCapacity(entries.count)
        for key in entryOrder {
            guard let c = entries[key] else { continue }
            if allowAll || allowedSourceIds!.contains(c.sourceId) {
                out.append(c)
            }
        }
        return out
    }

    public var size: Int {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return entries.count
    }

    @discardableResult
    public func removeSources(_ sourceIds: [String]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        guard !sourceIds.isEmpty else { return 0 }
        let targets = Set(sourceIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !targets.isEmpty, !entries.isEmpty else { return 0 }

        var removed = 0
        var nextOrder: [String] = []
        nextOrder.reserveCapacity(entryOrder.count)
        for key in entryOrder {
            guard let c = entries[key] else { continue }
            var sid = c.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            if sid.isEmpty {
                sid = c.summary.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if targets.contains(sid) {
                entries.removeValue(forKey: key)
                removed += 1
            } else {
                nextOrder.append(key)
            }
        }
        entryOrder = nextOrder
        if removed > 0 {
            persistLocked()
        }
        return removed
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        loaded = true
        entries.removeAll()
        entryOrder.removeAll()
        let fm = FileManager.default
        if fm.fileExists(atPath: poolFileURL.path) {
            try? fm.removeItem(at: poolFileURL)
        }
        let tmp = tmpFileURL()
        if fm.fileExists(atPath: tmp.path) {
            try? fm.removeItem(at: tmp)
        }
    }

    // MARK: - Private

    private func mergeLocked(
        _ additions: [SourceCandidate],
        titleNormalizer: ((String) -> String)?,
        nowMillis: Int64?
    ) -> Int {
        ensureLoadedLocked()
        let now = (nowMillis ?? 0) > 0 ? nowMillis! : Self.currentMillis()
        pruneExpiredLocked(nowMillis: now)
        guard !additions.isEmpty else { return 0 }
        let normalizer = titleNormalizer ?? { ComicTitleNormalizer.normalize($0) }

        var changedCount = 0
        for raw in additions {
            let title = SearchRules.trim(raw.summary.title)
            if title.isEmpty { continue }
            var sourceId = raw.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            if sourceId.isEmpty {
                sourceId = raw.summary.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if sourceId.isEmpty { continue }

            let effectiveFetchedAt = raw.fetchedAt > 0 ? raw.fetchedAt : now
            if isExpired(fetchedAt: effectiveFetchedAt, nowMillis: now) {
                continue
            }

            var normTitle = normalizer(title)
            if normTitle.isEmpty {
                normTitle = ComicTitleNormalizer.normalize(title)
            }
            if normTitle.isEmpty {
                normTitle = title
            }
            let key = "\(sourceId)\u{0000}\(normTitle)"

            let incoming: SourceCandidate
            if raw.fetchedAt == effectiveFetchedAt && sourceId == raw.sourceId {
                incoming = raw
            } else {
                incoming = SourceCandidate(
                    summary: raw.summary,
                    sourceId: sourceId,
                    sourceName: raw.sourceName,
                    sourceChannel: raw.sourceChannel,
                    featuredCategoryLabel: raw.featuredCategoryLabel,
                    rankInList: raw.rankInList,
                    author: raw.author,
                    genres: raw.genres,
                    matchedQueryGenre: raw.matchedQueryGenre,
                    matchedQueryAuthor: raw.matchedQueryAuthor,
                    fetchedAt: effectiveFetchedAt
                )
            }

            if let existing = entries[key] {
                let merged = mergeCandidate(cur: existing, inc: incoming)
                if merged.enriched {
                    entries[key] = merged.candidate
                    changedCount += 1
                }
            } else {
                entries[key] = incoming
                entryOrder.append(key)
                changedCount += 1
            }
        }

        if entries.count > maxCandidates {
            trimToMaxLocked()
        }
        return changedCount
    }

    private func persistLocked() {
        ensureLoadedLocked()
        var candidatesArr: [[String: Any]] = []
        candidatesArr.reserveCapacity(entryOrder.count)
        for key in entryOrder {
            if let c = entries[key] {
                candidatesArr.append(c.toJSONObject())
            }
        }
        let root: [String: Any] = [
            "version": Self.schemaVersion,
            "savedAt": NSNumber(value: Self.currentMillis()),
            "candidates": candidatesArr
        ]
        if let payload = try? JSONSerialization.data(withJSONObject: root, options: []) {
            try? writeAtomic(payload, to: poolFileURL)
        }
    }

    private func ensureLoadedLocked() {
        guard !loaded else { return }
        loaded = true
        entries.removeAll()
        entryOrder.removeAll()

        let fm = FileManager.default
        let tmp = tmpFileURL()
        let exists = fm.fileExists(atPath: poolFileURL.path)
        let size = (try? fm.attributesOfItem(atPath: poolFileURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        if !exists || size == 0 {
            if let tmpBytes = nonEmptyDataIfExists(at: tmp) {
                do {
                    try parseAndLoadLocked(tmpBytes)
                    try? moveReplace(from: tmp, to: poolFileURL)
                } catch {
                    entries.removeAll()
                    entryOrder.removeAll()
                }
            }
            return
        }

        do {
            let bytes = try Data(contentsOf: poolFileURL)
            try parseAndLoadLocked(bytes)
            if fm.fileExists(atPath: tmp.path) {
                try? fm.removeItem(at: tmp)
            }
        } catch {
            entries.removeAll()
            entryOrder.removeAll()
            backupCorruptFileIfAbsent()
        }
    }

    private func parseAndLoadLocked(_ bytes: Data) throws {
        guard !bytes.isEmpty,
              let raw = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("{"), raw.hasSuffix("}") else {
            throw PoolError.invalid("Invalid candidate pool root JSON")
        }
        let obj = try JSONSerialization.jsonObject(with: bytes, options: [])
        guard let root = obj as? [String: Any] else {
            throw PoolError.invalid("Invalid candidate pool root JSON")
        }
        guard let verVal = root["version"],
              let ver = JsonValueHelper.strictInt(verVal) else {
            throw PoolError.invalid("Missing candidate pool schema version")
        }
        guard ver >= 1, ver <= Self.schemaVersion else {
            throw PoolError.invalid("Unsupported candidate pool version: \(verVal)")
        }
        guard let arr = root["candidates"] as? [Any] else {
            return
        }
        for elem in arr {
            guard let dict = elem as? [String: Any],
                  let c = SourceCandidate.fromJSONObject(dict) else {
                continue
            }
            var sourceId = c.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            if sourceId.isEmpty {
                sourceId = c.summary.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var normTitle = ComicTitleNormalizer.normalize(c.summary.title)
            if normTitle.isEmpty {
                normTitle = SearchRules.trim(c.summary.title)
            }
            if sourceId.isEmpty || normTitle.isEmpty { continue }
            let key = "\(sourceId)\u{0000}\(normTitle)"
            if let prev = entries[key] {
                entries[key] = mergeCandidate(cur: prev, inc: c).candidate
            } else {
                entries[key] = c
                entryOrder.append(key)
            }
        }
        if entries.count > maxCandidates {
            trimToMaxLocked()
        }
    }

    private func pruneExpiredLocked(nowMillis: Int64) {
        guard !entries.isEmpty else { return }
        var nextOrder: [String] = []
        nextOrder.reserveCapacity(entryOrder.count)
        for key in entryOrder {
            guard let c = entries[key], !isExpired(fetchedAt: c.fetchedAt, nowMillis: nowMillis) else {
                entries.removeValue(forKey: key)
                continue
            }
            nextOrder.append(key)
        }
        entryOrder = nextOrder
    }

    private func isExpired(fetchedAt: Int64, nowMillis: Int64) -> Bool {
        if fetchedAt <= 0 { return true }
        if poolTtlMs <= 0 { return (nowMillis - fetchedAt) > 0 }
        return (nowMillis - fetchedAt) >= poolTtlMs
    }

    private func trimToMaxLocked() {
        guard entries.count > maxCandidates else { return }
        let orderedPairs: [(key: String, value: SourceCandidate)] = entryOrder.compactMap { key in
            guard let val = entries[key] else { return nil }
            return (key, val)
        }
        let sorted = orderedPairs.sorted { a, b in
            let ca = a.value
            let cb = b.value
            if cb.fetchedAt != ca.fetchedAt { return cb.fetchedAt < ca.fetchedAt }
            if ca.rankInList != cb.rankInList { return ca.rankInList < cb.rankInList }
            let chA = Self.channelStrength(ca.sourceChannel)
            let chB = Self.channelStrength(cb.sourceChannel)
            if chB != chA { return chB < chA }
            let covA = Self.hasCover(ca.summary)
            let covB = Self.hasCover(cb.summary)
            if covB != covA { return covB && !covA }
            return cb.genres.count < ca.genres.count
        }
        entries.removeAll()
        entryOrder.removeAll()
        let keep = min(maxCandidates, sorted.count)
        for i in 0..<keep {
            let item = sorted[i]
            entries[item.key] = item.value
            entryOrder.append(item.key)
        }
    }

    private func mergeCandidate(cur: SourceCandidate, inc: SourceCandidate) -> (candidate: SourceCandidate, enriched: Bool) {
        let mergedFetchedAt = max(cur.fetchedAt, inc.fetchedAt)
        let mergedRank = min(cur.rankInList, inc.rankInList)

        let curStrength = Self.channelStrength(cur.sourceChannel)
        let incStrength = Self.channelStrength(inc.sourceChannel)
        let mergedChannel = incStrength > curStrength ? inc.sourceChannel : cur.sourceChannel

        var mergedFeaturedLabel = !cur.featuredCategoryLabel.isEmpty
            ? cur.featuredCategoryLabel
            : inc.featuredCategoryLabel
        if inc.sourceChannel == .sourceFeaturedCategory
            && !inc.featuredCategoryLabel.isEmpty
            && cur.featuredCategoryLabel.isEmpty {
            mergedFeaturedLabel = inc.featuredCategoryLabel
        }

        let mergedSourceName = !cur.sourceName.isEmpty ? cur.sourceName : inc.sourceName
        let mergedAuthor = !cur.author.isEmpty ? cur.author : inc.author
        let mergedQueryGenre = !cur.matchedQueryGenre.isEmpty ? cur.matchedQueryGenre : inc.matchedQueryGenre
        let mergedQueryAuthor = !cur.matchedQueryAuthor.isEmpty ? cur.matchedQueryAuthor : inc.matchedQueryAuthor

        var genreSet = Set<String>()
        var mergedGenres: [String] = []
        for g in cur.genres + inc.genres where genreSet.insert(g).inserted {
            mergedGenres.append(g)
        }

        let mergedSummary = Self.mergeSummary(cur: cur.summary, inc: inc.summary)

        let curLatest = (cur.summary.latestChapter ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedLatest = (mergedSummary.latestChapter ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let enriched = mergedFetchedAt > cur.fetchedAt
            || mergedRank < cur.rankInList
            || mergedChannel != cur.sourceChannel
            || mergedGenres.count > cur.genres.count
            || (!Self.hasCover(cur.summary) && Self.hasCover(mergedSummary))
            || (cur.author.isEmpty && !mergedAuthor.isEmpty)
            || (cur.featuredCategoryLabel.isEmpty && !mergedFeaturedLabel.isEmpty)
            || (cur.matchedQueryGenre.isEmpty && !mergedQueryGenre.isEmpty)
            || (cur.matchedQueryAuthor.isEmpty && !mergedQueryAuthor.isEmpty)
            || (curLatest.isEmpty && !mergedLatest.isEmpty)

        guard enriched else {
            return (cur, false)
        }

        let updated = SourceCandidate(
            summary: mergedSummary,
            sourceId: cur.sourceId,
            sourceName: mergedSourceName,
            sourceChannel: mergedChannel,
            featuredCategoryLabel: mergedFeaturedLabel,
            rankInList: mergedRank,
            author: mergedAuthor,
            genres: mergedGenres,
            matchedQueryGenre: mergedQueryGenre,
            matchedQueryAuthor: mergedQueryAuthor,
            fetchedAt: mergedFetchedAt
        )
        return (updated, true)
    }

    private static func mergeSummary(cur: ComicSummary, inc: ComicSummary) -> ComicSummary {
        let sourceId = !cur.sourceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cur.sourceId : inc.sourceId
        let comicId = !cur.comicId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cur.comicId : inc.comicId
        let title = !cur.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cur.title : inc.title
        let coverUrl = !cur.coverUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cur.coverUrl : inc.coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = !cur.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cur.subtitle : inc.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let incLatest = (inc.latestChapter ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let latest = !incLatest.isEmpty ? inc.latestChapter : cur.latestChapter

        var tagSet = Set<String>()
        var tags: [String] = []
        for t in cur.tags + inc.tags where tagSet.insert(t).inserted {
            tags.append(t)
        }

        return ComicSummary(
            sourceId: sourceId.trimmingCharacters(in: .whitespacesAndNewlines),
            comicId: comicId.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            coverUrl: coverUrl,
            subtitle: subtitle,
            tags: tags,
            latestChapter: (latest?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? nil : latest
        )
    }

    private static func channelStrength(_ channel: RecommendChannel) -> Int {
        switch channel {
        case .systemConsensusHot: return 4
        case .sourceFeaturedCategory: return 3
        case .latestUpdates: return 2
        case .habitPersonalized: return 1
        case .explorationNewTaste: return 0
        }
    }

    private static func hasCover(_ s: ComicSummary) -> Bool {
        !s.coverUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func tmpFileURL() -> URL {
        filesDirURL.appendingPathComponent(Self.fileName + ".tmp")
    }

    private func writeAtomic(_ payload: Data, to target: URL) throws {
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let tmp = tmpFileURL()
        do {
            try payload.write(to: tmp, options: [])
            if let handle = try? FileHandle(forWritingTo: tmp) {
                try? handle.synchronize()
                try? handle.close()
            }
            try moveReplace(from: tmp, to: target)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }

    private func backupCorruptFileIfAbsent() {
        let backup = filesDirURL.appendingPathComponent(Self.fileName + ".corrupt")
        let fm = FileManager.default
        if fm.fileExists(atPath: backup.path) { return }
        if let data = try? Data(contentsOf: poolFileURL) {
            try? data.write(to: backup, options: [])
        }
    }

    private func nonEmptyDataIfExists(at url: URL) -> Data? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value, size > 0 else {
            return nil
        }
        return try? Data(contentsOf: url)
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

    private static func currentMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private enum PoolError: Error {
        case invalid(String)
    }
}
