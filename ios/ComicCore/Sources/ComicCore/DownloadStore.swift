import Foundation

public enum DownloadStoreError: LocalizedError, Sendable {
    case storeCorrupted
    case storeTooLarge
    case unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .storeCorrupted:
            return "下载数据库损坏"
        case .storeTooLarge:
            return "下载数据库超出大小限制（16 MiB）"
        case .unsupportedVersion:
            return "下载数据库版本不支持"
        }
    }
}

public struct DownloadStoreData: Codable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var order: [String]
    public var tasks: [String: DownloadTask]
    public var snapshots: [String: ComicDetail]
    public var pages: [String: [DownloadPage]]

    public init(version: Int = DownloadStoreData.currentVersion,
                order: [String] = [],
                tasks: [String: DownloadTask] = [:],
                snapshots: [String: ComicDetail] = [:],
                pages: [String: [DownloadPage]] = [:]) {
        self.version = version
        self.order = order
        self.tasks = tasks
        self.snapshots = snapshots
        self.pages = pages
    }
}

public final class DownloadStore: DownloadRepository, @unchecked Sendable {
    public static let maxFileBytes = 16 * 1024 * 1024 // 16 MiB

    private let file: URL
    private let lock = NSLock()
    private var data: DownloadStoreData

    public var fileURL: URL { file }

    public convenience init(directory: URL) throws {
        let file = directory.appendingPathComponent("downloads.json")
        try self.init(file: file)
    }

    public init(file: URL) throws {
        self.file = file
        let parent = file.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: file.path) {
            let loaded = try Self.loadData(from: file)
            self.data = loaded
        } else {
            self.data = DownloadStoreData()
        }
    }

    private static func loadData(from file: URL) throws -> DownloadStoreData {
        let path = file.path
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        if let fileSize = attributes[.size] as? NSNumber, fileSize.int64Value > Int64(maxFileBytes) {
            throw DownloadStoreError.storeTooLarge
        }
        let rawData: Data
        do {
            rawData = try Data(contentsOf: file)
        } catch {
            throw DownloadStoreError.storeCorrupted
        }
        guard rawData.count <= maxFileBytes else {
            throw DownloadStoreError.storeTooLarge
        }
        let decoded: DownloadStoreData
        do {
            decoded = try JSONDecoder().decode(DownloadStoreData.self, from: rawData)
        } catch {
            throw DownloadStoreError.storeCorrupted
        }
        guard decoded.version == DownloadStoreData.currentVersion else {
            throw DownloadStoreError.unsupportedVersion
        }
        return decoded
    }

    private func persistLocked() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let encoded: Data
        do {
            encoded = try encoder.encode(data)
        } catch {
            throw DownloadStoreError.storeCorrupted
        }
        guard encoded.count <= Self.maxFileBytes else {
            throw DownloadStoreError.storeTooLarge
        }
        try encoded.write(to: file, options: .atomic)
    }

    // MARK: - DownloadRepository Protocol

    public func list() -> [DownloadTask] {
        lock.lock()
        defer { lock.unlock() }
        return data.order.compactMap { data.tasks[$0] }
    }

    public func get(id: String) -> DownloadTask? {
        lock.lock()
        defer { lock.unlock() }
        return data.tasks[id]
    }

    public func save(task: DownloadTask) {
        lock.lock()
        defer { lock.unlock() }
        if data.tasks[task.id] == nil {
            data.order.append(task.id)
        }
        data.tasks[task.id] = task
        try? persistLocked()
    }

    public func saveSnapshot(_ detail: ComicDetail) {
        lock.lock()
        defer { lock.unlock() }
        guard let id = try? DownloadModels.bookId(source: detail.summary.sourceId, comic: detail.summary.comicId) else {
            return
        }
        data.snapshots[id] = detail
        try? persistLocked()
    }

    public func snapshot(id: String) -> ComicDetail? {
        lock.lock()
        defer { lock.unlock() }
        return data.snapshots[id]
    }

    public func pages(task: String) -> [DownloadPage] {
        lock.lock()
        defer { lock.unlock() }
        return (data.pages[task] ?? []).sorted(by: { $0.index < $1.index })
    }

    public func savePage(task: String, page: DownloadPage) {
        lock.lock()
        defer { lock.unlock() }
        var current = data.pages[task] ?? []
        if let idx = current.firstIndex(where: { $0.index == page.index }) {
            current[idx] = page
        } else {
            current.append(page)
        }
        data.pages[task] = current.sorted(by: { $0.index < $1.index })
        try? persistLocked()
    }

    public func clearPages(task: String) {
        lock.lock()
        defer { lock.unlock() }
        data.pages.removeValue(forKey: task)
        try? persistLocked()
    }

    public func replacePages(task: String, pages: [DownloadPage]) {
        lock.lock()
        defer { lock.unlock() }
        data.pages[task] = pages.sorted(by: { $0.index < $1.index })
        try? persistLocked()
    }

    public func remove(task: String) {
        lock.lock()
        defer { lock.unlock() }
        data.pages.removeValue(forKey: task)
        data.tasks.removeValue(forKey: task)
        data.order.removeAll(where: { $0 == task })
        try? persistLocked()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        // Flush any pending changes
        try? persistLocked()
    }
}
