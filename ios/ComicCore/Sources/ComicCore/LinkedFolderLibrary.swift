import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct LinkedFolderEntry: Codable, Equatable, Sendable {
    public let pageID: String
    public let relativePath: String
    public let fileIdentity: String?
    public let byteCount: Int64
    public let modifiedAt: TimeInterval?
}

/// The bookmark is private library data, never an ambient file URL permission.
public struct LinkedFolderReference: Codable, Equatable, Sendable {
    public let recordID: String
    public let bookmarkData: Data
    public let manifestFingerprint: String
    public let entries: [LinkedFolderEntry]

    func validate(pages: [String]) throws {
        guard UUID(uuidString: recordID) != nil, !bookmarkData.isEmpty, bookmarkData.count <= 1024 * 1024,
              !entries.isEmpty, entries.count <= 50_000, pages == entries.map(\.pageID),
              Set(pages).count == pages.count, Set(entries.map(\.relativePath)).count == entries.count,
              manifestFingerprint.count == 64,
              manifestFingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw LocalLibraryError.invalidBook
        }
        for entry in entries {
            guard UUID(uuidString: entry.pageID) != nil, entry.byteCount > 0,
                  entry.byteCount <= Int64(LocalLibrary.maximumImageBytes),
                  entry.modifiedAt?.isFinite ?? true else { throw LocalLibraryError.invalidBook }
            _ = try LinkedFolderAccess.components(entry.relativePath)
        }
    }
}

enum LinkedFolderPageURL {
    static func make(bookID: String, pageID: String) throws -> URL {
        guard UUID(uuidString: bookID) != nil, UUID(uuidString: pageID) != nil,
              let url = URL(string: "xxcomic-folder://page/\(bookID)/\(pageID)") else { throw LocalLibraryError.invalidBook }
        return url
    }
    static func parse(_ url: URL) throws -> (bookID: String, pageID: String) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "xxcomic-folder", parts.percentEncodedHost == "page",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.query == nil, parts.fragment == nil,
              url.absoluteString.hasPrefix("xxcomic-folder://page/"), !parts.percentEncodedPath.contains("%") else {
            throw LocalLibraryError.invalidBook
        }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 3, path[0].isEmpty,
              UUID(uuidString: String(path[1])) != nil, UUID(uuidString: String(path[2])) != nil else {
            throw LocalLibraryError.invalidBook
        }
        return (String(path[1]), String(path[2]))
    }
}

enum LinkedFolderAccess {
    static func components(_ relative: String) throws -> [String] {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relative.contains("\\"), !relative.contains("\0"), relative.utf8.count <= 4096,
              !parts.isEmpty, parts.count <= 6,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw LocalLibraryError.invalidBook }
        return parts
    }

    static func withBookmark<T>(_ data: Data, body: (URL) throws -> T) throws -> T {
        try Task.checkCancellation()
        let root = try BatchImportWorker.resolveBookmark(data)
        guard root.isFileURL else { throw LocalLibraryError.invalidBook }
        #if canImport(Darwin)
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        #endif
        return try FileAccessCoordinator.system.coordinate(root, access: .read, body: body)
    }

    /// Pin the authorized root and open each child relative to it. Parent links,
    /// final links and special files never become readable through an index.
    static func read(root: URL, relative: String) throws -> Data {
        let parts = try components(relative)
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var descriptors = [rootFD]
        defer { for fd in descriptors.reversed() { close(fd) } }
        for part in parts.dropLast() {
            let child = openat(descriptors.last!, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw LocalLibraryError.invalidBook }
            descriptors.append(child)
        }
        let fileFD = openat(descriptors.last!, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fileFD >= 0 else { throw LocalLibraryError.invalidBook }
        let handle = FileHandle(fileDescriptor: fileFD, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fileFD, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw LocalLibraryError.invalidBook }
        guard info.st_size > 0, info.st_size <= LocalLibrary.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
        try Task.checkCancellation()
        let bytes = try handle.read(upToCount: LocalLibrary.maximumImageBytes + 1) ?? Data()
        try Task.checkCancellation()
        guard !bytes.isEmpty, bytes.count <= LocalLibrary.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
        return bytes
    }
}

extension LocalLibrary {
    /// Covers and regular image pages use the actual library instance. This also
    /// works in isolated UI sessions and never assumes an Application Support path.
    public func ownedImageData(at url: URL) throws -> Data {
        if url.scheme == "xxcomic-folder" {
            let identity = try LinkedFolderPageURL.parse(url)
            let book = try book(id: identity.bookID)
            guard let folder = book.linkedFolder, let entry = folder.entries.first(where: { $0.pageID == identity.pageID }) else {
                throw LocalLibraryError.invalidBook
            }
            return try LinkedFolderAccess.withBookmark(folder.bookmarkData) { root in
                let file = root.appendingPathComponent(entry.relativePath)
                return try FileAccessCoordinator.system.coordinate(file, access: .read) { coordinated in
                    guard coordinated.standardizedFileURL == file.standardizedFileURL else { throw LocalLibraryError.invalidBook }
                    return try LinkedFolderAccess.read(root: root, relative: entry.relativePath)
                }
            }
        }
        guard url.isFileURL, url.query == nil, url.fragment == nil else { throw LocalLibraryError.invalidBook }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let parts = resolved.pathComponents
        guard parts.count == root.pathComponents.count + 2, parts.starts(with: root.pathComponents) else {
            throw LocalLibraryError.invalidBook
        }
        let bookID = parts[parts.count - 2], name = parts.last!
        let current = try book(id: bookID)
        guard current.coverName == name || (current.epub == nil && current.pdf == nil && current.linkedFolder == nil && current.pages.contains(name)) else {
            throw LocalLibraryError.invalidBook
        }
        let file = try ownedFile(bookID: bookID, name: name)
        let attributes = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard attributes.isSymbolicLink != true, file.resolvingSymlinksInPath().standardizedFileURL == resolved else { throw LocalLibraryError.invalidBook }
        return try FileAccessCoordinator.system.coordinate(file, access: .read) {
            try FileAccessCoordinator.readRegularFile($0, maximumBytes: Int64(Self.maximumImageBytes))
        }
    }

