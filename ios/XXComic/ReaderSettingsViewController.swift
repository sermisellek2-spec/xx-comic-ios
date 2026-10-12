import UIKit
import ComicCore

@MainActor
final class ReaderSettingsViewController: UIViewController, UIViewControllerTransitioningDelegate {
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?
    private let store: ReaderPreferencesStore
    private var settings: ReaderPreferences
    private let content = UIStackView()
    private var choices: [[ReaderSettingCard]] = []
    private var enhancementChoices: UIView!
    private var comparisonRow: UIView!
    private var enhancementSwitch: UISwitch!
    private var dragStartHeight: CGFloat = 0
    private var userResized = false
    private let toggles: [(String, String?, String, WritableKeyPath<ReaderPreferences, Bool>)] = [
        ("隐藏右下角状态信息", nil, "reader.fully.immersive", \.fullyImmersive),
        ("墨水屏模式", nil, "reader.display.mode", \.inkScreen),
        ("搓指放大", nil, "reader.pinch.zoom", \.pinchZoom),
        ("禁止动画翻页", "开启后直接切页，左右滑动仅在单页模式生效", "reader.disable.page.animation", \.disablePageAnimation),
        ("去白边", "自动裁去图片外围白边，原文件不变", "reader.crop.white.margins", \.cropWhiteMargins)
    ]

