import XCTest
@testable import ComicCore

final class AppUpdateCheckerTests: XCTestCase {
    func testParseValidRelease() throws {
        let json = """
        {
            "versionName": "2.0.30",
            "versionCode": 230,
            "size": 15480000,
            "sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
            "updateMode": "soft",
            "releaseNotes": "1. 优化阅读器体验\\n2. 修复闪退问题",
            "downloadUrl": "https://example.com/app.ipa"
        }
        """

        let release = try AppRelease.parse(from: json)
        XCTAssertEqual(release.versionName, "2.0.30")
        XCTAssertEqual(release.versionCode, 230)
        XCTAssertEqual(release.size, 15480000)
        XCTAssertEqual(release.updateMode, "soft")
        XCTAssertEqual(release.downloadUrl, "https://example.com/app.ipa")

        // 检查版本比较逻辑
        XCTAssertTrue(release.hasNewVersion(currentVersionCode: 229))
        XCTAssertFalse(release.hasNewVersion(currentVersionCode: 230))
        XCTAssertFalse(release.hasNewVersion(currentVersionCode: 231))
    }
}
