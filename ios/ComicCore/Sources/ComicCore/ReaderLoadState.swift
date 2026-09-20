import Foundation

/// Chapter loading hides directory errors temporarily, but cannot discard them.
public struct ReaderLoadState {
    public enum FailureKind { case chapter, directory }
    public private(set) var chapterLoading = false
    private var chapterError: Error?
    private var directoryError: Error?
    public init() {}
    public var visibleFailure: (kind: FailureKind, error: Error)? {
        guard !chapterLoading else { return nil }
        if let chapterError { return (.chapter, chapterError) }
        if let directoryError { return (.directory, directoryError) }
        return nil
    }
    public mutating func chapterStarted() { chapterLoading = true; chapterError = nil }
    public mutating func chapterFinished(error: Error? = nil) { chapterLoading = false; chapterError = error }
    public mutating func directoryFinished(error: Error? = nil) { directoryError = error }
}
