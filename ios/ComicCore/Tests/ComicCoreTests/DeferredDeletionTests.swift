import XCTest
@testable import ComicCore

final class DeferredDeletionTests: XCTestCase {
    func testUndoPreservesRealCopyBeyondDeadline() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("owned copy".utf8).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let target = LocalDeletionTarget.localSeries("test")
        let queue = DeferredDeletionQueue(delayNanoseconds: 30_000_000, operation: { _ in try FileManager.default.removeItem(at: file) })
        await queue.schedule([target])
        let restored = await queue.undo([target]); XCTAssertEqual(restored, [target])
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(try Data(contentsOf: file), Data("owned copy".utf8))
        let hidden = await queue.hiddenTargets; XCTAssertTrue(hidden.isEmpty)
    }

    func testDeadlineDeletesCopyAndReportsActualResult() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("owned copy".utf8).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let done = expectation(description: "deletion committed")
        let queue = DeferredDeletionQueue(delayNanoseconds: 20_000_000, operation: { _ in try FileManager.default.removeItem(at: file) }, onResult: { _, result in
            if case .success = result { done.fulfill() }
        })
        await queue.schedule([.downloadBook("test")])
        await fulfillment(of: [done], timeout: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFailureRestoresVisibilityAndRemainsRetryable() async {
        let failed = expectation(description: "failed deletion surfaced")
        let target = LocalDeletionTarget.localSeries("missing")
        let queue = DeferredDeletionQueue(delayNanoseconds: 1_000_000, operation: { _ in throw LocalCatalogError.targetNotFound }, onResult: { _, result in
            if case .failure = result { failed.fulfill() }
        })
        await queue.schedule([target]); await fulfillment(of: [failed], timeout: 2)
        let hidden = await queue.hiddenTargets; XCTAssertFalse(hidden.contains(target))
    }

    func testReschedulingAndBatchUndoCannotCommitOldTimer() async throws {
        let never = expectation(description: "cancelled operation"); never.isInverted = true
        let targets: [LocalDeletionTarget] = [.localSeries("a"), .downloadBook("b")]
        let queue = DeferredDeletionQueue(delayNanoseconds: 30_000_000, operation: { _ in never.fulfill() })
        await queue.schedule(targets); await queue.schedule(targets)
        let restored = await queue.undo(targets); XCTAssertEqual(restored, Set(targets))
        await fulfillment(of: [never], timeout: 0.08)
    }
}
