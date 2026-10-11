import XCTest
@testable import ComicCore

final class DiscoveryHeaderGestureTests: XCTestCase {
    func testHorizontalSmallAndEndedGesturesDoNotCollapseTools() {
        var gesture = DiscoveryHeaderGesture()
        XCTAssertEqual(gesture.move(x: 0, y: -100), 0)
        gesture.begin(x: 50, y: 100)
        XCTAssertEqual(gesture.move(x: 50, y: 89), 0)
        XCTAssertEqual(gesture.move(x: 100, y: 80), 0)
        gesture.end()
        XCTAssertEqual(gesture.move(x: 50, y: 0), 0)
    }
    func testReversingFingerDirectionExpandsToolsWithoutDependingOnScrollOffset() {
        var gesture = DiscoveryHeaderGesture()
        gesture.begin(x: 50, y: 100)
        XCTAssertEqual(gesture.move(x: 50, y: 80), -1)
        XCTAssertEqual(gesture.move(x: 50, y: 78), 0)
        XCTAssertEqual(gesture.move(x: 50, y: 95), 1)
    }
}
