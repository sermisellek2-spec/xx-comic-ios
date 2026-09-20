import UIKit
import ComicCore

@MainActor
final class TextReaderSettingsViewController: UITableViewController {
    private var settings: TextReaderPreferences
    private let onChange: (TextReaderPreferences) -> Void
    var onDismiss: (() -> Void)?
    init(settings: TextReaderPreferences, onChange: @escaping (TextReaderPreferences) -> Void) {
        self.settings = settings; self.onChange = onChange
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "文字排版"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }
    @objc private func close() { dismiss(animated: true) { [weak self] in self?.onDismiss?() } }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 4 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        switch indexPath.row {
        case 0:
            cell.textLabel?.text = "字号 · \(settings.fontSize)"
            let stepper = UIStepper(); stepper.minimumValue = 12; stepper.maximumValue = 32
            stepper.stepValue = 1; stepper.value = Double(settings.fontSize)
            stepper.accessibilityIdentifier = "epub.fontSize"
            stepper.addTarget(self, action: #selector(fontChanged(_:)), for: .valueChanged)
            cell.accessoryView = stepper
        case 1:
            cell.textLabel?.text = "行距"
            let control = UISegmentedControl(items: ["紧凑", "标准", "宽松"])
            control.selectedSegmentIndex = settings.lineHeight < 1.625 ? 0 : (settings.lineHeight > 1.875 ? 2 : 1)
            control.addTarget(self, action: #selector(lineChanged(_:)), for: .valueChanged); cell.accessoryView = control
        case 2:
            cell.textLabel?.text = "主题"
            let control = UISegmentedControl(items: ["浅白", "护眼", "夜空"])
            control.selectedSegmentIndex = settings.theme.rawValue
            control.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged); cell.accessoryView = control
        default:
            cell.textLabel?.text = "翻页"
            let control = UISegmentedControl(items: ["连续滚动", "点击翻页"])
            control.selectedSegmentIndex = settings.pagedMode ? 1 : 0
            control.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged); cell.accessoryView = control
        }
        return cell
    }
    private func changed() { onChange(settings); tableView.reloadData() }
    @objc private func fontChanged(_ sender: UIStepper) { settings.fontSize = Int(sender.value); changed() }
    @objc private func lineChanged(_ sender: UISegmentedControl) { settings.lineHeight = [1.5, 1.75, 2][sender.selectedSegmentIndex]; changed() }
    @objc private func themeChanged(_ sender: UISegmentedControl) { settings.theme = TextReaderTheme(rawValue: sender.selectedSegmentIndex) ?? .dark; changed() }
    @objc private func modeChanged(_ sender: UISegmentedControl) { settings.pagedMode = sender.selectedSegmentIndex == 1; changed() }
}
