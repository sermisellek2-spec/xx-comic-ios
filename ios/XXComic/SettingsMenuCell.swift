import UIKit

@MainActor
final class SettingsMenuCell: UITableViewCell {
    let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let valueLabel = UILabel()
    private let glyph = UIImageView()
    private let card = UIView()
    private let separator = UIView()

    init(icon: ParityIcon, title: String, subtitle: String = "", value: String = "", identifier: String) {
        super.init(style: .default, reuseIdentifier: nil)
        backgroundColor = .clear
        selectionStyle = .none
        accessibilityIdentifier = identifier
        valueLabel.accessibilityIdentifier = identifier + ".value"
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 8
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        separator.backgroundColor = Palette.borderSoft
        separator.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(separator)
        let iconHost = UIView()
        iconHost.backgroundColor = Palette.accentSoft
        iconHost.layer.cornerRadius = 8
        iconHost.addSubview(glyph)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.image = icon.image(size: 18); glyph.tintColor = Palette.accent
        glyph.contentMode = .scaleAspectFit
        titleLabel.text = title; titleLabel.textColor = Palette.text
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 14, weight: .medium))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        subtitleLabel.text = subtitle; subtitleLabel.textColor = Palette.text3
        subtitleLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 11))
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isHidden = subtitle.isEmpty
        let copy = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        copy.axis = .vertical; copy.spacing = 1
        valueLabel.text = value; valueLabel.textColor = Palette.text3
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textAlignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.isHidden = value.isEmpty
        valueLabel.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
        let arrow = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)))
        arrow.tintColor = Palette.text3; arrow.contentMode = .scaleAspectFit
        let end = UIStackView(arrangedSubviews: [valueLabel, arrow]); end.spacing = 4; end.alignment = .center
        end.setContentHuggingPriority(UILayoutPriority(751), for: .horizontal)
        end.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
        copy.setContentHuggingPriority(UILayoutPriority(249), for: .horizontal)
        let row = UIStackView(arrangedSubviews: [iconHost, copy, end]); row.spacing = 9; row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(row)
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
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle.isEmpty ? 46 : 56),
            iconHost.widthAnchor.constraint(equalToConstant: 28), iconHost.heightAnchor.constraint(equalToConstant: 28),
            glyph.centerXAnchor.constraint(equalTo: iconHost.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: iconHost.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 18), glyph.heightAnchor.constraint(equalToConstant: 18),
            valueLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 82),
            arrow.widthAnchor.constraint(equalToConstant: 16), arrow.heightAnchor.constraint(equalToConstant: 16)
        ])
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
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
}
