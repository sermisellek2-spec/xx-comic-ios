import Foundation

/// The app owns one session actor. URIs are opaque metadata, not persisted file authorization.
public actor BatchImportSession {
    public enum State: String, Codable, Sendable {
        case pending, running, completed, skipped, failed
    }

    public struct Item: Codable, Equatable, Sendable {
        public let uri: String
        public let name: String
        public let format: String
        public let selectionIndex: Int
        public fileprivate(set) var state: State = .pending
        public fileprivate(set) var error: String = ""

        public init(uri: String, name: String, format: String, selectionIndex: Int) {
            self.uri = uri
            self.name = name
            self.format = format
            self.selectionIndex = selectionIndex
        }
    }

    public struct Group: Codable, Equatable, Sendable {
        public let key: String
        public let title: String
        public fileprivate(set) var targetBookId: String
        public let requiresExistingBook: Bool
        public fileprivate(set) var items: [Item]

        public init(key: String, title: String, targetBookId: String,
                    requiresExistingBook: Bool = false, items: [Item]) {
            self.key = key
            self.title = title
            self.targetBookId = targetBookId
            self.requiresExistingBook = requiresExistingBook
            self.items = items
        }

        private enum CodingKeys: String, CodingKey {
            case key, title, targetBookId, requiresExistingBook, items
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            key = try values.decode(String.self, forKey: .key)
            title = try values.decode(String.self, forKey: .title)
            targetBookId = try values.decode(String.self, forKey: .targetBookId)
            requiresExistingBook = values.contains(.requiresExistingBook)
                ? try values.decode(Bool.self, forKey: .requiresExistingBook) : false
            items = try values.decode([Item].self, forKey: .items)
        }
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public let version: Int
        public let taskId: String
        public fileprivate(set) var groups: [Group]
        public fileprivate(set) var cancelled: Bool
    }

    public enum SessionError: Error, Equatable {
        case unfinishedBatch, taskMismatch, invalidIndex, cancelled
        case tooLarge, unsupportedVersion, invalidSnapshot
    }

    private static let byteLimit = 16 * 1024 * 1024
    private let file: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private var snapshot: Snapshot?

    public init(file: URL) throws {
        try self.init(file: file, write: { try $0.write(to: $1, options: .atomic) })
    }

    init(file: URL, write: @escaping @Sendable (Data, URL) throws -> Void) throws {
        self.file = file
        self.write = write
        snapshot = try Self.load(file)
    }

    public func current() -> Snapshot? { snapshot }

    public func create(groups: [Group]) throws -> Snapshot {
        if let snapshot, !snapshot.cancelled,
           snapshot.groups.contains(where: { $0.items.contains(where: { !Self.finished($0) }) }) {
            throw SessionError.unfinishedBatch
        }
        let next = Snapshot(version: 1, taskId: UUID().uuidString, groups: groups, cancelled: false)
        try persist(next)
        return next
    }

    public func start(taskID: String, group: Int, item: Int) throws {
        var next = try checked(taskID, group: group, item: item)
        guard !next.cancelled else { throw SessionError.cancelled }
        guard next.groups[group].items[item].state == .pending else { return }
        next.groups[group].items[item].state = .running
        next.groups[group].items[item].error = ""
        try persist(next)
    }

    public func complete(taskID: String, group: Int, item: Int, bookID: String) throws {
        try changeItem(taskID: taskID, group: group, item: item, state: .completed, bookID: bookID)
    }

    public func fail(taskID: String, group: Int, item: Int, error: String) throws {
        try changeItem(taskID: taskID, group: group, item: item, state: .failed, error: error)
    }

    public func skip(taskID: String, group: Int, item: Int) throws {
        try changeItem(taskID: taskID, group: group, item: item, state: .skipped)
    }

    public func setTargetBookID(taskID: String, group: Int, bookID: String) throws {
        var next = try checked(taskID, group: group)
        guard !next.cancelled else { return }
        next.groups[group].targetBookId = bookID
        try persist(next)
    }

    /// The caller must stop the previous worker before retrying; this actor does not cancel workers.
    public func retryFailed(taskID: String) throws { try changeUnfinished(taskID: taskID, cancel: false) }
    public func cancel(taskID: String) throws { try changeUnfinished(taskID: taskID, cancel: true) }

    public func pendingGroupIndices() -> [Int] {
        guard let snapshot, !snapshot.cancelled else { return [] }
        return snapshot.groups.indices.filter { index in
            snapshot.groups[index].items.contains { $0.state == .pending || $0.state == .running }
        }
    }

    private static func finished(_ item: Item) -> Bool { item.state == .completed || item.state == .skipped }

    private func checked(_ taskID: String, group: Int? = nil, item: Int? = nil) throws -> Snapshot {
        guard let next = snapshot, next.taskId == taskID else { throw SessionError.taskMismatch }
        if let group {
            guard next.groups.indices.contains(group) else { throw SessionError.invalidIndex }
            if let item, !next.groups[group].items.indices.contains(item) { throw SessionError.invalidIndex }
        }
        return next
    }

    private func changeItem(taskID: String, group: Int, item: Int, state: State,
                            error: String = "", bookID: String = "") throws {
        var next = try checked(taskID, group: group, item: item)
        guard !next.cancelled, !Self.finished(next.groups[group].items[item]) else { return }
        if !bookID.isEmpty { next.groups[group].targetBookId = bookID }
        next.groups[group].items[item].state = state
        next.groups[group].items[item].error = error
        try persist(next)
    }

    private func changeUnfinished(taskID: String, cancel: Bool) throws {
        var next = try checked(taskID)
        guard !next.cancelled else { return }
        for group in next.groups.indices {
            for item in next.groups[group].items.indices {
                let value = next.groups[group].items[item]
                if cancel ? !Self.finished(value) : (value.state == .failed || value.state == .running) {
                    next.groups[group].items[item].state = cancel ? .skipped : .pending
                    next.groups[group].items[item].error = ""
                }
            }
        }
        next.cancelled = cancel
        try persist(next)
    }

    private func persist(_ next: Snapshot) throws {
        let data = try JSONEncoder().encode(next)
        guard data.count <= Self.byteLimit else { throw SessionError.tooLarge }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(data, file)
        snapshot = next
    }

    private static func load(_ file: URL) throws -> Snapshot? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain &&
                (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) { return nil }
            throw error
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SessionError.invalidSnapshot }
        if let size = attributes[.size] as? NSNumber, size.int64Value > byteLimit { throw SessionError.tooLarge }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(8192, byteLimit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= byteLimit else { throw SessionError.tooLarge }
        }
        guard String(data: data, encoding: .utf8) != nil else { throw SessionError.invalidSnapshot }
        var restored = try JSONDecoder().decode(Snapshot.self, from: data)
        guard restored.version == 1 else { throw SessionError.unsupportedVersion }
        guard UUID(uuidString: restored.taskId) != nil else { throw SessionError.invalidSnapshot }
        for group in restored.groups.indices {
            for item in restored.groups[group].items.indices where restored.groups[group].items[item].state == .running {
                restored.groups[group].items[item].state = .pending
            }
        }
        return restored
    }
}
