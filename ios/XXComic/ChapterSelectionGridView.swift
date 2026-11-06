import UIKit
import ComicCore

/// Recycled compact chapter selection grid with toolbar helpers and swipe/drag selection.
/// Aligned 1:1 with Android 2.0.44's `ChapterSelectionGrid`.
/// Features:
/// - Multi-column compact chapter cells with title, selected state, and "已下载" badge.
/// - Pan & long-press gesture recognizers wired to `SwipeChapterSelection` for smooth drag selection/deselection.
/// - Toolbar helper actions: Select All (`allButton`), Invert/Clear (`invertButton`), Sort Order Toggle (`orderButton`).
/// - Hint label: "轻点选择，长按后滑动连续选择".
/// - Empty state: "暂无可选择章节".
public final class ChapterSelectionGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {

    // MARK: - Item Model

    public struct Item: Equatable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let fullTitle: String
        public let selectable: Bool
        public let isDownloaded: Bool
        public let open: (() -> Void)?

        public init(
            id: String,
            title: String,
            subtitle: String = "",
            fullTitle: String = "",
            selectable: Bool = true,
            isDownloaded: Bool = false,
            open: (() -> Void)? = nil
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.fullTitle = fullTitle.isEmpty ? title : fullTitle
            self.selectable = selectable
            self.isDownloaded = isDownloaded
            self.open = open
        }

