import Foundation

/// Formats concise, factual recommendation reasons without AI clichés or emojis.
/// Enforces `reason <= 22` chars and `gridReason <= 11` chars.
public enum RecommendReasonFormatter {
    public static let maxReasonLength = 22
    public static let maxGridReasonLength = 11

    public struct FormattedReason: Equatable, Sendable {
        public let reason: String
        public let gridReason: String

        public init(reason: String, gridReason: String) {
            self.reason = reason
            self.gridReason = gridReason
        }
    }

    private static let clicheAiRegex = try! NSRegularExpression(
        pattern: "(?<![a-zA-Z])AI(?![a-zA-Z])",
        options: [.caseInsensitive]
    )

    public static func format(
        channel: RecommendChannel,
        candidateGenres: [String],
        author: String?,
        hotSourceCount: Int,
        sourceName: String?,
        featuredCategoryLabel: String?,
        profile: HabitProfile?,
        personalizationActive: Bool
    ) -> FormattedReason {
        let safeSource = sanitizeText(sourceName)
        let safeAuthor = sanitizeText(author)
        let safeFeatured = sanitizeText(featuredCategoryLabel)
        let hasPersonalProfile = personalizationActive && profile != nil && !(profile?.isColdStart ?? true)

        // 1 & 2: Matched author
        if hasPersonalProfile, let profile, !safeAuthor.isEmpty {
            let matchedAuthorKey = findBestMatchedAuthorKey(rawAuthor: safeAuthor, profile: profile)
            if !matchedAuthorKey.isEmpty {
                let seedTitle = sanitizeText(profile.topSeedTitleByAuthor[matchedAuthorKey])
                if !seedTitle.isEmpty {
                    let full = fitBracketTitle(prefix: "在追《", title: seedTitle, suffix: "》同作者", maxLen: maxReasonLength)
                    let grid = safeAuthor.utf16.count <= 5
                        ? clamp("同作者·\(safeAuthor)", maxLen: maxGridReasonLength)
                        : "同作者作品"
                    return finalizeReasons(reason: full, gridReason: grid)
                }
                let full = clamp("常看作者 · \(safeAuthor)", maxLen: maxReasonLength)
                let grid = safeAuthor.utf16.count <= 5
                    ? clamp("作者·\(safeAuthor)", maxLen: maxGridReasonLength)
                    : "同作者作品"
                return finalizeReasons(reason: full, gridReason: grid)
            }
        }

        let matchedPositiveGenres = (hasPersonalProfile && profile != nil)
            ? findMatchedPositiveGenres(genres: candidateGenres, profile: profile!)
            : []

        // 3: High genre overlap with seed title
        if hasPersonalProfile, let profile, !matchedPositiveGenres.isEmpty {
            let topGenre = matchedPositiveGenres[0]
            let topSeedTitle = sanitizeText(profile.topSeedTitleByGenre[topGenre])
            let topWeight = profile.genreWeights[topGenre] ?? 0.0
            let highOverlap = matchedPositiveGenres.count >= 2
                || (channel == .habitPersonalized && topWeight >= 1.2)
            if !topSeedTitle.isEmpty && highOverlap && channel != .explorationNewTaste {
                let gSuffix = matchedPositiveGenres.count >= 2
                    ? "》· \(matchedPositiveGenres[0])·\(matchedPositiveGenres[1])"
                    : "》· \(matchedPositiveGenres[0])"
                var full = fitBracketTitle(prefix: "在追《", title: topSeedTitle, suffix: gSuffix, maxLen: maxReasonLength)
                if full.utf16.count > maxReasonLength && matchedPositiveGenres.count >= 2 {
                    full = fitBracketTitle(
                        prefix: "在追《",
                        title: topSeedTitle,
                        suffix: "》· \(matchedPositiveGenres[0])",
                        maxLen: maxReasonLength
                    )
                }
                let grid = fitBracketTitle(prefix: "在追《", title: topSeedTitle, suffix: "》", maxLen: maxGridReasonLength)
                return finalizeReasons(reason: full, gridReason: grid)
            }
        }

        // 4: Exploration
        if channel == .explorationNewTaste {
            return formatExploration(genres: candidateGenres, safeSource: safeSource)
        }

        // 5: Multi-source consensus
        if hotSourceCount >= 2 {
            let full = clamp("\(hotSourceCount) 个站源同榜热推", maxLen: maxReasonLength)
            let grid = clamp("\(hotSourceCount) 站同榜热推", maxLen: maxGridReasonLength)
            return finalizeReasons(reason: full, gridReason: grid)
        }

        // 6: Source featured category
        if channel == .sourceFeaturedCategory || !safeFeatured.isEmpty {
            let cat = safeFeatured.isEmpty ? "热门推荐" : safeFeatured
            let full = safeSource.isEmpty
                ? clamp(cat, maxLen: maxReasonLength)
                : joinWithDot(left: safeSource, right: cat, maxLen: maxReasonLength)
            let grid: String
            if !safeSource.isEmpty && (safeSource.utf16.count + 1 + cat.utf16.count) <= maxGridReasonLength {
                grid = "\(safeSource)·\(cat)"
            } else {
                grid = clamp(cat, maxLen: maxGridReasonLength)
            }
            return finalizeReasons(reason: full, gridReason: grid)
        }

        // 7: Matched positive genres (without seed title or lower overlap)
        if hasPersonalProfile && !matchedPositiveGenres.isEmpty {
            let first = matchedPositiveGenres[0]
            let twoGenres = matchedPositiveGenres.count >= 2
                ? "\(first)·\(matchedPositiveGenres[1])"
                : first
            let full = clamp("常看 \(twoGenres)", maxLen: maxReasonLength)
            let candidateGrid = "常看 \(twoGenres)"
            let grid = candidateGrid.utf16.count <= maxGridReasonLength
                ? candidateGrid
                : clamp("常看 \(first)", maxLen: maxGridReasonLength)
            return finalizeReasons(reason: full, gridReason: grid)
        }

        // 8: Latest updates
        if channel == .latestUpdates {
            let full = safeSource.isEmpty
                ? "近期连载更新"
                : joinWithDot(left: safeSource, right: "最近更新", maxLen: maxReasonLength)
            let grid = (!safeSource.isEmpty && (safeSource.utf16.count + 3) <= maxGridReasonLength)
                ? "\(safeSource)·更新"
                : "最近更新"
            return finalizeReasons(reason: full, gridReason: grid)
        }

        // 9: Primary genre fallback
        if let firstGenre = candidateGenres.first {
            let primary = sanitizeText(firstGenre)
            if !primary.isEmpty {
                let full = safeSource.isEmpty
                    ? clamp("\(primary)人气作品", maxLen: maxReasonLength)
                    : joinWithDot(left: safeSource, right: "\(primary)热推", maxLen: maxReasonLength)
                let grid = clamp("\(primary)热推", maxLen: maxGridReasonLength)
                return finalizeReasons(reason: full, gridReason: grid)
            }
        }

        // 10: Final fallback
        let full = safeSource.isEmpty
            ? "站源人气榜单"
            : joinWithDot(left: safeSource, right: "人气榜单", maxLen: maxReasonLength)
        let grid = (!safeSource.isEmpty && (safeSource.utf16.count + 3) <= maxGridReasonLength)
            ? "\(safeSource)·热榜"
            : "站源人气榜"
        return finalizeReasons(reason: full, gridReason: grid)
    }

