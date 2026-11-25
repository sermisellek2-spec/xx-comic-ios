import UIKit
import ComicCore

// MARK: - Section Header Helper View

@MainActor
final class RecommendSectionHeaderView: UIView {
    private let accentBar = UIView()
    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let actionLabel = UILabel()
    private let actionIcon = UIImageView()
    private var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        accentBar.backgroundColor = Palette.accent
        accentBar.layer.cornerRadius = 1.5
        accentBar.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        actionButton.backgroundColor = Palette.accentSoft
        actionButton.layer.cornerRadius = 13
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        actionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        actionLabel.textColor = Palette.accentText
        actionLabel.isUserInteractionEnabled = false

        actionIcon.tintColor = Palette.accentText
        actionIcon.contentMode = .scaleAspectFit
        actionIcon.isUserInteractionEnabled = false
        actionIcon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        actionIcon.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let btnStack = UIStackView(arrangedSubviews: [actionIcon, actionLabel])
        btnStack.axis = .horizontal
        btnStack.alignment = .center
        btnStack.spacing = 4
        btnStack.isUserInteractionEnabled = false
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(btnStack)

        NSLayoutConstraint.activate([
            btnStack.topAnchor.constraint(equalTo: actionButton.topAnchor, constant: 5),
            btnStack.bottomAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: -5),
            btnStack.leadingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: 10),
            btnStack.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor, constant: -10)
        ])

        addSubview(accentBar)
        addSubview(titleLabel)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentBar.centerYAnchor.constraint(equalTo: centerYAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
            accentBar.heightAnchor.constraint(equalToConstant: 13),

            titleLabel.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),

            heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    func configure(
        title: String,
        actionTitle: String?,
        icon: ParityIcon? = nil,
        iconTrailing: Bool = false,
        actionId: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.onAction = onAction
        titleLabel.text = title
        if let actionTitle, !actionTitle.isEmpty, onAction != nil {
            actionLabel.text = actionTitle
            if let icon {
                actionIcon.image = icon.image(size: 12)
                actionIcon.isHidden = false
            } else {
                actionIcon.isHidden = true
            }
            if let stack = actionButton.subviews.first as? UIStackView {
                stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0) }
                if iconTrailing {
                    stack.addArrangedSubview(actionLabel)
                    stack.addArrangedSubview(actionIcon)
                } else {
                    stack.addArrangedSubview(actionIcon)
                    stack.addArrangedSubview(actionLabel)
                }
            }
            actionButton.isHidden = false
            actionButton.accessibilityIdentifier = actionId
            actionButton.accessibilityLabel = actionTitle
        } else {
            actionButton.isHidden = true
            actionButton.accessibilityIdentifier = nil
        }
    }

    @objc private func handleTap() {
        onAction?()
    }
}

// MARK: - Spotlight Banner Cell

@MainActor
final class RecommendSpotlightCell: UICollectionViewCell {
    static let reuseId = "RecommendSpotlightCell"

    private let headerView = RecommendSectionHeaderView()
    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var carousel = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
    private let pageControl = UIPageControl()

    private var items: [RecommendItem] = []
    private var refererProvider: ((RecommendItem) -> String)?
    private var library: LocalLibrary?
    private var onSelect: ((RecommendItem) -> Void)?
    private var onLongPress: ((RecommendItem) -> Void)?
    private var onImpressions: (([RecommendItem]) -> Void)?
    private var lastCardWidth: CGFloat = 296

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumLineSpacing = 10
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 16)

        carousel.backgroundColor = .clear
        carousel.showsHorizontalScrollIndicator = false
        carousel.decelerationRate = .fast
        carousel.dataSource = self
        carousel.delegate = self
        carousel.register(RecommendSpotlightCardCell.self, forCellWithReuseIdentifier: RecommendSpotlightCardCell.reuseId)
        carousel.translatesAutoresizingMaskIntoConstraints = false
        carousel.accessibilityIdentifier = "recommend.spotlight.carousel"
        contentView.addSubview(carousel)

        pageControl.currentPageIndicatorTintColor = Palette.accent
        pageControl.pageIndicatorTintColor = Palette.border
        pageControl.isUserInteractionEnabled = false
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageControl)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            carousel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            carousel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            carousel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            carousel.heightAnchor.constraint(equalToConstant: 124),

            pageControl.topAnchor.constraint(equalTo: carousel.bottomAnchor, constant: 4),
            pageControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pageControl.heightAnchor.constraint(equalToConstant: 16),
            pageControl.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    static func requiredHeight() -> CGFloat {
        // 30 header + 8 gap + 124 carousel + 4 gap + 16 dots = 182
        return 182
    }

    func configure(
        items: [RecommendItem],
        availableWidth: CGFloat,
        refererProvider: @escaping (RecommendItem) -> String,
        library: LocalLibrary,
        onRefresh: @escaping () -> Void,
        onSelect: @escaping (RecommendItem) -> Void,
        onLongPress: @escaping (RecommendItem) -> Void,
        onImpressions: (([RecommendItem]) -> Void)?
    ) {
        self.items = items
        self.refererProvider = refererProvider
        self.library = library
        self.onSelect = onSelect
        self.onLongPress = onLongPress
        self.onImpressions = onImpressions

        lastCardWidth = max(240, min(324, availableWidth - 36))
        flowLayout.itemSize = CGSize(width: lastCardWidth, height: 124)

        headerView.configure(
            title: "今日为你挑选",
            actionTitle: "换一批",
            icon: .refresh,
            actionId: "recommend.spotlight.refresh",
            onAction: onRefresh
        )
        pageControl.numberOfPages = items.count
        pageControl.currentPage = 0
        pageControl.isHidden = items.count <= 1
        carousel.reloadData()
        if !items.isEmpty {
            carousel.setContentOffset(.zero, animated: false)
            onImpressions?(Array(items.prefix(1)))
        }
    }
}

