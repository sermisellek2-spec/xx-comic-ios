import Foundation

public enum DiscoveryBrowseMode: Int, Sendable, Equatable {
    case recommend = 0
    case category = 1
}

public enum DiscoveryFooterState: Equatable, Sendable {
    case none
    case loading
    case loadMore
    case end
    case errorRetry
    case verifyRequired
}

public enum DiscoveryHeaderActionType: Int, Equatable, Sendable {
    case none = 0
    case verify = 1
    case singleSearch = 2
}

public struct DiscoverySourceMeta: Equatable, Sendable {
    public let id: String
    public let name: String
    public let requiresVpn: Bool
    public let hasExactMatch: Bool

    public init(id: String, name: String, requiresVpn: Bool, hasExactMatch: Bool) {
        self.id = id
        self.name = name
        self.requiresVpn = requiresVpn
        self.hasExactMatch = hasExactMatch
    }
}

public struct DiscoverySectionHeaderRow: Equatable, Sendable {
    public let sourceId: String
    public let title: String
    public let requiresVpn: Bool
    public let hasExactMatch: Bool
    public let countBadge: String
    public let actionLabel: String
    public let actionType: DiscoveryHeaderActionType

    public init(
        sourceId: String,
        title: String,
        requiresVpn: Bool,
        hasExactMatch: Bool,
        countBadge: String,
        actionLabel: String,
        actionType: DiscoveryHeaderActionType
    ) {
        self.sourceId = sourceId
        self.title = title
        self.requiresVpn = requiresVpn
        self.hasExactMatch = hasExactMatch
        self.countBadge = countBadge
        self.actionLabel = actionLabel
        self.actionType = actionType
    }
}

public struct DiscoveryPosterRow: Equatable, Sendable {
    public let sectionSourceId: String
    public let comic: ComicSummary
    public let remark: String

    public init(comic: ComicSummary) {
        self.init(sectionSourceId: comic.sourceId, comic: comic)
    }

    public init(sectionSourceId: String, comic: ComicSummary) {
        self.sectionSourceId = sectionSourceId
        self.comic = comic
        self.remark = DiscoveryModels.compactRemark(comic)
    }

    /// Collision-free item identity key combining source and comic ID.
    /// Empty when `comic.comicId` is missing so invalid entries never alias.
    public var stableItemKey: String {
        guard !comic.comicId.isEmpty else { return "" }
        let source = !comic.sourceId.isEmpty ? comic.sourceId : sectionSourceId
        return "\(source)\u{0000}\(comic.comicId)"
    }
}

public enum DiscoveryRowItem: Equatable, Sendable {
    case sectionHeader(DiscoverySectionHeaderRow)
    case poster(DiscoveryPosterRow)
    case footer(DiscoveryFooterState)
    case fullCustom(String)
}

/// Pure state and display-row models for the Discovery page.
public enum DiscoveryModels {
    /// Maximum items rendered beneath each source section in Global Search.
    public static let globalMaxItemsPerSource = 6

    /// Sentinel source ID representing the default aggregated "全部 (N)" view in Global Search.
    public static let globalAllSourcesId = ""

    /// Maximum filter groups rendered inline in Category mode before collapsing remaining groups into the sheet.
    public static let inlineFilterMaxGroups = 3
    /// Filter groups with more options than this threshold expose a quick-expand sheet trigger.
    public static let inlineFilterExpandThreshold = 16
    /// Maximum inline chips rendered per horizontal filter row before delegating the rest to the expand sheet.
    public static let inlineFilterMaxInlineChips = 32

    /// Caps a source's global search result list to at most `globalMaxItemsPerSource` (6) items.
    public static func capGlobalItems(_ items: [ComicSummary]?) -> [ComicSummary] {
        guard let items, !items.isEmpty else { return [] }
        return Array(items.prefix(globalMaxItemsPerSource))
    }

