import Foundation

/// Pure image enhancement policy aligned with Android 2.0.40's `ImageEnhancementPolicy.java`.
public enum ImageEnhancementPolicy {
    public static let modeOff = 0
    public static let modeFast = 1
    public static let modeSmart = 2
    public static let bandRows = 64
    public static let maxProcessDuration: TimeInterval = 15.0
    private static let mib: Int64 = 1024 * 1024

    public static func shouldRun(
        mode: Int,
        lowRam: Bool,
        width: Int,
        height: Int,
        heapLimit: Int64 = 256 * 1024 * 1024,
        availableBytes: Int64 = 128 * 1024 * 1024
    ) -> Bool {
        guard mode == modeFast || mode == modeSmart else { return false }
        guard width >= 32 && height >= 32 && width <= 4096 && height <= 4096 else { return false }
        let pixels = Int64(width) * Int64(height)
        if pixels > (lowRam ? 1_000_000 : 4_000_000) { return false }
        let required = pixels * 20 + 2 * mib
        let budget = min(lowRam ? 16 * mib : 64 * mib, heapLimit / (lowRam ? 8 : 3))
        let reserve = max(16 * mib, heapLimit / 8)
        return required <= budget && (availableBytes - reserve) >= required
    }

    public static func cacheKey(sourceKey: String?, mode: Int) -> String {
        return "enhance:animevideov3-x2-20220424:\(mode):\(sourceKey ?? "")"
    }

    public static func cacheKey(sourceKey: String?, mode: Int, width: Int, height: Int, pixelRevision: Int) -> String {
        return "\(cacheKey(sourceKey: sourceKey, mode: mode)):\(width)x\(height):\(pixelRevision)"
    }
}
