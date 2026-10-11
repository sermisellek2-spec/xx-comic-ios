import Foundation

/// A strip may contain several chapters, but every persisted position and
/// progress control still belongs to one chapter. IDs, not directory indexes,
/// connect the strip to a directory that can be loaded later or reordered.
public struct ContinuousReaderPages: Sendable {
    public struct Segment: Sendable {
        public let chapter: Chapter
        public let imageURLs: [String]
        public let range: Range<Int>
    }

    public struct Location: Sendable {
        public let chapter: Chapter
        public let imageURLs: [String]
        public let position: ReaderPosition
    }

    public private(set) var segments: [Segment] = []
    public private(set) var imageURLs: [String] = []
    public var lastChapter: Chapter? { segments.last?.chapter }

    public init() {}

    @discardableResult
    public mutating func append(chapter: Chapter, imageURLs: [String]) -> Bool {
        guard !imageURLs.isEmpty, !segments.contains(where: { Self.matches($0.chapter, chapter) }) else { return false }
        let start = self.imageURLs.count
        self.imageURLs.append(contentsOf: imageURLs)
        segments.append(Segment(chapter: chapter, imageURLs: imageURLs, range: start..<self.imageURLs.count))
        return true
    }

    public func segment(for chapter: Chapter) -> Segment? {
        segments.first { Self.matches($0.chapter, chapter) }
    }

    public func globalIndex(for chapter: Chapter, position: ReaderPosition) -> Int? {
        guard let segment = segment(for: chapter) else { return nil }
        return segment.range.lowerBound + position.index(in: segment.imageURLs)
    }

    public func location(at globalIndex: Int, offset: Double = 0, atEnd: Bool = false) -> Location? {
        guard let segment = segments.first(where: { $0.range.contains(globalIndex) }) else { return nil }
        let index = globalIndex - segment.range.lowerBound
        let position = ReaderPosition(imageIndex: index, offset: offset, atEnd: atEnd,
            linkedPageID: ReaderPosition.linkedIdentity(in: segment.imageURLs[index]),
            linkedTailID: segment.imageURLs.last.flatMap(ReaderPosition.linkedIdentity(in:)))
        return Location(chapter: segment.chapter, imageURLs: segment.imageURLs, position: position)
    }

    public static func matches(_ left: Chapter, _ right: Chapter) -> Bool {
        (!left.chapterId.isEmpty && left.chapterId == right.chapterId)
            || (!left.url.isEmpty && left.url == right.url)
    }
}
