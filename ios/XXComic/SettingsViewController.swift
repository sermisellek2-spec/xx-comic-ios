import UIKit
import ComicCore

final class SettingsViewController: UITableViewController {
    private let environment: AppEnvironment
    private let store: ReaderPreferencesStore
    private let habitTracker: ReadingHabitTracker
    private let defaults: UserDefaults

    private var cachedSizeString: String = ""

    init(environment: AppEnvironment) {
        self.environment = environment
        self.store = environment.preferences
        self.habitTracker = environment.readingHabits
        self.defaults = environment.defaults
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        tableView.backgroundColor = Palette.background
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateCacheSizeText()
        tableView.reloadData()
    }

    private func updateCacheSizeText() {
        Task.detached {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            let totalBytes = cacheURL != nil ? StorageCalculator.directorySize(at: cacheURL!) : 0
            let text = StorageCalculator.formatBytes(totalBytes)
            await MainActor.run {
                self.cachedSizeString = text
                self.tableView.reloadData()
            }
        }
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
        case .automatic: return "自动"
        case .my: return "我的书架"
        case .local: return "本地书架"
        }
    }

    private var installedVersionLabel: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(buildVersion))"
    }

    // MARK: - UITableViewDataSource & Delegate

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "阅读与外观"
        case 1: return "站源与本地数据"
        case 2: return "App"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 4 // 主题模式、启动书架、阅读历史、阅读设置
        case 1: return 5 // 站源管理、下载中心、本地存储管理、缓存清理、错误日志
        case 2: return 3 // 版本更新、关于 App、匿名统计
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Palette.card
        cell.textLabel?.textColor = Palette.text
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        cell.detailTextLabel?.textColor = Palette.secondaryText
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.accessoryType = .disclosureIndicator

        switch indexPath.section {
        case 0:
            if indexPath.row == 0 {
                // 主题模式
                let themeCell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
                themeCell.backgroundColor = Palette.card
                themeCell.textLabel?.text = "主题模式"
                themeCell.textLabel?.textColor = Palette.text
                themeCell.textLabel?.font = .systemFont(ofSize: 15)
                themeCell.detailTextLabel?.text = "跟随系统、浅色或深色"
                themeCell.detailTextLabel?.textColor = Palette.secondaryText
                themeCell.detailTextLabel?.font = .systemFont(ofSize: 12)

                let control = UISegmentedControl(items: ["跟随系统", "浅色", "深色"])
                control.selectedSegmentIndex = (AppTheme(rawValue: defaults.integer(forKey: "theme.mode")) ?? .automatic).rawValue
                control.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
                themeCell.accessoryView = control
                themeCell.selectionStyle = .none
                return themeCell
            } else if indexPath.row == 1 {
                // 启动书架
                cell.textLabel?.text = "启动书架"
                cell.detailTextLabel?.text = launchBookshelfSubtitle
                let badge = UILabel()
                badge.text = launchBookshelfModeLabel
                badge.textColor = Palette.secondaryText
                badge.font = .systemFont(ofSize: 13)
                badge.sizeToFit()
                cell.accessoryView = badge
            } else if indexPath.row == 2 {
                // 阅读历史
                cell.textLabel?.text = "阅读历史"
                cell.detailTextLabel?.text = "章节与阅读位置"
                let countBadge = UILabel()
                countBadge.text = "\(environment.library.history.count) 条"
                countBadge.textColor = Palette.secondaryText
                countBadge.font = .systemFont(ofSize: 13)
                countBadge.sizeToFit()
                cell.accessoryView = countBadge
            } else {
                // 阅读设置
                cell.textLabel?.text = "阅读设置"
                cell.detailTextLabel?.text = "切换阅读页左右触控区"
            }

        case 1:
            if indexPath.row == 0 {
                // 站源管理
                cell.textLabel?.text = "站源管理"
                cell.detailTextLabel?.text = "启停、导入导出与检测"
                let badge = UILabel()
                badge.text = "\(environment.sources.count) 个开启"
                badge.textColor = Palette.secondaryText
                badge.font = .systemFont(ofSize: 13)
                badge.sizeToFit()
                cell.accessoryView = badge
            } else if indexPath.row == 1 {
                // 下载中心
                cell.textLabel?.text = "下载中心"
                cell.detailTextLabel?.text = "任务进度、暂停与章节重试"
                let summary = downloadSummaryText
                if !summary.isEmpty {
                    let badge = UILabel()
                    badge.text = summary
                    badge.textColor = Palette.secondaryText
                    badge.font = .systemFont(ofSize: 13)
                    badge.sizeToFit()
                    cell.accessoryView = badge
                }
            } else if indexPath.row == 2 {
                // 本地存储管理
                cell.textLabel?.text = "本地存储管理"
                cell.detailTextLabel?.text = "仅 Wi-Fi 下载 · 副本与空间统计"
            } else if indexPath.row == 3 {
                // 缓存清理
                cell.textLabel?.text = "缓存清理"
                cell.detailTextLabel?.text = "保留收藏与阅读历史"
                if !cachedSizeString.isEmpty {
                    let badge = UILabel()
                    badge.text = cachedSizeString
                    badge.textColor = Palette.secondaryText
                    badge.font = .systemFont(ofSize: 13)
                    badge.sizeToFit()
                    cell.accessoryView = badge
                }
            } else {
                // 错误日志
                cell.textLabel?.text = "错误日志"
                cell.detailTextLabel?.text = "只保存在本机"
                let badge = UILabel()
                badge.text = errorLogSummaryText
                badge.textColor = Palette.secondaryText
                badge.font = .systemFont(ofSize: 13)
                badge.sizeToFit()
                cell.accessoryView = badge
            }

        case 2:
            if indexPath.row == 0 {
                // 版本更新
                cell.textLabel?.text = "版本更新"
                cell.detailTextLabel?.text = "包含最新的界面优化与稳定性修复"
                let badge = UILabel()
                badge.text = installedVersionLabel
                badge.textColor = Palette.secondaryText
                badge.font = .systemFont(ofSize: 13)
                badge.sizeToFit()
                cell.accessoryView = badge
            } else if indexPath.row == 1 {
                // 关于 App
                cell.textLabel?.text = "关于 App"
                cell.detailTextLabel?.text = "多站源漫画浏览与本地阅读工具"
                let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                let badge = UILabel()
                badge.text = shortVersion
                badge.textColor = Palette.secondaryText
                badge.font = .systemFont(ofSize: 13)
                badge.sizeToFit()
                cell.accessoryView = badge
            } else {
                // 匿名使用统计
                let statsCell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
                statsCell.backgroundColor = Palette.card
                statsCell.textLabel?.text = "发送匿名使用统计"
                statsCell.textLabel?.textColor = Palette.text
                statsCell.textLabel?.font = .systemFont(ofSize: 15)
                statsCell.detailTextLabel?.text = "仅包含安装代次与基础版本，不收集阅读内容"
                statsCell.detailTextLabel?.textColor = Palette.secondaryText
                statsCell.detailTextLabel?.font = .systemFont(ofSize: 12)
                let statsToggle = UISwitch()
                statsToggle.isOn = UsageStatsClient.shared.isEnabled
                statsToggle.addAction(UIAction { [weak statsToggle] _ in
                    UsageStatsClient.shared.setEnabled(statsToggle?.isOn ?? true)
                }, for: .valueChanged)
                statsCell.accessoryView = statsToggle
                statsCell.selectionStyle = .none
                return statsCell
            }

        default:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 0:
            if indexPath.row == 1 {
                navigationController?.pushViewController(LaunchBookshelfSettingsViewController(tracker: habitTracker), animated: true)
            } else if indexPath.row == 2 {
                navigationController?.pushViewController(BookshelfViewController(environment: environment, historyOnly: true), animated: true)
            } else if indexPath.row == 3 {
                navigationController?.pushViewController(ReaderSettingsViewController(store: store), animated: true)
            }

        case 1:
            if indexPath.row == 0 {
                navigationController?.pushViewController(SourceSettingsViewController(environment: environment), animated: true)
            } else if indexPath.row == 1 {
                navigationController?.pushViewController(DownloadCenterViewController(environment: environment), animated: true)
            } else if indexPath.row == 2 {
                navigationController?.pushViewController(LocalStorageViewController(environment: environment), animated: true)
            } else if indexPath.row == 3 {
                navigationController?.pushViewController(CacheCleanupViewController(environment: environment), animated: true)
            } else if indexPath.row == 4 {
                navigationController?.pushViewController(ErrorLogsViewController(environment: environment), animated: true)
            }

        case 2:
            if indexPath.row == 0 {
                checkForUpdate()
            } else {
                navigationController?.pushViewController(AboutAppViewController(environment: environment), animated: true)
            }

        default:
            break
        }
    }

    @objc private func themeChanged(_ sender: UISegmentedControl) {
        defaults.set(sender.selectedSegmentIndex, forKey: "theme.mode")
        NotificationCenter.default.post(name: AppThemeController.changed, object: nil)
    }

    private func checkForUpdate() {
        let currentCode = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "229") ?? 229
        let currentName = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.29"

        let progressAlert = UIAlertController(title: "检查更新中…", message: "正在获取最新版本信息", preferredStyle: .alert)
        present(progressAlert, animated: true)

        Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await AppUpdateChecker.shared.fetchRelease()
                progressAlert.dismiss(animated: true) {
                    if release.hasNewVersion(currentVersionCode: currentCode) {
                        let alert = UIAlertController(
                            title: "发现新版本 XX Comic \(release.versionName)",
                            message: "当前版本: \(currentName)\n\n\(release.releaseNotes.isEmpty ? "包含最新的界面优化与稳定性修复" : release.releaseNotes)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "前往更新", style: .default) { _ in
                            if let urlStr = release.downloadUrl, let targetURL = URL(string: urlStr) {
                                UIApplication.shared.open(targetURL)
                            } else if let githubURL = URL(string: "https://github.com/lxcodinglove/xx-comic/releases") {
                                UIApplication.shared.open(githubURL)
                            }
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
                progressAlert.dismiss(animated: true) {
                    let alert = UIAlertController(
                        title: "检查更新失败",
                        message: "无法连接到更新服务器，请检查网络连接后重试。\n(\(error.localizedDescription))",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in
                        self?.checkForUpdate()
                    })
                    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                    self.present(alert, animated: true)
                }
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

final class ReaderSettingsViewController: UITableViewController {
    var onChange: (() -> Void)?
    private let store: ReaderPreferencesStore
    private var settings: ReaderPreferences
    private let toggles: [(String, String, WritableKeyPath<ReaderPreferences, Bool>)] = [
        ("左手翻页", "reader.left.hand", \.leftHand),
        ("完全沉浸", "reader.fully.immersive", \.fullyImmersive),
        ("墨水屏模式", "reader.display.mode", \.inkScreen),
        ("双指缩放", "reader.pinch.zoom", \.pinchZoom),
        ("禁止动画翻页", "reader.disable.page.animation", \.disablePageAnimation),
        ("去白边", "reader.crop.white.margins", \.cropWhiteMargins),
        ("原图对照", "reader.enhancement.comparison", \.enhancementComparison)
    ]

    init(store: ReaderPreferencesStore) {
        self.store = store
        settings = store.load()
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "阅读设置"
        tableView.backgroundColor = Palette.background
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 4 : toggles.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "阅读主题跟随系统或固定；图像增强支持本地 2 倍 AI 超分与普通增强。" : "设置保存在本机。"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Palette.card
        cell.textLabel?.textColor = Palette.text
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.selectionStyle = .none
        if indexPath.section == 0 {
            let labels = [["条漫", "单页"], ["触碰", "按钮", "滑动"], ["默认", "深色", "浅色"], ["关闭", "普通", "2倍超分"]]
            let titles = ["阅读布局", "翻页方式", "阅读主题", "图像增强"]
            let selected = [settings.layout.rawValue, settings.turnMode.rawValue, settings.theme.rawValue, settings.enhancementMode]
            let segment = UISegmentedControl(items: labels[indexPath.row])
            segment.selectedSegmentIndex = selected[indexPath.row]
            segment.tag = indexPath.row
            segment.accessibilityLabel = titles[indexPath.row]
            segment.addTarget(self, action: #selector(selectionChanged(_:)), for: .valueChanged)
            let label = UILabel()
            label.text = titles[indexPath.row]
            label.textColor = Palette.text
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            let stack = UIStackView(arrangedSubviews: [label, segment])
            stack.axis = .vertical
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
                segment.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
            ])
        } else {
            let (title, identifier, keyPath) = toggles[indexPath.row]
            cell.textLabel?.text = title
            let toggle = UISwitch()
            toggle.isOn = settings[keyPath: keyPath]
            toggle.tag = indexPath.row
            toggle.accessibilityLabel = title
            toggle.accessibilityIdentifier = identifier
            toggle.onTintColor = Palette.accent
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        }
        return cell
    }

    @objc private func selectionChanged(_ control: UISegmentedControl) {
        switch control.tag {
        case 0: settings.layout = ReaderLayout(rawValue: control.selectedSegmentIndex) ?? .strip
        case 1: settings.turnMode = ReaderTurnMode(rawValue: control.selectedSegmentIndex) ?? .tap
        case 2: settings.theme = ReaderTheme(rawValue: control.selectedSegmentIndex) ?? .system
        case 3: settings.enhancementMode = control.selectedSegmentIndex
        default: break
        }
        store.save(settings)
        onChange?()
    }

    @objc private func toggleChanged(_ control: UISwitch) {
        settings[keyPath: toggles[control.tag].2] = control.isOn
        store.save(settings)
        onChange?()
    }
}
