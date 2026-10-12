import UIKit
import ComicCore

@MainActor
final class SourceGroupSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var groups: [SourceGroup] = []

    var onGroupSelected: ((SourceGroup) -> Void)?
    var onGroupsChanged: (() -> Void)?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "站源分组"
        view.backgroundColor = Palette.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(dismissTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "新建分组", style: .plain, target: self, action: #selector(createGroupTapped))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "source-groups.close"
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "source-groups.create"

        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.accessibilityIdentifier = "source-groups.list"
        tableView.register(SourceGroupCell.self, forCellReuseIdentifier: "source_group_cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        reloadGroups()
    }

    private func reloadGroups() {
        groups = environment.sourceGroupStore.groups
        tableView.reloadData()
    }

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }

    @objc private func createGroupTapped() {
        let alert = UIAlertController(title: "新建站源分组", message: "请输入分组名称", preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "分组名称"
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text else { return }
            do {
                let newGroup = try self.environment.sourceGroupStore.create(name: name, sourceIds: [])
                self.reloadGroups()
                self.onGroupsChanged?()
                self.showSelectSources(for: newGroup)
            } catch {
                self.showGroupError(error)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "source_group_cell", for: indexPath) as! SourceGroupCell
        let group = groups[indexPath.row]
        let count = group.isBuiltin ? environment.sourcePreferences.orderedIDs.count : group.sourceIds.count
        let isSelected = (group.id == environment.sourceGroupStore.selectedId)
        cell.configure(
            group: group,
            sourceCount: count,
            isSelected: isSelected,
            onSelectSources: { [weak self] in self?.showSelectSources(for: group) },
            onRename: { [weak self] in self?.renameGroup(group) },
            onDelete: { [weak self] in self?.deleteGroup(group) }
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let group = groups[indexPath.row]
        do {
            try environment.sourceGroupStore.select(id: group.id)
            tableView.reloadData()
            onGroupSelected?(group)
            onGroupsChanged?()
            NotificationCenter.default.post(name: AppEnvironment.sourcesChanged, object: environment)
            dismiss(animated: true)
        } catch {
            showGroupError(error)
        }
    }

    private func showSelectSources(for group: SourceGroup) {
        let sheet = SourceGroupSourcesSelectSheet(environment: environment, group: group) { [weak self] in
            self?.reloadGroups()
            self?.onGroupsChanged?()
            NotificationCenter.default.post(name: AppEnvironment.sourcesChanged, object: self?.environment)
        }
        let nav = UINavigationController(rootViewController: sheet)
        presentAfterForm(nav)
    }

    private func presentAfterForm(_ controller: UIViewController) {
        if let form = presentedViewController as? UIAlertController {
            form.dismiss(animated: true) { [weak self] in
                guard let self, self.viewIfLoaded?.window != nil, self.presentedViewController == nil else { return }
                self.present(controller, animated: true)
            }
        } else if presentedViewController == nil { present(controller, animated: true) }
    }

    private func showGroupError(_ error: Error) {
        let alert = UIAlertController(title: "分组操作失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        presentAfterForm(alert)
    }

    private func renameGroup(_ group: SourceGroup) {
        guard !group.isBuiltin else { return }
        let alert = UIAlertController(title: "重命名分组", message: nil, preferredStyle: .alert)
        alert.addTextField {
            $0.text = group.name
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text else { return }
            do {
                try self.environment.sourceGroupStore.rename(id: group.id, to: name)
                self.reloadGroups()
                self.onGroupsChanged?()
            } catch {
                self.showGroupError(error)
            }
        })
        present(alert, animated: true)
    }

    private func deleteGroup(_ group: SourceGroup) {
        guard !group.isBuiltin else { return }
        let alert = UIAlertController(
            title: "删除分组",
            message: "只删除“\(group.name)”分组，站源继续保留。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try self.environment.sourceGroupStore.delete(id: group.id)
                self.reloadGroups()
                self.onGroupsChanged?()
                NotificationCenter.default.post(name: AppEnvironment.sourcesChanged, object: self.environment)
            } catch {
                self.showGroupError(error)
            }
        })
        present(alert, animated: true)
    }
}

// MARK: - SourceGroupCell

