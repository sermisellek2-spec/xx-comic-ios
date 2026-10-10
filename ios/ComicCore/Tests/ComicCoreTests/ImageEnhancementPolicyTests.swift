import XCTest
@testable import ComicCore

final class ImageEnhancementPolicyTests: XCTestCase {
    func testModeOffNeverRuns() {
        XCTAssertFalse(ImageEnhancementPolicy.shouldRun(mode: ImageEnhancementPolicy.modeOff, lowRam: false, width: 800, height: 1200))
    }

    func testTooSmallOrTooLargeImagesRejected() {
        // Less than 32px
        XCTAssertFalse(ImageEnhancementPolicy.shouldRun(mode: ImageEnhancementPolicy.modeFast, lowRam: false, width: 20, height: 20))
        // Greater than 4096px
        XCTAssertFalse(ImageEnhancementPolicy.shouldRun(mode: ImageEnhancementPolicy.modeFast, lowRam: false, width: 5000, height: 1000))
    }

    func testLowRamLimits() {
        // Safe size on low RAM (600x800 = 480,000 pixels)
        XCTAssertTrue(ImageEnhancementPolicy.shouldRun(mode: ImageEnhancementPolicy.modeFast, lowRam: true, width: 600, height: 800, heapLimit: 256 * 1024 * 1024, availableBytes: 128 * 1024 * 1024))

        // Normal size on regular RAM (800x1000 = 800,000 pixels)
        XCTAssertTrue(ImageEnhancementPolicy.shouldRun(mode: ImageEnhancementPolicy.modeFast, lowRam: false, width: 800, height: 1000, heapLimit: 256 * 1024 * 1024, availableBytes: 128 * 1024 * 1024))

        // Too big on low RAM (> 1,000,000 pixels)
        XCTAssertFalse(ImageEnhancementPolicy.shouldRun(mode: ImageEnhancementPolicy.modeFast, lowRam: true, width: 1200, height: 1600, heapLimit: 256 * 1024 * 1024, availableBytes: 128 * 1024 * 1024))
    }

    func testCacheKeyFormat() {
        let key = ImageEnhancementPolicy.cacheKey(sourceKey: "http://example.com/pic.jpg", mode: 1)
        XCTAssertEqual(key, "enhance:animevideov3-x2-20220424:1:http://example.com/pic.jpg")

        let fullKey = ImageEnhancementPolicy.cacheKey(sourceKey: "http://example.com/pic.jpg", mode: 1, width: 800, height: 1200, pixelRevision: 42)
        XCTAssertEqual(fullKey, "enhance:animevideov3-x2-20220424:1:http://example.com/pic.jpg:800x1200:42")
    }
}
