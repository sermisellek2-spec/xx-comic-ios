import Foundation

public struct ComicSummary: Codable, Equatable, Sendable {
    public let sourceId: String
    public let comicId: String
    public let title: String
    public let coverUrl: String
    public let subtitle: String
    public let tags: [String]

    public init(sourceId: String, comicId: String, title: String, coverUrl: String = "", subtitle: String = "", tags: [String] = []) {
        self.sourceId = sourceId
        self.comicId = comicId
        self.title = title
        self.coverUrl = coverUrl
        self.subtitle = subtitle
        self.tags = tags
    }
}

public struct Chapter: Codable, Equatable, Sendable {
    public let chapterId: String
    public let title: String
    public let url: String
    public let sectionSlot: Int
    public let chapterSlot: Int

    public init(chapterId: String, title: String, url: String, sectionSlot: Int = 0, chapterSlot: Int = 0) {
        self.chapterId = chapterId
        self.title = title
        self.url = url
        self.sectionSlot = sectionSlot
        self.chapterSlot = chapterSlot
    }
}
