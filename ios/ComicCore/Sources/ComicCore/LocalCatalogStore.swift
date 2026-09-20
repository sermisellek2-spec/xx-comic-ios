import Foundation

public actor LocalCatalogStore {
    private let file: URL
    private var catalog: LocalCatalog
    private var hasLoadedFromDisk = false

    public var fileURL: URL { file }

    public init(directory: URL) throws {
        self.file = directory.appendingPathComponent("catalog.json")
        let (loadedCatalog, exists) = try Self.loadCatalog(from: file)
        self.catalog = loadedCatalog
        self.hasLoadedFromDisk = exists
    }

    public init(file: URL) throws {
        self.file = file
        let (loadedCatalog, exists) = try Self.loadCatalog(from: file)
        self.catalog = loadedCatalog
        self.hasLoadedFromDisk = exists
    }

    private static func loadCatalog(from file: URL) throws -> (LocalCatalog, Bool) {
        let path = file.path
        guard FileManager.default.fileExists(atPath: path) else {
            return (LocalCatalog(), false)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        if let fileSize = attributes[.size] as? NSNumber, fileSize.int64Value > Int64(LocalCatalog.maxFileBytes) {
            throw LocalCatalogError.catalogTooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw LocalCatalogError.catalogCorrupted
        }
        guard data.count <= LocalCatalog.maxFileBytes else {
            throw LocalCatalogError.catalogTooLarge
        }
        let decoded: LocalCatalog
        do {
            decoded = try JSONDecoder().decode(LocalCatalog.self, from: data)
        } catch {
            throw LocalCatalogError.catalogCorrupted
        }
        guard decoded.version == LocalCatalog.currentVersion else {
            throw LocalCatalogError.unsupportedVersion
        }
        return (decoded, true)
    }

    public func existsOnDisk() -> Bool {
        FileManager.default.fileExists(atPath: file.path)
    }

    public func currentCatalog() -> LocalCatalog {
        catalog
    }

    public func listSeries() -> [LocalSeriesRecord] {
        catalog.series
    }

    public func listReadySeries() -> [LocalSeriesRecord] {
        catalog.series.filter { $0.status == "ready" }.sorted {
            $0.updatedAt == $1.updatedAt ? $0.createdAt > $1.createdAt : $0.updatedAt > $1.updatedAt
        }
    }

    public func getSeries(id: String) -> LocalSeriesRecord? {
        catalog.series.first { $0.id == id }
    }

    public func findSeries(byVolumeID volumeId: String) -> LocalSeriesRecord? {
        catalog.series.first { $0.volumeIDs.contains(volumeId) }
    }

    public func findTombstone(byFingerprint fingerprint: String) -> LocalDeletedFingerprintRecord? {
        catalog.tombstones.first { $0.fingerprint == fingerprint }
    }

    public func listTombstones() -> [LocalDeletedFingerprintRecord] {
        catalog.tombstones
    }

    public func removeTombstones(forSeriesId seriesId: String) throws {
        var next = catalog
        let countBefore = next.tombstones.count
        next.tombstones.removeAll { $0.seriesId == seriesId }
        if next.tombstones.count != countBefore {
            try persist(next)
        }
    }

    public func seedLegacySeriesIfNeeded(_ legacySeries: [LocalSeriesRecord]) throws {
        guard !hasLoadedFromDisk && !FileManager.default.fileExists(atPath: file.path) else { return }
        if catalog.series.isEmpty && !legacySeries.isEmpty {
            var next = catalog
            next.series = legacySeries
            try persist(next)
        }
    }

    public func commitNewSeries(_ series: LocalSeriesRecord, removingFingerprints: [String] = []) throws {
        var next = catalog
        if let existingIndex = next.series.firstIndex(where: { $0.id == series.id }) {
            next.series[existingIndex] = series
        } else {
            next.series.append(series)
        }
        if !removingFingerprints.isEmpty {
            let toRemove = Set(removingFingerprints)
            next.tombstones.removeAll { toRemove.contains($0.fingerprint) }
        }
        try persist(next)
    }

    public func appendVolume(seriesId: String, volumeId: String, removingFingerprints: [String] = []) throws {
        guard let index = catalog.series.firstIndex(where: { $0.id == seriesId }) else {
            throw LocalCatalogError.targetNotFound
        }
        guard catalog.series[index].status == "ready" else {
            throw LocalCatalogError.targetNotReady
        }
        var updated = catalog.series[index]
        guard !updated.volumeIDs.contains(volumeId) else { return }
        updated.volumeIDs.append(volumeId)
        updated.updatedAt = Date().timeIntervalSince1970

        var next = catalog
        next.series[index] = updated
        if !removingFingerprints.isEmpty {
            let toRemove = Set(removingFingerprints)
            next.tombstones.removeAll { toRemove.contains($0.fingerprint) }
        }
        try persist(next)
    }

    public func renameSeries(id: String, newTitle: String) throws -> LocalSeriesRecord {
        let trimmed = SearchRules.trim(newTitle)
        guard !trimmed.isEmpty else {
            throw LocalCatalogError.titleEmpty
        }
        guard let index = catalog.series.firstIndex(where: { $0.id == id }) else {
            throw LocalCatalogError.targetNotFound
        }
        var updated = catalog.series[index]
        updated.userTitle = trimmed
        updated.updatedAt = Date().timeIntervalSince1970

        var next = catalog
        next.series[index] = updated
        try persist(next)
        return updated
    }

    public func reorderVolumes(seriesId: String, newVolumeIDs: [String]) throws {
        guard let index = catalog.series.firstIndex(where: { $0.id == seriesId }) else {
            throw LocalCatalogError.targetNotFound
        }
        let currentVolumes = catalog.series[index].volumeIDs
        guard currentVolumes.count == newVolumeIDs.count,
              Set(currentVolumes) == Set(newVolumeIDs),
              Set(newVolumeIDs).count == newVolumeIDs.count else {
            throw LocalCatalogError.invalidPermutation
        }
        var updated = catalog.series[index]
        updated.volumeIDs = newVolumeIDs
        updated.updatedAt = Date().timeIntervalSince1970

        var next = catalog
        next.series[index] = updated
        try persist(next)
    }

    public func markSeriesDeleting(seriesId: String) throws {
        guard let index = catalog.series.firstIndex(where: { $0.id == seriesId }) else {
            throw LocalCatalogError.targetNotFound
        }
        var updated = catalog.series[index]
        updated.status = "deleting"
        updated.updatedAt = Date().timeIntervalSince1970

        var next = catalog
        next.series[index] = updated
        try persist(next)
    }

    public func completeSeriesDeletion(seriesId: String, newTombstones: [LocalDeletedFingerprintRecord]) throws {
        var next = catalog
        next.series.removeAll { $0.id == seriesId }
        for tombstone in newTombstones {
            if let existing = next.tombstones.firstIndex(where: { $0.fingerprint == tombstone.fingerprint }) {
                next.tombstones[existing] = tombstone
            } else {
                next.tombstones.append(tombstone)
            }
        }
        try persist(next)
    }

    public func removeVolumeFromSeries(seriesId: String, volumeId: String, newTombstones: [LocalDeletedFingerprintRecord] = []) throws {
        guard let index = catalog.series.firstIndex(where: { $0.id == seriesId }) else {
            throw LocalCatalogError.targetNotFound
        }
        var updated = catalog.series[index]
        guard let volIndex = updated.volumeIDs.firstIndex(of: volumeId) else {
            throw LocalCatalogError.volumeNotFound
        }
        updated.volumeIDs.remove(at: volIndex)
        updated.updatedAt = Date().timeIntervalSince1970

        var next = catalog
        next.series[index] = updated
        for tombstone in newTombstones {
            if let existing = next.tombstones.firstIndex(where: { $0.fingerprint == tombstone.fingerprint }) {
                next.tombstones[existing] = tombstone
            } else {
                next.tombstones.append(tombstone)
            }
        }
        try persist(next)
    }

    public func removeTombstone(seriesId: String) throws {
        var next = catalog
        next.tombstones.removeAll { $0.seriesId == seriesId }
        try persist(next)
    }

    public func removeTombstone(fingerprint: String) throws {
        var next = catalog
        next.tombstones.removeAll { $0.fingerprint == fingerprint }
        try persist(next)
    }

    private func persist(_ next: LocalCatalog) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(next)
        guard data.count <= LocalCatalog.maxFileBytes else {
            throw LocalCatalogError.catalogTooLarge
        }
        try data.write(to: file, options: .atomic)
        self.catalog = next
        self.hasLoadedFromDisk = true
    }
}
