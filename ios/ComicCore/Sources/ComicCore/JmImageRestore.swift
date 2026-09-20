#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

extension JmImageTransform {
    /// Restore the already sampled image, as Android's reader does before display effects.
    public static func restore(_ image: CGImage, imageURL: String) throws -> CGImage {
        let count = try slices(imageURL: imageURL)
        let strips = bounds(height: image.height, slices: count)
        guard !strips.isEmpty else { return image }
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= Int.max / 4,
              height <= Int.max / (width * 4) else { throw TransformError.decodeFailed }
        let rowBytes = width * 4
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let source = context.data else { throw TransformError.decodeFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var output = Data(count: rowBytes * height)
        try output.withUnsafeMutableBytes { buffer in
            guard let destination = buffer.baseAddress else { throw TransformError.decodeFailed }
            for strip in strips {
                try Task.checkCancellation()
                destination.advanced(by: strip.targetY * rowBytes).copyMemory(
                    from: source.advanced(by: strip.sourceY * rowBytes), byteCount: strip.height * rowBytes)
            }
        }
        guard let provider = CGDataProvider(data: output as CFData),
              let restored = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw TransformError.decodeFailed }
        try Task.checkCancellation()
        return restored
    }
}
#endif