extension RecommendSpotlightCell: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: RecommendSpotlightCardCell.reuseId,
            for: indexPath
        ) as? RecommendSpotlightCardCell,
              let library,
              let refererProvider else {
            return UICollectionViewCell()
        }
        let item = items[indexPath.item]
        cell.configure(item: item, referer: refererProvider(item), library: library) { [weak self] in
            self?.onLongPress?(item)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        onSelect?(item)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let stride = lastCardWidth + 10
        guard stride > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / stride))
        pageControl.currentPage = max(0, min(max(0, items.count - 1), page))
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let idx = pageControl.currentPage
        if idx >= 0 && idx < items.count {
            onImpressions?([items[idx]])
        }
    }
}

@MainActor
private final class RecommendSpotlightCardCell: UICollectionViewCell {
    static let reuseId = "RecommendSpotlightCardCell"

    private let coverContainer = UIView()
    private let coverView = RemoteImageView()
    private let remarkPill = UIView()
    private let remarkLabel = UILabel()
    private let titleLabel = UILabel()
    private let sublineLabel = UILabel()
    private let genreStack = UIStackView()
    private let reasonLabel = UILabel()
    private var onLongPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        contentView.backgroundColor = Palette.card
        contentView.layer.cornerRadius = 14
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = Palette.borderSoft.cgColor
        contentView.layer.masksToBounds = true

        coverContainer.backgroundColor = Palette.placeholder
        coverContainer.layer.cornerRadius = 8
        coverContainer.layer.masksToBounds = true
        coverContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverContainer)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(coverView)

        remarkPill.backgroundColor = UIColor.black.withAlphaComponent(0.64)
        remarkPill.layer.cornerRadius = 4
        remarkPill.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(remarkPill)

        remarkLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        remarkLabel.textColor = .white
        remarkLabel.translatesAutoresizingMaskIntoConstraints = false
        remarkPill.addSubview(remarkLabel)

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        sublineLabel.font = .systemFont(ofSize: 12)
        sublineLabel.textColor = Palette.secondaryText
        sublineLabel.numberOfLines = 1
        sublineLabel.lineBreakMode = .byTruncatingTail

        genreStack.axis = .horizontal
        genreStack.spacing = 4
        genreStack.alignment = .center

        reasonLabel.font = .systemFont(ofSize: 11, weight: .medium)
        reasonLabel.textColor = Palette.accentText
        reasonLabel.numberOfLines = 1
        reasonLabel.lineBreakMode = .byTruncatingTail

        let rightStack = UIStackView(arrangedSubviews: [titleLabel, sublineLabel, genreStack, UIView(), reasonLabel])
        rightStack.axis = .vertical
        rightStack.alignment = .leading
        rightStack.spacing = 4
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rightStack)

        NSLayoutConstraint.activate([
            coverContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 11),
            coverContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverContainer.widthAnchor.constraint(equalToConstant: 76),
            coverContainer.heightAnchor.constraint(equalToConstant: 101),

            coverView.topAnchor.constraint(equalTo: coverContainer.topAnchor),
            coverView.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor),
            coverView.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),

            remarkPill.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor, constant: -4),
            remarkPill.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: -4),
            remarkPill.leadingAnchor.constraint(greaterThanOrEqualTo: coverContainer.leadingAnchor, constant: 4),
            remarkLabel.topAnchor.constraint(equalTo: remarkPill.topAnchor, constant: 1),
            remarkLabel.bottomAnchor.constraint(equalTo: remarkPill.bottomAnchor, constant: -1),
            remarkLabel.leadingAnchor.constraint(equalTo: remarkPill.leadingAnchor, constant: 4),
            remarkLabel.trailingAnchor.constraint(equalTo: remarkPill.trailingAnchor, constant: -4),

            rightStack.topAnchor.constraint(equalTo: coverContainer.topAnchor),
            rightStack.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),
            rightStack.leadingAnchor.constraint(equalTo: coverContainer.trailingAnchor, constant: 12),
            rightStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        contentView.addGestureRecognizer(longPress)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        contentView.layer.borderColor = Palette.borderSoft.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.cancel()
        onLongPress = nil
    }

    func configure(item: RecommendItem, referer: String, library: LocalLibrary, onLongPress: @escaping () -> Void) {
        self.onLongPress = onLongPress
        titleLabel.text = item.summary.title

        let compact = DiscoveryModels.compactRemark(item.summary)
        remarkPill.isHidden = compact.isEmpty
        remarkLabel.text = compact

        var subParts: [String] = []
        if !item.author.isEmpty { subParts.append(item.author) }
        if !item.sourceName.isEmpty { subParts.append(item.sourceName) }
        sublineLabel.text = subParts.isEmpty ? item.summary.subtitle : subParts.joined(separator: " · ")

        genreStack.arrangedSubviews.forEach {
            genreStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for genre in item.genres.prefix(3) where !genre.isEmpty {
            let pill = UILabel()
            pill.text = " \(genre) "
            pill.font = .systemFont(ofSize: 10, weight: .medium)
            pill.textColor = Palette.accentText
            pill.backgroundColor = Palette.accentSoft
            pill.layer.cornerRadius = 4
            pill.layer.masksToBounds = true
            genreStack.addArrangedSubview(pill)
        }
        genreStack.isHidden = genreStack.arrangedSubviews.isEmpty

        reasonLabel.text = item.reason.isEmpty ? item.gridReason : item.reason
        coverView.loadCover(
            primaryUrl: item.summary.coverUrl,
            fallbackUrls: item.fallbackCoverUrls,
            referer: referer,
            library: library
        )
        accessibilityIdentifier = item.summary.title
        accessibilityLabel = item.summary.title
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress?()
    }
}

