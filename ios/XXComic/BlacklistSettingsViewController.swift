import UIKit
import ComicCore

/// Management page for "设置 › 黑名单列表": search filtering, single restore,
/// swipe-to-restore, multi-select batch edit with sticky footer, and Rem empty/corrupt states.
@MainActor
final class BlacklistSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let environment: AppEnvironment
    private var allEntries: [BlacklistEntry] = []
    private var visibleEntries: [BlacklistEntry] = []
    private var selectedKeys = Set<String>()
    private var isEditMode = false
    private var searchQuery = ""
    private var blacklistObserver: NSObjectProtocol?

    private let searchContainer = UIView()
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyScroll = UIScrollView()
    private let emptyImage = UIImageView()
    private let emptyTitle = UILabel()
    private let emptyDesc = UILabel()
    private let emptyActionButton = UIButton(type: .system)

    private let stickyFooter = UIView()
    private let selectionCountLabel = UILabel()
    private let selectAllButton = UIButton(type: .system)
    private let restoreAllButton = UIButton(type: .system)
    private let restoreSelectedButton = UIButton(type: .system)
    private var tableBottomToViewConstraint: NSLayoutConstraint!
    private var tableBottomToFooterConstraint: NSLayoutConstraint!
    private var editBarItem: UIBarButtonItem?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    deinit {
        if let blacklistObserver {
            NotificationCenter.default.removeObserver(blacklistObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        setupNavigation()
        setupViews()
        setupEmptyState()
        setupStickyFooter()
        observeBlacklist()
        reloadFromStore()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        SecondaryHeaderBar.configureNavigationBarAppearance(for: navigationController)
        reloadFromStore()
    }

    private func setupNavigation() {
        SecondaryHeaderBar.apply(to: self, title: "黑名单列表", meta: "0 部")
        let editItem = SecondaryHeaderBar.textButton(
            title: "编辑",
            accessibilityIdentifier: "blacklist.edit",
            target: self,
            action: #selector(toggleEditMode)
        )
        editBarItem = editItem
        navigationItem.rightBarButtonItem = editItem
    }

    private func setupViews() {
        searchContainer.backgroundColor = Palette.background
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchContainer)

        searchBar.placeholder = "搜索已拉黑的漫画或站源"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.accessibilityIdentifier = "blacklist.search"
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchBar)

        tableView.backgroundColor = Palette.background
        tableView.separatorColor = Palette.borderSoft
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(BlacklistEntryCell.self, forCellReuseIdentifier: BlacklistEntryCell.reuseId)
        tableView.accessibilityIdentifier = "blacklist.list"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            searchBar.topAnchor.constraint(equalTo: searchContainer.topAnchor, constant: 2),
            searchBar.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: -2),
            searchBar.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupEmptyState() {
        emptyScroll.translatesAutoresizingMaskIntoConstraints = false
        emptyScroll.alwaysBounceVertical = true
        emptyScroll.keyboardDismissMode = .onDrag
        emptyScroll.isHidden = true
        emptyScroll.accessibilityIdentifier = "blacklist.empty"
        view.addSubview(emptyScroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyScroll.addSubview(stack)

        emptyImage.contentMode = .scaleAspectFit
        AppIllustrationCache.bind(emptyImage, assetName: "rem_empty", maxSideDp: 148)
        emptyImage.translatesAutoresizingMaskIntoConstraints = false

        emptyTitle.font = .systemFont(ofSize: 16, weight: .bold)
        emptyTitle.textColor = Palette.text
        emptyTitle.textAlignment = .center
        emptyTitle.numberOfLines = 0

        emptyDesc.font = .systemFont(ofSize: 13)
        emptyDesc.textColor = Palette.text3
        emptyDesc.textAlignment = .center
        emptyDesc.numberOfLines = 0

        emptyActionButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        emptyActionButton.setTitleColor(Palette.onAccent, for: .normal)
        emptyActionButton.backgroundColor = Palette.accent
        emptyActionButton.layer.cornerRadius = 8
        emptyActionButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        emptyActionButton.addTarget(self, action: #selector(emptyActionTapped), for: .touchUpInside)
        emptyActionButton.isHidden = true

        stack.addArrangedSubview(emptyImage)
        stack.addArrangedSubview(emptyTitle)
        stack.addArrangedSubview(emptyDesc)
        stack.addArrangedSubview(emptyActionButton)
        stack.setCustomSpacing(14, after: emptyDesc)

        NSLayoutConstraint.activate([
            emptyScroll.topAnchor.constraint(equalTo: searchContainer.bottomAnchor),
            emptyScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyScroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: emptyScroll.frameLayoutGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyScroll.frameLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyScroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyScroll.frameLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            emptyImage.widthAnchor.constraint(equalToConstant: 142),
            emptyImage.heightAnchor.constraint(equalToConstant: 142)
        ])
    }

    private func setupStickyFooter() {
        stickyFooter.backgroundColor = Palette.card
        stickyFooter.isHidden = true
        stickyFooter.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stickyFooter)

        let topBorder = UIView()
        topBorder.backgroundColor = Palette.borderSoft
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        stickyFooter.addSubview(topBorder)

        selectionCountLabel.text = "已选 0 部"
        selectionCountLabel.font = .systemFont(ofSize: 13, weight: .medium)
        selectionCountLabel.textColor = Palette.text2

        selectAllButton.setTitle("全选", for: .normal)
        selectAllButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        selectAllButton.setTitleColor(Palette.accentText, for: .normal)
        selectAllButton.backgroundColor = Palette.accentSoft
        selectAllButton.layer.cornerRadius = 14
        selectAllButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        selectAllButton.addTarget(self, action: #selector(toggleSelectAllTapped), for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [selectionCountLabel, UIView(), selectAllButton])
        topRow.axis = .horizontal
        topRow.alignment = .center

        restoreAllButton.setTitle("恢复全部", for: .normal)
        restoreAllButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        restoreAllButton.setTitleColor(Palette.text, for: .normal)
        restoreAllButton.backgroundColor = Palette.cardSoft
        restoreAllButton.layer.cornerRadius = 8
        restoreAllButton.layer.borderWidth = 1
        restoreAllButton.layer.borderColor = Palette.border.cgColor
        restoreAllButton.accessibilityIdentifier = "blacklist.clear"
        restoreAllButton.addTarget(self, action: #selector(confirmRestoreAllTapped), for: .touchUpInside)

        restoreSelectedButton.setTitle("恢复选中", for: .normal)
        restoreSelectedButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        restoreSelectedButton.setTitleColor(Palette.onAccent, for: .normal)
        restoreSelectedButton.backgroundColor = Palette.accent
        restoreSelectedButton.layer.cornerRadius = 8
        restoreSelectedButton.addTarget(self, action: #selector(restoreSelectedTapped), for: .touchUpInside)

        let actionRow = UIStackView(arrangedSubviews: [restoreAllButton, restoreSelectedButton])
        actionRow.axis = .horizontal
        actionRow.distribution = .fillEqually
        actionRow.spacing = 10

        let contentStack = UIStackView(arrangedSubviews: [topRow, actionRow])
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        stickyFooter.addSubview(contentStack)

        tableBottomToViewConstraint = tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        tableBottomToFooterConstraint = tableView.bottomAnchor.constraint(equalTo: stickyFooter.topAnchor)

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: stickyFooter.topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: stickyFooter.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: stickyFooter.trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            tableBottomToViewConstraint,

            stickyFooter.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stickyFooter.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stickyFooter.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: stickyFooter.topAnchor, constant: 10),
            contentStack.leadingAnchor.constraint(equalTo: stickyFooter.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: stickyFooter.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            restoreAllButton.heightAnchor.constraint(equalToConstant: 40),
            restoreSelectedButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func observeBlacklist() {
        blacklistObserver = NotificationCenter.default.addObserver(
            forName: AppEnvironment.blacklistChanged,
            object: environment,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromStore()
            }
        }
    }

    private func reloadFromStore() {
        allEntries = environment.blacklistStore.listEntries()
        let validKeys = Set(allEntries.map(\.normalizedTitle))
        selectedKeys = selectedKeys.intersection(validKeys)
        if allEntries.isEmpty || environment.blacklistStore.isCorrupted {
            isEditMode = false
            selectedKeys.removeAll()
        }
        applyFilterAndRender()
    }

    private func applyFilterAndRender() {
        SecondaryHeaderBar.updateMeta("\(allEntries.count) 部", on: self)

        let canEdit = !allEntries.isEmpty && !environment.blacklistStore.isCorrupted
        SecondaryHeaderBar.updateTextButton(editBarItem, title: isEditMode ? "完成" : "编辑", isHidden: !canEdit)
        navigationItem.rightBarButtonItem = canEdit ? editBarItem : nil

        if environment.blacklistStore.isCorrupted {
            searchContainer.isHidden = true
            tableView.isHidden = true
            emptyScroll.isHidden = false
            emptyTitle.text = "黑名单数据读取异常"
            emptyDesc.text = "原文件已保留为备份。可清空并重建黑名单，之后即可正常拉黑或恢复漫画。"
            emptyActionButton.setTitle("清空并重建", for: .normal)
            emptyActionButton.isHidden = false
            updateStickyFooter()
            return
        }

        if allEntries.isEmpty {
            searchContainer.isHidden = true
            tableView.isHidden = true
            emptyScroll.isHidden = false
            emptyTitle.text = "黑名单是空的"
            emptyDesc.text = "在书架、发现、推荐或搜索页长按漫画并选择「拉黑」后，漫画会显示在这里；可随时单条恢复，或点击右上角「编辑」批量恢复。"
            emptyActionButton.isHidden = true
            updateStickyFooter()
            return
        }

        searchContainer.isHidden = false
        let rawQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerQuery = rawQuery.lowercased()
        let normQuery = ComicTitleNormalizer.normalize(rawQuery)
        if lowerQuery.isEmpty {
            visibleEntries = allEntries
        } else {
            visibleEntries = allEntries.filter { entry in
                let groupLabel = resolveGroupLabel(for: entry)
                if entry.displayTitle.lowercased().contains(lowerQuery)
                    || entry.normalizedTitle.lowercased().contains(lowerQuery)
                    || entry.sourceName.lowercased().contains(lowerQuery)
                    || entry.originLabel.lowercased().contains(lowerQuery)
                    || groupLabel.lowercased().contains(lowerQuery) {
                    return true
                }
                return !normQuery.isEmpty && entry.normalizedTitle.contains(normQuery)
            }
        }

        if visibleEntries.isEmpty {
            tableView.isHidden = true
            emptyScroll.isHidden = false
            emptyTitle.text = "没有匹配的漫画"
            emptyDesc.text = "没有找到与“\(rawQuery)”匹配的黑名单记录"
            emptyActionButton.setTitle("清空搜索", for: .normal)
            emptyActionButton.isHidden = false
        } else {
            emptyScroll.isHidden = true
            tableView.isHidden = false
            tableView.reloadData()
        }
        updateStickyFooter()
    }

    private func updateStickyFooter() {
        let show = isEditMode && !allEntries.isEmpty && !environment.blacklistStore.isCorrupted
        stickyFooter.isHidden = !show
        tableBottomToFooterConstraint.isActive = show
        tableBottomToViewConstraint.isActive = !show
        if !show { return }

        selectionCountLabel.text = "已选 \(selectedKeys.count) 部"
        let hasVisible = !visibleEntries.isEmpty
        let allSelected = hasVisible && visibleEntries.allSatisfy { selectedKeys.contains($0.normalizedTitle) }
        selectAllButton.setTitle(allSelected ? "取消全选" : "全选", for: .normal)
        selectAllButton.isEnabled = hasVisible
        selectAllButton.alpha = hasVisible ? 1 : 0.45

        let canRestore = !selectedKeys.isEmpty
        restoreSelectedButton.isEnabled = canRestore
        restoreSelectedButton.alpha = canRestore ? 1 : 0.45
    }

    @objc private func toggleEditMode() {
        view.endEditing(true)
        isEditMode.toggle()
        selectedKeys.removeAll()
        applyFilterAndRender()
    }

    @objc private func toggleSelectAllTapped() {
        guard !visibleEntries.isEmpty else { return }
        let allSelected = visibleEntries.allSatisfy { selectedKeys.contains($0.normalizedTitle) }
        for entry in visibleEntries {
            if allSelected {
                selectedKeys.remove(entry.normalizedTitle)
            } else {
                selectedKeys.insert(entry.normalizedTitle)
            }
        }
        tableView.reloadData()
        updateStickyFooter()
    }

    @objc private func restoreSelectedTapped() {
        guard !selectedKeys.isEmpty else { return }
        let keys = Array(selectedKeys)
        let count = environment.restoreFromBlacklist(normalizedTitles: keys)
        selectedKeys.removeAll()
        if environment.blacklistStore.size == 0 {
            isEditMode = false
        }
        reloadFromStore()
        if count > 0 {
            RemToastView.show(message: "已恢复 \(count) 部漫画", kind: .success, in: self)
        }
    }

    @objc private func confirmRestoreAllTapped() {
        guard !allEntries.isEmpty else { return }
        let alert = UIAlertController(
            title: "全部恢复",
            message: "确定恢复黑名单中的全部 \(allEntries.count) 部漫画吗？\n恢复后它们会重新显示在发现、推荐、搜索与书架中。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "恢复全部", style: .default) { [weak self] _ in
            guard let self else { return }
            let cleared = self.environment.clearBlacklist()
            self.isEditMode = false
            self.selectedKeys.removeAll()
            self.reloadFromStore()
            if cleared > 0 {
                RemToastView.show(message: "已恢复全部 \(cleared) 部漫画", kind: .success, in: self)
            }
        })
        present(alert, animated: true)
    }

    @objc private func emptyActionTapped() {
        if environment.blacklistStore.isCorrupted {
            let alert = UIAlertController(
                title: "重建黑名单",
                message: "将清空损坏的数据并建立新的空白黑名单（原损坏文件已保存为备份）。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "清空并重建", style: .destructive) { [weak self] _ in
                guard let self else { return }
                _ = self.environment.clearBlacklist()
                self.reloadFromStore()
                RemToastView.show(message: "黑名单已重建", kind: .success, in: self)
            })
            present(alert, animated: true)
        } else {
            searchBar.text = ""
            searchQuery = ""
            applyFilterAndRender()
        }
    }

    private func restoreSingleEntry(_ entry: BlacklistEntry) {
        guard environment.restoreFromBlacklist(normalizedTitle: entry.normalizedTitle) else { return }
        let title = entry.displayTitle.isEmpty ? entry.normalizedTitle : entry.displayTitle
        reloadFromStore()
        RemToastView.show(message: "已恢复《\(title)》", kind: .success, in: self)
    }

    private func resolveGroupLabel(for entry: BlacklistEntry) -> String {
        if !entry.comicId.isEmpty {
            let scope: BookshelfScope = entry.originScope == "local" ? .local : .online
            let custom = environment.bookshelfGroupStore.getGroupsForComic(scope: scope, comicId: entry.comicId)
                .filter { !$0.isBuiltin }
                .map(\.name)
            if !custom.isEmpty {
                return custom.joined(separator: "、")
            }
        }
        return entry.groupSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - UISearchBarDelegate

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchQuery = searchText
        applyFilterAndRender()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: - UITableViewDataSource & Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleEntries.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        visibleEntries.isEmpty ? nil : "恢复后，漫画会重新显示在发现、推荐、搜索和书架中；若原本在书架里，会回到原来的分组并保留阅读进度。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: BlacklistEntryCell.reuseId, for: indexPath) as! BlacklistEntryCell
        let entry = visibleEntries[indexPath.row]
        let referer = environment.allSources.first(where: { $0.id == entry.sourceId })?.referer ?? ""
        cell.configure(
            entry: entry,
            groupLabel: resolveGroupLabel(for: entry),
            editing: isEditMode,
            selected: selectedKeys.contains(entry.normalizedTitle),
            referer: referer,
            library: environment.localLibrary
        ) { [weak self] in
            self?.restoreSingleEntry(entry)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard isEditMode else { return }
        let entry = visibleEntries[indexPath.row]
        if selectedKeys.contains(entry.normalizedTitle) {
            selectedKeys.remove(entry.normalizedTitle)
        } else {
            selectedKeys.insert(entry.normalizedTitle)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        updateStickyFooter()
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isEditMode else { return nil }
        let entry = visibleEntries[indexPath.row]
        let restoreAction = UIContextualAction(style: .normal, title: "恢复") { [weak self] _, _, completion in
            self?.restoreSingleEntry(entry)
            completion(true)
        }
        restoreAction.backgroundColor = Palette.accent
        return UISwipeActionsConfiguration(actions: [restoreAction])
    }
}

@MainActor
private final class BlacklistEntryCell: UITableViewCell {
    static let reuseId = "BlacklistEntryCell"

    private let checkImage = UIImageView()
    private let coverView = RemoteImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let groupLabel = UILabel()
    private let restoreButton = UIButton(type: .system)
    private var onRestore: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Palette.card
        contentView.backgroundColor = Palette.card
        selectionStyle = .none

        checkImage.contentMode = .scaleAspectFit
        checkImage.translatesAutoresizingMaskIntoConstraints = false
        checkImage.widthAnchor.constraint(equalToConstant: 22).isActive = true
        checkImage.heightAnchor.constraint(equalToConstant: 22).isActive = true

        coverView.backgroundColor = Palette.placeholder
        coverView.layer.cornerRadius = 6
        coverView.layer.borderWidth = 1 / UIScreen.main.scale
        coverView.layer.borderColor = Palette.borderSoft.cgColor
        coverView.clipsToBounds = true
        coverView.contentMode = .scaleAspectFill
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.widthAnchor.constraint(equalToConstant: 40).isActive = true
        coverView.heightAnchor.constraint(equalToConstant: 54).isActive = true

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 1

        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = Palette.text3
        metaLabel.numberOfLines = 1

        groupLabel.font = .systemFont(ofSize: 11)
        groupLabel.textColor = Palette.accentText
        groupLabel.numberOfLines = 1

        let infoStack = UIStackView(arrangedSubviews: [titleLabel, metaLabel, groupLabel])
        infoStack.axis = .vertical
        infoStack.spacing = 2
        infoStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        restoreButton.setTitle("恢复", for: .normal)
        restoreButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        restoreButton.setTitleColor(Palette.accentText, for: .normal)
        restoreButton.backgroundColor = Palette.accentSoft
        restoreButton.layer.cornerRadius = 8
        restoreButton.layer.borderWidth = 1 / UIScreen.main.scale
        restoreButton.layer.borderColor = Palette.borderSoft.cgColor
        restoreButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        restoreButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        restoreButton.setContentHuggingPriority(.required, for: .horizontal)
        restoreButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        restoreButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [checkImage, coverView, infoStack, restoreButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.cancel()
        coverView.image = nil
        onRestore = nil
    }

    func configure(
        entry: BlacklistEntry,
        groupLabel groupText: String,
        editing: Bool,
        selected: Bool,
        referer: String,
        library: LocalLibrary,
        onRestore: @escaping () -> Void
    ) {
        self.onRestore = onRestore
        let displayTitle = entry.displayTitle.isEmpty ? entry.normalizedTitle : entry.displayTitle
        titleLabel.text = displayTitle

        var metaParts: [String] = []
        if !entry.sourceName.isEmpty {
            metaParts.append(entry.sourceName)
        } else if !entry.originLabel.isEmpty {
            metaParts.append(entry.originLabel)
        }
        if !entry.originLabel.isEmpty && !entry.sourceName.isEmpty && entry.originLabel != entry.sourceName {
            metaParts.append(entry.originLabel)
        }
        if entry.blacklistedAt > 0 {
            metaParts.append(Self.formatRelative(ms: entry.blacklistedAt))
        }
        let meta = metaParts.joined(separator: " · ")
        metaLabel.text = meta
        metaLabel.isHidden = meta.isEmpty

        if groupText.isEmpty {
            groupLabel.isHidden = true
        } else {
            groupLabel.text = "恢复后回到「\(groupText)」"
            groupLabel.isHidden = false
        }

        checkImage.isHidden = !editing
        if editing {
            checkImage.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
            checkImage.tintColor = selected ? Palette.accent : Palette.text3
        }
        restoreButton.isHidden = editing
        restoreButton.accessibilityLabel = "恢复 \(displayTitle)"

        if !entry.coverUrl.isEmpty {
            let summary = ComicSummary(
                sourceId: entry.sourceId,
                comicId: entry.comicId,
                title: displayTitle,
                coverUrl: entry.coverUrl
            )
            coverView.loadCover(summary, referer: referer, library: library)
        } else {
            coverView.cancel()
            AppIllustrationCache.bind(coverView, assetName: "rem_no_image", maxSideDp: 56)
            coverView.contentMode = .scaleAspectFit
        }
    }

    @objc private func restoreTapped() {
        onRestore?()
    }

    private static func formatRelative(ms: Int64) -> String {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let diff = nowMs - ms
        let min = diff / 60_000
        if min < 1 { return "刚刚" }
        if min < 60 { return "\(min) 分钟前" }
        let hr = min / 60
        if hr < 24 { return "\(hr) 小时前" }
        let day = hr / 24
        if day == 1 { return "昨天" }
        if day < 7 { return "\(day) 天前" }
        if day < 30 { return "\(day / 7) 周前" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
