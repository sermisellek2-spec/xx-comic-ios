import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Decodes cover images with demand-sized subsampling while guaranteeing pixel-exact restoration
/// for rule-based scrambled covers before optional downscaling.
public enum CoverBitmapDecoder {
    public static let COVER_GRID_TARGET_WIDTH = 360
    public static let COVER_GRID_TARGET_HEIGHT = 480
    public static let COVER_HERO_TARGET_WIDTH = 720
    public static let COVER_HERO_TARGET_HEIGHT = 960
    public static let MAX_NON_TRANSFORM_DECODE_PIXELS: Int64 = 16_000_000
    public static let MAX_SAMPLE_SIZE = 64

    public static let coverGridTargetWidth = COVER_GRID_TARGET_WIDTH
    public static let coverGridTargetHeight = COVER_GRID_TARGET_HEIGHT
    public static let coverHeroTargetWidth = COVER_HERO_TARGET_WIDTH
    public static let coverHeroTargetHeight = COVER_HERO_TARGET_HEIGHT
    public static let maxNonTransformDecodePixels = MAX_NON_TRANSFORM_DECODE_PIXELS
    public static let maxSampleSize = MAX_SAMPLE_SIZE

    public struct DecodePlan: Equatable, Sendable {
        public let ruleTransform: String
        public let hasRuleTransform: Bool
        public let inSampleSize: Int
        public let downscaleAfterRestore: Bool
        public let targetWidth: Int
        public let targetHeight: Int

        public init(
            ruleTransform: String,
            hasRuleTransform: Bool,
            inSampleSize: Int,
            downscaleAfterRestore: Bool,
            targetWidth: Int,
            targetHeight: Int
        ) {
            self.ruleTransform = ruleTransform
            self.hasRuleTransform = hasRuleTransform
            self.inSampleSize = inSampleSize
            self.downscaleAfterRestore = downscaleAfterRestore
            self.targetWidth = targetWidth
            self.targetHeight = targetHeight
        }
    }