// MARK: - Guess You Like Grid Cell

@MainActor
final class RecommendGuessCell: UICollectionViewCell {
    static let reuseId = "RecommendGuessCell"

    private let headerView = RecommendSectionHeaderView()
    private let gridStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        gridStack.axis = .vertical
        gridStack.spacing = 12
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(gridStack)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            gridStack.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            gridStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gridStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gridStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    static func requiredHeight(itemCount: Int, columnCount: Int, availableWidth: CGFloat) -> CGFloat {
        let cols = max(3, columnCount)
        let spacing = DiscoveryLayoutMetrics.interItemSpacing
        let cardW = floor((max(200, availableWidth) - spacing * CGFloat(cols - 1)) / CGFloat(cols))
        let coverH = ceil(cardW * 4.0 / 3.0)
        let tileH = coverH + 6 + 34 + 16 + 4 // cover + gap + 2-line title + gridReason + slack
        let rows = max(1, Int(ceil(Double(itemCount) / Double(cols))))
        return 30 + 8 + CGFloat(rows) * tileH + CGFloat(max(0, rows - 1)) * 12
    }

    func configure(
        items: [RecommendItem],
        columnCount: Int,
        availableWidth: CGFloat,
        refererProvider: @escaping (RecommendItem) -> String,
        library: LocalLibrary,
        onRefresh: @escaping () -> Void,
        onSelect: @escaping (RecommendItem) -> Void,
        onLongPress: @escaping (RecommendItem) -> Void
    ) {
        headerView.configure(
            title: "猜你喜欢",
            actionTitle: "换一批",
            icon: .refresh,
            actionId: "recommend.guess.refresh",
            onAction: onRefresh
        )

        gridStack.arrangedSubviews.forEach {
            gridStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let cols = max(3, columnCount)
        let spacing = DiscoveryLayoutMetrics.interItemSpacing
        let cardW = floor((max(200, availableWidth) - spacing * CGFloat(cols - 1)) / CGFloat(cols))
        let coverH = ceil(cardW * 4.0 / 3.0)

        var idx = 0
        while idx < items.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = spacing
            row.alignment = .top

            for c in 0..<cols {
                let itemIdx = idx + c
                if itemIdx < items.count {
                    let item = items[itemIdx]
                    let tile = RecommendGridTileView(coverHeight: coverH)
                    tile.configure(
                        item: item,
                        referer: refererProvider(item),
                        library: library,
                        onTap: { onSelect(item) },
                        onLongPress: { onLongPress(item) }
                    )
                    row.addArrangedSubview(tile)
                } else {
                    row.addArrangedSubview(UIView())
                }
            }
            gridStack.addArrangedSubview(row)
            idx += cols
        }
    }
}

@MainActor
private final class RecommendGridTileView: UIView {
    private let coverContainer = UIView()
    private let coverView = RemoteImageView()
    private let remarkPill = UIView()
    private let remarkLabel = UILabel()
    private let titleLabel = UILabel()
    private let reasonLabel = UILabel()
    private var onTap: (() -> Void)?
    private var onLongPress: (() -> Void)?

