import Foundation
import XCTest
@testable import ComicCore
#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(PDFKit)
import CoreGraphics
import ImageIO
import PDFKit
#endif

final class PdfRendererTests: XCTestCase {
    func testAndroidScaleRoundingAndPixelBudget() throws {
        XCTAssertEqual(try PdfPublication.renderSize(width: 600, height: 800), .init(width: 1500, height: 2000))
        XCTAssertEqual(try PdfPublication.renderSize(width: 600, height: 800, maximumDimension: 720), .init(width: 600, height: 800))
        XCTAssertEqual(try PdfPublication.renderSize(width: 101, height: 201), .init(width: 253, height: 503))
        for pair in [(100_000.0, 100_000.0), (Double.greatestFiniteMagnitude, 1.0), (1.0, Double.greatestFiniteMagnitude), (1e200, 1e200)] {
            let size = try PdfPublication.renderSize(width: pair.0, height: pair.1)
            XCTAssertGreaterThanOrEqual(size.width, 1)
            XCTAssertGreaterThanOrEqual(size.height, 1)
            XCTAssertLessThanOrEqual(size.width * size.height, 24_000_000)
        }
        for invalid in [0, -1, Double.infinity, Double.nan] {
            XCTAssertThrowsError(try PdfPublication.renderSize(width: invalid, height: 800))
            XCTAssertThrowsError(try PdfPublication.renderSize(width: 600, height: invalid))
        }
    }

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(PDFKit)
    private func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("native.pdf")
        var box = CGRect(x: 0, y: 0, width: 80, height: 120)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for color in [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)] {
            context.beginPDFPage(nil)
            // Leave the background transparent: renderer must supply white.
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
            context.endPDFPage()
        }
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(url: url))
        try XCTUnwrap(document.page(at: 1)).rotation = 90
        XCTAssertTrue(document.write(to: url))
        return url
    }
    private func pixels(_ data: Data) throws -> (Int, Int, [UInt8]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (image.width, image.height, bytes)
    }
    func testNativeInspectionRenderingPageOrderRotationAndWhiteBackground() throws {
        let url = try fixture(), publication = try PdfRenderer.inspect(url)
        XCTAssertEqual(publication.pages, [.init(width: 80, height: 120), .init(width: 120, height: 80)])
        let first = try pixels(PdfRenderer.render(url, pageIndex: 0))
        let second = try pixels(PdfRenderer.render(url, pageIndex: 1))
        XCTAssertEqual(first.0, 200); XCTAssertEqual(first.1, 300)
        XCTAssertEqual(second.0, 300); XCTAssertEqual(second.1, 200)
        // Compare the colored regions' centroids, independent of bitmap scanline direction.
        // The lower-left block rotates to upper-left; a missing rotation cannot satisfy this.
        func centroid(_ p: (Int, Int, [UInt8]), channel: Int) -> (Double, Double, Double) {
            var count = 0.0, x = 0.0, y = 0.0
            for row in 0..<p.1 {
                for column in 0..<p.0 {
                    let offset = (row * p.0 + column) * 4
                    if p.2[offset + channel] > 180 && p.2[offset + 1] < 70 && p.2[offset + (2 - channel)] < 70 {
                        count += 1; x += Double(column); y += Double(row)
                    }
                }
            }
            return (x / max(1, count) / Double(p.0), y / max(1, count) / Double(p.1), count / Double(p.0 * p.1))
        }
        let red = centroid(first, channel: 0), blue = centroid(second, channel: 2)
        XCTAssertEqual(red.0, 0.25, accuracy: 0.02)
        XCTAssertEqual(blue.0, 0.25, accuracy: 0.02)
        XCTAssertEqual(red.1 + blue.1, 1, accuracy: 0.02)
        XCTAssertEqual(red.2, 0.25, accuracy: 0.02)
        XCTAssertEqual(blue.2, 0.25, accuracy: 0.02)
        func sample(_ p: (Int, Int, [UInt8]), x: Int, y: Int) -> [UInt8] {
            let offset = (y * p.0 + x) * 4
            return Array(p.2[offset..<(offset + 3)])
        }
        XCTAssertTrue(sample(first, x: 175, y: 250).allSatisfy { $0 > 240 })
        XCTAssertTrue(sample(second, x: 250, y: 25).allSatisfy { $0 > 240 })
        XCTAssertThrowsError(try PdfRenderer.render(url, pageIndex: -1))
        XCTAssertThrowsError(try PdfRenderer.render(url, pageIndex: 2))
        XCTAssertThrowsError(try PdfRenderer.render(url, pageIndex: 0, quality: .nan))
    }
    func testNativeMalformedEmptyEncryptedDocumentsAndCancellationRejected() async throws {
        let url = try fixture()
        let encrypted = url.deletingLastPathComponent().appendingPathComponent("locked.pdf")
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertTrue(document.write(to: encrypted, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        XCTAssertThrowsError(try PdfRenderer.inspect(encrypted))
        XCTAssertThrowsError(try PdfRenderer.render(encrypted, pageIndex: 0))
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try PdfRenderer.inspect(url)
        }
        do { _ = try await worker.value; XCTFail("取消仍返回页面") } catch { XCTAssertTrue(error is CancellationError) }
        let empty = url.deletingLastPathComponent().appendingPathComponent("empty.pdf")
        var box = CGRect(x: 0, y: 0, width: 80, height: 120)
        try XCTUnwrap(CGContext(empty as CFURL, mediaBox: &box, nil)).closePDF()
        XCTAssertThrowsError(try PdfRenderer.inspect(empty))
        try Data("%PDF-1.7 truncated document".utf8).write(to: url)
        XCTAssertThrowsError(try PdfRenderer.inspect(url))
        XCTAssertThrowsError(try PdfRenderer.render(url, pageIndex: 0))
    }
#else
    func testNativePDFRenderingRequiresAppleFrameworks() throws {
        throw XCTSkip("CoreGraphics / ImageIO / PDFKit native PDF tests require an Apple host; injected dimensions do not verify PDF decoding.")
    }
#endif
}
