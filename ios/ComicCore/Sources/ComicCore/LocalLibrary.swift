import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum LocalImportFormat: String, Codable, Sendable {
    case images, folder, zip, cbz, epub, pdf, mobi, azw, azw3
}

public struct LocalBook: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: TimeInterval
    public let pages: [String]
    public let chapters: [LocalBookChapter]?
    public let epub: EpubPublication?
    public let pdf: PdfPublication?
    public let coverName: String?
    public let kindleFormat: LocalKindleFormat?
    public let importFormat: LocalImportFormat?
    public let fingerprint: String?
    public let linkedFolder: LinkedFolderReference?

    public init(id: String, title: String, createdAt: TimeInterval, pages: [String], chapters: [LocalBookChapter]? = nil, epub: EpubPublication? = nil, pdf: PdfPublication? = nil, coverName: String? = nil, kindleFormat: LocalKindleFormat? = nil, importFormat: LocalImportFormat? = nil, fingerprint: String? = nil, linkedFolder: LinkedFolderReference? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.pages = pages; self.chapters = chapters
        self.epub = epub; self.pdf = pdf; self.coverName = coverName
        self.kindleFormat = kindleFormat
        self.importFormat = importFormat
        self.fingerprint = fingerprint
        self.linkedFolder = linkedFolder
    }
}

public struct LocalBookChapter: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let pages: [String]
}

extension LocalBook {
    func validateMetadata() throws {
        if let linkedFolder {
            guard importFormat == .folder, epub == nil, pdf == nil, kindleFormat == nil,
                  coverName == nil || coverName == "cover.bin" else { throw LocalLibraryError.invalidBook }
            try linkedFolder.validate(pages: pages)
        }
        if let fingerprint {
            guard fingerprint.count == 64,
                  fingerprint.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else {
                throw LocalLibraryError.invalidBook
            }
            guard let format = importFormat, format != .images else { throw LocalLibraryError.invalidBook }
        }
        if let format = importFormat {
            if format == .images {
                guard fingerprint == nil else { throw LocalLibraryError.invalidBook }
            } else {
                guard fingerprint != nil else { throw LocalLibraryError.invalidBook }
            }
            if epub != nil {
                if let kindle = kindleFormat {
                    guard (kindle == .mobi && (format == .mobi || format == .epub)) ||
                          (kindle == .azw && (format == .azw || format == .epub)) ||
                          (kindle == .azw3 && (format == .azw3 || format == .epub)) else { throw LocalLibraryError.invalidBook }
                } else {
                    guard format == .epub else { throw LocalLibraryError.invalidBook }
                }
            } else if pdf != nil {
                guard format == .pdf else { throw LocalLibraryError.invalidBook }
            } else {
                guard format == .images || format == .folder || format == .zip || format == .cbz else {
                    throw LocalLibraryError.invalidBook
                }
            }
        }
    }
}