    init(coverHeight: CGFloat) {
        super.init(frame: .zero)
        setup(coverHeight: coverHeight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup(coverHeight: CGFloat) {
        coverContainer.backgroundColor = Palette.placeholder
        coverContainer.layer.cornerRadius = 8
        coverContainer.layer.borderWidth = 0.5
        coverContainer.layer.borderColor = Palette.borderSoft.cgColor
        coverContainer.layer.masksToBounds = true
        coverContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverContainer)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(coverView)

        remarkPill.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        remarkPill.layer.cornerRadius = 4
        remarkPill.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(remarkPill)

        remarkLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        remarkLabel.textColor = .white
        remarkLabel.translatesAutoresizingMaskIntoConstraints = false
        remarkPill.addSubview(remarkLabel)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        reasonLabel.font = .systemFont(ofSize: 11, weight: .medium)
        reasonLabel.textColor = Palette.accentText
        reasonLabel.numberOfLines = 1
        reasonLabel.lineBreakMode = .byTruncatingTail
        reasonLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reasonLabel)

        NSLayoutConstraint.activate([
            coverContainer.topAnchor.constraint(equalTo: topAnchor),
            coverContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            coverContainer.heightAnchor.constraint(equalToConstant: coverHeight),

            coverView.topAnchor.constraint(equalTo: coverContainer.topAnchor),
            coverView.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor),
            coverView.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),

            remarkPill.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor, constant: -4),
            remarkPill.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: -4),
            remarkPill.leadingAnchor.constraint(greaterThanOrEqualTo: coverContainer.leadingAnchor, constant: 4),
            remarkLabel.topAnchor.constraint(equalTo: remarkPill.topAnchor, constant: 1),
            remarkLabel.bottomAnchor.constraint(equalTo: remarkPill.bottomAnchor, constant: -1),
            remarkLabel.leadingAnchor.constraint(equalTo: remarkPill.leadingAnchor, constant: 4),
            remarkLabel.trailingAnchor.constraint(equalTo: remarkPill.trailingAnchor, constant: -4),

            titleLabel.topAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            reasonLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            reasonLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            reasonLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            reasonLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.45
        addGestureRecognizer(lp)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        coverContainer.layer.borderColor = Palette.borderSoft.cgColor
    }

    func configure(
        item: RecommendItem,
        referer: String,
        library: LocalLibrary,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) {
        self.onTap = onTap
        self.onLongPress = onLongPress
        titleLabel.text = item.summary.title
        reasonLabel.text = item.gridReason.isEmpty ? item.sourceName : item.gridReason
        let compact = DiscoveryModels.compactRemark(item.summary)
        remarkPill.isHidden = compact.isEmpty
        remarkLabel.text = compact
        coverView.loadCover(
            primaryUrl: item.summary.coverUrl,
            fallbackUrls: item.fallbackCoverUrls,
            referer: referer,
            library: library
        )
        accessibilityIdentifier = item.summary.title
        accessibilityLabel = item.summary.title
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress?()
    }
}

// MARK: - Hot Rank Cell

@MainActor
final class RecommendHotCell: UICollectionViewCell {
    static let reuseId = "RecommendHotCell"

    private let headerView = RecommendSectionHeaderView()
    private let cardView = UIView()
    private let rowsStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        cardView.backgroundColor = Palette.card
        cardView.layer.cornerRadius = 14
        cardView.layer.borderWidth = 0.5
        cardView.layer.borderColor = Palette.borderSoft.cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        rowsStack.axis = .vertical
        rowsStack.spacing = 6
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(rowsStack)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            cardView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            rowsStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            rowsStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            rowsStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            rowsStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        cardView.layer.borderColor = Palette.borderSoft.cgColor
    }

    static func visibleCount(availableWidth: CGFloat, totalItems: Int) -> (columns: Int, count: Int) {
        let cols = availableWidth >= 520 ? 2 : 1
        let maxItems = cols == 2 ? 6 : 5
        return (cols, min(maxItems, totalItems))
    }

    static func requiredHeight(totalItems: Int, availableWidth: CGFloat) -> CGFloat {
        let info = visibleCount(availableWidth: availableWidth, totalItems: totalItems)
        let rows = max(1, Int(ceil(Double(info.count) / Double(info.columns))))
        let rowHeight: CGFloat = 53
        return 30 + 8 + 20 + CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * 6
    }

    func configure(
        items: [RecommendItem],
        availableWidth: CGFloat,
        refererProvider: @escaping (RecommendItem) -> String,
        library: LocalLibrary,
        onViewAll: @escaping () -> Void,
        onSelect: @escaping (RecommendItem) -> Void,
        onLongPress: @escaping (RecommendItem) -> Void
    ) {
        headerView.configure(
            title: "全网热门",
            actionTitle: "查看全部",
            icon: .chevronRight,
            iconTrailing: true,
            actionId: "recommend.hot.viewAll",
            onAction: onViewAll
        )

        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let info = Self.visibleCount(availableWidth: availableWidth, totalItems: items.count)
        let slice = Array(items.prefix(info.count))

        if info.columns == 2 {
            var idx = 0
            while idx < slice.count {
                let row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.spacing = 12
                for c in 0..<2 {
                    let pos = idx + c
                    if pos < slice.count {
                        let item = slice[pos]
                        row.addArrangedSubview(makeRankRow(
                            rank: pos + 1,
                            item: item,
                            referer: refererProvider(item),
                            library: library,
                            onSelect: { onSelect(item) },
                            onLongPress: { onLongPress(item) }
                        ))
                    } else {
                        row.addArrangedSubview(UIView())
                    }
                }
                rowsStack.addArrangedSubview(row)
                idx += 2
            }
        } else {
            for (pos, item) in slice.enumerated() {
                rowsStack.addArrangedSubview(makeRankRow(
                    rank: pos + 1,
                    item: item,
                    referer: refererProvider(item),
                    library: library,
                    onSelect: { onSelect(item) },
                    onLongPress: { onLongPress(item) }
                ))
            }
        }
    }

    private func makeRankRow(
        rank: Int,
        item: RecommendItem,
        referer: String,
        library: LocalLibrary,
        onSelect: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) -> UIView {
        let row = RecommendHotRankRowView()
        row.configure(rank: rank, item: item, referer: referer, library: library, onTap: onSelect, onLongPress: onLongPress)
        return row
    }
}

