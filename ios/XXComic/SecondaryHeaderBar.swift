import UIKit

/// Standardizes secondary page `UINavigationBar` appearance and action items
/// while preserving native `UINavigationBar` / `navigationItem` for XCUITest compatibility.
@MainActor
enum SecondaryHeaderBar {
    static let cardCornerRadius: CGFloat = 8
    static let iconSurfaceSize: CGFloat = 34
    static let minTapSize: CGFloat = 44

    static func configureNavigationBarAppearance(for navigationController: UINavigationController?) {
        guard let navBar = navigationController?.navigationBar else { return }
        navBar.tintColor = Palette.accent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.background
        appearance.shadowColor = Palette.borderSoft
        appearance.titleTextAttributes = [
            .foregroundColor: Palette.text,
            .font: UIFont.systemFont(ofSize: 19, weight: .bold)
        ]
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
    }

    static func apply(to viewController: UIViewController, title: String, meta: String? = nil) {
        viewController.title = title
        configureNavigationBarAppearance(for: viewController.navigationController)

        let titleView: HeaderTitleView
        if let existing = viewController.navigationItem.titleView as? HeaderTitleView {
            titleView = existing
        } else {
            titleView = HeaderTitleView()
            viewController.navigationItem.titleView = titleView
        }
        titleView.configure(title: title, meta: meta)
    }

    static func updateMeta(_ meta: String?, on viewController: UIViewController) {
        let title = viewController.title ?? ""
        apply(to: viewController, title: title, meta: meta)
    }

    static func iconButton(
        icon: ParityIcon,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        target: Any?,
        action: Selector
    ) -> UIBarButtonItem {
        let button = HeaderIconControl(icon: icon)
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        if let target {
            button.addTarget(target, action: action, for: .touchUpInside)
        }
        return UIBarButtonItem(customView: button)
    }

    static func iconButton(
        icon: ParityIcon,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> UIBarButtonItem {
        let button = HeaderIconControl(icon: icon)
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }

    static func moreButton(
        accessibilityLabel: String = "更多操作",
        accessibilityIdentifier: String,
        target: Any?,
        action: Selector
    ) -> UIBarButtonItem {
        iconButton(
            icon: .moreDots,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier,
            target: target,
            action: action
        )
    }

    static func textButton(
        title: String,
        accessibilityIdentifier: String,
        target: Any?,
        action: Selector
    ) -> UIBarButtonItem {
        let button = HeaderCapsuleTextControl(title: title)
        button.accessibilityIdentifier = accessibilityIdentifier
        if let target {
            button.addTarget(target, action: action, for: .touchUpInside)
        }
        return UIBarButtonItem(customView: button)
    }

    static func textButton(
        title: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> UIBarButtonItem {
        let button = HeaderCapsuleTextControl(title: title)
        button.accessibilityIdentifier = accessibilityIdentifier
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }

    static func updateTextButton(_ item: UIBarButtonItem?, title: String, isHidden: Bool = false) {
        guard let control = item?.customView as? HeaderCapsuleTextControl else { return }
        control.setTitle(title)
        control.isHidden = isHidden
    }
}

@MainActor
private final class HeaderTitleView: UIView {
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false

        titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 18, weight: .bold))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Palette.text
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityTraits = .header

        metaLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11, weight: .regular))
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.textColor = Palette.text3
        metaLabel.textAlignment = .center
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.isHidden = true

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(metaLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func configure(title: String, meta: String?) {
        titleLabel.text = title
        let trimmedMeta = meta?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        metaLabel.text = trimmedMeta
        metaLabel.isHidden = trimmedMeta.isEmpty
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        let size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: max(80, size.width), height: max(24, size.height))
    }
}

@MainActor
private final class HeaderIconControl: UIControl {
    private let surface = UIView()
    private let glyph = UIImageView()

    init(icon: ParityIcon) {
        super.init(frame: CGRect(x: 0, y: 0, width: SecondaryHeaderBar.minTapSize, height: SecondaryHeaderBar.minTapSize))
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button

        surface.backgroundColor = Palette.accentSoft
        surface.layer.cornerRadius = SecondaryHeaderBar.cardCornerRadius
        surface.layer.borderWidth = 1
        surface.layer.borderColor = Palette.borderSoft.cgColor
        surface.isUserInteractionEnabled = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        glyph.image = icon.image(size: 20)
        glyph.tintColor = Palette.accent
        glyph.contentMode = .scaleAspectFit
        glyph.isUserInteractionEnabled = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(glyph)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: SecondaryHeaderBar.minTapSize),
            heightAnchor.constraint(greaterThanOrEqualToConstant: SecondaryHeaderBar.minTapSize),
            surface.centerXAnchor.constraint(equalTo: centerXAnchor),
            surface.centerYAnchor.constraint(equalTo: centerYAnchor),
            surface.widthAnchor.constraint(equalToConstant: SecondaryHeaderBar.iconSurfaceSize),
            surface.heightAnchor.constraint(equalToConstant: SecondaryHeaderBar.iconSurfaceSize),
            glyph.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 20),
            glyph.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override var isHighlighted: Bool {
        didSet {
            surface.alpha = isHighlighted ? 0.65 : 1.0
        }
    }

    override var isEnabled: Bool {
        didSet {
            surface.alpha = isEnabled ? 1.0 : 0.45
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        surface.layer.borderColor = Palette.borderSoft.resolvedColor(with: traitCollection).cgColor
    }
}

@MainActor
private final class HeaderCapsuleTextControl: UIControl {
    private let pill = UIView()
    private let label = UILabel()

    init(title: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: 56, height: SecondaryHeaderBar.minTapSize))
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title

        pill.backgroundColor = Palette.accentSoft
        pill.layer.cornerRadius = 16
        pill.layer.borderWidth = 1
        pill.layer.borderColor = Palette.borderSoft.cgColor
        pill.isUserInteractionEnabled = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        label.text = title
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 13, weight: .medium))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Palette.readable(foreground: Palette.accentText, background: Palette.accentSoft, fallback: Palette.text)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
            heightAnchor.constraint(greaterThanOrEqualToConstant: SecondaryHeaderBar.minTapSize),
            pill.leadingAnchor.constraint(equalTo: leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func setTitle(_ title: String) {
        label.text = title
        accessibilityLabel = title
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        let pillSize = pill.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: max(52, pillSize.width), height: max(SecondaryHeaderBar.minTapSize, pillSize.height))
    }

    override var isHighlighted: Bool {
        didSet {
            pill.alpha = isHighlighted ? 0.65 : 1.0
        }
    }

    override var isEnabled: Bool {
        didSet {
            pill.alpha = isEnabled ? 1.0 : 0.45
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        pill.layer.borderColor = Palette.borderSoft.resolvedColor(with: traitCollection).cgColor
    }
}