    init(store: ReaderPreferencesStore) {
        self.store = store; settings = store.load()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom; transitioningDelegate = self
        preferredContentSize = CGSize(width: 0, height: 570)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true
        view.backgroundColor = ReaderSettingColors.panel
        let handle = UIView(); handle.backgroundColor = ReaderSettingColors.border; handle.layer.cornerRadius = 2
        let heading = UILabel(); heading.text = "阅读设置"; heading.font = .systemFont(ofSize: 17, weight: .bold)
        heading.textColor = ReaderSettingColors.text; heading.accessibilityTraits = .header
        let close = UIButton(type: .system); close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = ReaderSettingColors.secondary; close.accessibilityLabel = "关闭"
        close.accessibilityIdentifier = "reader.settings.close"
        close.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [heading, close]); header.alignment = .center
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        header.heightAnchor.constraint(equalToConstant: 40).isActive = true
        header.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHeader(_:))))
        let scroll = UIScrollView(); scroll.contentInsetAdjustmentBehavior = .never; scroll.showsVerticalScrollIndicator = false
        scroll.accessibilityIdentifier = "reader.settings.content"
        content.axis = .vertical; content.spacing = 0
        content.addArrangedSubview(choiceRow(title: "阅读模式", items: [("卷轴模式", .readerStrip), ("普通模式", .readerPage), ("日漫模式", .readerManga)], group: 0))
        content.addArrangedSubview(choiceRow(title: "阅读主题", items: [("默认", .automatic), ("深色", .moon), ("浅色", .sun)], group: 1))
        for (index, item) in toggles.enumerated() {
            let (row, toggle) = switchRow(title: item.0, subtitle: item.1, identifier: item.2, isOn: settings[keyPath: item.3])
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self, let toggle else { return }; self.settings[keyPath: self.toggles[index].3] = toggle.isOn; self.save()
            }, for: .valueChanged)
            content.addArrangedSubview(row)
        }
        let enhancement = switchRow(title: "图像增强", subtitle: "本地 2 倍 AI 超分；清晰原图自动跳过", identifier: "reader.enhancement.enabled", isOn: settings.enhancementMode != 0)
        enhancementSwitch = enhancement.1
        enhancementSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }; self.settings.enhancementMode = self.enhancementSwitch.isOn ? 2 : 0; self.save()
        }, for: .valueChanged)
        content.addArrangedSubview(enhancement.0)
        enhancementChoices = choiceRow(title: "增强方式", items: [("普通增强", .lightning), ("2倍超分", .lightning)], group: 2)
        content.addArrangedSubview(enhancementChoices)
        let comparison = switchRow(title: "显示对比提示", subtitle: "显示增强状态，按住提示查看原图", identifier: "reader.enhancement.comparison", isOn: settings.enhancementComparison)
        comparisonRow = comparison.0
        comparison.1.addAction(UIAction { [weak self, weak toggle = comparison.1] _ in
            guard let toggle else { return }; self?.settings.enhancementComparison = toggle.isOn; self?.save()
        }, for: .valueChanged)
        content.addArrangedSubview(comparisonRow)
        for child in [handle, header, scroll] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        content.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(content)
        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: view.topAnchor, constant: 12), handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 32), handle.heightAnchor.constraint(equalToConstant: 4),
            header.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 4), header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        updateSelections()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !userResized else { return }
        let size = content.systemLayoutSizeFitting(CGSize(width: max(1, view.bounds.width - 36), height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let height = size.height + 84 + view.safeAreaInsets.bottom
        if abs(preferredContentSize.height - height) > 1 { preferredContentSize.height = height }
    }
    private func choiceRow(title: String, items: [(String, ParityIcon)], group: Int) -> UIView {
        let label = UILabel(); label.text = title; label.font = .systemFont(ofSize: 14); label.textColor = ReaderSettingColors.text
        label.numberOfLines = 2; label.widthAnchor.constraint(equalToConstant: 68).isActive = true
        let cards = UIStackView(); cards.spacing = 8; cards.distribution = .fillEqually
        var groupCards: [ReaderSettingCard] = []
        for (index, item) in items.enumerated() {
            let card = ReaderSettingCard(title: item.0, icon: item.1)
            card.accessibilityIdentifier = ["reader.layout", "reader.theme", "reader.enhancement.mode"][group] + ".\(group == 2 ? index + 1 : index)"
            card.addAction(UIAction { [weak self] _ in self?.select(group: group, index: index) }, for: .touchUpInside)
            cards.addArrangedSubview(card); groupCards.append(card)
        }
        choices.append(groupCards)
        cards.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let row = UIStackView(arrangedSubviews: [label, cards]); row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true; row.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 10, right: 0)
        // The outer view can be hidden by the main stack without forcing the
        // inner cards' fixed geometry to zero and producing layout conflicts.
        let host = UIView(); row.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(row)
        let top = row.topAnchor.constraint(equalTo: host.topAnchor), bottom = row.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        top.priority = .init(999); bottom.priority = .init(999)
        NSLayoutConstraint.activate([top, bottom, row.leadingAnchor.constraint(equalTo: host.leadingAnchor), row.trailingAnchor.constraint(equalTo: host.trailingAnchor)])
        return host
    }
    private func switchRow(title: String, subtitle: String?, identifier: String, isOn: Bool) -> (UIView, UISwitch) {
        let toggle = UISwitch(); toggle.isOn = isOn; toggle.onTintColor = ReaderSettingColors.accent
        let row = ReaderSettingSwitchRow(toggle: toggle)
        let label = UILabel(); label.text = title; label.textColor = ReaderSettingColors.text; label.font = .systemFont(ofSize: 14); label.numberOfLines = 0
        let copy = UIStackView(arrangedSubviews: [label]); copy.axis = .vertical; copy.spacing = 2
        if let subtitle {
            let hint = UILabel(); hint.text = subtitle; hint.textColor = ReaderSettingColors.secondary
            hint.font = .systemFont(ofSize: 12); hint.numberOfLines = 0; copy.addArrangedSubview(hint)
        }
        toggle.accessibilityIdentifier = identifier; toggle.accessibilityLabel = title; toggle.accessibilityHint = subtitle
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addAction(UIAction { [weak toggle] _ in
            guard let toggle else { return }; toggle.setOn(!toggle.isOn, animated: true); toggle.sendActions(for: .valueChanged)
        }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [copy, toggle]); stack.spacing = 12; stack.alignment = .center
        stack.isUserInteractionEnabled = true; stack.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(stack)
        row.accessibilityElements = [toggle]
        let verticalPadding: CGFloat = subtitle == nil ? 4 : 10
        let top = stack.topAnchor.constraint(equalTo: row.topAnchor, constant: verticalPadding), bottom = stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -verticalPadding)
        let minimumHeight = row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        for constraint in [top, bottom, minimumHeight] { constraint.priority = .init(999) }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor), stack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            top, bottom, minimumHeight
        ])
        return (row, toggle)
    }
    private func select(group: Int, index: Int) {
        if group == 0 { settings.readingMode = ReaderReadingMode(rawValue: index) ?? .scroll }
        else if group == 1 { settings.theme = ReaderTheme(rawValue: index) ?? .system }
        else { settings.enhancementMode = index + 1 }
        save()
    }
    private func save() {
        store.save(settings); onChange?(); updateSelections()
    }
    private func updateSelections() {
        let selected = [settings.readingMode.rawValue, settings.theme.rawValue, settings.enhancementMode - 1]
        for (group, cards) in choices.enumerated() {
            for (index, card) in cards.enumerated() { card.setSelection(index == selected[group]) }
        }
        enhancementChoices.isHidden = settings.enhancementMode == 0
        comparisonRow.isHidden = settings.enhancementMode == 0
        userResized = false; view.setNeedsLayout()
    }
    fileprivate func close() { if let onClose { onClose() } else { dismiss(animated: true) } }
    @objc private func dragHeader(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began { dragStartHeight = view.bounds.height; userResized = true }
        if pan.state == .changed { preferredContentSize.height = max(220, dragStartHeight - pan.translation(in: view).y) }
        if pan.state == .ended, pan.translation(in: view).y > 60, pan.velocity(in: view).y > 300 { close() }
    }
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        ReaderSettingsPresentation(presentedViewController: presented, presenting: presenting)
    }
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? { ReaderSettingsAnimation(presenting: true) }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? { ReaderSettingsAnimation(presenting: false) }
}

