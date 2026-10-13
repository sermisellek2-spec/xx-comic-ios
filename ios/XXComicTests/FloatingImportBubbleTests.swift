import XCTest
import UIKit
@testable import XXComic

@MainActor
final class FloatingImportBubbleTests: XCTestCase {
    private func settings() -> (String, UserDefaults) {
        let name = "bubble-tests." + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }

    func testFreshPositionUsesAndroidDefaultAndDoesNotWritePreferences() {
        let (name, defaults) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let bubble = FloatingImportBubble(defaults: defaults); parent.addSubview(bubble)
        bubble.positionInParent()
        XCTAssertEqual(bubble.frame.minX, 393 - 16 - 54, accuracy: 0.01)
        XCTAssertEqual(bubble.frame.minY, 16 + 0.88 * (852 - 54 - 20 - 16), accuracy: 0.01)
        XCTAssertNil(defaults.object(forKey: "floating_bubble_snap_left"))
        XCTAssertNil(defaults.object(forKey: "floating_bubble_y_fraction"))
    }

    func testDraggedEdgeAndFractionSurviveNewViewAndChangedParentGeometry() {
        let (name, defaults) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let first = FloatingImportBubble(defaults: defaults); parent.addSubview(first)
        first.frame.origin = CGPoint(x: 25, y: 200); first.snapToEdge()
        XCTAssertTrue(defaults.bool(forKey: "floating_bubble_snap_left"))
        let fraction = defaults.double(forKey: "floating_bubble_y_fraction")
        let availableHeight: Double = 852.0 - 54.0 - 20.0 - 16.0
        let expectedFraction: Double = (200.0 - 16.0) / availableHeight
        XCTAssertEqual(fraction, expectedFraction, accuracy: 0.0001)
        let reopened = FloatingImportBubble(defaults: UserDefaults(suiteName: name)!)
        parent.addSubview(reopened); reopened.positionInParent()
        XCTAssertEqual(reopened.frame.origin.x, 16, accuracy: 0.01)
        XCTAssertEqual(reopened.frame.origin.y, 200, accuracy: 0.01)
        parent.bounds.size = CGSize(width: 852, height: 393); reopened.positionInParent()
        XCTAssertEqual(reopened.frame.minX, 16, accuracy: 0.01)
        XCTAssertEqual(reopened.frame.minY, 16 + CGFloat(fraction) * (393 - 54 - 20 - 16), accuracy: 0.01)
        XCTAssertLessThanOrEqual(reopened.frame.maxY, parent.bounds.maxY - 20)
        XCTAssertEqual(defaults.double(forKey: "floating_bubble_y_fraction"), fraction)
    }

    func testOutOfRangeDragClampsAndInvalidSavedFractionIsReadWithoutOverwriting() {
        let (name, defaults) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 834, height: 1210))
        let bubble = FloatingImportBubble(defaults: defaults); parent.addSubview(bubble)
        bubble.frame.origin = CGPoint(x: 5000, y: 5000); bubble.snapToEdge(); bubble.positionInParent()
        XCTAssertFalse(defaults.bool(forKey: "floating_bubble_snap_left"))
        XCTAssertEqual(defaults.double(forKey: "floating_bubble_y_fraction"), 1)
        XCTAssertEqual(bubble.frame.maxX, 834 - 16, accuracy: 0.01)
        XCTAssertEqual(bubble.frame.maxY, 1210 - 20, accuracy: 0.01)
        defaults.set("damaged", forKey: "floating_bubble_y_fraction"); bubble.positionInParent()
        XCTAssertEqual(bubble.frame.minY, 16 + 0.88 * (1210 - 54 - 20 - 16), accuracy: 0.01)
        XCTAssertEqual(defaults.string(forKey: "floating_bubble_y_fraction"), "damaged")
        defaults.set(-3, forKey: "floating_bubble_y_fraction"); bubble.positionInParent()
        XCTAssertEqual(bubble.frame.minY, 16, accuracy: 0.01)
        XCTAssertEqual(defaults.integer(forKey: "floating_bubble_y_fraction"), -3)
    }
}