    /// Computes a power-of-two `inSampleSize >= 1` whose decoded width and height remain
    /// at least `reqWidth` and `reqHeight` while staying as close to the target as possible.
    /// Never upscales images smaller than the target.
    public static func calculateInSampleSize(
        rawWidth: Int,
        rawHeight: Int,
        reqWidth: Int,
        reqHeight: Int
    ) -> Int {
        guard rawWidth > 0, rawHeight > 0, reqWidth > 0, reqHeight > 0 else {
            return 1
        }
        var inSampleSize = 1
        if rawHeight > reqHeight || rawWidth > reqWidth {
            let halfHeight = rawHeight / 2
            let halfWidth = rawWidth / 2
            while (halfHeight / inSampleSize) >= reqHeight
                    && (halfWidth / inSampleSize) >= reqWidth {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    /// Computes aspect-preserving dimensions that fit inside `maxWidth x maxHeight`
    /// without upscaling when the source already fits.
    public static func computeScaledDimensions(
        width: Int,
        height: Int,
        maxWidth: Int,
        maxHeight: Int
    ) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else {
            return (0, 0)
        }
        guard maxWidth > 0, maxHeight > 0 else {
            return (width, height)
        }
        if width <= maxWidth && height <= maxHeight {
            return (width, height)
        }
        if Int64(width) * Int64(maxHeight) >= Int64(height) * Int64(maxWidth) {
            let outW = maxWidth
            var outH = max(1, Int((Double(height) * Double(maxWidth) / Double(width)).rounded()))
            if outH > maxHeight {
                outH = maxHeight
            }
            return (outW, outH)
        }
        let outH = maxHeight
        var outW = max(1, Int((Double(width) * Double(maxHeight) / Double(height)).rounded()))
        if outW > maxWidth {
            outW = maxWidth
        }
        return (outW, outH)
    }

    /// Returns `true` when a restored rule-transformed bitmap exceeds `1.5x` the
    /// requested cover bounds on either axis and should be scaled down to save memory.
    public static func shouldDownscaleRestoredBitmap(
        width: Int,
        height: Int,
        reqWidth: Int,
        reqHeight: Int
    ) -> Bool {
        guard width > 0, height > 0, reqWidth > 0, reqHeight > 0 else {
            return false
        }
        return Int64(width) * 2 > Int64(reqWidth) * 3
            || Int64(height) * 2 > Int64(reqHeight) * 3
    }

    /// Extracts canonical rule transform string if `imageUrl` carries one; otherwise empty.
    public static func resolveRuleTransform(_ imageUrl: String?) -> String {
        guard let imageUrl, !imageUrl.isEmpty else { return "" }
        if RuleImages.isRule(imageUrl) {
            return (try? RuleImages.transformation(imageUrl)) ?? ""
        }
        if let txRange = imageUrl.range(of: "#xx-tx=") {
            let encoded = String(imageUrl[txRange.upperBound...]).components(separatedBy: CharacterSet(charactersIn: "&#"))[0]
            if let decoded = try? RuleBase64.decode(encoded) {
                let tx = String(decoding: decoded, as: UTF8.self)
                if RuleBitmapTransform.isSupported(tx) {
                    return tx
                }
            }
        }
        if let bandRange = imageUrl.range(of: "#xx-bands=") {
            let numStr = String(imageUrl[bandRange.upperBound...]).components(separatedBy: CharacterSet(charactersIn: "&#"))[0]
            if let count = Int(numStr), count >= 2, count <= 100 {
                return "bands:\(count)"
            }
        }
        return ""
    }

    /// Pure Swift decode planner covering rule-transform safety and sample-size computation.
    public static func planDecode(
        rawWidth: Int,
        rawHeight: Int,
        imageUrl: String?,
        reqWidth: Int,
        reqHeight: Int
    ) -> DecodePlan {
        let transform = resolveRuleTransform(imageUrl)
        let hasTransform = !transform.isEmpty && RuleBitmapTransform.isSupported(transform)
        if hasTransform {
            let downscale = shouldDownscaleRestoredBitmap(
                width: rawWidth,
                height: rawHeight,
                reqWidth: reqWidth,
                reqHeight: reqHeight
            )
            let target: (width: Int, height: Int) = downscale
                ? computeScaledDimensions(width: rawWidth, height: rawHeight, maxWidth: reqWidth, maxHeight: reqHeight)
                : (max(0, rawWidth), max(0, rawHeight))
            return DecodePlan(
                ruleTransform: transform,
                hasRuleTransform: true,
                inSampleSize: 1,
                downscaleAfterRestore: downscale,
                targetWidth: target.width,
                targetHeight: target.height
            )
        }
        let sampleSize = clampNonTransformSampleSize(
            rawWidth: rawWidth,
            rawHeight: rawHeight,
            sampleSize: calculateInSampleSize(
                rawWidth: rawWidth,
                rawHeight: rawHeight,
                reqWidth: reqWidth,
                reqHeight: reqHeight
            )
        )
        let outW = rawWidth > 0 ? max(1, rawWidth / sampleSize) : 0
        let outH = rawHeight > 0 ? max(1, rawHeight / sampleSize) : 0
        return DecodePlan(
            ruleTransform: "",
            hasRuleTransform: false,
            inSampleSize: sampleSize,
            downscaleAfterRestore: false,
            targetWidth: outW,
            targetHeight: outH
        )
    }

    private static func clampNonTransformSampleSize(rawWidth: Int, rawHeight: Int, sampleSize: Int) -> Int {
        var clamped = max(1, sampleSize)
        guard rawWidth > 0, rawHeight > 0 else { return clamped }
        while clamped < MAX_SAMPLE_SIZE
                && Int64(rawWidth / clamped) * Int64(rawHeight / clamped) > MAX_NON_TRANSFORM_DECODE_PIXELS {
            clamped *= 2
        }
        return clamped
    }

    #if canImport(ImageIO) && canImport(CoreGraphics)
    public static func decodeFile(
        at url: URL,
        imageUrl: String?,
        reqWidth: Int,
        reqHeight: Int
    ) -> CGImage? {
        guard url.isFileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              size > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return decodeFromSource(source, imageUrl: imageUrl, reqWidth: reqWidth, reqHeight: reqHeight)
    }

    public static func decodeData(
        _ data: Data,
        imageUrl: String?,
        reqWidth: Int,
        reqHeight: Int
    ) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return decodeFromSource(source, imageUrl: imageUrl, reqWidth: reqWidth, reqHeight: reqHeight)
    }

    private static func decodeFromSource(
        _ source: CGImageSource,
        imageUrl: String?,
        reqWidth: Int,
        reqHeight: Int
    ) -> CGImage? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any]
        let rawW = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let rawH = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0

        var transform = resolveRuleTransform(imageUrl)
        if transform.isEmpty, let imageUrl, !imageUrl.isEmpty {
            transform = (try? JmImageTransform.resolveTransformSpec(imageURL: imageUrl)) ?? ""
        }

        // Never thumbnail transform-protected covers before restoring pixels.
        if !transform.isEmpty && RuleBitmapTransform.isSupported(transform) {
            guard let fullImage = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else {
                return nil
            }
            let origW = rawW > 0 ? rawW : fullImage.width
            let origH = rawH > 0 ? rawH : fullImage.height
            return restoreAndDownscale(
                fullImage,
                transform: transform,
                origWidth: origW,
                origHeight: origH,
                reqWidth: reqWidth,
                reqHeight: reqHeight
            )
        }

