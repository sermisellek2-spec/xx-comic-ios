import Foundation

/// Record representing a blacklisted comic title and its restore metadata.
public struct BlacklistEntry: Codable, Equatable, Hashable, Sendable {
    public let normalizedTitle: String
    public let displayTitle: String
    public let coverUrl: String
    public let comicId: String
    public let sourceId: String
    public let sourceName: String
    public let originScope: String
    public let originLabel: String
    public let groupSummary: String
    public let blacklistedAt: Int64

    public init(
        normalizedTitle: String = "",
        displayTitle: String = "",
        coverUrl: String = "",
        comicId: String = "",
        sourceId: String = "",
        sourceName: String = "",
        originScope: String = "",
        originLabel: String = "",
        groupSummary: String = "",
        blacklistedAt: Int64 = 0
    ) {
        let safeDisplay = displayTitle
        var safeNormalized = SearchRules.trim(normalizedTitle)
        if safeNormalized.isEmpty && !safeDisplay.isEmpty {
            safeNormalized = ComicTitleNormalizer.normalize(safeDisplay)
        }
        self.normalizedTitle = safeNormalized
        self.displayTitle = safeDisplay
        self.coverUrl = coverUrl
        self.comicId = comicId
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.originScope = originScope
        self.originLabel = originLabel
        self.groupSummary = groupSummary
        self.blacklistedAt = blacklistedAt
    }

    enum CodingKeys: String, CodingKey {
        case normalizedTitle
        case displayTitle
        case coverUrl
        case comicId
        case sourceId
        case sourceName
        case originScope
        case originLabel
        case groupSummary
        case blacklistedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let norm = try container.decodeIfPresent(String.self, forKey: .normalizedTitle) ?? ""
        let disp = try container.decodeIfPresent(String.self, forKey: .displayTitle) ?? ""
        let cover = try container.decodeIfPresent(String.self, forKey: .coverUrl) ?? ""
        let cid = try container.decodeIfPresent(String.self, forKey: .comicId) ?? ""
        let sid = try container.decodeIfPresent(String.self, forKey: .sourceId) ?? ""
        let sname = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        let scope = try container.decodeIfPresent(String.self, forKey: .originScope) ?? ""
        let label = try container.decodeIfPresent(String.self, forKey: .originLabel) ?? ""
        let group = try container.decodeIfPresent(String.self, forKey: .groupSummary) ?? ""
        let ts = try container.decodeIfPresent(Int64.self, forKey: .blacklistedAt) ?? 0
        self.init(
            normalizedTitle: norm,
            displayTitle: disp,
            coverUrl: cover,
            comicId: cid,
            sourceId: sid,
            sourceName: sname,
            originScope: scope,
            originLabel: label,
            groupSummary: group,
            blacklistedAt: ts
        )
    }

    public func toJSONObject() -> [String: Any] {
        [
            "normalizedTitle": normalizedTitle,
            "displayTitle": displayTitle,
            "coverUrl": coverUrl,
            "comicId": comicId,
            "sourceId": sourceId,
            "sourceName": sourceName,
            "originScope": originScope,
            "originLabel": originLabel,
            "groupSummary": groupSummary,
            "blacklistedAt": NSNumber(value: blacklistedAt)
        ]
    }

    public static func fromJSONObject(_ obj: [String: Any]?) -> BlacklistEntry? {
        guard let obj else { return nil }
        var normalizedTitle = cleanString(obj, "normalizedTitle")
        let displayTitle = cleanString(obj, "displayTitle")
        if SearchRules.trim(normalizedTitle).isEmpty {
            normalizedTitle = ComicTitleNormalizer.normalize(displayTitle)
        }
        if normalizedTitle.isEmpty && SearchRules.trim(displayTitle).isEmpty {
            return nil
        }
        return BlacklistEntry(
            normalizedTitle: normalizedTitle,
            displayTitle: displayTitle,
            coverUrl: cleanString(obj, "coverUrl"),
            comicId: cleanString(obj, "comicId"),
            sourceId: cleanString(obj, "sourceId"),
            sourceName: cleanString(obj, "sourceName"),
            originScope: cleanString(obj, "originScope"),
            originLabel: cleanString(obj, "originLabel"),
            groupSummary: cleanString(obj, "groupSummary"),
            blacklistedAt: cleanInt64(obj, "blacklistedAt", defaultValue: 0)
        )
    }

    private static func cleanString(_ obj: [String: Any], _ key: String) -> String {
        guard let value = obj[key], !(value is NSNull) else { return "" }
        if let str = value as? String { return str }
        if JsonValueHelper.isJsonBoolean(value) {
            return (value as? Bool ?? false) ? "true" : "false"
        }
        if let num = value as? NSNumber { return num.stringValue }
        return ""
    }

    private static func cleanInt64(_ obj: [String: Any], _ key: String, defaultValue: Int64) -> Int64 {
        guard let value = obj[key], !(value is NSNull), !JsonValueHelper.isJsonBoolean(value) else { return defaultValue }
        if let num = value as? NSNumber { return num.int64Value }
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        if let str = value as? String, let parsed = Int64(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return defaultValue
    }
}
