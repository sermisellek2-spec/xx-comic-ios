import UIKit
import ComicCore

@MainActor
final class TextReaderSettingsViewController: UITableViewController, UIViewControllerTransitioningDelegate {
    private var settings: TextReaderPreferences
    private let onChange: (TextReaderPreferences) -> Void
    var onDismiss: (() -> Void)?
    init(settings: TextReaderPreferences, onChange: @escaping (TextReaderPreferences) -> Void) {
        self.settings = settings; self.onChange = onChange
        super.init(style: .plain)
        modalPresentationStyle = .custom; transitioningDelegate = self
        preferredContentSize = CGSize(width: 0, height: 289)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "文字排版设置"
        tableView.backgroundColor = Palette.card
        tableView.separatorStyle = .none; tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = 0; tableView.sectionFooterHeight = 0
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.contentInset.bottom = 20
        tableView.accessibilityIdentifier = "epub.text.settings"
        tableView.tableHeaderView = TextReaderSettingsHeader(close: { [weak self] in self?.close() })
        view.accessibilityViewIsModal = true
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView, header.bounds.width != tableView.bounds.width else { return }
        header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 79)
        tableView.tableHeaderView = header
    }
    fileprivate func close() { let callback = onDismiss; dismiss(animated: true, completion: callback) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 4 }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { [52, 48, 48, 42][indexPath.row] }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none; cell.backgroundColor = Palette.card
        let row = UIStackView(); row.axis = .horizontal; row.alignment = .center; row.spacing = 6
        let label = UILabel(); label.font = .systemFont(ofSize: 13); label.textColor = Palette.text2
        label.numberOfLines = 0; row.addArrangedSubview(label)
        switch indexPath.row {
        case 0:
            label.text = "字体大小"; label.isAccessibilityElement = false
            let minus = TextReaderChoiceButton(title: "−", selected: false)
            minus.titleLabel?.font = .systemFont(ofSize: 20); minus.accessibilityLabel = "减小字号"
            minus.accessibilityIdentifier = "epub.fontSize-Decrement"; minus.isEnabled = settings.fontSize > 12
            minus.alpha = minus.isEnabled ? 1 : 0.4
            let plus = TextReaderChoiceButton(title: "+", selected: false)
            plus.titleLabel?.font = .systemFont(ofSize: 20); plus.accessibilityLabel = "增大字号"
            plus.accessibilityIdentifier = "epub.fontSize-Increment"; plus.isEnabled = settings.fontSize < 32
            plus.alpha = plus.isEnabled ? 1 : 0.4
            let value = UILabel(); value.text = "\(settings.fontSize) sp"; value.textColor = Palette.text
            value.accessibilityLabel = "字体大小 · \(settings.fontSize) sp"
            value.font = .systemFont(ofSize: 13, weight: .bold); value.textAlignment = .center
            minus.addAction(UIAction { [weak self] _ in self?.changeFont(-1) }, for: .touchUpInside)
            plus.addAction(UIAction { [weak self] _ in self?.changeFont(1) }, for: .touchUpInside)
            let controls = UIStackView(arrangedSubviews: [minus, value, plus]); controls.alignment = .center
            value.widthAnchor.constraint(equalToConstant: 64).isActive = true
            for button in [minus, plus] { button.widthAnchor.constraint(equalToConstant: 38).isActive = true }
            row.addArrangedSubview(controls)
            cell.accessibilityElements = [value, minus, plus]
        case 1:
            label.text = "行间距"; row.distribution = .fillEqually
            for (index, title) in ["紧凑", "标准", "宽松"].enumerated() {
                let height = [1.5, 1.75, 2.0][index]
                let button = TextReaderChoiceButton(title: title, selected: abs(settings.lineHeight - height) < 0.05)
                button.accessibilityIdentifier = "epub.lineHeight.\(index)"
                button.addAction(UIAction { [weak self] _ in self?.settings.lineHeight = height; self?.changed() }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
        case 2:
            label.text = "阅读背景"; row.distribution = .fillEqually
            let swatches: [UIColor] = [.white, UIColor(red: 1, green: 205/255, blue: 64/255, alpha: 1), .black]
            for (index, title) in ["浅白", "护眼", "夜空"].enumerated() {
                let button = TextReaderChoiceButton(title: title, selected: settings.theme.rawValue == index)
                var config = UIButton.Configuration.plain(); config.title = title
                config.image = UIImage(systemName: "circle.fill")?.withTintColor(swatches[index], renderingMode: .alwaysOriginal)
                config.imagePlacement = .trailing; config.imagePadding = 4
                config.preferredSymbolConfigurationForImage = .init(pointSize: 10)
                config.contentInsets = .init(top: 0, leading: 4, bottom: 0, trailing: 4)
                config.titleTextAttributesTransformer = .init { attributes in var result = attributes; result.font = .systemFont(ofSize: 12); return result }
                button.configuration = config; button.updateColors()
                button.accessibilityIdentifier = "epub.theme.\(index)"; button.accessibilityHint = "阅读背景：" + title
                button.addAction(UIAction { [weak self] _ in self?.settings.theme = TextReaderTheme(rawValue: index) ?? .dark; self?.changed() }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
        default:
            label.text = "阅读模式"; row.distribution = .fillEqually
            for (index, title) in ["连续滚动", "点击翻页"].enumerated() {
                let button = TextReaderChoiceButton(title: title, selected: settings.pagedMode == (index == 1))
                button.accessibilityIdentifier = "epub.turn.\(index)"
                button.addAction(UIAction { [weak self] _ in self?.settings.pagedMode = index == 1; self?.changed() }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
        }
        row.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor, constant: indexPath.row == 0 ? 0 : -2)
        ])
        return cell
    }
    private func changed() { onChange(settings); tableView.reloadData() }
    private func changeFont(_ delta: Int) { settings.fontSize = max(12, min(32, settings.fontSize + delta)); changed() }
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        TextReaderSettingsPresentation(presentedViewController: presented, presenting: presenting)
    }
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? { ReaderSettingsAnimation(presenting: true) }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? { ReaderSettingsAnimation(presenting: false) }
}

