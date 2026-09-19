import UIKit
import ComicCore

final class SettingsViewController: UITableViewController {
    private let store: ReaderPreferencesStore
    init(store: ReaderPreferencesStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        tableView.backgroundColor = Palette.background
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "阅读设置"
        cell.textLabel?.textColor = Palette.text
        cell.backgroundColor = Palette.card
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(ReaderSettingsViewController(store: store), animated: true)
    }
}

final class ReaderSettingsViewController: UITableViewController {
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
        section == 0 ? "阅读主题的“默认”跟随手机系统，独立于 App 主题。" : "设置会保存在本机；阅读器功能将在后续内测版本接入。"
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
    }

    @objc private func toggleChanged(_ control: UISwitch) {
        settings[keyPath: toggles[control.tag].2] = control.isOn
        store.save(settings)
    }
}
