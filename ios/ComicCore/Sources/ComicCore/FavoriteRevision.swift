import Foundation

public struct FavoriteRevision: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public static let modeChapterSet = "CHAPTER_SET"
    public static let modeLatestChapter = "LATEST_CHAPTER"

    public let formatVersion: Int
    public let mode: String
    public let chapterIds: [String]
    public let latestChapterId: String
    public let latestChapterName: String
    public let chapterNumber: Int64?
    public let chapterCount: Int
    public let timestamp: Int64

    public init(formatVersion: Int = formatVersion,
                mode: String = modeChapterSet,
                chapterIds: [String] = [],
                latestChapterId: String = "",
                latestChapterName: String = "",
                chapterNumber: Int64? = nil,
                chapterCount: Int = 0,
                timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.formatVersion = formatVersion
        self.mode = mode
        self.chapterIds = chapterIds
        self.latestChapterId = latestChapterId
        self.latestChapterName = latestChapterName
        self.chapterNumber = chapterNumber
        self.chapterCount = chapterCount
        self.timestamp = timestamp
    }

    public static func fromChapters(latestChapterName: String?, chapters: [Chapter]?) -> FavoriteRevision {
        let rawLatest = latestChapterName ?? ""
        guard let chapters, !chapters.isEmpty else {
            let number = extractChapterNumber(rawLatest)
            return FavoriteRevision(mode: modeLatestChapter,
                                    chapterIds: [],
                                    latestChapterId: "",
                                    latestChapterName: rawLatest,
                                    chapterNumber: number,
                                    chapterCount: 0)
        }
        var ids: [String] = []
        var lastId = ""
        var lastName = ""
        var maxNumber: Int64?
        for c in chapters {
            let id = canonicalChapterId(c)
            if !id.isEmpty {
                ids.append(id)
                lastId = id
            }
            lastName = c.title
            if let num = extractChapterNumber(c.title) {
                if maxNumber == nil || num > maxNumber! {
                    maxNumber = num
                }
            }
        }
        let resolvedName = rawLatest.isEmpty ? lastName : rawLatest
        if maxNumber == nil {
            maxNumber = extractChapterNumber(resolvedName)
        }
        return FavoriteRevision(mode: modeChapterSet,
                                chapterIds: ids,
                                latestChapterId: lastId,
                                latestChapterName: resolvedName,
                                chapterNumber: maxNumber,
                                chapterCount: ids.count)
    }

    public static func fromDetail(_ detail: ComicDetail?) -> FavoriteRevision? {
        guard let detail else { return nil }
        return fromChapters(latestChapterName: detail.latestChapter, chapters: detail.chapters)
    }

    public static func hasNewChapters(baseline: FavoriteRevision?, candidate: FavoriteRevision?) -> Bool {
        guard let baseline, let candidate else { return false }
        if candidate.mode == modeChapterSet {
            if baseline.mode == modeChapterSet {
                if baseline.chapterIds.isEmpty { return false }
                let baseSet = Set(baseline.chapterIds)
                let newIds = candidate.chapterIds.filter { !baseSet.contains($0) }
                return !newIds.isEmpty
            } else if baseline.mode == modeLatestChapter {
                if let bNum = baseline.chapterNumber, let cNum = candidate.chapterNumber {
                    return cNum > bNum
                }
                return false
            }
        }
        if candidate.mode == modeLatestChapter {
            if let bNum = baseline.chapterNumber, let cNum = candidate.chapterNumber {
                return cNum > bNum
            }
            return false
        }
        return false
    }

    public static func canonicalChapterId(_ chapter: Chapter) -> String {
        let trimmed = chapter.chapterId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return normalizeChapterUrl(chapter.url)
    }

    public static func normalizeChapterUrl(_ url: String) -> String {
        var cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hashIdx = cleaned.firstIndex(of: "#") {
            cleaned = String(cleaned[..<hashIdx])
        }
        if let queryIdx = cleaned.firstIndex(of: "?") {
            let base = String(cleaned[..<queryIdx])
            let query = String(cleaned[cleaned.index(after: queryIdx)...])
            let params = query.components(separatedBy: "&")
            let preserved = params.filter { $0.hasPrefix("section_slot=") || $0.hasPrefix("chapter_slot=") }
            cleaned = preserved.isEmpty ? base : base + "?" + preserved.joined(separator: "&")
        }
        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
            if let schemeEnd = cleaned.range(of: "://") {
                if let slash = cleaned[schemeEnd.upperBound...].firstIndex(of: "/") {
                    cleaned = String(cleaned[slash...])
                }
            }
        }
        return cleaned
    }

    public static func extractChapterNumber(_ title: String) -> Int64? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)"#) else { return nil }
        let ns = title as NSString
        if let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) {
            let str = ns.substring(with: match.range(at: 1))
            return Int64(str)
        }
        return nil
    }
}

public struct FavoriteUpdateState: Codable, Equatable, Sendable {
    public let sourceId: String
    public let comicId: String
    public var pendingUpdate: Bool
    public var observedRevision: FavoriteRevision?
    public var acknowledgedRevision: FavoriteRevision?

    public init(sourceId: String, comicId: String, pendingUpdate: Bool,
                observedRevision: FavoriteRevision?, acknowledgedRevision: FavoriteRevision?) {
        self.sourceId = sourceId
        self.comicId = comicId
        self.pendingUpdate = pendingUpdate
        self.observedRevision = observedRevision
        self.acknowledgedRevision = acknowledgedRevision
    }
}