        public static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.subtitle == rhs.subtitle &&
            lhs.fullTitle == rhs.fullTitle &&
            lhs.selectable == rhs.selectable &&
            lhs.isDownloaded == rhs.isDownloaded
        }
    }

    // MARK: - Properties

    private var canonicalItems: [Item] = []
    private var visibleItems: [Item] = []
    private var positions: [String: Int] = [:]

    public private(set) var selection: SwipeChapterSelection
    public private(set) var isDescending: Bool = false
    public private(set) var isInteractive: Bool = true
    public var isCompact: Bool = true

    public var onSelectionChanged: (() -> Void)?
    public var onOrderChanged: ((Bool) -> Void)?

    // MARK: - Gesture & Drag State

    private var isPainting: Bool = false
    private var displayLink: CADisplayLink?
    private var lastTouchY: CGFloat = 0

    // MARK: - Subviews

    public let allButton = UIButton(type: .custom)
    public let orderButton = UIButton(type: .custom)
    public let invertButton = UIButton(type: .custom)
    private let toolbarStack = UIStackView()
    private let hintLabel = UILabel()
    private let emptyLabel = UILabel()

    public private(set) var collectionView: UICollectionView!
    public private(set) var panGesture: UIPanGestureRecognizer!
    public private(set) var longPressGesture: UILongPressGestureRecognizer!

    // MARK: - Initializers

    public init(
        entries: [Item] = [],
        selected: Set<String> = [],
        compact: Bool = true,
        onSelectionChanged: (() -> Void)? = nil
    ) {
        self.isCompact = compact
        self.onSelectionChanged = onSelectionChanged

        // Deduplicate canonical items by ID
        var seenIds = Set<String>()
        var deduped: [Item] = []
        var availableIds = Set<String>()
        for item in entries {
            if seenIds.insert(item.id).inserted {
                deduped.append(item)
                if item.selectable {
                    availableIds.insert(item.id)
                }
            }
        }
        self.canonicalItems = deduped
        self.visibleItems = deduped
        self.selection = SwipeChapterSelection(available: availableIds, selected: selected)

        super.init(frame: .zero)
        setupViews()
        reindex()
        updateTools()
    }

    required init?(coder: NSCoder) {
        self.selection = SwipeChapterSelection(available: [])
        super.init(coder: coder)
        setupViews()
        reindex()
        updateTools()
    }

    // MARK: - Setup Views

    private func setupViews() {
        accessibilityIdentifier = "chapter-selection-grid"
        translatesAutoresizingMaskIntoConstraints = false

        // Toolbar row
        toolbarStack.axis = .horizontal
        toolbarStack.alignment = .center
        toolbarStack.distribution = .equalSpacing
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbarStack)

        setupToolButton(allButton, identifier: "chapter.selection.all", defaultTitle: "全选章节")
        allButton.addTarget(self, action: #selector(allButtonTapped), for: .touchUpInside)

        setupToolButton(invertButton, identifier: "chapter.selection.invert", defaultTitle: "反选章节")
        invertButton.setImage(UIImage(systemName: "arrow.left.arrow.right"), for: .normal)
        invertButton.tintColor = Palette.text2
        invertButton.accessibilityLabel = "反选章节"
        invertButton.addTarget(self, action: #selector(invertButtonTapped), for: .touchUpInside)

        setupToolButton(orderButton, identifier: "chapter.selection.order", defaultTitle: "当前正序，切换倒序")
        orderButton.addTarget(self, action: #selector(orderButtonTapped), for: .touchUpInside)

        let rightTools = UIStackView(arrangedSubviews: [allButton, invertButton, orderButton])
        rightTools.axis = .horizontal
        rightTools.alignment = .center
        rightTools.spacing = 4
        rightTools.translatesAutoresizingMaskIntoConstraints = false
        toolbarStack.addArrangedSubview(rightTools)

        // Hint label: "轻点选择，长按后滑动连续选择"
        hintLabel.text = "轻点选择，长按后滑动连续选择"
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = Palette.text3
        hintLabel.accessibilityIdentifier = "chapter.selection.hint"
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        // Collection View
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 0, left: 6, bottom: 6, right: 6)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.accessibilityIdentifier = "chapter-grid"
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ChapterSelectionCell.self, forCellWithReuseIdentifier: ChapterSelectionCell.reuseIdentifier)
        addSubview(collectionView)

        // Gestures for swipe paint selection
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.25
        longPressGesture.delegate = self
        collectionView.addGestureRecognizer(longPressGesture)

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        collectionView.addGestureRecognizer(panGesture)

        // Empty state label
        emptyLabel.text = "暂无可选择章节"
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = Palette.text3
        emptyLabel.textAlignment = .center
        emptyLabel.accessibilityIdentifier = "chapter.selection.empty"
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = !canonicalItems.isEmpty
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            toolbarStack.topAnchor.constraint(equalTo: topAnchor),
            toolbarStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            toolbarStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            toolbarStack.heightAnchor.constraint(equalToConstant: 48),

            hintLabel.topAnchor.constraint(equalTo: toolbarStack.bottomAnchor, constant: 2),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),

            collectionView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 6),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func setupToolButton(_ button: UIButton, identifier: String, defaultTitle: String) {
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = defaultTitle
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        updateFlowLayout()
    }

    private func updateFlowLayout() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let width = collectionView.bounds.width
        guard width > 0 else { return }

        let gap: CGFloat = 6
        let cellBaseWidth: CGFloat = isCompact ? 64 : 84
        let scale = max(1.0, traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1.2 : 1.0)
        let scaledWidth = round(cellBaseWidth * scale)
        let availableWidth = width - layout.sectionInset.left - layout.sectionInset.right

        let columns = max(2, Int((availableWidth + gap) / (scaledWidth + gap)))
        let totalGaps = CGFloat(columns - 1) * gap
        let itemWidth = floor((availableWidth - totalGaps) / CGFloat(columns))
        let itemHeight: CGFloat = isCompact ? 48 : 64

        let newSize = CGSize(width: itemWidth, height: itemHeight)
        if layout.itemSize != newSize {
            layout.itemSize = newSize
            layout.invalidateLayout()
        }
    }

    // MARK: - Public Accessors

    public func selectionButton() -> UIButton { allButton }

    public var selectedCount: Int { selection.count }

    public func isSelected(_ id: String) -> Bool { selection.contains(id) }
    public func selectedIds() -> Set<String> { selection.selected }

    public func setOnOrderChanged(_ listener: ((Bool) -> Void)?) {
        orderChanged = listener
    }

    public var orderChanged: ((Bool) -> Void)? {
        get { onOrderChanged }
        set { onOrderChanged = newValue }
    }

    public func setInteractionEnabled(_ enabled: Bool) {
        cancelStroke()
        isInteractive = enabled
        collectionView.isUserInteractionEnabled = enabled
        collectionView.reloadData()
        updateTools()
    }

    public func setInteractive(_ enabled: Bool) {
        setInteractionEnabled(enabled)
    }

    public func setItems(_ items: [Item], selected: Set<String>? = nil) {
        setEntries(items, selected: selected)
    }

    public func setDescending(_ value: Bool) {
        if isDescending == value { return }
        cancelStroke()
        isDescending = value
        visibleItems = isDescending ? Array(canonicalItems.reversed()) : canonicalItems
        reindex()
        collectionView.reloadData()
        if !visibleItems.isEmpty {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
        }
        updateTools()
        onOrderChanged?(value)
    }

    public func setEntries(_ entries: [Item], selected: Set<String>? = nil) {
        cancelStroke()
        var seen = Set<String>()
        var deduped: [Item] = []
        var availableIds = Set<String>()
        for item in entries {
            if seen.insert(item.id).inserted {
                deduped.append(item)
                if item.selectable {
                    availableIds.insert(item.id)
                }
            }
        }
        canonicalItems = deduped
        visibleItems = isDescending ? Array(canonicalItems.reversed()) : canonicalItems
        let newSelected = selected ?? self.selection.selected
        self.selection = SwipeChapterSelection(available: availableIds, selected: newSelected)
        emptyLabel.isHidden = !canonicalItems.isEmpty
        reindex()
        collectionView.reloadData()
        updateTools()
    }

    public func selectAll() {
        cancelStroke()
        if !selection.allSelected() {
            selection.toggleAll()
        }
        collectionView.reloadData()
        notifySelection()
    }

    public func clearSelection() {
        cancelStroke()
        if selection.allSelected() {
            selection.toggleAll()
        } else {
            selection.setSelected([])
        }
        collectionView.reloadData()
        notifySelection()
    }

    public func invertSelection() {
        cancelStroke()
        for item in canonicalItems where item.selectable {
            _ = selection.toggle(item.id)
        }
        collectionView.reloadData()
        notifySelection()
    }

    // MARK: - Tools State Management

    private func updateTools() {
        let all = selection.allSelected()
        allButton.isSelected = all
        let allImage = UIImage(systemName: all ? "checkmark.circle.fill" : "circle")
        allButton.setImage(allImage, for: .normal)
        allButton.tintColor = all ? Palette.accent : Palette.text2
        let allLabel = all ? "取消全选章节" : "全选章节"
        allButton.accessibilityLabel = allLabel
        allButton.isEnabled = isInteractive && selection.availableCount > 0
        allButton.alpha = allButton.isEnabled ? 1.0 : 0.35

        invertButton.isEnabled = isInteractive && selection.availableCount > 0
        invertButton.alpha = invertButton.isEnabled ? 1.0 : 0.35

        orderButton.isSelected = isDescending
        let orderImage = UIImage(systemName: isDescending ? "arrow.down" : "arrow.up")
        orderButton.setImage(orderImage, for: .normal)
        orderButton.tintColor = isDescending ? Palette.accent : Palette.text2
        let orderLabel = isDescending ? "当前倒序，切换正序" : "当前正序，切换倒序"
        orderButton.accessibilityLabel = orderLabel
        orderButton.isEnabled = isInteractive && visibleItems.count > 1
        orderButton.alpha = orderButton.isEnabled ? 1.0 : 0.35
    }

    private func notifySelection() {
        updateTools()
        onSelectionChanged?()
    }

    private func reindex() {
        positions.removeAll(keepingCapacity: true)
        for (i, item) in visibleItems.enumerated() {
            positions[item.id] = i
        }
    }

    // MARK: - Actions

    @objc private func allButtonTapped() {
        cancelStroke()
        selection.toggleAll()
        collectionView.reloadData()
        notifySelection()
    }

    @objc private func invertButtonTapped() {
        invertSelection()
    }

    @objc private func orderButtonTapped() {
        setDescending(!isDescending)
    }

    // MARK: - UICollectionViewDataSource & Delegate

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleItems.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChapterSelectionCell.reuseIdentifier, for: indexPath) as! ChapterSelectionCell
        let item = visibleItems[indexPath.item]
        let isSelected = selection.contains(item.id)
        cell.configure(item: item, isSelected: isSelected, isCompact: isCompact, isInteractive: isInteractive)
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard isInteractive, !isPainting else { return }
        let item = visibleItems[indexPath.item]
        if item.selectable {
            _ = selection.toggle(item.id)
            if let cell = collectionView.cellForItem(at: indexPath) as? ChapterSelectionCell {
                cell.configure(item: item, isSelected: selection.contains(item.id), isCompact: isCompact, isInteractive: isInteractive)
            }
            notifySelection()
        } else if let openAction = item.open {
            openAction()
        }
    }

    // MARK: - Swipe / Paint Selection Gestures

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard isInteractive else { return }
        let point = gesture.location(in: collectionView)
        switch gesture.state {
        case .began:
            beginPaint(at: point)
        case .changed:
            movePaint(to: point)
        case .ended:
            finishPaint(at: point)
        case .cancelled, .failed:
            cancelStroke()
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isInteractive, isPainting else { return }
        let point = gesture.location(in: collectionView)
        switch gesture.state {
        case .changed:
            movePaint(to: point)
        case .ended:
            finishPaint(at: point)
        case .cancelled, .failed:
            cancelStroke()
        default:
            break
        }
    }

    private func beginPaint(at point: CGPoint) {
        guard let indexPath = collectionView.indexPathForItem(at: point),
              indexPath.item < visibleItems.count else { return }
        let item = visibleItems[indexPath.item]
        guard item.selectable, selection.begin(item.id) else { return }

        isPainting = true
        collectionView.isScrollEnabled = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        refreshCell(id: item.id)
        notifySelection()
        startEdgeScroll(at: point)
    }

    private func movePaint(to point: CGPoint) {
        guard isPainting else { return }
        lastTouchY = point.y
        if let indexPath = collectionView.indexPathForItem(at: point),
           indexPath.item < visibleItems.count {
            let item = visibleItems[indexPath.item]
            if item.selectable && selection.visit(item.id) {
                refreshCell(id: item.id)
                notifySelection()
            }
        }
    }

    private func finishPaint(at point: CGPoint) {
        guard isPainting else { return }
        movePaint(to: point)
        stopEdgeScroll()
        isPainting = false
        collectionView.isScrollEnabled = true
        selection.finish()
        notifySelection()
    }

    public func cancelStroke() {
        guard isPainting else { return }
        stopEdgeScroll()
        isPainting = false
        collectionView.isScrollEnabled = true
        if selection.cancel() {
            collectionView.reloadData()
            notifySelection()
        }
    }

    private func refreshCell(id: String) {
        guard let pos = positions[id] else { return }
        let indexPath = IndexPath(item: pos, section: 0)
        if let cell = collectionView.cellForItem(at: indexPath) as? ChapterSelectionCell {
            let item = visibleItems[pos]
            cell.configure(item: item, isSelected: selection.contains(item.id), isCompact: isCompact, isInteractive: isInteractive)
        }
    }

    // MARK: - Edge Scrolling During Drag

    private func startEdgeScroll(at point: CGPoint) {
        lastTouchY = point.y
        stopEdgeScroll()
        displayLink = CADisplayLink(target: self, selector: #selector(edgeScrollTick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopEdgeScroll() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func edgeScrollTick() {
        guard isPainting, isInteractive else {
            stopEdgeScroll()
            return
        }
        let edgeThreshold: CGFloat = 36
        let bounds = collectionView.bounds
        let offsetY = collectionView.contentOffset.y
        let maxOffsetY = max(0, collectionView.contentSize.height - bounds.height)

        var deltaY: CGFloat = 0
        let visibleTouchY = lastTouchY - offsetY

        if visibleTouchY < edgeThreshold && offsetY > 0 {
            deltaY = -8
        } else if visibleTouchY > bounds.height - edgeThreshold && offsetY < maxOffsetY {
            deltaY = 8
        }

        if deltaY != 0 {
            let newOffset = CGPoint(x: 0, y: max(0, min(maxOffsetY, offsetY + deltaY)))
            collectionView.contentOffset = newOffset
            movePaint(to: CGPoint(x: bounds.midX, y: lastTouchY + deltaY))
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === longPressGesture && otherGestureRecognizer === panGesture {
            return true
        }
        return false
    }

    deinit {
        stopEdgeScroll()
    }
}

// MARK: - Chapter Selection Cell

final class ChapterSelectionCell: UICollectionViewCell {
    static let reuseIdentifier = "ChapterSelectionCell"

    private let boxView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }

    private func setupCell() {
        contentView.addSubview(boxView)
        boxView.translatesAutoresizingMaskIntoConstraints = false
        boxView.layer.cornerRadius = 8
        boxView.clipsToBounds = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        boxView.addSubview(stack)

        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.textAlignment = .center
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 11)

        badgeLabel.text = "已下载"
        badgeLabel.font = .systemFont(ofSize: 9, weight: .bold)
        badgeLabel.textColor = Palette.text3
        badgeLabel.backgroundColor = Palette.cardSoft
        badgeLabel.layer.cornerRadius = 4
        badgeLabel.clipsToBounds = true
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.isHidden = true
        boxView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            boxView.topAnchor.constraint(equalTo: contentView.topAnchor),
            boxView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            boxView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            boxView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: boxView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: boxView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: boxView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: boxView.trailingAnchor, constant: -4),

            badgeLabel.topAnchor.constraint(equalTo: boxView.topAnchor, constant: 2),
            badgeLabel.trailingAnchor.constraint(equalTo: boxView.trailingAnchor, constant: -2),
            badgeLabel.heightAnchor.constraint(equalToConstant: 14),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
    }

    func configure(item: ChapterSelectionGridView.Item, isSelected: Bool, isCompact: Bool, isInteractive: Bool) {
        accessibilityIdentifier = "chapter:\(item.id)"
        boxView.tag = item.id.hashValue

        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: isCompact ? 12 : 13, weight: isSelected ? .bold : .regular)
        titleLabel.numberOfLines = isCompact ? 1 : 2

        subtitleLabel.text = item.subtitle
        subtitleLabel.isHidden = isCompact || item.subtitle.isEmpty

        let enabled = isInteractive && (item.selectable || item.open != nil)
        isUserInteractionEnabled = enabled

        badgeLabel.isHidden = !item.isDownloaded

        if isSelected {
            boxView.backgroundColor = Palette.accent
            boxView.layer.borderColor = Palette.accent.cgColor
            boxView.layer.borderWidth = 1.0
            titleLabel.textColor = Palette.onAccent
            subtitleLabel.textColor = Palette.onAccent
        } else if item.selectable {
            boxView.backgroundColor = Palette.card
            boxView.layer.borderColor = Palette.border.cgColor
            boxView.layer.borderWidth = 0.5
            titleLabel.textColor = Palette.text
            subtitleLabel.textColor = Palette.text3
        } else {
            boxView.backgroundColor = Palette.cardSoft
            boxView.layer.borderColor = Palette.borderSoft.cgColor
            boxView.layer.borderWidth = 0.5
            titleLabel.textColor = Palette.text3
            subtitleLabel.textColor = Palette.text3
        }

        let fullDesc = (item.fullTitle.isEmpty || item.fullTitle == item.title) ? "" : "，原名 \(item.fullTitle)"
        let subDesc = item.subtitle.isEmpty ? "" : "，\(item.subtitle)"
        let stateDesc = item.isDownloaded ? "，已下载，不可选择" : (item.selectable ? (isSelected ? "，已选" : "，未选") : "，不可选择")
        accessibilityLabel = "\(item.title)\(fullDesc)\(subDesc)\(stateDesc)"
    }
}
