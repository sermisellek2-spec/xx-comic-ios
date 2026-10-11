import UIKit
import ImageIO
import CoreImage
import ComicCore

@MainActor
final class RemoteImageView: UIImageView {
    static var imageUrlResolver: ((_ imageUrl: String, _ force: Bool) async throws -> String)?
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private static var cacheGeneration = UUID()
    static func clearMemoryCache() {
        cacheGeneration = UUID()
        cache.removeAllObjects()
    }
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var original: UIImage?
    private var effectsTask: Task<Void, Never>?
    private var effectsID = UUID()
    private var cropMargins = false, cropVertical = false, inkScreen = false
    private var loadedContentMode: UIView.ContentMode = .scaleToFill
    private var showingCoverPlaceholder = false
    var onLoaded: ((CGSize) -> Void)?
    var onFailure: (() -> Void)?
    var needsReload: Bool { original == nil && task == nil }

    private func beginLoad(reader: Bool) {
        cancel()
        if !showingCoverPlaceholder { loadedContentMode = contentMode }
        original = nil
        backgroundColor = Palette.card
        showingCoverPlaceholder = !reader
        if reader {
            image = nil
            contentMode = loadedContentMode
        } else {
            image = UIImage(named: "rem_no_image")
            contentMode = .scaleAspectFit
        }
    }

    func loadCover(_ comic: ComicSummary, referer: String, library: LocalLibrary) {
        guard comic.sourceId == "local", comic.coverUrl.isEmpty else { load(comic.coverUrl, referer: referer); return }
        beginLoad(reader: false)
        let token = generation
        let worker = Task.detached { () async throws -> LocalBook in
            try Task.checkCancellation()
            // A collection has its own stable ID; its cover belongs to the first volume.
            if let series = try await library.series(id: comic.comicId), let volumeID = series.volumeIDs.first {
                return try library.book(id: volumeID)
            }
            return try library.book(id: comic.comicId)
        }
        task = Task { [weak self] in
            defer { if self?.generation == token { self?.task = nil } }
            do {
                let book = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if let epub = book.epub { self.original = TextBookCover.image(title: book.title, author: epub.author) }
                else if book.pdf != nil { self.original = UIImage(systemName: "doc.richtext") }
                self.render()
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.onFailure?()
            }
        }
    }

