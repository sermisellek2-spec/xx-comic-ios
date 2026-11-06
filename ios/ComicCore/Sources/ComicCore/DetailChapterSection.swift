import Foundation

/// Model representing a chapter range segment for inline preview and quick navigation.
public struct DetailChapterSegment: Equatable, Sendable, Codable {
    public let index: Int
    public let label: String
    public let chapterIndices: [Int]

    public init(index: Int, label: String, chapterIndices: [Int]) {
        self.index = index
        self.label = label
        self.chapterIndices = chapterIndices
    }
}

/// Pure computation and layout algorithms for chapter preview and segmentation.
/// Ported from Android 2.0.46's `DetailChapterSectionView`.
public enum DetailChapterSection {
    public static let previewLimit: Int = 12
    public static let maxExpandedCells: Int = 60

    public typealias Segment = DetailChapterSegment

    /// Calculates adaptive segment size to keep pill tabs bounded (O(1) layout).
    public static func calculateSegmentSize(_ totalChapters: Int) -> Int {
        if totalChapters <= 600 { return 60 }
        if totalChapters <= 2400 { return 120 }
        let raw = (totalChapters + 23) / 24
        return max(120, ((raw + 59) / 60) * 60)
    }

    /// Builds segmented chapter ranges in either ascending or descending order.
    public static func buildSegments(totalChapters: Int, isDesc: Bool) -> [Segment] {
        if totalChapters <= 0 { return [] }
        let segmentSize = calculateSegmentSize(totalChapters)
        var segments: [Segment] = []
        let count = (totalChapters + segmentSize - 1) / segmentSize
        for s in 0..<count {
            let offset = s * segmentSize
            let len = min(segmentSize, totalChapters - offset)
            var indices: [Int] = []
            indices.reserveCapacity(len)
            let label: String
            if !isDesc {
                let startIdx = offset
                let endIdx = offset + len - 1
                for i in startIdx...endIdx {
                    indices.append(i)
                }
                label = "\(startIdx + 1)-\(endIdx + 1)"
            } else {
                let highIdx = totalChapters - 1 - offset
                let lowIdx = highIdx - len + 1
                for i in stride(from: highIdx, through: lowIdx, by: -1) {
                    indices.append(i)
                }
                label = "\(highIdx + 1)-\(lowIdx + 1)"
            }
            segments.append(Segment(index: s, label: label, chapterIndices: indices))
        }
        return segments
    }

    /// Selects the segment index containing the currently reading chapter, or 0.
    public static func selectDefaultSegmentIndex(
        segments: [Segment],
        currentChapterIndex: Int,
        hasCurrent: Bool
    ) -> Int {
        if segments.isEmpty { return 0 }
        if hasCurrent && currentChapterIndex >= 0 {
            for (i, seg) in segments.enumerated() {
                if seg.chapterIndices.contains(currentChapterIndex) {
                    return i
                }
            }
        }
        return 0
    }

    /// Calculates the visible window of chapters centered around the current reading chapter.
    public static func selectVisibleWindow(
        segmentIndices: [Int],
        currentChapterIndex: Int,
        hasCurrent: Bool,
        expanded: Bool,
        columns: Int
    ) -> [Int] {
        if segmentIndices.isEmpty { return [] }
        let limit = expanded ? maxExpandedCells : previewLimit
        if segmentIndices.count <= limit {
            return segmentIndices
        }
        let pos = hasCurrent ? (segmentIndices.firstIndex(of: currentChapterIndex) ?? -1) : -1
        if pos < 0 {
            return Array(segmentIndices.prefix(limit))
        }
        let safeCols = max(1, columns)
        let targetRow = pos / safeCols
        let windowRows = max(1, limit / safeCols)
        let startRow = max(0, targetRow - (windowRows - 1) / 2)
        var startIdx = startRow * safeCols
        if startIdx + limit > segmentIndices.count {
            startIdx = max(0, segmentIndices.count - limit)
        }
        if pos < startIdx {
            startIdx = pos
        } else if pos >= startIdx + limit {
            startIdx = pos - limit + 1
        }
        let endIdx = min(segmentIndices.count, startIdx + limit)
        return Array(segmentIndices[startIdx..<endIdx])
    }

    /// Cleans and formats a chapter title, falling back to "第 X 话".
    public static func cleanChapterTitle(chapter: Chapter?, index: Int) -> String {
        if let title = chapter?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return "第 \(index + 1) 话"
    }

