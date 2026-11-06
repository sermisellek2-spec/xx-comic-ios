import UIKit
import ComicCore

// MARK: - SpreadBitmapError

public enum SpreadBitmapError: LocalizedError {
    case imageNotLoaded(String)
    case insufficientMemory(String)
    case canvasExceedsBudget(String)
    case cropFailed(String)

    public var errorDescription: String? {
        switch self {
        case .imageNotLoaded(let msg),
             .insufficientMemory(let msg),
             .canvasExceedsBudget(let msg),
             .cropFailed(let msg):
            return msg
        }
    }
}

// MARK: - SpreadBitmapComposer

/// Owned, bounded raster composition matching Android's SpreadBitmapComposer.
public final class SpreadBitmapComposer: @unchecked Sendable {
    private init() {}

    public final class Result: @unchecked Sendable {
        public let image: UIImage
        public let leftFraction: Double
        public var bitmap: UIImage { image }

        public init(image: UIImage, leftFraction: Double) {
            self.image = image
            self.leftFraction = leftFraction
        }

        public init(bitmap: UIImage, leftFraction: Double) {
            self.image = bitmap
            self.leftFraction = leftFraction
        }
    }

    /// Composes two page images side-by-side with common height scaling and memory bounds.
    public static func compose(first: UIImage,
                               second: UIImage,
                               firstOnLeft: Bool,
                               maxPixels: Int64 = 4_000_000,
                               maxBytes: Int64 = 16 * 1024 * 1024) throws -> Result {
        guard let leftCG = (firstOnLeft ? first : second).cgImage,
              let rightCG = (firstOnLeft ? second : first).cgImage else {
            throw SpreadBitmapError.imageNotLoaded("跨页图片未完整载入")
        }
        let left = firstOnLeft ? first : second
        let right = firstOnLeft ? second : first

        let leftW = Double(leftCG.width)
        let leftH = Double(leftCG.height)
        let rightW = Double(rightCG.width)
        let rightH = Double(rightCG.height)
        guard leftW > 0, leftH > 0, rightW > 0, rightH > 0 else {
            throw SpreadBitmapError.imageNotLoaded("跨页图片未完整载入")
        }

        let height = min(leftH, rightH)
        let leftWidth = leftW * height / leftH
        let rightWidth = rightW * height / rightH
        let available = min(Double(maxPixels), Double(maxBytes / 4))
        if available < 4 {
            throw SpreadBitmapError.insufficientMemory("当前设备没有足够内存显示跨页")
        }

        let scale = min(1.0, sqrt(available / ((leftWidth + rightWidth) * height)))
        let h = max(1, Int(floor(height * scale)))
        let lw = max(1, Int(floor(leftWidth * scale)))
        let rw = max(1, Int(floor(rightWidth * scale)))

        if Int64(lw + rw) * Int64(h) > Int64(available) {
            throw SpreadBitmapError.canvasExceedsBudget("跨页画布超出内存预算")
        }

        let totalWidth = lw + rw
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: h), format: format)
        let output = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: totalWidth, height: h))
            left.draw(in: CGRect(x: 0, y: 0, width: lw, height: h))
            right.draw(in: CGRect(x: lw, y: 0, width: rw, height: h))
        }

        let fraction = Double(lw) / Double(totalWidth)
        return Result(image: output, leftFraction: fraction)
    }

    /// Crops the left or right half of a double-page image.
    public static func cropDoublePage(image: UIImage, leftHalf: Bool) throws -> UIImage {
        guard let cg = image.cgImage else {
            throw SpreadBitmapError.imageNotLoaded("双页原图解码失败")
        }
        guard let cropped = cropDoublePage(cgImage: cg, leftHalf: leftHalf) else {
            throw SpreadBitmapError.cropFailed("双页原图宽度无效")
        }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Crops the left or right half of a double-page CGImage.
    public static func cropDoublePage(cgImage: CGImage, leftHalf: Bool) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 1, height > 0 else { return nil }
        let half = width / 2
        let left = leftHalf ? 0 : half
        let cropWidth = leftHalf ? half : (width - half)
        guard cropWidth > 0 else { return nil }
        return cgImage.cropping(to: CGRect(x: left, y: 0, width: cropWidth, height: height))
    }

    /// Extracts pixels conforming to SpreadDetectorPixels from a UIImage.
    public static func extractPixels(from image: UIImage) -> SpreadDetectorPixels? {
        guard let cg = image.cgImage else { return nil }
        return CGImageSpreadDetectorPixels(cgImage: cg)
    }

    /// Extracts pixels conforming to SpreadDetectorPixels from a CGImage.
    public static func extractPixels(from cgImage: CGImage) -> SpreadDetectorPixels? {
        return CGImageSpreadDetectorPixels(cgImage: cgImage)
    }
}