    func prepareLinkedFolder(title: String, folder: URL, bookmark: Data, recordID: String,
                             previous: LocalBook?, isReadableImage: (URL) throws -> Bool) throws -> PreparedLocalImport {
        try FileAccessCoordinator.system.coordinate(folder, access: .read) { coordinated in
            let index = try LocalFolderIndex(folder: coordinated, metadataOnly: true, isReadableImage: isReadableImage)
            let oldEntries = previous?.linkedFolder?.entries ?? []
            let byPath = Dictionary(uniqueKeysWithValues: oldEntries.map { ($0.relativePath, $0) })
            let byIdentity = Dictionary(grouping: oldEntries.filter { $0.fileIdentity != nil }, by: { $0.fileIdentity! })
            var raw: [(path: String, identity: String?, size: Int64, modified: TimeInterval?)] = []
            for (path, file) in zip(index.relativePaths, index.files) {
                try Task.checkCancellation()
                let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
                let identity: String?
                if let inode = attrs[.systemFileNumber] as? NSNumber, let device = attrs[.systemNumber] as? NSNumber {
                    identity = "\(device):\(inode)"
                } else { identity = nil }
                raw.append((path, identity, (attrs[.size] as? NSNumber)?.int64Value ?? 0, (attrs[.modificationDate] as? Date)?.timeIntervalSince1970))
            }
            let newIdentityCounts = Dictionary(grouping: raw.filter { $0.identity != nil }, by: { $0.identity! }).mapValues(\.count)
            var used = Set<String>()
            let entries = raw.map { item -> LinkedFolderEntry in
                let exact = byPath[item.path]
                let renamed = item.identity.flatMap { key -> LinkedFolderEntry? in
                    let candidates = byIdentity[key] ?? []
                    return candidates.count == 1 && newIdentityCounts[key] == 1 ? candidates.first : nil
                }
                let candidate = exact?.pageID ?? renamed?.pageID
                let pageID = candidate.flatMap { used.insert($0).inserted ? $0 : nil } ?? UUID().uuidString
                used.insert(pageID)
                return LinkedFolderEntry(pageID: pageID, relativePath: item.path, fileIdentity: item.identity,
                                         byteCount: item.size, modifiedAt: item.modified)
            }
            // Fingerprint the listing metadata only, not every image's bytes.
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            struct ManifestEntry: Encodable { let path: String; let identity: String?; let size: Int64; let modified: TimeInterval? }
            let manifest = raw.map { ManifestEntry(path: $0.path, identity: $0.identity, size: $0.size, modified: $0.modified) }
            let manifestFingerprint = try ContentFingerprint.metadata(encoder.encode(manifest))
            let fingerprint = try previous?.linkedFolder != nil ? previous!.fingerprint! : Self.linkedFolderIdentity(folder)
            return try prepareLocalImport { id, staging, owned in
                let names = entries.map(\.pageID)
                let oldChapters = Dictionary(grouping: previous?.chapters ?? [], by: \.title)
                var usedChapters = Set<String>()
                let chapters = index.groups.map { group in
                    let existing = oldChapters[group.title]
                    let groupPages = group.indices.map { names[$0] }
                    let pageSet = Set(groupPages)
                    let overlaps = (previous?.chapters ?? []).filter { !usedChapters.contains($0.id) }.map {
                        (chapter: $0, count: $0.pages.filter(pageSet.contains).count)
                    }.filter { $0.count > 0 }.sorted { $0.count > $1.count }
                    let retained: String?
                    if let best = overlaps.first, overlaps.count == 1 || best.count > overlaps[1].count { retained = best.chapter.id }
                    else if existing?.count == 1, !usedChapters.contains(existing![0].id) { retained = existing![0].id }
                    else { retained = nil }
                    let chapterID = retained ?? id + "_folder_" + UUID().uuidString
                    usedChapters.insert(chapterID)
                    return LocalBookChapter(id: chapterID, title: group.title, pages: groupPages)
                }
                var coverName: String?
                if let first = index.files.first, try isReadableImage(first) {
                    // One cover is owned locally; the remaining pages stay in Files.
                    let bytes = try LinkedFolderAccess.read(root: coordinated, relative: index.relativePaths[0])
                    try owned.write(bytes, name: "cover.bin"); coverName = "cover.bin"
                }
                let reference = LinkedFolderReference(recordID: recordID, bookmarkData: bookmark,
                                                       manifestFingerprint: manifestFingerprint, entries: entries)
                return LocalBook(id: id, title: previous?.title ?? (SearchRules.trim(title).isEmpty ? "本地漫画" : SearchRules.trim(title)),
                                 createdAt: previous?.createdAt ?? Date().timeIntervalSince1970,
                                 pages: names, chapters: chapters, coverName: coverName, importFormat: .folder,
                                 fingerprint: fingerprint, linkedFolder: reference)
            }
        }
    }

    static func linkedFolderIdentity(_ folder: URL) throws -> String {
        try ContentFingerprint.metadata(Data(("linked-folder-v1\n" + folder.standardizedFileURL.path).utf8))
    }
}
