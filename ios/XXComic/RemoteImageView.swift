import UIKit
import ImageIO
import CoreImage
import ComicCore

@MainActor
final class RemoteImageView: UIImageView {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var original: UIImage?
    private var effectsTask: Task<Void, Never>?
    private var effectsID = UUID()
    private var cropMargins = false, cropVertical = false, inkScreen = false
    var onLoaded: ((CGSize) -> Void)?
    var onFailure: (() -> Void)?

    func load(_ text: String, referer: String, reader: Bool = false) {
        cancel()
        image = nil; original = nil
        backgroundColor = Palette.card
        guard let url = URL(string: text), ["https", "http", "file"].contains(url.scheme?.lowercased() ?? "") else {
            onFailure?(); return
        }
        let key = ((reader ? "reader\n" : "cover\n") + referer + "\n" + text) as NSString
        if let cached = Self.cache.object(forKey: key) {
            original = cached; render()
            return
        }
        let token = generation
        task = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.setValue(referer, forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 30
                let data: Data
                if url.isFileURL {
                    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                    let resolved = url.resolvingSymlinksInPath().standardizedFileURL
                    let suffix = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "XXComic-UITests" : "XXComic"
                    let allowed = support.appendingPathComponent(suffix).appendingPathComponent("Local").resolvingSymlinksInPath()
                    guard resolved.path.hasPrefix(allowed.path + "/") else { throw URLError(.noPermissionsToReadFile) }
                    data = try await Task.detached(priority: .userInitiated) {
                        let size = try resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= LocalLibrary.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
                        return try Data(contentsOf: resolved, options: .mappedIfSafe)
                    }.value
                } else {
                    let (bytes, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 40 * 1024 * 1024 else {
                        throw URLError(.badServerResponse)
                    }
                    data = bytes
                }
                let decoded = try await Task.detached(priority: .userInitiated) { () throws -> UIImage? in
                    let imageData = ManwaImageDecoder.usesImageHost(text) ? try ManwaImageDecoder.decode(data) : data
                    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
                    var maximumDimension = 4096
                    if reader, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                       let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                       let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                       width.doubleValue > 0, height.doubleValue > 0 {
                        // Preserve long-strip text; constrain decoded pixel area, not its longest edge.
                        let scale = min(1, sqrt(24_000_000 / (width.doubleValue * height.doubleValue)))
                        maximumDimension = max(1, Int(max(width.doubleValue, height.doubleValue) * scale))
                    }
                    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                            kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary) else { return nil }
                    return UIImage(cgImage: image)
                }.value
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                guard let decoded else { self.onFailure?(); return }
                Self.cache.setObject(decoded, forKey: key, cost: Int(decoded.size.width * decoded.size.height * 4))
                self.original = decoded
                self.render()
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.onFailure?()
            }
        }
    }

    func setReaderEffects(crop: Bool, vertical: Bool, ink: Bool) {
        guard crop != cropMargins || vertical != cropVertical || ink != inkScreen else { return }
        cropMargins = crop; cropVertical = vertical; inkScreen = ink
        render()
    }
    private func render() {
        effectsTask?.cancel(); effectsID = UUID()
        guard let original else { return }
        guard cropMargins || inkScreen else { image = original; onLoaded?(original.size); return }
        let token = effectsID, crop = cropMargins, vertical = cropVertical, ink = inkScreen
        effectsTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage in
                guard var cg = original.cgImage else { return original }
                if crop {
                    let width = cg.width, height = cg.height
                    var bytes = [UInt8](repeating: 0, count: width * height * 4)
                    let rect: ImageCrop? = bytes.withUnsafeMutableBytes { buffer in
                        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                                      space: CGColorSpaceCreateDeviceRGB(),
                                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
                        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                        let pixels = buffer.bindMemory(to: UInt8.self)
                        return WhiteMarginDetector.detect(width: width, height: height, cropVertical: vertical) { x, y in
                            let i = (y * width + x) * 4
                            return UInt32(pixels[i + 3]) << 24 | UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
                        }
                    }
                    if let rect, let cropped = cg.cropping(to: CGRect(x: rect.left, y: rect.top, width: rect.right - rect.left, height: rect.bottom - rect.top)) { cg = cropped }
                }
                if ink {
                    let input = CIImage(cgImage: cg)
                    let weights = CIVector(x: 0.213 * 1.25, y: 0.715 * 1.25, z: 0.072 * 1.25, w: 0)
                    let output = input.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": weights, "inputGVector": weights, "inputBVector": weights,
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                        "inputBiasVector": CIVector(x: -0.125, y: -0.125, z: -0.125, w: 0)
                    ])
                    if let filtered = CIContext().createCGImage(output, from: input.extent) { cg = filtered }
                }
                return UIImage(cgImage: cg)
            }.value
            guard let self, !Task.isCancelled, self.effectsID == token else { return }
            self.image = rendered; self.onLoaded?(rendered.size)
        }
    }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil
        effectsID = UUID(); effectsTask?.cancel(); effectsTask = nil
    }
    deinit { task?.cancel(); effectsTask?.cancel() }
}

@MainActor
final class ComicCell: UICollectionViewCell {
    let cover = RemoteImageView()
    private let nameLabel = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 8
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.numberOfLines = 2
        nameLabel.textColor = Palette.text
        for view in [cover, nameLabel] { view.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(view) }
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: contentView.topAnchor), cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), cover.heightAnchor.constraint(equalTo: cover.widthAnchor, multiplier: 4 / 3),
            nameLabel.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 6), nameLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: cover.trailingAnchor), nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    func configure(_ comic: ComicCore.ComicSummary, referer: String) {
        nameLabel.text = comic.title
        accessibilityLabel = comic.title
        cover.load(comic.coverUrl, referer: referer)
    }
    override func prepareForReuse() { super.prepareForReuse(); cover.cancel(); cover.image = nil }
}
