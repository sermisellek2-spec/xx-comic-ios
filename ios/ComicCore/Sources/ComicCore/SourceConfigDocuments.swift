import Foundation

public enum SourceConfigDocumentError: LocalizedError, Equatable {
    case invalidFile
    case tooLarge
    case invalidUTF8
    case readFailed
    case unsafeExport

    public var errorDescription: String? {
        switch self {
        case .invalidFile: return "请选择普通的站源配置文件，现有配置未修改"
        case .tooLarge: return "站源配置超过 8 MB，现有配置未修改"
        case .invalidUTF8: return "站源配置不是 UTF-8 文本，现有配置未修改"
        case .readFailed: return "无法读取站源配置文件，请重新选择；现有配置未修改"
        case .unsafeExport: return "无法清理临时导出副本，文件已保留"
        }
    }
}

public struct SourceConfigExportDocument: Equatable, Sendable {
    public let id: UUID
    public let url: URL
}

/// Only value snapshots enter this worker. Parsing and file-provider access do
/// not block UIKit, and preparing an import cannot change saved preferences.
public actor SourceConfigDocuments {
    public static let filename = "xx-comic-sources.json"
    public static let maximumBytes: Int64 = 8 * 1024 * 1024
    private let root: URL
    private let coordinator: FileAccessCoordinator
    private var exports: [UUID: (document: SourceConfigExportDocument, bytes: Data)] = [:]

    public init(temporaryRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("XXComicSourceExports", isDirectory: true),
                coordinator: FileAccessCoordinator = .system) {
        self.root = temporaryRoot.standardizedFileURL
        self.coordinator = coordinator
    }

    public func prepareImport(from url: URL, snapshot: SourceImportSnapshot) throws -> PreparedSourceImport {
        try Task.checkCancellation()
        guard url.isFileURL else { throw SourceConfigDocumentError.invalidFile }
        #if canImport(Darwin)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        #endif
        let data: Data
        do {
            data = try coordinator.coordinate(url, access: .read) {
                try FileAccessCoordinator.readRegularFile($0, maximumBytes: Self.maximumBytes)
            }
        } catch is CancellationError { throw CancellationError() }
        catch LocalLibraryError.imageTooLarge { throw SourceConfigDocumentError.tooLarge }
        catch DownloadLocationError.unsafePath { throw SourceConfigDocumentError.invalidFile }
        catch { throw SourceConfigDocumentError.readFailed }
        guard var text = String(data: data, encoding: .utf8) else { throw SourceConfigDocumentError.invalidUTF8 }
        // Android's UTF-8 JSONObject reader accepts a leading BOM too.
        if text.first == "\u{FEFF}" { text.removeFirst() }
        return try SourcePreferences.prepareImport(jsonString: text, snapshot: snapshot)
    }

    public func prepareExport(_ package: SourceExportPackage) throws -> SourceConfigExportDocument {
        try Task.checkCancellation()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(package)
        guard data.count <= Self.maximumBytes else { throw SourceConfigDocumentError.tooLarge }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        guard try manager.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw SourceConfigDocumentError.unsafeExport
        }
        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        let document = SourceConfigExportDocument(id: id, url: folder.appendingPathComponent(Self.filename))
        do {
            try Task.checkCancellation()
            try data.write(to: document.url, options: .withoutOverwriting)
            exports[id] = (document, data)
            try Task.checkCancellation()
            return document
        } catch {
            if exports[id] != nil { try discardExport(document) }
            else if try manager.contentsOfDirectory(atPath: folder.path).isEmpty { try manager.removeItem(at: folder) }
            throw error
        }
    }

    /// Delete only this actor's exact, unchanged file, then its empty directory.
    /// Unknown entries and replaced files (including links) are preserved.
    public func discardExport(_ document: SourceConfigExportDocument) throws {
        guard let owned = exports[document.id] else { return }
        guard owned.document == document,
              document.url.lastPathComponent == Self.filename,
              document.url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == root.path else {
            throw SourceConfigDocumentError.unsafeExport
        }
        let manager = FileManager.default, folder = document.url.deletingLastPathComponent()
        for directory in [root, folder] {
            guard try manager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw SourceConfigDocumentError.unsafeExport
            }
        }
        let names = try manager.contentsOfDirectory(atPath: folder.path)
        if names.contains(Self.filename) {
            let attributes = try manager.attributesOfItem(atPath: document.url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.int64Value == Int64(owned.bytes.count),
                  try Data(contentsOf: document.url) == owned.bytes else {
                throw SourceConfigDocumentError.unsafeExport
            }
            try manager.removeItem(at: document.url)
        }
        if try manager.contentsOfDirectory(atPath: folder.path).isEmpty { try manager.removeItem(at: folder) }
        exports.removeValue(forKey: document.id)
    }
}
