@preconcurrency import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// File-backed store for recommendation personalization settings, dislikes,
/// impressions, and bounded click history (`recommend_profile.json`).
public final class RecommendProfileStore: @unchecked Sendable {
    public static let schemaVersion = 1
    public static let maxClickedRecords = 100
    public static let maxImpressionRecords = 2000
    public static let fileName = "recommend_profile.json"

    private let lock = NSLock()
    private let storageFileURL: URL
    private let writeQueue: DispatchQueue?
    private var writeSequence: UInt64 = 0

    private var _personalizationEnabled = true
    private var _onboardingDismissed = false
    private var _selectedGenres: [String] = []
    private var _dislikedByTitle: [String: DislikedRecord] = [:]
    private var _dislikeOrder: [String] = []
    private var _impressionsByTitle: [String: ImpressionRecord] = [:]
    private var _clickedRecords: [ClickedRecord] = []
    private var _corrupted = false

    public init(storageFile: URL, asyncPersistence: Bool = false) {
        self.storageFileURL = storageFile
        self.writeQueue = asyncPersistence
            ? DispatchQueue(label: "com.xxcomic.recommend.profile.io", qos: .utility)
            : nil
        lock.lock()
        loadLocked()
        lock.unlock()
    }

    public convenience init(directory: URL, asyncPersistence: Bool = false) {
        self.init(storageFile: directory.appendingPathComponent(Self.fileName), asyncPersistence: asyncPersistence)
    }

