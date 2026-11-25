#if canImport(ImageIO)
import Foundation
import ImageIO

public enum LocalImageProbe {
    public static func isReadable(_ url: URL) throws -> Bool {
        try Task.checkCancellation()
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
        guard let size = attributes.fileSize, size <= LocalLibrary.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
        let readable: Bool = autoreleasepool {
            if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
               CGImageSourceGetCount(source) > 0 {
                if CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256
                ] as CFDictionary) != nil {
                    return true
                }
                if AvifImageHelper.isAvifFile(at: url),
                   CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil {
                    return true
                }
            }
            if AvifImageHelper.isAvifFile(at: url) && AvifImageHelper.hasCompleteContainer(at: url) {
                return true
            }
            return false
        }
        try Task.checkCancellation()
        return readable
    }
}
#endif
