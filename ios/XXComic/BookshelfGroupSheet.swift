import UIKit
import ComicCore

@MainActor
final class BookshelfGroupSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private let scope: BookshelfScope
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var groups: [BookshelfGroup] = []
    private var selectedGroupId: String
    private var checkedPersistenceOnOpen = false

    var onGroupSelected: ((BookshelfGroup) -> Void)?
    var onGroupsChanged: (() -> Void)?

    init(environment: AppEnvironment, scope: BookshelfScope, selectedGroupId: String) {
        self.environment = environment
        self.scope = scope
        self.selectedGroupId = selectedGroupId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "分组管理"
        view.backgroundColor = Palette.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(dismissTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "新建分组", style: .plain, target: self, action: #selector(createGroupTapped))

        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(GroupCell.self, forCellReuseIdentifier: "group_cell")
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !checkedPersistenceOnOpen else { return }
        checkedPersistenceOnOpen = true
        if let error = environment.bookshelfGroupStore.persistenceError {
            showBookshelfGroupError(error, retry: { [weak self] in
                guard let self else { return }
                do {
                    try self.environment.bookshelfGroupStore.retryLoading()
                    self.reloadGroups()
                    self.onGroupsChanged?()
                } catch { self.showBookshelfGroupError(error) }
            })
        }
    }

    private func reloadGroups() {
        groups = environment.bookshelfGroupStore.getGroups(scope: scope)
        tableView.reloadData()
    }

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }

    @objc private func createGroupTapped() {
        let alert = UIAlertController(title: "新建分组", message: "请输入分组名称", preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "分组名称"
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text else { return }
            do {
                let newGroup = try self.environment.bookshelfGroupStore.createGroup(scope: self.scope, rawName: name)
                self.reloadGroups()
                self.onGroupsChanged?()
                self.onGroupSelected?(newGroup)
            } catch {
                self.showBookshelfGroupError(error)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "group_cell", for: indexPath) as! GroupCell
        let group = groups[indexPath.row]
        let count = environment.bookshelfGroupStore.getMembers(groupId: group.id).count
        let isSelected = (group.id == selectedGroupId)
        cell.configure(group: group, memberCount: count, isSelected: isSelected,
                       onRename: { [weak self] in self?.renameGroup(group) },
                       onDelete: { [weak self] in self?.deleteGroup(group) })
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let group = groups[indexPath.row]
        selectedGroupId = group.id
        tableView.reloadData()
        onGroupSelected?(group)
        dismiss(animated: true)
    }

    private func renameGroup(_ group: BookshelfGroup) {
        guard !group.isBuiltin else { return }
        let alert = UIAlertController(title: "重命名分组", message: nil, preferredStyle: .alert)
        alert.addTextField {
            $0.text = group.name
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text else { return }
            do {
                _ = try self.environment.bookshelfGroupStore.renameGroup(id: group.id, rawNewName: name)
                self.reloadGroups()
                self.onGroupsChanged?()
            } catch {
                self.showBookshelfGroupError(error)
            }
        })
        present(alert, animated: true)
    }

    private func deleteGroup(_ group: BookshelfGroup) {
        guard !group.isBuiltin else { return }
        let alert = UIAlertController(
            title: "删除分组“\(group.name)”？",
            message: "分组内的漫画将保留在“全部”中，不会被删除。",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "删除分组", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                let snapshot = try self.environment.bookshelfGroupStore.deleteGroup(id: group.id)
                if self.selectedGroupId == group.id {
                    self.selectedGroupId = (self.scope == .online) ? BookshelfGroupStore.builtinOnlineAllId : BookshelfGroupStore.builtinLocalAllId
                    if let builtin = self.environment.bookshelfGroupStore.getBuiltinGroup(scope: self.scope) {
                        self.onGroupSelected?(builtin)
                    }
                }
                self.reloadGroups()
                self.onGroupsChanged?()

                // Offer undo
                let undoAlert = UIAlertController(title: "已删除分组“\(group.name)”", message: nil, preferredStyle: .alert)
                undoAlert.addAction(UIAlertAction(title: "知道了", style: .default))
                undoAlert.addAction(UIAlertAction(title: "撤销", style: .default) { [weak self] _ in
                    guard let self else { return }
                    let restored = self.environment.bookshelfGroupStore.restoreGroup(snapshot: snapshot)
                    if let error = self.environment.bookshelfGroupStore.persistenceError {
                        self.showBookshelfGroupError(error)
                        return
                    }
                    self.selectedGroupId = restored.id
                    self.reloadGroups()
                    self.onGroupsChanged?()
                    self.onGroupSelected?(restored)
                })
                self.presentBookshelfGroupAlert(undoAlert)
            } catch {
                self.showBookshelfGroupError(error)
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    private final class GroupCell: UITableViewCell {
        private let titleLabel = UILabel()
        private let countLabel = UILabel()
        private let checkmarkIcon = UIImageView(image: UIImage(systemName: "checkmark"))
        private let renameButton = UIButton(type: .system)
        private let deleteButton = UIButton(type: .system)
        private var onRename: (() -> Void)?
        private var onDelete: (() -> Void)?

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            backgroundColor = Palette.card
            contentView.backgroundColor = Palette.card

            titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
            titleLabel.textColor = Palette.text

            countLabel.font = .systemFont(ofSize: 13)
            countLabel.textColor = Palette.text2

            checkmarkIcon.tintColor = Palette.accent
            checkmarkIcon.translatesAutoresizingMaskIntoConstraints = false

            renameButton.setImage(UIImage(systemName: "pencil"), for: .normal)
            renameButton.tintColor = Palette.text2
            renameButton.addTarget(self, action: #selector(renameTapped), for: .touchUpInside)

            deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
            deleteButton.tintColor = Palette.text2
            deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

            let labelStack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
            labelStack.axis = .vertical
            labelStack.spacing = 2
            labelStack.translatesAutoresizingMaskIntoConstraints = false

            let buttonStack = UIStackView(arrangedSubviews: [renameButton, deleteButton, checkmarkIcon])
            buttonStack.axis = .horizontal
            buttonStack.spacing = 12
            buttonStack.alignment = .center
            buttonStack.translatesAutoresizingMaskIntoConstraints = false

            contentView.addSubview(labelStack)
            contentView.addSubview(buttonStack)

            NSLayoutConstraint.activate([
                labelStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                labelStack.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8),

                buttonStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                buttonStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

                contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 54)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:)") }

        @objc private func renameTapped() { onRename?() }
        @objc private func deleteTapped() { onDelete?() }

        func configure(group: BookshelfGroup, memberCount: Int, isSelected: Bool,
                       onRename: @escaping () -> Void, onDelete: @escaping () -> Void) {
            self.onRename = onRename
            self.onDelete = onDelete
            accessibilityIdentifier = "bookshelf.group.manage." + group.id
            renameButton.accessibilityIdentifier = "bookshelf.group.rename." + group.id
            renameButton.accessibilityLabel = "重命名分组“\(group.name)”"
            deleteButton.accessibilityIdentifier = "bookshelf.group.delete." + group.id
            deleteButton.accessibilityLabel = "删除分组“\(group.name)”"
            titleLabel.text = group.name
            countLabel.text = group.isBuiltin ? "内置全部 · \(memberCount) 本" : "\(memberCount) 本漫画"
            checkmarkIcon.isHidden = !isSelected
            renameButton.isHidden = group.isBuiltin
            deleteButton.isHidden = group.isBuiltin
        }
    }
}