    public var isCorrupted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _corrupted
    }

    public var isPersonalizationEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _personalizationEnabled
    }

    public func setPersonalizationEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard _personalizationEnabled != enabled else { return }
        _personalizationEnabled = enabled
        saveLocked()
    }

    public var isOnboardingDismissed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _onboardingDismissed
    }

    public func setOnboardingDismissed(_ dismissed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard _onboardingDismissed != dismissed else { return }
        _onboardingDismissed = dismissed
        saveLocked()
    }

    public func getSelectedGenres() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return _selectedGenres
    }

    public func setSelectedGenres(_ genres: [String]) {
        lock.lock()
        defer { lock.unlock() }
        _selectedGenres.removeAll()
        var seen = Set<String>()
        for raw in genres {
            let g = normalizeGenreInput(raw)
            if !g.isEmpty && seen.insert(g).inserted {
                _selectedGenres.append(g)
            }
        }
        saveLocked()
    }

    @discardableResult
    public func togglePreferredGenre(_ genre: String) -> Bool {
        let g = normalizeGenreInput(genre)
        guard !g.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        let added: Bool
        if let idx = _selectedGenres.firstIndex(of: g) {
            _selectedGenres.remove(at: idx)
            added = false
        } else {
            _selectedGenres.append(g)
            added = true
        }
        saveLocked()
        return added
    }

    public func recordDislike(
        normalizedTitle: String?,
        displayTitle: String?,
        genres: [String] = [],
        author: String = "",
        timestamp: Int64? = nil
    ) {
        let key = resolveKey(normalizedTitle: normalizedTitle, displayTitle: displayTitle)
        guard !key.isEmpty else { return }
        let trimmedDisplay = SearchRules.trim(displayTitle ?? "")
        let safeDisplay = trimmedDisplay.isEmpty ? key : trimmedDisplay
        let cleanGenres = normalizeGenres(genres)
        let safeAuthor = SearchRules.trim(author)
        let ts = (timestamp ?? 0) > 0 ? timestamp! : Self.currentMillis()

        lock.lock()
        defer { lock.unlock() }
        _dislikedByTitle[key] = DislikedRecord(
            normalizedTitle: key,
            displayTitle: safeDisplay,
            genres: cleanGenres,
            author: safeAuthor,
            timestamp: ts
        )
        _dislikeOrder.removeAll { $0 == key }
        _dislikeOrder.append(key)
        saveLocked()
    }

    @discardableResult
    public func undoDislike(_ normalizedTitle: String?) -> Bool {
        guard let normalizedTitle, !SearchRules.trim(normalizedTitle).isEmpty else {
            return undoLastDislike()
        }
        return removeDislike(normalizedTitle)
    }

    @discardableResult
    public func undoLastDislike() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_dislikeOrder.isEmpty else { return false }
        let last = _dislikeOrder.removeLast()
        let removed = _dislikedByTitle.removeValue(forKey: last) != nil
        if removed {
            saveLocked()
        }
        return removed
    }

    @discardableResult
    public func removeDislike(_ normalizedTitle: String?) -> Bool {
        let key = resolveKey(normalizedTitle: normalizedTitle, displayTitle: nil)
        guard !key.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        let removed = _dislikedByTitle.removeValue(forKey: key) != nil
        _dislikeOrder.removeAll { $0 == key }
        if removed {
            saveLocked()
        }
        return removed
    }

    public func isDisliked(_ normalizedTitle: String?) -> Bool {
        let key = resolveKey(normalizedTitle: normalizedTitle, displayTitle: nil)
        guard !key.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return _dislikedByTitle[key] != nil
    }

    public func listDisliked() -> [DislikedRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _dislikedByTitle.values.sorted { $0.timestamp > $1.timestamp }
    }

    public func recordImpressions(_ normalizedTitles: [String], timestamp: Int64? = nil) {
        guard !normalizedTitles.isEmpty else { return }
        let ts = (timestamp ?? 0) > 0 ? timestamp! : Self.currentMillis()
        var uniqueKeys: [String] = []
        var seen = Set<String>()
        for title in normalizedTitles {
            let key = resolveKey(normalizedTitle: title, displayTitle: nil)
            if !key.isEmpty && seen.insert(key).inserted {
                uniqueKeys.append(key)
            }
        }
        guard !uniqueKeys.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        for key in uniqueKeys {
            if let prev = _impressionsByTitle[key] {
                _impressionsByTitle[key] = ImpressionRecord(
                    normalizedTitle: key,
                    impressions: prev.impressions + 1,
                    clicks: prev.clicks,
                    lastImpressionAt: ts,
                    lastClickAt: prev.lastClickAt
                )
            } else {
                _impressionsByTitle[key] = ImpressionRecord(
                    normalizedTitle: key,
                    impressions: 1,
                    clicks: 0,
                    lastImpressionAt: ts,
                    lastClickAt: 0
                )
            }
        }
        trimImpressionsLocked()
        saveLocked()
    }

    public func recordClick(
        normalizedTitle: String?,
        title: String?,
        sourceId: String = "",
        author: String = "",
        genres: [String] = [],
        timestamp: Int64? = nil
    ) {
        let key = resolveKey(normalizedTitle: normalizedTitle, displayTitle: title)
        guard !key.isEmpty else { return }
        let ts = (timestamp ?? 0) > 0 ? timestamp! : Self.currentMillis()
        let trimmedTitle = SearchRules.trim(title ?? "")
        let safeTitle = trimmedTitle.isEmpty ? key : trimmedTitle
        let safeSource = SearchRules.trim(sourceId)
        let safeAuthor = SearchRules.trim(author)
        let cleanGenres = normalizeGenres(genres)

        lock.lock()
        defer { lock.unlock() }
        if let prev = _impressionsByTitle[key] {
            _impressionsByTitle[key] = ImpressionRecord(
                normalizedTitle: key,
                impressions: max(1, prev.impressions),
                clicks: prev.clicks + 1,
                lastImpressionAt: prev.lastImpressionAt,
                lastClickAt: ts
            )
        } else {
            _impressionsByTitle[key] = ImpressionRecord(
                normalizedTitle: key,
                impressions: 1,
                clicks: 1,
                lastImpressionAt: ts,
                lastClickAt: ts
            )
        }
        trimImpressionsLocked()

        _clickedRecords.removeAll { $0.normalizedTitle == key }
        _clickedRecords.insert(
            ClickedRecord(
                normalizedTitle: key,
                title: safeTitle,
                sourceId: safeSource,
                author: safeAuthor,
                genres: cleanGenres,
                clickedAt: ts
            ),
            at: 0
        )
        while _clickedRecords.count > Self.maxClickedRecords {
            _clickedRecords.removeLast()
        }
        saveLocked()
    }

    public func getImpressionRecords() -> [String: ImpressionRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _impressionsByTitle
    }

    public func getImpressionRecord(_ normalizedTitle: String?) -> ImpressionRecord? {
        let key = resolveKey(normalizedTitle: normalizedTitle, displayTitle: nil)
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return _impressionsByTitle[key]
    }

    public func getClickedRecords() -> [ClickedRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _clickedRecords
    }

    public func resetLearningData() {
        lock.lock()
        defer { lock.unlock() }
        _selectedGenres.removeAll()
        _dislikedByTitle.removeAll()
        _dislikeOrder.removeAll()
        _impressionsByTitle.removeAll()
        _clickedRecords.removeAll()
        saveLocked()
    }

    public func flush() {
        writeQueue?.sync {}
    }

    // MARK: - Private

    private func trimImpressionsLocked() {
        guard _impressionsByTitle.count > Self.maxImpressionRecords else { return }
        let sorted = _impressionsByTitle.sorted { a, b in
            let ta = max(a.value.lastImpressionAt, a.value.lastClickAt)
            let tb = max(b.value.lastImpressionAt, b.value.lastClickAt)
            return ta < tb
        }
        let removeCount = _impressionsByTitle.count - Self.maxImpressionRecords
        for i in 0..<min(removeCount, sorted.count) {
            _impressionsByTitle.removeValue(forKey: sorted[i].key)
        }
    }

    private func loadLocked() {
        resetInMemoryLocked()
        _corrupted = false

        let fm = FileManager.default
        let tmpURL = tmpFileURL()
        let exists = fm.fileExists(atPath: storageFileURL.path)
        let size = (try? fm.attributesOfItem(atPath: storageFileURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        if !exists || size == 0 {
            if let tmpBytes = nonEmptyDataIfExists(at: tmpURL) {
                do {
                    try parseAndApplyLocked(tmpBytes)
                    try? moveReplace(from: tmpURL, to: storageFileURL)
                } catch {
                    resetInMemoryLocked()
                }
            }
            return
        }

        do {
            let bytes = try Data(contentsOf: storageFileURL)
            try parseAndApplyLocked(bytes)
            if fm.fileExists(atPath: tmpURL.path) {
                try? fm.removeItem(at: tmpURL)
            }
        } catch {
            backupCorruptFileIfAbsent()
            _corrupted = true
            resetInMemoryLocked()
        }
    }

    private func resetInMemoryLocked() {
        _personalizationEnabled = true
        _onboardingDismissed = false
        _selectedGenres.removeAll()
        _dislikedByTitle.removeAll()
        _dislikeOrder.removeAll()
        _impressionsByTitle.removeAll()
        _clickedRecords.removeAll()
    }

    private func parseAndApplyLocked(_ bytes: Data) throws {
        guard !bytes.isEmpty,
              let raw = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("{"), raw.hasSuffix("}") else {
            throw StoreError.invalid("Invalid root object")
        }
        let obj = try JSONSerialization.jsonObject(with: bytes, options: [])
        guard let root = obj as? [String: Any] else {
            throw StoreError.invalid("Invalid root object")
        }
        guard let verVal = root["version"],
              let ver = JsonValueHelper.strictInt(verVal) else {
            throw StoreError.invalid("Missing schema version")
        }
        guard ver >= 1, ver <= Self.schemaVersion else {
            throw StoreError.invalid("Unsupported version: \(verVal)")
        }

        _personalizationEnabled = RecommendModels.optBool(root, "personalizationEnabled", defaultValue: true)
        _onboardingDismissed = RecommendModels.optBool(root, "onboardingDismissed", defaultValue: false)

        if let rawGenres = root["selectedGenres"] {
            guard let genresArr = rawGenres as? [Any] else {
                throw StoreError.invalid("Invalid selectedGenres")
            }
            var seen = Set<String>()
            for elem in genresArr {
                if let str = elem as? String {
                    let g = normalizeGenreInput(str)
                    if !g.isEmpty && seen.insert(g).inserted {
                        _selectedGenres.append(g)
                    }
                }
            }
        }

        if let rawDisliked = root["dislikedComics"] {
            guard let dislikedArr = rawDisliked as? [Any] else {
                throw StoreError.invalid("Invalid dislikedComics")
            }
            for elem in dislikedArr {
                guard let dict = elem as? [String: Any] else {
                    throw StoreError.invalid("Invalid dislikedComics element")
                }
                if let rec = DislikedRecord.fromJSONObject(dict) {
                    _dislikedByTitle[rec.normalizedTitle] = rec
                    _dislikeOrder.removeAll { $0 == rec.normalizedTitle }
                    _dislikeOrder.append(rec.normalizedTitle)
                }
            }
        }

        if let rawImp = root["impressionRecords"] {
            guard let impObj = rawImp as? [String: Any] else {
                throw StoreError.invalid("Invalid impressionRecords")
            }
            for (rawKey, rawVal) in impObj {
                let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if key.isEmpty || rawVal is NSNull { continue }
                guard let recDict = rawVal as? [String: Any] else {
                    throw StoreError.invalid("Invalid impression record")
                }
                if let rec = ImpressionRecord.fromJSONObject(normalizedTitle: key, obj: recDict) {
                    _impressionsByTitle[rec.normalizedTitle] = rec
                }
            }
        }

        if let rawClicked = root["clickedRecords"] {
            guard let clickArr = rawClicked as? [Any] else {
                throw StoreError.invalid("Invalid clickedRecords")
            }
            for elem in clickArr {
                guard let dict = elem as? [String: Any] else {
                    throw StoreError.invalid("Invalid clickedRecords element")
                }
                if let rec = ClickedRecord.fromJSONObject(dict) {
                    _clickedRecords.append(rec)
                }
            }
            _clickedRecords.sort { $0.clickedAt > $1.clickedAt }
            while _clickedRecords.count > Self.maxClickedRecords {
                _clickedRecords.removeLast()
            }
        }
    }

    private func serializePayloadLocked() throws -> Data {
        var impObj: [String: Any] = [:]
        for (key, value) in _impressionsByTitle {
            impObj[key] = value.toJSONObject()
        }
        var dislikedArr: [[String: Any]] = []
        dislikedArr.reserveCapacity(_dislikeOrder.count)
        for key in _dislikeOrder {
            if let rec = _dislikedByTitle[key] {
                dislikedArr.append(rec.toJSONObject())
            }
        }
        for (key, rec) in _dislikedByTitle where !_dislikeOrder.contains(key) {
            dislikedArr.append(rec.toJSONObject())
        }
        let root: [String: Any] = [
            "version": Self.schemaVersion,
            "personalizationEnabled": _personalizationEnabled,
            "onboardingDismissed": _onboardingDismissed,
            "selectedGenres": _selectedGenres,
            "dislikedComics": dislikedArr,
            "impressionRecords": impObj,
            "clickedRecords": _clickedRecords.map { $0.toJSONObject() }
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
    }

    private func saveLocked() {
        if _corrupted { return }
        guard let payload = try? serializePayloadLocked() else { return }
        writeSequence &+= 1
        let seq = writeSequence

        if let writeQueue {
            writeQueue.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let canWrite = (seq == self.writeSequence) && !self._corrupted
                self.lock.unlock()
                if canWrite {
                    try? self.writePayloadAtomically(payload)
                }
            }
            return
        }
        try? writePayloadAtomically(payload)
    }

    private func writePayloadAtomically(_ payload: Data) throws {
        let parent = storageFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let tmp = tmpFileURL()
        do {
            try payload.write(to: tmp, options: [])
            if let handle = try? FileHandle(forWritingTo: tmp) {
                try? handle.synchronize()
                try? handle.close()
            }
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

    private func backupCorruptFileIfAbsent() {
        let backup = storageFileURL.deletingLastPathComponent()
            .appendingPathComponent(storageFileURL.lastPathComponent + ".corrupt")
        let fm = FileManager.default
        if fm.fileExists(atPath: backup.path) { return }
        if let data = try? Data(contentsOf: storageFileURL) {
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

    private func resolveKey(normalizedTitle: String?, displayTitle: String?) -> String {
        if let normalizedTitle {
            let trimmed = SearchRules.trim(normalizedTitle)
            if !trimmed.isEmpty { return trimmed }
        }
        if let displayTitle {
            let trimmed = SearchRules.trim(displayTitle)
            if !trimmed.isEmpty {
                return RecommendModels.normalizeTitleFallback(trimmed)
            }
        }
        return ""
    }

    private func normalizeGenreInput(_ raw: String) -> String {
        let norm = RecommendSourceClassifier.normalizeGenreTag(raw)
        if !norm.isEmpty { return norm }
        let simplified = RecommendSourceClassifier.toSimplified(raw)
        if simplified.isEmpty || RecommendSourceClassifier.isNoisyTag(simplified) { return "" }
        return simplified
    }

    private func normalizeGenres(_ rawGenres: [String]) -> [String] {
        guard !rawGenres.isEmpty else { return [] }
        let out = RecommendSourceClassifier.extractCanonicalGenres(rawGenres)
        if !out.isEmpty { return out }
        var seen = Set<String>()
        var fallback: [String] = []
        for g in rawGenres {
            let clean = normalizeGenreInput(g)
            if !clean.isEmpty && seen.insert(clean).inserted {
                fallback.append(clean)
            }
        }
        return fallback
    }

    private static func currentMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private enum StoreError: Error {
        case invalid(String)
    }
}
