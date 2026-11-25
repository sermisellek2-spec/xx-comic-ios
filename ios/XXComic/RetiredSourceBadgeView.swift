import UIKit

/// Shared UI components indicating that a comic's bound source has been retired.
@MainActor
enum RetiredSourceBadgeView {
    static let badgeText = "站源已下线"
    static let switchActionText = "立即换源"
    private static let defaultBannerMessage = "当前站源已下线，请切换其他站源继续阅读"

    private static let coverPillBackground = UIColor(red: 168.0 / 255.0, green: 72.0 / 255.0, blue: 16.0 / 255.0, alpha: 228.0 / 255.0)
    private static let inlineBackground = dynamicColor(
        day: (255, 241, 224),
        night: (71, 43, 23)
    )
    private static let inlineBorder = dynamicColor(
        day: (240, 205, 168),
        night: (112, 69, 36)
    )
    private static let inlineForeground = dynamicColor(
        day: (154, 62, 8),
        night: (255, 200, 138)
    )

    static func createCoverPill() -> UIView {
        let container = UIView()
        container.backgroundColor = coverPillBackground
        container.layer.cornerRadius = 6
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        container.isAccessibilityElement = true
        container.accessibilityLabel = badgeText

        let label = UILabel()
        label.text = badgeText
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6)
        ])
        return container
    }

    static func createInlinePill() -> UIView {
        let container = BorderedView()
        container.backgroundColor = inlineBackground
        container.borderColorProvider = { inlineBorder }
        container.layer.cornerRadius = 6
        container.layer.borderWidth = 1
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        container.isAccessibilityElement = true
        container.accessibilityLabel = badgeText

        let label = UILabel()
        label.text = badgeText
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = Palette.readable(foreground: inlineForeground, background: inlineBackground, fallback: Palette.text)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6)
        ])
        return container
    }

    static func createDetailBanner(message: String? = nil, onSwitchSource: (() -> Void)?) -> UIView {
        let banner = BorderedView()
        banner.backgroundColor = Palette.cardSoft
        banner.borderColorProvider = { Palette.border }
        banner.layer.cornerRadius = 8
        banner.layer.borderWidth = 1
        banner.accessibilityIdentifier = "detail.retired.banner"

        let icon = UIImageView(image: ParityIcon.cloudOff.image(size: 16))
        icon.tintColor = Palette.readable(foreground: inlineForeground, background: Palette.cardSoft, fallback: Palette.text2)
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false
        icon.translatesAutoresizingMaskIntoConstraints = false

        let trimmedMsg = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let messageLabel = UILabel()
        messageLabel.text = trimmedMsg.isEmpty ? defaultBannerMessage : trimmedMsg
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = Palette.text2
        messageLabel.numberOfLines = 2
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let actionButton = UIButton(type: .system)
        actionButton.setTitle(switchActionText, for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        let actionFg = Palette.readable(foreground: Palette.accentText, background: Palette.accentSoft, fallback: Palette.text)
        actionButton.setTitleColor(actionFg, for: .normal)
        actionButton.backgroundColor = Palette.accentSoft
        actionButton.layer.cornerRadius = 16
        actionButton.layer.borderWidth = 1
        actionButton.layer.borderColor = Palette.border.cgColor
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        actionButton.accessibilityIdentifier = "detail.retired.switchSource"
        actionButton.accessibilityLabel = switchActionText
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        if let onSwitchSource {
            actionButton.addAction(UIAction { _ in onSwitchSource() }, for: .touchUpInside)
        } else {
            actionButton.isEnabled = false
            actionButton.alpha = 0.6
        }

        let row = UIStackView(arrangedSubviews: [icon, messageLabel, actionButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(row)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            row.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: banner.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -10)
        ])
        return banner
    }

    private static func dynamicColor(day: (CGFloat, CGFloat, CGFloat), night: (CGFloat, CGFloat, CGFloat)) -> UIColor {
        UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? night : day
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        }
    }
}

@MainActor
private final class BorderedView: UIView {
    var borderColorProvider: (() -> UIColor)? {
        didSet {
            layer.borderColor = borderColorProvider?().resolvedColor(with: traitCollection).cgColor
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if let provider = borderColorProvider {
            layer.borderColor = provider().resolvedColor(with: traitCollection).cgColor
        }
    }
}
