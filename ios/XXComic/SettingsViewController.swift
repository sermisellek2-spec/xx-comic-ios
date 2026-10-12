import UIKit
import ComicCore

final class SettingsViewController: UITableViewController {
    private let environment: AppEnvironment
    private let store: ReaderPreferencesStore
    private let habitTracker: ReadingHabitTracker
    private let defaults: UserDefaults

    private var cachedSizeString: String = ""
    private var cacheSizeTask: Task<Void, Never>?
    private var cacheSizeGeneration = UUID()
    private var updateTask: Task<Void, Never>?
    private var updateGeneration = UUID()

    deinit { cacheSizeTask?.cancel(); updateTask?.cancel() }

    init(environment: AppEnvironment) {
        self.environment = environment
        self.store = environment.preferences
        self.habitTracker = environment.readingHabits
        self.defaults = environment.defaults
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        tableView.backgroundColor = Palette.background
        tableView.separatorColor = Palette.borderSoft
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: CGFloat.leastNormalMagnitude))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateCacheSizeText()
        tableView.reloadData()
    }

    private func updateCacheSizeText() {
        cacheSizeTask?.cancel()
        let token = UUID(); cacheSizeGeneration = token
        let cache = environment.responseCache
        cacheSizeTask = Task { [weak self] in
            do {
                let usage = try await cache.usage()
                guard let self, self.cacheSizeGeneration == token, !Task.isCancelled else { return }
                self.cachedSizeString = StorageCalculator.formatBytes(usage.totalBytes)
                self.tableView.reloadData()
            } catch {
                guard let self, self.cacheSizeGeneration == token, !Task.isCancelled else { return }
                self.cachedSizeString = "计算失败"
                self.tableView.reloadData()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cacheSizeTask?.cancel()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentedViewController == nil else { return }
        updateGeneration = UUID(); updateTask?.cancel(); updateTask = nil
    }

    private var downloadSummaryText: String {
        let tasks = environment.downloadStore.list()
        let pending = tasks.filter { $0.state != .completed }.count
        if pending > 0 {
            return "\(pending) 个进行中"
        }
        return tasks.isEmpty ? "" : "已完成"
    }

    private var errorLogSummaryText: String {
        let count = ErrorLogStore.shared.count
        return count > 0 ? "\(count) 条" : "无"
    }

    private var launchBookshelfSubtitle: String {
        switch habitTracker.launchMode {
        case .automatic: return habitTracker.currentAutoSubtitle
        case .my: return "启动默认显示我的书架"
        case .local: return "启动默认显示本地书架"
        }
    }

    private var launchBookshelfModeLabel: String {
        switch habitTracker.launchMode {
        case .automatic: return "自动跟随"
        case .my: return "我的书架"
        case .local: return "本地书架"
        }
    }

    private var installedVersionLabel: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.40"
        let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "340"
        return "\(shortVersion) (\(buildVersion))"
    }

    private var currentTheme: AppTheme { AppTheme(rawValue: defaults.integer(forKey: "theme.mode")) ?? .automatic }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        [3, 6, 2][section]
    }
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        let label = UILabel()
        label.text = ["阅读与外观", "站源与本地数据", "App"][section]
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Palette.text3
        label.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -5)
        ])
        return header
    }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12)).lineHeight + 15
    }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { 10 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = settingsCell(at: indexPath)
        cell.setGroupPosition(first: indexPath.row == 0, last: indexPath.row == [3, 6, 2][indexPath.section] - 1)
        return cell
    }
    private func settingsCell(at indexPath: IndexPath) -> SettingsMenuCell {
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            let label = ["自动", "白天", "黑夜"][currentTheme.rawValue]
            let icon: ParityIcon = currentTheme == .automatic ? .automatic : (currentTheme == .light ? .sun : .moon)
            return SettingsMenuCell(icon: icon, title: "主题模式", subtitle: "跟随系统、浅色或深色", value: label, identifier: "settings.theme")
        case (0, 1):
            return SettingsMenuCell(icon: .bookshelf, title: "启动书架", subtitle: launchBookshelfSubtitle, value: launchBookshelfModeLabel, identifier: "settings.launch")
        case (0, 2):
            return SettingsMenuCell(icon: .history, title: "阅读历史", subtitle: "章节与阅读位置", value: "\(environment.library.history.count) 条", identifier: "settings.history")
        case (1, 0):
            return SettingsMenuCell(icon: .source, title: "站源管理", subtitle: "拖动排序、启停与导入导出", value: "\(environment.sources.count) 个开启", identifier: "settings.sources")
        case (1, 1):
            return SettingsMenuCell(icon: .download, title: "下载中心", subtitle: "任务进度、暂停与章节重试", value: downloadSummaryText, identifier: "settings.downloads")
        case (1, 2):
            return SettingsMenuCell(icon: .bookshelf, title: "本地存储管理", subtitle: "仅 Wi-Fi 下载 · 副本与空间统计", identifier: "settings.storage")
        case (1, 3):
            return SettingsMenuCell(icon: .trash, title: "缓存清理", subtitle: "保留收藏与阅读历史", value: cachedSizeString, identifier: "settings.cache")
        case (1, 4):
            return SettingsMenuCell(icon: .lightning, title: "错误日志", subtitle: "只保存在本机", value: errorLogSummaryText, identifier: "settings.errors")
        case (1, 5):
            return SettingsMenuCell(icon: .profile, title: "使用统计", subtitle: "可选 · 不上传阅读内容", value: environment.usageStats.isEnabled ? "已开启" : "已关闭", identifier: "settings.statistics")
        case (2, 0):
            return SettingsMenuCell(icon: .automatic, title: "版本更新", value: installedVersionLabel, identifier: "settings.update")
        default:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.40"
            return SettingsMenuCell(icon: .profile, title: "关于 App", value: version, identifier: "settings.about")
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            present(ThemeChoiceSheet(selected: currentTheme) { [weak self] theme in
                guard let self else { return }
                self.defaults.set(theme.rawValue, forKey: "theme.mode")
                NotificationCenter.default.post(name: AppThemeController.changed, object: nil)
                self.tableView.reloadData()
            }, animated: true)
        case (0, 1): navigationController?.pushViewController(LaunchBookshelfSettingsViewController(tracker: habitTracker), animated: true)
        case (0, 2): navigationController?.pushViewController(BookshelfViewController(environment: environment, historyOnly: true), animated: true)
        case (1, 0): navigationController?.pushViewController(SourceSettingsViewController(environment: environment), animated: true)
        case (1, 1): navigationController?.pushViewController(DownloadCenterViewController(environment: environment), animated: true)
        case (1, 2): navigationController?.pushViewController(LocalStorageViewController(environment: environment), animated: true)
        case (1, 3): navigationController?.pushViewController(CacheCleanupViewController(environment: environment), animated: true)
        case (1, 4): navigationController?.pushViewController(ErrorLogsViewController(environment: environment), animated: true)
        case (1, 5): showStatisticsChoice()
        case (2, 0): checkForUpdate()
        case (2, 1): navigationController?.pushViewController(AboutAppViewController(environment: environment), animated: true)
        default: break
        }
    }
    private func showStatisticsChoice() {
        let enabled = environment.usageStats.isEnabled
        let alert = UIAlertController(title: "使用统计", message: "开启后用于统计使用规模和版本兼容性。仅包含随机安装标识、应用版本、系统版本和设备型号，不上传阅读内容、搜索词、书架或本地文件。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: enabled ? "关闭统计" : "开启统计", style: .default) { [weak self] _ in
            guard let self else { return }
            do { try self.environment.setUsageStatsEnabled(!enabled); self.tableView.reloadData() }
            catch { self.showError(error) }
        })
        present(alert, animated: true)
    }

    private func checkForUpdate() {
        updateTask?.cancel()
        let token = UUID(); updateGeneration = token
        let currentCode = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "340") ?? 340
        let currentName = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.40"

        let progressAlert = UIAlertController(title: "检查更新中…", message: "正在获取最新版本信息", preferredStyle: .alert)
        progressAlert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.updateGeneration = UUID(); self?.updateTask?.cancel(); self?.updateTask = nil
        })
        present(progressAlert, animated: true)

        updateTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.updateGeneration == token { self.updateTask = nil } }
            do {
                let release = try await self.environment.fetchAppRelease()
                guard self.updateGeneration == token, !Task.isCancelled else { return }
                progressAlert.dismiss(animated: true) {
                    guard self.updateGeneration == token, self.viewIfLoaded?.window != nil, self.presentedViewController == nil else { return }
                    if release.hasNewVersion(currentVersionCode: currentCode) {
                        let alert = UIAlertController(
                            title: "发现新版本 XX Comic \(release.versionName)",
                            message: "当前版本: \(currentName)\n\n\(release.releaseNotes.isEmpty ? "包含最新的界面优化与稳定性修复" : release.releaseNotes)\n\n\(IOSUpdatePolicy.installationHint)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "浏览器更新", style: .default) { [weak self] _ in
                            self?.openReleasePage(IOSUpdatePolicy.browserURL(for: release))
                        })
                        alert.addAction(UIAlertAction(title: "稍后", style: .cancel))
                        self.present(alert, animated: true)
                    } else {
                        let alert = UIAlertController(
                            title: "已经是最新版本",
                            message: "XX Comic \(self.installedVersionLabel)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "知道了", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            } catch {
                guard self.updateGeneration == token, !Task.isCancelled else { return }
                progressAlert.dismiss(animated: true) {
                    guard self.updateGeneration == token, self.viewIfLoaded?.window != nil, self.presentedViewController == nil else { return }
                    let alert = UIAlertController(
                        title: "检查更新失败",
                        message: "暂时无法查询最新版本，可重试或自行查看发布页。\n\n\(IOSUpdatePolicy.installationHint)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self, weak alert] _ in
                        alert?.dismiss(animated: true) { [weak self] in
                            guard let self, self.viewIfLoaded?.window != nil, self.presentedViewController == nil else { return }
                            self.checkForUpdate()
                        }
                    })
                    alert.addAction(UIAlertAction(title: "查看发布页", style: .default) { [weak self] _ in
                        self?.openReleasePage(IOSUpdatePolicy.releasesURL)
                    })
                    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func openReleasePage(_ url: URL) {
        UIApplication.shared.open(url) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor [weak self] in
                guard let self, self.viewIfLoaded?.window != nil else { return }
                let alert = UIAlertController(title: "无法打开浏览器", message: "请稍后重试。发布地址：\(IOSUpdatePolicy.releasesURL.absoluteString)", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "知道了", style: .default))
                self.present(alert, animated: true)
            }
        }
    }
}