    /// Extracts a concise bottom-right cover badge string (latest chapter or status).
    public static func compactRemark(_ item: ComicSummary?) -> String {
        guard let item else { return "" }
        let latest = trimClean(item.latestChapter)
        if !latest.isEmpty {
            return latest
        }
        var sub = trimClean(item.subtitle)
        if sub.isEmpty || sub == "暂无" {
            return ""
        }
        if let newlineIdx = sub.firstIndex(of: "\n") {
            sub = String(sub[..<newlineIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if sub.utf16.count > 18 {
            if let dotRange = sub.range(of: " · ") {
                let offset = sub.utf16.distance(from: sub.startIndex, to: dotRange.lowerBound)
                if offset > 0 && offset <= 18 {
                    sub = String(sub[..<dotRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return sub
                }
            }
            if let slashIdx = sub.firstIndex(of: "/") {
                let offset = sub.utf16.distance(from: sub.startIndex, to: slashIdx)
                if offset > 0 && offset <= 18 {
                    sub = String(sub[..<slashIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return sub
    }

    public static func shouldShowFilterExpand(_ group: SourceFilterGroup?) -> Bool {
        guard let group else { return false }
        return group.options.count > inlineFilterExpandThreshold
    }

    /// Returns the indices of filter groups to display inline in Category mode:
    /// caps default inline rows at 3 while always keeping any group beyond the cap with an active non-default filter.
    public static func visibleInlineGroupIndices(
        _ groups: [SourceFilterGroup],
        selectedFilters: [String: String]
    ) -> [Int] {
        guard !groups.isEmpty else { return [] }
        var indices: [Int] = []
        var validCount = 0
        for (i, group) in groups.enumerated() {
            if group.options.isEmpty { continue }
            if validCount < inlineFilterMaxGroups || isGroupNonDefault(group, selectedFilters: selectedFilters) {
                indices.append(i)
            }
            validCount += 1
        }
        return indices
    }

    /// Counts valid non-empty filter groups for badge display.
    public static func countValidFilterGroups(_ groups: [SourceFilterGroup]) -> Int {
        groups.reduce(0) { $0 + ($1.options.isEmpty ? 0 : 1) }
    }

    /// Returns the 1-based drawer tab index of the first valid filter group collapsed out of inline view.
    public static func firstCollapsedFilterTab(
        _ groups: [SourceFilterGroup],
        selectedFilters: [String: String]
    ) -> Int {
        guard !groups.isEmpty else { return 1 }
        let visible = Set(visibleInlineGroupIndices(groups, selectedFilters: selectedFilters))
        for (i, group) in groups.enumerated() {
            if group.options.isEmpty { continue }
            if !visible.contains(i) {
                return i + 1
            }
        }
        return 1
    }

    private static func isGroupNonDefault(
        _ group: SourceFilterGroup,
        selectedFilters: [String: String]
    ) -> Bool {
        guard !group.options.isEmpty else { return false }
        guard let val = selectedFilters[group.key], !val.isEmpty, val.lowercased() != "all" else {
            return false
        }
        let firstVal = group.options[0].value
        return val != firstVal
    }

    /// Builds inline filter options while guaranteeing the currently selected option is always present
    /// even when a source defines 100+ tag options.
    public static func inlineOptionsForGroup(
        _ group: SourceFilterGroup,
        selectedValue: String?
    ) -> [SourceFilterOption] {
        guard !group.options.isEmpty else { return [] }
        if group.options.count <= inlineFilterMaxInlineChips {
            return group.options
        }
        var slice = Array(group.options.prefix(inlineFilterMaxInlineChips))
        let sel = selectedValue ?? ""
        var foundSelected = sel.isEmpty
        if !foundSelected {
            foundSelected = slice.contains { $0.value == sel }
        }
        if !foundSelected {
            for i in inlineFilterMaxInlineChips..<group.options.count {
                let opt = group.options[i]
                if opt.value == sel {
                    slice.insert(opt, at: 1)
                    break
                }
            }
        }
        return slice
    }

    /// Builds virtualized rows for Global Search ("全部" aggregated view or single-source chip filter),
    /// strictly enforcing `<= 6` items per source.
    public static func buildGlobalRows(
        selectedSourceId: String?,
        orderedHitSources: [DiscoverySourceMeta],
        verificationSources: [DiscoverySourceMeta],
        resultsBySource: [String: [ComicSummary]],
        query: String
    ) -> [DiscoveryRowItem] {
        var rows: [DiscoveryRowItem] = []
        let sel = selectedSourceId ?? globalAllSourcesId

        if sel == globalAllSourcesId {
            for meta in orderedHitSources {
                let capped = capGlobalItems(resultsBySource[meta.id])
                if capped.isEmpty { continue }
                let exact = meta.hasExactMatch || SearchRules.hasExact(capped, query: query)
                rows.append(.sectionHeader(DiscoverySectionHeaderRow(
                    sourceId: meta.id,
                    title: meta.name,
                    requiresVpn: meta.requiresVpn,
                    hasExactMatch: exact,
                    countBadge: "\(capped.count) 部",
                    actionLabel: "单站搜索 ›",
                    actionType: .singleSearch
                )))
                for item in capped {
                    rows.append(.poster(DiscoveryPosterRow(sectionSourceId: meta.id, comic: item)))
                }
            }
            for verifyMeta in verificationSources {
                if let raw = resultsBySource[verifyMeta.id], !raw.isEmpty { continue }
                rows.append(.sectionHeader(DiscoverySectionHeaderRow(
                    sourceId: verifyMeta.id,
                    title: verifyMeta.name,
                    requiresVpn: verifyMeta.requiresVpn,
                    hasExactMatch: false,
                    countBadge: "需验证",
                    actionLabel: "去验证 ›",
                    actionType: .verify
                )))
            }
            return rows
        }

        // Single-source chip filter mode
        let capped = capGlobalItems(resultsBySource[sel])
        if capped.isEmpty {
            return rows
        }
        let matchedMeta = orderedHitSources.first { $0.id == sel }
        let name = matchedMeta?.name ?? sel
        let vpn = matchedMeta?.requiresVpn ?? false
        let exact = (matchedMeta?.hasExactMatch ?? false) || SearchRules.hasExact(capped, query: query)
        rows.append(.sectionHeader(DiscoverySectionHeaderRow(
            sourceId: sel,
            title: name,
            requiresVpn: vpn,
            hasExactMatch: exact,
            countBadge: "\(capped.count) 部",
            actionLabel: "单站搜索 ›",
            actionType: .singleSearch
        )))
        for item in capped {
            rows.append(.poster(DiscoveryPosterRow(sectionSourceId: sel, comic: item)))
        }
        return rows
    }

    /// Strictly compares every display-relevant field of two `ComicSummary` objects.
    public static func areComicsContentEqual(_ a: ComicSummary?, _ b: ComicSummary?) -> Bool {
        a == b
    }

    public static func totalDisplayedGlobalHits(
        orderedHitSources: [DiscoverySourceMeta],
        resultsBySource: [String: [ComicSummary]]
    ) -> Int {
        var sum = 0
        for meta in orderedHitSources {
            if let list = resultsBySource[meta.id] {
                sum += min(globalMaxItemsPerSource, list.count)
            }
        }
        return sum
    }

    public static func shouldExitDiscoverySearchOnBack(
        currentTab: Int,
        hasBlockingOrSubpage: Bool,
        searchHistoryMode: Bool,
        globalSearchMode: Bool,
        singleSearchQuery: String?
    ) -> Bool {
        if currentTab != 1 || hasBlockingOrSubpage { return false }
        if searchHistoryMode || globalSearchMode { return true }
        return !SearchRules.trim(singleSearchQuery ?? "").isEmpty
    }

    private static func trimClean(_ value: String?) -> String {
        guard let value else { return "" }
        return SearchRules.trim(value.replacingOccurrences(of: "\r", with: " "))
    }
}
