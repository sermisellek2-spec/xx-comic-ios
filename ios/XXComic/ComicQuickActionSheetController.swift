import UIKit
import ComicCore

/// Bottom modal quick-action sheet for comic cards across discovery, search, bookshelf, and detail entry points.
@MainActor
final class ComicQuickActionSheetController: UIViewController {
    static let maxActionsPerRow = 4

    private struct ActionItem {
        let id: String
        let label: String
        let icon: ParityIcon
        let isDanger: Bool
        let isAccent: Bool
        let handler: () -> Void
    }

    private let comic: ComicSummary
    private let sourceName: String
    private let referer: String
    private let library: LocalLibrary
    private let isFavorite: Bool
    private let showNotInterested: Bool
    private let allowRemoveFromShelf: Bool
    private let onToggleFavorite: () -> Void
    private let onSwitchSource: () -> Void
    private let onNotInterested: (() -> Void)?
    private let onBlacklist: () -> Void
    private let onRemoveFromShelf: (() -> Void)?

    private let backdropView = UIView()
    private let panelView = UIView()
    private let coverView = RemoteImageView()
    private var panelBottomConstraint: NSLayoutConstraint!
    private var panelWidthConstraint: NSLayoutConstraint!
    private var isClosing = false

    init(
        comic: ComicSummary,
        sourceName: String,
        referer: String,
        library: LocalLibrary,
        isFavorite: Bool,
        showNotInterested: Bool = false,
        allowRemoveFromShelf: Bool = false,
        onToggleFavorite: @escaping () -> Void,
        onSwitchSource: @escaping () -> Void,
        onNotInterested: (() -> Void)? = nil,
        onBlacklist: @escaping () -> Void,
        onRemoveFromShelf: (() -> Void)? = nil
    ) {
        self.comic = comic
        self.sourceName = sourceName
        self.referer = referer
        self.library = library
        self.isFavorite = isFavorite
        self.showNotInterested = showNotInterested
        self.allowRemoveFromShelf = allowRemoveFromShelf
        self.onToggleFavorite = onToggleFavorite
        self.onSwitchSource = onSwitchSource
        self.onNotInterested = onNotInterested
        self.onBlacklist = onBlacklist
        self.onRemoveFromShelf = onRemoveFromShelf
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePanelWidth()
        animateIn()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePanelWidth()
    }

    private func updatePanelWidth() {
        let maxW: CGFloat = traitCollection.horizontalSizeClass == .regular ? 520 : view.bounds.width
        panelWidthConstraint.constant = min(view.bounds.width, maxW)
    }

    private func setupUI() {
        backdropView.backgroundColor = Palette.scrim
        backdropView.alpha = 0
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        view.addSubview(backdropView)

        panelView.backgroundColor = Palette.card
        panelView.layer.cornerRadius = 16
        panelView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panelView.clipsToBounds = true
        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.accessibilityIdentifier = "quickAction.sheet"
        view.addSubview(panelView)

        let handleHost = UIView()
        handleHost.translatesAutoresizingMaskIntoConstraints = false
        let handle = UIView()
        handle.backgroundColor = Palette.border
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false
        handleHost.addSubview(handle)

        let header = buildHeader()
        let divider = UIView()
        divider.backgroundColor = Palette.borderSoft
        divider.translatesAutoresizingMaskIntoConstraints = false

        let grid = buildActionGrid()

        let stack = UIStackView(arrangedSubviews: [handleHost, header, divider, grid])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(stack)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        handleHost.addGestureRecognizer(pan)
        let headerPan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        header.addGestureRecognizer(headerPan)

        panelBottomConstraint = panelView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 320)
        panelWidthConstraint = panelView.widthAnchor.constraint(equalToConstant: min(view.bounds.width, 520))

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panelView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panelWidthConstraint,
            panelBottomConstraint,

            handleHost.heightAnchor.constraint(equalToConstant: 16),
            handle.centerXAnchor.constraint(equalTo: handleHost.centerXAnchor),
            handle.centerYAnchor.constraint(equalTo: handleHost.centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: 32),
            handle.heightAnchor.constraint(equalToConstant: 4),

            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            stack.topAnchor.constraint(equalTo: panelView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func buildHeader() -> UIView {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false

        coverView.backgroundColor = Palette.placeholder
        coverView.layer.cornerRadius = 6
        coverView.layer.borderWidth = 1 / UIScreen.main.scale
        coverView.layer.borderColor = Palette.borderSoft.cgColor
        coverView.clipsToBounds = true
        coverView.contentMode = .scaleAspectFill
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.loadCover(comic, referer: referer, library: library)

        let titleLabel = UILabel()
        titleLabel.text = comic.title.isEmpty ? "漫画" : comic.title
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        let sourceLabel = UILabel()
        sourceLabel.text = sourceName
        sourceLabel.font = .systemFont(ofSize: 12)
        sourceLabel.textColor = Palette.text3
        sourceLabel.numberOfLines = 1
        sourceLabel.isHidden = sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let textStack = UIStackView(arrangedSubviews: [titleLabel, sourceLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(coverView)
        header.addSubview(textStack)

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            coverView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            coverView.topAnchor.constraint(equalTo: header.topAnchor, constant: 4),
            coverView.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
            coverView.widthAnchor.constraint(equalToConstant: 30),
            coverView.heightAnchor.constraint(equalToConstant: 40),

            textStack.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18),
            textStack.centerYAnchor.constraint(equalTo: coverView.centerYAnchor)
        ])
        return header
    }

