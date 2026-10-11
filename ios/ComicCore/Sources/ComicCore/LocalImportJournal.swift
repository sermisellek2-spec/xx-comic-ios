import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A process-independent record of the exact objects created by one import.
/// The journal stays inside the pinned directory across its publication rename.
/// File names alone never authorize recovery, and a live importer holds flock.
final class LocalImportJournal {
    static let name = ".xxcomic-import.jsonl"
    private static let maximumBytes = 16 * 1024 * 1024

    struct Identity: Codable, Equatable {
        let device: UInt64
        let inode: UInt64
        init(_ info: stat) { device = UInt64(info.st_dev); inode = UInt64(info.st_ino) }
    }
    private struct Header: Codable {
        let version: Int
        let token: String
        let root: Identity
        let folder: Identity
        let journal: Identity
    }
    private struct Event: Codable {
        let kind: String
        var name: String? = nil
        var identity: Identity? = nil
        var targetID: String? = nil
        var pendingCatalog: Bool? = nil
    }

    private let folderFD: Int32
    private let handle: FileHandle
    private let header: Header
    private var removed = false

    init(rootFD: Int32, folderFD: Int32, token: String) throws {
        self.folderFD = folderFD
        let fd = openat(folderFD, Self.name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Self.systemError() }
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw Self.systemError() }
        header = Header(version: 1, token: token, root: try Self.identity(rootFD, directory: true),
                        folder: try Self.identity(folderFD, directory: true), journal: try Self.identity(fd))
        try append(header)
        try handle.synchronize()
    }

    private static func systemError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }
    private static func identity(_ fd: Int32, directory: Bool = false) throws -> Identity {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw systemError() }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(directory ? S_IFDIR : S_IFREG) else { throw LocalLibraryError.invalidBook }
        return Identity(info)
    }
    private static func identity(parent: Int32, name: String, directory: Bool = false) throws -> Identity? {
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw systemError()
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(directory ? S_IFDIR : S_IFREG) else { throw LocalLibraryError.invalidBook }
        return Identity(info)
    }
    func validate() throws {
        guard !removed, try Self.identity(parent: folderFD, name: Self.name) == header.journal else { throw LocalLibraryError.invalidBook }
    }
    private func append<T: Encodable>(_ event: T) throws {
        let bytes = try JSONEncoder().encode(event) + Data([10])
        guard try handle.offset() <= UInt64(Self.maximumBytes - bytes.count) else { throw LocalLibraryError.folderTooLarge }
        try handle.write(contentsOf: bytes)
    }
    func record(name: String, identity: [UInt64]) throws {
        guard Self.validName(name), name != Self.name, identity.count == 2 else { throw LocalLibraryError.invalidBook }
        try validate()
        var info = stat()
        guard fstatat(folderFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw Self.systemError() }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              [UInt64(info.st_dev), UInt64(info.st_ino)] == identity else { throw LocalLibraryError.invalidBook }
        try append(Event(kind: "file", name: name, identity: Identity(info)))
    }
    func forget(name: String) throws {
        try validate()
        try append(Event(kind: "remove", name: name))
    }
    func willPublish(targetID: String, pendingCatalog: Bool) throws {
        guard UUID(uuidString: targetID) != nil else { throw LocalLibraryError.invalidBook }
        try validate()
        try append(Event(kind: "publish", targetID: targetID, pendingCatalog: pendingCatalog))
        try handle.synchronize()
    }
    func willDelete(targetID: String) throws {
        guard UUID(uuidString: targetID) != nil else { throw LocalLibraryError.invalidBook }
        try validate()
        try append(Event(kind: "delete", targetID: targetID))
        try handle.synchronize()
    }
    func remove() throws {
        if removed { return }
        try validate()
        guard unlinkat(folderFD, Self.name, 0) == 0 else { throw Self.systemError() }
        removed = true
    }

    private static func names(in folderFD: Int32) throws -> [String] {
        let copied = dup(folderFD)
        guard copied >= 0 else { throw systemError() }
        guard let directory = fdopendir(copied) else { let error = systemError(); close(copied); throw error }
        defer { closedir(directory) }
        rewinddir(directory)
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else { if errno != 0 { throw systemError() }; break }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) { String(cString: $0) }
            }
            if name != ".", name != ".." { names.append(name) }
            guard names.count <= 50_005 else { throw LocalLibraryError.folderTooLarge }
        }
        return names
    }

    /// Returns false for an unknown directory, replaced journal, or active import.
    /// A recognized transaction with unknown/replaced contents is retained and reported.
    static func recover(root: URL, folder: URL, catalogVolumeIDs: Set<String>) throws -> Bool {
        guard folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return false }
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw systemError() }
        defer { close(rootFD) }
        let folderName = folder.lastPathComponent
        let folderFD = openat(rootFD, folderName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folderFD >= 0 else { return false }
        defer { close(folderFD) }
        let journalFD = openat(folderFD, name, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard journalFD >= 0 else { return false }
        let file = FileHandle(fileDescriptor: journalFD, closeOnDealloc: true)
        defer { try? file.close() } // Keep the transaction lock through the final unlink.
        guard flock(journalFD, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { return false }
            throw systemError()
        }
        var journalInfo = stat()
        guard fstat(journalFD, &journalInfo) == 0, journalInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              journalInfo.st_size > 0, journalInfo.st_size <= maximumBytes else { return false }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        // An incomplete final event can only remove authority, never add a file to cleanup.
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        guard let first = lines.first, let header = try? JSONDecoder().decode(Header.self, from: Data(first)),
              header.version == 1, UUID(uuidString: header.token) != nil,
              header.root == (try identity(rootFD, directory: true)),
              header.folder == (try identity(folderFD, directory: true)),
              header.journal == Identity(journalInfo),
              try identity(parent: rootFD, name: folderName, directory: true) == header.folder else { return false }
        var owned: [String: Identity] = [:]
        var publication: Event?
        let completeLines = data.last == 10 ? lines.dropFirst() : lines.dropFirst().dropLast()
        for line in completeLines where !line.isEmpty {
            guard let event = try? JSONDecoder().decode(Event.self, from: Data(line)) else { throw LocalLibraryError.invalidBook }
            switch event.kind {
            case "file":
                guard let name = event.name, validName(name), name != Self.name, let object = event.identity else { throw LocalLibraryError.invalidBook }
                if let previous = owned[name], previous != object { throw LocalLibraryError.invalidBook }
                owned[name] = object
            case "remove":
                guard let name = event.name, validName(name), name != Self.name else { throw LocalLibraryError.invalidBook }
                owned[name] = nil
            case "publish":
                guard let target = event.targetID, UUID(uuidString: target) != nil, event.pendingCatalog != nil else { throw LocalLibraryError.invalidBook }
                publication = event
            case "delete":
                guard let target = event.targetID, UUID(uuidString: target) != nil else { throw LocalLibraryError.invalidBook }
                publication = event
            default: throw LocalLibraryError.invalidBook
            }
        }
        let staged = folderName == ".import-" + header.token
        if folderName == header.token, publication == nil {
            // A crash while writing a deletion journal precedes any data deletion.
            guard try identity(parent: folderFD, name: name) == header.journal else { throw LocalLibraryError.invalidBook }
            guard unlinkat(folderFD, name, 0) == 0 else { throw systemError() }
            return true
        }
        guard staged || folderName == publication?.targetID else { return false }
        if !staged, let publication, publication.kind == "publish",
           publication.pendingCatalog == false || catalogVolumeIDs.contains(folderName) {
            // A committed or legacy volume remains readable. Only the exact journal is removed.
            guard try identity(parent: folderFD, name: name) == header.journal else { throw LocalLibraryError.invalidBook }
            guard unlinkat(folderFD, name, 0) == 0 else { throw systemError() }
            return true
        }
        let contents = try names(in: folderFD)
        for entry in contents where entry != name {
            guard let object = owned[entry], try identity(parent: folderFD, name: entry) == object else { throw LocalLibraryError.invalidBook }
        }
        // Check all entries before deleting any; book.json is last for partial recovery.
        let files = contents.filter { $0 != name }.sorted { lhs, rhs in
            if lhs == "book.json" { return false }; if rhs == "book.json" { return true }; return lhs < rhs
        }
        for entry in files {
            guard try identity(parent: rootFD, name: folderName, directory: true) == header.folder,
                  try identity(parent: folderFD, name: entry) == owned[entry] else { throw LocalLibraryError.invalidBook }
            guard unlinkat(folderFD, entry, 0) == 0 else { throw systemError() }
        }
        guard try identity(parent: folderFD, name: name) == header.journal else { throw LocalLibraryError.invalidBook }
        guard unlinkat(folderFD, name, 0) == 0 else { throw systemError() }
        // AT_REMOVEDIR preserves any new unknown entry; recovery never recurses.
        guard unlinkat(rootFD, folderName, AT_REMOVEDIR) == 0 else { throw systemError() }
        return true
    }
}
