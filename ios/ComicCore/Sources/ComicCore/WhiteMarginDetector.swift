import Foundation

public struct ImageCrop: Equatable, Sendable {
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int
    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
}

public enum WhiteMarginDetector {
    /// ARGB pixels, matching Android. A single non-white pixel protects the entire edge.
    public static func detect(width: Int, height: Int, cropVertical: Bool,
                              pixel: (Int, Int) -> UInt32) -> ImageCrop {
        guard width >= 10, height >= 10 else { return ImageCrop(left: 0, top: 0, right: width, bottom: height) }
        func white(_ value: UInt32) -> Bool {
            let r = (value >> 16) & 255, g = (value >> 8) & 255, b = value & 255
            return value >> 24 == 255 && min(r, g, b) >= 245 && max(r, g, b) - min(r, g, b) <= 10
        }
        func margin(length: Int, cross: Int, vertical: Bool, reversed: Bool) -> Int {
            let limit = Int(Float(length) * 0.15)
            var count = 0
            for distance in 0..<limit {
                let coordinate = reversed ? length - 1 - distance : distance
                if !(0..<cross).allSatisfy({ white(vertical ? pixel($0, coordinate) : pixel(coordinate, $0)) }) { break }
                count += 1
            }
            if count >= limit { return 0 }
            return max(0, count - max(2, Int((Float(length) * 0.003).rounded())))
        }
        let left = margin(length: width, cross: height, vertical: false, reversed: false)
        let right = width - margin(length: width, cross: height, vertical: false, reversed: true)
        let top = cropVertical ? margin(length: height, cross: width, vertical: true, reversed: false) : 0
        let bottom = cropVertical ? height - margin(length: height, cross: width, vertical: true, reversed: true) : height
        return ImageCrop(left: left, top: top, right: right, bottom: bottom)
    }
}
