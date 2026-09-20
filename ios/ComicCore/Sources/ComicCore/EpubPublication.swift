import Foundation

public enum EpubError: Error, LocalizedError, Equatable {
    case invalid(String)
    case invalidXML(String)
    case unsafeXML
    case limitExceeded(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): return "无效的 EPUB：\(reason)"
        case .invalidXML(let path): return "EPUB XML 格式损坏：\(path)"
        case .unsafeXML: return "EPUB XML 包含不安全的 DOCTYPE 或 ENTITY 声明"
        case .limitExceeded(let reason): return "EPUB 超出安全限制：\(reason)"
        }
    }
}

public struct EpubPublication: Codable, Equatable, Sendable {
    public struct ManifestItem: Codable, Equatable, Sendable {
        public let id: String
        public let href: String
        public let mediaType: String
        public let properties: String
    }
    public struct SpineItem: Codable, Equatable, Sendable {
        public let idref: String
        public let fullZipPath: String
        public let mediaType: String
        public let linear: Bool
        public let resolvedImageEntry: String?
    }
    public struct NavItem: Codable, Equatable, Sendable {
        public let title: String
        public let href: String
        public let spineIndex: Int
        public let children: [NavItem]
    }
    public struct ChapterRange: Codable, Equatable, Sendable {
        public let title: String
        public let startIndex: Int
        public let endIndex: Int
    }

    public let title: String
    public let author: String
    public let description: String
    public let language: String
    public let opfPath: String
    public let coverEntry: String?
    public let manifest: [ManifestItem]
    public let spine: [SpineItem]
    public let navItems: [NavItem]
    public let isFixedLayout: Bool
    public let isPurePictureEpub: Bool
    public let isReflowableText: Bool
    public let hasDrm: Bool
    public let hasFontObfuscation: Bool
    public let unsupportedReason: String?

    public func chapterRanges(overrideTitle: String? = nil) throws -> [ChapterRange] {
        try Task.checkCancellation()
        guard !hasDrm else { throw EpubError.invalid("该 EPUB 受到 DRM 加密保护，暂不支持阅读") }
        guard !spine.isEmpty else { throw EpubError.invalid("EPUB 没有可阅读的正文页面") }
        let override = SearchRules.trim(overrideTitle ?? "")
        if !override.isEmpty { return [ChapterRange(title: override, startIndex: 0, endIndex: spine.count)] }

        // Iterative flattening also bounds stack usage for publications decoded from persisted JSON.
        var mapped: [NavItem] = [], pending = Array(navItems.reversed())
        while let item = pending.popLast() {
            try Task.checkCancellation()
            if item.spineIndex >= 0 { mapped.append(item) }
            pending.append(contentsOf: item.children.reversed())
        }
        mapped = mapped.enumerated().sorted {
            $0.element.spineIndex == $1.element.spineIndex ? $0.offset < $1.offset : $0.element.spineIndex < $1.element.spineIndex
        }.map(\.element)
        // Java Pattern's default \s and \d are ASCII; ICU's defaults are broader.
        let pattern = #"^(?:(?:第[ \t\n\x0B\f\r]*)?[0-9]+[ \t\n\x0B\f\r]*[页頁]|(?:page|p)[ \t\n\x0B\f\r]*#?[ \t\n\x0B\f\r]*[0-9]+(?:\.(?:xhtml|html|jpg|jpeg|png))?|[0-9]+)$"#
        let pages = mapped.filter { SearchRules.trim($0.title).range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }.count
        let pseudoPages = !mapped.isEmpty && (pages * 2 >= mapped.count || (Double(mapped.count) >= Double(spine.count) * 0.7 && pages >= 2))
        let bookTitle = SearchRules.trim(title)
        if pseudoPages { return [ChapterRange(title: bookTitle.isEmpty ? "全本" : bookTitle, startIndex: 0, endIndex: spine.count)] }
        var boundaries: [(String, Int)] = []
        for item in mapped where item.spineIndex < spine.count {
            if boundaries.last?.1 != item.spineIndex { boundaries.append((item.title, item.spineIndex)) }
        }
        if boundaries.isEmpty { boundaries = [(bookTitle.isEmpty ? "全 1 卷" : bookTitle, 0)] }
        else if boundaries[0].1 > 0 { boundaries.insert(("封面与序言", 0), at: 0) }
        return boundaries.enumerated().map { index, boundary in
            ChapterRange(title: boundary.0, startIndex: boundary.1, endIndex: index + 1 < boundaries.count ? boundaries[index + 1].1 : spine.count)
        }
    }
}
