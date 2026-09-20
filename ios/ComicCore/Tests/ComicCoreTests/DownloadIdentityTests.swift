import XCTest
@testable import ComicCore

final class DownloadIdentityTests: XCTestCase {
    func testSignedImageCredentialsAreDiscardedButScrambleIdentitySurvives() {
        XCTAssertEqual(
            "https://cdn/image.jpg?scramble_id=20",
            DownloadModels.imageIdentity("https://cdn/image.jpg?token=secret&scramble_id=20&expires=1")
        )
        XCTAssertTrue(DownloadModels.sameImage("https://cdn/image.jpg?token=old", "https://cdn/image.jpg?token=new"))
        XCTAssertFalse(DownloadModels.sameImage("https://cdn/image.jpg?scramble_id=20", "https://cdn/image.jpg?scramble_id=21"))
    }

    func testStableIdsDistinguishSourcesAndComponentBoundaries() throws {
        let id1 = try DownloadModels.bookId(source: "a", comic: "bc")
        let id2 = try DownloadModels.bookId(source: "ab", comic: "c")
        XCTAssertNotEqual(id1, id2)

        let s1 = try DownloadModels.bookId(source: "source1", comic: "same")
        let s2 = try DownloadModels.bookId(source: "source2", comic: "same")
        XCTAssertNotEqual(s1, s2)
    }

    func testEmptyComponentThrowsInvalidIdentity() {
        XCTAssertThrowsError(try DownloadModels.key(["source", ""])) { error in
            XCTAssertEqual(error as? DownloadError, DownloadError.invalidIdentity)
        }
    }
}
