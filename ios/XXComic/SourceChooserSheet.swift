import UIKit
import ComicCore

@MainActor
final class SourceChooserSheetController: UIViewController {
    private let environment: AppEnvironment
    private var selectedSourceId: String
    var onSelectSource: ((any ComicSource) -> Void)?
    var onGroupChanged: (() -> Void)?
    var onManageSources: (() -> Void)?

    private let backdropView = UIView()
    private let panelView = UIView()
    private let dragHandle = UIView()
    private let titleLabel = UILabel()
    private let groupsButton = UIButton(type: .system)
    private let manageButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let groupChipsScroll = SourceOptionScrollView()
    private let groupChipsStack = UIStackView()
    private let searchField = UISearchTextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyView = UIStackView()
    private let emptyLabel = UILabel()
    private let emptyActionButton = UIButton(type: .system)

    private var panelBottomConstraint: NSLayoutConstraint!
    private var panelWidthConstraint: NSLayoutConstraint!
    private var panelHeightConstraint: NSLayoutConstraint!
    private var searchHeightConstraint: NSLayoutConstraint!
    private var searchTopConstraint: NSLayoutConstraint!

    private var groupSources: [any ComicSource] = []
    private var filteredSources: [any ComicSource] = []
    private var searchQuery: String = ""
    private var isClosing = false
    private var didScrollToInitialSource = false