/// A complete import becomes visible through a single directory rename.
public struct LocalLibrary: Sendable {
    public static let maximumImageBytes = 128 * 1024 * 1024
    static let maximumImportBytes: Int64 = 20 * 1024 * 1024 * 1024
    private static let copyChunkBytes = 256 * 1024
    private let directoryPath: String
    private let readChunk: @Sendable (FileHandle, Int) throws -> Data?
    let importOwner = UUID()
    let beforeImportPublish: @Sendable () throws -> Void
    let beforeKindlePublish: @Sendable () throws -> Void
    public var directory: URL { URL(fileURLWithPath: directoryPath, isDirectory: true) }
    public let catalogStore: LocalCatalogStore
    public init(directory: URL) throws {
        try self.init(directory: directory, readChunk: { try $0.read(upToCount: $1) })
    }
    init(directory: URL, readChunk: @escaping @Sendable (FileHandle, Int) throws -> Data?,
         beforeKindlePublish: @escaping @Sendable () throws -> Void = {},
         beforeImportPublish: @escaping @Sendable () throws -> Void = {},
         catalogStore: LocalCatalogStore? = nil) throws {
        directoryPath = directory.path
        self.readChunk = readChunk
        self.beforeKindlePublish = beforeKindlePublish
        self.beforeImportPublish = beforeImportPublish
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.catalogStore = try catalogStore ?? LocalCatalogStore(directory: directory)
    }
    public func books() throws -> [LocalBook] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .map { try book(id: $0.lastPathComponent) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
    }
    public func book(id: String) throws -> LocalBook {
        guard UUID(uuidString: id) != nil else { throw LocalLibraryError.invalidBook }
        let manifest = try ownedFile(bookID: id, name: "book.json")
        let book = try JSONDecoder().decode(LocalBook.self, from: Data(contentsOf: manifest))
        guard book.id == id else { throw LocalLibraryError.invalidBook }
        _ = try pageURLs(for: book)
        return book
    }
    public func pageURLs(for book: LocalBook) throws -> [URL] {
        guard book.epub == nil || book.pdf == nil else { throw LocalLibraryError.invalidBook }
        guard book.kindleFormat == nil || (book.epub != nil && book.pdf == nil) else { throw LocalLibraryError.invalidBook }
        try book.validateMetadata()
        if book.importFormat == .zip || book.importFormat == .cbz {
            _ = try ownedFile(bookID: book.id, name: "source.archive")
        }
        let pageNames = Set(book.pages)
        guard UUID(uuidString: book.id) != nil, !book.pages.isEmpty, pageNames.count == book.pages.count else { throw LocalLibraryError.invalidBook }
        if let chapters = book.chapters {
            let chapterPages = chapters.flatMap(\.pages)
            guard !chapters.isEmpty, Set(chapters.map(\.id)).count == chapters.count,
                  chapters.allSatisfy({ !$0.id.isEmpty && !$0.id.contains("/") && !$0.id.contains("\\") && $0.id != "." && $0.id != ".." && !$0.pages.isEmpty && $0.pages.allSatisfy(pageNames.contains) }),
                  chapterPages.count == book.pages.count, Set(chapterPages).count == chapterPages.count,
                  Set(chapterPages) == pageNames else { throw LocalLibraryError.invalidBook }
        }
        if book.epub != nil {
            try validateEpub(book)
            return try book.pages.indices.map { try EpubPageURL.make(bookID: book.id, index: $0) }
        }
        if book.pdf != nil {
            try validatePdf(book)
            return try book.pages.indices.map { try LocalPageURL.make(bookID: book.id, index: $0, scheme: "xxcomic-pdf") }
        }
        if book.linkedFolder != nil {
            if let cover = book.coverName { _ = try ownedFile(bookID: book.id, name: cover) }
            return try book.pages.map { try LinkedFolderPageURL.make(bookID: book.id, pageID: $0) }
        }
        guard book.coverName == nil else { throw LocalLibraryError.invalidBook }
        return try book.pages.map { name in
            guard name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.isEmpty else { throw LocalLibraryError.invalidBook }
            return directory.appendingPathComponent(book.id, isDirectory: true).appendingPathComponent(name)
        }
    }
    public func summary(for book: LocalBook) throws -> ComicSummary {
        let pages = try pageURLs(for: book)
        let cover = book.epub == nil && book.pdf == nil && book.linkedFolder == nil ? pages.first?.absoluteString ?? ""
            : try book.coverName.map { try ownedFile(bookID: book.id, name: $0).absoluteString } ?? ""
        return ComicSummary(sourceId: "local", comicId: book.id, title: book.title,
                            coverUrl: cover, subtitle: "\(book.pages.count) 页")
    }
    public func summary(for series: LocalSeriesRecord) throws -> ComicSummary {
        if let firstId = series.volumeIDs.first, let firstBook = try? book(id: firstId) {
            let allVolumes = series.volumeIDs.compactMap { try? book(id: $0) }
            let totalPages = allVolumes.reduce(0) { $0 + $1.pages.count }
            let pages = try pageURLs(for: firstBook)
            let cover = firstBook.epub == nil && firstBook.pdf == nil && firstBook.linkedFolder == nil ? pages.first?.absoluteString ?? ""
                : try firstBook.coverName.map { try ownedFile(bookID: firstBook.id, name: $0).absoluteString } ?? ""
            let volumePrefix = series.volumeIDs.count > 1 ? "\(series.volumeIDs.count) 卷 · " : ""
            return ComicSummary(sourceId: "local", comicId: series.id, title: series.displayTitle,
                                coverUrl: cover, subtitle: "\(volumePrefix)\(totalPages) 页")
        }
        return ComicSummary(sourceId: "local", comicId: series.id, title: series.displayTitle, coverUrl: "", subtitle: "0 页")
    }
    public func legacySeries() throws -> [LocalSeriesRecord] {
        try books().map {
            LocalSeriesRecord(id: $0.id, originalTitle: $0.title, userTitle: nil, volumeIDs: [$0.id],
                              createdAt: $0.createdAt, updatedAt: $0.createdAt, status: "ready")
        }
    }
    private func ensureLegacySeeded() async throws {
        let exists = await catalogStore.existsOnDisk()
        if !exists {
            try await catalogStore.seedLegacySeriesIfNeeded(try legacySeries())
        }
    }
    public func series() async throws -> [LocalSeriesRecord] {
        let exists = await catalogStore.existsOnDisk()
        if exists {
            return await catalogStore.listReadySeries()
        }
        return try legacySeries()
    }
    public func series(id: String) async throws -> LocalSeriesRecord? {
        if let found = await catalogStore.getSeries(id: id) {
            return found
        }
        let exists = await catalogStore.existsOnDisk()
        if !exists, let b = try? book(id: id) {
            return LocalSeriesRecord(id: b.id, originalTitle: b.title, userTitle: nil, volumeIDs: [b.id],
                                     createdAt: b.createdAt, updatedAt: b.createdAt, status: "ready")
        }
        return nil
    }
    public func volumes(for series: LocalSeriesRecord) throws -> [LocalBook] {
        try series.volumeIDs.map { try book(id: $0) }
    }
    public func findReadySeries(byFingerprint fingerprint: String) async throws -> (series: LocalSeriesRecord, volume: LocalBook)? {
        let ready = await catalogStore.listReadySeries()
        for s in ready {
            for vId in s.volumeIDs {
                if let b = try? book(id: vId), b.fingerprint == fingerprint {
                    return (s, b)
                }
            }
        }
        let exists = await catalogStore.existsOnDisk()
        if !exists {
            for b in (try? books()) ?? [] where b.fingerprint == fingerprint {
                let s = LocalSeriesRecord(id: b.id, originalTitle: b.title, userTitle: nil, volumeIDs: [b.id],
                                          createdAt: b.createdAt, updatedAt: b.createdAt, status: "ready")
                return (s, b)
            }
        }
        return nil
    }
    public func chapters(for seriesId: String) async throws -> [Chapter] {
        guard let s = try await series(id: seriesId) else {
            if let b = try? book(id: seriesId) {
                return chapters(for: b)
            }
            throw LocalCatalogError.targetNotFound
        }
        var result: [Chapter] = []
        for (volSlot, volId) in s.volumeIDs.enumerated() {
            let b = try book(id: volId)
            let volChapters = chapters(for: b, sectionSlot: volSlot, baseSlot: result.count)
            result.append(contentsOf: volChapters)
        }
        return result
    }

