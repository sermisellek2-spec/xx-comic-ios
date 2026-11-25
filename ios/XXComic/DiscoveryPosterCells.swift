import UIKit
import ComicCore

// MARK: - Responsive Layout Metrics

enum DiscoveryLayoutMetrics {
    static let horizontalPadding: CGFloat = 12
    static let interItemSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 14
    static let minCardWidth: CGFloat = 110

    static func columns(forWidth width: CGFloat) -> Int {
        let usable = max(200, width - horizontalPadding * 2)
        return max(3, Int((usable + interItemSpacing) / (minCardWidth + interItemSpacing)))
    }

    static func cardWidth(forWidth width: CGFloat) -> CGFloat {
        let cols = CGFloat(columns(forWidth: width))
        let usable = max(200, width - horizontalPadding * 2)
        return floor((usable - interItemSpacing * (cols - 1)) / cols)
    }

    static func posterCardHeight(forCardWidth cardWidth: CGFloat, showSourceBadge: Bool) -> CGFloat {
        let coverHeight = ceil(cardWidth * 4.0 / 3.0)
        // cover + 6pt gap + 2-line title (~34pt) + optional 20pt source pill + 4pt bottom slack
        return coverHeight + 6 + 34 + (showSourceBadge ? 22 : 0) + 4
    }
}

// MARK: - DiscoveryPosterCell

@MainActor
final class DiscoveryPosterCell: UICollectionViewCell {
    static let reuseId = "DiscoveryPosterCell"

    private let coverContainer = UIView()
    private let coverView = RemoteImageView()
    private let scrimView = UIView()
    private let scrimGradient = CAGradientLayer()
    private let remarkPill = UIView()
    private let remarkLabel = UILabel()
    private let titleLabel = UILabel()
    private let sourcePill = UIView()
    private let sourceLabel = UILabel()
    private var sourceHeightConstraint: NSLayoutConstraint!
    private var sourceTopConstraint: NSLayoutConstraint!
    private var onLongPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        contentView.backgroundColor = .clear

