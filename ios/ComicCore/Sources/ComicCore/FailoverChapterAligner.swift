import Foundation

/// Shared title normalization, Chinese numeral parsing, and 5-tier 1-to-1 chapter alignment.
public enum FailoverChapterAligner {
    private static let bracketTagsRegex = try! NSRegularExpression(
        pattern: #"\[[^\]]*\]|【[^】]*】|\([^)]*\)|（[^）]*）"#,
        options: []
    )
    private static let whitespaceRegex = try! NSRegularExpression(pattern: #"\s+"#, options: [])
    private static let episodePrefixRegex = try! NSRegularExpression(
        pattern: #"第\s*(\d+(?:\.\d+)?|[零〇一二两三四五六七八九十百千万]+)\s*[话話章回集幕]"#,
        options: []
    )
    private static let englishEpisodeRegex = try! NSRegularExpression(
        pattern: #"(?:chapter|chap|ch|episode|ep)\.?\s*(\d+(?:\.\d+)?)|#\s*(\d+(?:\.\d+)?)"#,
        options: [.caseInsensitive]
    )
    private static let leadingNumberRegex = try! NSRegularExpression(
        pattern: #"^(\d+(?:\.\d+)?)(?:\s|$|[话話章回集幕.\-_:：])"#,
        options: []
    )
    private static let cnStandaloneRegex = try! NSRegularExpression(
        pattern: #"^第?\s*([零〇一二两三四五六七八九十百千万]+)(?:\s|$|[话話章回集幕.])"#,
        options: []
    )
    private static let volumePatternRegex = try! NSRegularExpression(
        pattern: #"第\s*(\d+(?:\.\d+)?|[零〇一二两三四五六七八九十百千万]+)\s*[卷捲册]|vol\.?\s*(\d+(?:\.\d+)?)"#,
        options: [.caseInsensitive]
    )
    private static let extraNumberRegex = try! NSRegularExpression(
        pattern: #"(?:番外|extra|sp|ex)\s*(\d+(?:\.\d+)?)"#,
        options: [.caseInsensitive]
    )

    public static func stripTitleTags(_ title: String?) -> String {
        guard let title else { return "" }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
        let strippedRaw = bracketTagsRegex.stringByReplacingMatches(in: trimmed, options: [], range: fullRange, withTemplate: " ")
        let strippedRange = NSRange(strippedRaw.startIndex..., in: strippedRaw)
        let stripped = whitespaceRegex.stringByReplacingMatches(in: strippedRaw, options: [], range: strippedRange, withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? trimmed : stripped
    }

    public static func titleMatchScore(candidateTitle: String?, targetTitle: String?) -> Int {
        guard let candidateTitle, let targetTitle else { return 0 }
        let candTrim = candidateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTrim = targetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if candTrim.isEmpty || targetTrim.isEmpty { return 0 }
        let direct = SearchRules.calculateMatchScore(title: candTrim, query: targetTrim)
        let candStripped = stripTitleTags(candTrim)
        let targetStripped = stripTitleTags(targetTrim)
        let strippedScore = SearchRules.calculateMatchScore(title: candStripped, query: targetStripped)
        let crossA = SearchRules.calculateMatchScore(title: candStripped, query: targetTrim)
        let crossB = SearchRules.calculateMatchScore(title: candTrim, query: targetStripped)
        return max(max(direct, strippedScore), max(crossA, crossB))
    }

    public static func normalizeChapterTitle(_ title: String?) -> String {
        guard let title else { return "" }
        var s = toHalfWidthDigitsAndAscii(stripTitleTags(title))
        s = s.replacingOccurrences(of: "話", with: "话").replacingOccurrences(of: "捲", with: "卷")
        s = s.lowercased()
        let range = NSRange(s.startIndex..., in: s)
        s = whitespaceRegex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        return String(s.filter { $0.isLetter || $0.isNumber })
    }

    public static func extractChapterKey(_ title: String?) -> String {
        guard let title else { return "" }
        var normalized = toHalfWidthDigitsAndAscii(stripTitleTags(title))
        normalized = normalized
            .replacingOccurrences(of: "話", with: "话")
            .replacingOccurrences(of: "捲", with: "卷")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "" }

        if let raw = firstCapture(episodePrefixRegex, in: normalized) {
            let num = canonicalNumberToken(raw)
            if !num.isEmpty { return "ep:" + num }
        }
        if let raw = firstCapture(englishEpisodeRegex, in: normalized) {
            let num = canonicalNumberToken(raw)
            if !num.isEmpty { return "ep:" + num }
        }
        if let raw = firstCapture(leadingNumberRegex, in: normalized) {
            let num = canonicalNumberToken(raw)
            if !num.isEmpty { return "ep:" + num }
        }
        if let raw = firstCapture(cnStandaloneRegex, in: normalized) {
            let num = canonicalNumberToken(raw)
            if !num.isEmpty { return "ep:" + num }
        }
        if let raw = firstCapture(volumePatternRegex, in: normalized) {
            let num = canonicalNumberToken(raw)
            if !num.isEmpty { return "vol:" + num }
        }
        if let raw = firstCapture(extraNumberRegex, in: normalized) {
            let num = canonicalNumberToken(raw)
            if !num.isEmpty { return "sp:extra:" + num }
        }

        let lower = normalized.lowercased()
        if lower.contains("序章") || lower.contains("楔子") || lower == "序" || lower.contains("prologue") {
            return "sp:prologue"
        }
        if lower.contains("最终话")
            || lower.contains("最终回")
            || lower.contains("大结局")
            || lower.contains("完结话")
            || lower == "完结" {
            return "sp:finale"
        }
        if lower.contains("番外") || lower.contains("extra") || lower == "sp" {
            return "sp:extra"
        }
        return ""
    }

    public static func parseChineseNumber(_ raw: String?) -> Int64 {
        guard let raw, !raw.isEmpty else { return -1 }
        let scalars = Array(raw)
        let hasMultiplier = scalars.contains { $0 == "十" || $0 == "百" || $0 == "千" || $0 == "万" }
        if !hasMultiplier {
            var val: Int64 = 0
            for c in scalars {
                let d = chineseDigit(c)
                if d < 0 { return -1 }
                val = val * 10 + Int64(d)
            }
            return val
        }
        var total: Int64 = 0
        var section: Int64 = 0
        var current: Int64 = 0
        var seenDigit = false
        for c in scalars {
            let d = chineseDigit(c)
            if d >= 0 {
                current = Int64(d)
                seenDigit = true
            } else {
                let unit = chineseUnit(c)
                if unit < 0 { return -1 }
                if unit == 10000 {
                    section = (section + (seenDigit ? current : 0)) * unit
                    total += section
                    section = 0
                    current = 0
                    seenDigit = false
                } else {
                    var factor = seenDigit ? current : (unit == 10 ? 1 : 0)
                    if factor == 0 && !seenDigit {
                        factor = 1
                    }
                    section += factor * unit
                    current = 0
                    seenDigit = false
                }
            }
        }
        return total + section + (seenDigit ? current : 0)
    }

    public static func alignChapters(references: [Chapter], candidates: [Chapter]) -> [Chapter] {
        guard !candidates.isEmpty else { return [] }
        guard !references.isEmpty else { return candidates }

        let refs = references.map(Signature.init)
        let cands = candidates.map(Signature.init)
        var matchedRefForCand = [Int](repeating: -1, count: cands.count)
        var refUsed = [Bool](repeating: false, count: refs.count)

        for tier in 1...5 {
            for ci in 0..<cands.count {
                if matchedRefForCand[ci] >= 0 { continue }
                let cand = cands[ci]
                for ri in 0..<refs.count {
                    if refUsed[ri] { continue }
                    if matchesAtTier(refs[ri], cand, tier: tier) {
                        matchedRefForCand[ci] = ri
                        refUsed[ri] = true
                        break
                    }
                }
            }
        }

        var assignedIds = Set<String>()
        for ci in 0..<cands.count {
            let ri = matchedRefForCand[ci]
            if ri >= 0 {
                assignedIds.insert(refs[ri].chapter.chapterId)
            }
        }

        var aligned = [Chapter]()
        aligned.reserveCapacity(cands.count)
        for ci in 0..<cands.count {
            let cand = cands[ci].chapter
            let ri = matchedRefForCand[ci]
            if ri >= 0 {
                let ref = refs[ri].chapter
                let title = cand.title.isEmpty ? ref.title : cand.title
                aligned.append(Chapter(
                    chapterId: ref.chapterId,
                    title: title,
                    url: cand.url,
                    sectionSlot: cand.sectionSlot,
                    chapterSlot: cand.chapterSlot
                ))
            } else {
                var id = cand.chapterId
                if id.isEmpty || !assignedIds.insert(id).inserted {
                    id = "extra:\(ci):\(id)"
                }
                aligned.append(Chapter(
                    chapterId: id,
                    title: cand.title,
                    url: cand.url,
                    sectionSlot: cand.sectionSlot,
                    chapterSlot: cand.chapterSlot
                ))
            }
        }
        return aligned
    }

    public static func findMatchingChapter(target: Chapter?, candidates: [Chapter]) -> Chapter? {
        guard let target, !candidates.isEmpty else { return nil }
        let targetSig = Signature(target)
        let candSigs = candidates.map(Signature.init)
        for tier in 1...5 {
            for cand in candSigs {
                if matchesAtTier(targetSig, cand, tier: tier) {
                    return cand.chapter
                }
            }
        }
        return nil
    }

    private struct Signature {
        let chapter: Chapter
        let id: String
        let normTitle: String
        let key: String

        init(_ chapter: Chapter) {
            self.chapter = chapter
            self.id = chapter.chapterId
            self.normTitle = FailoverChapterAligner.normalizeChapterTitle(chapter.title)
            self.key = FailoverChapterAligner.extractChapterKey(chapter.title)
        }
    }

    private static func matchesAtTier(_ a: Signature, _ b: Signature, tier: Int) -> Bool {
        let conflictingKeys = !a.key.isEmpty && !b.key.isEmpty && a.key != b.key
        switch tier {
        case 1:
            return !a.id.isEmpty && a.id == b.id && !conflictingKeys
        case 2:
            return !a.normTitle.isEmpty && a.normTitle == b.normTitle && !conflictingKeys
        case 3:
            return !a.key.isEmpty && a.key == b.key && a.chapter.sectionSlot == b.chapter.sectionSlot
        case 4:
            return !a.key.isEmpty && a.key == b.key
        case 5:
            return a.key.isEmpty
                && b.key.isEmpty
                && a.chapter.sectionSlot == b.chapter.sectionSlot
                && a.chapter.chapterSlot == b.chapter.chapterSlot
        default:
            return false
        }
    }

    private static func firstCapture(_ regex: NSRegularExpression, in text: String) -> String? {
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }
        for group in 1..<match.numberOfRanges {
            let nsRange = match.range(at: group)
            if nsRange.location != NSNotFound, let range = Range(nsRange, in: text) {
                return String(text[range])
            }
        }
        return nil
    }