    init(
        environment: AppEnvironment,
        selectedSourceId: String,
        onSelectSource: ((any ComicSource) -> Void)? = nil,
        onGroupChanged: (() -> Void)? = nil,
        onManageSources: (() -> Void)? = nil
    ) {
        self.environment = environment
        self.selectedSourceId = selectedSourceId
        self.onSelectSource = onSelectSource
        self.onGroupChanged = onGroupChanged
        self.onManageSources = onManageSources
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
        reloadData(scrollToSelected: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePanelDimensions()
        animateIn()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didScrollToInitialSource {
            didScrollToInitialSource = true
            scrollToSelectedSource(animated: true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePanelDimensions()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        panelView.layer.borderColor = Palette.borderSoft.cgColor
        searchField.layer.borderColor = Palette.borderSoft.cgColor
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
        panelView.accessibilityIdentifier = "source.chooser.sheet"
        view.addSubview(panelView)

        dragHandle.backgroundColor = Palette.border
        dragHandle.layer.cornerRadius = 2
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(dragHandle)

        titleLabel.text = "切换站源"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureHeaderPill(groupsButton, title: "分组", identifier: "source.chooser.groups", action: #selector(openGroupsTapped))
        configureHeaderPill(manageButton, title: "管理", identifier: "source.chooser.manage", action: #selector(openManageTapped))

        closeButton.setImage(ParityIcon.close.image(size: 15), for: .normal)
        closeButton.tintColor = Palette.secondaryText
        closeButton.backgroundColor = Palette.surface
        closeButton.layer.cornerRadius = 15
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.accessibilityIdentifier = "source.chooser.close"
        closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), groupsButton, manageButton, closeButton])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(headerRow)

        groupChipsScroll.showsHorizontalScrollIndicator = false
        groupChipsScroll.translatesAutoresizingMaskIntoConstraints = false
        groupChipsScroll.accessibilityIdentifier = "source.chooser.groupChips"
        panelView.addSubview(groupChipsScroll)

        groupChipsStack.axis = .horizontal
        groupChipsStack.spacing = 8
        groupChipsStack.alignment = .center
        groupChipsStack.translatesAutoresizingMaskIntoConstraints = false
        groupChipsScroll.addSubview(groupChipsStack)

        searchField.placeholder = "搜索站源名称..."
        searchField.font = .systemFont(ofSize: 14)
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.backgroundColor = Palette.surface
        searchField.layer.cornerRadius = 10
        searchField.layer.borderWidth = 0.5
        searchField.layer.borderColor = Palette.borderSoft.cgColor
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.accessibilityIdentifier = "source.chooser.search"
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        searchField.delegate = self
        panelView.addSubview(searchField)

        tableView.backgroundColor = .clear
        tableView.separatorColor = Palette.borderSoft
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 36, bottom: 0, right: 16)
        tableView.rowHeight = 50
        tableView.keyboardDismissMode = .onDrag
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SourceChooserRowCell.self, forCellReuseIdentifier: SourceChooserRowCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.accessibilityIdentifier = "source.chooser.list"
        panelView.addSubview(tableView)

        emptyView.axis = .vertical
        emptyView.alignment = .center
        emptyView.spacing = 10
        emptyView.isHidden = true
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(emptyView)

        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = Palette.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0

        emptyActionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        emptyActionButton.setTitleColor(Palette.accentText, for: .normal)
        emptyActionButton.backgroundColor = Palette.accentSoft
        emptyActionButton.layer.cornerRadius = 14
        emptyActionButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        emptyActionButton.addTarget(self, action: #selector(emptyActionTapped), for: .touchUpInside)

        emptyView.addArrangedSubview(emptyLabel)
        emptyView.addArrangedSubview(emptyActionButton)

        panelWidthConstraint = panelView.widthAnchor.constraint(equalToConstant: view.bounds.width)
        panelHeightConstraint = panelView.heightAnchor.constraint(equalToConstant: 460)
        panelBottomConstraint = panelView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 600)
        searchTopConstraint = searchField.topAnchor.constraint(equalTo: groupChipsScroll.bottomAnchor, constant: 10)
        searchHeightConstraint = searchField.heightAnchor.constraint(equalToConstant: 36)

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

            groupChipsScroll.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 12),
            groupChipsScroll.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 16),
            groupChipsScroll.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -16),
            groupChipsScroll.heightAnchor.constraint(equalToConstant: 34),

            groupChipsStack.topAnchor.constraint(equalTo: groupChipsScroll.topAnchor),
            groupChipsStack.bottomAnchor.constraint(equalTo: groupChipsScroll.bottomAnchor),
            groupChipsStack.leadingAnchor.constraint(equalTo: groupChipsScroll.leadingAnchor),
            groupChipsStack.trailingAnchor.constraint(equalTo: groupChipsScroll.trailingAnchor),
            groupChipsStack.heightAnchor.constraint(equalTo: groupChipsScroll.heightAnchor),

            searchTopConstraint,
            searchField.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -16),
            searchHeightConstraint,

            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: panelView.safeAreaLayoutGuide.bottomAnchor, constant: -4),

            emptyView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyView.leadingAnchor.constraint(greaterThanOrEqualTo: panelView.leadingAnchor, constant: 24),
            emptyView.trailingAnchor.constraint(lessThanOrEqualTo: panelView.trailingAnchor, constant: -24)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panelView.addGestureRecognizer(pan)
    }

    private func configureHeaderPill(_ button: UIButton, title: String, identifier: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.setTitleColor(Palette.accentText, for: .normal)
        button.backgroundColor = Palette.accentSoft
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func updatePanelDimensions() {
        let maxW: CGFloat = traitCollection.horizontalSizeClass == .regular ? 560 : view.bounds.width
        panelWidthConstraint.constant = min(view.bounds.width, maxW)
        let maxH = min(max(320, view.bounds.height * 0.80), 660)
        let rowCount = max(3, filteredSources.count)
        let searchAddon: CGFloat = searchField.isHidden ? 0 : 46
        let desired = min(maxH, 136 + searchAddon + CGFloat(rowCount) * 50 + view.safeAreaInsets.bottom)
        panelHeightConstraint.constant = max(300, desired)
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

    private func reloadData(scrollToSelected: Bool) {
        rebuildGroupChips()
        groupSources = environment.discoverySources
        let showSearch = groupSources.count > 6 || !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        searchField.isHidden = !showSearch
        searchTopConstraint.constant = showSearch ? 10 : 0
        searchHeightConstraint.constant = showSearch ? 36 : 0

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredSources = groupSources
        } else {
            filteredSources = groupSources.filter {
                $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query)
            }
        }

        if filteredSources.isEmpty {
            emptyView.isHidden = false
            tableView.isHidden = true
            if !query.isEmpty {
                emptyLabel.text = "没有匹配“\(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))”的站源"
                emptyActionButton.setTitle("清空搜索", for: .normal)
            } else if environment.sourceGroupStore.selectedId != SourceGroupStore.allId {
                emptyLabel.text = "当前站源分组暂无可用站源"
                emptyActionButton.setTitle("切换回全部分组", for: .normal)
            } else {
                emptyLabel.text = "暂无已启用的发现站源"
                emptyActionButton.setTitle("管理站源", for: .normal)
            }
        } else {
            emptyView.isHidden = true
            tableView.isHidden = false
        }

        tableView.reloadData()
        updatePanelDimensions()
        if scrollToSelected {
            scrollToSelectedSource(animated: true)
        }
    }

    private func rebuildGroupChips() {
        groupChipsStack.arrangedSubviews.forEach {
            groupChipsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let selectedGroupId = environment.sourceGroupStore.selectedId
        for group in environment.sourceGroupStore.groups {
            let active = group.id == selectedGroupId
            let chip = UIButton(type: .system)
            chip.setTitle(group.name, for: .normal)
            chip.titleLabel?.font = .systemFont(ofSize: 13, weight: active ? .semibold : .medium)
            chip.setTitleColor(active ? Palette.onAccent : Palette.secondaryText, for: .normal)
            chip.backgroundColor = active ? Palette.accent : Palette.surface
            chip.layer.cornerRadius = 15
            chip.layer.borderWidth = 0.5
            chip.layer.borderColor = (active ? Palette.accent : Palette.borderSoft).cgColor
            chip.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            chip.accessibilityIdentifier = "source.chooser.group.\(group.id)"
            chip.accessibilityLabel = group.name
            chip.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                do {
                    try self.environment.sourceGroupStore.select(id: group.id)
                    self.reloadData(scrollToSelected: true)
                    self.onGroupChanged?()
                } catch {
                    RemToastView.show(message: error.localizedDescription, kind: .error, in: self)
                }
            }, for: .touchUpInside)
            groupChipsStack.addArrangedSubview(chip)
        }
    }

    private func scrollToSelectedSource(animated: Bool) {
        guard let idx = filteredSources.firstIndex(where: { $0.id == selectedSourceId }) else { return }
        let path = IndexPath(row: idx, section: 0)
        tableView.scrollToRow(at: path, at: .middle, animated: animated)
    }

    @objc private func searchTextChanged() {
        searchQuery = searchField.text ?? ""
        reloadData(scrollToSelected: false)
    }

    @objc private func openGroupsTapped() {
        let sheet = SourceGroupSheet(environment: environment)
        sheet.onGroupSelected = { [weak self] _ in
            self?.reloadData(scrollToSelected: true)
            self?.onGroupChanged?()
        }
        sheet.onGroupsChanged = { [weak self] in
            self?.reloadData(scrollToSelected: true)
            self?.onGroupChanged?()
        }
        present(sheet, animated: true)
    }

    @objc private func openManageTapped() {
        animateOut { [weak self] in
            self?.onManageSources?()
        }
    }

    @objc private func emptyActionTapped() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            searchQuery = ""
            searchField.text = nil
            reloadData(scrollToSelected: true)
        } else if environment.sourceGroupStore.selectedId != SourceGroupStore.allId {
            do {
                try environment.sourceGroupStore.select(id: SourceGroupStore.allId)
                reloadData(scrollToSelected: true)
                onGroupChanged?()
            } catch {
                RemToastView.show(message: error.localizedDescription, kind: .error, in: self)
            }
        } else {
            openManageTapped()
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

extension SourceChooserSheetController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredSources.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: SourceChooserRowCell.reuseId, for: indexPath) as? SourceChooserRowCell else {
            return UITableViewCell()
        }
        let source = filteredSources[indexPath.row]
        let isSelected = source.id == selectedSourceId
        let requiresVpn = environment.requiresVpn(sourceId: source.id)
        let isRule = source is ScriptComicSource || source is FailoverComicSource
        cell.configure(source: source, isSelected: isSelected, requiresVpn: requiresVpn, isRuleSource: isRule)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let chosen = filteredSources[indexPath.row]
        selectedSourceId = chosen.id
        animateOut { [weak self] in
            self?.onSelectSource?(chosen)
        }
    }
}