@MainActor
final class RecommendHotRankRowView: UIView {
    private let rankBadge = UILabel()
    private let coverView = RemoteImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let pillLabel = UILabel()
    private var onTap: (() -> Void)?
    private var onLongPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        rankBadge.font = .systemFont(ofSize: 12, weight: .bold)
        rankBadge.textAlignment = .center
        rankBadge.layer.cornerRadius = 6
        rankBadge.layer.masksToBounds = true
        rankBadge.translatesAutoresizingMaskIntoConstraints = false

        coverView.contentMode = .scaleAspectFill
        coverView.backgroundColor = Palette.placeholder
        coverView.layer.cornerRadius = 6
        coverView.layer.masksToBounds = true
        coverView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Palette.text
        titleLabel.lineBreakMode = .byTruncatingTail

        metaLabel.font = .systemFont(ofSize: 11)
        metaLabel.textColor = Palette.secondaryText
        metaLabel.lineBreakMode = .byTruncatingTail

        let textStack = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        pillLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        pillLabel.textColor = Palette.accentText
        pillLabel.backgroundColor = Palette.accentSoft
        pillLabel.layer.cornerRadius = 9
        pillLabel.layer.masksToBounds = true
        pillLabel.textAlignment = .center
        pillLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [rankBadge, coverView, textStack, pillLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            rankBadge.widthAnchor.constraint(equalToConstant: 24),
            rankBadge.heightAnchor.constraint(equalToConstant: 24),

            coverView.widthAnchor.constraint(equalToConstant: 34),
            coverView.heightAnchor.constraint(equalToConstant: 45),

            pillLabel.heightAnchor.constraint(equalToConstant: 20),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.45
        addGestureRecognizer(lp)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    func configure(
        rank: Int,
        item: RecommendItem,
        referer: String,
        library: LocalLibrary,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) {
        self.onTap = onTap
        self.onLongPress = onLongPress

        rankBadge.text = "\(rank)"
        switch rank {
        case 1:
            rankBadge.backgroundColor = UIColor(red: 0.85, green: 0.51, blue: 0.17, alpha: 0.18)
            rankBadge.textColor = UIColor(red: 0.85, green: 0.51, blue: 0.17, alpha: 1.0)
        case 2:
            rankBadge.backgroundColor = UIColor(red: 0.43, green: 0.51, blue: 0.58, alpha: 0.18)
            rankBadge.textColor = UIColor(red: 0.43, green: 0.51, blue: 0.58, alpha: 1.0)
        case 3:
            rankBadge.backgroundColor = UIColor(red: 0.66, green: 0.41, blue: 0.25, alpha: 0.18)
            rankBadge.textColor = UIColor(red: 0.66, green: 0.41, blue: 0.25, alpha: 1.0)
        default:
            rankBadge.backgroundColor = Palette.surface
            rankBadge.textColor = Palette.secondaryText
        }

        titleLabel.text = item.summary.title
        var metaParts: [String] = []
        if !item.genres.isEmpty { metaParts.append(item.genres.prefix(2).joined(separator: "/")) }
        let remark = DiscoveryModels.compactRemark(item.summary)
        if !remark.isEmpty { metaParts.append(remark) }
        if metaParts.isEmpty && !item.sourceName.isEmpty { metaParts.append(item.sourceName) }
        metaLabel.text = metaParts.joined(separator: " · ")

        let badge = item.hotSourceCount >= 2 ? "  \(item.hotSourceCount)站热推  " : "  \(item.sourceName)  "
        pillLabel.text = badge
        pillLabel.isHidden = badge.trimmingCharacters(in: .whitespaces).isEmpty

        coverView.loadCover(
            primaryUrl: item.summary.coverUrl,
            fallbackUrls: item.fallbackCoverUrls,
            referer: referer,
            library: library
        )
        accessibilityIdentifier = item.summary.title
        accessibilityLabel = "\(rank). \(item.summary.title)"
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress?()
    }
}

// MARK: - Latest Updates Horizontal Strip Cell

@MainActor
final class RecommendLatestCell: UICollectionViewCell {
    static let reuseId = "RecommendLatestCell"

