import XCTest
import UIKit
@testable import XXComic

@MainActor
final class ReaderSeekGeometryTests: XCTestCase {
    func testCenteredToolbarGivesTheVisibleSliderATouchableParent() throws {
        let row = UIStackView()
        row.axis = .horizontal; row.alignment = .center
        row.frame = CGRect(x: 0, y: 0, width: 393, height: 42)
        let before = UIButton(type: .system), after = UIButton(type: .system)
        let seek = ReaderSeekBar()
        seek.configure(currentPage: 0, total: 4)
        let controls: [UIView] = [before, seek, after]
        for item in controls { row.addArrangedSubview(item) }
        before.widthAnchor.constraint(equalToConstant: 60).isActive = true
        after.widthAnchor.constraint(equalToConstant: 60).isActive = true
        row.layoutIfNeeded()
        let slider = try XCTUnwrap(seek.subviews.compactMap { $0 as? UISlider }.first)
        XCTAssertGreaterThan(seek.bounds.height, 0, "A drawn control with a zero-height ancestor is not operable")
        XCTAssertTrue(seek.bounds.contains(slider.frame))
        let thumb = slider.thumbRect(forBounds: slider.bounds, trackRect: slider.trackRect(forBounds: slider.bounds), value: slider.value)
        let point = slider.convert(CGPoint(x: thumb.midX, y: thumb.midY), to: row)
        XCTAssertTrue(row.hitTest(point, with: nil) === slider, "The actual thumb must receive touches")
        XCTAssertTrue(slider.isAccessibilityElement)
    }
}
