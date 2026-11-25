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

    private static let volatileQueryParams: Set<String> = [
        "auth", "token", "access_token", "auth_token", "refresh_token",
        "sign", "sig", "signature", "timestamp", "ts", "_t", "_",
        "nonce", "expires", "expire", "exp", "session", "session_id",
        "jsessionid", "phpsessid", "utm_source", "utm_medium",
        "utm_campaign", "utm_term", "utm_content", "fbclid", "gclid",
        "spm", "rnd", "rand", "cache", "cb"
    ]

    private static let cnEpisodePattern = try? NSRegularExpression(
        pattern: #"第\s*(\d+)(?:\.\d+)?\s*[话話章回集幕]"#
    )
    private static let enEpisodePattern = try? NSRegularExpression(
        pattern: #"(?i)(?:\b(?:chapter|chap|ch|episode|ep)\.?\s*|#\s*)(\d+)(?:\.\d+)?(?!\d)"#
    )
    private static let bareEpisodeSuffixPattern = try? NSRegularExpression(
        pattern: #"(?<!\d)(\d+)(?:\.\d+)?\s*[话話章回集幕]"#
    )
    private static let volumePattern = try? NSRegularExpression(
        pattern: #"(?i)(?:第\s*(\d+)(?:\.\d+)?\s*[卷捲册]|\b(?:vol|volume)\.?\s*(\d+)(?:\.\d+)?(?!\d))"#
    )
    private static let pureNumberPattern = try? NSRegularExpression(
        pattern: #"^\s*(\d+)\s*$"#
    )
    private static let yearOrDatePrefixPattern = try? NSRegularExpression(
        pattern: #"^\s*(?:19\d{2}|20\d{2})(?:\s*(?:年|新年|春节|元旦|国庆|中秋|情人节|圣诞|万圣|特辑|番外|特别篇|纪念|贺图)|[-/.]\d{1,2}(?:[-/.]\d{1,2})?)"#
    )
    private static let leadingNumberPattern = try? NSRegularExpression(
        pattern: #"^\s*(\d+)(?:\.\d+)?(?:\s+|[-–—_:：\.]+)(.+)$"#
    )

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
        var seenIds = Set<String>()
        var ids: [String] = []
        var lastId = ""
        var lastName = ""
        var maxNumber: Int64?
        for c in chapters {
            let id = canonicalChapterId(c)
            if !id.isEmpty {
                if seenIds.insert(id).inserted {
                    ids.append(id)
                }
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
        var base = cleaned
        var query: String?
        if let queryIdx = cleaned.firstIndex(of: "?") {
            base = String(cleaned[..<queryIdx])
            query = String(cleaned[cleaned.index(after: queryIdx)...])
        }
        if base.hasPrefix("http://") || base.hasPrefix("https://") {
            if let schemeEnd = base.range(of: "://") {
                if let slash = base[schemeEnd.upperBound...].firstIndex(of: "/") {
                    base = String(base[slash...])
                } else {
                    base = "/"
                }
            }
        }
        if let query, !query.isEmpty {
            var preserved: [String] = []
            for param in query.components(separatedBy: "&") {
                if param.isEmpty { continue }
                let eqIdx = param.firstIndex(of: "=")
                let rawKey = eqIdx.map { String(param[..<$0]) } ?? param
                let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if key.isEmpty || volatileQueryParams.contains(key) {
                    continue
                }
                if key == "t", let eqIdx {
                    let val = String(param[param.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if val.isEmpty || val.range(of: #"^\d{10,}$"#, options: .regularExpression) != nil {
                        continue
                    }
                }
                preserved.append(param)
            }
            if !preserved.isEmpty {
                preserved.sort()
                return base + "?" + preserved.joined(separator: "&")
            }
        }
        return base
    }

    public static func extractChapterNumber(_ title: String) -> Int64? {
        let normalized = toHalfWidthDigits(title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if let match = matchFirstNumber(cnEpisodePattern, text: normalized, group: 1) { return match }
        if let match = matchFirstNumber(enEpisodePattern, text: normalized, group: 1) { return match }
        if let match = matchFirstNumber(bareEpisodeSuffixPattern, text: normalized, group: 1) { return match }
        if let match = matchFirstGroup(volumePattern, text: normalized, group1: 1, group2: 2) { return match }
        if let match = matchFirstNumber(pureNumberPattern, text: normalized, group: 1) { return match }

        let fullRange = NSRange(location: 0, length: (normalized as NSString).length)
        let isYearOrDate = yearOrDatePrefixPattern?.firstMatch(in: normalized, options: [], range: fullRange) != nil
        if !isYearOrDate {
            if let match = matchFirstNumber(leadingNumberPattern, text: normalized, group: 1) { return match }
        }
        return nil
    }

    private static func matchFirstNumber(_ regex: NSRegularExpression?, text: String, group: Int) -> Int64? {
        guard let regex else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              group < match.numberOfRanges else {
            return nil
        }
        let r = match.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return Int64(ns.substring(with: r))
    }

    private static func matchFirstGroup(_ regex: NSRegularExpression?, text: String, group1: Int, group2: Int) -> Int64? {
        guard let regex else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        if group1 < match.numberOfRanges {
            let r1 = match.range(at: group1)
            if r1.location != NSNotFound {
                return Int64(ns.substring(with: r1))
            }
        }
        if group2 < match.numberOfRanges {
            let r2 = match.range(at: group2)
            if r2.location != NSNotFound {
                return Int64(ns.substring(with: r2))
            }
        }
        return nil
    }

    private static func toHalfWidthDigits(_ input: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(input.unicodeScalars.count)
        for scalar in input.unicodeScalars {
            if scalar.value >= 0xFF10 && scalar.value <= 0xFF19,
               let digit = UnicodeScalar(0x30 + (scalar.value - 0xFF10)) {
                scalars.append(digit)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
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
