import Foundation

public enum SearchRules {
    public static let exactMatchScore = 10000

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

    public static func calculateMatchScore(title: String, query: String) -> Int {
        let rawTitle = trim(title)
        let rawQuery = trim(query)
        if rawTitle.isEmpty || rawQuery.isEmpty { return 0 }

        if rawTitle.utf16.elementsEqual(rawQuery.utf16) { return exactMatchScore }

        let lowerTitle = rawTitle.lowercased()
        let lowerQuery = rawQuery.lowercased()
        if lowerTitle.utf16.elementsEqual(lowerQuery.utf16) || lowerTitle == lowerQuery {
            return 9900
        }

        var normTitle = normalizeForMatch(lowerTitle)
        var normQuery = normalizeForMatch(lowerQuery)
        if normTitle.isEmpty { normTitle = lowerTitle }
        if normQuery.isEmpty { normQuery = lowerQuery }

        if normTitle.utf16.elementsEqual(normQuery.utf16) || normTitle == normQuery {
            return 9500
        }

        // 半匹配 A：标题完整包含搜索词
        if lowerTitle.contains(lowerQuery) || normTitle.contains(normQuery) {
            let isPrefix = lowerTitle.hasPrefix(lowerQuery) || normTitle.hasPrefix(normQuery)
            let isSuffix = lowerTitle.hasSuffix(lowerQuery) || normTitle.hasSuffix(normQuery)
            let qLen = max(1, normQuery.utf16.count)
            let tLen = max(qLen, normTitle.utf16.count)
            let ratioBonus = Int((1500.0 * Double(qLen) / Double(tLen)).rounded())
            let positionBonus = isPrefix ? 800 : (isSuffix ? 300 : 0)
            return 7000 + positionBonus + ratioBonus
        }

        // 半匹配 B：搜索词完整包含标题（标题至少 2 个有效字符）
        if normTitle.utf16.count >= 2 && (lowerQuery.contains(lowerTitle) || normQuery.contains(normTitle)) {
            let isPrefix = lowerQuery.hasPrefix(lowerTitle) || normQuery.hasPrefix(normTitle)
            let tLen = normTitle.utf16.count
            let qLen = max(tLen, normQuery.utf16.count)
            let ratioBonus = Int((900.0 * Double(tLen) / Double(qLen)).rounded())
            return 5800 + (isPrefix ? 300 : 0) + ratioBonus
        }

        // 相似度匹配：当无直接包含关系时，按公共子序列与字符覆盖度评估相似度
        let a = Array(normTitle.utf16)
        let b = Array(normQuery.utf16)
        if b.count < 2 || a.count < 2 { return 0 }

        let lcs = longestCommonSubsequence(a, b)
        let commonChars = countMatchedQueryChars(title: a, query: b)
        let bestOverlap = max(lcs, commonChars)
        let queryCoverage = Double(bestOverlap) / Double(b.count)
        if bestOverlap < 2 || queryCoverage < 0.5 { return 0 }

        let lcsQueryRatio = Double(lcs) / Double(b.count)
        let lcsDice = (2.0 * Double(lcs)) / Double(b.count + a.count)
        let charQueryRatio = Double(commonChars) / Double(b.count)
        let similarity = 0.45 * lcsQueryRatio + 0.35 * lcsDice + 0.20 * charQueryRatio
        return Int((1000.0 + similarity * 4500.0).rounded())
    }

    public static func bestMatchScore(_ items: [ComicSummary], query: String) -> Int {
        guard !items.isEmpty else { return 0 }
        let trimmedQuery = trim(query)
        guard !trimmedQuery.isEmpty else { return 0 }
        var best = 0
        for item in items {
            let score = calculateMatchScore(title: item.title, query: trimmedQuery)
            if score > best {
                best = score
                if best >= exactMatchScore { break }
            }
        }
        return best
    }

    public static func prioritize(_ items: [ComicSummary], query: String) -> [ComicSummary] {
        guard !items.isEmpty else { return [] }
        let trimmedQuery = trim(query)
        guard !trimmedQuery.isEmpty else { return items }

        var scores: [Int] = []
        scores.reserveCapacity(items.count)
        var hasPositive = false
        for item in items {
            let score = calculateMatchScore(title: item.title, query: trimmedQuery)
            scores.append(score)
            if score > 0 { hasPositive = true }
        }

        guard hasPositive else { return items }

        var indexed = Array(items.indices)
        indexed.sort { a, b in
            let scoreA = scores[a]
            let scoreB = scores[b]
            if scoreA != scoreB {
                return scoreA > scoreB
            }
            return a < b
        }
        return indexed.map { items[$0] }
    }

    public static func hasExact(_ items: [ComicSummary], query: String) -> Bool {
        items.contains { isExact(title: $0.title, query: query) }
    }

    private static func normalizeForMatch(_ input: String) -> String {
        String(input.filter { $0.isLetter || $0.isNumber })
    }

