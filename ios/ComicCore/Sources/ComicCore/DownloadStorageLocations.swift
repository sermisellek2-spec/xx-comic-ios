import Foundation

public enum DownloadLocationError: LocalizedError {
    case invalidStore, permissionRequired(String), unsafePath, unknownLocation, wrongFolder
    public var errorDescription: String? {
        switch self {
        case .invalidStore: return "下载位置记录无法读取，原记录已保留"
        case .permissionRequired(let name): return "无法访问下载目录「\(name)」，请到本地存储管理重新授权"
        case .unsafePath: return "下载路径含外部链接或未知文件，已保留原文件"
        case .unknownLocation: return "下载目录记录不存在，请重新选择目录"
        case .wrongFolder: return "所选目录不包含原下载副本，请选择原目录；已有内容不会迁移"
        }
    }
}

/// Book identity stays independent of its physical directory and the current default.
/// Security scopes stay open while this service is alive, including offline readers.
public final class DownloadStorageLocations: @unchecked Sendable {
    public struct Location: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        fileprivate var bookmark: Data
    }
    public struct BookmarkAccess: Sendable {
        public let create: @Sendable (URL) throws -> Data
        public let resolve: @Sendable (Data) throws -> URL
        public let start: @Sendable (URL) -> Bool
        public let stop: @Sendable (URL) -> Void
        public init(create: @escaping @Sendable (URL) throws -> Data, resolve: @escaping @Sendable (Data) throws -> URL,
                    start: @escaping @Sendable (URL) -> Bool, stop: @escaping @Sendable (URL) -> Void) {
            self.create = create; self.resolve = resolve; self.start = start; self.stop = stop
        }
        public static let system = BookmarkAccess(create: { url in
            #if canImport(Darwin)
            return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            throw DownloadLocationError.permissionRequired(url.lastPathComponent)
            #endif
        }, resolve: { data in
            #if canImport(Darwin)
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else { throw DownloadLocationError.permissionRequired("原目录") }
            return url
            #else
            throw DownloadLocationError.permissionRequired("原目录")
            #endif
        }, start: { url in
            #if canImport(Darwin)
            return url.startAccessingSecurityScopedResource()
            #else
            return false
            #endif
        }, stop: { url in
            #if canImport(Darwin)
            url.stopAccessingSecurityScopedResource()
            #endif
        })
    }
    private struct Mapping: Codable {
        let locationID: String
        let bookName: String
        var chapters: [String: String]
        let legacy: Bool
    }
    private struct State: Codable {
        var version = 1
        var selectedID = "default_private"
        var locations: [String: Location] = [:]
        var books: [String: Mapping] = [:]
    }
    public static let defaultID = "default_private"
    public static let ownershipFile = ".xxcomic-book"
    public let privateDirectory: URL
    private let file: URL
    private let access: BookmarkAccess
    private let coordinator: FileAccessCoordinator
    private let lock = NSRecursiveLock()
    private var state: State
    private var scopes: [String: URL] = [:]

    public init(file: URL, privateDirectory: URL, access: BookmarkAccess = .system,
                coordinator: FileAccessCoordinator = .system) throws {
        self.file = file; self.privateDirectory = privateDirectory; self.access = access; self.coordinator = coordinator
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 16 * 1024 * 1024 else { throw DownloadLocationError.invalidStore }
                let bytes = try Data(contentsOf: file)
                guard bytes.count <= 16 * 1024 * 1024 else { throw DownloadLocationError.invalidStore }
                state = try JSONDecoder().decode(State.self, from: bytes)
                guard state.version == 1, state.selectedID == Self.defaultID || state.locations[state.selectedID] != nil,
                      state.books.allSatisfy({ Self.component($0.key) && Self.component($0.value.bookName) &&
                          ($0.value.locationID == Self.defaultID || state.locations[$0.value.locationID] != nil) &&
                          $0.value.chapters.allSatisfy({ Self.component($0.key) && Self.component($0.value) }) &&
                          (!$0.value.legacy || ($0.value.locationID == Self.defaultID && $0.value.bookName == $0.key && $0.value.chapters.allSatisfy { $0.key == $0.value })) }) else {
                    throw DownloadLocationError.invalidStore
                }
            } catch { throw DownloadLocationError.invalidStore }
        } else { state = State() }
    }
    deinit { scopes.values.forEach(access.stop) }
    public var selectedID: String { lock.lock(); defer { lock.unlock() }; return state.selectedID }
    public var selectedName: String {
        lock.lock(); defer { lock.unlock() }
        return state.locations[state.selectedID].map { "自定义目录：" + $0.name + " (XXComic/downloads)" } ?? "应用私有存储 (默认)"
    }
    public var locations: [Location] { lock.lock(); defer { lock.unlock() }; return state.locations.values.sorted { $0.name < $1.name } }
    public func useDefault() throws {
        lock.lock(); defer { lock.unlock() }
        var next = state; next.selectedID = Self.defaultID; try persist(next)
    }

    /// Called on a worker after Files returns its scoped URL. A URL string is never stored as permission.
    @discardableResult public func select(directory: URL, reauthorizing id: String? = nil) throws -> String {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        guard access.start(directory) else { throw DownloadLocationError.permissionRequired(directory.lastPathComponent) }
        var retainScope = false
        defer { if !retainScope { access.stop(directory) } }
        try coordinator.coordinate(directory, access: .write) { coordinated in
            guard coordinated.standardizedFileURL == directory.standardizedFileURL else { throw DownloadLocationError.wrongFolder }
            let root = try externalRoot(coordinated, create: true)
            if let id {
                guard state.locations[id] != nil else { throw DownloadLocationError.unknownLocation }
                // Reauthorization cannot silently point old books at a different, empty folder.
                for (bookID, mapping) in state.books where mapping.locationID == id {
                    let book = root.appendingPathComponent(mapping.bookName, isDirectory: true)
                    try assertDirectory(book, create: false)
                    guard (try? ownershipID(in: book)) == bookID else { throw DownloadLocationError.wrongFolder }
                }
            }
            let probe = root.appendingPathComponent(".xxcomic-write-test-" + UUID().uuidString)
            let payload = Data("XX_COMIC_STORAGE_OK".utf8)
            try payload.write(to: probe, options: .withoutOverwriting)
            do {
                guard try FileAccessCoordinator.readRegularFile(probe, maximumBytes: 64) == payload else { throw DownloadLocationError.unsafePath }
                try FileManager.default.removeItem(at: probe)
            } catch { try? FileManager.default.removeItem(at: probe); throw error }
        }
        try Task.checkCancellation()
        let locationID = id ?? "files_" + UUID().uuidString
        let bookmark = try access.create(directory)
        var next = state
        next.locations[locationID] = Location(id: locationID, name: directory.lastPathComponent, bookmark: bookmark)
        next.selectedID = locationID
        try persist(next)
        if let old = scopes[locationID] { access.stop(old) }
        scopes[locationID] = directory; retainScope = true
        return locationID
    }

    public func prepare(_ task: DownloadTask, comicTitle: String, locationID requestedLocation: String? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        guard Self.component(task.bookId), Self.component(task.id) else { throw DownloadLocationError.unsafePath }
        if state.books[task.bookId] == nil {
            var next = state
            let legacy = FileManager.default.fileExists(atPath: privateDirectory.appendingPathComponent(task.bookId).path)
            let locationID = legacy ? Self.defaultID : (requestedLocation ?? state.selectedID)
            try withRoot(locationID, access: .write, create: true) { root in
                let name = legacy ? task.bookId : try uniqueName(title: comicTitle + "_" + task.sourceId, id: task.bookId, in: root)
                let book = root.appendingPathComponent(name, isDirectory: true)
                try assertDirectory(book, create: true)
                if !legacy { try Data(task.bookId.utf8).write(to: book.appendingPathComponent(Self.ownershipFile), options: .withoutOverwriting) }
                next.books[task.bookId] = Mapping(locationID: locationID, bookName: name, chapters: [:], legacy: legacy)
            }
            try persist(next)
        }
        if !task.isFileTask, state.books[task.bookId]!.chapters[task.id] == nil {
            var next = state
            try withBookDirectory(bookID: task.bookId, access: .read) { book in
                let name = next.books[task.bookId]!.legacy ? task.id : try uniqueName(title: task.title, id: task.id, in: book)
                next.books[task.bookId]!.chapters[task.id] = name
            }
            try persist(next)
        }
    }
    public func bookDirectory(bookID: String) throws -> URL {
        try withBookDirectory(bookID: bookID, access: .read) { $0 }
    }
    public func chapterDirectory(_ task: DownloadTask, create: Bool = false) throws -> URL {
        try withBookDirectory(bookID: task.bookId, access: create ? .write : .read) {
            try chapterDirectory(task, in: $0, create: create)
        }
    }
    // These helpers are used inside a single accessor; they never start nested coordination.
    func chapterDirectory(_ task: DownloadTask, in book: URL, create: Bool = false) throws -> URL {
        guard Self.component(task.id) else { throw DownloadLocationError.unsafePath }
        let directory = book.appendingPathComponent(chapterName(task), isDirectory: true)
        if create || FileManager.default.fileExists(atPath: directory.path) { try assertDirectory(directory, create: create) }
        else if let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw DownloadLocationError.unsafePath
        }
        return directory
    }
    public func pageURL(_ page: DownloadPage, task: DownloadTask) throws -> URL {
        guard page.path == "\(task.bookId)/\(task.id)/\(page.index).img", page.index >= 0 else { throw DownloadLocationError.unsafePath }
        return try chapterDirectory(task).appendingPathComponent("\(page.index).img")
    }
    public func chapterName(_ task: DownloadTask) -> String {
        lock.lock(); defer { lock.unlock() }; return state.books[task.bookId]?.chapters[task.id] ?? task.id
    }
    public func hasOwnershipMarker(bookID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return state.books[bookID].map { !$0.legacy } ?? false
    }
    public func removeMapping(bookID: String) throws {
        lock.lock(); defer { lock.unlock() }; var next = state; next.books.removeValue(forKey: bookID); try persist(next)
    }

    /// All provider I/O, including ownership checks, happens within this bounded accessor.
    /// The callback must not start asynchronous work or another coordination request.
    public func withBookDirectory<T>(bookID: String, access mode: FileAccessCoordinator.Access, body: (URL) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard Self.component(bookID) else { throw DownloadLocationError.unsafePath }
        let mapping = state.books[bookID]
        let locationID = mapping?.locationID ?? Self.defaultID
        let base = try resolvedDirectory(locationID)
        let root = locationID == Self.defaultID ? base : base.appendingPathComponent("XXComic", isDirectory: true).appendingPathComponent("downloads", isDirectory: true)
        let book = root.appendingPathComponent(mapping?.bookName ?? bookID, isDirectory: true)
        return try coordinator.coordinate(book, access: mode) { coordinated in
            guard coordinated.standardizedFileURL == book.standardizedFileURL else { throw DownloadLocationError.permissionRequired(base.lastPathComponent) }
            if locationID == Self.defaultID { try assertDirectory(root, create: false) }
            else { _ = try externalRoot(base, create: false) }
            // A missing owned directory is allowed for deletion retries after a database failure.
            let exists = FileManager.default.fileExists(atPath: coordinated.path)
            if exists { try assertDirectory(coordinated, create: false) }
            else if let attributes = try? FileManager.default.attributesOfItem(atPath: coordinated.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw DownloadLocationError.unsafePath
            } else if mapping != nil, mode != .delete { throw CocoaError(.fileReadNoSuchFile) }
            if exists, let mapping, !mapping.legacy {
                guard try ownershipID(in: coordinated) == bookID else { throw DownloadLocationError.unsafePath }
            }
            return try body(coordinated)
        }
    }

    /// Locate a previously recorded page without reading arbitrary paths from a URL.
    public func relativePath(of url: URL, bookID: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        guard url.isFileURL, Self.component(bookID) else { throw DownloadLocationError.unsafePath }
        let mapping = state.books[bookID], id = mapping?.locationID ?? Self.defaultID
        let base = try resolvedDirectory(id)
        let root = id == Self.defaultID ? base : base.appendingPathComponent("XXComic").appendingPathComponent("downloads")
        let prefix = root.appendingPathComponent(mapping?.bookName ?? bookID).standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    private func ownershipID(in book: URL) throws -> String {
        let bytes = try FileAccessCoordinator.readRegularFile(book.appendingPathComponent(Self.ownershipFile), maximumBytes: 256)
        guard let value = String(data: bytes, encoding: .utf8) else { throw DownloadLocationError.unsafePath }
        return value
    }
    private func withRoot<T>(_ id: String, access mode: FileAccessCoordinator.Access, create: Bool, body: (URL) throws -> T) throws -> T {
        let base = try resolvedDirectory(id)
        return try coordinator.coordinate(base, access: mode) { coordinated in
            guard coordinated.standardizedFileURL == base.standardizedFileURL else { throw DownloadLocationError.permissionRequired(base.lastPathComponent) }
            if id == Self.defaultID { try assertDirectory(coordinated, create: create); return try body(coordinated) }
            return try body(externalRoot(coordinated, create: create))
        }
    }
    private func resolvedDirectory(_ id: String) throws -> URL {
        if id == Self.defaultID { return privateDirectory }
        guard let location = state.locations[id] else { throw DownloadLocationError.unknownLocation }
        do {
            let directory: URL
            if let active = scopes[id] { directory = active }
            else {
                directory = try access.resolve(location.bookmark)
                guard access.start(directory) else { throw DownloadLocationError.permissionRequired(location.name) }
                scopes[id] = directory
            }
            return directory
        } catch { throw DownloadLocationError.permissionRequired(location.name) }
    }
    private func externalRoot(_ directory: URL, create: Bool) throws -> URL {
        try assertDirectory(directory, create: false)
        let app = directory.appendingPathComponent("XXComic", isDirectory: true)
        try assertDirectory(app, create: create)
        let downloads = app.appendingPathComponent("downloads", isDirectory: true)
        try assertDirectory(downloads, create: create)
        return downloads
    }
    private func assertDirectory(_ directory: URL, create: Bool) throws {
        guard directory.isFileURL else { throw DownloadLocationError.unsafePath }
        // Each component below the authorized root is checked as it is appended.
        // System ancestors such as /var may themselves be legitimate OS links.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw DownloadLocationError.unsafePath
        }
        if !FileManager.default.fileExists(atPath: directory.path), create { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw DownloadLocationError.unsafePath }
    }
    private func uniqueName(title: String, id: String, in directory: URL) throws -> String {
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        var clean = title.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined()
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: " ._"))
        var short = "", bytes = 0
        for character in clean.prefix(60) { let value = String(character); guard bytes + value.utf8.count <= 120 else { break }; short += value; bytes += value.utf8.count }
        let base = (short.isEmpty ? "unnamed" : short) + "_" + String(id.suffix(12))
        for attempt in 0..<10_000 {
            let name = base + (attempt == 0 ? "" : "_\(attempt)")
            if (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)) == nil { return name }
        }
        throw DownloadLocationError.unsafePath
    }
    private static func component(_ value: String) -> Bool { !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\") }
    private func persist(_ next: State) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        state = next
    }
}
