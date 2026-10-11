@preconcurrency import Foundation

/// A saved URI identifies a session item; only newly selected URLs grant access.
/// Exact matches take priority. A moved file is matched by name only when both
/// the remaining item and selected file are unique, never by selection order.
public struct BatchImportRecoveryPlan: Sendable {
    public let urlMap: [String: URL]
    public let unresolvedNames: [String]
    public let ambiguousNames: [String]
    public let pendingCount: Int

    public init(snapshot: BatchImportSession.Snapshot, selectedURLs: [URL]) {
        let items = snapshot.cancelled ? [] : snapshot.groups.flatMap(\.items).filter {
            $0.state == .pending || $0.state == .running || $0.state == .failed
        }
        let unique = Dictionary(items.map { ($0.uri, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = Set(selectedURLs.filter(\.isFileURL))
        var mapped: [String: URL] = [:]
        var consumed = Set<URL>()
        for item in unique.values {
            let exact = selected.filter { item.uri == $0.path || item.uri == $0.absoluteString }
            if exact.count == 1, let url = exact.first { mapped[item.uri] = url; consumed.insert(url) }
        }
        let remaining = unique.values.filter { mapped[$0.uri] == nil }
        let byName = Dictionary(grouping: remaining, by: \.name)
        let filesByName = Dictionary(grouping: selected.subtracting(consumed), by: \.lastPathComponent)
        var ambiguous = Set<String>()
        for (name, candidates) in byName {
            let files = filesByName[name] ?? []
            if candidates.count == 1, files.count == 1 {
                mapped[candidates[0].uri] = files[0]
            } else if !files.isEmpty {
                ambiguous.insert(name)
            }
        }
        urlMap = mapped
        unresolvedNames = items.filter { mapped[$0.uri] == nil }.map(\.name)
        ambiguousNames = ambiguous.sorted()
        pendingCount = items.count
    }
}