    private static func longestCommonSubsequence(_ a: [UTF16.CodeUnit], _ b: [UTF16.CodeUnit]) -> Int {
        let m = min(a.count, 64)
        let n = min(b.count, 64)
        guard m > 0, n > 0 else { return 0 }
        var dp = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            var prev = 0
            let ca = a[i - 1]
            for j in 1...n {
                let temp = dp[j]
                if ca == b[j - 1] {
                    dp[j] = prev + 1
                } else {
                    dp[j] = max(dp[j], dp[j - 1])
                }
                prev = temp
            }
        }
        return dp[n]
    }

    private static func countMatchedQueryChars(title: [UTF16.CodeUnit], query: [UTF16.CodeUnit]) -> Int {
        guard !title.isEmpty, !query.isEmpty else { return 0 }
        var used = [Bool](repeating: false, count: title.count)
        var matched = 0
        for qc in query {
            for j in 0..<title.count {
                if !used[j] && title[j] == qc {
                    used[j] = true
                    matched += 1
                    break
                }
            }
        }
        return matched
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

    public static func rankByScore<T>(_ items: [T], score: (T) -> Int) -> [T] {
        guard items.count > 1 else { return items }
        let scores = items.map(score)
        var indexed = Array(items.indices)
        indexed.sort { a, b in
            let scoreA = scores[a]
            let scoreB = scores[b]
            if scoreA != scoreB {
                return scoreA > scoreB
            }
            return a < b
        }
        return indexed.map { items[$0] }
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
    private var bestScores: [String: Int] = [:]
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
        let prioritized = SearchRules.prioritize(items, query: query)
        results[sourceID] = prioritized
        bestScores[sourceID] = SearchRules.bestMatchScore(prioritized, query: query)
        if SearchRules.hasExact(prioritized, query: query) { exactSourceIDs.insert(sourceID) }
        else { exactSourceIDs.remove(sourceID) }
        if !prioritized.isEmpty && !manuallySelected && !selectedFirstResult {
            selectedSourceID = sourceID
            selectedFirstResult = true
        }
        return true
    }

    /// Sources with non-empty results, ranked by match relevance (DISC-03), preserving user sourceIDs tie-break.
    public var visibleSourceIDs: [String] {
        let nonEmpty = sourceIDs.filter { !(results[$0]?.isEmpty ?? true) }
        return SourceOrder.rankByScore(nonEmpty) { bestScores[$0] ?? 0 }
    }
}

/// Fast-source priority dispatch scheduler for 100+ source global search (2.0.49 parity).
/// Only reorders network dispatch order; UI tab order remains controlled by `GlobalSearchState.visibleSourceIDs`.
public final class GlobalSearchDispatchPolicy: @unchecked Sendable {
    public static let shared = GlobalSearchDispatchPolicy()
    public static let maxConcurrency = 12
    public static let fastThresholdMs = 2000
    public static let defaultTimeoutMs = 8000

    public enum Tier: Int, Comparable, Sendable {
        case fastVerified = 0      // Recent search succeeded in < 2000ms
        case normal = 1            // Unclassified non-VPN or >= 2000ms success
        case requiresVpn = 2       // Unclassified VPN-flagged source
        case recentSlowOrFailed = 3 // Recent timeout or network failure

        public static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct SourceTelemetry: Sendable {
        var tier: Tier
        var latencyMs: Int
    }

    private let lock = NSLock()
    private var telemetry: [String: SourceTelemetry] = [:]

    public init() {}

    public func reset() {
        lock.lock()
        telemetry.removeAll()
        lock.unlock()
    }

    public func recordSuccess(sourceID: String, elapsedMs: Int) {
        let clamped = max(1, min(60_000, elapsedMs))
        let nextTier: Tier = clamped < Self.fastThresholdMs ? .fastVerified : .normal
        lock.lock()
        if let old = telemetry[sourceID] {
            let smoothed = (old.latencyMs + clamped) / 2
            telemetry[sourceID] = SourceTelemetry(tier: smoothed < Self.fastThresholdMs ? .fastVerified : nextTier, latencyMs: smoothed)
        } else {
            telemetry[sourceID] = SourceTelemetry(tier: nextTier, latencyMs: clamped)
        }
        lock.unlock()
    }

    public func recordFailure(sourceID: String, timedOut: Bool) {
        let penaltyMs = timedOut ? 30_000 : 25_000
        lock.lock()
        telemetry[sourceID] = SourceTelemetry(tier: .recentSlowOrFailed, latencyMs: penaltyMs)
        lock.unlock()
    }

    public func tier(for sourceID: String, requiresVpn: Bool) -> Tier {
        lock.lock()
        let recorded = telemetry[sourceID]
        lock.unlock()
        if let recorded {
            return recorded.tier
        }
        return requiresVpn ? .requiresVpn : .normal
    }

    public func estimatedLatencyMs(for sourceID: String, requiresVpn: Bool) -> Int {
        lock.lock()
        let recorded = telemetry[sourceID]
        lock.unlock()
        if let recorded {
            return recorded.latencyMs
        }
        return requiresVpn ? 8_000 : 3_000
    }

    public func timeoutMilliseconds(for sourceID: String, requiresVpn: Bool) -> Int {
        let t = tier(for: sourceID, requiresVpn: requiresVpn)
        switch t {
        case .fastVerified, .normal:
            return Self.defaultTimeoutMs
        case .requiresVpn:
            return 8_500
        case .recentSlowOrFailed:
            return 6_500
        }
    }

    public func sortForDispatch(_ sourceIDs: [String], requiresVpn: (String) -> Bool) -> [String] {
        guard sourceIDs.count > 1 else { return sourceIDs }
        lock.lock()
        let snapshot = telemetry
        lock.unlock()

        struct Entry {
            let id: String
            let index: Int
            let tier: Tier
            let latencyMs: Int
        }
        var entries = [Entry]()
        entries.reserveCapacity(sourceIDs.count)
        for (index, id) in sourceIDs.enumerated() {
            if let rec = snapshot[id] {
                entries.append(Entry(id: id, index: index, tier: rec.tier, latencyMs: rec.latencyMs))
            } else {
                let vpn = requiresVpn(id)
                entries.append(Entry(
                    id: id,
                    index: index,
                    tier: vpn ? .requiresVpn : .normal,
                    latencyMs: vpn ? 8_000 : 3_000
                ))
            }
        }
        entries.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.latencyMs != b.latencyMs { return a.latencyMs < b.latencyMs }
            return a.index < b.index
        }
        return entries.map(\.id)
    }
}