        coverContainer.backgroundColor = Palette.placeholder
        coverContainer.layer.cornerRadius = 8
        coverContainer.layer.borderWidth = 0.5
        coverContainer.layer.borderColor = Palette.borderSoft.cgColor
        coverContainer.layer.masksToBounds = true
        coverContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverContainer)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(coverView)

        scrimView.isUserInteractionEnabled = false
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        scrimGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.68).cgColor
        ]
        scrimGradient.locations = [0.0, 1.0]
        scrimView.layer.addSublayer(scrimGradient)
        coverContainer.addSubview(scrimView)

        remarkPill.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        remarkPill.layer.cornerRadius = 4
        remarkPill.layer.masksToBounds = true
        remarkPill.isUserInteractionEnabled = false
        remarkPill.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(remarkPill)

        remarkLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        remarkLabel.textColor = .white
        remarkLabel.lineBreakMode = .byTruncatingTail
        remarkLabel.numberOfLines = 1
        remarkLabel.translatesAutoresizingMaskIntoConstraints = false
        remarkPill.addSubview(remarkLabel)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        sourcePill.backgroundColor = Palette.accentSoft
        sourcePill.layer.cornerRadius = 4
        sourcePill.layer.masksToBounds = true
        sourcePill.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sourcePill)

        sourceLabel.font = .systemFont(ofSize: 10, weight: .medium)
        sourceLabel.textColor = Palette.accentText
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.numberOfLines = 1
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourcePill.addSubview(sourceLabel)

        sourceTopConstraint = sourcePill.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        sourceHeightConstraint = sourcePill.heightAnchor.constraint(equalToConstant: 18)

        NSLayoutConstraint.activate([
            coverContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            coverContainer.heightAnchor.constraint(equalTo: coverContainer.widthAnchor, multiplier: 4.0 / 3.0),

            coverView.topAnchor.constraint(equalTo: coverContainer.topAnchor),
            coverView.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor),
            coverView.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),

            scrimView.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),
            scrimView.heightAnchor.constraint(equalToConstant: 40),

            remarkPill.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor, constant: -5),
            remarkPill.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: -5),
            remarkPill.leadingAnchor.constraint(greaterThanOrEqualTo: coverContainer.leadingAnchor, constant: 5),

            remarkLabel.topAnchor.constraint(equalTo: remarkPill.topAnchor, constant: 2),
            remarkLabel.bottomAnchor.constraint(equalTo: remarkPill.bottomAnchor, constant: -2),
            remarkLabel.leadingAnchor.constraint(equalTo: remarkPill.leadingAnchor, constant: 5),
            remarkLabel.trailingAnchor.constraint(equalTo: remarkPill.trailingAnchor, constant: -5),

            titleLabel.topAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            sourceTopConstraint,
            sourcePill.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sourcePill.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            sourceHeightConstraint,

            sourceLabel.centerYAnchor.constraint(equalTo: sourcePill.centerYAnchor),
            sourceLabel.leadingAnchor.constraint(equalTo: sourcePill.leadingAnchor, constant: 5),
            sourceLabel.trailingAnchor.constraint(equalTo: sourcePill.trailingAnchor, constant: -5)
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        contentView.addGestureRecognizer(longPress)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrimGradient.frame = scrimView.bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        coverContainer.layer.borderColor = Palette.borderSoft.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.cancel()
        onLongPress = nil
        remarkPill.isHidden = true
        scrimView.isHidden = true
        sourcePill.isHidden = true
    }

    func configure(
        comic: ComicSummary,
        remark: String,
        sourceName: String?,
        referer: String,
        library: LocalLibrary,
        onLongPress: (() -> Void)?
    ) {
        self.onLongPress = onLongPress
        titleLabel.text = comic.title

        let compact = DiscoveryModels.compactRemark(comic)
        if compact.isEmpty {
            remarkPill.isHidden = true
            scrimView.isHidden = true
            remarkLabel.text = nil
        } else {
            remarkLabel.text = compact
            remarkPill.isHidden = false
            scrimView.isHidden = false
        }

        let trimmedSource = (sourceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSource.isEmpty {
            sourcePill.isHidden = true
            sourceLabel.text = nil
            sourceTopConstraint.constant = 0
            sourceHeightConstraint.constant = 0
        } else {
            sourceLabel.text = trimmedSource
            sourcePill.isHidden = false
            sourceTopConstraint.constant = 4
            sourceHeightConstraint.constant = 18
        }

        coverView.loadCover(comic, referer: referer, library: library)
        accessibilityIdentifier = comic.title
        accessibilityLabel = comic.title
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress?()
    }
}

// MARK: - DiscoverySectionHeaderCell

@MainActor
final class DiscoverySectionHeaderCell: UICollectionViewCell {
    static let reuseId = "DiscoverySectionHeaderCell"

    private let accentBar = UIView()
    private let titleLabel = UILabel()
    private let vpnBadge = SourceVpnBadgeView()
    private let exactDot = UIView()
    private let countPill = UIView()
    private let countLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        contentView.backgroundColor = .clear

        accentBar.backgroundColor = Palette.accent
        accentBar.layer.cornerRadius = 1.5
        accentBar.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        vpnBadge.translatesAutoresizingMaskIntoConstraints = false

        exactDot.backgroundColor = Palette.danger
        exactDot.layer.cornerRadius = 3
        exactDot.translatesAutoresizingMaskIntoConstraints = false

        countPill.backgroundColor = Palette.accentSoft
        countPill.layer.cornerRadius = 9
        countPill.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        countLabel.textColor = Palette.accentText
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countPill.addSubview(countLabel)

        actionButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        actionButton.setTitleColor(Palette.accentText, for: .normal)
        actionButton.backgroundColor = Palette.accentSoft
        actionButton.layer.cornerRadius = 12
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)

        let leftStack = UIStackView(arrangedSubviews: [accentBar, titleLabel, vpnBadge, exactDot, countPill])
        leftStack.axis = .horizontal
        leftStack.alignment = .center
        leftStack.spacing = 6
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(leftStack)
        contentView.addSubview(actionButton)

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            accentBar.widthAnchor.constraint(equalToConstant: 3),
            accentBar.heightAnchor.constraint(equalToConstant: 14),
            exactDot.widthAnchor.constraint(equalToConstant: 6),
            exactDot.heightAnchor.constraint(equalToConstant: 6),

            countLabel.topAnchor.constraint(equalTo: countPill.topAnchor, constant: 2),
            countLabel.bottomAnchor.constraint(equalTo: countPill.bottomAnchor, constant: -2),
            countLabel.leadingAnchor.constraint(equalTo: countPill.leadingAnchor, constant: 7),
            countLabel.trailingAnchor.constraint(equalTo: countPill.trailingAnchor, constant: -7),

            leftStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            leftStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),

            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 26)
        ])
    }

    func configure(row: DiscoverySectionHeaderRow, overrideActionLabel: String? = nil, onAction: (() -> Void)?) {
        self.onAction = onAction
        titleLabel.text = row.title
        vpnBadge.isHidden = !row.requiresVpn
        exactDot.isHidden = !row.hasExactMatch

        if row.countBadge.isEmpty {
            countPill.isHidden = true
            countLabel.text = nil
        } else {
            countLabel.text = row.countBadge
            countPill.isHidden = false
        }

        let resolvedAction = overrideActionLabel ?? row.actionLabel
        if resolvedAction.isEmpty || onAction == nil {
            actionButton.isHidden = true
            actionButton.setTitle(nil, for: .normal)
            actionButton.accessibilityIdentifier = nil
        } else {
            actionButton.isHidden = false
            actionButton.setTitle(resolvedAction, for: .normal)
            actionButton.accessibilityIdentifier = row.sourceId.isEmpty ? nil : "discover.global.section.\(row.sourceId)"
            actionButton.accessibilityLabel = resolvedAction
        }
    }

    @objc private func handleAction() {
        onAction?()
    }
}

// MARK: - DiscoveryFooterCell

@MainActor
final class DiscoveryFooterCell: UICollectionViewCell {
    static let reuseId = "DiscoveryFooterCell"

    private let stack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let button = UIButton(type: .system)
    private var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        spinner.color = Palette.accent
        spinner.hidesWhenStopped = true

        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.setTitleColor(Palette.secondaryText, for: .normal)
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(button)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    func configure(state: DiscoveryFooterState, onTap: (() -> Void)?) {
        self.onTap = onTap
        switch state {
        case .none:
            spinner.stopAnimating()
            button.setTitle(nil, for: .normal)
            button.isEnabled = false
        case .loading:
            spinner.startAnimating()
            button.setTitle("正在加载更多...", for: .normal)
            button.setTitleColor(Palette.secondaryText, for: .normal)
            button.isEnabled = false
        case .loadMore:
            spinner.stopAnimating()
            button.setTitle("加载更多", for: .normal)
            button.setTitleColor(Palette.accentText, for: .normal)
            button.isEnabled = true
        case .end:
            spinner.stopAnimating()
            button.setTitle("— 已经到底了 —", for: .normal)
            button.setTitleColor(Palette.text3, for: .normal)
            button.isEnabled = false
        case .errorRetry:
            spinner.stopAnimating()
            button.setTitle("加载失败，点击重试", for: .normal)
            button.setTitleColor(Palette.danger, for: .normal)
            button.isEnabled = true
            button.accessibilityIdentifier = "discover.footer.retry"
        case .verifyRequired:
            spinner.stopAnimating()
            button.setTitle("该站源需要验证，点击前往", for: .normal)
            button.setTitleColor(Palette.accentText, for: .normal)
            button.isEnabled = true
            button.accessibilityIdentifier = "discover.footer.verify"
        }
    }

    @objc private func handleTap() {
        onTap?()
    }
}

// MARK: - DiscoveryStateCell

@MainActor
final class DiscoveryStateCell: UICollectionViewCell {
    static let reuseId = "DiscoveryStateCell"