// MARK: - CGImageSpreadDetectorPixels

public final class CGImageSpreadDetectorPixels: SpreadDetectorPixels, @unchecked Sendable {
    public let width: Int
    public let height: Int
    private let pixels: [UInt32]

    public init?(cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        self.width = w
        self.height = h

        var rawBytes = [UInt8](repeating: 0, count: w * h * 4)
        let success = rawBytes.withUnsafeMutableBytes { (rawBuffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let ptr = rawBuffer.baseAddress else { return false }
            guard let context = CGContext(
                data: ptr,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard success else { return nil }

        var converted = [UInt32](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let offset = i * 4
            let r = UInt32(rawBytes[offset])
            let g = UInt32(rawBytes[offset + 1])
            let b = UInt32(rawBytes[offset + 2])
            let a = UInt32(rawBytes[offset + 3])
            converted[i] = (a << 24) | (r << 16) | (g << 8) | b
        }
        self.pixels = converted
    }

    public convenience init?(image: UIImage) {
        guard let cg = image.cgImage else { return nil }
        self.init(cgImage: cg)
    }

    public func argb(x: Int, y: Int) -> UInt32 {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return pixels[y * width + x]
    }
}

// MARK: - ReaderSpreadPalette

struct ReaderSpreadPalette {
    let panel: UIColor
    let card: UIColor
    let text: UIColor
    let secondary: UIColor
    let border: UIColor
    let accent: UIColor
    let primary: UIColor
    let danger: UIColor

    init(dark: Bool) {
        panel = dark ? UIColor(hex: 0x1C2128) : UIColor(hex: 0xFFFFFF)
        card = dark ? UIColor(hex: 0x22272E) : UIColor(hex: 0xF6F8FA)
        text = dark ? UIColor(hex: 0xE6EDF3) : UIColor(hex: 0x1F2328)
        secondary = dark ? UIColor(hex: 0x9DA7B3) : UIColor(hex: 0x656D76)
        border = dark ? UIColor(hex: 0x373E47) : UIColor(hex: 0xD8DEE4)
        accent = dark ? UIColor(hex: 0x388BFD) : UIColor(hex: 0x0969DA)
        primary = dark ? UIColor(hex: 0x1F6FEB) : UIColor(hex: 0x0969DA)
        danger = dark ? UIColor(hex: 0xFF938A) : UIColor(hex: 0xB42318)
    }
}

private extension UIColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

// MARK: - ReaderSpreadAction

@MainActor
public final class ReaderSpreadAction: @unchecked Sendable {
    public let title: String
    public let subtitle: String
    public let icon: UIImage?
    public let destructive: Bool
    public let run: () -> Void

    public init(title: String, subtitle: String, icon: UIImage? = nil, destructive: Bool = false, run: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.destructive = destructive
        self.run = run
    }

    init(title: String, subtitle: String, parityIcon: ParityIcon?, destructive: Bool = false, run: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = parityIcon?.image(size: 20)
        self.destructive = destructive
        self.run = run
    }

    convenience init(_ title: String, _ subtitle: String, _ destructive: Bool = false, run: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, icon: nil, destructive: destructive, run: run)
    }
}

// MARK: - ReaderSpreadActionSheet

@MainActor
public final class ReaderSpreadActionSheet: UIViewController {
    public typealias Action = ReaderSpreadAction

    private let dark: Bool
    private let sheetTitle: String
    private let pageLabel: String
    private let stateSummary: String
    private let status: String?
    private let currentActions: [Action]
    private let maintenanceActions: [Action]
    private let palette: ReaderSpreadPalette

    public init(dark: Bool,
                title: String,
                pageLabel: String,
                stateSummary: String,
                status: String?,
                current: [Action],
                maintenance: [Action]) {
        self.dark = dark
        self.sheetTitle = title
        self.pageLabel = pageLabel
        self.stateSummary = stateSummary
        self.status = status
        self.currentActions = current
        self.maintenanceActions = maintenance
        self.palette = ReaderSpreadPalette(dark: dark)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = palette.panel
        view.accessibilityViewIsModal = true
        view.accessibilityIdentifier = "reader.spread.actions.sheet"

        if let sheet = sheetPresentationController {
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 16
            if #available(iOS 16.0, *) {
                sheet.detents = [
                    .custom { [weak self] context in
                        guard let self else { return 450 }
                        return min(context.maximumDetentValue, self.estimatedHeight())
                    },
                    .large()
                ]
            } else {
                sheet.detents = [.medium(), .large()]
            }
        }

        setupUI()
    }

    private func estimatedHeight() -> CGFloat {
        var height: CGFloat = 84 // Top handle + header + padding
        height += 80 // Summary card
        if !currentActions.isEmpty {
            height += 30 + CGFloat(currentActions.count) * 64
        }
        if !maintenanceActions.isEmpty {
            height += 30 + CGFloat(maintenanceActions.count) * 64
        }
        return min(height, 650)
    }

    private func setupUI() {
        let handle = UIView()
        handle.backgroundColor = palette.border
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(handle)

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let titleLabel = UILabel()
        titleLabel.text = sheetTitle
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = palette.text
        titleLabel.accessibilityTraits = .header
        header.addArrangedSubview(titleLabel)

        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.accessibilityIdentifier = "reader.spread.sheet.scroll"
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let body = UIStackView()
        body.axis = .vertical
        body.spacing = 0
        body.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(body)

        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 32),
            handle.heightAnchor.constraint(equalToConstant: 4),

            header.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            header.heightAnchor.constraint(equalToConstant: 40),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            body.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        // Summary Card
        let summaryCard = createCardView()
        let summaryStack = UIStackView()
        summaryStack.axis = .vertical
        summaryStack.spacing = 0
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.addSubview(summaryStack)

        let rangeLabel = UILabel()
        rangeLabel.text = "原页 \(pageLabel)"
        rangeLabel.font = .systemFont(ofSize: 18, weight: .bold)
        rangeLabel.textColor = palette.text
        summaryStack.addArrangedSubview(rangeLabel)

        let stateLabel = UILabel()
        stateLabel.text = stateSummary
        stateLabel.font = .systemFont(ofSize: 13, weight: .regular)
        stateLabel.textColor = palette.accent
        stateLabel.numberOfLines = 0
        summaryStack.addArrangedSubview(createSpacer(6))
        summaryStack.addArrangedSubview(stateLabel)

        if let status, !status.isEmpty {
            let statusLabel = UILabel()
            statusLabel.text = status
            statusLabel.font = .systemFont(ofSize: 12, weight: .regular)
            statusLabel.textColor = palette.secondary
            statusLabel.numberOfLines = 0
            summaryStack.addArrangedSubview(createSpacer(8))
            summaryStack.addArrangedSubview(statusLabel)
        }

        NSLayoutConstraint.activate([
            summaryStack.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: 14),
            summaryStack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -14),
            summaryStack.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 14),
            summaryStack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -14)
        ])
        body.addArrangedSubview(summaryCard)

        // Action Groups
        addActionsGroup(title: "当前页", actions: currentActions, to: body)
        addActionsGroup(title: "识别与维护", actions: maintenanceActions, to: body)
    }

    private func addActionsGroup(title: String, actions: [Action], to body: UIStackView) {
        guard !actions.isEmpty else { return }

        let sectionHeader = UILabel()
        sectionHeader.text = title
        sectionHeader.font = .systemFont(ofSize: 12, weight: .bold)
        sectionHeader.textColor = palette.secondary

        let headerHost = UIView()
        headerHost.translatesAutoresizingMaskIntoConstraints = false
        sectionHeader.translatesAutoresizingMaskIntoConstraints = false
        headerHost.addSubview(sectionHeader)
        NSLayoutConstraint.activate([
            sectionHeader.leadingAnchor.constraint(equalTo: headerHost.leadingAnchor),
            sectionHeader.trailingAnchor.constraint(equalTo: headerHost.trailingAnchor),
            sectionHeader.topAnchor.constraint(equalTo: headerHost.topAnchor, constant: 16),
            sectionHeader.bottomAnchor.constraint(equalTo: headerHost.bottomAnchor, constant: -8)
        ])
        body.addArrangedSubview(headerHost)

        let groupCard = createCardView()
        let groupStack = UIStackView()
        groupStack.axis = .vertical
        groupStack.spacing = 0
        groupStack.translatesAutoresizingMaskIntoConstraints = false
        groupCard.addSubview(groupStack)

        NSLayoutConstraint.activate([
            groupStack.topAnchor.constraint(equalTo: groupCard.topAnchor),
            groupStack.bottomAnchor.constraint(equalTo: groupCard.bottomAnchor),
            groupStack.leadingAnchor.constraint(equalTo: groupCard.leadingAnchor),
            groupStack.trailingAnchor.constraint(equalTo: groupCard.trailingAnchor)
        ])

        for (index, action) in actions.enumerated() {
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = palette.border
                divider.translatesAutoresizingMaskIntoConstraints = false
                let dividerHost = UIView()
                dividerHost.translatesAutoresizingMaskIntoConstraints = false
                dividerHost.addSubview(divider)
                NSLayoutConstraint.activate([
                    divider.leadingAnchor.constraint(equalTo: dividerHost.leadingAnchor, constant: 46),
                    divider.trailingAnchor.constraint(equalTo: dividerHost.trailingAnchor, constant: -14),
                    divider.topAnchor.constraint(equalTo: dividerHost.topAnchor),
                    divider.bottomAnchor.constraint(equalTo: dividerHost.bottomAnchor),
                    divider.heightAnchor.constraint(equalToConstant: 1)
                ])
                groupStack.addArrangedSubview(dividerHost)
            }

            let row = UIControl()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.accessibilityTraits = .button
            row.accessibilityLabel = "\(action.title)，\(action.subtitle)"
            row.accessibilityIdentifier = "reader.spread.action.\(action.title)"

            let iconView = UIImageView()
            iconView.contentMode = .scaleAspectFit
            iconView.image = action.icon
            iconView.tintColor = action.destructive ? palette.danger : palette.accent
            iconView.translatesAutoresizingMaskIntoConstraints = false

            let textStack = UIStackView()
            textStack.axis = .vertical
            textStack.spacing = 4
            textStack.isUserInteractionEnabled = false
            textStack.translatesAutoresizingMaskIntoConstraints = false

            let actionTitle = UILabel()
            actionTitle.text = action.title
            actionTitle.font = .systemFont(ofSize: 14, weight: .bold)
            actionTitle.textColor = action.destructive ? palette.danger : palette.text

            let actionSub = UILabel()
            actionSub.text = action.subtitle
            actionSub.font = .systemFont(ofSize: 12, weight: .regular)
            actionSub.textColor = palette.secondary
            actionSub.numberOfLines = 0

            textStack.addArrangedSubview(actionTitle)
            textStack.addArrangedSubview(actionSub)

            row.addSubview(iconView)
            row.addSubview(textStack)

            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
                iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
                iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 20),
                iconView.heightAnchor.constraint(equalToConstant: 20),

                textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
                textStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
                textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
                textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12)
            ])

            row.addAction(UIAction { [weak self] _ in
                self?.dismiss(animated: true) {
                    action.run()
                }
            }, for: .touchUpInside)

            groupStack.addArrangedSubview(row)
        }

        body.addArrangedSubview(groupCard)
    }

    private func createCardView() -> UIView {
        let card = UIView()
        card.backgroundColor = palette.card
        card.layer.cornerRadius = 10
        card.layer.borderWidth = 1
        card.layer.borderColor = palette.border.cgColor
        card.clipsToBounds = true
        return card
    }

    private func createSpacer(_ height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }
}