    private static func formatExploration(genres: [String], safeSource: String) -> FormattedReason {
        let primary = genres.first.map { sanitizeText($0) } ?? ""
        if !primary.isEmpty {
            let full = clamp("换换口味 · \(primary)人气作", maxLen: maxReasonLength)
            let candidateGrid = "换口味·\(primary)"
            let grid = candidateGrid.utf16.count <= maxGridReasonLength
                ? candidateGrid
                : clamp("\(primary)新口味", maxLen: maxGridReasonLength)
            return finalizeReasons(reason: full, gridReason: grid)
        }
        let full = safeSource.isEmpty
            ? "换换口味 · 站源人气作"
            : joinWithDot(left: "换换口味", right: "\(safeSource)人气", maxLen: maxReasonLength)
        return finalizeReasons(reason: full, gridReason: "换换口味")
    }

    private static func findBestMatchedAuthorKey(rawAuthor: String, profile: HabitProfile) -> String {
        var bestKey = ""
        var bestWeight = 0.0
        for key in UserHabitProfiler.splitAuthors(rawAuthor) {
            if let w = profile.authorWeights[key], w > bestWeight {
                bestWeight = w
                bestKey = key
            }
        }
        return bestKey
    }

    private static func findMatchedPositiveGenres(genres: [String], profile: HabitProfile) -> [String] {
        guard !genres.isEmpty else { return [] }
        var matched: [String] = []
        var seen = Set<String>()
        for g in genres {
            if let w = profile.genreWeights[g], w > 0.0, seen.insert(g).inserted {
                matched.append(g)
            }
        }
        matched.sort { (profile.genreWeights[$0] ?? 0.0) > (profile.genreWeights[$1] ?? 0.0) }
        return matched
    }

