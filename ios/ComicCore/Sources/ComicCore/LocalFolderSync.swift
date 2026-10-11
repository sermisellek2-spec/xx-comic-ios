import Foundation

public actor SingleWriterGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func lock() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    public func unlock() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        } else {
            isLocked = false
        }
    }

    public func execute<T>(_ block: () async throws -> T) async rethrows -> T {
        await lock()
        defer { unlock() }
        return try await block()
    }
}

public final class LocalFolderSyncCoordinator: @unchecked Sendable {
    public enum SyncResult: Equatable, Sendable {
        case upToDate(fileCount: Int)
        case updated(oldFileCount: Int, newFileCount: Int)
        case error(String)
    }
    public let store: FolderBookmarkStore
    public let library: LocalLibrary
    private let isReadableImage: @Sendable (URL) throws -> Bool
    private let syncGate = SingleWriterGate()

    public init(store: FolderBookmarkStore, library: LocalLibrary,
                isReadableImage: @escaping @Sendable (URL) throws -> Bool) {
        self.store = store; self.library = library; self.isReadableImage = isReadableImage
    }

    /// Every link, migration, synchronization and deletion uses one writer.
    public func linkFolder(url: URL, title: String? = nil) async throws -> SyncedFolderRecord {
        try await syncGate.execute {
            try Task.checkCancellation()
            let bookmark = try BatchImportWorker.createBookmark(for: url)
            let sameRecord = store.list().first { record in
                guard let oldURL = try? BatchImportWorker.resolveBookmark(record.bookmarkData) else { return false }
                return oldURL.standardizedFileURL == url.standardizedFileURL
            }
            if let record = sameRecord, try await library.series(id: record.seriesId) != nil {
                return try await indexFolder(url: url, bookmark: bookmark, record: record)
            }
            let fingerprint = try LocalLibrary.linkedFolderIdentity(url)
            if let existing = try await library.findReadySeries(byFingerprint: fingerprint),
               let linked = existing.volume.linkedFolder {
                let record = store.record(id: linked.recordID) ?? SyncedFolderRecord(
                    id: linked.recordID, folderName: title ?? existing.series.displayTitle,
                    bookmarkData: bookmark, seriesId: existing.series.id)
                return try await indexFolder(url: url, bookmark: bookmark, record: record)
            }
            let recordID = sameRecord?.id ?? UUID().uuidString
            let folderTitle = title ?? sameRecord?.folderName ?? url.lastPathComponent
            #if canImport(Darwin)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            #endif
            let prepared = try await prepare(url: url, title: folderTitle, bookmark: bookmark, recordID: recordID, previous: nil)
            let imported = try await library.publishImport(prepared, explicitTitle: folderTitle)
            let record = SyncedFolderRecord(id: recordID, folderName: folderTitle, bookmarkData: bookmark,
                                            seriesId: imported.series.id, fileCount: imported.book.pages.count)
            do { try store.save(record: record) }
            catch {
                // A failed authorization record must not leave a successful new book.
                // publishImport's identity/tombstone recovery remains intact.
                if imported.book.linkedFolder?.recordID == recordID { try await library.deleteSeries(id: imported.series.id) }
                throw error
            }
            return record
        }
    }

    /// A user-selected folder can restore a moved/revoked authorization while keeping
    /// the existing series, volume, chapter IDs, titles and retained page identities.
    public func reauthorize(id: String, url: URL) async throws -> SyncedFolderRecord {
        try await syncGate.execute {
            try Task.checkCancellation()
            guard let record = store.record(id: id) else { throw LocalCatalogError.targetNotFound }
            let bookmark = try BatchImportWorker.createBookmark(for: url)
            return try await indexFolder(url: url, bookmark: bookmark, record: record)
        }
    }