// MARK: - ReaderSpreadPreviewSheet

@MainActor
public final class ReaderSpreadPreviewSheet: UIViewController {
    public let first: Int
    private let dark: Bool
    private let palette: ReaderSpreadPalette

    public let imageView = UIImageView()
    public let leftLabel = UILabel()
    public let rightLabel = UILabel()
    public let messageLabel = UILabel()
    public let progressView = UIActivityIndicatorView(style: .medium)
    public let retryButton = UIButton(type: .system)
    public let swapButton = UIButton(type: .system)
    public let confirmButton = UIButton(type: .system)
    private let placeholderView = UIStackView()

    public var onSwap: (() -> Void)?
    public var onConfirm: (() -> Void)?
    public var onRetry: (() -> Void)?
    public var onDismiss: (() -> Void)?

    public init(dark: Bool, first: Int) {
        self.dark = dark
        self.first = first
        self.palette = ReaderSpreadPalette(dark: dark)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = palette.panel
        view.accessibilityViewIsModal = true
        view.accessibilityIdentifier = "reader.spread.preview.sheet"

        if let sheet = sheetPresentationController {
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 16
            if #available(iOS 16.0, *) {
                sheet.detents = [
                    .custom { [weak self] context in
                        guard let self else { return 520 }
                        return min(context.maximumDetentValue, self.estimatedHeight())
                    },
                    .large()
                ]
            } else {
                sheet.detents = [.medium(), .large()]
            }
        }

