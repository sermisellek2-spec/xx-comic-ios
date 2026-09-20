import Foundation

public struct PdfPublication: Codable, Equatable, Sendable {
    public struct PageSize: Codable, Equatable, Sendable {
        public let width: Double
        public let height: Double
        public init(width: Double, height: Double) { self.width = width; self.height = height }
    }
    public let pages: [PageSize]
    public init(pages: [PageSize]) { self.pages = pages }

    func validate() throws {
        guard (1...50_000).contains(pages.count) else { throw PdfError.invalidDocument }
        for page in pages {
            try Task.checkCancellation()
            guard page.width.isFinite, page.height.isFinite, page.width > 0, page.height > 0 else { throw PdfError.invalidDocument }
        }
    }

    public static func renderSize(width: Double, height: Double, maximumDimension: Int = 2048) throws -> PageSize {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw PdfError.invalidDocument }
        let scale = min(2.5, max(1, Double(maximumDimension > 0 ? maximumDimension : 2048) / max(width, height)))
        let w = max(1, (width * scale).rounded()), h = max(1, (height * scale).rounded())
        let budget = 24_000_000.0
        guard w > budget / h else { return PageSize(width: w, height: h) }
        // Unlike Android, cap allocation at 24M pixels, also for extremely elongated pages.
        // Ratio form avoids overflow when finite source dimensions have an infinite product.
        let ratio = min(w, h) / max(w, h)
        let long = floor(min(budget, sqrt(budget / ratio)))
        let short = max(1, floor(long * ratio))
        return w >= h ? PageSize(width: long, height: short) : PageSize(width: short, height: long)
    }
}

public enum PdfError: Error, LocalizedError {
    case invalidDocument, encrypted, renderFailed
    public var errorDescription: String? {
        switch self {
        case .invalidDocument: return "PDF 损坏、没有有效页面或超过 50000 页，原文件已保留。"
        case .encrypted: return "PDF 受密码保护，暂不支持加密 PDF 文件。"
        case .renderFailed: return "PDF 页面渲染失败，请重试或重新导入文件。"
        }
    }
}