    private let headerView = RecommendSectionHeaderView()
    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var carousel = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)

    private var items: [RecommendItem] = []
    private var refererProvider: ((RecommendItem) -> String)?
    private var library: LocalLibrary?
    private var onSelect: ((RecommendItem) -> Void)?
    private var onLongPress: ((RecommendItem) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumLineSpacing = 10
        flowLayout.itemSize = CGSize(width: 92, height: 176)

        carousel.backgroundColor = .clear
        carousel.showsHorizontalScrollIndicator = false
        carousel.dataSource = self
        carousel.delegate = self
        carousel.register(RecommendLatestCardCell.self, forCellWithReuseIdentifier: RecommendLatestCardCell.reuseId)
        carousel.translatesAutoresizingMaskIntoConstraints = false
        carousel.accessibilityIdentifier = "recommend.latest.carousel"
        contentView.addSubview(carousel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            carousel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            carousel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            carousel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            carousel.heightAnchor.constraint(equalToConstant: 176),
            carousel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    static func requiredHeight() -> CGFloat {
        // 30 header + 8 gap + 176 carousel = 214
        return 214
    }

    func configure(
        items: [RecommendItem],
        refererProvider: @escaping (RecommendItem) -> String,
        library: LocalLibrary,
        onSelect: @escaping (RecommendItem) -> Void,
        onLongPress: @escaping (RecommendItem) -> Void
    ) {
        self.items = items
        self.refererProvider = refererProvider
        self.library = library
        self.onSelect = onSelect
        self.onLongPress = onLongPress

        headerView.configure(title: "最近上新", actionTitle: nil)
        carousel.reloadData()
    }
}

extension RecommendLatestCell: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: RecommendLatestCardCell.reuseId,
            for: indexPath
        ) as? RecommendLatestCardCell,
              let library,
              let refererProvider else {
            return UICollectionViewCell()
        }
        let item = items[indexPath.item]
        cell.configure(item: item, referer: refererProvider(item), library: library) { [weak self] in
            self?.onLongPress?(item)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(items[indexPath.item])
    }
}

@MainActor
private final class RecommendLatestCardCell: UICollectionViewCell {
    static let reuseId = "RecommendLatestCardCell"

    private let coverContainer = UIView()
    private let coverView = RemoteImageView()
    private let remarkPill = UIView()
    private let remarkLabel = UILabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private var onLongPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
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

        remarkPill.backgroundColor = UIColor.black.withAlphaComponent(0.64)
        remarkPill.layer.cornerRadius = 4
        remarkPill.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(remarkPill)

        remarkLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        remarkLabel.textColor = .white
        remarkLabel.translatesAutoresizingMaskIntoConstraints = false
        remarkPill.addSubview(remarkLabel)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        metaLabel.font = .systemFont(ofSize: 10)
        metaLabel.textColor = Palette.secondaryText
        metaLabel.numberOfLines = 1
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(metaLabel)

        NSLayoutConstraint.activate([
            coverContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverContainer.widthAnchor.constraint(equalToConstant: 92),
            coverContainer.heightAnchor.constraint(equalToConstant: 122),

            coverView.topAnchor.constraint(equalTo: coverContainer.topAnchor),
            coverView.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor),
            coverView.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),

            remarkPill.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor, constant: -4),
            remarkPill.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: -4),
            remarkPill.leadingAnchor.constraint(greaterThanOrEqualTo: coverContainer.leadingAnchor, constant: 4),
            remarkLabel.topAnchor.constraint(equalTo: remarkPill.topAnchor, constant: 1),
            remarkLabel.bottomAnchor.constraint(equalTo: remarkPill.bottomAnchor, constant: -1),
            remarkLabel.leadingAnchor.constraint(equalTo: remarkPill.leadingAnchor, constant: 4),
            remarkLabel.trailingAnchor.constraint(equalTo: remarkPill.trailingAnchor, constant: -4),

            titleLabel.topAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.45
        contentView.addGestureRecognizer(lp)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        coverContainer.layer.borderColor = Palette.borderSoft.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.cancel()
        onLongPress = nil
    }

    func configure(item: RecommendItem, referer: String, library: LocalLibrary, onLongPress: @escaping () -> Void) {
        self.onLongPress = onLongPress
        titleLabel.text = item.summary.title
        metaLabel.text = item.genres.first ?? item.sourceName
        let compact = DiscoveryModels.compactRemark(item.summary)
        remarkPill.isHidden = compact.isEmpty
        remarkLabel.text = compact
        coverView.loadCover(
            primaryUrl: item.summary.coverUrl,
            fallbackUrls: item.fallbackCoverUrls,
            referer: referer,
            library: library
        )
        accessibilityIdentifier = item.summary.title
        accessibilityLabel = item.summary.title
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress?()
    }
}

