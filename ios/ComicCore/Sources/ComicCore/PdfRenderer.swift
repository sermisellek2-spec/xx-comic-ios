#if canImport(CoreGraphics) && canImport(ImageIO)
import Foundation
import CoreGraphics
import ImageIO

/// Each invocation owns its document and bitmap, so no CoreGraphics document crosses workers.
public enum PdfRenderer {
    private static func open(_ url: URL) throws -> CGPDFDocument {
        try Task.checkCancellation()
        guard url.isFileURL, let document = CGPDFDocument(url as CFURL) else { throw PdfError.invalidDocument }
        guard !document.isEncrypted, document.isUnlocked else { throw PdfError.encrypted }
        guard (1...50_000).contains(document.numberOfPages), document.page(at: 1) != nil else {
            throw PdfError.invalidDocument
        }
        // CoreGraphics can expose a one-page document for a PDF created with
        // no page contents. Such a document is not renderable and must be
        // rejected during inspection rather than failing later in the reader.
        guard let first = document.page(at: 1),
              let dictionary = first.dictionary else { throw PdfError.invalidDocument }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(dictionary, "Contents", &stream), let stream else {
            throw PdfError.invalidDocument
        }
        var format = CGPDFDataFormat.raw
        guard let streamData = CGPDFStreamCopyData(stream, &format), CFDataGetLength(streamData) > 0 else {
            throw PdfError.invalidDocument
        }
        try Task.checkCancellation()
        return document
    }

    private static func size(_ page: CGPDFPage) throws -> PdfPublication.PageSize {
        let box = page.getBoxRect(.cropBox)
        guard box.origin.x.isFinite, box.origin.y.isFinite, box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0 else { throw PdfError.invalidDocument }
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        guard rotation % 90 == 0 else { throw PdfError.invalidDocument }
        return rotation == 90 || rotation == 270
            ? .init(width: Double(box.height), height: Double(box.width))
            : .init(width: Double(box.width), height: Double(box.height))
    }

    public static func inspect(_ url: URL) throws -> PdfPublication {
        let document = try open(url)
        var pages: [PdfPublication.PageSize] = []
        for index in 1...document.numberOfPages {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw PdfError.invalidDocument }
            pages.append(try size(page))
        }
        try Task.checkCancellation()
        let publication = PdfPublication(pages: pages)
        try publication.validate()
        return publication
    }

    public static func render(_ url: URL, pageIndex: Int, maximumDimension: Int = 2048, quality: Double = 0.92) throws -> Data {
        let document = try open(url)
        guard pageIndex >= 0, pageIndex < document.numberOfPages, quality.isFinite, (0...1).contains(quality),
              let page = document.page(at: pageIndex + 1) else { throw PdfError.renderFailed }
        try Task.checkCancellation()
        let pageSize = try size(page)
        let pixels = try PdfPublication.renderSize(width: pageSize.width, height: pageSize.height, maximumDimension: maximumDimension)
        try Task.checkCancellation()
        let width = Int(pixels.width), height = Int(pixels.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw PdfError.renderFailed
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: false))
        // CoreGraphics' page transform is expressed in page points on some
        // Apple SDKs. Apply the final pixel scale explicitly so a 2.5x render
        // does not leave the PDF content at its original point dimensions.
        context.scaleBy(x: CGFloat(width) / CGFloat(pageSize.width),
                        y: CGFloat(height) / CGFloat(pageSize.height))
        try Task.checkCancellation()
        context.drawPDFPage(page)
        try Task.checkCancellation()
        guard let image = context.makeImage() else { throw PdfError.renderFailed }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil) else { throw PdfError.renderFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PdfError.renderFailed }
        try Task.checkCancellation()
        return output as Data
    }
}
#endif
