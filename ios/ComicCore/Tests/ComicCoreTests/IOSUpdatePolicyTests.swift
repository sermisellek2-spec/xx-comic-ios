import XCTest
@testable import ComicCore

final class IOSUpdatePolicyTests: XCTestCase {
    func testOnlyCurrentIOSRepositoryIPAOrReleasePageCanBeOpened() {
        for value in [
            "https://github.com/sermisellek2-spec/xx-comic-ios/releases/download/2.0.40/XXComic.ipa",
            "https://github.com/sermisellek2-spec/xx-comic-ios/releases/tag/2.0.40"
        ] {
            let release = AppRelease(versionName: "2.0.40", versionCode: 340, downloadUrl: value)
            XCTAssertEqual(IOSUpdatePolicy.browserURL(for: release).absoluteString, value)
        }
    }

    func testAndroidPackagesUnsafeURLsAndOtherRepositoriesFallBackToIOSReleases() {
        let values: [String?] = [nil, "", "xxcomic://update", "javascript:alert(1)",
            "https://example.com/app.ipa",
            "https://github.com/old/xx-comic/releases/download/v1/app.ipa",
            "https://github.com/sermisellek2-spec/xx-comic-ios/releases/download/v1/app.apk",
            "https://github.com/sermisellek2-spec/xx-comic-ios/releases-other/tag/v1",
            "https://user@github.com/sermisellek2-spec/xx-comic-ios/releases/tag/v1"]
        for value in values {
            XCTAssertEqual(IOSUpdatePolicy.browserURL(for: AppRelease(versionName: "2.0.40", versionCode: 340, downloadUrl: value)), IOSUpdatePolicy.releasesURL)
        }
    }
}
