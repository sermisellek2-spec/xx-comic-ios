import UIKit
import UniformTypeIdentifiers
import ComicCore

@MainActor
final class DownloadLocationViewController: UITableViewController, UIDocumentPickerDelegate {
    private let locations: DownloadStorageLocations
    private var reauthorizingID: String?
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var feedback: String?

    init(locations: DownloadStorageLocations) { self.locations = locations; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "离线下载位置"
        tableView.backgroundColor = Palette.background
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 60
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent { generation = UUID(); operation?.cancel() }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : locations.locations.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "新下载的保存位置" : "原目录重新授权" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? (feedback ?? "新作品保存到所选目录的 XXComic/downloads；已有作品继续使用原目录，不自动迁移。授权失效时选择原目录重新授权后，到下载中心重试。") : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Palette.card; cell.textLabel?.textColor = Palette.text
        cell.detailTextLabel?.textColor = Palette.secondaryText; cell.detailTextLabel?.numberOfLines = 0
        cell.textLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "当前目录"; cell.detailTextLabel?.text = locations.selectedName
                cell.accessibilityIdentifier = "download.location.current"; cell.selectionStyle = .none
            case 1:
                cell.textLabel?.text = "更改 · 选择文件夹"; cell.accessoryType = .disclosureIndicator
                cell.accessibilityIdentifier = "download.location.choose"
            default:
                cell.textLabel?.text = "恢复应用私有目录"; cell.accessibilityIdentifier = "download.location.default"
                cell.accessoryType = locations.selectedID == DownloadStorageLocations.defaultID ? .checkmark : .none
            }
        } else {
            let location = locations.locations[indexPath.row]
            cell.textLabel?.text = location.name; cell.detailTextLabel?.text = "重新授权原目录；原副本保留"
            cell.accessoryType = .disclosureIndicator; cell.accessibilityIdentifier = "download.location.reauthorize." + location.id
        }
        cell.isUserInteractionEnabled = operation == nil
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard operation == nil else { return }
        if indexPath.section == 1 { reauthorizingID = locations.locations[indexPath.row].id; pickFolder(); return }
        if indexPath.row == 1 {
            reauthorizingID = nil
            let alert = UIAlertController(title: "更改离线下载目录", message: "新作品将保存到所选目录的 XXComic/downloads；已有内容留在原位置，不自动迁移。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "选择文件夹", style: .default) { [weak self] _ in self?.pickFolder() })
            present(alert, animated: true)
        } else if indexPath.row == 2 {
            run { [locations] in try locations.useDefault() }
        }
    }
    private func pickFolder() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self; picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { reauthorizingID = nil }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let directory = urls.first else { return }
        let id = reauthorizingID; reauthorizingID = nil
        run { [locations] in try locations.select(directory: directory, reauthorizing: id) }
    }
    private func run<Result: Sendable>(_ work: @escaping @Sendable () throws -> Result) {
        let token = UUID(); generation = token; feedback = "正在检查目录授权与读写…"
        let worker = Task.detached(priority: .utility) { try Task.checkCancellation(); return try work() }
        operation = Task { [weak self] in
            do {
                _ = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.feedback = "下载目录已保存；原副本保留"
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.feedback = "目录未更改：" + error.localizedDescription
            }
            self?.operation = nil; self?.tableView.reloadData()
        }
        tableView.reloadData()
    }
}
