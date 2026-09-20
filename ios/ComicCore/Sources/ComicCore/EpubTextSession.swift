import Foundation

/// Navigation uses the imported spine partition, never href sorting (hrefs can repeat).
public struct EpubTextSession: Sendable {
    public let book: LocalBook
    public private(set) var chapterIndex: Int
    public private(set) var spineIndex: Int
    private let chapterSpines: [[Int]]
    private let spineChapters: [Int]
    public var entry: EpubPublication.SpineItem { book.epub!.spine[spineIndex] }

    public init(book: LocalBook, chapterIndex: Int, locator: TextLocator?) throws {
        guard let publication = book.epub, !publication.hasDrm, !publication.spine.isEmpty,
              book.pages.count == publication.spine.count, Set(book.pages).count == book.pages.count,
              let chapters = book.chapters, !chapters.isEmpty,
              Set(chapters.map(\.id)).count == chapters.count,
              chapters.flatMap(\.pages) == book.pages,
              chapters.allSatisfy({ !$0.pages.isEmpty }),
              publication.spine.allSatisfy({ (try? EpubArchive.normalized($0.fullZipPath)) == $0.fullZipPath }) else {
            throw LocalLibraryError.invalidBook
        }
        let indices = Dictionary(uniqueKeysWithValues: book.pages.enumerated().map { ($0.element, $0.offset) })
        chapterSpines = chapters.map { $0.pages.map { indices[$0]! } }
        spineChapters = chapters.enumerated().flatMap { index, chapter in chapter.pages.map { _ in index } }
        self.book = book
        self.chapterIndex = max(0, min(chapters.count - 1, chapterIndex))
        spineIndex = chapterSpines[self.chapterIndex][0]
        if let locator, locator.bookID == book.id, locator.chapterIndex == self.chapterIndex,
           chapterSpines[self.chapterIndex].contains(locator.spineIndex),
           publication.spine[locator.spineIndex].fullZipPath == locator.resourceHref {
            spineIndex = locator.spineIndex
        }
    }

    public mutating func selectChapter(_ index: Int) throws {
        guard chapterSpines.indices.contains(index) else { throw LocalLibraryError.invalidBook }
        chapterIndex = index; spineIndex = chapterSpines[index][0]
    }

    public mutating func moveSpine(delta: Int) -> Bool {
        guard delta == -1 || delta == 1, book.pages.indices.contains(spineIndex + delta) else { return false }
        spineIndex += delta; chapterIndex = spineChapters[spineIndex]
        return true
    }

    public mutating func navigate(path: String) -> Bool {
        guard (try? EpubArchive.normalized(path)) == path else { return false }
        if entry.fullZipPath == path { return true }
        guard let index = book.epub!.spine.firstIndex(where: { $0.fullZipPath == path }) else { return false }
        spineIndex = index; chapterIndex = spineChapters[index]
        return true
    }

    public func locator(anchorID: String = "", percent: Double, charOffset: Int = 0) -> TextLocator {
        TextLocator(bookID: book.id, chapterIndex: chapterIndex, spineIndex: spineIndex,
                    resourceHref: entry.fullZipPath, anchorID: anchorID, scrollPercentage: percent, charOffset: charOffset)
    }
}