    public func chapters(for book: LocalBook, sectionSlot: Int = 0, baseSlot: Int = 0) -> [Chapter] {
        if let chapters = book.chapters, !chapters.isEmpty {
            return chapters.enumerated().map { index, chapter in
                Chapter(chapterId: chapter.id, title: chapter.title, url: book.id + "/" + chapter.id,
                        sectionSlot: sectionSlot, chapterSlot: baseSlot + index)
            }
        }
        return [Chapter(chapterId: book.id, title: book.title, url: book.id, sectionSlot: sectionSlot, chapterSlot: baseSlot)]
    }

    public func readingTarget(seriesId: String, chapterId: String) async throws -> LocalReadingTarget {
        let allChapters = try await chapters(for: seriesId)
        guard let globalIdx = allChapters.firstIndex(where: { $0.chapterId == chapterId }) else {
            throw LocalCatalogError.targetNotFound
        }
        return try await readingTarget(seriesId: seriesId, chapterIndex: globalIdx, allChapters: allChapters)
    }

    public func readingTarget(seriesId: String, chapterIndex: Int) async throws -> LocalReadingTarget {
        let allChapters = try await chapters(for: seriesId)
        return try await readingTarget(seriesId: seriesId, chapterIndex: chapterIndex, allChapters: allChapters)
    }