@MainActor
private final class ReaderSettingSwitchRow: UIControl {
    private let toggle: UISwitch
    init(toggle: UISwitch) { self.toggle = toggle; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit === toggle || hit.isDescendant(of: toggle) ? hit : self
    }
}

@MainActor
private final class ReaderSettingCard: UIControl {
    private let icon: UIImageView
    private let label = UILabel()
    init(title: String, icon: ParityIcon) {
        self.icon = UIImageView(image: icon.image(size: 22)); super.init(frame: .zero)
        isAccessibilityElement = true; accessibilityLabel = title; accessibilityTraits = .button
        layer.cornerRadius = 8
        label.text = title; label.font = .systemFont(ofSize: 12); label.textAlignment = .center
        for child in [self.icon, label] { child.isUserInteractionEnabled = false; child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        NSLayoutConstraint.activate([
            self.icon.widthAnchor.constraint(equalToConstant: 22), self.icon.heightAnchor.constraint(equalToConstant: 22),
            self.icon.centerXAnchor.constraint(equalTo: centerXAnchor), self.icon.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: self.icon.bottomAnchor, constant: 5), label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4), label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    func setSelection(_ selected: Bool) {
        isSelected = selected
        backgroundColor = selected ? ReaderSettingColors.selected : ReaderSettingColors.unselected
        icon.tintColor = selected ? ReaderSettingColors.selectedIcon : ReaderSettingColors.secondary
        label.textColor = selected ? ReaderSettingColors.selectedText : ReaderSettingColors.secondary
        label.font = .systemFont(ofSize: 12, weight: selected ? .medium : .regular)
        layer.borderWidth = selected ? 2 : 1
        layer.borderColor = (selected ? ReaderSettingColors.selectedBorder : ReaderSettingColors.cardBorder).resolvedColor(with: traitCollection).cgColor
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection); setSelection(isSelected)
    }
}

private enum ReaderSettingColors {
    static let panel = color(0xFFFFFF, 0x1C2128), text = color(0x1F2328, 0xE6EDF3)
    static let secondary = color(0x656D76, 0x8B949E), border = color(0xD0D7DE, 0x444C56)
    static let accent = color(0x0969DA, 0x58A6FF), unselected = color(0xF6F8FA, 0x22272E)
    static let selectedIcon = color(0x0969DA, 0x388BFD), selectedText = color(0x0969DA, 0xFFFFFF)
    static let selectedBorder = color(0x0969DA, 0x2E79E6), cardBorder = color(0xD0D7DE, 0x373E47)
    static let selected = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 46/255, green: 121/255, blue: 230/255, alpha: 38/255)
            : UIColor(red: 235/255, green: 245/255, blue: 255/255, alpha: 1)
    }
    private static func color(_ day: Int, _ night: Int) -> UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? night : day
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
}

@MainActor
private final class ReaderSettingsPresentation: UIPresentationController {
    private let backdrop = UIView()
    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let height = min(containerView.bounds.height - containerView.safeAreaInsets.top, max(220, presentedViewController.preferredContentSize.height))
        return CGRect(x: 0, y: containerView.bounds.maxY - height, width: containerView.bounds.width, height: height)
    }
    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.5); backdrop.alpha = 0; backdrop.frame = containerView.bounds
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        containerView.insertSubview(backdrop, at: 0)
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 1 })
    }
    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 0 })
    }
    override func containerViewWillLayoutSubviews() {
        backdrop.frame = containerView?.bounds ?? .zero; presentedView?.frame = frameOfPresentedViewInContainerView
        presentedView?.layer.cornerRadius = 16; presentedView?.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]; presentedView?.clipsToBounds = true
    }
    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container); containerView?.setNeedsLayout()
    }
    @objc private func close() { (presentedViewController as? ReaderSettingsViewController)?.close() }
}

@MainActor
private final class ReaderSettingsAnimation: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.24 }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let controller = context.viewController(forKey: presenting ? .to : .from), let view = controller.view else { context.completeTransition(false); return }
        if presenting {
            context.containerView.addSubview(view); view.frame = context.finalFrame(for: controller)
            view.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
        }
        UIView.animate(withDuration: transitionDuration(using: context), animations: {
            view.transform = self.presenting ? .identity : CGAffineTransform(translationX: 0, y: view.bounds.height)
        }, completion: { _ in context.completeTransition(!context.transitionWasCancelled) })
    }
}
