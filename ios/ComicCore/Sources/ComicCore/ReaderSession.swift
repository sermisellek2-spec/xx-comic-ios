import Foundation

public enum ReaderMove: Equatable, Sendable {
    case image(Int)
    case chapter(Int, atEnd: Bool)
    case boundary
    case unavailable
}

public struct ReaderSession: Sendable {
    public let chapterCount: Int
    public private(set) var chapterIndex: Int
    public private(set) var imageIndex = 0
    public private(set) var imageCount = 0

    public init(chapterCount: Int, chapterIndex: Int) {
        self.chapterCount = max(0, chapterCount)
        self.chapterIndex = max(0, min(max(0, chapterCount - 1), chapterIndex))
    }
    public mutating func loaded(imageCount: Int, position: ReaderPosition) {
        self.imageCount = max(0, imageCount)
        imageIndex = position.index(for: imageCount)
    }
    public mutating func loaded(chapter: Chapter, in chapters: [Chapter], imageCount: Int, position: ReaderPosition) -> Bool {
        guard let index = chapters.firstIndex(where: {
            (!chapter.chapterId.isEmpty && $0.chapterId == chapter.chapterId)
                || (!chapter.url.isEmpty && $0.url == chapter.url)
        }) else { return false }
        self = ReaderSession(chapterCount: chapters.count, chapterIndex: index)
        loaded(imageCount: imageCount, position: position)
        return true
    }
    public mutating func changeChapter(to index: Int) {
        guard index >= 0 && index < chapterCount else { return }
        chapterIndex = index
        imageCount = 0
        imageIndex = 0
    }
    public mutating func updateImage(_ index: Int) {
        imageIndex = max(0, min(max(0, imageCount - 1), index))
    }
    public mutating func move(delta: Int) -> ReaderMove {
        guard imageCount > 0, delta == -1 || delta == 1 else { return .unavailable }
        let next = imageIndex + delta
        if next >= 0 && next < imageCount {
            imageIndex = next
            return .image(next)
        }
        let chapter = chapterIndex + delta
        guard chapter >= 0 && chapter < chapterCount else { return .boundary }
        return .chapter(chapter, atEnd: delta < 0)
    }
}
