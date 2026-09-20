import XCTest
@testable import ComicCore

final class Mh18VerificationAttemptTests: XCTestCase {
    func testAutomaticRecoveryNeverExtendsDeadlineAndStopsAfterTwoReloads() {
        var attempt = Mh18VerificationAttempt(startedAt: 10)
        XCTAssertTrue(attempt.recover(now: 20))
        XCTAssertTrue(attempt.recover(now: 30))
        XCTAssertFalse(attempt.recover(now: 40))
        XCTAssertEqual(attempt.deadline, 130)
        XCTAssertFalse(attempt.accepts(attempt.token, now: 130))
    }

    func testNavigationAndManualRetryRejectOldProbeEvenWithSameNavigationNumber() {
        var attempt = Mh18VerificationAttempt(startedAt: 0)
        let first = attempt.token
        attempt.navigationStarted()
        XCTAssertFalse(attempt.accepts(first, now: 1))
        let next = attempt.token
        XCTAssertTrue(attempt.accepts(next, now: 1))
        attempt = Mh18VerificationAttempt(startedAt: 100)
        XCTAssertEqual(attempt.deadline, 220)
        XCTAssertFalse(attempt.accepts(first, now: 101))
        XCTAssertFalse(attempt.accepts(next, now: 101))
        XCTAssertTrue(attempt.accepts(attempt.token, now: 219))
    }

    func testStoppedAndExpiredProbeCannotSucceedAndSuccessIsTerminal() {
        var attempt = Mh18VerificationAttempt(startedAt: 0)
        let token = attempt.token
        XCTAssertFalse(attempt.complete(token, now: 120))
        attempt.stop()
        XCTAssertFalse(attempt.complete(token, now: 2))
        attempt = Mh18VerificationAttempt(startedAt: 200)
        XCTAssertTrue(attempt.complete(attempt.token, now: 201))
        XCTAssertFalse(attempt.accepts(attempt.token, now: 202))
        XCTAssertFalse(attempt.recover(now: 202))
    }
}
