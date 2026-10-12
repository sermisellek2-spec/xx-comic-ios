import Foundation

public struct LocalReadingTarget: Equatable, Sendable {
    public enum ReaderKind: String, Codable, Equatable, Sendable {
        case comic
    }

    public let seriesId: String
    public let volumeId: String
    public let chapter: Chapter
    public let globalChapterIndex: Int
    public let volumeChapterIndex: Int
    public let kind: ReaderKind
    public let totalChapters: Int

    public init(seriesId: String, volumeId: String, chapter: Chapter,
                globalChapterIndex: Int, volumeChapterIndex: Int,
                kind: ReaderKind, totalChapters: Int) {
        self.seriesId = seriesId
        self.volumeId = volumeId
        self.chapter = chapter
        self.globalChapterIndex = globalChapterIndex
        self.volumeChapterIndex = volumeChapterIndex
        self.kind = kind
        self.totalChapters = totalChapters
    }
}