        setupUI()
        loading(firstOnLeft: true)
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            clear()
            onDismiss?()
        }
    }

    private func estimatedHeight() -> CGFloat {
        return 490
    }

    private func setupUI() {
        let handle = UIView()
        handle.backgroundColor = palette.border
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(handle)

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let titleLabel = UILabel()
        titleLabel.text = "合并预览"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = palette.text
        titleLabel.accessibilityTraits = .header
        header.addArrangedSubview(titleLabel)

        let body = UIStackView()
        body.axis = .vertical
        body.spacing = 0
        body.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(body)

        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 32),
            handle.heightAnchor.constraint(equalToConstant: 4),

            header.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            header.heightAnchor.constraint(equalToConstant: 40),

            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            body.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            body.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            body.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        // Body info labels
        let pageRangeLabel = UILabel()
        pageRangeLabel.text = "原页 \(first + 1)–\(first + 2)"
        pageRangeLabel.font = .systemFont(ofSize: 14, weight: .bold)
        pageRangeLabel.textColor = palette.text
        body.addArrangedSubview(pageRangeLabel)

        let hintLabel = UILabel()
        hintLabel.text = "确认接缝和左右顺序后，再合并显示"
        hintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        hintLabel.textColor = palette.secondary
        let hintHost = UIView()
        hintHost.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintHost.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(equalTo: hintHost.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: hintHost.trailingAnchor),
            hintLabel.topAnchor.constraint(equalTo: hintHost.topAnchor, constant: 4),
            hintLabel.bottomAnchor.constraint(equalTo: hintHost.bottomAnchor, constant: -10)
        ])
        body.addArrangedSubview(hintHost)

        // Image Card
        let imageCard = UIView()
        imageCard.backgroundColor = palette.card
        imageCard.layer.cornerRadius = 10
        imageCard.layer.borderWidth = 1
        imageCard.layer.borderColor = palette.border.cgColor
        imageCard.clipsToBounds = true
        imageCard.translatesAutoresizingMaskIntoConstraints = false
        imageCard.heightAnchor.constraint(equalToConstant: 240).isActive = true
        body.addArrangedSubview(imageCard)

        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "reader.spread.preview.image"
        imageView.accessibilityLabel = "跨页合并预览"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageCard.addSubview(imageView)

        placeholderView.axis = .vertical
        placeholderView.alignment = .center
        placeholderView.spacing = 10
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        imageCard.addSubview(placeholderView)

        progressView.color = palette.secondary
        progressView.hidesWhenStopped = true
        placeholderView.addArrangedSubview(progressView)

        messageLabel.text = "正在加载原页…"
        messageLabel.font = .systemFont(ofSize: 13, weight: .regular)
        messageLabel.textColor = palette.secondary
        messageLabel.textAlignment = .center
        placeholderView.addArrangedSubview(messageLabel)

        retryButton.setTitle("重新加载", for: .normal)
        retryButton.setTitleColor(palette.accent, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        retryButton.backgroundColor = palette.card
        retryButton.layer.cornerRadius = 6
        retryButton.layer.borderWidth = 1
        retryButton.layer.borderColor = palette.border.cgColor
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        retryButton.accessibilityIdentifier = "reader.spread.preview.retry"
        retryButton.isHidden = true
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        placeholderView.addArrangedSubview(retryButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: imageCard.topAnchor, constant: 8),
            imageView.bottomAnchor.constraint(equalTo: imageCard.bottomAnchor, constant: -8),
            imageView.leadingAnchor.constraint(equalTo: imageCard.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: imageCard.trailingAnchor, constant: -8),

            placeholderView.centerXAnchor.constraint(equalTo: imageCard.centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: imageCard.centerYAnchor),
            placeholderView.leadingAnchor.constraint(greaterThanOrEqualTo: imageCard.leadingAnchor, constant: 16),
            placeholderView.trailingAnchor.constraint(lessThanOrEqualTo: imageCard.trailingAnchor, constant: -16)
        ])

        // Order bar
        let orderStack = UIStackView()
        orderStack.axis = .horizontal
        orderStack.distribution = .fillEqually
        orderStack.alignment = .center
        orderStack.translatesAutoresizingMaskIntoConstraints = false
        orderStack.heightAnchor.constraint(equalToConstant: 36).isActive = true

        leftLabel.font = .systemFont(ofSize: 13, weight: .bold)
        leftLabel.textColor = palette.accent
        leftLabel.textAlignment = .center
        leftLabel.accessibilityIdentifier = "reader.spread.preview.left"

        rightLabel.font = .systemFont(ofSize: 13, weight: .bold)
        rightLabel.textColor = palette.accent
        rightLabel.textAlignment = .center
        rightLabel.accessibilityIdentifier = "reader.spread.preview.right"

        orderStack.addArrangedSubview(leftLabel)
        orderStack.addArrangedSubview(rightLabel)

        let orderHost = UIView()
        orderHost.translatesAutoresizingMaskIntoConstraints = false
        orderStack.translatesAutoresizingMaskIntoConstraints = false
        orderHost.addSubview(orderStack)
        NSLayoutConstraint.activate([
            orderStack.leadingAnchor.constraint(equalTo: orderHost.leadingAnchor),
            orderStack.trailingAnchor.constraint(equalTo: orderHost.trailingAnchor),
            orderStack.topAnchor.constraint(equalTo: orderHost.topAnchor, constant: 4),
            orderStack.bottomAnchor.constraint(equalTo: orderHost.bottomAnchor, constant: -4)
        ])
        body.addArrangedSubview(orderHost)

        // Footer buttons
        let footerStack = UIStackView()
        footerStack.axis = .horizontal
        footerStack.spacing = 10
        footerStack.alignment = .fill
        footerStack.distribution = .fillProportionally
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        footerStack.heightAnchor.constraint(equalToConstant: 48).isActive = true

        swapButton.setTitle("左右互换", for: .normal)
        swapButton.setTitleColor(palette.accent, for: .normal)
        swapButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        swapButton.backgroundColor = palette.card
        swapButton.layer.cornerRadius = 8
        swapButton.layer.borderWidth = 1
        swapButton.layer.borderColor = palette.border.cgColor
        swapButton.accessibilityIdentifier = "reader.spread.preview.swap"
        swapButton.addAction(UIAction { [weak self] _ in self?.onSwap?() }, for: .touchUpInside)

        confirmButton.setTitle("按此顺序合并", for: .normal)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        confirmButton.backgroundColor = palette.primary
        confirmButton.layer.cornerRadius = 8
        confirmButton.accessibilityIdentifier = "reader.spread.preview.confirm"
        confirmButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) { [weak self] in
                self?.onConfirm?()
            }
        }, for: .touchUpInside)

        footerStack.addArrangedSubview(swapButton)
        footerStack.addArrangedSubview(confirmButton)

        // Width proportion: confirm is ~1.6x swap
        confirmButton.widthAnchor.constraint(equalTo: swapButton.widthAnchor, multiplier: 1.6).isActive = true

        let footerHost = UIView()
        footerHost.translatesAutoresizingMaskIntoConstraints = false
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        footerHost.addSubview(footerStack)
        NSLayoutConstraint.activate([
            footerStack.leadingAnchor.constraint(equalTo: footerHost.leadingAnchor),
            footerStack.trailingAnchor.constraint(equalTo: footerHost.trailingAnchor),
            footerStack.topAnchor.constraint(equalTo: footerHost.topAnchor, constant: 8),
            footerStack.bottomAnchor.constraint(equalTo: footerHost.bottomAnchor)
        ])
        body.addArrangedSubview(footerHost)
    }

    public func loading(firstOnLeft: Bool) {
        leftLabel.text = "左 · 原页 \(firstOnLeft ? first + 1 : first + 2)"
        rightLabel.text = "右 · 原页 \(firstOnLeft ? first + 2 : first + 1)"
        imageView.image = nil
        placeholderView.isHidden = false
        progressView.startAnimating()
        retryButton.isHidden = true
        messageLabel.text = "正在加载原页…"
        setConfirmEnabled(false)
    }

    public func loaded(_ image: UIImage) {
        imageView.image = image
        placeholderView.isHidden = true
        progressView.stopAnimating()
        setConfirmEnabled(true)
    }

    public func failed() {
        progressView.stopAnimating()
        placeholderView.isHidden = false
        messageLabel.text = "图片加载失败，请重试"
        retryButton.isHidden = false
        setConfirmEnabled(false)
    }

    public func clear() {
        imageView.image = nil
    }

    private func setConfirmEnabled(_ enabled: Bool) {
        confirmButton.isEnabled = enabled
        confirmButton.alpha = enabled ? 1.0 : 0.45
    }
}

