import Foundation

/// Legacy library.json compatibility only; no reader consumes or creates these records.
public struct TextLocator: Codable, Equatable, Sendable {
    public let bookID: String
    public let chapterIndex: Int
    public let spineIndex: Int
    public let resourceHref: String
    public let anchorID: String
    public let scrollPercentage: Double
    public let charOffset: Int

    public init(bookID: String, chapterIndex: Int, spineIndex: Int, resourceHref: String,
                anchorID: String = "", scrollPercentage: Double = 0, charOffset: Int = 0) {
        self.bookID = bookID
        self.chapterIndex = max(0, chapterIndex)
        self.spineIndex = max(0, spineIndex)
        self.resourceHref = resourceHref
        self.anchorID = anchorID
        self.scrollPercentage = scrollPercentage.isFinite ? max(0, min(1, scrollPercentage)) : 0
        self.charOffset = max(0, charOffset)
    }

    private enum CodingKeys: String, CodingKey {
        case bookID = "bookId", anchorID = "anchorId"
        case chapterIndex, spineIndex, resourceHref, scrollPercentage, charOffset
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bookID: try values.decodeIfPresent(String.self, forKey: .bookID) ?? "",
                  chapterIndex: try values.decodeIfPresent(Int.self, forKey: .chapterIndex) ?? 0,
                  spineIndex: try values.decodeIfPresent(Int.self, forKey: .spineIndex) ?? 0,
                  resourceHref: try values.decodeIfPresent(String.self, forKey: .resourceHref) ?? "",
                  anchorID: try values.decodeIfPresent(String.self, forKey: .anchorID) ?? "",
                  scrollPercentage: try values.decodeIfPresent(Double.self, forKey: .scrollPercentage) ?? 0,
                  charOffset: try values.decodeIfPresent(Int.self, forKey: .charOffset) ?? 0)
    }
}