    private func readingTarget(seriesId: String, chapterIndex: Int, allChapters: [Chapter]) async throws -> LocalReadingTarget {
        guard allChapters.indices.contains(chapterIndex) else {
            throw LocalCatalogError.targetNotFound
        }
        let chapter = allChapters[chapterIndex]
        let volumeId = String(chapter.url.split(separator: "/").first ?? Substring(chapter.chapterId))
        let book = try self.book(id: volumeId)
        let volChIdx: Int
        if let chapters = book.chapters {
            volChIdx = chapters.firstIndex(where: { $0.id == chapter.chapterId }) ?? 0
        } else {
            volChIdx = 0
        }
        let isText = (book.epub != nil && !book.epub!.isPurePictureEpub)
        let kind: LocalReadingTarget.ReaderKind = isText ? .text : .comic
        return LocalReadingTarget(seriesId: seriesId, volumeId: volumeId, chapter: chapter,
                                  globalChapterIndex: chapterIndex, volumeChapterIndex: volChIdx,
                                  kind: kind, totalChapters: allChapters.count)
    }
    public func publishImport(_ prepared: PreparedLocalImport, targetSeriesId: String? = nil, explicitTitle: String? = nil) async throws -> (series: LocalSeriesRecord, book: LocalBook) {
        defer { try? discardPrepared(prepared) }
        try await ensureLegacySeeded()
        if let fp = prepared.book.fingerprint {
            if let existing = try await findReadySeries(byFingerprint: fp) {
                try discardPrepared(prepared)
                if targetSeriesId == nil || targetSeriesId == existing.series.id {
                    return (existing.series, existing.volume)
                } else {
                    throw LocalCatalogError.alreadyImported
                }
            }
        }
        var workingPrepared = prepared
        var seriesId = targetSeriesId ?? UUID().uuidString
        var userTitle: String? = nil
        if let fp = prepared.book.fingerprint, targetSeriesId == nil {
            if let tombstone = await catalogStore.findTombstone(byFingerprint: fp) {
                userTitle = tombstone.userTitle
                if await catalogStore.getSeries(id: tombstone.seriesId) == nil {
                    seriesId = tombstone.seriesId
                }
                let targetVolDir = directory.appendingPathComponent(tombstone.volumeId)
                if !FileManager.default.fileExists(atPath: targetVolDir.path) {
                    workingPrepared = try prepared.reassigningTargetID(tombstone.volumeId)
                }
            }
        }
        if let targetId = targetSeriesId {
            guard let existingSeries = await catalogStore.getSeries(id: targetId) else {
                try discardPrepared(workingPrepared)
                throw LocalCatalogError.targetNotFound
            }
            guard existingSeries.status == "ready" else {
                try discardPrepared(workingPrepared)
                throw LocalCatalogError.targetNotReady
            }
        }
        let publishedBook = try publishPrepared(workingPrepared, pendingCatalog: true)
        let committedSeries: LocalSeriesRecord
        do {
            if let targetId = targetSeriesId {
                let removingFPs = [publishedBook.fingerprint].compactMap { $0 }
                try await catalogStore.appendVolume(seriesId: targetId, volumeId: publishedBook.id, removingFingerprints: removingFPs)
                guard let updatedSeries = await catalogStore.getSeries(id: targetId) else {
                    throw LocalCatalogError.targetNotFound
                }
                committedSeries = updatedSeries
            } else {
                let title = explicitTitle ?? publishedBook.title
                let series = LocalSeriesRecord(id: seriesId, originalTitle: title, userTitle: userTitle,
                                               volumeIDs: [publishedBook.id], createdAt: publishedBook.createdAt,
                                               updatedAt: Date().timeIntervalSince1970, status: "ready")
                let removingFPs = [publishedBook.fingerprint].compactMap { $0 }
                try await catalogStore.commitNewSeries(series, removingFingerprints: removingFPs)
                committedSeries = series
            }
        } catch {
            try rollbackImportPublication(workingPrepared)
            throw error
        }
        // Catalog commit is already durable: a journal-cleanup error must never roll it back.
        try finishImportPublication(workingPrepared)
        return (committedSeries, publishedBook)
    }
    public func deleteSeries(id: String) async throws {
        try await ensureLegacySeeded()
        guard let series = await catalogStore.getSeries(id: id) else {
            throw LocalCatalogError.targetNotFound
        }
        if series.status == "deleting" {
            for volID in series.volumeIDs {
                _ = try LocalImportJournal.recover(root: directory, folder: directory.appendingPathComponent(volID),
                                                   catalogVolumeIDs: Set(series.volumeIDs))
            }
        }
        var pendingVolumeIDs: [String] = []
        // Validate the whole series before changing visibility or removing any volume.
        for volID in series.volumeIDs {
            let url = directory.appendingPathComponent(volID)
            var info = stat()
            if lstat(url.path, &info) != 0 {
                if errno == ENOENT, series.status == "deleting" { continue }
                throw LocalLibraryError.invalidBook
            }
            try removeOwnedVolumeDirectory(url, expectedID: volID, remove: false)
            pendingVolumeIDs.append(volID)
        }
        var tombstones: [LocalDeletedFingerprintRecord] = []
        let now = Date().timeIntervalSince1970
        for volId in series.volumeIDs {
            if let fp = (try? book(id: volId))?.fingerprint {
                tombstones.append(LocalDeletedFingerprintRecord(
                    fingerprint: fp, seriesId: series.id, volumeId: volId, userTitle: series.userTitle, deletedAt: now
                ))
            }
        }
        try await catalogStore.markSeriesDeleting(seriesId: id, newTombstones: tombstones)
        for volId in pendingVolumeIDs {
            let volURL = directory.appendingPathComponent(volId)
            try deleteOwnedDirectory(volURL, recordDeletion: true)
        }
        try await catalogStore.completeSeriesDeletion(seriesId: id, newTombstones: tombstones)
    }
    public func deleteVolume(seriesId: String, volumeId: String) async throws {
        try await ensureLegacySeeded()
        guard let series = await catalogStore.getSeries(id: seriesId) else {
            throw LocalCatalogError.targetNotFound
        }
        guard series.volumeIDs.contains(volumeId) else {
            throw LocalCatalogError.volumeNotFound
        }
        if series.volumeIDs.count <= 1 {
            try await deleteSeries(id: seriesId)
            return
        }
        let fp = (try? book(id: volumeId))?.fingerprint
        let volURL = directory.appendingPathComponent(volumeId)
        try deleteOwnedDirectory(volURL)
        var tombstones: [LocalDeletedFingerprintRecord] = []
        if let fp {
            tombstones.append(LocalDeletedFingerprintRecord(
                fingerprint: fp, seriesId: seriesId, volumeId: volumeId, userTitle: series.userTitle, deletedAt: Date().timeIntervalSince1970
            ))
        }
        try await catalogStore.removeVolumeFromSeries(seriesId: seriesId, volumeId: volumeId, newTombstones: tombstones)
    }
    public func renameSeries(id: String, newTitle: String) async throws -> LocalSeriesRecord {
        try await ensureLegacySeeded()
        return try await catalogStore.renameSeries(id: id, newTitle: newTitle)
    }
    public func reorderVolumes(seriesId: String, newVolumeIDs: [String]) async throws {
        try await ensureLegacySeeded()
        try await catalogStore.reorderVolumes(seriesId: seriesId, newVolumeIDs: newVolumeIDs)
    }
    func deleteOwnedDirectory(_ url: URL, recordDeletion: Bool = false) throws {
        let name = url.lastPathComponent
        guard UUID(uuidString: name) != nil else { throw LocalLibraryError.invalidBook }
        try removeOwnedVolumeDirectory(url, expectedID: name, recordDeletion: recordDeletion)
    }
    func removeOwnedVolumeDirectory(_ url: URL, expectedID: String, remove: Bool = true, recordDeletion: Bool = false) throws {
        guard UUID(uuidString: expectedID) != nil else { throw LocalLibraryError.invalidBook }
        let name = url.lastPathComponent
        if name != expectedID {
            let marker = ".backup-" + expectedID + "-"
            let suffix = String(name.dropFirst(marker.count))
            guard UUID(uuidString: suffix) != nil, name == marker + suffix else { throw LocalLibraryError.invalidBook }
        }
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw LocalLibraryError.invalidBook
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw LocalLibraryError.invalidBook
        }
        let manifest = url.appendingPathComponent("book.json")
        let book = try JSONDecoder().decode(LocalBook.self, from: FileAccessCoordinator.readRegularFile(manifest, maximumBytes: 32 * 1024 * 1024))
        guard book.id == expectedID else { throw LocalLibraryError.invalidBook }
        try book.validateMetadata()
        var known: Set<String> = ["book.json"]
        if book.linkedFolder == nil, book.epub == nil, book.pdf == nil { known.formUnion(book.pages) }
        if book.epub != nil { known.insert("content.epub") }
        if book.pdf != nil { known.insert("content.pdf") }
        if book.kindleFormat != nil { known.insert("source.kindle") }
        if book.importFormat == .zip || book.importFormat == .cbz { known.insert("source.archive") }
        if let cover = book.coverName { known.insert(cover) }
        guard known.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") }) else { throw LocalLibraryError.invalidBook }
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        // Preflight the complete set. Unknown files/directories and links survive.
        for file in files {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard known.contains(file.lastPathComponent), info.isRegularFile == true, info.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
        }
        let rootFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(rootFD) }
        let folderFD = openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folderFD >= 0 else { throw LocalLibraryError.invalidBook }
        defer { close(folderFD) }
        var pinned = stat(), current = stat()
        guard fstat(folderFD, &pinned) == 0, lstat(url.path, &current) == 0,
              pinned.st_dev == current.st_dev, pinned.st_ino == current.st_ino else { throw LocalLibraryError.invalidBook }
        var fileIdentities: [String: [UInt64]] = [:]
        for file in files {
            var info = stat()
            guard fstatat(folderFD, file.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw LocalLibraryError.invalidBook }
            fileIdentities[file.lastPathComponent] = [UInt64(info.st_dev), UInt64(info.st_ino)]
        }
        if !remove { return }
        var deletionJournal: LocalImportJournal?
        if recordDeletion {
            let journal = try LocalImportJournal(rootFD: rootFD, folderFD: folderFD, token: expectedID)
            do {
                for (file, identity) in fileIdentities { try journal.record(name: file, identity: identity) }
                try journal.willDelete(targetID: expectedID)
            } catch {
                try journal.remove()
                throw error
            }
            deletionJournal = journal
        }
        for file in files.sorted(by: { $0.lastPathComponent == "book.json" ? false : $1.lastPathComponent == "book.json" ? true : $0.lastPathComponent < $1.lastPathComponent }) {
            var info = stat(), location = stat()
            guard fstatat(rootFD, name, &location, AT_SYMLINK_NOFOLLOW) == 0,
                  location.st_dev == pinned.st_dev, location.st_ino == pinned.st_ino,
                  fstatat(folderFD, file.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  fileIdentities[file.lastPathComponent] == [UInt64(info.st_dev), UInt64(info.st_ino)] else { throw LocalLibraryError.invalidBook }
            guard unlinkat(folderFD, file.lastPathComponent, 0) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        try deletionJournal?.remove()
        // Never recursively remove a directory if a new unknown entry appears.
        guard unlinkat(rootFD, name, AT_REMOVEDIR) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    private func isVolumeCompleteAndReadable(at dirURL: URL, expectedID: String) -> Bool {
        let manager = FileManager.default
        var isDir: ObjCBool = false
        guard manager.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let bookJSONURL = dirURL.appendingPathComponent("book.json")
        guard manager.fileExists(atPath: bookJSONURL.path),
              let data = try? Data(contentsOf: bookJSONURL),
              let book = try? JSONDecoder().decode(LocalBook.self, from: data) else {
            return false
        }
        guard book.id == expectedID, UUID(uuidString: book.id) != nil else {
            return false
        }
        guard (try? book.validateMetadata()) != nil else { return false }
        if book.linkedFolder != nil {
            // External permission loss does not invalidate an owned index/backup.
            // Authorization and individual page availability are checked on access.
        } else if book.epub != nil {
            let epubFile = dirURL.appendingPathComponent("content.epub")
            guard manager.fileExists(atPath: epubFile.path),
                  let attrs = try? manager.attributesOfItem(atPath: epubFile.path),
                  (attrs[.size] as? UInt64 ?? 0) > 0,
                  manager.isReadableFile(atPath: epubFile.path) else {
                return false
            }
        } else if book.pdf != nil {
            let pdfFile = dirURL.appendingPathComponent("content.pdf")
            guard manager.fileExists(atPath: pdfFile.path),
                  let attrs = try? manager.attributesOfItem(atPath: pdfFile.path),
                  (attrs[.size] as? UInt64 ?? 0) > 0,
                  manager.isReadableFile(atPath: pdfFile.path) else {
                return false
            }
        } else {
            if book.importFormat == .zip || book.importFormat == .cbz {
                let archiveFile = dirURL.appendingPathComponent("source.archive")
                guard manager.fileExists(atPath: archiveFile.path),
                      let attrs = try? manager.attributesOfItem(atPath: archiveFile.path),
                      (attrs[.size] as? UInt64 ?? 0) > 0,
                      manager.isReadableFile(atPath: archiveFile.path) else {
                    return false
                }
            }
            guard !book.pages.isEmpty else { return false }
            for page in book.pages {
                guard !page.isEmpty, !page.contains("/"), !page.contains("\\"), page != ".", page != ".." else {
                    return false
                }
                let pageFile = dirURL.appendingPathComponent(page)
                guard manager.fileExists(atPath: pageFile.path),
                      let attrs = try? manager.attributesOfItem(atPath: pageFile.path),
                      (attrs[.size] as? UInt64 ?? 0) > 0,
                      manager.isReadableFile(atPath: pageFile.path) else {
                    return false
                }
            }
        }
        if let coverName = book.coverName {
            guard !coverName.isEmpty, !coverName.contains("/"), !coverName.contains("\\"), coverName != ".", coverName != ".." else {
                return false
            }
            let coverFile = dirURL.appendingPathComponent(coverName)
            guard manager.fileExists(atPath: coverFile.path),
                  manager.isReadableFile(atPath: coverFile.path) else {
                return false
            }
        }
        return true
    }

    public func recoverOrphans() async throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        let items = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        let catalogExists = await catalogStore.existsOnDisk()
        let allSeries = catalogExists ? await catalogStore.listSeries() : []
        let allVolumeIDs = Set(allSeries.flatMap(\.volumeIDs))
        var recoveryFailed = false

        let canonicalLibrary = directory.resolvingSymlinksInPath().standardizedFileURL

        for item in items {
            let name = item.lastPathComponent
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else { continue }

            if name.hasPrefix(".import-") || UUID(uuidString: name) != nil {
                do { _ = try LocalImportJournal.recover(root: directory, folder: item, catalogVolumeIDs: allVolumeIDs) }
                catch { recoveryFailed = true }
                continue
            }

            if name.hasPrefix(".backup-") {
                let remainder = String(name.dropFirst(".backup-".count))
                // Must strictly match <36-char-UUID>-<36-char-UUID>
                guard remainder.count == 73 else { continue }
                let targetVolId = String(remainder.prefix(36))
                let sep = remainder[remainder.index(remainder.startIndex, offsetBy: 36)]
                let nonce = String(remainder.suffix(36))
                guard sep == "-",
                      UUID(uuidString: targetVolId) != nil,
                      UUID(uuidString: nonce) != nil else {
                    continue
                }

                // Verify volume ownership against catalog if catalog exists
                if catalogExists && !allVolumeIDs.contains(targetVolId) {
                    continue
                }

                // Verify targetDir is strictly an immediate child within library directory
                let targetDir = directory.appendingPathComponent(targetVolId, isDirectory: true)
                let canonicalTarget = targetDir.resolvingSymlinksInPath().standardizedFileURL
                guard canonicalTarget.deletingLastPathComponent().path == canonicalLibrary.path,
                      canonicalTarget.lastPathComponent == targetVolId,
                      canonicalTarget.path != canonicalLibrary.path else {
                    continue
                }

                let targetIsComplete = isVolumeCompleteAndReadable(at: targetDir, expectedID: targetVolId)
                let backupIsComplete = isVolumeCompleteAndReadable(at: item, expectedID: targetVolId)

                if targetIsComplete {
                    // A complete target does not authorize deleting unknown backup files.
                    do { try removeOwnedVolumeDirectory(item, expectedID: targetVolId) }
                    catch { recoveryFailed = true }
                } else if backupIsComplete {
                    // Target volume is missing or damaged/missing pages, but backup is complete: restore backup!
                    if manager.fileExists(atPath: targetDir.path) {
                        do { try deleteOwnedDirectory(targetDir) }
                        catch {
                            // Keep an unrecognized/corrupt directory intact before restoring.
                            let retained = directory.appendingPathComponent(".retained-" + targetVolId + "-" + UUID().uuidString)
                            try manager.moveItem(at: targetDir, to: retained)
                        }
                    }
                    try manager.moveItem(at: item, to: targetDir)
                }
                // If neither is complete, keep both to avoid data loss.
                continue
            }

        }
        if catalogExists {
            for s in allSeries where s.status == "deleting" {
                do { try await deleteSeries(id: s.id) }
                catch { recoveryFailed = true }
            }
        }
        if recoveryFailed { throw LocalLibraryError.recoveryIncomplete }
    }
    public func importArchiveCoordinated(title: String, archive: URL, isReadableImage: @escaping (URL) throws -> Bool,
                                         targetSeriesId: String? = nil) async throws -> (series: LocalSeriesRecord, book: LocalBook) {
        let prepared = try prepareArchive(title: title, archive: archive, isReadableImage: isReadableImage)
        return try await publishImport(prepared, targetSeriesId: targetSeriesId, explicitTitle: title)
    }
    public func importFolderCoordinated(title: String, folder: URL, isReadableImage: @escaping (URL) throws -> Bool,
                                        targetSeriesId: String? = nil) async throws -> (series: LocalSeriesRecord, book: LocalBook) {
        let prepared = try prepareFolder(title: title, folder: folder, isReadableImage: isReadableImage)
        return try await publishImport(prepared, targetSeriesId: targetSeriesId, explicitTitle: title)
    }
    public func updateFolderSeries(seriesId: String, title: String, folder: URL,
                                   isReadableImage: @escaping (URL) throws -> Bool) async throws -> (series: LocalSeriesRecord, book: LocalBook) {
        let prepared = try prepareFolder(title: title, folder: folder, isReadableImage: isReadableImage)
        return try await replaceFolderVolume(seriesId: seriesId, prepared: prepared)
    }
    func replaceFolderVolume(seriesId: String, prepared: PreparedLocalImport,
                             commitRecord: @Sendable (LocalSeriesRecord, LocalBook) throws -> Void = { _, _ in }) async throws -> (series: LocalSeriesRecord, book: LocalBook) {
        defer { try? discardPrepared(prepared) }
        try await ensureLegacySeeded()
        guard var s = await catalogStore.getSeries(id: seriesId), s.status == "ready" else {
            try discardPrepared(prepared)
            throw LocalCatalogError.targetNotFound
        }
        let originalSeries = s
        let existingVolId = s.volumeIDs.first
        let targetVolId = existingVolId ?? prepared.book.id
        let workingPrepared = try prepared.reassigningTargetID(targetVolId, allowExisting: true)

        let existingDir = directory.appendingPathComponent(targetVolId)
        let existsOnDisk = FileManager.default.fileExists(atPath: existingDir.path)

        var backupDir: URL? = nil
        if existsOnDisk {
            let backupName = ".backup-" + targetVolId + "-" + UUID().uuidString
            let candidateBackup = directory.appendingPathComponent(backupName)
            try FileManager.default.moveItem(at: existingDir, to: candidateBackup)
            backupDir = candidateBackup
        }

        let published: LocalBook
        do {
            published = try publishPrepared(workingPrepared)
        } catch {
            if let backup = backupDir {
                try? FileManager.default.moveItem(at: backup, to: existingDir)
            }
            throw error
        }

        if s.volumeIDs.isEmpty { s.volumeIDs = [published.id] }
        else { s.volumeIDs[0] = published.id }
        s.updatedAt = Date().timeIntervalSince1970

        var catalogCommitted = false
        do {
            try await catalogStore.commitNewSeries(s)
            catalogCommitted = true
            try commitRecord(s, published)
        } catch {
            if catalogCommitted { try await catalogStore.commitNewSeries(originalSeries) }
            let newPublishedDir = directory.appendingPathComponent(published.id)
            try deleteOwnedDirectory(newPublishedDir)
            if let backup = backupDir {
                try FileManager.default.moveItem(at: backup, to: existingDir)
            }
            throw error
        }

        if let backup = backupDir {
            try? removeOwnedVolumeDirectory(backup, expectedID: targetVolId)
        }
        return (s, published)
    }
    public func importImagesCoordinated(title: String, files: [URL],
                                        targetSeriesId: String? = nil) async throws -> (series: LocalSeriesRecord, book: LocalBook) {
        let prepared = try prepareImages(title: title, files: files)
        return try await publishImport(prepared, targetSeriesId: targetSeriesId, explicitTitle: title)
    }
    public func importEpubCoordinated(title: String, archive: URL, isReadableImage: @escaping (URL) throws -> Bool,
                                      targetSeriesId: String? = nil) async throws -> (series: LocalSeriesRecord, book: LocalBook) {
        let prepared = try prepareEpub(title: title, archive: archive, isReadableImage: isReadableImage)
        return try await publishImport(prepared, targetSeriesId: targetSeriesId, explicitTitle: title)
    }
    public func importPdfCoordinated(title: String, file: URL, inspect: (URL) throws -> PdfPublication,
                                     renderCover: (URL) throws -> Data?, targetSeriesId: String? = nil) async throws -> (series: LocalSeriesRecord, book: LocalBook) {
        let prepared = try preparePdf(title: title, file: file, inspect: inspect, renderCover: renderCover)
        return try await publishImport(prepared, targetSeriesId: targetSeriesId, explicitTitle: title)
    }
    public func importKindleCoordinated(title: String, source: URL, format: LocalKindleFormat,
                                        isReadableImage: @escaping (URL) throws -> Bool, targetSeriesId: String? = nil) async throws -> (series: LocalSeriesRecord, book: LocalBook) {
        let prepared = try prepareKindle(title: title, source: source, format: format, isReadableImage: isReadableImage)
        return try await publishImport(prepared, targetSeriesId: targetSeriesId, explicitTitle: title)
    }
    public func importImages(title: String, files: [URL]) throws -> LocalBook {
        try publishPrepared(prepareImages(title: title, files: files))
    }
    func prepareImages(title: String, files: [URL]) throws -> PreparedLocalImport {
        try prepareFiles(title: title, files: files.sorted(by: { NaturalPathOrder.less($0.lastPathComponent, $1.lastPathComponent) }), groups: nil, importFormat: .images)
    }
    public func importFolder(title: String, folder: URL, isReadableImage: (URL) throws -> Bool) throws -> LocalBook {
        try publishPrepared(prepareFolder(title: title, folder: folder, isReadableImage: isReadableImage))
    }
    func prepareFolder(title: String, folder: URL, isReadableImage: (URL) throws -> Bool) throws -> PreparedLocalImport {
        let index = try LocalFolderIndex(folder: folder, isReadableImage: isReadableImage)
        return try prepareFolderFiles(title: title, index: index)
    }
    public func importArchive(title: String, archive: URL, isReadableImage: (URL) throws -> Bool) throws -> LocalBook {
        try publishPrepared(prepareArchive(title: title, archive: archive, isReadableImage: isReadableImage))
    }
    func prepareArchive(title: String, archive: URL, isReadableImage: (URL) throws -> Bool) throws -> PreparedLocalImport {
        do {
            return try prepareLocalImport { id, staging, owned in
                let targetArchive = staging.appendingPathComponent("source.archive")
                var copiedBytes: Int64 = 0
                try copy(archive, to: targetArchive, totalBytes: &copiedBytes, maximumFileBytes: Self.maximumImportBytes, didCreateFile: owned.recordFile)
                let index = try LocalArchiveIndex(archive: targetArchive, staging: staging, isReadableImage: { url in
                    let readable = try isReadableImage(url)
                    try owned.recordFile(url)
                    return readable
                }, didCreateFile: owned.recordFile)
                let format: LocalImportFormat = archive.pathExtension.lowercased() == "cbz" ? .cbz : .zip
                let fingerprint = try ContentFingerprint.file(targetArchive)
                return imageBook(title: title, id: id, names: index.names, groups: index.groups, importFormat: format, fingerprint: fingerprint)
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as LocalLibraryError { throw error }
        catch {
            if [NSCocoaErrorDomain, NSPOSIXErrorDomain].contains((error as NSError).domain) { throw error }
            throw LocalLibraryError.invalidArchive
        }
    }
    private func prepareFolderFiles(title: String, index: LocalFolderIndex) throws -> PreparedLocalImport {
        guard !index.files.isEmpty else { throw LocalLibraryError.emptyImport }
        return try prepareLocalImport { id, staging, owned in
            var names: [String] = []
            var totalBytes: Int64 = 0
            for (slot, file) in index.files.enumerated() {
                try Task.checkCancellation()
                let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
                guard let size = attributes.fileSize, size <= Self.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
                let name = "\(slot)." + file.pathExtension.lowercased()
                try copy(file, to: staging.appendingPathComponent(name), totalBytes: &totalBytes, didCreateFile: owned.recordFile)
                names.append(name)
            }
            let folderFiles = zip(index.relativePaths, names).map { (relativePath: $0, ownedFile: staging.appendingPathComponent($1)) }
            let fingerprint = try ContentFingerprint.folder(staging, files: folderFiles)
            return imageBook(title: title, id: id, names: names, groups: index.groups, importFormat: .folder, fingerprint: fingerprint)
        }
    }
    private func prepareFiles(title: String, files: [URL], groups: [LocalFolderIndex.Group]?, importFormat: LocalImportFormat?) throws -> PreparedLocalImport {
        guard !files.isEmpty else { throw LocalLibraryError.emptyImport }
        return try prepareLocalImport { id, staging, owned in
            var names: [String] = []
            var totalBytes: Int64 = 0
            for (index, file) in files.enumerated() {
                try Task.checkCancellation()
                let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
                guard let size = attributes.fileSize, size <= Self.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
                let name = "\(index)." + file.pathExtension.lowercased()
                try copy(file, to: staging.appendingPathComponent(name), totalBytes: &totalBytes, didCreateFile: owned.recordFile)
                names.append(name)
            }
            return imageBook(title: title, id: id, names: names, groups: groups, importFormat: importFormat, fingerprint: nil)
        }
    }
    private func imageBook(title: String, id: String, names: [String], groups: [LocalFolderIndex.Group]?,
                           importFormat: LocalImportFormat? = nil, fingerprint: String? = nil) -> LocalBook {
        let cleaned = SearchRules.trim(title)
        let chapters = groups?.enumerated().map { slot, group in
            LocalBookChapter(id: id + "_ch_\(slot)", title: group.title, pages: group.indices.map { names[$0] })
        }
        let book = LocalBook(id: id, title: cleaned.isEmpty ? "本地漫画" : cleaned, createdAt: Date().timeIntervalSince1970,
                             pages: names, chapters: chapters, importFormat: importFormat, fingerprint: fingerprint)
        return book
    }
    func copy(_ source: URL, to destination: URL, totalBytes: inout Int64, maximumFileBytes: Int64 = Int64(maximumImageBytes),
              didCreateFile: (URL) throws -> Void = { _ in }) throws {
        try Data().write(to: destination, options: .withoutOverwriting)
        try didCreateFile(destination)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var imageBytes: Int64 = 0
        while true {
            try Task.checkCancellation()
            guard let data = try readChunk(input, Self.copyChunkBytes), !data.isEmpty else { break }
            try Task.checkCancellation()
            let count = Int64(data.count)
            guard count <= maximumFileBytes - imageBytes else {
                throw maximumFileBytes == Int64(Self.maximumImageBytes) ? LocalLibraryError.imageTooLarge : LocalLibraryError.archiveTooLarge
            }
            guard count <= Self.maximumImportBytes - totalBytes else { throw LocalLibraryError.folderTooLarge }
            try output.write(contentsOf: data)
            imageBytes += count
            totalBytes += count
        }
        try Task.checkCancellation()
    }
}

public enum LocalLibraryError: LocalizedError {
    case invalidBook, emptyImport, imageTooLarge, folderTooDeep, folderTooLarge, invalidArchive, archiveTooLarge, requiresTextReader, recoveryIncomplete
    public var errorDescription: String? {
        switch self {
        case .invalidBook: return "本地漫画数据无效或文件不可用，原文件已保留。"
        case .emptyImport: return "没有可导入的图片。"
        case .imageTooLarge: return "单张图片不能超过 128 MiB，本次未导入，请先缩小该图片。"
        case .folderTooDeep: return "目录层级过深（最多支持 5 层），本次未导入。"
        case .folderTooLarge: return "文件夹超过 50000 项或 20 GiB，本次未导入。"
        case .invalidArchive: return "压缩包损坏、路径不安全、已加密或格式不支持，本次未导入，原文件已保留。仅支持 ZIP/CBZ。"
        case .archiveTooLarge: return "压缩包超过安全限制：最多 50000 项、单项 128 MiB、总量 20 GiB。本次未导入，原文件已保留。"
        case .requiresTextReader: return "该 EPUB 章节包含文字内容，需要使用文字阅读器。"
        case .recoveryIncomplete: return "部分本地恢复未完成：未知或被替换的文件已保留，请检查本地存储后重试。"
        }
    }
}
