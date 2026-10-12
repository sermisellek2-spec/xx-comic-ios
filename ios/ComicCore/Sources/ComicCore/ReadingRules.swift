import Foundation

public struct ReaderPosition: Codable, Equatable, Sendable {
    public let imageIndex: Int
    public let offset: Double
    public let atEnd: Bool
    public let linkedPageID: String?
    public let linkedTailID: String?

    public init(imageIndex: Int, offset: Double, atEnd: Bool = false, linkedPageID: String? = nil, linkedTailID: String? = nil) {
        self.imageIndex = max(0, imageIndex)
        self.offset = offset.isNaN ? 0 : max(0, min(1, offset))
        self.atEnd = atEnd
        self.linkedPageID = linkedPageID.flatMap { UUID(uuidString: $0) != nil ? $0 : nil }
        self.linkedTailID = linkedTailID.flatMap { UUID(uuidString: $0) != nil ? $0 : nil }
    }

    public func index(for count: Int) -> Int {
        min(max(0, count > 0 ? count - 1 : 0), imageIndex)
    }

    public func index(in imageURLs: [String]) -> Int {
        if let linkedPageID, let retained = imageURLs.firstIndex(where: {
            guard let url = URL(string: $0), let identity = try? LinkedFolderPageURL.parse(url) else { return false }
            return identity.pageID == linkedPageID
        }) { return retained }
        return index(for: imageURLs.count)
    }

    public static func linkedIdentity(in imageURL: String) -> String? {
        guard let url = URL(string: imageURL) else { return nil }
        return (try? LinkedFolderPageURL.parse(url))?.pageID
    }

    public func isAtEnd(in imageURLs: [String]) -> Bool {
        guard atEnd else { return false }
        guard let linkedTailID else { return true }
        return imageURLs.last.flatMap(Self.linkedIdentity(in:)) == linkedTailID
    }

    public func legacyProgress(count: Int) -> Int {
        guard count > 0 else { return 0 }
        if atEnd { return 10000 }
        return max(0, min(10000, Int(((Double(index(for: count)) + offset) * 10000 / Double(count)).rounded())))
    }

    public static func fromLegacy(_ progress: Int, count: Int) -> ReaderPosition {
        guard count > 0 else { return ReaderPosition(imageIndex: 0, offset: 0) }
        // Handle completion before converting Double(count) back to Int.
        if progress >= 10000 { return ReaderPosition(imageIndex: count - 1, offset: 0, atEnd: true) }
        let row = Double(max(0, progress)) * Double(count) / 10000
        let index = min(count - 1, Int(floor(row)))
        return ReaderPosition(imageIndex: index, offset: row - Double(index))
    }

    private enum CodingKeys: String, CodingKey { case imageIndex, offset, atEnd, linkedPageID, linkedTailID }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(imageIndex: try values.decode(Int.self, forKey: .imageIndex),
                  offset: try values.decode(Double.self, forKey: .offset),
                  atEnd: try values.decode(Bool.self, forKey: .atEnd),
                  linkedPageID: try values.decodeIfPresent(String.self, forKey: .linkedPageID),
                  linkedTailID: try values.decodeIfPresent(String.self, forKey: .linkedTailID))
    }
}

public enum ReaderTapAction: Equatable, Sendable { case none, toggleControls, move(Int) }

public enum ReaderNavigation {
    public static func isEdgeTapNavigationPermitted(layout: ReaderLayout, mode: ReaderTurnMode) -> Bool {
        layout == .paged && mode != .buttons
    }

    public static func tapAction(x: Double, y: Double, controlsVisible: Bool, layout: ReaderLayout,
                                 mode: ReaderTurnMode, zoomed: Bool,
                                 direction: ReaderPageDirection = .leftToRight) -> ReaderTapAction {
        if controlsVisible { return .toggleControls }
        guard x.isFinite, y.isFinite else { return .none }
        let activeY = layout == .paged ? (y >= 0.25 && y <= 0.75) : (y > 0.25 && y < 0.75)
        guard activeY else { return .none }
        let allowsTap = isEdgeTapNavigationPermitted(layout: layout, mode: mode)
        if allowsTap && !zoomed && (x < 0.28 || x > 0.72) {
            return .move(tapDelta(leftSide: x < 0.28, direction: direction))
        }
        return .toggleControls
    }
    public static func tapDelta(leftSide: Bool, direction: ReaderPageDirection = .leftToRight) -> Int {
        let delta = leftSide ? -1 : 1
        return direction == .rightToLeft ? -delta : delta
    }
    public static func swipeDelta(dx: Double, direction: ReaderPageDirection = .leftToRight) -> Int {
        let delta = dx < 0 ? 1 : -1
        return direction == .rightToLeft ? -delta : delta
    }
    public static func crossesChapter(index: Int, count: Int, delta: Int) -> Bool {
        guard count > 0 else { return false }
        let (next, overflow) = index.addingReportingOverflow(delta)
        return overflow || next < 0 || next >= count
    }
}

public enum HistoryProgressLabel {
    public static func label(savedIndex: Int, titles: [String?]) -> String {
        if savedIndex < 0 { return "有阅读记录" }
        if !titles.isEmpty && savedIndex >= titles.count { return "目录已更新 · 点击继续" }
        if titles.indices.contains(savedIndex), let title = titles[savedIndex] {
            let trimmed = SearchRules.trim(title)
            if !trimmed.isEmpty { return "上次看到 · " + trimmed }
        }
        let (chapter, overflow) = savedIndex.addingReportingOverflow(1)
        return overflow ? "目录已更新 · 点击继续" : "上次看到 第 \(chapter) 章"
    }
}

public enum ReaderTheme: Int, CaseIterable, Codable, Sendable {
    case system = 0, dark = 1, light = 2
    public func isDark(systemDark: Bool) -> Bool {
        switch self { case .system: return systemDark; case .dark: return true; case .light: return false }
    }
}
