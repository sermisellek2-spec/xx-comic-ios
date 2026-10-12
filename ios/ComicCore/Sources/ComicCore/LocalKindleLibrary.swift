import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The selected filename extension is a label, never a claim of format support.
public enum LocalKindleFormat: String, Codable, Sendable {
    case mobi, azw, azw3
}

extension LocalLibrary {
    public func importKindle(title: String, source: URL, format: LocalKindleFormat,
                             isReadableImage: (URL) throws -> Bool) throws -> LocalBook {
        try publishPrepared(prepareKindle(title: title, source: source, format: format, isReadableImage: isReadableImage))
    }
    func prepareKindle(title: String, source: URL, format: LocalKindleFormat,
                       isReadableImage: (URL) throws -> Bool) throws -> PreparedLocalImport {
        try prepareOwnedEpub(title: title, kindleFormat: format, isReadableImage: isReadableImage) { staging, owned in
            let original = staging.appendingPathComponent("source.kindle")
            try copyEbook(source, to: original, didCreateFile: owned.recordFile)
            _ = try KindlePublicationAdapter.convert(source: original, to: staging.appendingPathComponent("content.epub"), requireComic: true)
            try owned.recordFile(staging.appendingPathComponent("content.epub"))
        }
    }

    func ownedKindle(_ book: LocalBook) throws -> URL {
        guard book.kindleFormat != nil, book.epub != nil, book.pdf == nil else { throw LocalLibraryError.invalidBook }
        let source = try ownedFile(bookID: book.id, name: "source.kindle")
        guard let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) <= Self.maximumImportBytes else {
            throw LocalLibraryError.invalidBook
        }
        return source
    }

    /// lstat-style attributes distinguish a missing file from a dangling symbolic link.
    func existingOwnedEPUB(_ book: LocalBook) throws -> URL? {
        let content = directory.appendingPathComponent(book.id).appendingPathComponent("content.epub")
        do { _ = try FileManager.default.attributesOfItem(atPath: content.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
        let owned = try ownedFile(bookID: book.id, name: "content.epub")
        guard let size = try owned.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) <= Self.maximumImportBytes else {
            throw LocalLibraryError.invalidBook
        }
        return owned
    }

    /// Recovery is only for absent derived files. Existing corruption is never replaced.
    func ownedEPUB(_ book: LocalBook) throws -> URL {
        try Task.checkCancellation()
        if let content = try existingOwnedEPUB(book) { return content }
        let original = try ownedKindle(book), manager = FileManager.default
        let folder = original.deletingLastPathComponent()
        let manifest = try ownedFile(bookID: book.id, name: "book.json")
        // Keep the original inode alive while checking its identity after conversion.
        let input = try FileHandle(forReadingFrom: original)
        defer { try? input.close() }
        func identity(_ url: URL) throws -> [NSNumber] {
            let attributes = try manager.attributesOfItem(atPath: url.path)
            guard let device = attributes[.systemNumber] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { throw LocalLibraryError.invalidBook }
            return [device, inode]
        }
        let folderIdentity = try identity(folder), sourceIdentity = try identity(original), manifestIdentity = try identity(manifest)
        // Pin the directory before validation; a later rename/symlink cannot redirect linkat.
        let folderFD = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folderFD >= 0 else {
            let failure = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        defer { close(folderFD) }
        var opened = stat()
        guard fstat(folderFD, &opened) == 0 else {
            let failure = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        guard [NSNumber(value: opened.st_dev), NSNumber(value: opened.st_ino)] == folderIdentity else { throw LocalLibraryError.invalidBook }
        func validateOwner() throws {
            try Task.checkCancellation()
            _ = try ownedKindle(book)
            guard try identity(folder) == folderIdentity, try identity(original) == sourceIdentity,
                  try identity(manifest) == manifestIdentity, try self.book(id: book.id) == book else { throw LocalLibraryError.invalidBook }
        }
        let scratch = directory.appendingPathComponent(".restore-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: scratch) }
        var derived = scratch.appendingPathComponent("content.epub")
        // Recreate the old derived bytes without changing its stable publication metadata.
        // The reading route still rejects text; this only preserves the owned original.
        var publication = try KindlePublicationAdapter.convert(source: original, to: derived, requireComic: false)
        if publication != book.epub, book.epub?.isPurePictureEpub == true {
            // New short comics use image pages; try that shape in a separate,
            // owned file. Both variants must exactly match saved metadata, and
            // nothing is published or overwritten before identity validation.
            derived = scratch.appendingPathComponent("comic.epub")
            publication = try KindlePublicationAdapter.convert(source: original, to: derived)
        }
        guard publication == book.epub else { throw LocalLibraryError.invalidBook }
        try validateOwner()
        try beforeKindlePublish()
        try Task.checkCancellation()
        // This relative name has no parent components and is atomically non-overwriting.
        if linkat(AT_FDCWD, derived.path, folderFD, "content.epub", 0) != 0 {
            let failure = errno
            guard failure == EEXIST else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure)) }
            // Each worker converts independently. Only a matching owned winner is reusable.
            try validateOwner()
            guard let winner = try existingOwnedEPUB(book), try EpubParser.parse(archive: winner) == book.epub else {
                throw LocalLibraryError.invalidBook
            }
            try Task.checkCancellation()
            return winner
        }
        // A moved directory may still accept the link. Roll back only our successful link,
        // using the pinned directory, never the now-untrusted original path or an EEXIST winner.
        var keepPublication = false
        defer { if !keepPublication { _ = unlinkat(folderFD, "content.epub", 0) } }
        try validateOwner()
        let content = try ownedFile(bookID: book.id, name: "content.epub")
        keepPublication = true
        return content
    }
}
