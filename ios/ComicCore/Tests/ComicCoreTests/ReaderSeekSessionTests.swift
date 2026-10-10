import XCTest
@testable import ComicCore

final class ReaderSeekSessionTests: XCTestCase {
    func testSessionLifecycle() {
        let session = ReaderSeekSession()
        XCTAssertFalse(session.isTracking)

        session.start(token: 100, value: 5)
        XCTAssertTrue(session.isTracking)

        // Change during tracking does not commit immediately (returns nil)
        let intermediate = session.change(token: 100, value: 8, fromUser: true)
        XCTAssertNil(intermediate)

        // Stop with matching token commits the latest preview value
        let committed = session.stop(token: 100)
        XCTAssertEqual(committed, 8)
        XCTAssertFalse(session.isTracking)
    }

    func testNonTouchCommitImmediately() {
        let session = ReaderSeekSession()
        // Non-touch change (e.g. keyboard) commits directly
        let committed = session.change(token: 1, value: 3, fromUser: true)
        XCTAssertEqual(committed, 3)
    }

    func testCancellationDiscardsPreview() {
        let session = ReaderSeekSession()
        session.start(token: 100, value: 5)
        _ = session.change(token: 100, value: 12, fromUser: true)
        session.cancel()
        XCTAssertFalse(session.isTracking)

        // Stop after cancel returns nil
        let committed = session.stop(token: 100)
        XCTAssertNil(committed)
    }

    func testMismatchedTokenCancelsSession() {
        let session = ReaderSeekSession()
        session.start(token: 100, value: 5)
        _ = session.change(token: 999, value: 10, fromUser: true)
        XCTAssertFalse(session.isTracking)
    }

    func testBubbleLeftPinning() {
        // Centered bubble
        let pos1 = ReaderSeekSession.bubbleLeft(center: 200, bubbleWidth: 80, viewportWidth: 400, margin: 10)
        XCTAssertEqual(pos1, 160) // 200 - 40 = 160

        // Pinned to left margin
        let pos2 = ReaderSeekSession.bubbleLeft(center: 20, bubbleWidth: 80, viewportWidth: 400, margin: 10)
        XCTAssertEqual(pos2, 10)

        // Pinned to right margin
        let pos3 = ReaderSeekSession.bubbleLeft(center: 390, bubbleWidth: 80, viewportWidth: 400, margin: 10)
        XCTAssertEqual(pos3, 310) // 400 - 10 - 80 = 310
    }
}