// MARK: - More Header & Poster Card Cell

@MainActor
final class RecommendMoreHeaderCell: UICollectionViewCell {
    static let reuseId = "RecommendMoreHeaderCell"
    private let headerView = RecommendSectionHeaderView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func configure(subtitle: String? = nil) {
        headerView.configure(title: subtitle ?? "更多推荐", actionTitle: nil)
    }
}

@MainActor
final class RecommendMoreCardCell: UICollectionViewCell {
    static let reuseId = "RecommendMoreCardCell"

    private let coverContainer = UIView()
    private let coverView = RemoteImageView()
    private let remarkPill = UIView()
    private let remarkLabel = UILabel()
    private let titleLabel = UILabel()
    private let reasonBadge = UILabel()
    private var onLongPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
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

        remarkPill.backgroundColor = UIColor.black.withAlphaComponent(0.64)
        remarkPill.layer.cornerRadius = 4
        remarkPill.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(remarkPill)

        remarkLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        remarkLabel.textColor = .white
        remarkLabel.translatesAutoresizingMaskIntoConstraints = false
        remarkPill.addSubview(remarkLabel)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        reasonBadge.font = .systemFont(ofSize: 11, weight: .medium)
        reasonBadge.textColor = Palette.accentText
        reasonBadge.numberOfLines = 1
        reasonBadge.lineBreakMode = .byTruncatingTail
        reasonBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(reasonBadge)

        NSLayoutConstraint.activate([
            coverContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            coverContainer.heightAnchor.constraint(equalTo: coverContainer.widthAnchor, multiplier: 4.0 / 3.0),

            coverView.topAnchor.constraint(equalTo: coverContainer.topAnchor),
            coverView.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor),
            coverView.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),

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

            reasonBadge.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            reasonBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            reasonBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.45
        contentView.addGestureRecognizer(lp)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        coverContainer.layer.borderColor = Palette.borderSoft.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.cancel()
        onLongPress = nil
    }

    static func cardHeight(forCardWidth width: CGFloat) -> CGFloat {
        return ceil(width * 4.0 / 3.0) + 6 + 34 + 16 + 4
    }

    func configure(item: RecommendItem, referer: String, library: LocalLibrary, onLongPress: @escaping () -> Void) {
        self.onLongPress = onLongPress
        titleLabel.text = item.summary.title
        reasonBadge.text = item.gridReason.isEmpty ? item.sourceName : item.gridReason
        let compact = DiscoveryModels.compactRemark(item.summary)
        remarkPill.isHidden = compact.isEmpty
        remarkLabel.text = compact
        coverView.loadCover(
            primaryUrl: item.summary.coverUrl,
            fallbackUrls: item.fallbackCoverUrls,
            referer: referer,
            library: library
        )
        accessibilityIdentifier = item.summary.title
        accessibilityLabel = item.summary.title
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress?()
    }
}

// MARK: - Recommend Footer Cell

@MainActor
final class RecommendFooterCell: UICollectionViewCell {
    static let reuseId = "RecommendFooterCell"

    private let stack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let actionButton = UIButton(type: .system)
    private var onRetry: (() -> Void)?

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

        actionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        actionButton.addTarget(self, action: #selector(handleRetry), for: .touchUpInside)

        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(actionButton)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    func configure(state: RecommendPagePolicy.FooterStateKind, errorMessage: String, onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
        switch state {
        case .ready:
            spinner.stopAnimating()
            actionButton.setTitle("继续下滑加载更多", for: .normal)
            actionButton.setTitleColor(Palette.text3, for: .normal)
            actionButton.isEnabled = false
            actionButton.accessibilityIdentifier = "recommend.footer.ready"
        case .loading:
            spinner.startAnimating()
            actionButton.setTitle("正在挖掘更多推荐...", for: .normal)
            actionButton.setTitleColor(Palette.secondaryText, for: .normal)
            actionButton.isEnabled = false
            actionButton.accessibilityIdentifier = "recommend.footer.loading"
        case .error:
            spinner.stopAnimating()
            let msg = errorMessage.isEmpty ? RecommendPagePolicy.defaultFooterError : errorMessage
            actionButton.setTitle(msg, for: .normal)
            actionButton.setTitleColor(Palette.danger, for: .normal)
            actionButton.isEnabled = true
            actionButton.accessibilityIdentifier = "recommend.footer.retry"
        }
    }

    @objc private func handleRetry() {
        onRetry?()
    }
}

// MARK: - Recommend Empty / Skeleton / Error State Cell

@MainActor
final class RecommendStateCell: UICollectionViewCell {
    static let reuseId = "RecommendStateCell"

