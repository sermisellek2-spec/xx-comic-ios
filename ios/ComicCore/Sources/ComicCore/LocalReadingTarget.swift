import Foundation

public struct LocalReadingTarget: Equatable, Sendable {
    public enum ReaderKind: String, Codable, Equatable, Sendable {
        case comic
        case text
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

extension TextLocator {
    public func toSeriesLocator(seriesId: String, globalChapterIndex: Int) -> TextLocator {
        TextLocator(bookID: seriesId, chapterIndex: globalChapterIndex, spineIndex: spineIndex,
                    resourceHref: resourceHref, anchorID: anchorID,
                    scrollPercentage: scrollPercentage, charOffset: charOffset)
    }

    public func toVolumeLocator(volumeId: String, volumeChapterIndex: Int) -> TextLocator {
        TextLocator(bookID: volumeId, chapterIndex: volumeChapterIndex, spineIndex: spineIndex,
                    resourceHref: resourceHref, anchorID: anchorID,
                    scrollPercentage: scrollPercentage, charOffset: charOffset)
    }
}
