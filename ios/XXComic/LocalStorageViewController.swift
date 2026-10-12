import UIKit
import ComicCore

@MainActor
final class LocalStorageViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let environment: AppEnvironment

    private struct Item: Equatable, Sendable {
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
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private var folderSyncTask: Task<Void, Never>?
    private var folderAccessTask: Task<Void, Never>?
    private var folderAccessGeneration = UUID()
    private var reauthorizingFolderID: String?
    private var folderFeedback: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    deinit { loadTask?.cancel(); folderSyncTask?.cancel(); folderAccessTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "本地存储管理"
        view.backgroundColor = Palette.background

        setupViews()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTapped), name: AppEnvironment.libraryChanged, object: nil)
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(reloadTapped))
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

    @objc private func reloadTapped() { loadData() }

    private func loadData() {
        loadTask?.cancel()
        let token = UUID(); loadGeneration = token
        let library = environment.localLibrary
        let localDir = library.directory
        let locations = environment.downloadLocations
        let cache = environment.responseCache
        let folders = environment.folderBookmarkStore.list()
        let groups = Dictionary(grouping: environment.downloadStore.list(), by: \.bookId)
        let downloadedItems = groups.map { bookID, tasks -> Item in
            var title = environment.downloadStore.snapshot(id: bookID)?.summary.title ?? "离线漫画"
            if let first = tasks.first, first.isFileTask { title += " · " + first.title }
            return Item(id: bookID, title: title, isDownload: true, size: tasks.reduce(0) { $0 + $1.bytes })
        }
        statsLabel.text = "正在统计空间…"
        let worker = Task.detached(priority: .utility) { () async throws -> ([Item], String) in
            var loaded: [Item] = []
            for series in try await library.series() {
                try Task.checkCancellation()
                var bytes: Int64 = 0
                for volumeID in series.volumeIDs {
                    bytes += try StorageCalculator.directorySize(at: localDir.appendingPathComponent(volumeID, isDirectory: true))
                }
                loaded.append(Item(id: series.id, title: series.displayTitle, isDownload: false, size: bytes))
            }
            loaded += downloadedItems
            let importedSize = try StorageCalculator.directorySize(at: localDir)
            // Include each mapped book in its real location, without traversing a user's directory root.
            var downloadSummary: String
            do {
                var downloadedSize: Int64 = 0
                for bookID in groups.keys {
                    try Task.checkCancellation()
                    downloadedSize += try locations.withBookDirectory(bookID: bookID, access: .read) {
                        try StorageCalculator.directorySize(at: $0)
                    }
                }
                downloadSummary = "离线下载: " + StorageCalculator.formatBytes(downloadedSize)
            } catch is CancellationError { throw CancellationError() }
            catch { downloadSummary = "离线下载统计未完成：" + error.localizedDescription }
            let usage = try await cache.usage()
            let usableSpace = StorageCalculator.usableSpace()
            try Task.checkCancellation()
            let summary = "本地导入: \(StorageCalculator.formatBytes(importedSize))  ·  \(downloadSummary)\n可清缓存: \(StorageCalculator.formatBytes(usage.totalBytes))  ·  剩余空间: \(StorageCalculator.formatBytes(usableSpace))"
            return (loaded, summary)
        }
        loadTask = Task { [weak self] in
            do {
                let (loaded, summary) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, self.loadGeneration == token, !Task.isCancelled else { return }
                self.items = loaded.filter { item in
                    item.isDownload ? !self.environment.localDeletion.containsDownloadBook(item.id) : !self.environment.localDeletion.containsLocalSeries(item.id)
                }
                self.syncedFolders = folders
                self.selectedIDs.formIntersection(Set(self.items.map(\.id)))
                self.statsLabel.text = summary
                self.tableView.reloadData()
            } catch {
                guard let self, self.loadGeneration == token, !Task.isCancelled else { return }
                self.statsLabel.text = "空间统计失败，点击右上角重试"
                self.tableView.reloadData()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        loadTask?.cancel()
        if isMovingFromParent {
            folderAccessGeneration = UUID(); folderAccessTask?.cancel()
            folderSyncTask?.cancel()
        }
    }

    // MARK: - Actions

    @objc private func wifiSwitchChanged(_ sender: UISwitch) {
        environment.downloadRuntime.isWifiOnly = sender.isOn
        environment.defaults.set(sender.isOn, forKey: "downloads.wifiOnly")
    }

    @objc private func clearCacheTapped() {
        navigationController?.pushViewController(CacheCleanupViewController(environment: environment), animated: true)
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
        let requests = targets.map { item in
            LocalDeletionController.Request(target: item.isDownload ? .downloadBook(item.id) : .localSeries(item.id), title: item.title,
                groupComicID: item.isDownload ? (environment.downloadStore.snapshot(id: item.id)?.summary.comicId ?? environment.downloadStore.list().first { $0.bookId == item.id }?.comicId ?? item.id) : item.id)
        }
        selectedIDs.removeAll()
        environment.localDeletion.schedule(requests, from: self)
        loadData()
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
        if let folderAccessTask { folderAccessTask.cancel(); return }
        guard folderSyncTask == nil else { return }
        reauthorizingFolderID = nil
        pickFolder()
    }
    private func pickFolder() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        #if DEBUG
        if reauthorizingFolderID != nil, let selected = LinkedFolderUITestFixtures.reauthorizationSelection(library: environment.localLibrary) {
            documentPicker(picker, didPickDocumentsAt: [selected]); return
        }
        #endif
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func syncAllFoldersTapped() {
        if let folderSyncTask { folderSyncTask.cancel(); return }
        guard folderAccessTask == nil else { return }
        syncFolders(ids: nil)
    }

    private func syncFolders(ids: Set<String>?) {
        guard folderSyncTask == nil else { return }
        let folders = environment.folderSyncCoordinator.store.list().filter { ids?.contains($0.id) ?? true }
        guard !folders.isEmpty else { showToast("没有需要同步的关联文件夹"); return }
        folderSyncTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.folderSyncTask = nil
                self.tableView.reloadSections(IndexSet(integer: 2), with: .none)
            }
            var failed: [(id: String, name: String, error: String)] = []
            var succeeded = 0
            var results: [String: LocalFolderSyncCoordinator.SyncResult] = [:]
            for folder in folders {
                if Task.isCancelled { break }
                let result = await self.environment.folderSyncCoordinator.sync(id: folder.id)
                results[folder.id] = result
                switch result {
                case .upToDate, .updated: succeeded += 1
                case .error(let message): failed.append((folder.id, folder.folderName, message))
                }
            }
            self.environment.folderSynchronizationFinished(results)
            self.loadData()
            guard self.viewIfLoaded?.window != nil else { return }
            if Task.isCancelled { self.showToast("已取消同步，已完成的结果保留"); return }
            guard !failed.isEmpty else { self.showToast("已同步 \(succeeded) 个文件夹"); return }
            let failures = failed.map { "\($0.name)：\($0.error)" }.joined(separator: "\n")
            let retryIDs = Set(failed.map(\.id))
            let alert = UIAlertController(title: "部分文件夹同步失败", message: "成功 \(succeeded) 个，失败 \(failed.count) 个。\n\n" + failures, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "稍后", style: .cancel))
            alert.addAction(UIAlertAction(title: "重试失败项", style: .default) { [weak self] _ in self?.syncFolders(ids: retryIDs) })
            self.present(alert, animated: true)
        }
        tableView.reloadSections(IndexSet(integer: 2), with: .none)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let reauthorizingID = reauthorizingFolderID; reauthorizingFolderID = nil
        let token = UUID(); folderAccessGeneration = token
        let coordinator = environment.folderSyncCoordinator
        folderFeedback = reauthorizingID == nil ? "正在建立文件夹索引…" : "正在恢复文件夹授权…"
        tableView.reloadSections(IndexSet(integer: 2), with: .none)
        folderAccessTask = Task { [weak self] in
            defer {
                if self?.folderAccessGeneration == token {
                    self?.folderAccessTask = nil
                    self?.tableView.reloadSections(IndexSet(integer: 2), with: .none)
                }
            }
            do {
                if let reauthorizingID { _ = try await coordinator.reauthorize(id: reauthorizingID, url: url) }
                else { _ = try await coordinator.linkFolder(url: url) }
                guard let self, self.folderAccessGeneration == token, !Task.isCancelled else { return }
                RemoteImageView.clearMemoryCache(); ReaderEnhancementEngine.shared.clearCache()
                self.environment.notifyLibraryChanged()
                self.folderFeedback = reauthorizingID == nil ? "已关联文件夹；正文直接读取，原文件保留" : "已恢复授权；书名和阅读记录保留"
                self.loadData()
            } catch is CancellationError {
                guard let self, self.folderAccessGeneration == token else { return }
                self.folderFeedback = "已取消，原索引和原文件保留"
            } catch {
                guard let self, self.folderAccessGeneration == token else { return }
                self.folderFeedback = "文件夹操作失败：\(error.localizedDescription)；可重新选择重试"
            }
        }
        tableView.reloadSections(IndexSet(integer: 2), with: .none)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { reauthorizingFolderID = nil }

    private func reauthorizeFolder(_ folder: SyncedFolderRecord) {
        guard folderAccessTask == nil, folderSyncTask == nil else { return }
        let alert = UIAlertController(title: "重新授权《\(folder.folderName)》", message: "请选择原文件夹或移动后的文件夹。保留书名、卷和阅读记录，原文件不移动。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "选择文件夹", style: .default) { [weak self] _ in
            self?.reauthorizingFolderID = folder.id; self?.pickFolder()
        })
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource & Delegate

    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 2 else { return nil }
        return folderFeedback ?? environment.folderSynchronizationError ?? "正文直接读取所选文件夹；只保存索引和封面。进入应用时检查变化，授权失效可点按文件夹重新授权。解除关联仅停止自动同步，原文件保留。"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 2 } // Wi-Fi and actual download location
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
            if indexPath.row == 1 {
                let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
                cell.backgroundColor = Palette.card; cell.textLabel?.text = "离线下载位置"
                cell.textLabel?.textColor = Palette.text; cell.textLabel?.font = .systemFont(ofSize: 14, weight: .bold)
                cell.detailTextLabel?.text = environment.downloadLocations.selectedName
                cell.detailTextLabel?.numberOfLines = 0; cell.detailTextLabel?.textColor = Palette.secondaryText
                cell.accessoryType = .disclosureIndicator; cell.accessibilityIdentifier = "storage.download-location"
                return cell
            }
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
                linkButton.setTitle(folderAccessTask == nil ? "＋ 关联新外部文件夹" : "取消索引", for: .normal)
                linkButton.accessibilityIdentifier = "local.folder.link"
                linkButton.isEnabled = folderSyncTask == nil
                linkButton.setTitleColor(Palette.accent, for: .normal)
                linkButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
                linkButton.addTarget(self, action: #selector(linkNewFolderTapped), for: .touchUpInside)

                let syncAllButton = UIButton(type: .system)
                syncAllButton.setTitle(folderSyncTask == nil ? "立即同步全部" : "取消同步", for: .normal)
                syncAllButton.accessibilityIdentifier = "local.folder.sync"
                syncAllButton.isEnabled = folderAccessTask == nil
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
            cell.accessibilityIdentifier = "local.folder." + folder.id
            cell.accessoryType = .disclosureIndicator
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
            cell.detailTextLabel?.text = "\(folder.fileCount) 张图片 · \(statusDesc) · 上次同步: \(timeDesc)\n点按重新授权" + (folder.lastError.map { "\n" + $0 } ?? "")
            cell.accessibilityValue = "\(folder.fileCount) 张图片 · \(statusDesc)"
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.textColor = folder.status == .active ? Palette.secondaryText : .systemRed
            cell.detailTextLabel?.font = .systemFont(ofSize: 12)
            cell.selectionStyle = .default
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
        if indexPath.section == 2, indexPath.row > 0 {
            reauthorizeFolder(syncedFolders[indexPath.row - 1]); return
        }
        if indexPath.section == 0, indexPath.row == 1 {
            navigationController?.pushViewController(DownloadLocationViewController(locations: environment.downloadLocations), animated: true)
            return
        }
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
            guard let self, self.folderSyncTask == nil, self.folderAccessTask == nil else { completion(false); return }
            self.folderSyncTask = Task {
                defer { self.folderSyncTask = nil; self.tableView.reloadSections(IndexSet(integer: 2), with: .none) }
                let res = await self.environment.folderSyncCoordinator.sync(id: folder.id)
                self.environment.folderSynchronizationFinished([folder.id: res])
                guard self.viewIfLoaded?.window != nil else { completion(false); return }
                var succeeded = true
                switch res {
                case .upToDate(let count): self.showToast("已是最新 (\(count) 张图片)")
                case .updated(_, let newCount): self.showToast("已更新至 \(newCount) 张图片")
                case .error(let msg): succeeded = false; self.showToast("同步失败: \(msg)")
                }
                self.loadData()
                completion(succeeded)
            }
            self.tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
        syncAction.backgroundColor = Palette.accent

        let unlinkAction = UIContextualAction(style: .destructive, title: "解除关联") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            Task {
                do {
                    try await self.environment.folderSyncCoordinator.unlinkFolder(id: folder.id)
                    self.showToast("已解除文件夹关联")
                    self.loadData()
                    completion(true)
                } catch {
                    self.showToast("解除关联失败：\(error.localizedDescription)")
                    completion(false)
                }
            }
        }

        return UISwipeActionsConfiguration(actions: [unlinkAction, syncAction])
    }
}