@MainActor
final class SourceGroupCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let selectSourcesButton = UIButton(type: .system)
    private let renameButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let builtinBadge = UILabel()

    private var onSelectSources: (() -> Void)?
    private var onRename: (() -> Void)?
    private var onDelete: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setupViews() {
        backgroundColor = Palette.card
        selectionStyle = .none

        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        countLabel.font = .systemFont(ofSize: 13, weight: .regular)
        countLabel.textColor = Palette.secondaryText

        builtinBadge.text = "内置"
        builtinBadge.font = .systemFont(ofSize: 12, weight: .regular)
        builtinBadge.textColor = Palette.secondaryText

        selectSourcesButton.setTitle("选源", for: .normal)
        selectSourcesButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        selectSourcesButton.tintColor = Palette.accent
        selectSourcesButton.addAction(UIAction { [weak self] _ in self?.onSelectSources?() }, for: .touchUpInside)

        renameButton.setTitle("重命名", for: .normal)
        renameButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .regular)
        renameButton.tintColor = Palette.secondaryText
        renameButton.addAction(UIAction { [weak self] _ in self?.onRename?() }, for: .touchUpInside)

        deleteButton.setTitle("删除", for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .regular)
        deleteButton.tintColor = .systemRed
        deleteButton.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [selectSourcesButton, renameButton, deleteButton])
        actions.axis = .horizontal
        actions.spacing = 12
        actions.alignment = .center

        let left = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        left.axis = .horizontal
        left.spacing = 6
        left.alignment = .center

        let main = UIStackView(arrangedSubviews: [left, builtinBadge, actions])
        main.axis = .horizontal
        main.spacing = 12
        main.alignment = .center
        main.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(main)

        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            main.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            main.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            main.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    func configure(group: SourceGroup, sourceCount: Int, isSelected: Bool,
                   onSelectSources: @escaping () -> Void,
                   onRename: @escaping () -> Void,
                   onDelete: @escaping () -> Void) {
        self.onSelectSources = onSelectSources
        self.onRename = onRename
        self.onDelete = onDelete
        accessibilityIdentifier = "source-group.row." + group.id
        selectSourcesButton.accessibilityIdentifier = "source-group.sources." + group.id
        renameButton.accessibilityIdentifier = "source-group.rename." + group.id
        deleteButton.accessibilityIdentifier = "source-group.delete." + group.id

        titleLabel.text = group.name
        titleLabel.textColor = isSelected ? Palette.accent : Palette.text
        titleLabel.font = isSelected ? .systemFont(ofSize: 15, weight: .bold) : .systemFont(ofSize: 15, weight: .medium)

        countLabel.text = "(\(sourceCount))"
        countLabel.textColor = isSelected ? Palette.accent : Palette.secondaryText

        accessoryType = isSelected ? .checkmark : .none

        builtinBadge.isHidden = !group.isBuiltin
        selectSourcesButton.isHidden = group.isBuiltin
        renameButton.isHidden = group.isBuiltin
        deleteButton.isHidden = group.isBuiltin
    }
}

// MARK: - SourceGroupSourcesSelectSheet

@MainActor
final class SourceGroupSourcesSelectSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private let group: SourceGroup
    private let onSaved: () -> Void
    private var selectedIds: Set<String>
    private let allSources: [any ComicSource]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerLabel = UILabel()

    init(environment: AppEnvironment, group: SourceGroup, onSaved: @escaping () -> Void) {
        self.environment = environment
        self.group = group
        self.onSaved = onSaved
        self.selectedIds = Set(group.sourceIds)
        // Android's grouping uses the entire current catalog. Disabled sources
        // remain assignable and retain their membership when enabled later.
        self.allSources = environment.sourcePreferences.orderedIDs.compactMap { id in
            environment.allSources.first { $0.id == id }
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选源 · " + group.name
        view.backgroundColor = Palette.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "保存", style: .done, target: self, action: #selector(saveTapped))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "source-group.selection.cancel"
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "source-group.selection.save"

        headerLabel.font = .systemFont(ofSize: 13, weight: .regular)
        headerLabel.textColor = Palette.secondaryText
        headerLabel.text = "已选 \(selectedIds.count) 个"
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.accessibilityIdentifier = "source-group.selection.list"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        do {
            try environment.sourceGroupStore.setSources(id: group.id, sourceIds: Array(selectedIds))
            onSaved()
            dismiss(animated: true)
        } catch {
            let alert = UIAlertController(title: "保存失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        allSources.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "source_select_cell")
        let source = allSources[indexPath.row]
        let checked = selectedIds.contains(source.id)

        cell.backgroundColor = Palette.card
        cell.textLabel?.text = source.name + (environment.sourcePreferences.isEnabled(source.id) ? "" : "（未启用）")
        cell.accessibilityIdentifier = "source-group.selection." + source.id
        cell.accessibilityValue = checked ? "已选择" : "未选择"
        cell.textLabel?.textColor = checked ? Palette.accent : Palette.text
        cell.textLabel?.font = checked ? .systemFont(ofSize: 15, weight: .bold) : .systemFont(ofSize: 15, weight: .regular)
        cell.accessoryType = checked ? .checkmark : .none

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let source = allSources[indexPath.row]
        if selectedIds.contains(source.id) {
            selectedIds.remove(source.id)
        } else {
            selectedIds.insert(source.id)
        }
        headerLabel.text = "已选 \(selectedIds.count) 个"
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}