    private static func canonicalNumberToken(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        if raw.range(of: #"^\d+(?:\.\d+)?$"#, options: .regularExpression) != nil {
            if let dot = raw.firstIndex(of: ".") {
                var intPart = String(raw[..<dot]).replacingOccurrences(of: #"^0+(?!$)"#, with: "", options: .regularExpression)
                let fracPart = String(raw[raw.index(after: dot)...]).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                if intPart.isEmpty { intPart = "0" }
                return fracPart.isEmpty ? intPart : "\(intPart).\(fracPart)"
            }
            let trimmed = raw.replacingOccurrences(of: #"^0+(?!$)"#, with: "", options: .regularExpression)
            return trimmed.isEmpty ? "0" : trimmed
        }
        let parsed = parseChineseNumber(raw)
        return parsed >= 0 ? String(parsed) : ""
    }

    private static func toHalfWidthDigitsAndAscii(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v >= 0xFF10 && v <= 0xFF19 {
                out.unicodeScalars.append(UnicodeScalar(UInt32(0x30) + (v - 0xFF10))!)
            } else if v >= 0xFF21 && v <= 0xFF3A {
                out.unicodeScalars.append(UnicodeScalar(UInt32(0x41) + (v - 0xFF21))!)
            } else if v >= 0xFF41 && v <= 0xFF5A {
                out.unicodeScalars.append(UnicodeScalar(UInt32(0x61) + (v - 0xFF41))!)
            } else if v == 0x3000 {
                out.append(" ")
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func chineseDigit(_ c: Character) -> Int {
        switch c {
        case "零", "〇": return 0
        case "一": return 1
        case "二", "两": return 2
        case "三": return 3
        case "四": return 4
        case "五": return 5
        case "六": return 6
        case "七": return 7
        case "八": return 8
        case "九": return 9
        default: return -1
        }
    }

    private static func chineseUnit(_ c: Character) -> Int64 {
        switch c {
        case "十": return 10
        case "百": return 100
        case "千": return 1000
        case "万": return 10000
        default: return -1
        }
    }
}
