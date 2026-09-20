import XCTest
@testable import ComicCore

private final class MemoryRepository: DownloadRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var order: [String] = []
    private var data: [String: DownloadTask] = [:]

    func list() -> [DownloadTask] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { data[$0] }
    }

    func get(id: String) -> DownloadTask? {
        lock.lock()
        defer { lock.unlock() }
        return data[id]
    }

    func save(task: DownloadTask) {
        lock.lock()
        defer { lock.unlock() }
        if data[task.id] == nil {
            order.append(task.id)
        }
        data[task.id] = task
    }

    func remove(id: String) {
        lock.lock()
        defer { lock.unlock() }
        order.removeAll { $0 == id }
        data.removeValue(forKey: id)
    }
}

final class DownloadCoordinatorTests: XCTestCase {
    private func chapter(_ id: String) -> Chapter {
        Chapter(chapterId: id, title: id, url: "https://sample/\(id)", sectionSlot: 0, chapterSlot: 0)
    }

    func testDuplicateEnqueueAndReversedDisplayKeepTheSameTask() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "source", comic: "comic", chapters: [chapter("a"), chapter("b")], selected: ["a", "b"])
        queue.enqueue(source: "source", comic: "comic", chapters: [chapter("b"), chapter("a")], selected: ["b", "a"])
        XCTAssertEqual(db.list().count, 2)
        let lease = queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)
        XCTAssertEqual(lease?.chapterId, "a")
    }

    func testUserPauseWinsOverNetworkRecoveryAndInvalidatesLateCompletion() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "s", comic: "c", chapters: [chapter("a")], selected: ["a"])
        let lease = queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)
        XCTAssertNotNil(lease)
        queue.pause(id: lease!.id)
        XCTAssertFalse(queue.complete(lease: lease!))
        XCTAssertNil(queue.claim(now: 10000, connected: true, wifi: true, wifiOnly: true))
        queue.resume(id: lease!.id)
        XCTAssertNotNil(queue.claim(now: 10000, connected: true, wifi: true, wifiOnly: true))
    }

    func testCancellationRejectsLatePageAndCompletion() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "s", comic: "c", chapters: [chapter("a")], selected: ["a"])
        let lease = queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)
        XCTAssertNotNil(lease)
        queue.cancel(id: lease!.id)
        XCTAssertFalse(queue.isCurrent(lease!))
        XCTAssertFalse(queue.complete(lease: lease!))
        XCTAssertEqual(db.get(id: lease!.id)?.state, .cancelled)
    }

    func testVerificationWaitDoesNotBlockAnotherSource() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "blocked", comic: "c", chapters: [chapter("a"), chapter("b")], selected: ["a", "b"])
        queue.enqueue(source: "other", comic: "d", chapters: [chapter("a")], selected: ["a"])
        let first = queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)
        XCTAssertNotNil(first)
        queue.waitForVerification(first!)
        XCTAssertEqual(queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)?.sourceId, "other")
    }

    func testThreeAutomaticRetriesThenManualRetryRequired() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "s", comic: "c", chapters: [chapter("a")], selected: ["a"])
        var now: Int64 = 0
        let delays: [Int64] = [2000, 5000, 15000]
        for delay in delays {
            let lease = queue.claim(now: now, connected: true, wifi: true, wifiOnly: true)
            XCTAssertNotNil(lease)
            queue.failed(lease: lease!, now: now, error: "network", retryAfter: 0)
            XCTAssertNil(queue.claim(now: now + delay - 1, connected: true, wifi: true, wifiOnly: true))
            now += delay
        }
        let last = queue.claim(now: now, connected: true, wifi: true, wifiOnly: true)
        XCTAssertNotNil(last)
        queue.failed(lease: last!, now: now, error: "network", retryAfter: 0)
        XCTAssertNil(queue.claim(now: Int64.max, connected: true, wifi: true, wifiOnly: true))
        XCTAssertEqual(db.get(id: last!.id)?.state, .failed)
    }

    func testRecoveryPreservesManualPauseAndCompletedAndRequeuesInterruptedWork() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "s", comic: "c", chapters: [chapter("a"), chapter("b"), chapter("c")], selected: ["a", "b", "c"])
        let a = queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)
        XCTAssertNotNil(a)
        _ = queue.complete(lease: a!)

        let b = queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)
        XCTAssertNotNil(b)
        queue.pause(id: b!.id)

        let c = queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)
        XCTAssertNotNil(c)

        DownloadCoordinator(repository: db).recover()
        XCTAssertEqual(db.get(id: a!.id)?.state, .completed)
        XCTAssertEqual(db.get(id: b!.id)?.state, .pausedUser)
        XCTAssertFalse(queue.isCurrent(c!))
        XCTAssertEqual(queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)?.chapterId, "c")
    }

    func testWifiOnlyWaitsUntilUnmeteredWifiOrExplicitPreferenceChange() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "s", comic: "c", chapters: [chapter("a")], selected: ["a"])
        XCTAssertNil(queue.claim(now: 0, connected: true, wifi: false, wifiOnly: true))
        XCTAssertNotNil(queue.claim(now: 0, connected: true, wifi: false, wifiOnly: false))
    }

    func testRetryAfterCoolsDownTheSourceButNotOtherSources() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "s", comic: "c", chapters: [chapter("a"), chapter("b")], selected: ["a", "b"])
        queue.enqueue(source: "other", comic: "c", chapters: [chapter("a")], selected: ["a"])
        let lease = queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)
        XCTAssertNotNil(lease)
        queue.failed(lease: lease!, now: 0, error: "HTTP 429", retryAfter: 60000)
        XCTAssertEqual(queue.claim(now: 10000, connected: true, wifi: true, wifiOnly: true)?.sourceId, "other")
    }

    func testBoundedClaimsAllowTwoTasksButRejectTheThird() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "source", comic: "comic", chapters: [chapter("a"), chapter("b"), chapter("c")], selected: ["a", "b", "c"])
        XCTAssertNotNil(queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true, maxActive: 2, maxPerSource: 2))
        XCTAssertNotNil(queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true, maxActive: 2, maxPerSource: 2))
        XCTAssertNil(queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true, maxActive: 2, maxPerSource: 2))
    }

    func testSourceLimitDoesNotBlockAnotherSource() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "source", comic: "comic", chapters: [chapter("a"), chapter("b"), chapter("c")], selected: ["a", "b", "c"])
        queue.enqueue(source: "other", comic: "comic", chapters: [chapter("d")], selected: ["d"])
        XCTAssertNotNil(queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true, maxActive: 3, maxPerSource: 2))
        XCTAssertNotNil(queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true, maxActive: 3, maxPerSource: 2))
        XCTAssertEqual(queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true, maxActive: 3, maxPerSource: 2)?.sourceId, "other")
    }

    func testDeletingAndRecreatingIdentityCannotReviveAnOldWorker() {
        let db = MemoryRepository()
        let queue = DownloadCoordinator(repository: db)
        queue.enqueue(source: "s", comic: "c", chapters: [chapter("a")], selected: ["a"])
        let old = queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true)
        XCTAssertNotNil(old)
        queue.cancel(id: old!.id)
        db.remove(id: old!.id)
        queue.enqueue(source: "s", comic: "c", chapters: [chapter("a")], selected: ["a"])
        XCTAssertNotNil(queue.claim(now: 0, connected: true, wifi: true, wifiOnly: true))
        XCTAssertFalse(queue.complete(lease: old!))
    }
}