    func load(_ text: String, referer: String, reader: Bool = false, localPageImage: (@Sendable (URL) throws -> Data)? = nil) {
        beginLoad(reader: reader)
        guard let url = URL(string: text),
              ["https", "http", "file"].contains(url.scheme?.lowercased() ?? "") || (["xxcomic-epub", "xxcomic-pdf"].contains(url.scheme ?? "") && localPageImage != nil) else {
            onFailure?(); return
        }
        var cacheIdentity = !PublicSourceImages.sourceId(text).isEmpty
            ? PublicSourceImages.cacheIdentity(text)
            : ZaimanhuaComicSource.imageCacheIdentity(text)
        if XinmanhuaImageDecoder.usesImageHost(cacheIdentity) {
            cacheIdentity = "xinmanhua-jpeg-v2:" + cacheIdentity
        }
        let effectiveReferer = PublicSourceImages.referer(text, fallback: referer)
        let key = ((reader ? "reader\n" : "cover\n") + effectiveReferer + "\n" + cacheIdentity) as NSString
        if let cached = Self.cache.object(forKey: key) {
            original = cached; render()
            return
        }
        let token = generation
        let cacheToken = Self.cacheGeneration
        task = Task { [weak self] in
            defer { if self?.generation == token { self?.task = nil } }
            do {
                var request = URLRequest(url: url)
                if !effectiveReferer.isEmpty {
                    request.setValue(effectiveReferer, forHTTPHeaderField: "Referer")
                }
                // Match Android SourceImageFetcher.applyHeaders for cover and reader requests.
                request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue("image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
                request.setValue("image", forHTTPHeaderField: "Sec-Fetch-Dest")
                request.setValue("no-cors", forHTTPHeaderField: "Sec-Fetch-Mode")
                request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
                request.timeoutInterval = 30
                let data: Data
                if ["xxcomic-epub", "xxcomic-pdf"].contains(url.scheme ?? "") || (url.isFileURL && localPageImage != nil) {
                    guard let localPageImage else { throw URLError(.unsupportedURL) }
                    let worker = Task.detached(priority: .userInitiated) {
                        try Task.checkCancellation()
                        let bytes = try localPageImage(url)
                        try Task.checkCancellation()
                        guard bytes.count <= LocalLibrary.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
                        return bytes
                    }
                    data = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                } else if url.isFileURL {
                    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                    let resolved = url.resolvingSymlinksInPath().standardizedFileURL
                    let suffix = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "XXComic-UITests" : "XXComic"
                    let allowed = support.appendingPathComponent(suffix).appendingPathComponent("Local").resolvingSymlinksInPath()
                    guard resolved.path.hasPrefix(allowed.path + "/") else { throw URLError(.noPermissionsToReadFile) }
                    let worker = Task.detached(priority: .userInitiated) {
                        try FileAccessCoordinator.system.coordinate(resolved, access: .read) {
                            try FileAccessCoordinator.readRegularFile($0, maximumBytes: Int64(LocalLibrary.maximumImageBytes))
                        }
                    }
                    data = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                } else {
                    let isSigned = text.contains("#xx-")
                    var fetchedBytes: Data?
                    for attempt in 0..<(isSigned ? 2 : 1) {
                        let resolvedText: String
                        if isSigned, let resolver = Self.imageUrlResolver {
                            resolvedText = try await resolver(text, attempt > 0)
                        } else {
                            resolvedText = PublicSourceImages.strip(text)
                        }
                        guard let resolvedURL = URL(string: resolvedText) else {
                            throw URLError(.badURL)
                        }
                        var req = request
                        req.url = resolvedURL
                        let ref = PublicSourceImages.referer(resolvedText, fallback: effectiveReferer)
                        if !ref.isEmpty {
                            req.setValue(ref, forHTTPHeaderField: "Referer")
                        }
                        let (bytes, response) = try await URLSession.shared.data(for: req)
                        if let http = response as? HTTPURLResponse {
                            if isSigned && attempt == 0 && (http.statusCode == 403 || http.statusCode == 410) {
                                continue
                            }
                            if (200..<300).contains(http.statusCode), bytes.count <= 40 * 1024 * 1024 {
                                fetchedBytes = bytes
                                break
                            }
                        }
                        throw URLError(.badServerResponse)
                    }
                    guard let bytes = fetchedBytes else {
                        throw URLError(.badServerResponse)
                    }
                    data = bytes
                }
                try Task.checkCancellation()
                let decoder = Task.detached(priority: .userInitiated) { () throws -> UIImage? in
                    try Task.checkCancellation()
                    let imageData: Data
                    if !PublicSourceImages.sourceId(text).isEmpty {
                        imageData = try PublicSourceImages.decode(data, tagged: text)
                    } else if XinmanhuaImageDecoder.usesImageHost(text) {
                        imageData = try XinmanhuaImageDecoder.decode(data)
                    } else if ManwaImageDecoder.usesImageHost(text) {
                        imageData = try ManwaImageDecoder.decode(data)
                    } else {
                        imageData = data
                    }
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
                    return UIImage(cgImage: reader ? try JmImageTransform.restore(image, imageURL: text) : image)
                }
                let decoded = try await withTaskCancellationHandler {
                    try await decoder.value
                } onCancel: { decoder.cancel() }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                guard let decoded else { self.onFailure?(); return }
                if cacheToken == Self.cacheGeneration {
                    Self.cache.setObject(decoded, forKey: key, cost: Int(decoded.size.width * decoded.size.height * 4))
                }
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
        showingCoverPlaceholder = false
        contentMode = loadedContentMode
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
    private let sourceLabel = UILabel()
    private let latestOverlay = UIView()
    private let latestLabel = UILabel()
    private let badgeContainer = UIView()
    private let badgeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 8

        badgeContainer.layer.cornerRadius = 9
        badgeContainer.clipsToBounds = true
        badgeContainer.isHidden = true

        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor, constant: 2),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeContainer.bottomAnchor, constant: -2),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
            badgeContainer.heightAnchor.constraint(equalToConstant: 18)
        ])

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.numberOfLines = 1
        nameLabel.textColor = Palette.text
        sourceLabel.font = .systemFont(ofSize: 11); sourceLabel.textColor = Palette.text3
        latestOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        latestLabel.font = .systemFont(ofSize: 10); latestLabel.textColor = .white
        latestLabel.translatesAutoresizingMaskIntoConstraints = false; latestOverlay.addSubview(latestLabel)

