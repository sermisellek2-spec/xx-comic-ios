import UIKit
import ComicCore

@MainActor
final class LocalStorageViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let environment: AppEnvironment

    private struct Item: Equatable {
        let id: String
        let title: String
        let isDownload: Bool
        let size: Int64
    }

    private var items: [Item] = []
    private var syncedFolders: [SyncedFolderRecord] = []
    private var selectedIDs = Set<String>()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let wifiSwitch = UISwitch()
    private let statsLabel = UILabel()
    private let clearCacheButton = UIButton(type: .system)
    private let deleteSelectedButton = UIButton(type: .system)

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "本地存储管理"
        view.backgroundColor = Palette.background

        setupViews()
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }

    private func setupViews() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "card")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "book")
        view.addSubview(tableView)

        let bottomBar = UIStackView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.axis = .horizontal
        bottomBar.spacing = 12
        bottomBar.distribution = .fillEqually
        view.addSubview(bottomBar)

        clearCacheButton.setTitle("清理缓存", for: .normal)
        clearCacheButton.setTitleColor(Palette.accent, for: .normal)
        clearCacheButton.backgroundColor = Palette.card
        clearCacheButton.layer.cornerRadius = 8
        clearCacheButton.layer.borderWidth = 1
        clearCacheButton.layer.borderColor = Palette.border.cgColor
        clearCacheButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        clearCacheButton.addTarget(self, action: #selector(clearCacheTapped), for: .touchUpInside)

        deleteSelectedButton.setTitle("删除选中", for: .normal)
        deleteSelectedButton.setTitleColor(.systemRed, for: .normal)
        deleteSelectedButton.backgroundColor = Palette.card
        deleteSelectedButton.layer.cornerRadius = 8
        deleteSelectedButton.layer.borderWidth = 1
        deleteSelectedButton.layer.borderColor = Palette.border.cgColor
        deleteSelectedButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        deleteSelectedButton.addTarget(self, action: #selector(deleteSelectedTapped), for: .touchUpInside)

        bottomBar.addArrangedSubview(clearCacheButton)
        bottomBar.addArrangedSubview(deleteSelectedButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
    }

    private func loadData() {
        Task { [self] in
            // 1. 本地系列
            var loaded: [Item] = []
            let seriesList = (try? await environment.localLibrary.series()) ?? []
            for s in seriesList {
                var totalBytes: Int64 = 0
                for volId in s.volumeIDs {
                    let volDir = environment.localLibrary.directory.appendingPathComponent(volId, isDirectory: true)
                    totalBytes += StorageCalculator.directorySize(at: volDir)
                }
                loaded.append(Item(id: s.id, title: s.displayTitle, isDownload: false, size: totalBytes))
            }

            // 2. 离线下载任务分组
            let downloadTasks = environment.downloadStore.list()
            let grouped = Dictionary(grouping: downloadTasks, by: \.bookId)
            for (bookId, tasks) in grouped {
                let detail = environment.downloadStore.snapshot(id: bookId)
                let firstTask = tasks.first
                var title = detail?.summary.title ?? "离线漫画"
                if let first = firstTask, first.isFileTask {
                    title += " · " + first.title
                }
                let totalBytes = tasks.reduce(0) { $0 + $1.bytes }
                loaded.append(Item(id: bookId, title: title, isDownload: true, size: totalBytes))
            }

            self.items = loaded
            self.syncedFolders = self.environment.folderBookmarkStore.list()
            self.tableView.reloadData()
            self.updateStatistics()
        }
    }

    private func updateStatistics() {
        Task.detached {
            let localDir = await self.environment.localLibrary.directory
            let downloadsDir = await self.environment.downloadRuntime.downloadsDirectory

            let importedSize = StorageCalculator.directorySize(at: localDir)
            let downloadedSize = StorageCalculator.directorySize(at: downloadsDir)
            let usableSpace = StorageCalculator.usableSpace()

            // 缓存大小：图片缓存和派生缓存
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            let cacheSize = cacheURL != nil ? StorageCalculator.directorySize(at: cacheURL!) : 0

            await MainActor.run {
                self.statsLabel.text = "本地导入: \(StorageCalculator.formatBytes(importedSize))  ·  离线下载: \(StorageCalculator.formatBytes(downloadedSize))\n可清缓存: \(StorageCalculator.formatBytes(cacheSize))  ·  剩余空间: \(StorageCalculator.formatBytes(usableSpace))"
            }
        }
    }

    // MARK: - Actions

    @objc private func wifiSwitchChanged(_ sender: UISwitch) {
        environment.downloadRuntime.isWifiOnly = sender.isOn
        environment.defaults.set(sender.isOn, forKey: "downloads.wifiOnly")
    }

    @objc private func clearCacheTapped() {
        URLCache.shared.removeAllCachedResponses()
        if let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let fileManager = FileManager.default
            if let files = try? fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
        updateStatistics()
        showToast("缓存已清理")
    }

    @objc private func deleteSelectedTapped() {
        guard !selectedIDs.isEmpty else {
            showToast("先选择需要删除的漫画")
            return
        }

        let alert = UIAlertController(
            title: "删除选中的本地漫画？",
            message: "仅删除 App 中的副本，原文件、在线收藏和阅读记录不受影响。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.performDelete()
        })
        present(alert, animated: true)
    }

    private func performDelete() {
        let targets = items.filter { selectedIDs.contains($0.id) }
        Task {
            for item in targets {
                if item.isDownload {
                    self.environment.downloadRuntime.deleteBook(bookId: item.id)
                } else {
                    try? await self.environment.localLibrary.deleteSeries(id: item.id)
                }
            }
            self.selectedIDs.removeAll()
            self.environment.notifyLibraryChanged()
            self.showToast("已清理本地副本")
            self.loadData()
        }
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            alert.dismiss(animated: true)
        }
    }

    // MARK: - Actions

    @objc private func linkNewFolderTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func syncAllFoldersTapped() {
        Task {
            self.showToast("正在同步关联文件夹...")
            _ = await self.environment.folderSyncCoordinator.syncAll()
            self.environment.notifyLibraryChanged()
            self.showToast("文件夹同步完成")
            self.loadData()
        }
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Task {
            do {
                _ = try await self.environment.folderSyncCoordinator.linkFolder(url: url)
                self.environment.notifyLibraryChanged()
                self.showToast("已成功关联并索引文件夹")
                self.loadData()
            } catch {
                self.showToast("关联失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UITableViewDataSource & Delegate

    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 1 } // Wi-Fi Switch
        if section == 1 { return 1 } // Storage Stats
        if section == 2 { return syncedFolders.count + 1 } // Synced Folders + Add Action
        return items.count // Books List
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 2 {
            return "关联外部文件夹 (自动同步)"
        }
        if section == 3 {
            return "已保存的本地漫画与离线下载"
        }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "wifi")
            cell.backgroundColor = Palette.card
            cell.textLabel?.text = "仅 Wi-Fi 下载"
            cell.textLabel?.textColor = Palette.text
            cell.textLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            cell.detailTextLabel?.text = "未连接 Wi-Fi 时自动暂停下载任务"
            cell.detailTextLabel?.textColor = Palette.secondaryText
            cell.detailTextLabel?.font = .systemFont(ofSize: 12)
            wifiSwitch.isOn = environment.downloadRuntime.isWifiOnly
            wifiSwitch.onTintColor = Palette.accent
            wifiSwitch.removeTarget(self, action: #selector(wifiSwitchChanged(_:)), for: .valueChanged)
            wifiSwitch.addTarget(self, action: #selector(wifiSwitchChanged(_:)), for: .valueChanged)
            cell.accessoryView = wifiSwitch
            cell.selectionStyle = .none
            return cell
        }

        if indexPath.section == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: "stats")
            cell.backgroundColor = Palette.card
            cell.selectionStyle = .none

            let titleLabel = UILabel()
            titleLabel.text = "存储空间统计"
            titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
            titleLabel.textColor = Palette.text

            statsLabel.numberOfLines = 0
            statsLabel.font = .systemFont(ofSize: 12)
            statsLabel.textColor = Palette.secondaryText
            if statsLabel.text == nil || statsLabel.text!.isEmpty {
                statsLabel.text = "正在统计存储占用..."
            }

            let stack = UIStackView(arrangedSubviews: [titleLabel, statsLabel])
            stack.axis = .vertical
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false

            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            cell.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
            ])
            return cell
        }

        if indexPath.section == 2 {
            if indexPath.row == 0 {
                let cell = UITableViewCell(style: .default, reuseIdentifier: "sync_actions")
                cell.backgroundColor = Palette.card
                cell.selectionStyle = .none

                let linkButton = UIButton(type: .system)
                linkButton.setTitle("＋ 关联新外部文件夹", for: .normal)
                linkButton.setTitleColor(Palette.accent, for: .normal)
                linkButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
                linkButton.addTarget(self, action: #selector(linkNewFolderTapped), for: .touchUpInside)

                let syncAllButton = UIButton(type: .system)
                syncAllButton.setTitle("立即同步全部", for: .normal)
                syncAllButton.setTitleColor(Palette.accent, for: .normal)
                syncAllButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
                syncAllButton.addTarget(self, action: #selector(syncAllFoldersTapped), for: .touchUpInside)

                let stack = UIStackView(arrangedSubviews: [linkButton, syncAllButton])
                stack.axis = .horizontal
                stack.distribution = .equalSpacing
                stack.translatesAutoresizingMaskIntoConstraints = false

                cell.contentView.subviews.forEach { $0.removeFromSuperview() }
                cell.contentView.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                    stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                    stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
                    stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10)
                ])
                return cell
            }

            let folder = syncedFolders[indexPath.row - 1]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "synced_folder")
            cell.backgroundColor = Palette.card
            cell.textLabel?.text = folder.folderName
            cell.textLabel?.textColor = Palette.text
            cell.textLabel?.font = .systemFont(ofSize: 15, weight: .bold)

            let statusDesc: String
            switch folder.status {
            case .active: statusDesc = "正常同步"
            case .permissionRevoked: statusDesc = "授权失效"
            case .folderMissing: statusDesc = "原文件夹丢失"
            case .syncFailed: statusDesc = "同步失败"
            }
            let timeDesc = DateFormatter.localizedString(from: Date(timeIntervalSince1970: folder.lastSyncTimestamp), dateStyle: .short, timeStyle: .short)
            cell.detailTextLabel?.text = "\(folder.fileCount) 张图片 · \(statusDesc) · 上次同步: \(timeDesc)"
            cell.detailTextLabel?.textColor = folder.status == .active ? Palette.secondaryText : .systemRed
            cell.detailTextLabel?.font = .systemFont(ofSize: 12)
            cell.selectionStyle = .none
            return cell
        }

        let item = items[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "book")
        cell.backgroundColor = Palette.card
        cell.textLabel?.text = item.title
        cell.textLabel?.textColor = Palette.text
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .bold)

        let badge = item.isDownload ? "离线下载" : "本地导入"
        cell.detailTextLabel?.text = "\(badge) · \(StorageCalculator.formatBytes(item.size))"
        cell.detailTextLabel?.textColor = Palette.secondaryText
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)

        let isSelected = selectedIDs.contains(item.id)
        let checkImageName = isSelected ? "checkmark.circle.fill" : "circle"
        let checkImageView = UIImageView(image: UIImage(systemName: checkImageName))
        checkImageView.tintColor = isSelected ? Palette.accent : Palette.secondaryText
        cell.accessoryView = checkImageView

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 3 else { return }

        let item = items[indexPath.row]
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 2 && indexPath.row > 0 else { return nil }
        let folder = syncedFolders[indexPath.row - 1]

        let syncAction = UIContextualAction(style: .normal, title: "立即同步") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            Task {
                let res = await self.environment.folderSyncCoordinator.sync(id: folder.id)
                self.environment.notifyLibraryChanged()
                switch res {
                case .upToDate(let count): self.showToast("已是最新 (\(count) 张图片)")
                case .updated(_, let newCount): self.showToast("已更新至 \(newCount) 张图片")
                case .error(let msg): self.showToast("同步失败: \(msg)")
                }
                self.loadData()
                completion(true)
            }
        }
        syncAction.backgroundColor = Palette.accent

        let unlinkAction = UIContextualAction(style: .destructive, title: "解除关联") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            Task {
                try? await self.environment.folderSyncCoordinator.unlinkFolder(id: folder.id)
                self.showToast("已解除文件夹关联")
                self.loadData()
                completion(true)
            }
        }

        return UISwipeActionsConfiguration(actions: [unlinkAction, syncAction])
    }
}
