import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
@_silgen_name("renameat2")
private func renameat2(_ oldFD: Int32, _ old: UnsafePointer<CChar>, _ newFD: Int32,
                       _ new: UnsafePointer<CChar>, _ flags: UInt32) -> Int32
#endif

/// The caller must publish or discard a successful preparation. Copies share one lifetime.
public struct PreparedLocalImport: Sendable {
    public let book: LocalBook
    public var staging: URL { storage.staging }
    fileprivate let storage: LocalImportDirectory

    func reassigningTargetID(_ targetID: String, allowExisting: Bool = false) throws -> PreparedLocalImport {
        guard targetID != book.id else { return self }
        guard UUID(uuidString: targetID) != nil else { throw LocalLibraryError.invalidBook }
        if !allowExisting {
            guard !FileManager.default.fileExists(atPath: storage.root.appendingPathComponent(targetID).path) else {
                return self
            }
        }
        return try storage.reassign(targetID: targetID, book: book)
    }
}

extension LocalLibrary {
    func prepareLocalImport(targetID: String? = nil, _ build: (String, URL, LocalImportDirectory) throws -> LocalBook) throws -> PreparedLocalImport {
        try Task.checkCancellation()
        let storage = try LocalImportDirectory(root: directory, owner: importOwner, targetID: targetID)
        do {
            let book = try build(storage.id, storage.staging, storage)
            try storage.validateLocation()
            guard book.id == storage.id else { throw LocalLibraryError.invalidBook }
            try Task.checkCancellation()
            let manifest = try JSONEncoder().encode(book)
            storage.manifestBytes = manifest.count
            try storage.write(manifest, name: "book.json")
            try storage.validate(book)
            try Task.checkCancellation()
            return PreparedLocalImport(book: book, storage: storage)
        } catch {
            try storage.discard()
            throw error
        }
    }

    func publishPrepared(_ prepared: PreparedLocalImport) throws -> LocalBook {
        let storage = prepared.storage
        guard storage.owner == importOwner else { throw LocalLibraryError.invalidBook }
        storage.lock.lock()
        defer { storage.lock.unlock() }
        guard !storage.finished else { throw LocalLibraryError.invalidBook }
        do {
            try storage.validate(prepared.book)
            try beforeImportPublish()
            try storage.validate(prepared.book)
            try Task.checkCancellation()
            // A single same-volume rename makes the complete volume visible, without overwriting.
            #if canImport(Darwin)
            let result = renameatx_np(storage.rootFD, storage.name, storage.rootFD, storage.id, UInt32(RENAME_EXCL))
            #else
            let result = renameat2(storage.rootFD, storage.name, storage.rootFD, storage.id, 1) // RENAME_NOREPLACE
            #endif
            guard result == 0 else { throw importSystemError() }
            // Never clean an unknown object if an external actor renamed the source during the syscall.
            try storage.validateLocation(name: storage.id)
            storage.finished = true
            return prepared.book
        } catch {
            try storage.discard()
            throw error
        }
    }

    func discardPrepared(_ prepared: PreparedLocalImport) throws {
        let storage = prepared.storage
        guard storage.owner == importOwner else { throw LocalLibraryError.invalidBook }
        storage.lock.lock()
        defer { storage.lock.unlock() }
        try storage.discard()
    }
}

private func importSystemError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }

/// Pins both directories for relative publication/cleanup; the lock protects only terminal use.
final class LocalImportDirectory: @unchecked Sendable {
    var id: String
    let token: String
    let owner: UUID
    let root: URL
    let rootFD: Int32
    let stagingFD: Int32
    let lock = NSLock()
    var finished = false
    var manifestBytes = 0
    private var ownedFiles: [String: [UInt64]] = [:]
    var name: String { ".import-" + token }
    var staging: URL { root.appendingPathComponent(name, isDirectory: true) }

