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

public struct ComicDetail: Codable, Equatable, Sendable {
    public let summary: ComicSummary
    public let author: String
    public let status: String
    public let description: String
    public let latestChapter: String
    public let chapters: [Chapter]

    public init(summary: ComicSummary, author: String, status: String, description: String, latestChapter: String, chapters: [Chapter]) {
        self.summary = summary
        self.author = author
        self.status = status
        self.description = description
        self.latestChapter = latestChapter
        self.chapters = chapters
    }
}

public struct ChapterPage: Codable, Equatable, Sendable {
    public let chapterId: String
    public let title: String
    public let nextPageUrl: String
    public let imageUrls: [String]

    public init(chapterId: String, title: String, nextPageUrl: String, imageUrls: [String]) {
        self.chapterId = chapterId
        self.title = title
        self.nextPageUrl = nextPageUrl
        self.imageUrls = imageUrls
    }
}

public struct SourceFilterGroup: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let options: [SourceFilterOption]

    public init(key: String, label: String, options: [SourceFilterOption]) {
        self.key = key
        self.label = label
        self.options = options
    }
}

public struct SourceFilterOption: Codable, Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}
