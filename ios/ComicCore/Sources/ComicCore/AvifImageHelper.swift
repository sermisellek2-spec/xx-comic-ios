import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// AVIF/ISOBMFF header, container completeness, and optional ImageIO decode helpers.
public enum AvifImageHelper {
    public static let maxAvifBytes: Int64 = 64 * 1024 * 1024
    public static let maxAvifPixelBytes: Int64 = 128 * 1024 * 1024
    private static let maxBoxCount = 4096

    public static func isAvifHeader(_ data: Data) -> Bool {
        RuleImageData.isIsoBmffImageHeader(data)
    }

    public static func isAvifHeader(_ bytes: [UInt8], offset: Int, length: Int) -> Bool {
        guard offset >= 0, length >= offset, length <= bytes.count else { return false }
        return RuleImageData.isIsoBmffImageHeader(Data(bytes[offset..<length]))
    }

    public static func isAvifFile(at url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size >= 12 else {
            return false
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let readLen = min(64, size)
        guard let head = try? handle.read(upToCount: readLen), head.count >= 12 else {
            return false
        }
        return isAvifHeader(head)
    }

    /// Streams ISOBMFF top-level boxes (max 4096, 64-bit size supported, unsized size=0 rejected)
    /// and verifies `pos == fileLength && sawFtyp && (sawMeta || sawMoov) && sawMdat` with non-empty `mdat` payload.
    public static func hasCompleteContainer(at url: URL) -> Bool {
        guard isAvifFile(at: url) else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let lenNum = attrs[.size] as? NSNumber else {
            return false
        }
        let fileLength = lenNum.uint64Value
        guard fileLength >= 32 else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        var pos: UInt64 = 0
        var sawFtyp = false
        var sawMetaOrMoov = false
        var sawMdat = false

        for _ in 0..<maxBoxCount where pos < fileLength {
            guard fileLength - pos >= 8 else { return false }
            do {
                try handle.seek(toOffset: pos)
                guard let header = try handle.read(upToCount: 8), header.count == 8 else {
                    return false
                }
                var boxSize = readUInt32(header, at: 0)
                var headerLen: UInt64 = 8
                if boxSize == 1 {
                    guard fileLength - pos >= 16 else { return false }
                    guard let ext = try handle.read(upToCount: 8), ext.count == 8 else {
                        return false
                    }
                    guard let largeSize = readUInt64(ext, at: 0) else { return false }
                    boxSize = largeSize
                    headerLen = 16
                } else if boxSize == 0 {
                    // Unsized box cannot verify truncation cleanly.
                    return false
                }
                guard boxSize >= headerLen, boxSize <= fileLength - pos else {
                    return false
                }
                if pos == 0 {
                    guard matchesFourCC(header, at: 4, 0x66, 0x74, 0x79, 0x70) else { // ftyp
                        return false
                    }
                    sawFtyp = true
                } else if matchesFourCC(header, at: 4, 0x6D, 0x65, 0x74, 0x61) || // meta
                          matchesFourCC(header, at: 4, 0x6D, 0x6F, 0x6F, 0x76) {  // moov
                    sawMetaOrMoov = true
                } else if matchesFourCC(header, at: 4, 0x6D, 0x64, 0x61, 0x74) { // mdat
                    guard boxSize > headerLen else { return false }
                    sawMdat = true
                }
                pos += boxSize
            } catch {
                return false
            }
        }
        return pos == fileLength && sawFtyp && sawMetaOrMoov && sawMdat
    }

    /// In-memory ISOBMFF container completeness check mirroring `hasCompleteContainer(at:)`.
    public static func hasCompleteContainer(data: Data) -> Bool {
        guard data.count >= 32, isAvifHeader(data) else { return false }
        let fileLength = UInt64(data.count)
        return data.withUnsafeBytes { rawBuf -> Bool in
            guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }
            var pos: UInt64 = 0
            var sawFtyp = false
            var sawMetaOrMoov = false
            var sawMdat = false

            for _ in 0..<maxBoxCount where pos < fileLength {
                guard fileLength - pos >= 8 else { return false }
                let offset = Int(pos)
                var boxSize = (UInt64(base[offset]) << 24)
                    | (UInt64(base[offset + 1]) << 16)
                    | (UInt64(base[offset + 2]) << 8)
                    | UInt64(base[offset + 3])
                var headerLen: UInt64 = 8
                if boxSize == 1 {
                    guard fileLength - pos >= 16 else { return false }
                    let hi = (UInt64(base[offset + 8]) << 24)
                        | (UInt64(base[offset + 9]) << 16)
                        | (UInt64(base[offset + 10]) << 8)
                        | UInt64(base[offset + 11])
                    let lo = (UInt64(base[offset + 12]) << 24)
                        | (UInt64(base[offset + 13]) << 16)
                        | (UInt64(base[offset + 14]) << 8)
                        | UInt64(base[offset + 15])
                    if hi > (UInt64(Int64.max) >> 32) { return false }
                    boxSize = (hi << 32) | lo
                    headerLen = 16
                } else if boxSize == 0 {
                    return false
                }
                guard boxSize >= headerLen, boxSize <= fileLength - pos else {
                    return false
                }
                let f0 = base[offset + 4]
                let f1 = base[offset + 5]
                let f2 = base[offset + 6]
                let f3 = base[offset + 7]
                if pos == 0 {
                    guard f0 == 0x66 && f1 == 0x74 && f2 == 0x79 && f3 == 0x70 else { // ftyp
                        return false
                    }
                    sawFtyp = true
                } else if (f0 == 0x6D && f1 == 0x65 && f2 == 0x74 && f3 == 0x61) || // meta
                          (f0 == 0x6D && f1 == 0x6F && f2 == 0x6F && f3 == 0x76) {  // moov
                    sawMetaOrMoov = true
                } else if f0 == 0x6D && f1 == 0x64 && f2 == 0x61 && f3 == 0x74 { // mdat
                    guard boxSize > headerLen else { return false }
                    sawMdat = true
                }
                pos += boxSize
            }
            return pos == fileLength && sawFtyp && sawMetaOrMoov && sawMdat
        }
    }

