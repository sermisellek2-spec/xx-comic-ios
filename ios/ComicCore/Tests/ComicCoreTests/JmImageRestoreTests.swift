#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import XCTest
@testable import ComicCore

final class JmImageRestoreTests: XCTestCase {
    func testDistinctRowsReorderWithRemainderWithoutFlippingEachStrip() throws {
        let bytes = Data((0..<13).flatMap { [UInt8($0 * 10), 0, 0, 255] })
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let original = try XCTUnwrap(CGImage(width: 1, height: 13, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let restored = try JmImageTransform.restore(original, imageURL: "https://cdn-msp.18comic.vip/media/photos/1114754/00010.webp?scramble_id=220980")
        let result = try XCTUnwrap(restored.dataProvider?.data) as Data
        XCTAssertEqual(stride(from: 0, to: result.count, by: 4).map { result[$0] }, [90, 100, 110, 120, 60, 70, 80, 30, 40, 50, 0, 10, 20])
        XCTAssertEqual(restored.width, 1)
        XCTAssertEqual(restored.height, 13)
        let unchanged = try JmImageTransform.restore(original, imageURL: "https://example.org/image.jpg")
        XCTAssertTrue(unchanged === original)
    }
}
#endif