        for view in [cover, nameLabel, sourceLabel, latestOverlay, badgeContainer] { view.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(view) }
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: contentView.topAnchor), cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), cover.heightAnchor.constraint(equalTo: cover.widthAnchor, multiplier: 4 / 3),
            badgeContainer.topAnchor.constraint(equalTo: cover.topAnchor, constant: 6),
            badgeContainer.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: -6),
            nameLabel.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 6), nameLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            sourceLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            sourceLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor), sourceLabel.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            sourceLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            latestOverlay.leadingAnchor.constraint(equalTo: cover.leadingAnchor), latestOverlay.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            latestOverlay.bottomAnchor.constraint(equalTo: cover.bottomAnchor), latestOverlay.heightAnchor.constraint(equalToConstant: 20),
            latestLabel.leadingAnchor.constraint(equalTo: latestOverlay.leadingAnchor, constant: 6), latestLabel.trailingAnchor.constraint(equalTo: latestOverlay.trailingAnchor, constant: -6),
            latestLabel.centerYAnchor.constraint(equalTo: latestOverlay.centerYAnchor)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func configure(_ comic: ComicCore.ComicSummary, referer: String, library: LocalLibrary,
                   badgeText: String? = nil, badgeColor: UIColor? = nil, sourceName: String? = nil, latestChapter: String? = nil) {
        nameLabel.text = comic.title
        accessibilityLabel = comic.title
        sourceLabel.text = sourceName; sourceLabel.isHidden = sourceName == nil
        latestOverlay.isHidden = latestChapter?.isEmpty != false
        latestLabel.text = latestChapter.map { BookshelfLayoutHelper.formatOnlineLatestChapter($0) }
        cover.loadCover(comic, referer: referer, library: library)

        if let badgeText, !badgeText.isEmpty {
            badgeLabel.text = badgeText
            badgeContainer.backgroundColor = badgeColor ?? Palette.accent
            badgeContainer.isHidden = false
        } else {
            badgeContainer.isHidden = true
        }
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        cover.cancel()
        cover.image = nil
        badgeContainer.isHidden = true
        latestOverlay.isHidden = true
        accessibilityValue = nil
    }
}

@MainActor
final class ComicListCell: UICollectionViewCell {
    let cover = RemoteImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailLabel = UILabel()
    private let badgeContainer = UIView()
    private let badgeLabel = UILabel()
    private var coverWidth: NSLayoutConstraint!
    private var coverHeight: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Palette.card
        contentView.backgroundColor = Palette.card
        layer.cornerRadius = 8
        clipsToBounds = true

        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 6
        cover.translatesAutoresizingMaskIntoConstraints = false

        badgeContainer.layer.cornerRadius = 9
        badgeContainer.clipsToBounds = true
        badgeContainer.isHidden = true
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor, constant: 2),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeContainer.bottomAnchor, constant: -2),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
            badgeContainer.heightAnchor.constraint(equalToConstant: 18)
        ])

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = Palette.text2
        subtitleLabel.numberOfLines = 1

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = Palette.accent
        detailLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(cover)
        contentView.addSubview(badgeContainer)
        contentView.addSubview(textStack)

        coverWidth = cover.widthAnchor.constraint(equalToConstant: 54)
        coverHeight = cover.heightAnchor.constraint(equalToConstant: 72)
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            cover.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverWidth, coverHeight,

            badgeContainer.topAnchor.constraint(equalTo: cover.topAnchor, constant: -4),
            badgeContainer.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 4),

            textStack.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func configure(_ comic: ComicCore.ComicSummary, referer: String, library: LocalLibrary,
                   subtitle: String? = nil, detail: String? = nil,
                   badgeText: String? = nil, badgeColor: UIColor? = nil, largeCover: Bool = false) {
        titleLabel.text = comic.title
        accessibilityLabel = comic.title
        subtitleLabel.text = subtitle ?? (comic.subtitle.isEmpty ? "暂无信息" : comic.subtitle)
        detailLabel.text = detail ?? (comic.sourceId == "local" ? "本地漫画" : "")
        detailLabel.isHidden = (detailLabel.text?.isEmpty ?? true)
        coverWidth.constant = largeCover ? 68 : 54
        coverHeight.constant = largeCover ? 91 : 72
        cover.loadCover(comic, referer: referer, library: library)

        if let badgeText, !badgeText.isEmpty {
            badgeLabel.text = badgeText
            badgeContainer.backgroundColor = badgeColor ?? Palette.accent
            badgeContainer.isHidden = false
        } else {
            badgeContainer.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cover.cancel()
        cover.image = nil
        badgeContainer.isHidden = true
        accessibilityValue = nil
    }
}
