import UIKit
import ComicCore

final class SettingsViewController: UITableViewController {
    private let store: ReaderPreferencesStore
    private let habitTracker: ReadingHabitTracker
    private let defaults: UserDefaults
    init(store: ReaderPreferencesStore, habitTracker: ReadingHabitTracker, defaults: UserDefaults = .standard) {
        self.store = store
        self.habitTracker = habitTracker
        self.defaults = defaults
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        tableView.backgroundColor = Palette.background
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 2 {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = "启动书架"
            cell.detailTextLabel?.text = launchBookshelfSubtitle
            cell.textLabel?.textColor = Palette.text
            cell.detailTextLabel?.textColor = Palette.secondaryText
            cell.backgroundColor = Palette.card
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if indexPath.row == 1 {
            cell.textLabel?.text = "主题模式"
            let control = UISegmentedControl(items: ["自动", "白天", "黑夜"])
            control.selectedSegmentIndex = (AppTheme(rawValue: defaults.integer(forKey: "theme.mode")) ?? .automatic).rawValue
            control.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
            cell.accessoryView = control; cell.backgroundColor = Palette.card
            return cell
        }
        cell.textLabel?.text = "阅读设置"
        cell.textLabel?.textColor = Palette.text
        cell.backgroundColor = Palette.card
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            navigationController?.pushViewController(ReaderSettingsViewController(store: store), animated: true)
        } else if indexPath.row == 2 {
            navigationController?.pushViewController(LaunchBookshelfSettingsViewController(tracker: habitTracker), animated: true)
        }
    }
    @objc private func themeChanged(_ sender: UISegmentedControl) {
        defaults.set(sender.selectedSegmentIndex, forKey: "theme.mode")
        NotificationCenter.default.post(name: AppThemeController.changed, object: nil)
    }

    private var launchBookshelfSubtitle: String {
        switch habitTracker.launchMode {
        case .automatic: return habitTracker.currentAutoSubtitle
        case .my: return "启动默认显示我的书架"
        case .local: return "启动默认显示本地书架"
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
        ("去白边", "reader.crop.white.margins", \.cropWhiteMargins)
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
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : toggles.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "阅读主题的“默认”跟随手机系统，独立于 App 主题。" : "设置保存在本机。"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Palette.card
        cell.textLabel?.textColor = Palette.text
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.selectionStyle = .none
        if indexPath.section == 0 {
            let labels = [["条漫", "单页"], ["触碰", "按钮", "滑动"], ["默认", "深色", "浅色"]]
            let titles = ["阅读布局", "翻页方式", "阅读主题"]
            let selected = [settings.layout.rawValue, settings.turnMode.rawValue, settings.theme.rawValue]
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
        default: settings.theme = ReaderTheme(rawValue: control.selectedSegmentIndex) ?? .system
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
