import UIKit
import ComicCore

@MainActor
final class RecommendRankSheetController: UIViewController {
    private let environment: AppEnvironment
    private var items: [RecommendItem]
    var onSelect: ((RecommendItem) -> Void)?
    var onLongPress: ((RecommendItem) -> Void)?

    private let backdropView = UIView()
    private let panelView = UIView()
    private let dragHandle = UIView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private var panelBottomConstraint: NSLayoutConstraint!
    private var panelWidthConstraint: NSLayoutConstraint!
    private var panelHeightConstraint: NSLayoutConstraint!
    private var isClosing = false

    init(
        environment: AppEnvironment,
        items: [RecommendItem],
        onSelect: ((RecommendItem) -> Void)? = nil,
        onLongPress: ((RecommendItem) -> Void)? = nil
    ) {
        self.environment = environment
        self.items = Array(items.prefix(RecommendConstants.expandedHotRankItems))
        self.onSelect = onSelect
        self.onLongPress = onLongPress
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
        refreshEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePanelDimensions()
        animateIn()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePanelDimensions()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        panelView.layer.borderColor = Palette.borderSoft.cgColor
    }

    func updateItems(_ nextItems: [RecommendItem]) {
        self.items = Array(nextItems.prefix(RecommendConstants.expandedHotRankItems))
        countLabel.text = items.isEmpty ? "" : "共 \(items.count) 部"
        tableView.reloadData()
        refreshEmptyState()
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
        panelView.layer.borderWidth = 0.5
        panelView.layer.borderColor = Palette.borderSoft.cgColor
        panelView.clipsToBounds = true
        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.accessibilityIdentifier = "recommend.rank.sheet"
        view.addSubview(panelView)

        dragHandle.backgroundColor = Palette.border
        dragHandle.layer.cornerRadius = 2
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(dragHandle)

        titleLabel.text = "全网热门排行"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = Palette.text

        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = Palette.secondaryText
        countLabel.text = items.isEmpty ? "" : "共 \(items.count) 部"

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        titleStack.axis = .horizontal
        titleStack.alignment = .firstBaseline
        titleStack.spacing = 8

        closeButton.setImage(ParityIcon.close.image(size: 15), for: .normal)
        closeButton.tintColor = Palette.secondaryText
        closeButton.backgroundColor = Palette.surface
        closeButton.layer.cornerRadius = 15
        closeButton.accessibilityIdentifier = "recommend.rank.close"
        closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [titleStack, UIView(), closeButton])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(headerRow)

        tableView.backgroundColor = .clear
        tableView.separatorColor = Palette.borderSoft
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 16)
        tableView.rowHeight = 64
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(RecommendRankSheetCell.self, forCellReuseIdentifier: RecommendRankSheetCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.accessibilityIdentifier = "recommend.rank.list"
        panelView.addSubview(tableView)

        emptyLabel.text = "暂无热门排行数据"
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = Palette.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(emptyLabel)

        panelWidthConstraint = panelView.widthAnchor.constraint(equalToConstant: view.bounds.width)
        panelHeightConstraint = panelView.heightAnchor.constraint(equalToConstant: 520)
        panelBottomConstraint = panelView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 700)

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panelView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panelBottomConstraint,
            panelWidthConstraint,
            panelHeightConstraint,

            dragHandle.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 10),
            dragHandle.centerXAnchor.constraint(equalTo: panelView.centerXAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 36),
            dragHandle.heightAnchor.constraint(equalToConstant: 4),

            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            headerRow.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: 10),
            headerRow.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 16),
            headerRow.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: panelView.safeAreaLayoutGuide.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panelView.addGestureRecognizer(pan)
    }

    private func refreshEmptyState() {
        emptyLabel.isHidden = !items.isEmpty
        tableView.isHidden = items.isEmpty
    }

    private func updatePanelDimensions() {
        let maxW: CGFloat = traitCollection.horizontalSizeClass == .regular ? 580 : view.bounds.width
        panelWidthConstraint.constant = min(view.bounds.width, maxW)
        panelHeightConstraint.constant = min(max(360, view.bounds.height * 0.84), 680)
    }

    private func animateIn() {
        panelBottomConstraint.constant = 0
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.backdropView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    private func animateOut(completion: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        panelBottomConstraint.constant = panelHeightConstraint.constant + 40
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
            self.backdropView.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }

    @objc private func dismissTapped() {
        animateOut()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: panelView)
        switch gesture.state {
        case .changed:
            if translation.y > 0 {
                panelBottomConstraint.constant = translation.y
            }
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: panelView).y
            if translation.y > 120 || velocity > 800 {
                animateOut()
            } else {
                panelBottomConstraint.constant = 0
                UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
            }
        default:
            break
        }
    }
}

extension RecommendRankSheetController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: RecommendRankSheetCell.reuseId,
            for: indexPath
        ) as? RecommendRankSheetCell else {
            return UITableViewCell()
        }
        let item = items[indexPath.row]
        let referer = environment.allSources.first(where: { $0.id == item.summary.sourceId })?.referer(forUrl: item.summary.coverUrl) ?? ""
        cell.configure(
            rank: indexPath.row + 1,
            item: item,
            referer: referer,
            library: environment.localLibrary
        ) { [weak self] in
            self?.onLongPress?(item)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        animateOut { [weak self] in
            self?.onSelect?(item)
        }
    }
}

@MainActor
private final class RecommendRankSheetCell: UITableViewCell {
    static let reuseId = "RecommendRankSheetCell"

    private let rowView = RecommendHotRankRowView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        rowView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowView)
        NSLayoutConstraint.activate([
            rowView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            rowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            rowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    func configure(
        rank: Int,
        item: RecommendItem,
        referer: String,
        library: LocalLibrary,
        onLongPress: @escaping () -> Void
    ) {
        rowView.configure(
            rank: rank,
            item: item,
            referer: referer,
            library: library,
            onTap: {},
            onLongPress: onLongPress
        )
        // Row taps are handled by UITableView didSelectRowAt so gestures do not conflict.
        rowView.gestureRecognizers?.forEach {
            if $0 is UITapGestureRecognizer {
                $0.isEnabled = false
            }
        }
        accessibilityIdentifier = "recommend.rank.item.\(rank)"
        accessibilityLabel = "\(rank). \(item.summary.title)"
    }
}
