import Foundation
import XCTest
@testable import ComicCore

final class JmImageTransformTests: XCTestCase {
    func testOfficialVectorUsesHexCharacterAndStripsOnlyFinalExtension() throws {
        XCTAssertEqual(try JmImageTransform.slices(aid: 1_114_754, scrambleID: 220_980, fileName: "00010.webp"), 4)
        XCTAssertEqual(try JmImageTransform.slices(aid: 1_114_754, scrambleID: 220_980, fileName: "00010.jpg"), 4)
        XCTAssertEqual(try JmImageTransform.slices(aid: 1_114_754, scrambleID: 220_980, fileName: "00010"), 4)
    }

    func testThresholdsAndInvalidNumbers() throws {
        XCTAssertEqual(try JmImageTransform.slices(aid: 100, scrambleID: 101, fileName: "1.jpg"), 0)
        XCTAssertEqual(try JmImageTransform.slices(aid: 268_849, scrambleID: 1, fileName: "1.jpg"), 10)
        XCTAssertEqual(try JmImageTransform.slices(aid: 268_850, scrambleID: 1, fileName: "00001.jpg"), 6)
        XCTAssertEqual(try JmImageTransform.slices(aid: 421_925, scrambleID: 1, fileName: "00001.jpg"), 18)
        XCTAssertEqual(try JmImageTransform.slices(aid: 421_926, scrambleID: 1, fileName: "00001.jpg"), 14)
        XCTAssertEqual(try JmImageTransform.slices(aid: -1, scrambleID: 0, fileName: "1.jpg"), 0)
        XCTAssertEqual(try JmImageTransform.slices(aid: 1, scrambleID: -1, fileName: "1.jpg"), 0)
    }

    func testURLGateAndRawFileName() throws {
        for url in ["https://cdn-msp.18comic.vip/media/photos/1114754/00010.webp?scramble_id=220980", "http://cdn-msp3.18comic.vip/media/photos/1114754/00010.jpg?x=1&scramble_id=220980"] {
            XCTAssertEqual(try JmImageTransform.slices(imageURL: url), 4)
        }
        for url in ["https://other.18comic.vip/media/photos/1114754/00010.webp?scramble_id=220980", "https://cdn-msp.18comic.vip.evil.org/media/photos/1114754/00010.webp?scramble_id=220980", "https://cdn-msp.18comic.vip:444/media/photos/1114754/00010.webp?scramble_id=220980", "https://user@cdn-msp.18comic.vip/media/photos/1114754/00010.webp?scramble_id=220980", "file:///media/photos/1114754/00010.webp?scramble_id=220980", "https://cdn-msp.18comic.vip/media/photos/1114754/00010.webp", "https://cdn-msp.18comic.vip/media/photos/1114754/00010.webp?scramble_id=-1", "https://cdn-msp.18comic.vip/media/photos/999999999999999999999999/00010.webp?scramble_id=1"] {
            XCTAssertEqual(try JmImageTransform.slices(imageURL: url), 0, url)
        }
    }

    func testRemainderAndEveryRowCoveredExactlyOnce() {
        let bounds = JmImageTransform.bounds(height: 1499, slices: 14)
        XCTAssertEqual(bounds.count, 14)
        XCTAssertEqual(bounds.first, .init(sourceY: 1391, targetY: 0, height: 108))
        XCTAssertEqual(bounds.last, .init(sourceY: 0, targetY: 1392, height: 107))
        XCTAssertEqual(bounds.flatMap { Array($0.sourceY..<($0.sourceY + $0.height)) }.sorted(), Array(0..<1499))
        XCTAssertEqual(bounds.flatMap { Array($0.targetY..<($0.targetY + $0.height)) }, Array(0..<1499))
    }

    func testNoTransformForTooShortOrInvalidDimensions() {
        for (height, slices) in [(3, 4), (0, 4), (-1, 4), (10, 0), (10, 1), (10, -1)] {
            XCTAssertTrue(JmImageTransform.bounds(height: height, slices: slices).isEmpty)
        }
        XCTAssertEqual(JmImageTransform.bounds(height: 4, slices: 4).map(\.sourceY), [3, 2, 1, 0])
    }

    func testCancelledTransformDoesNotReturnAnApparentlyDecodedImage() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try JmImageTransform.slices(aid: 1_114_754, scrambleID: 220_980, fileName: "00010.webp")
        }
        do { _ = try await task.value; XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