    private static func matchesFourCC(_ data: Data, at offset: Int, _ c0: UInt8, _ c1: UInt8, _ c2: UInt8, _ c3: UInt8) -> Bool {
        guard offset >= 0, offset + 4 <= data.count else { return false }
        let idx = data.startIndex + offset
        return data[idx] == c0 && data[idx + 1] == c1 && data[idx + 2] == c2 && data[idx + 3] == c3
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt64 {
        let idx = data.startIndex + offset
        return (UInt64(data[idx]) << 24)
            | (UInt64(data[idx + 1]) << 16)
            | (UInt64(data[idx + 2]) << 8)
            | UInt64(data[idx + 3])
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64? {
        let hi = readUInt32(data, at: offset)
        let lo = readUInt32(data, at: offset + 4)
        if hi > (UInt64(Int64.max) >> 32) { return nil }
        return (hi << 32) | lo
    }

    #if canImport(ImageIO)
    public static var isSystemAvifDecodeSupported: Bool {
        guard let types = CGImageSourceCopyTypeIdentifiers() as? [String] else { return false }
        return types.contains { type in
            let lower = type.lowercased()
            return lower == "public.avif" || lower == "public.avis" || lower == "org.aomedia.avif"
        }
    }

    public static func decodeBounds(at url: URL) -> (width: Int, height: Int)? {
        guard isAvifFile(at: url),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let len = (attrs[.size] as? NSNumber)?.int64Value,
              len >= 12, len <= maxAvifBytes else {
            return nil
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return extractBounds(from: source)
    }

    public static func decodeBounds(data: Data) -> (width: Int, height: Int)? {
        guard data.count >= 12, Int64(data.count) <= maxAvifBytes, isAvifHeader(data) else {
            return nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return extractBounds(from: source)
    }

    private static func extractBounds(from source: CGImageSource) -> (width: Int, height: Int)? {
        guard CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              w > 0, h > 0 else {
            return nil
        }
        return (w, h)
    }

    #if canImport(CoreGraphics)
    public static func decodeImage(at url: URL, sampleSize: Int = 1) -> CGImage? {
        guard isAvifFile(at: url),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let len = (attrs[.size] as? NSNumber)?.int64Value,
              len >= 12, len <= maxAvifBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return decodeImage(from: source, sampleSize: sampleSize)
    }

    public static func decodeImage(data: Data, sampleSize: Int = 1) -> CGImage? {
        guard data.count >= 12, Int64(data.count) <= maxAvifBytes, isAvifHeader(data),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return decodeImage(from: source, sampleSize: sampleSize)
    }

    private static func decodeImage(from source: CGImageSource, sampleSize: Int) -> CGImage? {
        guard let bounds = extractBounds(from: source) else { return nil }
        guard Int64(bounds.width) * Int64(bounds.height) * 4 <= maxAvifPixelBytes else {
            return nil
        }
        let effectiveSample = max(1, sampleSize)
        if effectiveSample > 1 {
            let maxPixel = max(1, max(bounds.width, bounds.height) / effectiveSample)
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ] as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
    #endif
    #endif
}
