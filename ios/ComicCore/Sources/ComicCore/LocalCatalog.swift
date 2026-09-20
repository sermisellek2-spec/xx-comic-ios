import Foundation

public struct LocalSeriesRecord: Codable, Equatable, Sendable {
    public let id: String
    public let originalTitle: String
    public var userTitle: String?
    public var volumeIDs: [String]
    public let createdAt: TimeInterval
    public var updatedAt: TimeInterval
    public var status: String

    public init(id: String, originalTitle: String, userTitle: String? = nil, volumeIDs: [String],
                createdAt: TimeInterval, updatedAt: TimeInterval, status: String = "ready") {
        self.id = id
        self.originalTitle = originalTitle
        self.userTitle = userTitle
        self.volumeIDs = volumeIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
    }

    public var displayTitle: String {
        if let userTitle, !SearchRules.trim(userTitle).isEmpty {
            return SearchRules.trim(userTitle)
        }
        let trimmedOriginal = SearchRules.trim(originalTitle)
        if !trimmedOriginal.isEmpty {
            return trimmedOriginal
        }
        return "未命名漫画"
    }
}

public struct LocalDeletedFingerprintRecord: Codable, Equatable, Sendable {
    public let fingerprint: String
    public let seriesId: String
    public let volumeId: String
    public let userTitle: String?
    public let deletedAt: TimeInterval

    public init(fingerprint: String, seriesId: String, volumeId: String, userTitle: String?, deletedAt: TimeInterval) {
        self.fingerprint = fingerprint
        self.seriesId = seriesId
        self.volumeId = volumeId
        self.userTitle = userTitle
        self.deletedAt = deletedAt
    }
}

public struct LocalCatalog: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maxFileBytes = 16 * 1024 * 1024 // 16 MiB

    public var version: Int
    public var series: [LocalSeriesRecord]
    public var tombstones: [LocalDeletedFingerprintRecord]

    public init(version: Int = Self.currentVersion, series: [LocalSeriesRecord] = [], tombstones: [LocalDeletedFingerprintRecord] = []) {
        self.version = version
        self.series = series
        self.tombstones = tombstones
    }
}

public enum LocalCatalogError: LocalizedError, Equatable {
    case unsupportedVersion
    case catalogCorrupted
    case catalogTooLarge
    case alreadyImported
    case targetNotFound
    case targetNotReady
    case volumeNotFound
    case invalidPermutation
    case titleEmpty

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "目录快照版本暂不支持，已保留原文件。"
        case .catalogCorrupted: return "本地目录快照损坏，已保留原文件以供排查。"
        case .catalogTooLarge: return "本地目录快照超过大小限制（16 MiB），未做更改。"
        case .alreadyImported: return "文件已在本地书架中，已跳过"
        case .targetNotFound: return "目标合集不存在，操作已取消。"
        case .targetNotReady: return "目标合集已移除或正在处理，操作已取消。"
        case .volumeNotFound: return "指定分卷不存在，操作已取消。"
        case .invalidPermutation: return "分卷排列顺序无效，不能包含缺项、重复项或外部项。"
        case .titleEmpty: return "漫画标题不能为空。"
        }
    }
}
