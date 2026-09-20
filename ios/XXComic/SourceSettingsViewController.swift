import UIKit
import ComicCore

@MainActor
final class SourceSettingsViewController: UITableViewController {
    private let environment: AppEnvironment
    let onVerified: () -> Void
    private var ids: [String] { environment.sourcePreferences.orderedIDs }
    init(environment: AppEnvironment, onVerified: @escaping () -> Void = {}) {
        self.environment = environment; self.onVerified = onVerified
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "站源管理"
        tableView.backgroundColor = Palette.background
        tableView.setEditing(true, animated: false)
        tableView.allowsSelectionDuringEditing = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "恢复默认排序", style: .plain, target: self, action: #selector(resetOrder))
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { ids.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "拖动右侧手柄调整顺序。关闭站源不会删除收藏和阅读记录。" }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = ids[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let source = environment.allSources.first { $0.id == id }
        cell.backgroundColor = Palette.card
        cell.textLabel?.text = source?.name
        cell.detailTextLabel?.text = URL(string: source?.referer ?? "")?.host
        cell.textLabel?.textColor = Palette.text
        cell.detailTextLabel?.textColor = Palette.secondaryText
        let toggle = UISwitch()
        toggle.isOn = environment.sourcePreferences.isEnabled(id)
        toggle.accessibilityLabel = source?.name
        toggle.accessibilityIdentifier = "source.enabled." + id
        toggle.addAction(UIAction { [weak self, weak toggle] _ in
            guard let self, let toggle else { return }
            self.environment.sourcePreferences.setEnabled(toggle.isOn, id: id)
            self.notifyChanged()
        }, for: .valueChanged)
        cell.editingAccessoryView = toggle
        cell.showsReorderControl = true
        return cell
    }
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        var reordered = ids
        let id = reordered.remove(at: sourceIndexPath.row)
        reordered.insert(id, at: destinationIndexPath.row)
        environment.sourcePreferences.setOrder(reordered)
        notifyChanged()
    }
    @objc private func resetOrder() {
        environment.sourcePreferences.resetOrder()
        tableView.reloadData()
        notifyChanged()
    }
    private func notifyChanged() { NotificationCenter.default.post(name: AppEnvironment.sourcesChanged, object: environment) }
}
