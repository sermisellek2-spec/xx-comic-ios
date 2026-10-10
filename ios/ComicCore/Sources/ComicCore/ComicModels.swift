import Foundation

public struct ComicSummary: Codable, Equatable, Sendable {
    public let sourceId: String
    public let comicId: String
    public let title: String
    public let coverUrl: String
    public let subtitle: String
    public let tags: [String]
    public let latestChapter: String?

    public init(sourceId: String, comicId: String, title: String, coverUrl: String = "", subtitle: String = "", tags: [String] = [], latestChapter: String? = nil) {
        self.sourceId = sourceId
        self.comicId = comicId
        self.title = title
        self.coverUrl = coverUrl
        self.subtitle = subtitle
        self.tags = tags
        self.latestChapter = latestChapter
    }

    public func withLatestChapter(_ latestChapter: String?) -> ComicSummary {
        ComicSummary(sourceId: sourceId, comicId: comicId, title: title, coverUrl: coverUrl, subtitle: subtitle, tags: tags, latestChapter: latestChapter)
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

    public init(chapterId: String, title: String, nextPageUrl: String = "", imageUrls: [String]) {
        self.chapterId = chapterId
        self.title = title
        self.nextPageUrl = nextPageUrl
        self.imageUrls = imageUrls
    }
}

public struct FileResource: Codable, Equatable, Sendable {
    public let fileId: String
    public let revision: String
    public let title: String
    public let order: Int
    public let expectedFormat: String
    public let bytes: Int64
    public let sha256: String?
    public let url: String
    public let headers: [String: String]
    public let expiresAt: Int64

    public init(fileId: String, revision: String = "", title: String = "", order: Int = 0,
                expectedFormat: String = "", bytes: Int64 = -1, sha256: String? = nil,
                url: String = "", headers: [String: String] = [:], expiresAt: Int64 = 0) {
        self.fileId = fileId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.revision = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.order = order
        self.expectedFormat = expectedFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.bytes = bytes
        self.sha256 = sha256.flatMap {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t.lowercased()
        }
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.headers = headers
        self.expiresAt = expiresAt
    }

    public func isExpired(now: Int64) -> Bool {
        expiresAt > 0 && now >= expiresAt
    }

    public func withUrl(_ newUrl: String, newExpiresAt: Int64) -> FileResource {
        FileResource(fileId: fileId, revision: revision, title: title, order: order,
                     expectedFormat: expectedFormat, bytes: bytes, sha256: sha256,
                     url: newUrl, headers: headers, expiresAt: newExpiresAt)
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
