import XCTest
import UIKit
@testable import XXComic

@MainActor
final class RootTabGeometryTests: XCTestCase {
    func testAllTabsRemainStackedAtPhoneAndTabletPortraitAndLandscapeWidths() throws {
        // Frozen makeBottomNav: equal columns, 20pt icon, 4pt gap, 10pt title,
        // and 60pt application bar; window insets live below that content.
        for width in [CGFloat(393), 852, 834, 1210] {
            let items = ["书架", "发现", "设置"].map { UITabBarItem(title: $0, image: UIImage(systemName: "book"), selectedImage: nil) }
            let bar = RootTabBar(items: items)
            bar.frame = CGRect(x: 0, y: 0, width: width, height: 94)
            bar.setNeedsLayout(); bar.layoutIfNeeded()
            let buttons = try XCTUnwrap(bar.accessibilityElements as? [UIControl])
            XCTAssertEqual(buttons.count, 3)
            for (index, button) in buttons.enumerated() {
                button.layoutIfNeeded()
                let icon = try XCTUnwrap(button.subviews.compactMap { $0 as? UIImageView }.first)
                let title = try XCTUnwrap(button.subviews.compactMap { $0 as? UILabel }.first)
                XCTAssertEqual(button.frame.width, width / 3, accuracy: 0.5)
                XCTAssertEqual(icon.frame.width, 20, accuracy: 0.01)
                XCTAssertEqual(icon.frame.height, 20, accuracy: 0.01)
                XCTAssertEqual(icon.frame.midX, title.frame.midX, accuracy: 0.01)
                XCTAssertEqual(title.frame.minY - icon.frame.maxY, 4, accuracy: 0.01)
                XCTAssertEqual(title.font.pointSize, 10)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                XCTAssertLessThanOrEqual(button.frame.maxY, 60)
                XCTAssertEqual(button.isSelected, index == 0)
            }
            bar.select(2, animated: false)
            XCTAssertTrue(buttons[2].isSelected)
            XCTAssertTrue(buttons[2].accessibilityTraits.contains(.selected))
            XCTAssertFalse(buttons[0].isSelected)
        }
    }
}
