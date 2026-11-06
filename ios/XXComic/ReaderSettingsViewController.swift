import UIKit
import ComicCore

@MainActor
final class ReaderSettingsViewController: UIViewController, UIViewControllerTransitioningDelegate {
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?

    // MARK: - 2.0.41 ~ 2.0.43 Properties and Callbacks
    var autoScaleEnabled: Bool = false {
        didSet {
            if isViewLoaded {
                autoScaleSwitch?.isOn = autoScaleEnabled
                scaleOptionsContainer?.isHidden = !autoScaleEnabled
            }
        }
    }
    var scaleMode: Int = ReaderScalePolicy.SMART {
        didSet {
            if isViewLoaded {
                updateScaleChips()
            }
        }
    }
    var onAutoScaleChanged: ((Bool, Int) -> Void)?

    var spreadEnabled: Bool = false {
        didSet {
            if isViewLoaded {
                spreadSwitch?.isOn = spreadEnabled
                spreadActionsRow?.isHidden = !spreadEnabled
            }
        }
    }
    var spreadStatus: String? {
        didSet {
            if isViewLoaded {
                spreadSubtitleLabel?.text = spreadStatus ?? "只合并接缝明确的相邻图片，按本书记忆"
            }
        }
    }
    var onSpreadEnabledChanged: ((Bool) -> Void)?
    var onSpreadActions: (() -> Void)?

    var doublePageEnabled: Bool = false {
        didSet {
            if isViewLoaded {
                doublePageSwitch?.isOn = doublePageEnabled
                doublePageActionsRow?.isHidden = !doublePageEnabled
            }
        }
    }
    var doublePageStatus: String? {
        didSet {
            if isViewLoaded {
                doublePageSubtitleLabel?.text = doublePageStatus ?? "宽图自动切为左右两页，按本书记忆"
            }
        }
    }
    var onDoublePageEnabledChanged: ((Bool) -> Void)?
    var onDoublePageActions: (() -> Void)?

    private let store: ReaderPreferencesStore
    private var settings: ReaderPreferences
    private let content = UIStackView()
    private var choices: [[ReaderSettingCard]] = []
    private var enhancementChoices: UIView!
    private var comparisonRow: UIView!
    private var enhancementSwitch: UISwitch!
    private var dragStartHeight: CGFloat = 0
    private var userResized = false

    private var autoScaleSwitch: UISwitch?
    private var scaleOptionsContainer: UIView?
    private var scaleChips: [ReaderScaleChip] = []
    private var scaleHintLabel: UILabel?

    private var spreadSwitch: UISwitch?
    private var spreadSubtitleLabel: UILabel?
    private var spreadActionsRow: UIView?

    private var doublePageSwitch: UISwitch?
    private var doublePageSubtitleLabel: UILabel?
    private var doublePageActionsRow: UIView?

    private let toggles: [(String, String?, String, WritableKeyPath<ReaderPreferences, Bool>)] = [
        ("隐藏右下角状态信息", nil, "reader.fully.immersive", \.fullyImmersive),
        ("墨水屏模式", nil, "reader.display.mode", \.inkScreen),
        ("搓指放大", nil, "reader.pinch.zoom", \.pinchZoom),
        ("禁止动画翻页", "开启后直接切页，左右滑动仅在单页模式生效", "reader.disable.page.animation", \.disablePageAnimation),
        ("去白边", "自动裁去图片外围白边，原文件不变", "reader.crop.white.margins", \.cropWhiteMargins)
    ]

    init(store: ReaderPreferencesStore) {
        self.store = store
        self.settings = store.load()
        let defaults = UserDefaults.standard
        self.autoScaleEnabled = defaults.bool(forKey: "reader.auto.scale.enabled")
        self.scaleMode = ReaderScalePolicy.normalize(defaults.integer(forKey: "reader.scale.mode"))
        self.spreadEnabled = defaults.bool(forKey: "reader.spread.enabled")
        self.doublePageEnabled = defaults.bool(forKey: "reader.double.page.enabled")
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = self
        preferredContentSize = CGSize(width: 0, height: 570)
    }