    private func prepare(url: URL, title: String, bookmark: Data, recordID: String,
                         previous: LocalBook?) async throws -> PreparedLocalImport {
        let library = self.library, probe = self.isReadableImage
        let worker = Task.detached(priority: .utility) {
            try library.prepareLinkedFolder(title: title, folder: url, bookmark: bookmark,
                                            recordID: recordID, previous: previous, isReadableImage: probe)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private func indexFolder(url: URL, bookmark: Data, record: SyncedFolderRecord) async throws -> SyncedFolderRecord {
        guard let series = try await library.series(id: record.seriesId), series.status == "ready",
              let first = series.volumeIDs.first else { throw LocalCatalogError.targetNotFound }
        let previous = try library.book(id: first)
        #if canImport(Darwin)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        let prepared = try await prepare(url: url, title: record.folderName, bookmark: bookmark,
                                         recordID: record.id, previous: previous)
        var next = record
        next.bookmarkData = bookmark
        next.fileCount = prepared.book.pages.count
        next.lastSyncTimestamp = Date().timeIntervalSince1970
        next.status = .active; next.lastError = nil
        let persisted = next, store = self.store
        _ = try await library.replaceFolderVolume(seriesId: record.seriesId, prepared: prepared, commitRecord: { _, _ in
            try store.save(record: persisted)
        })
        return next
    }

    /// Removing the sync record keeps the book's own durable bookmark, so stopping
    /// automatic synchronization does not make an indexed book unreadable.
    public func unlinkFolder(id: String, deleteSeries: Bool = false) async throws {
        try await syncGate.execute {
            try Task.checkCancellation()
            guard let record = store.record(id: id) else { return }
            if deleteSeries, try await library.series(id: record.seriesId) != nil {
                try await library.deleteSeries(id: record.seriesId)
            }
            try store.remove(id: id)
        }
    }

    public func deleteSeries(id: String) async throws {
        try await syncGate.execute {
            try Task.checkCancellation()
            if try await library.series(id: id) != nil { try await library.deleteSeries(id: id) }
            for record in store.list() where record.seriesId == id { try store.remove(id: record.id) }
        }
    }

    public func recoverInterruptedSyncs() async throws {
        try await syncGate.execute {
            try Task.checkCancellation()
            try await library.recoverOrphans()
        }
    }

    public func sync(id: String) async -> SyncResult {
        await syncGate.execute { await performSync(id: id) }
    }

    private func performSync(id: String) async -> SyncResult {
        guard var record = store.record(id: id) else { return .error("未找到关联记录") }
        let originalRecord = record
        do {
            try Task.checkCancellation()
            let resolved = try BatchImportWorker.resolveBookmarkWithState(record.bookmarkData)
            let folderURL = resolved.url
            #if canImport(Darwin)
            let scoped = folderURL.startAccessingSecurityScopedResource()
            defer { if scoped { folderURL.stopAccessingSecurityScopedResource() } }
            #endif
            guard FileManager.default.fileExists(atPath: folderURL.path) else { throw CocoaError(.fileNoSuchFile) }
            let bookmark = try resolved.isStale ? BatchImportWorker.createBookmark(for: folderURL) : record.bookmarkData
            guard let series = try await library.series(id: record.seriesId), series.status == "ready",
                  let first = series.volumeIDs.first else { throw LocalCatalogError.targetNotFound }
            let currentBook = try library.book(id: first)
            let prepared = try await prepare(url: folderURL, title: record.folderName, bookmark: bookmark,
                                             recordID: record.id, previous: currentBook)
            if currentBook.linkedFolder?.manifestFingerprint == prepared.book.linkedFolder?.manifestFingerprint,
               currentBook.linkedFolder?.bookmarkData == bookmark {
                try library.discardPrepared(prepared)
                try Task.checkCancellation()
                record.lastSyncTimestamp = Date().timeIntervalSince1970
                record.status = .active; record.lastError = nil
                try store.save(record: record)
                return .upToDate(fileCount: currentBook.pages.count)
            }
            let oldCount = record.fileCount
            record.bookmarkData = bookmark
            record.fileCount = prepared.book.pages.count
            record.lastSyncTimestamp = Date().timeIntervalSince1970
            record.status = .active; record.lastError = nil
            let next = record, store = self.store
            _ = try await library.replaceFolderVolume(seriesId: record.seriesId, prepared: prepared, commitRecord: { _, _ in
                try store.save(record: next)
            })
            return .updated(oldFileCount: oldCount, newFileCount: record.fileCount)
        } catch is CancellationError {
            return .error("已取消同步，原索引保留")
        } catch {
            record = originalRecord
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain && (ns.code == 260 || ns.code == 4) {
                record.status = .folderMissing
            } else if (ns.domain == NSCocoaErrorDomain && (ns.code == 257 || ns.code == 256)) ||
                      (ns.domain == NSPOSIXErrorDomain && (ns.code == 1 || ns.code == 13)) {
                record.status = .permissionRevoked
            } else { record.status = .syncFailed }
            record.lastError = error.localizedDescription
            do { try store.save(record: record) }
            catch { return .error("同步失败，且状态记录保存失败：\(error.localizedDescription)") }
            return .error(record.lastError!)
        }
    }

    public func syncAll() async -> [String: SyncResult] {
        var results: [String: SyncResult] = [:]
        for record in store.list() {
            if Task.isCancelled { break }
            results[record.id] = await sync(id: record.id)
        }
        return results
    }
}