    private static func finalizeReasons(reason: String, gridReason: String) -> FormattedReason {
        var r = clamp(sanitizeText(reason), maxLen: maxReasonLength)
        var g = clamp(sanitizeText(gridReason), maxLen: maxGridReasonLength)
        if r.isEmpty { r = "站源人气榜单" }
        if g.isEmpty { g = "站源热榜" }
        return FormattedReason(reason: r, gridReason: g)
    }

    private static func fitBracketTitle(prefix: String, title: String, suffix: String, maxLen: Int) -> String {
        let available = maxLen - prefix.utf16.count - suffix.utf16.count
        if available <= 1 {
            return clamp(prefix + title + suffix, maxLen: maxLen)
        }
        return prefix + clamp(title, maxLen: available) + suffix
    }

    private static func joinWithDot(left: String, right: String, maxLen: Int) -> String {
        let sep = " · "
        if left.utf16.count + sep.utf16.count + right.utf16.count <= maxLen {
            return left + sep + right
        }
        let maxLeft = maxLen - sep.utf16.count - right.utf16.count
        if maxLeft >= 2 {
            return clamp(left, maxLen: maxLeft) + sep + right
        }
        return clamp(right, maxLen: maxLen)
    }

    static func clamp(_ text: String?, maxLen: Int) -> String {
        guard let text, maxLen > 0 else { return "" }
        let t = SearchRules.trim(text)
        if t.utf16.count <= maxLen { return t }
        if maxLen == 1 { return String(t.prefix(1)) }
        var out = ""
        var count = 0
        for ch in t {
            let u16 = String(ch).utf16.count
            if count + u16 > maxLen - 1 { break }
            out.append(ch)
            count += u16
        }
        return out + "…"
    }

    static func sanitizeText(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let simplified = RecommendSourceClassifier.toSimplified(raw)
        var noEmoji = String.UnicodeScalarView()
        noEmoji.reserveCapacity(simplified.unicodeScalars.count)
        for scalar in simplified.unicodeScalars {
            if !isEmojiOrPictograph(scalar.value) {
                noEmoji.append(scalar)
            }
        }
        var text = String(noEmoji)
        text = text.replacingOccurrences(of: "量身定制", with: "精选")
        text = text.replacingOccurrences(of: "猜你喜欢", with: "站源精选")
        text = text.replacingOccurrences(of: "智能推荐", with: "精选推荐")
        text = text.replacingOccurrences(of: "智能", with: "精选")
        let range = NSRange(location: 0, length: text.utf16.count)
        text = clicheAiRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return SearchRules.trim(text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression))
    }

    private static func isEmojiOrPictograph(_ cp: UInt32) -> Bool {
        if cp >= 0x1F000 && cp <= 0x1FAFF { return true }
        if cp >= 0x2600 && cp <= 0x27BF { return true }
        if cp >= 0x2300 && cp <= 0x23FF { return true }
        if cp >= 0xFE00 && cp <= 0xFE0F { return true }
        return cp == 0x200D || cp == 0x20E3
    }
}
