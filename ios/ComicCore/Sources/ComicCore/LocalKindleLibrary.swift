import Foundation

/// The selected filename extension is a label, never a claim of format support.
public enum LocalKindleFormat: String, Codable, Sendable {
    case mobi, azw, azw3
}

extension LocalLibrary {
    public func importKindle(title: String, source: URL, format: LocalKindleFormat,
                             isReadableImage: (URL) throws -> Bool) throws -> LocalBook {
        try importOwnedEpub(title: title, kindleFormat: format, isReadableImage: isReadableImage) { staging in
            let original = staging.appendingPathComponent("source.kindle")
            try copyEbook(source, to: original)
            _ = try KindlePublicationAdapter.convert(source: original, to: staging.appendingPathComponent("content.epub"))
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
        func validateOwner() throws {
            try Task.checkCancellation()
            _ = try ownedKindle(book)
            guard try identity(folder) == folderIdentity, try identity(original) == sourceIdentity,
                  try identity(manifest) == manifestIdentity, try self.book(id: book.id) == book else { throw LocalLibraryError.invalidBook }
        }
        let scratch = directory.appendingPathComponent(".restore-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: scratch) }
        let derived = scratch.appendingPathComponent("content.epub")
        let publication = try KindlePublicationAdapter.convert(source: original, to: derived)
        guard publication == book.epub else { throw LocalLibraryError.invalidBook }
        try validateOwner()
        let destination = folder.appendingPathComponent("content.epub")
        try Task.checkCancellation()
        // A same-volume hard link publishes atomically without replacing a concurrent winner.
        // Removing this request's scratch below completes the move.
        do { try manager.linkItem(at: derived, to: destination) }
        catch let error as NSError where (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError)
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(POSIXErrorCode.EEXIST.rawValue)) {
            // Each worker converts independently. Only a matching owned winner is reusable.
            try validateOwner()
            guard let winner = try existingOwnedEPUB(book), try EpubParser.parse(archive: winner) == book.epub else {
                throw LocalLibraryError.invalidBook
            }
            try Task.checkCancellation()
            return winner
        }
        return try ownedFile(bookID: book.id, name: "content.epub")
    }
}
