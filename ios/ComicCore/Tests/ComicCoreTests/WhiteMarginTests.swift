import XCTest
@testable import ComicCore

final class WhiteMarginTests: XCTestCase {
    func testPagedCropRetainsSafetyBorderAndStripPreservesVerticalEdges() {
        let pixel: (Int, Int) -> UInt32 = { x, y in
            (20..<180).contains(x) && (30..<270).contains(y) ? 0xff000000 : 0xffffffff
        }
        XCTAssertEqual(WhiteMarginDetector.detect(width: 200, height: 300, cropVertical: true, pixel: pixel),
                       ImageCrop(left: 18, top: 28, right: 182, bottom: 272))
        XCTAssertEqual(WhiteMarginDetector.detect(width: 200, height: 300, cropVertical: false, pixel: pixel),
                       ImageCrop(left: 18, top: 0, right: 182, bottom: 300))
    }
    func testWhitePageAndOversizedMarginRollBackConservatively() {
        XCTAssertEqual(WhiteMarginDetector.detect(width: 200, height: 200, cropVertical: true) { _, _ in 0xffffffff },
                       ImageCrop(left: 0, top: 0, right: 200, bottom: 200))
        XCTAssertEqual(WhiteMarginDetector.detect(width: 200, height: 200, cropVertical: false) { x, _ in
            (40..<190).contains(x) ? 0xff000000 : 0xffffffff
        }, ImageCrop(left: 0, top: 0, right: 192, bottom: 200))
    }
    func testOneTextPixelOrTransparentPixelStopsCropping() {
        for mark: UInt32 in [0xff000000, 0x00ffffff, 0xfff4ffff] {
            let result = WhiteMarginDetector.detect(width: 200, height: 200, cropVertical: false) { x, y in
                if x == 5 && y == 100 { return mark }
                return (25..<180).contains(x) && (20..<180).contains(y) ? 0xff000000 : 0xfff8faf6
            }
            XCTAssertEqual(result.left, 3)
        }
    }
    func testSmallImageIsUnchanged() {
        XCTAssertEqual(WhiteMarginDetector.detect(width: 9, height: 30, cropVertical: true) { _, _ in 0xffffffff },
                       ImageCrop(left: 0, top: 0, right: 9, bottom: 30))
    }
}