        guard rawW > 0, rawH > 0 else {
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
        let sampleSize = clampNonTransformSampleSize(
            rawWidth: rawW,
            rawHeight: rawH,
            sampleSize: calculateInSampleSize(
                rawWidth: rawW,
                rawHeight: rawH,
                reqWidth: reqWidth,
                reqHeight: reqHeight
            )
        )
        if sampleSize <= 1 {
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
        let maxPixel = max(1, max(rawW, rawH) / sampleSize)
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary)
    }

    private static func restoreAndDownscale(
        _ source: CGImage,
        transform: String,
        origWidth: Int,
        origHeight: Int,
        reqWidth: Int,
        reqHeight: Int
    ) -> CGImage? {
        let restored = restorePixels(source, transform: transform, origWidth: origWidth, origHeight: origHeight) ?? source
        let restoredW = restored.width
        let restoredH = restored.height
        guard shouldDownscaleRestoredBitmap(
            width: restoredW,
            height: restoredH,
            reqWidth: reqWidth,
            reqHeight: reqHeight
        ) else {
            return restored
        }
        let scaled = computeScaledDimensions(
            width: restoredW,
            height: restoredH,
            maxWidth: reqWidth,
            maxHeight: reqHeight
        )
        guard scaled.width > 0, scaled.height > 0,
              scaled.width < restoredW || scaled.height < restoredH else {
            return restored
        }
        let rowBytes = scaled.width * 4
        guard let ctx = CGContext(
            data: nil,
            width: scaled.width,
            height: scaled.height,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return restored
        }
        ctx.interpolationQuality = .high
        ctx.draw(restored, in: CGRect(x: 0, y: 0, width: scaled.width, height: scaled.height))
        return ctx.makeImage() ?? restored
    }

    static func restorePixels(
        _ image: CGImage,
        transform: String,
        origWidth: Int,
        origHeight: Int
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              width <= Int.max / 4,
              height <= Int.max / (width * 4) else {
            return nil
        }
        let ops = RuleBitmapTransform.plan(
            width: width,
            height: height,
            origWidth: origWidth > 0 ? origWidth : width,
            origHeight: origHeight > 0 ? origHeight : height,
            transform: transform
        )
        guard !ops.isEmpty else { return image }

        let rowBytes = width * 4
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), let sourceRaw = context.data else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let fastFullRowBands = ops.allSatisfy {
            $0.rotation == 0 && !$0.flipX && !$0.flipY &&
            $0.srcLeft == 0 && $0.dstLeft == 0 &&
            $0.srcRight == width && $0.dstRight == width
        }

        var output = Data(count: rowBytes * height)
        output.withUnsafeMutableBytes { buffer in
            guard let dstRaw = buffer.baseAddress else { return }
            if fastFullRowBands {
                for op in ops {
                    let bandH = op.dstBottom - op.dstTop
                    guard bandH > 0 else { continue }
                    dstRaw.advanced(by: op.dstTop * rowBytes).copyMemory(
                        from: sourceRaw.advanced(by: op.srcTop * rowBytes),
                        byteCount: bandH * rowBytes
                    )
                }
            } else {
                dstRaw.copyMemory(from: sourceRaw, byteCount: rowBytes * height)
                let srcPx = sourceRaw.assumingMemoryBound(to: UInt32.self)
                let dstPx = dstRaw.assumingMemoryBound(to: UInt32.self)
                for op in ops {
                    let w = op.dstRight - op.dstLeft
                    let h = op.dstBottom - op.dstTop
                    let srcW = op.srcRight - op.srcLeft
                    let srcH = op.srcBottom - op.srcTop
                    for dy in 0..<h {
                        let dstRowOffset = (op.dstTop + dy) * width + op.dstLeft
                        for dx in 0..<w {
                            var sx = dx
                            var sy = dy
                            if op.rotation == 90 {
                                sx = dy
                                sy = w - 1 - dx
                            } else if op.rotation == 180 {
                                sx = w - 1 - dx
                                sy = h - 1 - dy
                            } else if op.rotation == 270 {
                                sx = h - 1 - dy
                                sy = dx
                            }
                            if op.flipX { sx = srcW - 1 - sx }
                            if op.flipY { sy = srcH - 1 - sy }
                            dstPx[dstRowOffset + dx] = srcPx[(op.srcTop + sy) * width + (op.srcLeft + sx)]
                        }
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: output as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
    #endif
}