@MainActor
private final class TextReaderChoiceButton: UIButton {
    init(title: String, selected: Bool) {
        super.init(frame: .zero); setTitle(title, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 12); isSelected = selected
        accessibilityLabel = title; accessibilityTraits = selected ? [.button, .selected] : .button
        layer.cornerRadius = 8; layer.borderWidth = 1
        heightAnchor.constraint(equalToConstant: 32).isActive = true; updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    func updateColors() {
        let color = isSelected ? Palette.accent : Palette.text
        setTitleColor(color, for: .normal); setTitleColor(color, for: .selected)
        tintColor = color; configuration?.baseForegroundColor = color
        backgroundColor = isSelected ? Palette.accentSoft : Palette.surface
        layer.borderColor = (isSelected ? Palette.accent : Palette.border).resolvedColor(with: traitCollection).cgColor
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -max(0, (44 - bounds.width) / 2), dy: -max(0, (44 - bounds.height) / 2)).contains(point)
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection); updateColors()
    }
}

@MainActor
private final class TextReaderSettingsHeader: UIView {
    private let handle = UIView(), divider = UIView()
    private let heading = UILabel(), dismissButton = UIButton(type: .system)
    private let onClose: () -> Void
    init(close: @escaping () -> Void) {
        onClose = close
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 79))
        handle.backgroundColor = Palette.border; handle.layer.cornerRadius = 2
        divider.backgroundColor = Palette.borderSoft
        heading.text = "文字排版设置"; heading.textColor = Palette.text; heading.font = .systemFont(ofSize: 15, weight: .bold)
        heading.accessibilityTraits = .header
        dismissButton.setImage(UIImage(systemName: "xmark"), for: .normal); dismissButton.tintColor = Palette.text2
        dismissButton.accessibilityLabel = "关闭"; dismissButton.accessibilityIdentifier = "epub.text.settings.close"
        dismissButton.addAction(UIAction { _ in close() }, for: .touchUpInside)
        for child in [handle, divider, heading, dismissButton] { addSubview(child) }
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHeader(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    @objc private func dragHeader(_ pan: UIPanGestureRecognizer) {
        if pan.state == .ended, pan.translation(in: self).y > 60, pan.velocity(in: self).y > 300 { onClose() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        handle.frame = CGRect(x: (bounds.width - 32) / 2, y: 20, width: 32, height: 4)
        heading.frame = CGRect(x: 16, y: 30, width: max(0, bounds.width - 76), height: 40)
        dismissButton.frame = CGRect(x: bounds.width - 60, y: 28, width: 44, height: 44)
        divider.frame = CGRect(x: 16, y: 78, width: max(0, bounds.width - 32), height: 1)
    }
}

@MainActor
private final class TextReaderSettingsPresentation: UIPresentationController {
    private let backdrop = UIView()
    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let bottom = containerView.bounds.maxY - containerView.safeAreaInsets.bottom - 16
        let available = max(0, bottom - containerView.safeAreaInsets.top - 16)
        let height = min(available, presentedViewController.preferredContentSize.height)
        return CGRect(x: 16, y: bottom - height, width: max(0, containerView.bounds.width - 32), height: height)
    }
    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        backdrop.frame = containerView.bounds; backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.5); backdrop.alpha = 0
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        containerView.insertSubview(backdrop, at: 0)
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 1 })
    }
    override func dismissalTransitionWillBegin() { presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 0 }) }
    override func containerViewWillLayoutSubviews() {
        backdrop.frame = containerView?.bounds ?? .zero; presentedView?.frame = frameOfPresentedViewInContainerView
        presentedView?.layer.cornerRadius = 16; presentedView?.clipsToBounds = true
        presentedView?.layer.borderWidth = 1; presentedView?.layer.borderColor = Palette.border.resolvedColor(with: presentedViewController.traitCollection).cgColor
    }
    @objc private func close() { (presentedViewController as? TextReaderSettingsViewController)?.close() }
}
