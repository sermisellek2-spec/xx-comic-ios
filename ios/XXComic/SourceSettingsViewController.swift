import UIKit
import ComicCore

@MainActor
final class SourceSettingsViewController: UITableViewController {
    private let environment: AppEnvironment
    let onVerified: (() -> Void)?
    private var verificationTask: Task<Void, Never>?
    private var ids: [String] { environment.sourcePreferences.orderedIDs }
    init(environment: AppEnvironment, onVerified: (() -> Void)? = nil) {
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
        environment.mh18BrowserSession.statusChanged = { [weak self] in self?.tableView.reloadData() }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            verificationTask?.cancel()
            environment.mh18BrowserSession.statusChanged = nil
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { ids.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "拖动右侧手柄调整顺序。关闭站源不会删除收藏和阅读记录。" + (ids.contains("mh18") ? "18漫画的“重置”会结束浏览器会话及进行中的请求，保留站点 Cookie。" : "")
    }
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
        if id == "mh18" {
            cell.detailTextLabel?.text = "18mh.org · " + environment.mh18BrowserSession.status
            let verify = UIButton(type: .system)
            verify.setTitle("验证", for: .normal)
            verify.accessibilityLabel = "验证18漫画"
            verify.accessibilityIdentifier = "source.verify.mh18"
            verify.isEnabled = verificationTask == nil
            verify.addAction(UIAction { [weak self] _ in self?.verifyMh18() }, for: .touchUpInside)
            let reset = UIButton(type: .system)
            reset.setTitle("重置", for: .normal)
            reset.accessibilityLabel = "重置18漫画验证"
            reset.accessibilityHint = "结束浏览器会话和进行中的请求，保留站点 Cookie"
            reset.accessibilityIdentifier = "source.reset.mh18"
            reset.addAction(UIAction { [weak self] _ in self?.environment.mh18BrowserSession.reset() }, for: .touchUpInside)
            let controls = UIStackView(arrangedSubviews: [verify, reset, toggle])
            controls.spacing = 8
            controls.frame = CGRect(x: 0, y: 0, width: 156, height: 44)
            cell.editingAccessoryView = controls
        }
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
    private func verifyMh18() {
        guard verificationTask == nil else { return }
        verificationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.verificationTask = nil; self.tableView.reloadData() }
            do {
                try await self.environment.mh18BrowserSession.verify(from: self)
                guard !Task.isCancelled else { return }
                // The browser has already closed. Only error-return management is a modal flow.
                if let onVerified = self.onVerified {
                    self.navigationController?.dismiss(animated: true, completion: onVerified)
                }
            } catch {
                guard !(error is CancellationError), !Task.isCancelled else { return }
                self.showError(error)
            }
        }
        tableView.reloadData()
    }
}
