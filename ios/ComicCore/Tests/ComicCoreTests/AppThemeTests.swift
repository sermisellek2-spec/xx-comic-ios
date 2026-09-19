import XCTest
@testable import ComicCore

final class AppThemeTests: XCTestCase {
    func testAutomaticThemeSwitchesAtEightAndEighteenInLocalTime() {
        for (hour, dark) in [(0, true), (7, true), (8, false), (17, false), (18, true), (23, true)] {
            XCTAssertEqual(AppTheme.automatic.isDark(hour: hour), dark)
        }
        XCTAssertFalse(AppTheme.light.isDark(hour: 23))
        XCTAssertTrue(AppTheme.dark.isDark(hour: 12))
    }
}