    enum Mode {
        case skeleton(columns: Int)
        case empty(title: String, subtitle: String?, buttonTitle: String?, statusAccessibilityLabel: String?, assetName: String?, onAction: (() -> Void)?)
        case error(message: String, retryTitle: String, onRetry: () -> Void)
        case noSources(onManageSources: () -> Void)
        case searchHistory(terms: [String], onTapTerm: (String) -> Void, onClear: () -> Void)
    }

    private let rootStack = UIStackView()
    private var onPrimaryAction: (() -> Void)?
    private var onClearHistory: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    func configure(mode: Mode, availableWidth: CGFloat) {
        rootStack.arrangedSubviews.forEach {
            rootStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        onPrimaryAction = nil
        onClearHistory = nil

        switch mode {
        case .skeleton(let columns):
            buildSkeleton(columns: max(3, columns), width: availableWidth)
        case .empty(let title, let subtitle, let buttonTitle, let statusLabel, let assetName, let onAction):
            buildEmptyCard(
                title: title,
                subtitle: subtitle,
                buttonTitle: buttonTitle,
                statusAccessibilityLabel: statusLabel,
                assetName: assetName,
                onAction: onAction
            )
        case .error(let message, let retryTitle, let onRetry):
            buildEmptyCard(
                title: message,
                subtitle: "请检查网络或切换其他站源重试",
                buttonTitle: retryTitle,
                statusAccessibilityLabel: message,
                assetName: nil,
                onAction: onRetry
            )
        case .noSources(let onManageSources):
            buildEmptyCard(
                title: "当前没有已启用的发现站源",
                subtitle: "前往站源管理启用站源或调整分组",
                buttonTitle: "管理站源",
                statusAccessibilityLabel: "管理站源",
                assetName: "rem_empty_discovery",
                onAction: onManageSources
            )
        case .searchHistory(let terms, let onTapTerm, let onClear):
            buildSearchHistory(terms: terms, maxWidth: availableWidth, onTapTerm: onTapTerm, onClear: onClear)
        }
    }

    private func buildSkeleton(columns: Int, width: CGFloat) {
        let spacing: CGFloat = DiscoveryLayoutMetrics.interItemSpacing
        let cardW = floor((max(200, width) - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let coverH = ceil(cardW * 4.0 / 3.0)

        for _ in 0..<2 {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = spacing
            for _ in 0..<columns {
                let col = UIStackView()
                col.axis = .vertical
                col.spacing = 6

                let box = UIView()
                box.backgroundColor = Palette.placeholder
                box.layer.cornerRadius = 8
                box.heightAnchor.constraint(equalToConstant: coverH).isActive = true

                let line1 = UIView()
                line1.backgroundColor = Palette.surface
                line1.layer.cornerRadius = 4
                line1.heightAnchor.constraint(equalToConstant: 12).isActive = true

                let line2 = UIView()
                line2.backgroundColor = Palette.surface
                line2.layer.cornerRadius = 4
                line2.heightAnchor.constraint(equalToConstant: 10).isActive = true

                col.addArrangedSubview(box)
                col.addArrangedSubview(line1)
                col.addArrangedSubview(line2)
                row.addArrangedSubview(col)
            }
            rootStack.addArrangedSubview(row)
        }
    }

    private func buildEmptyCard(
        title: String,
        subtitle: String?,
        buttonTitle: String?,
        statusAccessibilityLabel: String?,
        assetName: String?,
        onAction: (() -> Void)?
    ) {
        self.onPrimaryAction = onAction

        let card = UIView()
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 0.5
        card.layer.borderColor = Palette.borderSoft.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let inner = UIStackView()
        inner.axis = .vertical
        inner.alignment = .center
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)

        if let assetName, !assetName.isEmpty {
            let illustration = UIImageView()
            illustration.contentMode = .scaleAspectFit
            illustration.translatesAutoresizingMaskIntoConstraints = false
            illustration.widthAnchor.constraint(equalToConstant: 104).isActive = true
            illustration.heightAnchor.constraint(equalToConstant: 104).isActive = true
            AppIllustrationCache.bind(illustration, assetName: assetName, maxSideDp: 104)
            inner.addArrangedSubview(illustration)
        }

        // Preserve UIButton accessibility compatibility for existing parity UI tests
        let titleButton = UIButton(type: .system)
        titleButton.setTitle(title, for: .normal)
        titleButton.setTitleColor(Palette.text, for: .normal)
        titleButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        titleButton.titleLabel?.numberOfLines = 0
        titleButton.titleLabel?.textAlignment = .center
        titleButton.accessibilityLabel = statusAccessibilityLabel ?? title
        titleButton.accessibilityIdentifier = "discover.state.title"
        if onAction != nil && (buttonTitle == nil || buttonTitle?.isEmpty == true) {
            titleButton.addTarget(self, action: #selector(handlePrimaryAction), for: .touchUpInside)
        } else {
            titleButton.isUserInteractionEnabled = false
        }
        inner.addArrangedSubview(titleButton)

        if let subtitle, !subtitle.isEmpty {
            let sub = UILabel()
            sub.text = subtitle
            sub.font = .systemFont(ofSize: 13)
            sub.textColor = Palette.secondaryText
            sub.numberOfLines = 0
            sub.textAlignment = .center
            inner.addArrangedSubview(sub)
        }

        if let buttonTitle, !buttonTitle.isEmpty, onAction != nil {
            let actionBtn = UIButton(type: .system)
            actionBtn.setTitle(buttonTitle, for: .normal)
            actionBtn.setTitleColor(Palette.onAccent, for: .normal)
            actionBtn.backgroundColor = Palette.accent
            actionBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            actionBtn.layer.cornerRadius = 18
            actionBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
            actionBtn.accessibilityIdentifier = "discover.state.action"
            actionBtn.addTarget(self, action: #selector(handlePrimaryAction), for: .touchUpInside)
            inner.addArrangedSubview(actionBtn)
        }

        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22)
        ])

        rootStack.addArrangedSubview(card)
    }

    private func buildSearchHistory(
        terms: [String],
        maxWidth: CGFloat,
        onTapTerm: @escaping (String) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.onClearHistory = onClear

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center

        let title = UILabel()
        title.text = "搜索历史"
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = Palette.text

        let clear = UIButton(type: .system)
        clear.setTitle("清空", for: .normal)
        clear.setTitleColor(Palette.secondaryText, for: .normal)
        clear.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        clear.accessibilityIdentifier = "discover.history.clear"
        clear.addTarget(self, action: #selector(handleClearHistory), for: .touchUpInside)

        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(clear)
        rootStack.addArrangedSubview(header)

        let flow = DiscoveryChipFlowContainer(maxWidth: max(220, maxWidth))
        for term in terms {
            let chip = UIButton(type: .system)
            chip.setTitle(term, for: .normal)
            chip.setTitleColor(Palette.text, for: .normal)
            chip.backgroundColor = Palette.surface
            chip.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            chip.layer.cornerRadius = 15
            chip.layer.borderWidth = 0.5
            chip.layer.borderColor = Palette.borderSoft.cgColor
            chip.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            chip.addAction(UIAction { _ in onTapTerm(term) }, for: .touchUpInside)
            flow.addChip(chip)
        }
        rootStack.addArrangedSubview(flow)
    }

    @objc private func handlePrimaryAction() {
        onPrimaryAction?()
    }

    @objc private func handleClearHistory() {
        onClearHistory?()
    }
}

// MARK: - DiscoveryStateOverlayView

@MainActor
final class DiscoveryStateOverlayView: UIView {
    private let cardView = UIView()
    private let stack = UIStackView()
    private var onPrimaryAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        cardView.backgroundColor = Palette.card
        cardView.layer.cornerRadius = 14
        cardView.layer.borderWidth = 0.5
        cardView.layer.borderColor = Palette.borderSoft.cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        let cardWidth = cardView.widthAnchor.constraint(equalTo: widthAnchor, constant: -24)
        cardWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            cardWidth,

            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -22)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        cardView.layer.borderColor = Palette.borderSoft.resolvedColor(with: traitCollection).cgColor
    }

