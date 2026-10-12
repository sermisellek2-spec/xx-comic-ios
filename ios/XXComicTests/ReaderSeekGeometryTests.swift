import XCTest
import UIKit
@testable import XXComic

@MainActor
final class ReaderSeekGeometryTests: XCTestCase {
    func testTrackingPreviewsWithoutMovingThePageAndCancelRestoresTheCommittedValue() throws {
        let seek = ReaderSeekBar(frame: CGRect(x: 0, y: 60, width: 280, height: 40))
        seek.configure(currentPage: 1, total: 12, sessionToken: 9); seek.layoutIfNeeded()
        let slider = try XCTUnwrap(seek.subviews.compactMap { $0 as? UISlider }.first)
        let bubble = try XCTUnwrap(seek.subviews.compactMap { $0 as? UILabel }.first)
        var commits: [Int] = [], tracking: [Bool] = []
        seek.onCommit = { commits.append($0) }; seek.onTracking = { tracking.append($0) }
        slider.sendActions(for: .touchDown); slider.value = 8; slider.sendActions(for: .valueChanged)
        XCTAssertEqual(bubble.text, " 9 / 12 "); XCTAssertFalse(bubble.isHidden)
        XCTAssertTrue(commits.isEmpty, "Preview must not change the chapter/page before release")
        XCTAssertGreaterThanOrEqual(bubble.frame.minX, 0); XCTAssertLessThanOrEqual(bubble.frame.maxX, seek.bounds.width)
        slider.sendActions(for: .touchCancel)
        XCTAssertEqual(slider.value, 1); XCTAssertTrue(bubble.isHidden); XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(tracking, [true, false])
        slider.sendActions(for: .touchDown); slider.value = 10; slider.sendActions(for: .valueChanged)
        slider.sendActions(for: .touchUpInside)
        XCTAssertEqual(commits, [10]); XCTAssertTrue(bubble.isHidden)
    }
    func testAChangedChapterTokenCannotCommitAnOldTrackingPreview() throws {
        let seek = ReaderSeekBar(frame: CGRect(x: 0, y: 0, width: 240, height: 40))
        seek.configure(currentPage: 0, total: 10, sessionToken: 1); seek.layoutIfNeeded()
        let slider = try XCTUnwrap(seek.subviews.compactMap { $0 as? UISlider }.first)
        var commits: [Int] = []; seek.onCommit = { commits.append($0) }
        slider.sendActions(for: .touchDown); slider.value = 9; slider.sendActions(for: .valueChanged)
        seek.configure(currentPage: 2, total: 5, sessionToken: 2)
        slider.sendActions(for: .touchUpInside)
        XCTAssertTrue(commits.isEmpty); XCTAssertEqual(slider.value, 2)
    }
    func testCenteredToolbarGivesTheVisibleSliderATouchableParent() throws {
        let row = UIStackView()
        row.axis = .horizontal; row.alignment = .center
        let host = UIViewController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        row.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            row.topAnchor.constraint(equalTo: host.view.topAnchor),
            row.heightAnchor.constraint(equalToConstant: 42)
        ])
        let before = UIButton(type: .system), after = UIButton(type: .system)
        let seek = ReaderSeekBar()
        seek.configure(currentPage: 0, total: 4)
        let controls: [UIView] = [before, seek, after]
        for item in controls { row.addArrangedSubview(item) }
        before.widthAnchor.constraint(equalToConstant: 60).isActive = true
        after.widthAnchor.constraint(equalToConstant: 60).isActive = true
        host.view.layoutIfNeeded()
        seek.layoutIfNeeded()
        let slider = try XCTUnwrap(seek.subviews.compactMap { $0 as? UISlider }.first)
        print("READER_SEEK_GEOMETRY row=\(row.bounds) parent=\(seek.bounds) slider=\(slider.frame) alignmentInsets=\(slider.alignmentRectInsets) accessibility=\(slider.isAccessibilityElement)")
        XCTAssertGreaterThan(seek.bounds.height, 0, "A drawn control with a zero-height ancestor is not operable")
        XCTAssertTrue(seek.bounds.contains(slider.frame))
        let thumb = slider.thumbRect(forBounds: slider.bounds, trackRect: slider.trackRect(forBounds: slider.bounds), value: slider.value)
        let point = slider.convert(CGPoint(x: thumb.midX, y: thumb.midY), to: row)
        XCTAssertTrue(row.hitTest(point, with: nil) === slider, "The actual thumb must receive touches")
        XCTAssertTrue(slider.isAccessibilityElement)
        slider.value = slider.maximumValue
        let lastThumb = slider.thumbRect(forBounds: slider.bounds, trackRect: slider.trackRect(forBounds: slider.bounds), value: slider.value)
        let lastPoint = slider.convert(CGPoint(x: lastThumb.midX, y: lastThumb.midY), to: row)
        XCTAssertTrue(row.hitTest(lastPoint, with: nil) === slider, "The last-page thumb must also receive touches")
    }
}
