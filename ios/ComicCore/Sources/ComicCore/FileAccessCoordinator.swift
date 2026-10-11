import Foundation

/// File-provider accessors are synchronous. Network downloads must finish in a
/// private staging directory before entering an accessor to publish their bytes.
public struct FileAccessCoordinator: Sendable {
    public enum Access: Equatable, Sendable { case read, write, delete }
    private let perform: @Sendable (URL, Access, (URL) throws -> Void) throws -> Void

    public init(perform: @escaping @Sendable (URL, Access, (URL) throws -> Void) throws -> Void) {
        self.perform = perform
    }

    public func coordinate<T>(_ url: URL, access: Access, body: (URL) throws -> T) throws -> T {
        try Task.checkCancellation()
        var result: Result<T, Error>?
        try perform(url, access) { coordinatedURL in
            try Task.checkCancellation()
            result = Result { try body(coordinatedURL) }
        }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    public static let system = FileAccessCoordinator { url, access, body in
        #if canImport(Darwin)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var accessorError: Error?
        switch access {
        case .read:
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) {
                do { try body($0) } catch { accessorError = error }
            }
        case .write:
            coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) {
                do { try body($0) } catch { accessorError = error }
            }
        case .delete:
            coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) {
                do { try body($0) } catch { accessorError = error }
            }
        }
        if let coordinationError { throw coordinationError }
        if let accessorError { throw accessorError }
        #else
        try body(url)
        #endif
    }

    public static func readRegularFile(_ url: URL, maximumBytes: Int64) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw DownloadLocationError.unsafePath }
        guard let size = (attributes[.size] as? NSNumber)?.int64Value, size >= 0, size <= maximumBytes else {
            throw LocalLibraryError.imageTooLarge
        }
        try Task.checkCancellation()
        // Owned memory remains valid after the coordination accessor has finished.
        let data = try Data(contentsOf: url)
        try Task.checkCancellation()
        guard data.count <= maximumBytes else { throw LocalLibraryError.imageTooLarge }
        return data
    }
}
