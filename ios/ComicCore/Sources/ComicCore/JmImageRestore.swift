#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

extension JmImageTransform {
    /// Extract canonical RuleBitmapTransform spec (`bands:N` or `rule-tx:{...}`) from an online or offline image URL.
    public static func resolveTransformSpec(imageURL: String) throws -> String {
        if RuleImages.isRule(imageURL) {
            return try RuleImages.transformation(imageURL)
        }
        if let txRange = imageURL.range(of: "#xx-tx=") {
            let encoded = String(imageURL[txRange.upperBound...]).components(separatedBy: CharacterSet(charactersIn: "&#"))[0]
            let decoded = try RuleBase64.decode(encoded)
            let tx = String(decoding: decoded, as: UTF8.self)
            guard RuleBitmapTransform.isSupported(tx) else {
                throw TransformError.decodeFailed
            }
            return tx
        }
        if let bandRange = imageURL.range(of: "#xx-bands=") {
            let numStr = String(imageURL[bandRange.upperBound...]).components(separatedBy: CharacterSet(charactersIn: "&#"))[0]
            if let count = Int(numStr), count >= 2, count <= 100 {
                return "bands:\(count)"
            }
            return ""
        }
        if let jmRange = imageURL.range(of: "#jm-origin=") {
            let encoded = String(imageURL[jmRange.upperBound...]).components(separatedBy: CharacterSet(charactersIn: "&#"))[0]
            if let decoded = try? RuleBase64.decode(encoded) {
                let origin = String(decoding: decoded, as: UTF8.self)
                let count = try slices(imageURL: origin)
                return count >= 2 ? "bands:\(count)" : ""
            }
            return ""
        }
        let count = try slices(imageURL: imageURL)
        return count >= 2 ? "bands:\(count)" : ""
    }

    /// Restore the already sampled image (`reverseBands`, `stripes`, `tiles`) before display effects.
    public static func restore(_ image: CGImage, imageURL: String) throws -> CGImage {
        let transform = try resolveTransformSpec(imageURL: imageURL)
        guard !transform.isEmpty else { return image }

        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= Int.max / 4,
              height <= Int.max / (width * 4) else { throw TransformError.decodeFailed }

        let ops = RuleBitmapTransform.plan(width: width, height: height, transform: transform)
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
            throw TransformError.decodeFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let fastFullRowBands = ops.allSatisfy {
            $0.rotation == 0 && !$0.flipX && !$0.flipY &&
            $0.srcLeft == 0 && $0.dstLeft == 0 &&
            $0.srcRight == width && $0.dstRight == width
        }

        var output = Data(count: rowBytes * height)
        try output.withUnsafeMutableBytes { buffer in
            guard let dstRaw = buffer.baseAddress else { throw TransformError.decodeFailed }
            if fastFullRowBands {
                for op in ops {
                    try Task.checkCancellation()
                    let bandH = op.dstBottom - op.dstTop
                    guard bandH > 0 else { continue }
                    dstRaw.advanced(by: op.dstTop * rowBytes).copyMemory(
                        from: sourceRaw.advanced(by: op.srcTop * rowBytes),
                        byteCount: bandH * rowBytes
                    )
                }
            } else {
                // Initialize full buffer from source first so untouched pixels remain intact
                dstRaw.copyMemory(from: sourceRaw, byteCount: rowBytes * height)
                let srcPx = sourceRaw.assumingMemoryBound(to: UInt32.self)
                let dstPx = dstRaw.assumingMemoryBound(to: UInt32.self)
                for op in ops {
                    try Task.checkCancellation()
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

        guard let provider = CGDataProvider(data: output as CFData),
              let restored = CGImage(
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
              ) else {
            throw TransformError.decodeFailed
        }
        try Task.checkCancellation()
        return restored
    }
}
#endif