    private func buildActionGrid() -> UIView {
        let items = buildActionItems()
        let rows = stride(from: 0, to: items.count, by: Self.maxActionsPerRow).map {
            Array(items[$0..<min($0 + Self.maxActionsPerRow, items.count)])
        }
        let cols = rows.count > 1 ? Self.maxActionsPerRow : max(1, items.count)
        let horizontalPad: CGFloat = cols >= 4 ? 12 : 16
        let gap: CGFloat = cols >= 4 ? 6 : 10

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 10
        grid.isLayoutMarginsRelativeArrangement = true
        grid.layoutMargins = UIEdgeInsets(top: 16, left: horizontalPad, bottom: 20, right: horizontalPad)

        for rowItems in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = gap
            for col in 0..<cols {
                if col < rowItems.count {
                    rowStack.addArrangedSubview(buildActionButton(rowItems[col], compact: cols >= 4))
                } else {
                    let spacer = UIView()
                    spacer.isUserInteractionEnabled = false
                    spacer.isAccessibilityElement = false
                    spacer.alpha = 0
                    rowStack.addArrangedSubview(spacer)
                }
            }
            grid.addArrangedSubview(rowStack)
        }
        return grid
    }

    private func buildActionItems() -> [ActionItem] {
        var items: [ActionItem] = [
            ActionItem(
                id: "favorite",
                label: isFavorite ? "取消收藏" : "收藏",
                icon: isFavorite ? .favoriteFill : .favorite,
                isDanger: false,
                isAccent: isFavorite,
                handler: onToggleFavorite
            ),
            ActionItem(
                id: "switchSource",
                label: "换源",
                icon: .source,
                isDanger: false,
                isAccent: true,
                handler: onSwitchSource
            )
        ]
        if showNotInterested, let onNotInterested {
            items.append(ActionItem(
                id: "notInterested",
                label: "不感兴趣",
                icon: .eyeOff,
                isDanger: false,
                isAccent: false,
                handler: onNotInterested
            ))
        }
        items.append(ActionItem(
            id: "blacklist",
            label: "拉黑",
            icon: .blacklist,
            isDanger: true,
            isAccent: false,
            handler: onBlacklist
        ))
        if allowRemoveFromShelf, let onRemoveFromShelf {
            items.append(ActionItem(
                id: "removeFromShelf",
                label: "从书架移除",
                icon: .trash,
                isDanger: true,
                isAccent: false,
                handler: onRemoveFromShelf
            ))
        }
        return items
    }

    private func buildActionButton(_ item: ActionItem, compact: Bool) -> UIView {
        let button = QuickActionTileButton(
            label: item.label,
            icon: item.icon,
            iconColor: item.isDanger ? Palette.danger : (item.isAccent ? Palette.accent : Palette.text),
            textColor: item.isDanger ? Palette.danger : Palette.text,
            horizontalPadding: compact ? 2 : 6
        )
        button.accessibilityIdentifier = "quickAction.\(item.id)"
        button.accessibilityLabel = item.label
        button.addAction(UIAction { [weak self] _ in
            self?.dismissAndRun(item.handler)
        }, for: .touchUpInside)
        return button
    }

    private func dismissAndRun(_ action: @escaping () -> Void) {
        guard !isClosing else { return }
        isClosing = true
        dismiss(animated: false) {
            action()
        }
    }

    @objc private func dismissTapped() {
        closeWithAnimation()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: panelView)
        switch recognizer.state {
        case .changed:
            panelView.transform = CGAffineTransform(translationX: 0, y: max(0, translation.y))
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: panelView).y
            if translation.y > 60 || velocity > 500 {
                closeWithAnimation()
            } else {
                let dur = UIAccessibility.isReduceMotionEnabled ? 0.0 : 0.16
                UIView.animate(withDuration: dur, delay: 0, options: [.curveEaseOut]) {
                    self.panelView.transform = .identity
                }
            }
        default:
            break
        }
    }

    private func animateIn() {
        panelBottomConstraint.constant = 0
        let skip = UIAccessibility.isReduceMotionEnabled || isUITesting
        if skip {
            backdropView.alpha = 1
            view.layoutIfNeeded()
            return
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.backdropView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    private func closeWithAnimation() {
        guard !isClosing else { return }
        isClosing = true
        let skip = UIAccessibility.isReduceMotionEnabled || isUITesting
        if skip {
            dismiss(animated: false)
            return
        }
        panelBottomConstraint.constant = max(200, panelView.bounds.height + 40)
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseIn]) {
            self.backdropView.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }

    private var isUITesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        return false
        #endif
    }
}

@MainActor
private final class QuickActionTileButton: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    init(label: String, icon: ParityIcon, iconColor: UIColor, textColor: UIColor, horizontalPadding: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Palette.cardSoft
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = Palette.borderSoft.cgColor
        isAccessibilityElement = true
        accessibilityTraits = .button

        iconView.image = icon.image(size: 22)
        iconView.tintColor = iconColor
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = label
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = textColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 5
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 62),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? Palette.accentSoft : Palette.cardSoft
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = Palette.borderSoft.resolvedColor(with: traitCollection).cgColor
    }
}
