import Foundation

public enum SyncedFolderStatus: String, Codable, Sendable {
    case active
    case permissionRevoked
    case folderMissing
    case syncFailed
}

public struct SyncedFolderRecord: Codable, Equatable, Sendable {
    public let id: String
    public var folderName: String
    public var bookmarkData: Data
    public var seriesId: String
    public var lastSyncTimestamp: TimeInterval
    public var fileCount: Int
    public var status: SyncedFolderStatus
    public var lastError: String?

    public init(
        id: String = UUID().uuidString,
        folderName: String,
        bookmarkData: Data,
        seriesId: String,
        lastSyncTimestamp: TimeInterval = Date().timeIntervalSince1970,
        fileCount: Int = 0,
        status: SyncedFolderStatus = .active,
        lastError: String? = nil
    ) {
        self.id = id
        self.folderName = folderName
        self.bookmarkData = bookmarkData
        self.seriesId = seriesId
        self.lastSyncTimestamp = lastSyncTimestamp
        self.fileCount = fileCount
        self.status = status
        self.lastError = lastError
    }
}

public final class FolderBookmarkStore: @unchecked Sendable {
    private struct FileData: Codable {
        var folders: [SyncedFolderRecord] = []
    }

    private let file: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private let lock = NSLock()
    private var folders: [SyncedFolderRecord] = []

    public convenience init(directory: URL) throws {
        try self.init(directory: directory, write: { try $0.write(to: $1, options: .atomic) })
    }

    init(directory: URL, write: @escaping @Sendable (Data, URL) throws -> Void) throws {
        self.file = directory.appendingPathComponent("synced_folders.json")
        self.write = write
        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            let decoded = try JSONDecoder().decode(FileData.self, from: data)
            self.folders = decoded.folders
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.folders = []
        }
    }

    public func list() -> [SyncedFolderRecord] {
        lock.lock()
        defer { lock.unlock() }
        return folders
    }

    public func record(id: String) -> SyncedFolderRecord? {
        lock.lock()
        defer { lock.unlock() }
        return folders.first { $0.id == id }
    }

    public func record(seriesId: String) -> SyncedFolderRecord? {
        lock.lock()
        defer { lock.unlock() }
        return folders.first { $0.seriesId == seriesId }
    }

    public func save(record: SyncedFolderRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = folders
        if let idx = next.firstIndex(where: { $0.id == record.id }) {
            next[idx] = record
        } else {
            next.append(record)
        }
        try persistLocked(next)
        folders = next
    }

    public func remove(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let next = folders.filter { $0.id != id }
        try persistLocked(next)
        folders = next
    }

    private func persistLocked(_ next: [SyncedFolderRecord]) throws {
        let data = try JSONEncoder().encode(FileData(folders: next))
        try write(data, file)
    }
}
