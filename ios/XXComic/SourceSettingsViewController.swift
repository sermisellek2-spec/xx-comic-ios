import UIKit
import ComicCore

@MainActor
final class SourceSettingsViewController: UITableViewController {
    private let environment: AppEnvironment
    let onVerified: (() -> Void)?
    private var verificationTask: Task<Void, Never>?
    private var healthCheckTask: Task<Void, Never>?
    private var healthStatuses: [String: String] = [:]
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(showMoreMenu))
        environment.mh18BrowserSession.statusChanged = { [weak self] in self?.tableView.reloadData() }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            verificationTask?.cancel()
            healthCheckTask?.cancel()
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
        let host = URL(string: source?.referer ?? "")?.host ?? ""
        if let health = healthStatuses[id] {
            cell.detailTextLabel?.text = "\(host) · \(health)"
        } else if id == "mh18" {
            cell.detailTextLabel?.text = "18mh.org · " + environment.mh18BrowserSession.status
        } else {
            cell.detailTextLabel?.text = host
        }
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
    @objc private func showMoreMenu() {
        let alert = UIAlertController(title: "站源管理", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "测试站源可用性", style: .default) { [weak self] _ in
            self?.runHealthCheck()
        })
        alert.addAction(UIAlertAction(title: "导入站源配置", style: .default) { [weak self] _ in
            self?.importConfig()
        })
        alert.addAction(UIAlertAction(title: "导出站源配置", style: .default) { [weak self] _ in
            self?.exportConfig()
        })
        alert.addAction(UIAlertAction(title: "恢复默认排序", style: .default) { [weak self] _ in
            self?.resetOrder()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }
    private func runHealthCheck() {
        healthCheckTask?.cancel()
        for id in environment.sourcePreferences.enabledIDs {
            healthStatuses[id] = "检测中…"
        }
        for id in ids where !environment.sourcePreferences.isEnabled(id) {
            healthStatuses[id] = "已关闭"
        }
        tableView.reloadData()

        healthCheckTask = Task { [weak self] in
            guard let self else { return }
            for id in self.environment.sourcePreferences.enabledIDs {
                guard !Task.isCancelled else { break }
                guard let source = self.environment.allSources.first(where: { $0.id == id }) else { continue }
                let start = DispatchTime.now()
                let ok = await source.healthCheck()
                guard !Task.isCancelled else { break }
                let ms = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
                self.healthStatuses[id] = ok ? "可用 (\(ms)ms)" : "不可用"
                self.tableView.reloadData()
            }
        }
    }
    private func importConfig() {
        let alert = UIAlertController(title: "导入站源配置", message: "粘贴符合 xx-comic.sources 格式的 JSON 配置：", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "{\"schema\":\"xx-comic.sources\", ...}"
            field.clearButtonMode = .whileEditing
            if let clip = UIPasteboard.general.string, clip.contains("xx-comic.sources") {
                field.text = clip
            }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "导入", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            do {
                let result = try self.environment.sourcePreferences.importConfig(jsonString: text)
                self.tableView.reloadData()
                self.notifyChanged()
                let successAlert = UIAlertController(
                    title: "导入成功",
                    message: "成功导入 \(result.totalSources) 个站源配置（启用 \(result.enabledCount)，禁用 \(result.disabledCount)）",
                    preferredStyle: .alert
                )
                successAlert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(successAlert, animated: true)
            } catch {
                self.showError(error)
            }
        })
        present(alert, animated: true)
    }
    private func exportConfig() {
        let tuples = environment.allSources.map { ($0.id, $0.name, URL(string: $0.referer)?.host ?? "", $0.referer) }
        let json = environment.sourcePreferences.exportConfig(sources: tuples)
        UIPasteboard.general.string = json
        let alert = UIAlertController(
            title: "已导出站源配置",
            message: "站源配置 JSON 已复制到剪贴板，符合 xx-comic.sources v2 规范，可直接分享或备份。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "分享", style: .default) { [weak self] _ in
            let share = UIActivityViewController(activityItems: [json], applicationActivities: nil)
            if let popover = share.popoverPresentationController {
                popover.sourceView = self?.view
                popover.sourceRect = CGRect(x: self?.view.bounds.midX ?? 0, y: self?.view.bounds.midY ?? 0, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            self?.present(share, animated: true)
        })
        alert.addAction(UIAlertAction(title: "完成", style: .cancel))
        present(alert, animated: true)
    }
    private func notifyChanged() {
        environment.reloadSources()
        NotificationCenter.default.post(name: AppEnvironment.sourcesChanged, object: environment)
    }
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