extension SourceChooserSheetController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - SourceChooserRowCell

@MainActor
private final class SourceChooserRowCell: UITableViewCell {
    static let reuseId = "SourceChooserRowCell"

    private let statusDot = UIView()
    private let nameLabel = UILabel()
    private let vpnBadge = SourceVpnBadgeView()
    private let tagLabel = UILabel()
    private let checkImage = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    private func setup() {
        backgroundColor = .clear
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = Palette.surface

        statusDot.layer.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
        nameLabel.textColor = Palette.text
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        vpnBadge.translatesAutoresizingMaskIntoConstraints = false

        tagLabel.font = .systemFont(ofSize: 10, weight: .medium)
        tagLabel.textColor = Palette.secondaryText
        tagLabel.backgroundColor = Palette.surface
        tagLabel.layer.cornerRadius = 4
        tagLabel.layer.masksToBounds = true
        tagLabel.textAlignment = .center
        tagLabel.translatesAutoresizingMaskIntoConstraints = false

        checkImage.image = ParityIcon.check.image(size: 15)
        checkImage.tintColor = Palette.accent
        checkImage.contentMode = .scaleAspectFit
        checkImage.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [statusDot, nameLabel, vpnBadge, tagLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        contentView.addSubview(checkImage)

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            tagLabel.heightAnchor.constraint(equalToConstant: 18),
            tagLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: checkImage.leadingAnchor, constant: -10),

            checkImage.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkImage.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkImage.widthAnchor.constraint(equalToConstant: 18),
            checkImage.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func configure(source: any ComicSource, isSelected: Bool, requiresVpn: Bool, isRuleSource: Bool) {
        nameLabel.text = source.name
        nameLabel.font = .systemFont(ofSize: 15, weight: isSelected ? .bold : .medium)
        nameLabel.textColor = isSelected ? Palette.accentText : Palette.text

        statusDot.backgroundColor = requiresVpn ? UIColor.systemOrange : Palette.green
        vpnBadge.isHidden = !requiresVpn

        if source.hasBackupFailover {
            tagLabel.text = " 多线 "
            tagLabel.isHidden = false
        } else if isRuleSource {
            tagLabel.text = " 规则 "
            tagLabel.isHidden = false
        } else if !source.supportsSearch {
            tagLabel.text = " 仅发现 "
            tagLabel.isHidden = false
        } else {
            tagLabel.isHidden = true
            tagLabel.text = nil
        }

        checkImage.isHidden = !isSelected
        backgroundColor = isSelected ? Palette.accentSoft.withAlphaComponent(0.35) : .clear

        accessibilityIdentifier = "source.chooser.item.\(source.id)"
        accessibilityLabel = source.name
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
