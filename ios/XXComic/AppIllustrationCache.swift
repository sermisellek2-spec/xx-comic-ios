import UIKit
import ImageIO
import ObjectiveC

/// Demand-driven downsampling and shared memory cache (<= 6 MiB) for bundled `rem_*` illustrations.
@MainActor
enum AppIllustrationCache {
    static let maxCacheBytes = 6 * 1024 * 1024
    private static let smallBucketDp = 56
    private static let mediumBucketDp = 160
    private static let largeBucketDp = 240

    private static var tokenAssociationKey: UInt8 = 0

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = maxCacheBytes
        return cache
    }()

    static func resolveBucketPx(maxSideDp: Int, scale: CGFloat) -> Int {
        let safeScale = scale > 0 ? scale : 1
        let safeDp = max(1, maxSideDp)
        if safeDp <= smallBucketDp {
            return clamp(Int((56 * safeScale).rounded()), min: 96, max: 224)
        }
        if safeDp <= mediumBucketDp {
            return clamp(Int((160 * safeScale).rounded()), min: 192, max: 560)
        }
        return clamp(Int((CGFloat(largeBucketDp) * safeScale).rounded()), min: 320, max: 840)
    }

    static func bind(_ imageView: UIImageView, assetName: String, maxSideDp: Int = 160) {
        let token = UUID()
        objc_setAssociatedObject(imageView, &tokenAssociationKey, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        guard !assetName.isEmpty else {
            imageView.image = nil
            return
        }
        let scale = imageView.traitCollection.displayScale > 0
            ? imageView.traitCollection.displayScale
            : UIScreen.main.scale
        let bucketPx = resolveBucketPx(maxSideDp: maxSideDp, scale: scale)
        let key = cacheKey(assetName: assetName, bucketPx: bucketPx)
        if let cached = cache.object(forKey: key) {
            imageView.image = cached
            return
        }
        Task { [weak imageView] in
            let decoded = await Task.detached(priority: .utility) {
                Self.decodeBundleImage(named: assetName, maxPixelSize: bucketPx, scale: scale)
            }.value
            guard let imageView else { return }
            let currentToken = objc_getAssociatedObject(imageView, &tokenAssociationKey) as? UUID
            guard currentToken == token else { return }
            if let decoded {
                let cost = cacheCost(for: decoded)
                cache.setObject(decoded, forKey: key, cost: cost)
                imageView.image = decoded
            } else {
                imageView.image = UIImage(named: assetName)
            }
        }
    }

    static func cachedOrDecodedImage(named assetName: String, maxSideDp: Int = 160, scale: CGFloat = UIScreen.main.scale) async -> UIImage? {
        guard !assetName.isEmpty else { return nil }
        let bucketPx = resolveBucketPx(maxSideDp: maxSideDp, scale: scale)
        let key = cacheKey(assetName: assetName, bucketPx: bucketPx)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let decoded = await Task.detached(priority: .utility) {
            Self.decodeBundleImage(named: assetName, maxPixelSize: bucketPx, scale: scale)
        }.value
        if let decoded {
            cache.setObject(decoded, forKey: key, cost: cacheCost(for: decoded))
            return decoded
        }
        return UIImage(named: assetName)
    }

    static func prewarm(_ assetNames: [String], maxSideDp: Int = 160) {
        let scale = UIScreen.main.scale
        let bucketPx = resolveBucketPx(maxSideDp: maxSideDp, scale: scale)
        for name in assetNames where !name.isEmpty {
            let key = cacheKey(assetName: name, bucketPx: bucketPx)
            if cache.object(forKey: key) != nil { continue }
            Task.detached(priority: .utility) {
                guard let decoded = Self.decodeBundleImage(named: name, maxPixelSize: bucketPx, scale: scale) else { return }
                await MainActor.run {
                    cache.setObject(decoded, forKey: key, cost: cacheCost(for: decoded))
                }
            }
        }
    }

    static func clear() {
        cache.removeAllObjects()
    }

    private static func cacheKey(assetName: String, bucketPx: Int) -> NSString {
        "\(assetName)#\(bucketPx)" as NSString
    }

    private static func cacheCost(for image: UIImage) -> Int {
        max(1, Int(image.size.width * image.scale * image.size.height * image.scale * 4))
    }

    nonisolated private static func decodeBundleImage(named assetName: String, maxPixelSize: Int, scale: CGFloat) -> UIImage? {
        let url = Bundle.main.url(forResource: assetName, withExtension: "png")
            ?? Bundle.main.url(forResource: assetName, withExtension: nil)
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale > 0 ? scale : 1, orientation: .up)
    }

    private static func clamp(_ value: Int, min lower: Int, max upper: Int) -> Int {
        max(lower, Swift.min(upper, value))
    }
}
