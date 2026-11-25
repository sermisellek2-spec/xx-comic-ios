import UIKit

@MainActor
final class SettingsMenuCell: UITableViewCell {
    static let reuseIdentifier = "SettingsMenuCell"

    let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let valueLabel = UILabel()
    private let glyph = UIImageView()
    private let iconHost = UIView()
    private let card = UIView()
    private let separator = UIView()
    private var minHeightConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    convenience init(icon: ParityIcon, title: String, subtitle: String = "", value: String = "", identifier: String, isDanger: Bool = false) {
        self.init(style: .default, reuseIdentifier: nil)
        configure(icon: icon, title: title, subtitle: subtitle, value: value, identifier: identifier, isDanger: isDanger)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setupViews() {
        backgroundColor = .clear
        selectionStyle = .none

        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 8
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        separator.backgroundColor = Palette.borderSoft
        separator.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(separator)

        iconHost.backgroundColor = Palette.accentSoft
        iconHost.layer.cornerRadius = 8
        iconHost.addSubview(glyph)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.contentMode = .scaleAspectFit

        titleLabel.textColor = Palette.text
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 14, weight: .medium))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        subtitleLabel.textColor = Palette.text3
        subtitleLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 11))
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 2

        let copy = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        copy.axis = .vertical
        copy.spacing = 1

        valueLabel.textColor = Palette.text3
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textAlignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)

        let arrow = UIImageView(image: ParityIcon.chevronRight.image(size: 14))
        arrow.tintColor = Palette.text3
        arrow.contentMode = .scaleAspectFit

        let end = UIStackView(arrangedSubviews: [valueLabel, arrow])
        end.spacing = 4
        end.alignment = .center
        end.setContentHuggingPriority(UILayoutPriority(751), for: .horizontal)
        end.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
        copy.setContentHuggingPriority(UILayoutPriority(249), for: .horizontal)

        let row = UIStackView(arrangedSubviews: [iconHost, copy, end])
        row.spacing = 9
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        minHeightConstraint = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 46)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 9),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -9),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            minHeightConstraint,
            iconHost.widthAnchor.constraint(equalToConstant: 28),
            iconHost.heightAnchor.constraint(equalToConstant: 28),
            glyph.centerXAnchor.constraint(equalTo: iconHost.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: iconHost.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 18),
            glyph.heightAnchor.constraint(equalToConstant: 18),
            valueLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 88),
            arrow.widthAnchor.constraint(equalToConstant: 14),
            arrow.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    func configure(icon: ParityIcon, title: String, subtitle: String = "", value: String = "", identifier: String, isDanger: Bool = false) {
        accessibilityIdentifier = identifier
        valueLabel.accessibilityIdentifier = identifier + ".value"
        valueLabel.accessibilityValue = nil

        glyph.image = icon.image(size: 18)
        glyph.tintColor = isDanger ? Palette.danger : Palette.accent
        iconHost.backgroundColor = isDanger ? Palette.danger.withAlphaComponent(0.12) : Palette.accentSoft

        titleLabel.text = title
        titleLabel.textColor = isDanger ? Palette.danger : Palette.text

        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty

        valueLabel.text = value
        valueLabel.isHidden = value.isEmpty

        minHeightConstraint.constant = subtitle.isEmpty ? 46 : 56
    }

    func setGroupPosition(first: Bool, last: Bool) {
        var corners: CACornerMask = []
        if first { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if last { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        card.layer.maskedCorners = corners
        separator.isHidden = last
    }

    #if DEBUG
    func setCacheTestMeasurement(memory: Int64, disk: Int64) {
        valueLabel.accessibilityValue = "memory=\(memory); disk=\(disk)"
    }
    #endif

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        card.backgroundColor = highlighted ? Palette.accentSoft : Palette.card
    }
}
