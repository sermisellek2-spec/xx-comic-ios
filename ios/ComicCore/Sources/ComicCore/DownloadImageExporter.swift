import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Sanitizes and generates readable, collision-resistant directory and file names
/// for offline downloads and exported image directories.
public enum DownloadNamingPolicy {
    public static let MAX_NAME_CHARS = 60
    public static let MAX_NAME_BYTES = 120
    public static let maxNameChars = MAX_NAME_CHARS
    public static let maxNameBytes = MAX_NAME_BYTES

    private static let illegalCharsRegex = try? NSRegularExpression(pattern: #"[\\/:*?"<>|\x00-\x1F\x7F]"#)
    private static let multiSepRegex = try? NSRegularExpression(pattern: #"[ _]{2,}"#)
    private static let windowsReservedRegex = try? NSRegularExpression(
        pattern: #"^(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$"#
    )

    public static func sanitize(_ raw: String?, fallback: String = "") -> String {
        guard let raw else {
            return !fallback.isEmpty ? sanitizeFallback(fallback) : ""
        }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s == "." || s == ".." || s == "..." {
            return "_"
        }
        s = replaceMatches(illegalCharsRegex, in: s, with: "_")
        s = replaceMatches(multiSepRegex, in: s, with: "_")
        s = trimEdgePunctuation(s)

        if s.isEmpty {
            return !fallback.isEmpty ? sanitizeFallback(fallback) : ""
        }
        if matchesWindowsReserved(s) {
            s = "_" + s
        }

        s = truncate(s, maxChars: MAX_NAME_CHARS, maxBytes: MAX_NAME_BYTES)
        s = trimEdgePunctuation(s)

        if s.isEmpty {
            return !fallback.isEmpty ? sanitizeFallback(fallback) : ""
        }
        if matchesWindowsReserved(s) {
            s = "_" + s
        }
        return s
    }

    public static func truncate(_ s: String, maxChars: Int, maxBytes: Int) -> String {
        guard maxChars > 0, maxBytes > 0 else { return "" }
        var result = ""
        var scalarCount = 0
        var byteCount = 0
        for scalar in s.unicodeScalars {
            if scalarCount >= maxChars { break }
            let scalarBytes = String(scalar).utf8.count
            if byteCount + scalarBytes > maxBytes { break }
            result.unicodeScalars.append(scalar)
            scalarCount += 1
            byteCount += scalarBytes
        }
        return result
    }

    public static func shortId(_ fullId: String?) -> String {
        guard let fullId, !fullId.isEmpty else { return "00000000" }
        let hex = DownloadModels.sha256Hex(Data(fullId.utf8))
        return String(hex.prefix(8))
    }

    public static func comicDirectoryCandidate(
        comicTitle: String?,
        sourceName: String?,
        bookId: String?,
        level: Int
    ) -> String {
        let sid = shortId(bookId)
        var cleanTitle = sanitize(comicTitle, fallback: "comic_\(sid)")
        if cleanTitle.isEmpty { cleanTitle = "comic_\(sid)" }
        if level == 0 { return cleanTitle }
        var cleanSource = sanitize(sourceName, fallback: "source")
        if cleanSource.isEmpty { cleanSource = "source" }
        if level == 1 { return "\(cleanTitle)_\(cleanSource)" }
        if level == 2 { return "\(cleanTitle)_\(cleanSource)_\(sid)" }
        return "\(cleanTitle)_\(cleanSource)_\(sid)_\(level - 2)"
    }

    public static func chapterDirectoryCandidate(
        chapterTitle: String?,
        orderIndex: Int,
        taskId: String?,
        level: Int
    ) -> String {
        let sid = shortId(taskId)
        let isEmptyTitle = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let fallback = isEmptyTitle
            ? (orderIndex > 0 ? "第\(orderIndex + 1)话" : "chapter_\(sid)")
            : "chapter_\(sid)"
        var cleanTitle = sanitize(chapterTitle, fallback: fallback)
        if cleanTitle.isEmpty { cleanTitle = "chapter_\(sid)" }
        if level == 0 { return cleanTitle }
        if level == 1 { return "\(cleanTitle)_\(sid)" }
        return "\(cleanTitle)_\(sid)_\(level - 1)"
    }

    private static func sanitizeFallback(_ fallback: String) -> String {
        var s = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        s = replaceMatches(illegalCharsRegex, in: s, with: "_")
        s = trimEdgePunctuation(s)
        return s.isEmpty ? "unnamed" : s
    }

    static func trimEdgePunctuation(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: " ._"))
    }