// MARK: - ReaderSpreadSheet Namespace

@MainActor
public enum ReaderSpreadSheet {
    public typealias Action = ReaderSpreadAction
    public typealias ActionSheet = ReaderSpreadActionSheet
    public typealias PreviewSheet = ReaderSpreadPreviewSheet

    @discardableResult
    public static func showActions(from presenter: UIViewController,
                                   dark: Bool,
                                   pageLabel: String,
                                   spread: Bool,
                                   order: String,
                                   status: String?,
                                   current: [ReaderSpreadAction],
                                   maintenance: [ReaderSpreadAction]) -> ReaderSpreadActionSheet {
        showActions(from: presenter, dark: dark, title: "跨页操作", pageLabel: pageLabel, spread: spread, order: order, status: status, current: current, maintenance: maintenance)
    }

    @discardableResult
    public static func showActions(from presenter: UIViewController,
                                   dark: Bool,
                                   title: String,
                                   pageLabel: String,
                                   spread: Bool,
                                   order: String,
                                   status: String?,
                                   current: [ReaderSpreadAction],
                                   maintenance: [ReaderSpreadAction]) -> ReaderSpreadActionSheet {
        let stateSummary = spread ? "已还原为跨页 · \(order)" : "当前为单页 · 可选择相邻页合并"
        return showActions(from: presenter, dark: dark, title: title, pageLabel: pageLabel, stateSummary: stateSummary, status: status, current: current, maintenance: maintenance)
    }

    @discardableResult
    public static func showActions(from presenter: UIViewController,
                                   dark: Bool,
                                   title: String,
                                   pageLabel: String,
                                   stateSummary: String,
                                   status: String?,
                                   current: [ReaderSpreadAction],
                                   maintenance: [ReaderSpreadAction]) -> ReaderSpreadActionSheet {
        let sheet = ReaderSpreadActionSheet(dark: dark, title: title, pageLabel: pageLabel, stateSummary: stateSummary, status: status, current: current, maintenance: maintenance)
        presenter.present(sheet, animated: true)
        return sheet
    }

    @discardableResult
    public static func showPreview(from presenter: UIViewController,
                                   dark: Bool,
                                   first: Int) -> ReaderSpreadPreviewSheet {
        let sheet = ReaderSpreadPreviewSheet(dark: dark, first: first)
        presenter.present(sheet, animated: true)
        return sheet
    }
}
