import XCTest
@testable import ComicCore

final class FavoriteRevisionTests: XCTestCase {
    func testChapterNumberExtractionAndNormalization() {
        XCTAssertEqual(FavoriteRevision.extractChapterNumber("第12话"), 12)
        XCTAssertEqual(FavoriteRevision.extractChapterNumber("Chapter 45 - Finale"), 45)
        XCTAssertEqual(FavoriteRevision.extractChapterNumber("番外篇"), nil)

        let url1 = "https://example.com/comic/123/ch1?query=abc#section2"
        XCTAssertEqual(FavoriteRevision.normalizeChapterUrl(url1), "/comic/123/ch1")

        let url2 = "/comic/123/ch1?section_slot=2&other=trash"
        XCTAssertEqual(FavoriteRevision.normalizeChapterUrl(url2), "/comic/123/ch1?section_slot=2")
    }

    func testHasNewChaptersDetection() {
        let ch1 = Chapter(chapterId: "1", title: "第1话", url: "/ch1")
        let ch2 = Chapter(chapterId: "2", title: "第2话", url: "/ch2")
        let ch3 = Chapter(chapterId: "3", title: "第3话", url: "/ch3")

        let rev1 = FavoriteRevision.fromChapters(latestChapterName: "第2话", chapters: [ch1, ch2])
        let rev2 = FavoriteRevision.fromChapters(latestChapterName: "第2话", chapters: [ch1, ch2])
        let rev3 = FavoriteRevision.fromChapters(latestChapterName: "第3话", chapters: [ch1, ch2, ch3])

        XCTAssertFalse(FavoriteRevision.hasNewChapters(baseline: rev1, candidate: rev2))
        XCTAssertTrue(FavoriteRevision.hasNewChapters(baseline: rev1, candidate: rev3))

        // Mode: latest chapter only
        let stringRev1 = FavoriteRevision.fromChapters(latestChapterName: "更新至 第5话", chapters: nil)
        let stringRev2 = FavoriteRevision.fromChapters(latestChapterName: "更新至 第6话", chapters: nil)
        XCTAssertTrue(FavoriteRevision.hasNewChapters(baseline: stringRev1, candidate: stringRev2))
        XCTAssertFalse(FavoriteRevision.hasNewChapters(baseline: stringRev2, candidate: stringRev1))
    }

    func testFavoriteUpdateCoordinatorWorkflowAndPersistence() {
        let defaultsName = "FavoriteRevisionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let coordinator = FavoriteUpdateCoordinator(defaults: defaults)

        final class BadgeBox: @unchecked Sendable {
            private let lock = NSLock()
            private var list: [(String, String, Bool)] = []
            func append(_ item: (String, String, Bool)) {
                lock.lock(); defer { lock.unlock() }
                list.append(item)
            }
            var first: (String, String, Bool)? {
                lock.lock(); defer { lock.unlock() }
                return list.first
            }
            var count: Int {
                lock.lock(); defer { lock.unlock() }
                return list.count
            }
        }
        let box = BadgeBox()
        coordinator.onBadgeChanged = { sourceId, comicId, visible in
            box.append((sourceId, comicId, visible))
        }

        let ch1 = Chapter(chapterId: "1", title: "第1话", url: "/ch1")
        let ch2 = Chapter(chapterId: "2", title: "第2话", url: "/ch2")
        let rev1 = FavoriteRevision.fromChapters(latestChapterName: "第1话", chapters: [ch1])
        let rev2 = FavoriteRevision.fromChapters(latestChapterName: "第2话", chapters: [ch1, ch2])

        // Initially acknowledge rev1
        coordinator.acknowledge(sourceId: "sourceA", comicId: "comic1", revision: rev1)
        XCTAssertFalse(coordinator.hasPendingUpdate(sourceId: "sourceA", comicId: "comic1"))

        // Record rev2 with new chapter
        coordinator.recordObserved(sourceId: "sourceA", comicId: "comic1", revision: rev2)
        XCTAssertTrue(coordinator.hasPendingUpdate(sourceId: "sourceA", comicId: "comic1"))
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(box.first?.2, true)

        // Restore in fresh coordinator from same defaults
        let restored = FavoriteUpdateCoordinator(defaults: defaults)
        XCTAssertTrue(restored.hasPendingUpdate(sourceId: "sourceA", comicId: "comic1"))

        // Acknowledge update
        restored.acknowledge(sourceId: "sourceA", comicId: "comic1", revision: rev2)
        XCTAssertFalse(restored.hasPendingUpdate(sourceId: "sourceA", comicId: "comic1"))
    }
}
