import Foundation

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

    public init(id: String, title: String, createdAt: TimeInterval, pages: [String], chapters: [LocalBookChapter]? = nil, epub: EpubPublication? = nil, pdf: PdfPublication? = nil, coverName: String? = nil, kindleFormat: LocalKindleFormat? = nil, importFormat: LocalImportFormat? = nil, fingerprint: String? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.pages = pages; self.chapters = chapters
        self.epub = epub; self.pdf = pdf; self.coverName = coverName
        self.kindleFormat = kindleFormat
        self.importFormat = importFormat
        self.fingerprint = fingerprint
    }
}

public struct LocalBookChapter: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let pages: [String]
}

extension LocalBook {
    func validateMetadata() throws {
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
        guard book.coverName == nil else { throw LocalLibraryError.invalidBook }
        return try book.pages.map { name in
            guard name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.isEmpty else { throw LocalLibraryError.invalidBook }
            return directory.appendingPathComponent(book.id, isDirectory: true).appendingPathComponent(name)
        }
    }
    public func summary(for book: LocalBook) throws -> ComicSummary {
        let pages = try pageURLs(for: book)
        let cover = book.epub == nil && book.pdf == nil ? pages.first?.absoluteString ?? ""
            : try book.coverName.map { try ownedFile(bookID: book.id, name: $0).absoluteString } ?? ""
        return ComicSummary(sourceId: "local", comicId: book.id, title: book.title,
                            coverUrl: cover, subtitle: "\(book.pages.count) 页")
    }
    public func summary(for series: LocalSeriesRecord) throws -> ComicSummary {
        if let firstId = series.volumeIDs.first, let firstBook = try? book(id: firstId) {
            let allVolumes = series.volumeIDs.compactMap { try? book(id: $0) }
            let totalPages = allVolumes.reduce(0) { $0 + $1.pages.count }
            let pages = try pageURLs(for: firstBook)
            let cover = firstBook.epub == nil && firstBook.pdf == nil ? pages.first?.absoluteString ?? ""
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
        let publishedBook = try publishPrepared(workingPrepared)
        do {
            if let targetId = targetSeriesId {
                let removingFPs = [publishedBook.fingerprint].compactMap { $0 }
                try await catalogStore.appendVolume(seriesId: targetId, volumeId: publishedBook.id, removingFingerprints: removingFPs)
                guard let updatedSeries = await catalogStore.getSeries(id: targetId) else {
                    throw LocalCatalogError.targetNotFound
                }
                return (updatedSeries, publishedBook)
            } else {
                let title = explicitTitle ?? publishedBook.title
                let series = LocalSeriesRecord(id: seriesId, originalTitle: title, userTitle: userTitle,
                                               volumeIDs: [publishedBook.id], createdAt: publishedBook.createdAt,
                                               updatedAt: Date().timeIntervalSince1970, status: "ready")
                let removingFPs = [publishedBook.fingerprint].compactMap { $0 }
                try await catalogStore.commitNewSeries(series, removingFingerprints: removingFPs)
                return (series, publishedBook)
            }
        } catch {
            let volumeDir = directory.appendingPathComponent(publishedBook.id)
            try? FileManager.default.removeItem(at: volumeDir)
            throw error
        }
    }
    public func deleteSeries(id: String) async throws {
        try await ensureLegacySeeded()
        guard let series = await catalogStore.getSeries(id: id) else {
            throw LocalCatalogError.targetNotFound
        }
        try await catalogStore.markSeriesDeleting(seriesId: id)
        var tombstones: [LocalDeletedFingerprintRecord] = []
        let now = Date().timeIntervalSince1970
        for volId in series.volumeIDs {
            if let fp = (try? book(id: volId))?.fingerprint {
                tombstones.append(LocalDeletedFingerprintRecord(
                    fingerprint: fp, seriesId: series.id, volumeId: volId, userTitle: series.userTitle, deletedAt: now
                ))
            }
        }
        for volId in series.volumeIDs {
            let volURL = directory.appendingPathComponent(volId)
            try deleteOwnedDirectory(volURL)
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
    func deleteOwnedDirectory(_ url: URL) throws {
        let name = url.lastPathComponent
        guard UUID(uuidString: name) != nil else { throw LocalLibraryError.invalidBook }
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw LocalLibraryError.invalidBook
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw LocalLibraryError.invalidBook
        }
        try FileManager.default.removeItem(at: url)
    }
    public func recoverOrphans() async throws {
        let manager = FileManager.default
        let items = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        for item in items {
            let name = item.lastPathComponent
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { continue }
            if name.hasPrefix(".import-") && values.isDirectory == true {
                try? manager.removeItem(at: item)
                continue
            }
            if UUID(uuidString: name) != nil && values.isDirectory == true {
                if await catalogStore.existsOnDisk() {
                    let allSeries = await catalogStore.listSeries()
                    let allVolumeIDs = Set(allSeries.flatMap(\.volumeIDs))
                    if !allVolumeIDs.contains(name) {
                        try? manager.removeItem(at: item)
                    }
                }
            }
        }
        if await catalogStore.existsOnDisk() {
            let allSeries = await catalogStore.listSeries()
            for s in allSeries where s.status == "deleting" {
                try? await deleteSeries(id: s.id)
            }
        }
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
    case invalidBook, emptyImport, imageTooLarge, folderTooDeep, folderTooLarge, invalidArchive, archiveTooLarge, requiresTextReader
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
        }
    }
}