    func configure(
        title: String,
        subtitle: String?,
        buttonTitle: String?,
        statusAccessibilityLabel: String?,
        assetName: String?,
        onAction: (() -> Void)?
    ) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        onPrimaryAction = onAction

        if let assetName, !assetName.isEmpty {
            let illustration = UIImageView()
            illustration.contentMode = .scaleAspectFit
            illustration.translatesAutoresizingMaskIntoConstraints = false
            illustration.widthAnchor.constraint(equalToConstant: 104).isActive = true
            illustration.heightAnchor.constraint(equalToConstant: 104).isActive = true
            AppIllustrationCache.bind(illustration, assetName: assetName, maxSideDp: 104)
            stack.addArrangedSubview(illustration)
        }

        let titleButton = UIButton(type: .system)
        titleButton.setTitle(title, for: .normal)
        titleButton.setTitleColor(Palette.text, for: .normal)
        titleButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        titleButton.titleLabel?.numberOfLines = 0
        titleButton.titleLabel?.textAlignment = .center
        titleButton.accessibilityLabel = statusAccessibilityLabel ?? title
        titleButton.accessibilityIdentifier = "discover.state.title"
        if onAction != nil && (buttonTitle == nil || buttonTitle?.isEmpty == true) {
            titleButton.addTarget(self, action: #selector(handlePrimaryAction), for: .touchUpInside)
        } else {
            titleButton.isUserInteractionEnabled = false
        }
        stack.addArrangedSubview(titleButton)

        if let subtitle, !subtitle.isEmpty {
            let sub = UILabel()
            sub.text = subtitle
            sub.font = .systemFont(ofSize: 13)
            sub.textColor = Palette.secondaryText
            sub.numberOfLines = 0
            sub.textAlignment = .center
            stack.addArrangedSubview(sub)
        }

        if let buttonTitle, !buttonTitle.isEmpty, onAction != nil {
            let actionBtn = UIButton(type: .system)
            actionBtn.setTitle(buttonTitle, for: .normal)
            actionBtn.setTitleColor(Palette.onAccent, for: .normal)
            actionBtn.backgroundColor = Palette.accent
            actionBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            actionBtn.layer.cornerRadius = 18
            actionBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
            actionBtn.accessibilityIdentifier = "discover.state.action"
            actionBtn.addTarget(self, action: #selector(handlePrimaryAction), for: .touchUpInside)
            stack.addArrangedSubview(actionBtn)
        }
    }

    @objc private func handlePrimaryAction() {
        onPrimaryAction?()
    }
}

// MARK: - DiscoveryChipFlowContainer

@MainActor
final class DiscoveryChipFlowContainer: UIView {
    private var chips: [UIView] = []
    private var lastLayoutWidth: CGFloat

