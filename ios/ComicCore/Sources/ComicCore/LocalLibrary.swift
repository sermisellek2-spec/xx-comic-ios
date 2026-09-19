import Foundation

public struct LocalBook: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: TimeInterval
    public let pages: [String]
}

/// A complete import becomes visible through a single directory rename.
public struct LocalLibrary: Sendable {
    public static let maximumImageBytes = 40 * 1024 * 1024
    private let directoryPath: String
    public var directory: URL { URL(fileURLWithPath: directoryPath, isDirectory: true) }
    public init(directory: URL) throws {
        directoryPath = directory.path
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
        guard UUID(uuidString: book.id) != nil, !book.pages.isEmpty else { throw LocalLibraryError.invalidBook }
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
        guard !files.isEmpty else { throw LocalLibraryError.emptyImport }
        let id = UUID().uuidString, manager = FileManager.default
        let staging = directory.appendingPathComponent(".import-" + id, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { if manager.fileExists(atPath: staging.path) { try? manager.removeItem(at: staging) } }
        var names: [String] = []
        for (index, file) in files.sorted(by: { NaturalPathOrder.less($0.lastPathComponent, $1.lastPathComponent) }).enumerated() {
            try Task.checkCancellation()
            let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
            guard let size = attributes.fileSize, size <= Self.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
            let name = "\(index)." + file.pathExtension.lowercased()
            try manager.copyItem(at: file, to: staging.appendingPathComponent(name))
            names.append(name)
        }
        let cleaned = SearchRules.trim(title)
        let book = LocalBook(id: id, title: cleaned.isEmpty ? "本地漫画" : cleaned, createdAt: Date().timeIntervalSince1970, pages: names)
        try JSONEncoder().encode(book).write(to: staging.appendingPathComponent("book.json"), options: .atomic)
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: directory.appendingPathComponent(id, isDirectory: true))
        return book
    }
}

public enum LocalLibraryError: LocalizedError {
    case invalidBook, emptyImport, imageTooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidBook: return "本地漫画数据无效或文件不可用，原文件已保留。"
        case .emptyImport: return "没有可导入的图片。"
        case .imageTooLarge: return "单张图片不能超过 40 MiB，本次未导入，请先缩小该图片。"
        }
    }
}
