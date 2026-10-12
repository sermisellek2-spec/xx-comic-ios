import UIKit
import ComicCore
import UniformTypeIdentifiers

@MainActor
final class SourceSettingsViewController: UITableViewController, UIDocumentPickerDelegate {
    private let environment: AppEnvironment
    let onVerified: (() -> Void)?
    private var verificationTask: Task<Void, Never>?
    private var healthCheckTask: Task<Void, Never>?
    private var healthStatuses: [String: String] = [:]
    private enum ConfigPickerPurpose { case importing; case exporting(SourceConfigExportDocument) }
    private let configDocuments = SourceConfigDocuments()
    private var configTask: Task<Void, Never>?
    private var configGeneration = UUID()
    private var configPicker: UIDocumentPickerViewController?
    private var configPickerPurpose: ConfigPickerPurpose?
    private var configFeedback = ""
    private var configBusy: Bool { configTask != nil || configPickerPurpose != nil }
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
        tableView.allowsSelectionDuringEditing = true
        updateConfigControls()
        environment.mh18BrowserSession.statusChanged = { [weak self] in self?.tableView.reloadData() }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            verificationTask?.cancel()
            healthCheckTask?.cancel()
            cancelConfigOperation()
            environment.mh18BrowserSession.statusChanged = nil
        }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : ids.count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "分组" : "全部站源"
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        return "拖动右侧手柄调整顺序。关闭站源不会删除收藏和阅读记录。" + (ids.contains("mh18") ? "18漫画的“重置”会结束浏览器会话及进行中的请求，保留站点 Cookie。" : "") + (configFeedback.isEmpty ? "" : "\n\n" + configFeedback)
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.backgroundColor = Palette.card
            cell.textLabel?.text = "站源分组"
            cell.textLabel?.textColor = Palette.text
            cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            let group = environment.sourceGroupStore.currentGroup
            let customCount = max(0, environment.sourceGroupStore.groups.count - 1)
            cell.detailTextLabel?.text = "当前：" + group.name + " · \(customCount) 个自定义分组"
            cell.detailTextLabel?.textColor = Palette.secondaryText
            cell.accessoryType = .disclosureIndicator
            cell.showsReorderControl = false
            return cell
        }

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
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            showSourceGroups()
        }
    }
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 1
    }
    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        if proposedDestinationIndexPath.section == 0 {
            return IndexPath(row: 0, section: 1)
        }
        return proposedDestinationIndexPath
    }
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard sourceIndexPath.section == 1, destinationIndexPath.section == 1 else { return }
        var reordered = ids
        let id = reordered.remove(at: sourceIndexPath.row)
        reordered.insert(id, at: destinationIndexPath.row)
        environment.sourcePreferences.setOrder(reordered)
        notifyChanged()
    }
    private func showSourceGroups() {
        let sheet = SourceGroupSheet(environment: environment)
        sheet.onGroupsChanged = { [weak self] in
            self?.tableView.reloadData()
            self?.notifyChanged()
        }
        let nav = UINavigationController(rootViewController: sheet)
        present(nav, animated: true)
    }
    @objc private func resetOrder() {
        environment.sourcePreferences.resetOrder()
        tableView.reloadData()
        notifyChanged()
    }
    @objc private func showMoreMenu() {
        let alert = UIAlertController(title: "站源管理", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "站源分组管理", style: .default) { [weak self] _ in
            self?.showSourceGroups()
        })
        alert.addAction(UIAlertAction(title: "测试站源可用性", style: .default) { [weak self] _ in
            self?.runHealthCheck()
        })
        alert.addAction(UIAlertAction(title: "导入站源配置", style: .default) { [weak self] _ in
            self?.afterMenuDismissal { [weak self] in self?.importConfig() }
        })
        alert.addAction(UIAlertAction(title: "导出站源配置", style: .default) { [weak self] _ in
            self?.afterMenuDismissal { [weak self] in self?.exportConfig() }
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
    private func afterMenuDismissal(_ action: @escaping () -> Void) {
        if let menu = presentedViewController as? UIAlertController { menu.dismiss(animated: true, completion: action) }
        else { action() }
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
        guard !configBusy else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false; picker.delegate = self
        configPicker = picker; configPickerPurpose = .importing
        configFeedback = "请选择站源配置文件"; updateConfigControls()
        present(picker, animated: true)
    }
    private func exportConfig() {
        guard !configBusy else { return }
        let tuples = ids.compactMap { id in environment.allSources.first { $0.id == id } }
            .map { ($0.id, $0.name, URL(string: $0.referer)?.host ?? "", $0.referer) }
        let package = environment.sourcePreferences.exportPackage(sources: tuples)
        let worker = configDocuments, token = UUID(); configGeneration = token
        configFeedback = "正在准备站源配置文件…"
        configTask = Task { [weak self] in
            defer { self?.finishConfigTask(token: token) }
            do {
                let document = try await worker.prepareExport(package)
                guard let self, self.configGeneration == token, !Task.isCancelled else {
                    try await worker.discardExport(document); return
                }
                let picker = UIDocumentPickerViewController(forExporting: [document.url], asCopy: true)
                picker.delegate = self
                self.configPicker = picker; self.configPickerPurpose = .exporting(document)
                self.configFeedback = "请选择保存位置"; self.updateConfigControls()
                self.present(picker, animated: true)
            } catch {
                guard let self, self.configGeneration == token, !Task.isCancelled else { return }
                self.configFeedback = "导出失败，可重新导出重试"
                self.showError(error)
            }
        }
        updateConfigControls()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard controller === configPicker, let purpose = configPickerPurpose else { return }
        configPicker = nil; configPickerPurpose = nil
        let token = configGeneration, worker = configDocuments
        controller.dismiss(animated: true) { [weak self] in
            guard let self, self.configGeneration == token else {
                if case .exporting(let document) = purpose { Self.discardExport(document, worker: worker) }
                return
            }
            switch purpose {
            case .importing:
                guard let url = urls.first else {
                    self.configFeedback = "未选择文件，现有配置未修改"; self.updateConfigControls(); return
                }
                self.readConfig(url)
            case .exporting(let document): self.finishExport(document, saved: !urls.isEmpty)
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard controller === configPicker, let purpose = configPickerPurpose else { return }
        configPicker = nil; configPickerPurpose = nil
        let token = configGeneration, worker = configDocuments
        controller.dismiss(animated: true) { [weak self] in
            guard let self, self.configGeneration == token else {
                if case .exporting(let document) = purpose { Self.discardExport(document, worker: worker) }
                return
            }
            switch purpose {
            case .importing:
                self.configFeedback = "已取消导入，现有配置未修改"; self.updateConfigControls()
            case .exporting(let document): self.finishExport(document, saved: false)
            }
        }
    }

    private func readConfig(_ url: URL) {
        let snapshot = environment.sourcePreferences.importSnapshot()
        let worker = configDocuments, token = UUID(); configGeneration = token
        configFeedback = "正在读取并检查站源配置…"
        configTask = Task { [weak self] in
            defer { self?.finishConfigTask(token: token) }
            do {
                let prepared = try await worker.prepareImport(from: url, snapshot: snapshot)
                guard let self, self.configGeneration == token, !Task.isCancelled else { return }
                let result = try self.environment.sourcePreferences.applyImport(prepared)
                self.healthCheckTask?.cancel(); self.healthCheckTask = nil
                self.healthStatuses.removeAll()
                self.notifyChanged()
                self.configFeedback = "已导入 \(result.totalSources) 个站源配置（启用 \(result.enabledCount)，禁用 \(result.disabledCount)）" + (result.orderUpdated ? "\n已更新排序" : "")
                let alert = UIAlertController(
                    title: result.warnings.isEmpty ? "导入完成" : (result.totalSources > 0 || result.orderUpdated ? "部分配置已导入" : "未导入配置"),
                    message: self.configFeedback + (result.warnings.isEmpty ? "" : "\n\n" + result.warnings.joined(separator: "\n")),
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert, animated: true)
            } catch {
                guard let self, self.configGeneration == token, !Task.isCancelled else { return }
                self.configFeedback = "导入失败，现有配置未修改；可重新选择文件重试"
                self.showError(error)
            }
        }
        updateConfigControls()
    }

    private func finishExport(_ document: SourceConfigExportDocument, saved: Bool) {
        let worker = configDocuments, token = UUID(); configGeneration = token
        configFeedback = saved ? "站源配置已保存为 \(SourceConfigDocuments.filename)" : "已取消导出"
        configTask = Task { [weak self] in
            defer { self?.finishConfigTask(token: token) }
            do { try await worker.discardExport(document) }
            catch {
                ErrorLogStore.shared.append(title: "站源导出临时副本未清理", detail: "文件已保留")
                guard let self, self.configGeneration == token, !Task.isCancelled else { return }
                self.configFeedback += "；临时副本未能清理，已保留"
            }
            guard let self, self.configGeneration == token, !Task.isCancelled, saved else { return }
            let alert = UIAlertController(title: "导出完成", message: self.configFeedback, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default)); self.present(alert, animated: true)
        }
        updateConfigControls()
    }

    private func finishConfigTask(token: UUID) {
        guard configGeneration == token else { return }
        configTask = nil; updateConfigControls()
    }
    @objc private func cancelConfigOperation() {
        configGeneration = UUID(); configTask?.cancel(); configTask = nil
        if case .exporting(let document) = configPickerPurpose {
            Self.discardExport(document, worker: configDocuments)
        }
        configPicker = nil; configPickerPurpose = nil
        configFeedback = "已取消操作，现有配置未修改"; updateConfigControls()
    }
    private static func discardExport(_ document: SourceConfigExportDocument, worker: SourceConfigDocuments) {
        Task {
            do { try await worker.discardExport(document) }
            catch { ErrorLogStore.shared.append(title: "站源导出临时副本未清理", detail: "文件已保留") }
        }
    }
    private func updateConfigControls() {
        tableView.isUserInteractionEnabled = !configBusy
        let item: UIBarButtonItem
        if configBusy {
            item = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelConfigOperation))
            item.accessibilityIdentifier = "source.config.cancel"
        } else {
            item = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(showMoreMenu))
            item.accessibilityLabel = "站源管理操作"; item.accessibilityIdentifier = "source.config.more"
        }
        navigationItem.rightBarButtonItems = [item]; tableView.reloadData()
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