final class LaunchBookshelfSettingsViewController: UITableViewController {
    private let tracker: ReadingHabitTracker
    private let options: [(String, String, ReadingHabitTracker.LaunchMode)] = [
        ("自动跟随习惯（默认）", "根据本机阅读习惯选择", .automatic),
        ("我的书架", "启动默认打开我的书架", .my),
        ("本地书架", "启动默认打开本地书架", .local)
    ]

    init(tracker: ReadingHabitTracker) {
        self.tracker = tracker
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "启动书架"
        tableView.backgroundColor = Palette.background
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? options.count : 1 }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? tracker.currentAutoSubtitle : "习惯数据只保存在本机。"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Palette.card
        if indexPath.section == 0 {
            let option = options[indexPath.row]
            cell.textLabel?.text = option.0
            cell.detailTextLabel?.text = option.1
            cell.accessoryType = tracker.launchMode == option.2 ? .checkmark : .none
        } else {
            cell.textLabel?.text = "重置习惯数据"
            cell.textLabel?.textColor = .systemRed
            cell.accessibilityIdentifier = "settings.reset.reading.habit"
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            tracker.launchMode = options[indexPath.row].2
            tableView.reloadData()
            return
        }
        let alert = UIAlertController(title: "重置习惯数据", message: "将清除本机学习到的阅读偏好，是否继续？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重置", style: .destructive) { [weak self] _ in
            self?.tracker.resetHabit()
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