    /// Cleans and formats a chapter title string, falling back to "第 X 话".
    public static func cleanChapterTitle(title: String?, index: Int) -> String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return "第 \(index + 1) 话"
    }

    /// Compact short chapter label ported from Android 2.0.44 `ChapterSelectionGrid.chapterLabel`.
    public static func chapterLabel(_ oneBased: Int) -> String {
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if oneBased > 0 && oneBased < 10 { return "第\(digits[oneBased])话" }
        if oneBased == 10 { return "第十话" }
        if oneBased > 10 && oneBased < 20 { return "第十\(digits[oneBased - 10])话" }
        if oneBased == 20 { return "第二十话" }
        return "第\(oneBased)话"
    }
}

/// ID and index-based drag/swipe paint selection state machine.
/// Ported from Android 2.0.44's `SwipeChapterSelection.java`.
/// A single drag stroke maintains an invariant direction (selecting vs deselecting)
/// and can be cancelled with complete atomic rollback.
public final class SwipeChapterSelection {
    public private(set) var available: Set<String>
    public private(set) var selected: Set<String>
    private var visited: Set<String> = []
    private var before: Set<String>?

    public private(set) var isSelecting: Bool = false
    public private(set) var startIndex: Int?
    public private(set) var currentIndex: Int?
    public var disabledIndices: Set<Int> = []

    public init(available: [String], selected: Set<String> = []) {
        self.available = Set(available)
        self.selected = selected.intersection(self.available)
    }

    public init(available: Set<String>, selected: Set<String> = []) {
        self.available = available
        self.selected = selected.intersection(self.available)
    }

    public convenience init(totalCount: Int, disabledIndices: Set<Int> = [], selected: Set<String> = []) {
        let allIds = (0..<totalCount).map(String.init)
        let availableIds = allIds.enumerated().filter { !disabledIndices.contains($0.offset) }.map(\.element)
        self.init(available: availableIds, selected: selected)
        self.disabledIndices = disabledIndices
    }

    public var selecting: Bool { isSelecting }

    public func contains(_ id: String) -> Bool {
        selected.contains(id)
    }

    public func allSelected() -> Bool {
        !available.isEmpty && available.isSubset(of: selected)
    }

    public var count: Int {
        selected.count
    }

    public var availableCount: Int {
        available.count
    }

    public func setSelected(_ newSelected: Set<String>) {
        selected = newSelected.intersection(available)
    }

    @discardableResult
    public func toggle(_ id: String) -> Bool {
        guard available.contains(id) else { return false }
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
        return true
    }

    @discardableResult
    public func begin(_ id: String) -> Bool {
        guard available.contains(id), before == nil else { return false }
        before = selected
        isSelecting = !selected.contains(id)
        visited.removeAll()
        visit(id)
        return true
    }

    @discardableResult
    public func visit(_ id: String) -> Bool {
        guard before != nil, available.contains(id), visited.insert(id).inserted else { return false }
        if isSelecting {
            return selected.insert(id).inserted
        } else {
            return selected.remove(id) != nil
        }
    }

    public func finish() {
        before = nil
        visited.removeAll()
        startIndex = nil
        currentIndex = nil
    }

    @discardableResult
    public func cancel() -> Bool {
        guard let previous = before else { return false }
        let changed = (selected != previous)
        selected = previous
        finish()
        return changed
    }

    public func toggleAll() {
        finish()
        if allSelected() {
            selected.removeAll()
        } else {
            selected = available
        }
    }

    // MARK: - Index-Based Drag Selection Support

    @discardableResult
    public func beginIndex(_ index: Int, orderedIds: [String]) -> Bool {
        guard index >= 0, index < orderedIds.count else { return false }
        let id = orderedIds[index]
        guard !disabledIndices.contains(index), available.contains(id), before == nil else { return false }
        startIndex = index
        currentIndex = index
        before = selected
        isSelecting = !selected.contains(id)
        visited.removeAll()
        visit(id)
        return true
    }

    @discardableResult
    public func visitIndex(_ index: Int, orderedIds: [String]) -> Bool {
        guard index >= 0, index < orderedIds.count, !disabledIndices.contains(index) else { return false }
        currentIndex = index
        let id = orderedIds[index]
        return visit(id)
    }

    @discardableResult
    public func applyRange(from start: Int, to end: Int, orderedIds: [String]) -> Int {
        let lower = min(start, end)
        let upper = max(start, end)
        guard lower >= 0, upper < orderedIds.count else { return 0 }
        var modified = 0
        for i in lower...upper {
            guard !disabledIndices.contains(i) else { continue }
            let id = orderedIds[i]
            if visit(id) {
                modified += 1
            }
        }
        return modified
    }
}
