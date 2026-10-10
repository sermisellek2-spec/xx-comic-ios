import Foundation

public enum SearchRules {
    // Java String.trim removes only UTF-16 code units <= U+0020.
    // Foundation whitespace trimming and Swift canonical equality are broader.
    public static func trim(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.drop(while: { $0.value <= 32 })
            .reversed().drop(while: { $0.value <= 32 }).reversed()))
    }

    public static func isExact(title: String, query: String) -> Bool {
        let expected = trim(query)
        return !expected.isEmpty && trim(title).utf16.elementsEqual(expected.utf16)
    }

    public static func prioritize(_ items: [ComicSummary], query: String) -> [ComicSummary] {
        var exact: [ComicSummary] = []
        var others: [ComicSummary] = []
        for item in items {
            if isExact(title: item.title, query: query) { exact.append(item) }
            else { others.append(item) }
        }
        return exact + others
    }

    public static func hasExact(_ items: [ComicSummary], query: String) -> Bool {
        items.contains { isExact(title: $0.title, query: query) }
    }
}

public enum SourceOrder {
    public static func normalize(_ saved: [String], available: [String]) -> [String] {
        let valid = Set(available)
        var seen = Set<String>()
        return (saved + available).filter { valid.contains($0) && seen.insert($0).inserted }
    }

    public static func exactFirst<T>(_ items: [T], isExact: (T) -> Bool) -> [T] {
        var first: [T] = []
        var rest: [T] = []
        for item in items {
            if isExact(item) { first.append(item) }
            else { rest.append(item) }
        }
        return first + rest
    }
}

/// Value state owned by the UI actor; networking carries the returned generation.
public struct GlobalSearchState: Sendable {
    public private(set) var generation = UUID()
    public private(set) var query = ""
    public private(set) var sourceIDs: [String] = []
    public private(set) var selectedSourceID: String?
    public private(set) var results: [String: [ComicSummary]] = [:]
    public private(set) var exactSourceIDs = Set<String>()
    private var manuallySelected = false
    private var selectedFirstResult = false

    public init() {}

    @discardableResult
    public mutating func begin(query: String, sourceIDs: [String], restoringSelectedSourceID: String? = nil) -> UUID {
        self = GlobalSearchState()
        self.query = SearchRules.trim(query)
        self.sourceIDs = SourceOrder.normalize([], available: sourceIDs)
        if let restoringSelectedSourceID, self.sourceIDs.contains(restoringSelectedSourceID) {
            selectedSourceID = restoringSelectedSourceID
            manuallySelected = true
        } else {
            selectedSourceID = self.sourceIDs.first
        }
        return generation
    }

    public mutating func select(_ sourceID: String) {
        guard sourceIDs.contains(sourceID) else { return }
        selectedSourceID = sourceID
        manuallySelected = true
    }

    @discardableResult
    public mutating func receive(sourceID: String, items: [ComicSummary], generation: UUID) -> Bool {
        guard generation == self.generation, sourceIDs.contains(sourceID) else { return false }
        results[sourceID] = SearchRules.prioritize(items, query: query)
        if SearchRules.hasExact(items, query: query) { exactSourceIDs.insert(sourceID) }
        else { exactSourceIDs.remove(sourceID) }
        if !items.isEmpty && !manuallySelected && !selectedFirstResult {
            selectedSourceID = sourceID
            selectedFirstResult = true
        }
        return true
    }

    /// Sources with non-empty results, exact-match sources partitioned to front (DISC-03).
    public var visibleSourceIDs: [String] {
        let nonEmpty = sourceIDs.filter { !(results[$0]?.isEmpty ?? true) }
        return SourceOrder.exactFirst(nonEmpty) { exactSourceIDs.contains($0) }
    }
}
