import UIKit
import ComicCore

@MainActor
final class BookshelfGroupSelectSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private let scope: BookshelfScope
    private let comicId: String
    private let comicTitle: String
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var groups: [BookshelfGroup] = []
    private var selectedGroupIds: Set<String> = []
    private var checkedPersistenceOnOpen = false

    var onGroupsUpdated: ((Set<String>) -> Void)?

    init(environment: AppEnvironment, scope: BookshelfScope, comicId: String, comicTitle: String) {
        self.environment = environment
        self.scope = scope
        self.comicId = comicId
        self.comicTitle = comicTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "移动至分组"
        view.backgroundColor = Palette.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))

        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "select_cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        let footer = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 60))
        let newGroupButton = UIButton(type: .system)
        newGroupButton.setTitle("+ 新建分组", for: .normal)
        newGroupButton.setTitleColor(Palette.accent, for: .normal)
        newGroupButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        newGroupButton.addTarget(self, action: #selector(newGroupTapped), for: .touchUpInside)
        newGroupButton.frame = footer.bounds
        newGroupButton.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        footer.addSubview(newGroupButton)
        tableView.tableFooterView = footer

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        loadGroups(resetSelection: true)
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
                    self.loadGroups(resetSelection: true)
                } catch { self.showBookshelfGroupError(error) }
            })
        }
    }

    private func loadGroups(resetSelection: Bool = false) {
        // Exclude builtin "全部" because comics are always members of "全部"
        groups = environment.bookshelfGroupStore.getGroups(scope: scope).filter { !$0.isBuiltin }
        if resetSelection {
            let currentGroups = environment.bookshelfGroupStore.getGroupsForComic(scope: scope, comicId: comicId)
            selectedGroupIds = Set(currentGroups.filter { !$0.isBuiltin }.map(\.id))
        } else {
            // Creating a group refreshes available rows, not the user's draft.
            selectedGroupIds.formIntersection(groups.map(\.id))
        }
        tableView.reloadData()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        environment.bookshelfGroupStore.updateComicGroups(scope: scope, comicId: comicId, targetGroupIds: selectedGroupIds)
        if let error = environment.bookshelfGroupStore.persistenceError {
            showBookshelfGroupError(error)
            return
        }
        environment.notifyLibraryChanged()
        onGroupsUpdated?(selectedGroupIds)
        dismiss(animated: true)
    }

    @objc private func newGroupTapped() {
        let alert = UIAlertController(title: "新建分组", message: "请输入分组名称", preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "分组名称"
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text else { return }
            do {
                let g = try self.environment.bookshelfGroupStore.createGroup(scope: self.scope, rawName: name)
                self.selectedGroupIds.insert(g.id)
                self.loadGroups()
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "select_cell", for: indexPath)
        let group = groups[indexPath.row]
        let isSelected = selectedGroupIds.contains(group.id)
        cell.backgroundColor = Palette.card
        cell.contentView.backgroundColor = Palette.card
        cell.textLabel?.text = group.name
        cell.textLabel?.textColor = Palette.text
        cell.accessoryType = isSelected ? .checkmark : .none
        cell.tintColor = Palette.accent
        cell.accessibilityIdentifier = "bookshelf.group.select." + group.id
        cell.accessibilityLabel = group.name
        cell.accessibilityValue = isSelected ? "已选择" : "未选择"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let group = groups[indexPath.row]
        if selectedGroupIds.contains(group.id) {
            selectedGroupIds.remove(group.id)
        } else {
            selectedGroupIds.insert(group.id)
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}

@MainActor
extension UIViewController {
    func presentBookshelfGroupAlert(_ alert: UIAlertController) {
        if let current = presentedViewController as? UIAlertController {
            current.dismiss(animated: true) { [weak self] in self?.present(alert, animated: true) }
        } else if presentedViewController == nil {
            present(alert, animated: true)
        }
    }

    func showBookshelfGroupError(_ error: Error, retry: (() -> Void)? = nil) {
        let alert = UIAlertController(title: "分组操作失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: retry == nil ? "确定" : "取消", style: .cancel))
        if let retry { alert.addAction(UIAlertAction(title: "重试", style: .default) { _ in retry() }) }
        presentBookshelfGroupAlert(alert)
    }
}
