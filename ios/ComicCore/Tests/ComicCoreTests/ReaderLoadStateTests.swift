import XCTest
@testable import ComicCore

final class ReaderLoadStateTests: XCTestCase {
    func testDirectoryVerificationBeforeChapterSuccessIsRestoredAfterLoading() {
        var state = ReaderLoadState()
        state.chapterStarted()
        state.directoryFinished(error: Mh18SourceError.verificationRequired)
        XCTAssertNil(state.visibleFailure)
        state.chapterFinished()
        XCTAssertFalse(state.chapterLoading)
        XCTAssertEqual(state.visibleFailure?.kind, .directory)
        XCTAssertEqual(state.visibleFailure?.error as? Mh18SourceError, .verificationRequired)
    }

    func testDirectorySuccessNeverClearsChapterFailureAndRetryRestoresDirectoryFailure() {
        var state = ReaderLoadState()
        state.chapterStarted()
        state.chapterFinished(error: Mh18SourceError.verificationRequired)
        state.directoryFinished()
        XCTAssertEqual(state.visibleFailure?.kind, .chapter)
        state.directoryFinished(error: Mh18SourceError.invalidResponse("directory"))
        XCTAssertEqual(state.visibleFailure?.kind, .chapter)
        state.chapterStarted()
        XCTAssertNil(state.visibleFailure)
        state.chapterFinished()
        XCTAssertEqual(state.visibleFailure?.kind, .directory)
    }

    func testIndependentCancellationLeavesLoadingAndOffersTheSameChapterRetry() {
        var state = ReaderLoadState()
        state.chapterStarted()
        state.chapterFinished(error: CancellationError())
        XCTAssertFalse(state.chapterLoading)
        XCTAssertEqual(state.visibleFailure?.kind, .chapter)
        XCTAssertTrue(state.visibleFailure?.error is CancellationError)
        state.chapterStarted()
        state.chapterFinished()
        XCTAssertNil(state.visibleFailure)
    }
}