    convenience init(store: ReaderPreferencesStore,
                     spreadEnabled: Bool,
                     spreadStatus: String? = nil,
                     doublePageEnabled: Bool = false,
                     doublePageStatus: String? = nil,
                     autoScaleEnabled: Bool = false,
                     scaleMode: Int = ReaderScalePolicy.SMART) {
        self.init(store: store)
        self.spreadEnabled = spreadEnabled
        self.spreadStatus = spreadStatus
        self.doublePageEnabled = doublePageEnabled
        self.doublePageStatus = doublePageStatus
        self.autoScaleEnabled = autoScaleEnabled
        self.scaleMode = scaleMode
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true
        view.backgroundColor = ReaderSettingColors.panel

        let handle = UIView()
        handle.backgroundColor = ReaderSettingColors.border
        handle.layer.cornerRadius = 2

        let heading = UILabel()
        heading.text = "阅读设置"
        heading.font = .systemFont(ofSize: 17, weight: .bold)
        heading.textColor = ReaderSettingColors.text
        heading.accessibilityTraits = .header

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = ReaderSettingColors.secondary
        close.accessibilityLabel = "关闭"
        close.accessibilityIdentifier = "reader.settings.close"
        close.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [heading, close])
        header.alignment = .center
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        header.heightAnchor.constraint(equalToConstant: 40).isActive = true
        header.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHeader(_:))))

        let scroll = UIScrollView()
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsVerticalScrollIndicator = false
        scroll.accessibilityIdentifier = "reader.settings.content"

        content.axis = .vertical
        content.spacing = 0

        // 1. Reading Mode
        content.addArrangedSubview(choiceRow(title: "阅读模式", items: [("卷轴模式", .readerStrip), ("普通模式", .readerPage), ("日漫模式", .readerManga)], group: 0))

        // 2. Reading Theme
        content.addArrangedSubview(choiceRow(title: "阅读主题", items: [("默认", .automatic), ("深色", .moon), ("浅色", .sun)], group: 1))

        // 3. Status Badge, Eink, Pinch Zoom
        for index in 0..<3 {
            let item = toggles[index]
            let (row, toggle, _) = switchRow(title: item.0, subtitle: item.1, identifier: item.2, isOn: settings[keyPath: item.3])
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self, let toggle else { return }
                self.settings[keyPath: self.toggles[index].3] = toggle.isOn
                self.save()
            }, for: .valueChanged)
            content.addArrangedSubview(row)
        }

        // 4. Auto Scale (自动缩放画面)
        setupAutoScaleRow()

        // 5. Disable Animation & Crop White Margins
        for index in 3..<5 {
            let item = toggles[index]
            let (row, toggle, _) = switchRow(title: item.0, subtitle: item.1, identifier: item.2, isOn: settings[keyPath: item.3])
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self, let toggle else { return }
                self.settings[keyPath: self.toggles[index].3] = toggle.isOn
                self.save()
            }, for: .valueChanged)
            content.addArrangedSubview(row)
        }

        // 6. Spread Restoration (跨页还原)
        setupSpreadRestorationRow()

        // 7. Double-Page Splitting (自动切分双页)
        setupDoublePageRow()

        // 8. Image Enhancement
        let enhancement = switchRow(title: "图像增强", subtitle: "本地 2 倍 AI 超分；清晰原图自动跳过", identifier: "reader.enhancement.enabled", isOn: settings.enhancementMode != 0)
        enhancementSwitch = enhancement.1
        enhancementSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.enhancementMode = self.enhancementSwitch.isOn ? 2 : 0
            self.save()
        }, for: .valueChanged)
        content.addArrangedSubview(enhancement.0)

        enhancementChoices = choiceRow(title: "增强方式", items: [("普通增强", .lightning), ("2倍超分", .lightning)], group: 2)
        content.addArrangedSubview(enhancementChoices)

        let comparison = switchRow(title: "显示对比提示", subtitle: "显示增强状态，按住提示查看原图", identifier: "reader.enhancement.comparison", isOn: settings.enhancementComparison)
        comparisonRow = comparison.0
        comparison.1.addAction(UIAction { [weak self, weak toggle = comparison.1] _ in
            guard let toggle else { return }
            self?.settings.enhancementComparison = toggle.isOn
            self?.save()
        }, for: .valueChanged)
        content.addArrangedSubview(comparisonRow)

        for child in [handle, header, scroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 32),
            handle.heightAnchor.constraint(equalToConstant: 4),

            header.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        updateSelections()
    }

    private func setupAutoScaleRow() {
        let (scaleRow, scaleToggle, _) = switchRow(
            title: "自动缩放画面",
            subtitle: "选择画面如何适应阅读区域",
            identifier: "reader.settings.autoScale",
            isOn: autoScaleEnabled
        )
        autoScaleSwitch = scaleToggle
        scaleToggle.addAction(UIAction { [weak self, weak scaleToggle] _ in
            guard let self, let scaleToggle else { return }
            self.autoScaleEnabled = scaleToggle.isOn
            self.scaleOptionsContainer?.isHidden = !scaleToggle.isOn
            UserDefaults.standard.set(self.autoScaleEnabled, forKey: "reader.auto.scale.enabled")
            UserDefaults.standard.set(self.scaleMode, forKey: "reader.scale.mode")
            self.onAutoScaleChanged?(self.autoScaleEnabled, self.scaleMode)
            self.onChange?()
            self.userResized = false
            self.view.setNeedsLayout()
        }, for: .valueChanged)
        content.addArrangedSubview(scaleRow)

        let scaleContainer = UIStackView()
        scaleContainer.axis = .vertical
        scaleContainer.spacing = 8
        scaleContainer.translatesAutoresizingMaskIntoConstraints = false

        scaleChips.removeAll()
        for row in 0..<3 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually
            for col in 0..<2 {
                let mode = row * 2 + col
                let chip = ReaderScaleChip(mode: mode)
                chip.addAction(UIAction { [weak self] _ in
                    guard let self, self.autoScaleEnabled else { return }
                    guard self.scaleMode != mode else { return }
                    self.scaleMode = mode
                    self.updateScaleChips()
                    UserDefaults.standard.set(self.scaleMode, forKey: "reader.scale.mode")
                    self.onAutoScaleChanged?(true, self.scaleMode)
                    self.onChange?()
                }, for: .touchUpInside)
                scaleChips.append(chip)
                rowStack.addArrangedSubview(chip)
            }
            scaleContainer.addArrangedSubview(rowStack)
        }

        let scaleHint = UILabel()
        scaleHint.font = .systemFont(ofSize: 12)
        scaleHint.textColor = ReaderSettingColors.secondary
        scaleHint.numberOfLines = 0
        scaleHint.accessibilityIdentifier = "reader.settings.scaleHint"
        scaleHint.text = ReaderScalePolicy.description(scaleMode)
        scaleHintLabel = scaleHint
        scaleContainer.addArrangedSubview(scaleHint)

        let scaleHost = UIView()
        scaleHost.translatesAutoresizingMaskIntoConstraints = false
        scaleHost.addSubview(scaleContainer)
        let top = scaleContainer.topAnchor.constraint(equalTo: scaleHost.topAnchor, constant: 4)
        let bottom = scaleContainer.bottomAnchor.constraint(equalTo: scaleHost.bottomAnchor, constant: -12)
        top.priority = .init(999)
        bottom.priority = .init(999)
        NSLayoutConstraint.activate([
            scaleContainer.leadingAnchor.constraint(equalTo: scaleHost.leadingAnchor, constant: 16),
            scaleContainer.trailingAnchor.constraint(equalTo: scaleHost.trailingAnchor),
            top, bottom
        ])
        scaleHost.isHidden = !autoScaleEnabled
        scaleOptionsContainer = scaleHost
        content.addArrangedSubview(scaleHost)
    }

    private func setupSpreadRestorationRow() {
        let (spreadRow, spreadToggle, spreadSubLabel) = switchRow(
            title: "跨页还原（自动识别）",
            subtitle: spreadStatus ?? "只合并接缝明确的相邻图片，按本书记忆",
            identifier: "reader.settings.spread",
            isOn: spreadEnabled
        )
        spreadSwitch = spreadToggle
        spreadSubtitleLabel = spreadSubLabel
        spreadToggle.addAction(UIAction { [weak self, weak spreadToggle] _ in
            guard let self, let spreadToggle else { return }
            self.spreadEnabled = spreadToggle.isOn
            self.spreadActionsRow?.isHidden = !spreadToggle.isOn
            UserDefaults.standard.set(self.spreadEnabled, forKey: "reader.spread.enabled")
            if self.spreadEnabled && self.doublePageEnabled {
                self.doublePageEnabled = false
                self.doublePageSwitch?.setOn(false, animated: true)
                self.doublePageActionsRow?.isHidden = true
                UserDefaults.standard.set(false, forKey: "reader.double.page.enabled")
                self.onDoublePageEnabledChanged?(false)
            }
            self.onSpreadEnabledChanged?(self.spreadEnabled)
            self.onChange?()
            self.userResized = false
            self.view.setNeedsLayout()
        }, for: .valueChanged)
        content.addArrangedSubview(spreadRow)

        let (spreadActionView, spreadActionControl) = actionEntryRow(
            title: "跨页操作",
            subtitle: "合并、拆开、调整左右顺序",
            identifier: "reader.settings.spreadActions"
        )
        spreadActionControl.addAction(UIAction { [weak self] _ in
            self?.close()
            self?.onSpreadActions?()
        }, for: .touchUpInside)
        spreadActionView.isHidden = !spreadEnabled
        spreadActionsRow = spreadActionView
        content.addArrangedSubview(spreadActionView)
    }

    private func setupDoublePageRow() {
        let (doublePageRow, doublePageToggle, doublePageSubLabel) = switchRow(
            title: "自动切分双页",
            subtitle: doublePageStatus ?? "宽图自动切为左右两页，按本书记忆",
            identifier: "reader.settings.doublePage",
            isOn: doublePageEnabled
        )
        doublePageSwitch = doublePageToggle
        doublePageSubtitleLabel = doublePageSubLabel
        doublePageToggle.addAction(UIAction { [weak self, weak doublePageToggle] _ in
            guard let self, let doublePageToggle else { return }
            self.doublePageEnabled = doublePageToggle.isOn
            self.doublePageActionsRow?.isHidden = !doublePageToggle.isOn
            UserDefaults.standard.set(self.doublePageEnabled, forKey: "reader.double.page.enabled")
            if self.doublePageEnabled && self.spreadEnabled {
                self.spreadEnabled = false
                self.spreadSwitch?.setOn(false, animated: true)
                self.spreadActionsRow?.isHidden = true
                UserDefaults.standard.set(false, forKey: "reader.spread.enabled")
                self.onSpreadEnabledChanged?(false)
            }
            self.onDoublePageEnabledChanged?(self.doublePageEnabled)
            self.onChange?()
            self.userResized = false
            self.view.setNeedsLayout()
        }, for: .valueChanged)
        content.addArrangedSubview(doublePageRow)

        let (doublePageActionView, doublePageActionControl) = actionEntryRow(
            title: "双页操作",
            subtitle: "调整左右顺序、强制切分或保持整页",
            identifier: "reader.settings.doublePageActions"
        )
        doublePageActionControl.addAction(UIAction { [weak self] _ in
            self?.close()
            self?.onDoublePageActions?()
        }, for: .touchUpInside)
        doublePageActionView.isHidden = !doublePageEnabled
        doublePageActionsRow = doublePageActionView
        content.addArrangedSubview(doublePageActionView)
    }

    private func actionEntryRow(title: String, subtitle: String, identifier: String) -> (UIView, UIControl) {
        let row = UIControl()
        row.accessibilityIdentifier = identifier
        row.accessibilityTraits = .button
        row.accessibilityLabel = "\(title)，\(subtitle)"

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = ReaderSettingColors.text

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = ReaderSettingColors.secondary
        subtitleLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.isUserInteractionEnabled = false

        let arrow = UILabel()
        arrow.text = "›"
        arrow.font = .systemFont(ofSize: 24, weight: .regular)
        arrow.textColor = ReaderSettingColors.secondary
        arrow.textAlignment = .center
        arrow.widthAnchor.constraint(equalToConstant: 36).isActive = true
        arrow.isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [textStack, arrow])
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)

        let host = UIView()
        host.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(row)

        let top = row.topAnchor.constraint(equalTo: host.topAnchor, constant: 4)
        let bottom = row.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -8)
        top.priority = .init(999)
        bottom.priority = .init(999)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            top, bottom,
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
        return (host, row)
    }

    private func updateScaleChips() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        for chip in scaleChips {
            chip.updateSelection(isSelected: chip.mode == scaleMode, isDark: isDark)
        }
        scaleHintLabel?.text = ReaderScalePolicy.description(scaleMode)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateScaleChips()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !userResized else { return }
        let contentWidth = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 36
        let size = content.systemLayoutSizeFitting(CGSize(width: max(1, contentWidth), height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let windowHeight = presentationController?.containerView?.bounds.height ?? view.window?.bounds.height ?? view.bounds.height
        // The Android sheet caps its scrolling content at 65% of the window,
        // while the handle, heading and bottom padding remain outside it.
        let height = min(size.height, windowHeight * 0.65) + 82 + view.safeAreaInsets.bottom
        if abs(preferredContentSize.height - height) > 1 { preferredContentSize.height = height }
    }

    private func choiceRow(title: String, items: [(String, ParityIcon)], group: Int) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14)
        label.textColor = ReaderSettingColors.text
        label.numberOfLines = 2
        label.widthAnchor.constraint(equalToConstant: 68).isActive = true

        let cards = UIStackView()
        cards.spacing = 8
        cards.distribution = .fillEqually

        var groupCards: [ReaderSettingCard] = []
        for (index, item) in items.enumerated() {
            let card = ReaderSettingCard(title: item.0, icon: item.1)
            card.accessibilityIdentifier = ["reader.layout", "reader.theme", "reader.enhancement.mode"][group] + ".\(group == 2 ? index + 1 : index)"
            card.addAction(UIAction { [weak self] _ in self?.select(group: group, index: index) }, for: .touchUpInside)
            cards.addArrangedSubview(card)
            groupCards.append(card)
        }
        choices.append(groupCards)
        cards.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let row = UIStackView(arrangedSubviews: [label, cards])
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 10, right: 0)

        let host = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(row)
        let top = row.topAnchor.constraint(equalTo: host.topAnchor)
        let bottom = row.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        top.priority = .init(999)
        bottom.priority = .init(999)
        NSLayoutConstraint.activate([
            top, bottom,
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        ])
        return host
    }

    private func switchRow(title: String, subtitle: String?, identifier: String, isOn: Bool) -> (UIView, UISwitch, UILabel?) {
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = ReaderSettingColors.accent
        toggle.transform = CGAffineTransform(scaleX: 0.67, y: 0.67)

        let switchHost = UIView()
        switchHost.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        switchHost.addSubview(toggle)
        NSLayoutConstraint.activate([
            switchHost.widthAnchor.constraint(equalToConstant: 34),
            switchHost.heightAnchor.constraint(equalToConstant: 24),
            toggle.centerXAnchor.constraint(equalTo: switchHost.centerXAnchor),
            toggle.centerYAnchor.constraint(equalTo: switchHost.centerYAnchor)
        ])

        toggle.thumbTintColor = isOn ? .white : ReaderSettingColors.switchThumbOff
        toggle.addAction(UIAction { [weak toggle] _ in
            guard let toggle else { return }
            toggle.thumbTintColor = toggle.isOn ? .white : ReaderSettingColors.switchThumbOff
        }, for: .valueChanged)

        let row = ReaderSettingSwitchRow(toggle: toggle)
        let label = UILabel()
        label.text = title
        label.textColor = ReaderSettingColors.text
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0

        let copy = UIStackView(arrangedSubviews: [label])
        copy.axis = .vertical
        copy.spacing = 2
        var hintLabel: UILabel?
        if let subtitle {
            let hint = UILabel()
            hint.text = subtitle
            hint.textColor = ReaderSettingColors.secondary
            hint.font = .systemFont(ofSize: 12)
            hint.numberOfLines = 0
            copy.addArrangedSubview(hint)
            hintLabel = hint
        }

        toggle.accessibilityIdentifier = identifier
        toggle.accessibilityLabel = title
        toggle.accessibilityHint = subtitle
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addAction(UIAction { [weak toggle] _ in
            guard let toggle else { return }
            toggle.setOn(!toggle.isOn, animated: true)
            toggle.sendActions(for: .valueChanged)
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [copy, switchHost])
        stack.spacing = 12
        stack.alignment = .center
        stack.isUserInteractionEnabled = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        row.accessibilityElements = [toggle]

        let verticalPadding: CGFloat = 10
        let top = stack.topAnchor.constraint(equalTo: row.topAnchor, constant: verticalPadding)
        let bottom = stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -verticalPadding)
        let minimumHeight = row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        for constraint in [top, bottom, minimumHeight] { constraint.priority = .init(999) }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            top, bottom, minimumHeight
        ])
        return (row, toggle, hintLabel)
    }

    private func select(group: Int, index: Int) {
        if group == 0 {
            settings.readingMode = ReaderReadingMode(rawValue: index) ?? .scroll
        } else if group == 1 {
            settings.theme = ReaderTheme(rawValue: index) ?? .system
        } else {
            settings.enhancementMode = index + 1
        }
        save()
    }

    private func save() {
        store.save(settings)
        onChange?()
        updateSelections()
    }

    private func updateSelections() {
        let selected = [settings.readingMode.rawValue, settings.theme.rawValue, settings.enhancementMode - 1]
        for (group, cards) in choices.enumerated() {
            for (index, card) in cards.enumerated() {
                card.setSelection(index == selected[group])
            }
        }
        enhancementChoices.isHidden = settings.enhancementMode == 0
        comparisonRow.isHidden = settings.enhancementMode == 0
        updateScaleChips()
        userResized = false
        view.setNeedsLayout()
    }

    fileprivate func close() {
        if let onClose {
            onClose()
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func dragHeader(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began {
            dragStartHeight = view.bounds.height
            userResized = true
        }
        if pan.state == .changed {
            preferredContentSize.height = max(220, dragStartHeight - pan.translation(in: view).y)
        }
        if pan.state == .ended, pan.translation(in: view).y > 60, pan.velocity(in: view).y > 300 {
            close()
        }
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        ReaderSettingsPresentation(presentedViewController: presented, presenting: presenting)
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        ReaderSettingsAnimation(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        ReaderSettingsAnimation(presenting: false)
    }
}

// MARK: - ReaderSettingSwitchRow

@MainActor
private final class ReaderSettingSwitchRow: UIControl {
    private let toggle: UISwitch
    init(toggle: UISwitch) {
        self.toggle = toggle
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit === toggle || hit.isDescendant(of: toggle) ? hit : self
    }
}

// MARK: - ReaderSettingCard

@MainActor
private final class ReaderSettingCard: UIControl {
    private let icon: UIImageView
    private let label = UILabel()

    init(title: String, icon: ParityIcon) {
        self.icon = UIImageView(image: icon.image(size: 22))
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        layer.cornerRadius = 8
        label.text = title
        label.font = .systemFont(ofSize: 12)
        label.textAlignment = .center
        for child in [self.icon, label] {
            child.isUserInteractionEnabled = false
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            self.icon.widthAnchor.constraint(equalToConstant: 22),
            self.icon.heightAnchor.constraint(equalToConstant: 22),
            self.icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            self.icon.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: self.icon.bottomAnchor, constant: 5),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
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
        super.traitCollectionDidChange(previousTraitCollection)
        setSelection(isSelected)
    }
}

// MARK: - ReaderScaleChip

@MainActor
private final class ReaderScaleChip: UIControl {
    let mode: Int
    private let titleLabel = UILabel()

    init(mode: Int) {
        self.mode = mode
        super.init(frame: .zero)
        layer.cornerRadius = 10
        layer.borderWidth = 1
        isAccessibilityElement = true
        accessibilityIdentifier = "reader.settings.scaleMode.\(mode)"
        accessibilityTraits = .button

        titleLabel.text = ReaderScalePolicy.label(mode)
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textAlignment = .center
        titleLabel.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func updateSelection(isSelected: Bool, isDark: Bool) {
        self.isSelected = isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        accessibilityLabel = "\(ReaderScalePolicy.label(mode))\(isSelected ? "，已选中" : "")"

        if isSelected {
            backgroundColor = isDark
                ? UIColor(red: 22/255, green: 54/255, blue: 83/255, alpha: 1)
                : UIColor(red: 234/255, green: 244/255, blue: 255/255, alpha: 1)
            layer.borderColor = UIColor(red: 64/255, green: 153/255, blue: 237/255, alpha: 1).cgColor
            titleLabel.textColor = isDark
                ? UIColor(red: 140/255, green: 203/255, blue: 255/255, alpha: 1)
                : UIColor(red: 9/255, green: 105/255, blue: 218/255, alpha: 1)
            titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        } else {
            backgroundColor = isDark
                ? UIColor(red: 37/255, green: 44/255, blue: 53/255, alpha: 1)
                : UIColor(red: 246/255, green: 248/255, blue: 250/255, alpha: 1)
            layer.borderColor = isDark
                ? UIColor(red: 57/255, green: 66/255, blue: 77/255, alpha: 1).cgColor
                : UIColor(red: 216/255, green: 222/255, blue: 228/255, alpha: 1).cgColor
            titleLabel.textColor = isDark
                ? UIColor(red: 230/255, green: 237/255, blue: 243/255, alpha: 1)
                : UIColor(red: 31/255, green: 35/255, blue: 40/255, alpha: 1)
            titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        }
    }
}

// MARK: - ReaderSettingColors

private enum ReaderSettingColors {
    static let panel = color(0xFFFFFF, 0x1C2128), text = color(0x1F2328, 0xE6EDF3)
    static let secondary = color(0x656D76, 0x8B949E), border = color(0xD0D7DE, 0x444C56)
    static let accent = color(0x0969DA, 0x58A6FF), unselected = color(0xF6F8FA, 0x22272E)
    static let switchThumbOff = color(0x8C959F, 0xD0D7DE)
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

// MARK: - Presentation & Animation

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
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        backdrop.alpha = 0
        backdrop.frame = containerView.bounds
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        containerView.insertSubview(backdrop, at: 0)
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 1 })
    }
    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 0 })
    }
    override func containerViewWillLayoutSubviews() {
        backdrop.frame = containerView?.bounds ?? .zero
        presentedView?.frame = frameOfPresentedViewInContainerView
        presentedView?.layer.cornerRadius = 16
        presentedView?.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        presentedView?.clipsToBounds = true
    }
    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        containerView?.setNeedsLayout()
    }
    @objc private func close() {
        (presentedViewController as? ReaderSettingsViewController)?.close()
    }
}

@MainActor
final class ReaderSettingsAnimation: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.24 }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let controller = context.viewController(forKey: presenting ? .to : .from), let view = controller.view else {
            context.completeTransition(false)
            return
        }
        if presenting {
            context.containerView.addSubview(view)
            view.frame = context.finalFrame(for: controller)
        }
        let distance = max(view.bounds.height, context.containerView.bounds.maxY - view.frame.minY)
        if presenting { view.transform = CGAffineTransform(translationX: 0, y: distance) }
        UIView.animate(withDuration: transitionDuration(using: context), animations: {
            view.transform = self.presenting ? .identity : CGAffineTransform(translationX: 0, y: distance)
        }, completion: { _ in context.completeTransition(!context.transitionWasCancelled) })
    }
}