    private static func replaceMatches(_ regex: NSRegularExpression?, in s: String, with template: String) -> String {
        guard let regex else { return s }
        let range = NSRange(location: 0, length: (s as NSString).length)
        return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
    }

    private static func matchesWindowsReserved(_ s: String) -> Bool {
        guard let regex = windowsReservedRegex else { return false }
        let range = NSRange(location: 0, length: (s as NSString).length)
        return regex.firstMatch(in: s, options: [], range: range) != nil
    }
}

/// Exports completed offline chapters into a user-chosen destination directory without
/// modifying or deleting any original offline download files.
public enum DownloadImageExporter {
    public static let prefKeyExportFormat = "downloads.export_image_format"
    public static let maxPageBytes: Int64 = 64 * 1024 * 1024

    public enum Format: String, CaseIterable, Codable, Sendable {
        case jpg
        case png
        case webp
        case original

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .jpg: return "JPG (.jpg)"
            case .png: return "PNG (.png)"
            case .webp: return "WebP (.webp)"
            case .original: return "原图格式"
            }
        }

        public var mimeType: String? {
            switch self {
            case .jpg: return "image/jpeg"
            case .png: return "image/png"
            case .webp: return "image/webp"
            case .original: return nil
            }
        }

        public var description: String {
            switch self {
            case .jpg: return "兼容最好，体积适中"
            case .png: return "无损画质，体积较大"
            case .webp: return "高压缩率，清晰省空间"
            case .original: return "保留原文件编码并自动补全后缀"
            }
        }

        public var quality: Int {
            switch self {
            case .jpg, .webp: return 92
            case .png, .original: return 100
            }
        }

        public static func fromId(_ id: String?) -> Format {
            guard let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !trimmed.isEmpty,
                  let fmt = Format(rawValue: trimmed) else {
                return .jpg
            }
            return fmt
        }
    }

    public struct ImageType: Equatable, Sendable {
        public let `extension`: String
        public let mimeType: String

        public init(extension ext: String, mimeType: String) {
            self.extension = ext.isEmpty ? ".jpg" : ext
            self.mimeType = mimeType.isEmpty ? "application/octet-stream" : mimeType
        }

        public var extensionWithoutDot: String {
            `extension`.hasPrefix(".") ? String(`extension`.dropFirst()) : `extension`
        }
    }

    public struct ExportResult: Equatable, Sendable {
        public let totalChapters: Int
        public let exportedChapters: Int
        public let totalPages: Int
        public let exportedPages: Int
        public let skippedPages: Int
        public let cancelled: Bool
        public let folderDisplayName: String
        public let lastError: String
        public let fallbackReason: String

        public init(
            totalChapters: Int,
            exportedChapters: Int,
            totalPages: Int,
            exportedPages: Int,
            skippedPages: Int,
            cancelled: Bool,
            folderDisplayName: String,
            lastError: String,
            fallbackReason: String = ""
        ) {
            self.totalChapters = totalChapters
            self.exportedChapters = exportedChapters
            self.totalPages = totalPages
            self.exportedPages = exportedPages
            self.skippedPages = skippedPages
            self.cancelled = cancelled
            self.folderDisplayName = folderDisplayName
            self.lastError = lastError
            self.fallbackReason = fallbackReason
        }
    }

    public struct Progress: Equatable, Sendable {
        public let donePages: Int
        public let totalPages: Int
        public let doneChapters: Int
        public let totalChapters: Int
        public let currentChapterTitle: String
    }

    public static func loadPreferredFormat(defaults: UserDefaults = .standard) -> Format {
        Format.fromId(defaults.string(forKey: prefKeyExportFormat))
    }

    public static func savePreferredFormat(_ format: Format, defaults: UserDefaults = .standard) {
        defaults.set(format.id, forKey: prefKeyExportFormat)
    }

    /// Detects image container format from the first 32 magic bytes (including AVIF).
    public static func detectImageFormat(_ data: Data) -> ImageType {
        let head = data.prefix(32)
        let bytes = Array(head)
        let n = bytes.count
        if n >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return ImageType(extension: ".jpg", mimeType: "image/jpeg")
        }
        if n >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return ImageType(extension: ".png", mimeType: "image/png")
        }
        if n >= 12
            && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return ImageType(extension: ".webp", mimeType: "image/webp")
        }
        if n >= 6
            && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38
            && (bytes[4] == 0x37 || bytes[4] == 0x39) && bytes[5] == 0x61 {
            return ImageType(extension: ".gif", mimeType: "image/gif")
        }
        if AvifImageHelper.isAvifHeader(head) {
            return ImageType(extension: ".avif", mimeType: "image/avif")
        }
        return ImageType(extension: ".jpg", mimeType: "application/octet-stream")
    }

    public static func hasSupportedTransform(_ transformation: String?) -> Bool {
        guard let transformation, !transformation.isEmpty else { return false }
        return RuleBitmapTransform.isSupported(transformation) || transformation.hasPrefix("jm:")
    }

    public static func effectiveOutputFormat(requested: Format, hasTransform: Bool) -> Format {
        if requested == .original && hasTransform {
            // Re-encoding after pixel descrambling uses lossless PNG to avoid quality degradation.
            return .png
        }
        return requested
    }

    public static func needsBitmapDecode(requested: Format, detected: ImageType?, hasTransform: Bool) -> Bool {
        if hasTransform { return true }
        if requested == .original { return false }
        guard let detected, let targetMime = requested.mimeType else { return true }
        return targetMime != detected.mimeType
    }

    /// Resolves the actual encoded format and optional fallback reason when WebP encoding is unsupported.
    public static func resolveTranscodeFormat(
        requested: Format,
        hasTransform: Bool,
        webpSupported: Bool
    ) -> (format: Format, fallbackReason: String?) {
        let effective = effectiveOutputFormat(requested: requested, hasTransform: hasTransform)
        if effective == .webp && !webpSupported {
            return (.png, "当前系统不支持 WebP 编码，已自动无损降级为 PNG")
        }
        return (effective, nil)
    }

    public static func sanitizeBookDirName(comicTitle: String?, bookId: String?) -> String {
        let sid = DownloadNamingPolicy.shortId(bookId)
        let name = DownloadNamingPolicy.sanitize(comicTitle, fallback: "comic_\(sid)")
        return name.isEmpty ? "comic_\(sid)" : name
    }

    public static func formatChapterDirName(
        oneBasedOrder: Int,
        chapterTitle: String?,
        chapterId: String?
    ) -> String {
        let prefix = String(format: "%03d", max(1, oneBasedOrder))
        var cleanTitle = DownloadNamingPolicy.sanitize(chapterTitle, fallback: "")
        if cleanTitle.isEmpty {
            cleanTitle = "chapter_\(DownloadNamingPolicy.shortId(chapterId))"
        }
        let combined = "\(prefix)_\(cleanTitle)"
        let truncated = trimTrailingSeparator(
            DownloadNamingPolicy.truncate(
                combined,
                maxChars: DownloadNamingPolicy.MAX_NAME_CHARS,
                maxBytes: DownloadNamingPolicy.MAX_NAME_BYTES
            )
        )
        return truncated.isEmpty ? prefix : truncated
    }

    public static func resolveUniqueChapterDirName(
        usedChapterDirNames: inout Set<String>,
        baseChapterDirName: String,
        chapterId: String?
    ) -> String {
        if usedChapterDirNames.insert(baseChapterDirName).inserted {
            return baseChapterDirName
        }
        let shortId = DownloadNamingPolicy.shortId(chapterId)
        let suffix = "_\(shortId)"
        var candidate = buildTruncatedNameWithSuffix(base: baseChapterDirName, suffix: suffix, fallback: shortId)
        if usedChapterDirNames.insert(candidate).inserted {
            return candidate
        }
        for n in 1...999 {
            let indexedSuffix = "\(suffix)_\(n)"
            candidate = buildTruncatedNameWithSuffix(
                base: baseChapterDirName,
                suffix: indexedSuffix,
                fallback: "\(shortId)_\(n)"
            )
            if usedChapterDirNames.insert(candidate).inserted {
                return candidate
            }
        }
        return candidate
    }

    public static func formatPageFileName(oneBasedPageIndex: Int, extension ext: String?) -> String {
        var clean = (ext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix(".") { clean = String(clean.dropFirst()) }
        if clean.isEmpty { clean = "jpg" }
        return String(format: "%03d.%@", max(1, oneBasedPageIndex), clean)
    }

    public static func resolveEffectiveTransform(pageUrl: String?, storedTransform: String? = nil) -> String? {
        if let storedTransform, !storedTransform.isEmpty {
            return storedTransform
        }
        guard let pageUrl, !pageUrl.isEmpty else { return nil }
        if RuleImages.isRule(pageUrl) {
            if let tx = try? RuleImages.transformation(pageUrl), !tx.isEmpty {
                return tx
            }
        }
        if let txRange = pageUrl.range(of: "#xx-tx=") {
            let encoded = String(pageUrl[txRange.upperBound...]).components(separatedBy: CharacterSet(charactersIn: "&#"))[0]
            if let decoded = try? RuleBase64.decode(encoded) {
                let tx = String(decoding: decoded, as: UTF8.self)
                if RuleBitmapTransform.isSupported(tx) { return tx }
            }
        }
        if let bandRange = pageUrl.range(of: "#xx-bands=") {
            let numStr = String(pageUrl[bandRange.upperBound...]).components(separatedBy: CharacterSet(charactersIn: "&#"))[0]
            if let count = Int(numStr), count >= 2, count <= 100 {
                return "bands:\(count)"
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"[?&]scramble_id=(\d+)"#),
           let match = regex.firstMatch(in: pageUrl, range: NSRange(pageUrl.startIndex..., in: pageUrl)),
           let range = Range(match.range(at: 1), in: pageUrl) {
            let base = pageUrl.components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
            return "jm:\(base)?scramble_id=\(pageUrl[range])"
        }
        return nil
    }

    private static func buildTruncatedNameWithSuffix(base: String, suffix: String, fallback: String) -> String {
        let suffixBytes = suffix.utf8.count
        let maxBaseChars = max(0, DownloadNamingPolicy.MAX_NAME_CHARS - suffix.count)
        let maxBaseBytes = max(0, DownloadNamingPolicy.MAX_NAME_BYTES - suffixBytes)
        let trimmed = trimTrailingSeparator(
            DownloadNamingPolicy.truncate(base, maxChars: maxBaseChars, maxBytes: maxBaseBytes)
        )
        return trimmed.isEmpty ? fallback : trimmed + suffix
    }

    private static func trimTrailingSeparator(_ s: String) -> String {
        var result = s
        while let last = result.last, last == "_" || last == "." || last == " " {
            result.removeLast()
        }
        return result
    }

    #if canImport(ImageIO) && canImport(CoreGraphics)
    public static func isWebPEncodeSupported() -> Bool {
        guard let types = CGImageDestinationCopyTypeIdentifiers() as? [String] else { return false }
        return types.contains { $0.caseInsensitiveCompare("org.webmproject.webp") == .orderedSame }
    }

    public static func destinationTypeIdentifier(for format: Format) -> CFString? {
        switch format {
        case .jpg: return "public.jpeg" as CFString
        case .png: return "public.png" as CFString
        case .webp: return "org.webmproject.webp" as CFString
        case .original: return nil
        }
    }

    public static func encodeImageData(
        _ rawBytes: Data,
        pageUrl: String?,
        requestedFormat: Format,
        webpSupported: Bool = isWebPEncodeSupported()
    ) throws -> (data: Data, imageType: ImageType, fallbackReason: String?) {
        guard !rawBytes.isEmpty else {
            throw DownloadError.corruptedData("图片文件为空")
        }
        guard Int64(rawBytes.count) <= maxPageBytes else {
            throw DownloadError.corruptedData("单页图片体积超出导出安全限制")
        }

        let detected = detectImageFormat(rawBytes)
        let transform = resolveEffectiveTransform(pageUrl: pageUrl)
        let hasTransform = hasSupportedTransform(transform)
        let decodeRequired = needsBitmapDecode(requested: requestedFormat, detected: detected, hasTransform: hasTransform)

        if !decodeRequired {
            return (rawBytes, detected, nil)
        }

        let (outputFormat, fallbackReason) = resolveTranscodeFormat(
            requested: requestedFormat,
            hasTransform: hasTransform,
            webpSupported: webpSupported
        )

        guard let source = CGImageSourceCreateWithData(rawBytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            throw DownloadError.corruptedData("图片解码失败")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any]
        let propW = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let propH = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0

        guard let decoded = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else {
            throw DownloadError.corruptedData("图片解码失败")
        }
        try Task.checkCancellation()

        let origW = propW > 0 ? propW : decoded.width
        let origH = propH > 0 ? propH : decoded.height
        let restored: CGImage
        if hasTransform, let transform {
            if RuleBitmapTransform.isSupported(transform) {
                guard let unscrambled = CoverBitmapDecoder.restorePixels(
                    decoded,
                    transform: transform,
                    origWidth: origW,
                    origHeight: origH
                ) else {
                    throw DownloadError.corruptedData("图片像素还原失败")
                }
                restored = unscrambled
            } else if transform.hasPrefix("jm:") {
                let jmUrl = String(transform.dropFirst(3))
                restored = try JmImageTransform.restore(decoded, imageURL: jmUrl, origWidth: origW, origHeight: origH)
            } else {
                restored = decoded
            }
        } else {
            restored = decoded
        }
        try Task.checkCancellation()

        let finalImage: CGImage
        if outputFormat == .jpg && hasAlphaChannel(restored) {
            finalImage = try flattenOnWhite(restored)
        } else {
            finalImage = restored
        }

        guard let uti = destinationTypeIdentifier(for: outputFormat) else {
            throw DownloadError.corruptedData("不支持的导出图片格式")
        }
        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(outData as CFMutableData, uti, 1, nil) else {
            throw DownloadError.corruptedData("图片编码器初始化失败")
        }
        var options: [CFString: Any] = [:]
        if outputFormat == .jpg || outputFormat == .webp {
            options[kCGImageDestinationLossyCompressionQuality] = Double(outputFormat.quality) / 100.0
        }
        CGImageDestinationAddImage(dest, finalImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw DownloadError.corruptedData("图片编码写入失败")
        }

        let ext = ".\(outputFormat.id)"
        let mime = outputFormat.mimeType ?? "application/octet-stream"
        return (outData as Data, ImageType(extension: ext, mimeType: mime), fallbackReason)
    }

    private static func hasAlphaChannel(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .premultipliedFirst, .premultipliedLast, .first, .last, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return true
        }
    }

    private static func flattenOnWhite(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let rowBytes = width * 4
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw DownloadError.corruptedData("图片透明通道处理失败")
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = ctx.makeImage() else {
            throw DownloadError.corruptedData("图片透明通道合成失败")
        }
        return result
    }

    public static func export(
        runtime: DownloadRuntime,
        bookId: String,
        chapterIds: [String]?,
        format: Format,
        destinationDirectory: URL,
        progress: ((Progress) -> Void)? = nil
    ) async throws -> ExportResult {
        let tasks = runtime.store.list().filter { $0.bookId == bookId && !$0.isFileTask && $0.state == .completed }
        let filterSet = (chapterIds?.isEmpty == false) ? Set(chapterIds!) : nil
        let selectedTasks = tasks
            .filter { filterSet == nil || filterSet!.contains($0.chapterId) || filterSet!.contains($0.id) }
            .sorted { $0.order < $1.order }

        guard !selectedTasks.isEmpty else {
            throw DownloadError.corruptedData("未找到可导出的已完成章节")
        }

        var totalPages = 0
        var taskPages: [[DownloadPage]] = []
        for task in selectedTasks {
            try Task.checkCancellation()
            let pages = runtime.store.pages(task: task.id)
            taskPages.append(pages)
            totalPages += pages.count
        }
        guard totalPages > 0 else {
            throw DownloadError.corruptedData("所选章节暂无可导出的页面文件")
        }

        let snapshot = runtime.store.snapshot(id: bookId)
        let comicTitle = snapshot?.summary.title ?? selectedTasks[0].comicId
        let bookDirName = sanitizeBookDirName(comicTitle: comicTitle, bookId: bookId)
        let bookDir = destinationDirectory.appendingPathComponent(bookDirName, isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: bookDir.path) {
            try fm.createDirectory(at: bookDir, withIntermediateDirectories: true)
        }

        let webpSupported = isWebPEncodeSupported()
        var donePages = 0
        var exportedPages = 0
        var skippedPages = 0
        var exportedChapters = 0
        var wasCancelled = false
        var lastError = ""
        var fallbackReason = ""
        var usedChapterDirNames = Set<String>()

        for (chIdx, task) in selectedTasks.enumerated() {
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            let pages = taskPages[chIdx]
            let baseChapterDirName = formatChapterDirName(
                oneBasedOrder: task.order + 1,
                chapterTitle: task.title,
                chapterId: task.chapterId
            )
            let chapterDirName = resolveUniqueChapterDirName(
                usedChapterDirNames: &usedChapterDirNames,
                baseChapterDirName: baseChapterDirName,
                chapterId: task.chapterId
            )
            let chapterDir = bookDir.appendingPathComponent(chapterDirName, isDirectory: true)
            var chapterCreated = false
            var chapterExported = 0

            for (pageIdx, page) in pages.enumerated() {
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }
                do {
                    let sourceFile = try resolveOfflinePageURL(runtime: runtime, task: task, page: page)
                    let rawBytes = try FileAccessCoordinator.readRegularFile(sourceFile, maximumBytes: maxPageBytes)
                    guard rawBytes.count == page.bytes, DownloadModels.sha256Hex(rawBytes) == page.hash else {
                        throw DownloadError.corruptedData("下载文件损坏，请先在下载中心重试")
                    }
                    let encoded = try encodeImageData(
                        rawBytes,
                        pageUrl: page.url,
                        requestedFormat: format,
                        webpSupported: webpSupported
                    )
                    if fallbackReason.isEmpty, let reason = encoded.fallbackReason {
                        fallbackReason = reason
                    }
                    if !chapterCreated {
                        if !fm.fileExists(atPath: chapterDir.path) {
                            try fm.createDirectory(at: chapterDir, withIntermediateDirectories: true)
                        }
                        chapterCreated = true
                    }
                    let fileName = formatPageFileName(
                        oneBasedPageIndex: pageIdx + 1,
                        extension: encoded.imageType.extensionWithoutDot
                    )
                    let targetFile = chapterDir.appendingPathComponent(fileName)
                    let partFile = chapterDir.appendingPathComponent(".\(fileName).\(UUID().uuidString).part")
                    defer {
                        if fm.fileExists(atPath: partFile.path) {
                            try? fm.removeItem(at: partFile)
                        }
                    }
                    try Task.checkCancellation()
                    try encoded.data.write(to: partFile, options: .atomic)
                    try Task.checkCancellation()
                    try AtomicFileOps.moveReplace(from: partFile, to: targetFile)
                    exportedPages += 1
                    chapterExported += 1
                } catch is CancellationError {
                    wasCancelled = true
                    break
                } catch {
                    if Task.isCancelled {
                        wasCancelled = true
                        break
                    }
                    skippedPages += 1
                    lastError = error.localizedDescription
                }
                donePages += 1
                progress?(Progress(
                    donePages: donePages,
                    totalPages: totalPages,
                    doneChapters: chIdx + 1,
                    totalChapters: selectedTasks.count,
                    currentChapterTitle: task.title
                ))
            }

            if chapterExported > 0 {
                exportedChapters += 1
            }
            if wasCancelled {
                break
            }
        }

        return ExportResult(
            totalChapters: selectedTasks.count,
            exportedChapters: exportedChapters,
            totalPages: totalPages,
            exportedPages: exportedPages,
            skippedPages: skippedPages,
            cancelled: wasCancelled,
            folderDisplayName: destinationDirectory.lastPathComponent,
            lastError: lastError,
            fallbackReason: fallbackReason
        )
    }

    private static func resolveOfflinePageURL(
        runtime: DownloadRuntime,
        task: DownloadTask,
        page: DownloadPage
    ) throws -> URL {
        if let storageLocations = runtime.storageLocations {
            return try storageLocations.pageURL(page, task: task)
        }
        guard page.path == "\(task.bookId)/\(task.id)/\(page.index).img", page.index >= 0 else {
            throw DownloadError.invalidIdentity
        }
        return try runtime.bookDirectory(bookID: task.bookId)
            .appendingPathComponent(task.id, isDirectory: true)
            .appendingPathComponent("\(page.index).img")
    }
    #endif
}
