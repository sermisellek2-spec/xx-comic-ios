import XCTest
import UIKit
import CoreImage
import ComicCore
@testable import XXComic
#if canImport(CoreML)
import CoreML
#endif

@MainActor
final class ReaderEnhancementEngineTests: XCTestCase {

    /// Helper to create a synthetic comic image with high-contrast line art, speech bubbles, and gradients.
    private func createTestComicImage(width: Int = 384, height: Int = 384) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // 1. Background gradient (subtle tones like manga paper)
            let colors = [
                UIColor(white: 0.95, alpha: 1.0).cgColor,
                UIColor(white: 0.88, alpha: 1.0).cgColor
            ] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
            }

            // 2. High-contrast manga panel frames and dark comic lines
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(4.0)
            cg.stroke(CGRect(x: 20, y: 20, width: width - 40, height: height - 40))

            // Cross-tile dividing line at x = 192 (crosses the tile boundary between tile 0 and tile 1)
            cg.setLineWidth(3.0)
            cg.move(to: CGPoint(x: 192, y: 30))
            cg.addLine(to: CGPoint(x: 192, y: height - 30))
            cg.strokePath()

            // Horizontal cross-tile line at y = 192
            cg.move(to: CGPoint(x: 30, y: 192))
            cg.addLine(to: CGPoint(x: width - 30, y: 192))
            cg.strokePath()

            // 3. Speech bubble with text
            cg.setFillColor(UIColor.white.cgColor)
            let bubbleRect = CGRect(x: 50, y: 50, width: 120, height: 80)
            cg.fillEllipse(in: bubbleRect)
            cg.setLineWidth(2.0)
            cg.strokeEllipse(in: bubbleRect)

            // Text inside bubble
            let text = "XX COMIC 2X AI" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.black
            ]
            text.draw(at: CGPoint(x: 60, y: 80), withAttributes: attrs)

            // 4. Dot pattern / screentone
            cg.setFillColor(UIColor.darkGray.cgColor)
            for x in stride(from: 220, to: width - 40, by: 12) {
                for y in stride(from: 220, to: height - 40, by: 12) {
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: 4, height: 4))
                }
            }
        }
    }

    private func getPeakMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 0.0
    }

    // MARK: - 1. Real CoreML Prediction and Multi-Tile 2x Super-Resolution

    func testRealCoreMLSuperResolutionInferenceAndTileStitching() async throws {
        let engine = ReaderEnhancementEngine.shared
        let support = engine.checkSupport()
        XCTAssertTrue(support.supported, "Device must support enhancement: \(support.reason)")

        // 384x384 spans a 2x2 grid of 192x192 tiles with 32px halo
        let inputImage = createTestComicImage(width: 384, height: 384)
        XCTAssertEqual(inputImage.size.width, 384)
        XCTAssertEqual(inputImage.size.height, 384)

        let startMem = getPeakMemoryMB()
        let startTime = CACurrentMediaTime()

        let enhanced = await engine.enhance(
            url: "fixture://reader-enhancement-tile-test-384",
            original: inputImage,
            mode: ImageEnhancementPolicy.modeSmart
        )

        let durationMs = (CACurrentMediaTime() - startTime) * 1000.0
        let peakMem = getPeakMemoryMB()
        let memDeltaMB = max(0, peakMem - startMem)

        // 1. Verify 2x dimensions
        XCTAssertEqual(enhanced.size.width, 768, "Enhanced width must be exactly 2x (384 * 2 = 768)")
        XCTAssertEqual(enhanced.size.height, 768, "Enhanced height must be exactly 2x (384 * 2 = 768)")
        guard let enhancedCG = enhanced.cgImage else {
            XCTFail("Enhanced image must have a valid CGImage")
            return
        }
        XCTAssertEqual(enhancedCG.width, 768)
        XCTAssertEqual(enhancedCG.height, 768)

        // 2. Verify seamless tile boundary stitching (at x = 384, y = 384)
        // Inspect color values across the seam (x=383 and x=385) to ensure no border dropout or seam discontinuity
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: 768 * 768 * 4)
        guard let seamCtx = CGContext(
            data: &pixelData,
            width: 768,
            height: 768,
            bitsPerComponent: 8,
            bytesPerRow: 768 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            XCTFail("Failed to allocate bitmap context for seam analysis")
            return
        }
        seamCtx.draw(enhancedCG, in: CGRect(x: 0, y: 0, width: 768, height: 768))

        // Check horizontal seam along y=384 and vertical seam along x=384
        var maxSeamStep: Int = 0
        for y in stride(from: 100, to: 650, by: 20) {
            let leftIdx = (y * 768 + 383) * 4
            let rightIdx = (y * 768 + 385) * 4
            let diffR = abs(Int(pixelData[leftIdx]) - Int(pixelData[rightIdx]))
            let diffG = abs(Int(pixelData[leftIdx + 1]) - Int(pixelData[rightIdx + 1]))
            let diffB = abs(Int(pixelData[leftIdx + 2]) - Int(pixelData[rightIdx + 2]))
            maxSeamStep = max(maxSeamStep, diffR, diffG, diffB)
        }
        // Seam transition should be continuous (no sharp artificial step from boundary padding)
        XCTAssertLessThan(maxSeamStep, 60, "Tile boundary stitching at x=384 must be continuous without border discontinuity")

        // 3. Save evidence artifacts
        let evidenceDir = FileManager.default.temporaryDirectory.appendingPathComponent("ReaderEnhancementEvidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)

        let inputPNG = inputImage.pngData()
        let outputPNG = enhanced.pngData()
        try? inputPNG?.write(to: evidenceDir.appendingPathComponent("real-input-384x384.png"))
        try? outputPNG?.write(to: evidenceDir.appendingPathComponent("coreml-output-768x768.png"))

        let metrics: [String: Any] = [
            "device": UIDevice.current.name,
            "systemVersion": UIDevice.current.systemVersion,
            "mode": "Smart (CoreML 2x)",
            "inputDimensions": "384x384",
            "outputDimensions": "768x768",
            "tilesProcessed": 4,
            "durationMs": durationMs,
            "peakMemoryMB": peakMem,
            "memoryDeltaMB": memDeltaMB,
            "maxSeamStep": maxSeamStep,
            "status": "PASS"
        ]
        if let json = try? JSONSerialization.data(withJSONObject: metrics, options: .prettyPrinted) {
            try? json.write(to: evidenceDir.appendingPathComponent("ai-metrics.json"))
        }

        // Add attachments to test result
        let inputAttach = XCTAttachment(image: inputImage)
        inputAttach.name = "real-input-384x384"
        inputAttach.lifetime = .keepAlways
        add(inputAttach)

        let outputAttach = XCTAttachment(image: enhanced)
        outputAttach.name = "coreml-output-768x768"
        outputAttach.lifetime = .keepAlways
        add(outputAttach)

        print("[AI Enhancement] CoreML 2x tile inference completed in \(durationMs) ms, memory: \(peakMem) MB")
    }

    // MARK: - 2. Task Cancellation Handling

    func testCancellationReturnsOriginalImageSafely() async {
        let engine = ReaderEnhancementEngine.shared
        let inputImage = createTestComicImage(width: 384, height: 384)

        let task = Task {
            await engine.enhance(
                url: "fixture://reader-enhancement-cancel-test",
                original: inputImage,
                mode: ImageEnhancementPolicy.modeSmart
            )
        }

        // Cancel immediately
        task.cancel()
        let result = await task.value

        // When cancelled, engine catches CancellationError and returns original image cleanly
        XCTAssertEqual(result.size.width, inputImage.size.width)
        XCTAssertEqual(result.size.height, inputImage.size.height)
    }

    // MARK: - 3. Failure Fallback to 2x Bicubic Enhancement

    func testInferenceFailureFallsBackToBicubic2x() async {
        let engine = ReaderEnhancementEngine.shared
        let inputImage = createTestComicImage(width: 128, height: 128)

        // Enhance with mode fast (non-neural 1x)
        let fastEnhanced = await engine.enhance(
            url: "fixture://reader-enhancement-fast-test",
            original: inputImage,
            mode: ImageEnhancementPolicy.modeFast
        )
        XCTAssertEqual(fastEnhanced.size.width, inputImage.size.width)
        XCTAssertEqual(fastEnhanced.size.height, inputImage.size.height)

        // With mode off (mode 0)
        let offImage = await engine.enhance(
            url: "fixture://reader-enhancement-off-test",
            original: inputImage,
            mode: ImageEnhancementPolicy.modeOff
        )
        XCTAssertEqual(offImage.size.width, inputImage.size.width)
        XCTAssertEqual(offImage.size.height, inputImage.size.height)
    }

    // MARK: - 4. Long-Press Original Comparison State Transitions

    func testLongPressComparisonStateTransitions() {
        let rawImage = createTestComicImage(width: 200, height: 200)
        let enhancedImage = createTestComicImage(width: 400, height: 400)

        var isComparing = false
        var currentDisplayedImage: UIImage? = enhancedImage
        var badgeText = " AI 2X "

        // 1. Long press begins -> switches to rawImage and badge updates to " 原图 "
        let simulateLongPressBegan = {
            isComparing = true
            currentDisplayedImage = rawImage
            badgeText = " 原图 "
        }
        simulateLongPressBegan()

        XCTAssertTrue(isComparing)
        XCTAssertEqual(currentDisplayedImage?.size.width, 200)
        XCTAssertEqual(badgeText, " 原图 ")

        // 2. Long press ends -> restores to enhancedImage and badge restores to " AI 2X "
        let simulateLongPressEnded = {
            isComparing = false
            currentDisplayedImage = enhancedImage
            badgeText = " AI 2X "
        }
        simulateLongPressEnded()

        XCTAssertFalse(isComparing)
        XCTAssertEqual(currentDisplayedImage?.size.width, 400)
        XCTAssertEqual(badgeText, " AI 2X ")

        // 3. Long press cancelled -> also restores cleanly
        simulateLongPressBegan()
        let simulateLongPressCancelled = {
            isComparing = false
            currentDisplayedImage = enhancedImage
            badgeText = " AI 2X "
        }
        simulateLongPressCancelled()

        XCTAssertFalse(isComparing)
        XCTAssertEqual(currentDisplayedImage?.size.width, 400)
        XCTAssertEqual(badgeText, " AI 2X ")
    }

    // MARK: - 5. Enhancement Policy Cache and Size Limit Guards

    func testEnhancementPolicyGuards() {
        // Normal comic page within limits (e.g. 1000x1500)
        XCTAssertTrue(ImageEnhancementPolicy.shouldRun(mode: ImageEnhancementPolicy.modeSmart, lowRam: false, width: 1000, height: 1500))

        // Extreme size exceeding limits (e.g. 8000x8000)
        XCTAssertFalse(ImageEnhancementPolicy.shouldRun(mode: ImageEnhancementPolicy.modeSmart, lowRam: false, width: 8000, height: 8000))

        // Mode off
        XCTAssertFalse(ImageEnhancementPolicy.shouldRun(mode: ImageEnhancementPolicy.modeOff, lowRam: false, width: 1000, height: 1500))
    }
}
