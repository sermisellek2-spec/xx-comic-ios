import Foundation

public struct LocalBook: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: TimeInterval
    public let pages: [String]
    public let chapters: [LocalBookChapter]?

    public init(id: String, title: String, createdAt: TimeInterval, pages: [String], chapters: [LocalBookChapter]? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.pages = pages; self.chapters = chapters
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
    public var directory: URL { URL(fileURLWithPath: directoryPath, isDirectory: true) }
    public init(directory: URL) throws {
        try self.init(directory: directory, readChunk: { try $0.read(upToCount: $1) })
    }
    init(directory: URL, readChunk: @escaping @Sendable (FileHandle, Int) throws -> Data?) throws {
        directoryPath = directory.path
        self.readChunk = readChunk
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public func books() throws -> [LocalBook] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .map { folder in
                let book = try JSONDecoder().decode(LocalBook.self, from: Data(contentsOf: folder.appendingPathComponent("book.json")))
                guard book.id == folder.lastPathComponent else { throw LocalLibraryError.invalidBook }
                _ = try pageURLs(for: book)
                return book
            }.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
    }
    public func book(id: String) throws -> LocalBook {
        guard UUID(uuidString: id) != nil else { throw LocalLibraryError.invalidBook }
        let book = try JSONDecoder().decode(LocalBook.self, from: Data(contentsOf: directory.appendingPathComponent(id).appendingPathComponent("book.json")))
        guard book.id == id else { throw LocalLibraryError.invalidBook }
        return book
    }
    public func pageURLs(for book: LocalBook) throws -> [URL] {
        let pageNames = Set(book.pages)
        guard UUID(uuidString: book.id) != nil, !book.pages.isEmpty, pageNames.count == book.pages.count else { throw LocalLibraryError.invalidBook }
        if let chapters = book.chapters {
            let chapterPages = chapters.flatMap(\.pages)
            guard !chapters.isEmpty, Set(chapters.map(\.id)).count == chapters.count,
                  chapters.allSatisfy({ !$0.id.isEmpty && !$0.id.contains("/") && !$0.id.contains("\\") && $0.id != "." && $0.id != ".." && !$0.pages.isEmpty && $0.pages.allSatisfy(pageNames.contains) }),
                  chapterPages.count == book.pages.count, Set(chapterPages).count == chapterPages.count,
                  Set(chapterPages) == pageNames else { throw LocalLibraryError.invalidBook }
        }
        return try book.pages.map { name in
            guard name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.isEmpty else { throw LocalLibraryError.invalidBook }
            return directory.appendingPathComponent(book.id, isDirectory: true).appendingPathComponent(name)
        }
    }
    public func summary(for book: LocalBook) throws -> ComicSummary {
        ComicSummary(sourceId: "local", comicId: book.id, title: book.title,
                     coverUrl: try pageURLs(for: book).first?.absoluteString ?? "", subtitle: "\(book.pages.count) 页")
    }
    public func importImages(title: String, files: [URL]) throws -> LocalBook {
        try importFiles(title: title, files: files.sorted(by: { NaturalPathOrder.less($0.lastPathComponent, $1.lastPathComponent) }), groups: nil)
    }
    public func importFolder(title: String, folder: URL, isReadableImage: (URL) throws -> Bool) throws -> LocalBook {
        let index = try LocalFolderIndex(folder: folder, isReadableImage: isReadableImage)
        return try importFiles(title: title, files: index.files, groups: index.groups)
    }
    private func importFiles(title: String, files: [URL], groups: [LocalFolderIndex.Group]?) throws -> LocalBook {
        guard !files.isEmpty else { throw LocalLibraryError.emptyImport }
        let id = UUID().uuidString, manager = FileManager.default
        let staging = directory.appendingPathComponent(".import-" + id, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { if manager.fileExists(atPath: staging.path) { try? manager.removeItem(at: staging) } }
        var names: [String] = []
        var totalBytes: Int64 = 0
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
            guard let size = attributes.fileSize, size <= Self.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
            let name = "\(index)." + file.pathExtension.lowercased()
            try copy(file, to: staging.appendingPathComponent(name), totalBytes: &totalBytes)
            names.append(name)
        }
        let cleaned = SearchRules.trim(title)
        let chapters = groups?.enumerated().map { slot, group in
            LocalBookChapter(id: id + "_ch_\(slot)", title: group.title, pages: group.indices.map { names[$0] })
        }
        let book = LocalBook(id: id, title: cleaned.isEmpty ? "本地漫画" : cleaned, createdAt: Date().timeIntervalSince1970, pages: names, chapters: chapters)
        try JSONEncoder().encode(book).write(to: staging.appendingPathComponent("book.json"), options: .atomic)
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: directory.appendingPathComponent(id, isDirectory: true))
        return book
    }
    private func copy(_ source: URL, to destination: URL, totalBytes: inout Int64) throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw LocalLibraryError.invalidBook }
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
            guard count <= Int64(Self.maximumImageBytes) - imageBytes else { throw LocalLibraryError.imageTooLarge }
            guard count <= Self.maximumImportBytes - totalBytes else { throw LocalLibraryError.folderTooLarge }
            try output.write(contentsOf: data)
            imageBytes += count
            totalBytes += count
        }
        try Task.checkCancellation()
    }
}

public enum LocalLibraryError: LocalizedError {
    case invalidBook, emptyImport, imageTooLarge, folderTooDeep, folderTooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidBook: return "本地漫画数据无效或文件不可用，原文件已保留。"
        case .emptyImport: return "没有可导入的图片。"
        case .imageTooLarge: return "单张图片不能超过 128 MiB，本次未导入，请先缩小该图片。"
        case .folderTooDeep: return "目录层级过深（最多支持 5 层），本次未导入。"
        case .folderTooLarge: return "文件夹超过 50000 项或 20 GiB，本次未导入。"
        }
    }
}
