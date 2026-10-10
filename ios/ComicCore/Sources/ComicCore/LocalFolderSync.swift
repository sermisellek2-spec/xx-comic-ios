import Foundation

public final class LocalFolderSyncCoordinator: @unchecked Sendable {
    public enum SyncResult: Equatable, Sendable {
        case upToDate(fileCount: Int)
        case updated(oldFileCount: Int, newFileCount: Int)
        case error(String)
    }

    public let store: FolderBookmarkStore
    public let library: LocalLibrary
    private let isReadableImage: @Sendable (URL) throws -> Bool

    public init(
        store: FolderBookmarkStore,
        library: LocalLibrary,
        isReadableImage: @escaping @Sendable (URL) throws -> Bool
    ) {
        self.store = store
        self.library = library
        self.isReadableImage = isReadableImage
    }

    /// Links an external folder, acquires persistent security bookmark, and creates or syncs its local series.
    public func linkFolder(url: URL, title: String? = nil) async throws -> SyncedFolderRecord {
        let folderTitle = title ?? url.lastPathComponent
        let bookmark = try BatchImportWorker.createBookmark(for: url)

        #if canImport(Darwin)
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        #endif

        let importResult = try await library.importFolderCoordinated(
            title: folderTitle,
            folder: url,
            isReadableImage: isReadableImage
        )

        let record = SyncedFolderRecord(
            folderName: folderTitle,
            bookmarkData: bookmark,
            seriesId: importResult.series.id,
            lastSyncTimestamp: Date().timeIntervalSince1970,
            fileCount: importResult.book.pages.count,
            status: .active,
            lastError: nil
        )
        try store.save(record: record)
        return record
    }

    /// Unlinks an external folder and optionally deletes its imported local series.
    public func unlinkFolder(id: String, deleteSeries: Bool = false) async throws {
        guard let record = store.record(id: id) else { return }
        try store.remove(id: id)
        if deleteSeries {
            try? await library.deleteSeries(id: record.seriesId)
        }
    }

    /// Synchronizes a single linked folder: checks for added/removed/renamed images.
    public func sync(id: String) async -> SyncResult {
        guard var record = store.record(id: id) else {
            return .error("未找到关联记录")
        }

        let folderURL: URL
        do {
            folderURL = try BatchImportWorker.resolveBookmark(record.bookmarkData)
        } catch {
            record.status = .permissionRevoked
            record.lastError = "权限已失效: \(error.localizedDescription)"
            try? store.save(record: record)
            return .error(record.lastError!)
        }

        #if canImport(Darwin)
        let hasAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { folderURL.stopAccessingSecurityScopedResource() }
        }
        #endif

        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            record.status = .folderMissing
            record.lastError = "文件夹不存在"
            try? store.save(record: record)
            return .error("文件夹不存在")
        }

        do {
            let index = try LocalFolderIndex(folder: folderURL, isReadableImage: isReadableImage)
            let series = try await library.series(id: record.seriesId)
            let currentBook = series.flatMap { try? library.volumes(for: $0).first }
            let oldFingerprint = currentBook?.fingerprint

            let folderFiles = zip(index.relativePaths, index.files).map { (relativePath: $0, ownedFile: $1) }
            let newFingerprint = try ContentFingerprint.folder(folderURL, files: folderFiles)

            if oldFingerprint == newFingerprint && currentBook?.pages.count == index.files.count {
                record.lastSyncTimestamp = Date().timeIntervalSince1970
                record.status = .active
                record.lastError = nil
                try store.save(record: record)
                return .upToDate(fileCount: index.files.count)
            }

            let oldFileCount = record.fileCount
            let result = try await library.updateFolderSeries(
                seriesId: record.seriesId,
                title: record.folderName,
                folder: folderURL,
                isReadableImage: isReadableImage
            )
            record.fileCount = result.book.pages.count
            record.lastSyncTimestamp = Date().timeIntervalSince1970
            record.status = .active
            record.lastError = nil
            try store.save(record: record)
            return .updated(oldFileCount: oldFileCount, newFileCount: record.fileCount)
        } catch {
            record.status = .syncFailed
            record.lastError = error.localizedDescription
            try? store.save(record: record)
            return .error(error.localizedDescription)
        }
    }

    /// Synchronizes all linked folders and returns the results.
    public func syncAll() async -> [String: SyncResult] {
        let all = store.list()
        var results: [String: SyncResult] = [:]
        for record in all {
            results[record.id] = await sync(id: record.id)
        }
        return results
    }
}
