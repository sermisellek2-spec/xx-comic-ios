import Foundation

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

    public init(id: String, title: String, createdAt: TimeInterval, pages: [String], chapters: [LocalBookChapter]? = nil, epub: EpubPublication? = nil, pdf: PdfPublication? = nil, coverName: String? = nil, kindleFormat: LocalKindleFormat? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.pages = pages; self.chapters = chapters
        self.epub = epub; self.pdf = pdf; self.coverName = coverName
        self.kindleFormat = kindleFormat
    }
}

public struct LocalBookChapter: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let pages: [String]
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
    public init(directory: URL) throws {
        try self.init(directory: directory, readChunk: { try $0.read(upToCount: $1) })
    }
    init(directory: URL, readChunk: @escaping @Sendable (FileHandle, Int) throws -> Data?,
         beforeKindlePublish: @escaping @Sendable () throws -> Void = {},
         beforeImportPublish: @escaping @Sendable () throws -> Void = {}) throws {
        directoryPath = directory.path
        self.readChunk = readChunk
        self.beforeKindlePublish = beforeKindlePublish
        self.beforeImportPublish = beforeImportPublish
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
    public func importImages(title: String, files: [URL]) throws -> LocalBook {
        try publishPrepared(prepareImages(title: title, files: files))
    }
    func prepareImages(title: String, files: [URL]) throws -> PreparedLocalImport {
        try prepareFiles(title: title, files: files.sorted(by: { NaturalPathOrder.less($0.lastPathComponent, $1.lastPathComponent) }), groups: nil)
    }
    public func importFolder(title: String, folder: URL, isReadableImage: (URL) throws -> Bool) throws -> LocalBook {
        try publishPrepared(prepareFolder(title: title, folder: folder, isReadableImage: isReadableImage))
    }
    func prepareFolder(title: String, folder: URL, isReadableImage: (URL) throws -> Bool) throws -> PreparedLocalImport {
        let index = try LocalFolderIndex(folder: folder, isReadableImage: isReadableImage)
        return try prepareFiles(title: title, files: index.files, groups: index.groups)
    }
    public func importArchive(title: String, archive: URL, isReadableImage: (URL) throws -> Bool) throws -> LocalBook {
        try publishPrepared(prepareArchive(title: title, archive: archive, isReadableImage: isReadableImage))
    }
    func prepareArchive(title: String, archive: URL, isReadableImage: (URL) throws -> Bool) throws -> PreparedLocalImport {
        do {
            return try prepareLocalImport { id, staging, owned in
                let index = try LocalArchiveIndex(archive: archive, staging: staging, isReadableImage: { url in
                    let readable = try isReadableImage(url)
                    try owned.recordFile(url)
                    return readable
                }, didCreateFile: owned.recordFile)
                return imageBook(title: title, id: id, names: index.names, groups: index.groups)
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as LocalLibraryError { throw error }
        catch {
            if [NSCocoaErrorDomain, NSPOSIXErrorDomain].contains((error as NSError).domain) { throw error }
            throw LocalLibraryError.invalidArchive
        }
    }
    private func prepareFiles(title: String, files: [URL], groups: [LocalFolderIndex.Group]?) throws -> PreparedLocalImport {
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
            return imageBook(title: title, id: id, names: names, groups: groups)
        }
    }
    private func imageBook(title: String, id: String, names: [String], groups: [LocalFolderIndex.Group]?) -> LocalBook {
        let cleaned = SearchRules.trim(title)
        let chapters = groups?.enumerated().map { slot, group in
            LocalBookChapter(id: id + "_ch_\(slot)", title: group.title, pages: group.indices.map { names[$0] })
        }
        let book = LocalBook(id: id, title: cleaned.isEmpty ? "本地漫画" : cleaned, createdAt: Date().timeIntervalSince1970, pages: names, chapters: chapters)
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