    enum Mode {
        case skeleton(columns: Int)
        case emptySources(onManageSources: () -> Void)
        case noPersonalization(onOpenPref: () -> Void)
        case emptyFeed(message: String, onRetry: () -> Void)
        case error(message: String, onRetry: () -> Void)
    }

    private let stack = UIStackView()
    private var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    func configure(mode: Mode, availableWidth: CGFloat) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        onAction = nil

        switch mode {
        case .skeleton(let cols):
            buildSkeleton(columns: max(3, cols), width: availableWidth)
        case .emptySources(let onManage):
            buildCard(
                title: "还没有可用的发现站源",
                subtitle: "请在站源管理中启用至少一个站源，即可为你生成本地推荐流",
                buttonTitle: "管理站源",
                assetName: "rem_empty_discovery",
                onAction: onManage
            )
        case .noPersonalization(let onOpenPref):
            buildCard(
                title: "当前仅展示基础推荐",
                subtitle: "你已关闭个性化推荐，可在推荐偏好中重新开启或选择题材",
                buttonTitle: "推荐偏好",
                assetName: "rem_empty_discovery",
                onAction: onOpenPref
            )
        case .emptyFeed(let message, let onRetry):
            buildCard(
                title: message,
                subtitle: "你可以下拉刷新，或在推荐偏好中调整题材与屏蔽列表",
                buttonTitle: "重新生成推荐",
                assetName: "rem_empty_discovery",
                onAction: onRetry
            )
        case .error(let message, let onRetry):
            buildCard(
                title: message,
                subtitle: "部分站源请求失败，点击可立即重新拉取",
                buttonTitle: "点击重试",
                assetName: nil,
                onAction: onRetry
            )
        }
    }

    private func buildSkeleton(columns: Int, width: CGFloat) {
        let banner = UIView()
        banner.backgroundColor = Palette.placeholder
        banner.layer.cornerRadius = 14
        banner.heightAnchor.constraint(equalToConstant: 124).isActive = true
        stack.addArrangedSubview(banner)

        let spacing = DiscoveryLayoutMetrics.interItemSpacing
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
                let line = UIView()
                line.backgroundColor = Palette.surface
                line.layer.cornerRadius = 4
                line.heightAnchor.constraint(equalToConstant: 12).isActive = true
                col.addArrangedSubview(box)
                col.addArrangedSubview(line)
                row.addArrangedSubview(col)
            }
            stack.addArrangedSubview(row)
        }
    }

    private func buildCard(
        title: String,
        subtitle: String,
        buttonTitle: String,
        assetName: String?,
        onAction: @escaping () -> Void
    ) {
        self.onAction = onAction

        let card = UIView()
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 0.5
        card.layer.borderColor = Palette.borderSoft.cgColor

        let inner = UIStackView()
        inner.axis = .vertical
        inner.alignment = .center
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)

        if let assetName, !assetName.isEmpty {
            let img = UIImageView()
            img.contentMode = .scaleAspectFit
            img.translatesAutoresizingMaskIntoConstraints = false
            img.widthAnchor.constraint(equalToConstant: 108).isActive = true
            img.heightAnchor.constraint(equalToConstant: 108).isActive = true
            AppIllustrationCache.bind(img, assetName: assetName, maxSideDp: 108)
            inner.addArrangedSubview(img)
        }

        let titleLbl = UILabel()
        titleLbl.text = title
        titleLbl.font = .systemFont(ofSize: 16, weight: .bold)
        titleLbl.textColor = Palette.text
        titleLbl.textAlignment = .center
        titleLbl.numberOfLines = 0

        let subLbl = UILabel()
        subLbl.text = subtitle
        subLbl.font = .systemFont(ofSize: 13)
        subLbl.textColor = Palette.secondaryText
        subLbl.textAlignment = .center
        subLbl.numberOfLines = 0

        let btn = UIButton(type: .system)
        btn.setTitle(buttonTitle, for: .normal)
        btn.setTitleColor(Palette.onAccent, for: .normal)
        btn.backgroundColor = Palette.accent
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.layer.cornerRadius = 18
        btn.contentEdgeInsets = UIEdgeInsets(top: 9, left: 20, bottom: 9, right: 20)
        btn.accessibilityIdentifier = "recommend.state.action"
        btn.addTarget(self, action: #selector(handleAction), for: .touchUpInside)

        inner.addArrangedSubview(titleLbl)
        inner.addArrangedSubview(subLbl)
        inner.addArrangedSubview(btn)

        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])

        stack.addArrangedSubview(card)
    }

    @objc private func handleAction() {
        onAction?()
    }
}