    init(maxWidth: CGFloat) {
        self.lastLayoutWidth = maxWidth
        super.init(frame: CGRect(x: 0, y: 0, width: maxWidth, height: 10))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    func addChip(_ chip: UIView) {
        chips.append(chip)
        addSubview(chip)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func clearChips() {
        chips.forEach { $0.removeFromSuperview() }
        chips.removeAll()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : lastLayoutWidth
        let height = layoutChips(forWidth: width, applyFrames: false)
        return CGSize(width: UIView.noIntrinsicMetric, height: max(1, height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        if abs(bounds.width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        _ = layoutChips(forWidth: bounds.width, applyFrames: true)
    }

    @discardableResult
    private func layoutChips(forWidth width: CGFloat, applyFrames: Bool) -> CGFloat {
        let hSpacing: CGFloat = 8
        let vSpacing: CGFloat = 8
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for chip in chips {
            let size = chip.sizeThatFits(CGSize(width: width, height: 44))
            let chipW = min(width, max(44, ceil(size.width)))
            let chipH = max(30, ceil(size.height))
            if x > 0 && x + chipW > width {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            if applyFrames {
                chip.frame = CGRect(x: x, y: y, width: chipW, height: chipH)
            }
            x += chipW + hSpacing
            rowHeight = max(rowHeight, chipH)
        }
        return chips.isEmpty ? 0 : y + rowHeight
    }
}
