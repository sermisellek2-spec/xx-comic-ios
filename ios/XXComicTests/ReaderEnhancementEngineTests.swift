import XCTest
import UIKit
import CoreImage
import ComicCore
@testable import XXComic

private final class PredictionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor
final class ReaderEnhancementEngineTests: XCTestCase {
    private func comicImage(width: Int = 384, height: Int = 384) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(white: 0.95, alpha: 1).cgColor, UIColor(white: 0.85, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
            cg.setStrokeColor(UIColor.black.cgColor); cg.setLineWidth(3)
            cg.stroke(CGRect(x: 20, y: 20, width: width - 40, height: height - 40))
            ("XX COMIC 2X AI" as NSString).draw(at: CGPoint(x: 40, y: 70), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.black])
            UIColor.red.setFill(); cg.fillEllipse(in: CGRect(x: 40, y: 120, width: 45, height: 70))
            UIColor.blue.setFill(); cg.fill(CGRect(x: width - 100, y: height - 100, width: 40, height: 40))
        }
    }
    private func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }
    func testRealCoreMLSuperResolutionInferenceAndTileStitching() async throws {
        let engine = ReaderEnhancementEngine()
        let input = comicImage()
        let start = CACurrentMediaTime(), memoryBefore = residentMemoryMB()
        let result = await engine.enhanceResult(url: "fixture://real-tiles", original: input, mode: ImageEnhancementPolicy.modeSmart)
        let durationMs = (CACurrentMediaTime() - start) * 1000
        XCTAssertEqual(result.method, .neural, "Fallback cannot count as successful CoreML inference")
        XCTAssertEqual(result.tilesProcessed, 4)
        let output = try XCTUnwrap(result.image.cgImage)
        XCTAssertEqual(output.width, 768); XCTAssertEqual(output.height, 768)
        var pixels = [UInt8](repeating: 0, count: 768 * 768 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 768, height: 768, bitsPerComponent: 8,
            bytesPerRow: 768 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(output, in: CGRect(x: 0, y: 0, width: 768, height: 768))
        var maxStep = 0
        for position in stride(from: 420, to: 520, by: 10) {
            for (a, b) in [(position * 768 + 383, position * 768 + 385), (383 * 768 + position, 385 * 768 + position)] {
                for channel in 0..<3 { maxStep = max(maxStep, abs(Int(pixels[a * 4 + channel]) - Int(pixels[b * 4 + channel]))) }
            }
        }
        XCTAssertLessThan(maxStep, 60)
        // A black/gray border must not become a colored checkerboard after channel shuffling.
        // The symmetric top/bottom border also makes this independent of bitmap row orientation.
        var maxGrayEdgeChroma = 0
        for y in 30..<60 {
            for x in 400..<700 {
                let offset = (y * 768 + x) * 4
                let rgb = (0..<3).map { Int(pixels[offset + $0]) }
                maxGrayEdgeChroma = max(maxGrayEdgeChroma, rgb.max()! - rgb.min()!)
            }
        }
        XCTAssertLessThan(maxGrayEdgeChroma, 80, "NCNN PixelShuffle semantics must preserve neutral edges")
        let metrics: [String: Any] = ["device": UIDevice.current.name, "systemVersion": UIDevice.current.systemVersion,
            "method": result.method.rawValue, "tilesProcessed": result.tilesProcessed, "inputDimensions": "384x384",
            "outputDimensions": "768x768", "durationMs": durationMs, "residentMemoryBeforeMB": memoryBefore,
            "residentMemoryAfterMB": residentMemoryMB(), "maxSeamStep": maxStep, "maxGrayEdgeChroma": maxGrayEdgeChroma]
        let data = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
        let json = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        json.name = "reader-ai-metrics"; json.lifetime = .keepAlways; add(json)
        for (name, image) in [("real-input-384x384", input), ("coreml-output-768x768", result.image)] {
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        print("[AI Enhancement] " + String(decoding: data, as: UTF8.self))
    }
    func testCancellationStopsBeforeNextPredictionTile() async throws {
        let counter = PredictionCounter()
        let engine = ReaderEnhancementEngine(tilePredictor: { _, _, input in
            counter.increment(); Thread.sleep(forTimeInterval: 0.2)
            return input.transformed(by: CGAffineTransform(scaleX: 2, y: 2))
        })
        let input = comicImage()
        let task = Task { await engine.enhanceResult(url: "fixture://cancel-tiles", original: input, mode: ImageEnhancementPolicy.modeSmart) }
        for _ in 0..<400 where counter.value == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(counter.value, 1)
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.method, .cancelled)
        XCTAssertTrue(result.image === input)
        XCTAssertEqual(counter.value, 1)
        XCTAssertNil(engine.cached(url: "fixture://cancel-tiles", original: input, mode: ImageEnhancementPolicy.modeSmart))
    }
    func testInferenceFailureFallsBackToBicubic2x() async {
        let counter = PredictionCounter()
        let engine = ReaderEnhancementEngine(tilePredictor: { _, _, _ in
            counter.increment(); throw CocoaError(.fileReadCorruptFile)
        })
        let input = comicImage(width: 128, height: 128)
        let result = await engine.enhanceResult(url: "fixture://failing-model", original: input, mode: ImageEnhancementPolicy.modeSmart)
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(result.method, .fallback)
        XCTAssertEqual(result.image.cgImage?.width, 256); XCTAssertEqual(result.image.cgImage?.height, 256)
        XCTAssertEqual(result.tilesProcessed, 0)
    }
    func testReaderCellCancelsEnhancementWhenLeavingScreen() async {
        let cell = ReaderImageCell(frame: CGRect(x: 0, y: 0, width: 384, height: 384))
        var preferences = ReaderPreferences(); preferences.enhancementMode = ImageEnhancementPolicy.modeSmart
        cell.apply(preferences)
        let started = expectation(description: "Cell starts enhancement")
        let cancelled = expectation(description: "Cell cancellation reaches enhancement")
        cell.enhancer = { _, image, _ in
            started.fulfill()
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { cancelled.fulfill() }
            return ReaderEnhancementEngine.Result(image: image, method: .neural, tilesProcessed: 1)
        }
        cell.displayLoadedImage(comicImage())
        await fulfillment(of: [started], timeout: 2)
        cell.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        await Task.yield()
        XCTAssertEqual(cell.enhancementMethod, .original)
    }
    func testReaderCellReuseRejectsLateResult() async {
        let cell = ReaderImageCell(frame: .zero)
        var preferences = ReaderPreferences(); preferences.enhancementMode = ImageEnhancementPolicy.modeSmart
        cell.apply(preferences)
        let started = expectation(description: "Old image task starts")
        var continuation: CheckedContinuation<ReaderEnhancementEngine.Result, Never>?
        cell.enhancer = { _, _, _ in
            await withCheckedContinuation { continuation = $0; started.fulfill() }
        }
        cell.displayLoadedImage(comicImage())
        await fulfillment(of: [started], timeout: 2)
        cell.prepareForReuse()
        continuation?.resume(returning: ReaderEnhancementEngine.Result(image: comicImage(), method: .neural, tilesProcessed: 1))
        await Task.yield(); await Task.yield()
        XCTAssertEqual(cell.enhancementMethod, .original)
    }
    func testEnhancementPolicyGuards() {
        XCTAssertTrue(ImageEnhancementPolicy.shouldRun(mode: 2, lowRam: false, width: 1000, height: 1500))
        XCTAssertFalse(ImageEnhancementPolicy.shouldRun(mode: 2, lowRam: false, width: 8000, height: 8000))
        XCTAssertFalse(ImageEnhancementPolicy.shouldRun(mode: 0, lowRam: false, width: 1000, height: 1500))
    }
}