    init(root: URL, owner: UUID, targetID: String? = nil) throws {
        let assigned = targetID ?? UUID().uuidString
        guard UUID(uuidString: assigned) != nil else { throw LocalLibraryError.invalidBook }
        self.id = assigned
        self.token = assigned
        self.root = root
        self.owner = owner
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw importSystemError() }
        self.rootFD = rootFD
        let name = ".import-" + token
        guard mkdirat(rootFD, name, 0o700) == 0 else {
            let error = importSystemError(); close(rootFD); throw error
        }
        let stagingFD = openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stagingFD >= 0 else {
            let error = importSystemError()
            // Only an empty directory can be removed here, never a replacement's contents.
            _ = unlinkat(rootFD, name, AT_REMOVEDIR)
            close(rootFD)
            throw error
        }
        self.stagingFD = stagingFD
    }

    deinit { close(stagingFD); close(rootFD) }

    private func matches(_ fd: Int32, parent: Int32, name: String) throws -> Bool {
        var pinned = stat(), current = stat()
        guard fstat(fd, &pinned) == 0 else { throw importSystemError() }
        guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0 else { throw importSystemError() }
        return current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
            && current.st_dev == pinned.st_dev && current.st_ino == pinned.st_ino
    }

    func validateLocation(name: String? = nil) throws {
        guard try matches(rootFD, parent: AT_FDCWD, name: root.path),
              try matches(stagingFD, parent: rootFD, name: name ?? self.name) else { throw LocalLibraryError.invalidBook }
    }

    func validate(_ book: LocalBook) throws {
        try validateLocation()
        try validateFiles()
        guard book.id == id, !book.pages.isEmpty else { throw LocalLibraryError.invalidBook }
        try book.validateMetadata()
        let manifestFD = openat(stagingFD, "book.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard manifestFD >= 0 else { throw importSystemError() }
        let manifest = FileHandle(fileDescriptor: manifestFD, closeOnDealloc: true)
        var manifestInfo = stat()
        guard fstat(manifestFD, &manifestInfo) == 0 else { throw importSystemError() }
        guard manifestInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              manifestInfo.st_size == manifestBytes else { throw LocalLibraryError.invalidBook }
        let data = try manifest.read(upToCount: manifestBytes + 1) ?? Data()
        guard data.count == manifestBytes else { throw LocalLibraryError.invalidBook }
        guard try JSONDecoder().decode(LocalBook.self, from: data) == book else { throw LocalLibraryError.invalidBook }
        var names = book.epub != nil ? ["content.epub"] : book.pdf != nil ? ["content.pdf"] : book.pages
        if book.kindleFormat != nil { names.append("source.kindle") }
        if book.importFormat == .zip || book.importFormat == .cbz { names.append("source.archive") }
        if let cover = book.coverName { names.append(cover) }
        names.append("book.json")
        for name in names {
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { throw LocalLibraryError.invalidBook }
            var attributes = stat()
            guard fstatat(stagingFD, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else { throw importSystemError() }
            guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw LocalLibraryError.invalidBook }
        }
        try validateLocation()
    }

    private func identity(_ name: String) throws -> [UInt64]? {
        var info = stat()
        guard fstatat(stagingFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw importSystemError()
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw LocalLibraryError.invalidBook }
        return [UInt64(info.st_dev), UInt64(info.st_ino)]
    }

    /// Called immediately after a known writer creates a file, before any caller callback.
    func recordFile(_ url: URL) throws {
        guard url.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL else { throw LocalLibraryError.invalidBook }
        let name = url.lastPathComponent, current = try identity(name)
        if let current, let previous = ownedFiles[name], previous != current { throw LocalLibraryError.invalidBook }
        ownedFiles[name] = current
    }

    func removeFile(_ url: URL) throws {
        guard url.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL else { throw LocalLibraryError.invalidBook }
        let name = url.lastPathComponent
        if let current = try identity(name) {
            guard ownedFiles[name] == current else { throw LocalLibraryError.invalidBook }
            guard unlinkat(stagingFD, name, 0) == 0 else { throw importSystemError() }
        }
        ownedFiles[name] = nil
    }

    /// Staging is invisible: exclusive creation avoids atomic-write replacement of foreign files.
    func write(_ data: Data, name: String) throws {
        try validateLocation()
        let fd = openat(stagingFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw importSystemError() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try recordFile(staging.appendingPathComponent(name))
        try handle.write(contentsOf: data)
    }

    /// Check the entire set before deleting anything; a matching name alone is not ownership.
    private func validateFiles() throws {
        let descriptor = dup(stagingFD)
        guard descriptor >= 0 else { throw importSystemError() }
        guard let entries = fdopendir(descriptor) else {
            let error = importSystemError(); close(descriptor); throw error
        }
        defer { closedir(entries) }
        rewinddir(entries)
        while true {
            errno = 0
            guard let entry = readdir(entries) else {
                if errno != 0 { throw importSystemError() }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard let owned = ownedFiles[name], try identity(name) == owned else { throw LocalLibraryError.invalidBook }
        }
    }

    func reassign(targetID: String, book: LocalBook) throws -> PreparedLocalImport {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { throw LocalLibraryError.invalidBook }
        try validateLocation()
        let newChapters: [LocalBookChapter]? = book.chapters?.enumerated().map { index, ch in
            let expectedOldPrefix = book.id + "_ch_"
            let newChapterId = ch.id.hasPrefix(expectedOldPrefix) ? "\(targetID)_ch_\(index)" : (ch.id == book.id ? targetID : ch.id)
            return LocalBookChapter(id: newChapterId, title: ch.title, pages: ch.pages)
        }
        let updatedBook = LocalBook(id: targetID, title: book.title, createdAt: book.createdAt, pages: book.pages,
                                    chapters: newChapters, epub: book.epub, pdf: book.pdf, coverName: book.coverName,
                                    kindleFormat: book.kindleFormat, importFormat: book.importFormat, fingerprint: book.fingerprint)
        try updatedBook.validateMetadata()
        try removeFile(staging.appendingPathComponent("book.json"))
        self.id = targetID
        let manifest = try JSONEncoder().encode(updatedBook)
        self.manifestBytes = manifest.count
        try write(manifest, name: "book.json")
        try validate(updatedBook)
        return PreparedLocalImport(book: updatedBook, storage: self)
    }

    func discard() throws {
        if finished { return }
        try validateLocation()
        try validateFiles()
        for name in Array(ownedFiles.keys) { try removeFile(staging.appendingPathComponent(name)) }
        try validateLocation()
        guard unlinkat(rootFD, name, AT_REMOVEDIR) == 0 else { throw importSystemError() }
        finished = true
    }
}
