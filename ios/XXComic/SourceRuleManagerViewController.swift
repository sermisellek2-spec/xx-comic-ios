import UIKit
import ComicCore
import UniformTypeIdentifiers

// MARK: - SourceVpnBadgeView

/// Compact, non-interactive network requirement marker shared by source views.
/// Matches Android 2.0.45's `SourceVpnBadge`.
@MainActor
final class SourceVpnBadgeView: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        label.text = "VPN"
        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        layer.cornerRadius = 3
        layer.borderWidth = 0.5
        layer.masksToBounds = true

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        ])

        updateColors()
        accessibilityLabel = "需要 VPN"
        isAccessibilityElement = true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    private func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        label.textColor = isDark
            ? UIColor(red: 0x9F / 255.0, green: 0xBD / 255.0, blue: 0xD0 / 255.0, alpha: 1.0)
            : UIColor(red: 0x7F / 255.0, green: 0xA5 / 255.0, blue: 0xBD / 255.0, alpha: 1.0)
        backgroundColor = isDark
            ? UIColor(red: 0x27 / 255.0, green: 0x3D / 255.0, blue: 0x4D / 255.0, alpha: 1.0)
            : UIColor(red: 0xF0 / 255.0, green: 0xF7 / 255.0, blue: 0xFB / 255.0, alpha: 1.0)
        layer.borderColor = (isDark
            ? UIColor(red: 0x3D / 255.0, green: 0x58 / 255.0, blue: 0x6B / 255.0, alpha: 1.0)
            : UIColor(red: 0xDC / 255.0, green: 0xEC / 255.0, blue: 0xF4 / 255.0, alpha: 1.0)).cgColor
    }
}

// MARK: - SourceActionDrawerSheet

/// Bottom sheet action drawer matching Android 2.0.44/2.0.45's `SourceActionDrawer`.
/// Drag handle (32x4), header title (17pt bold, no redundant top-right close button per 2.0.45),
/// divider, and scrollable action rows.
@MainActor
final class SourceActionDrawerSheet: UIViewController {

    enum ActionType {
        case subscribe
        case importFile
        case updateSubscriptions
        case exportRules
        case manageGroups
        case batchSelect
    }

    var onAction: ((ActionType) -> Void)?

    private let handle = UIView()
    private let titleLabel = UILabel()
    private let divider = UIView()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init(title: String = "规则操作") {
        super.init(nibName: nil, bundle: nil)
        titleLabel.text = title
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            if #available(iOS 16.0, *) {
                sheet.detents = [.custom(identifier: .init("drawer")) { _ in 430 }, .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 16
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.card
        setupLayout()
        populateActions()
    }

    private func setupLayout() {
        // Drag handle: 32x4 pt, cornerRadius 2
        handle.backgroundColor = Palette.border
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.accessibilityIdentifier = "source.action.drawer.handle"
        view.addSubview(handle)

        // Header title: 17pt bold, no redundant close button per 2.0.45
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.accessibilityIdentifier = "source.action.drawer.title"
        view.addSubview(titleLabel)

        // Divider
        divider.backgroundColor = Palette.borderSoft
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        // ScrollView & StackView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 32),
            handle.heightAnchor.constraint(equalToConstant: 4),

            titleLabel.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            titleLabel.heightAnchor.constraint(equalToConstant: 24),

            divider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func populateActions() {
        addActionRow(
            title: "网址导入 / 添加订阅",
            subtitle: "添加规则仓库或 HTTPS 网址",
            icon: ParityIcon.source.image(size: 22),
            identifier: "source.rule.subscribe",
            action: .subscribe
        )
        addActionRow(
            title: "从文件导入",
            subtitle: "导入 .xxrules.json 或规则包文件",
            icon: ParityIcon.download.image(size: 22),
            identifier: "source.rule.importFile",
            action: .importFile
        )
        addActionRow(
            title: "更新站源订阅",
            subtitle: "检查并更新所有规则订阅",
            icon: ParityIcon.history.image(size: 22),
            identifier: "source.rule.updateSubscriptions",
            action: .updateSubscriptions
        )
        addActionRow(
            title: "导出规则文件",
            subtitle: "将已安装规则导出为 JSON 文件",
            icon: ParityIcon.swap.image(size: 22),
            identifier: "source.rule.export",
            action: .exportRules
        )
        addActionRow(
            title: "站源分组管理",
            subtitle: "管理站源分类和分组",
            icon: ParityIcon.chapterList.image(size: 22),
            identifier: "source.rule.groups",
            action: .manageGroups
        )
        addActionRow(
            title: "批量选择管理",
            subtitle: "批量开启、关闭或删除规则",
            icon: ParityIcon.trash.image(size: 22),
            identifier: "source.rule.batchSelect",
            action: .batchSelect
        )
    }

    private func addActionRow(
        title: String,
        subtitle: String,
        icon: UIImage?,
        identifier: String,
        action: ActionType
    ) {
        let row = UIButton(type: .system)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.accessibilityIdentifier = identifier
        row.accessibilityLabel = title
        row.backgroundColor = Palette.cardSoft
        row.layer.cornerRadius = 10
        row.layer.borderWidth = 0.5
        row.layer.borderColor = Palette.borderSoft.cgColor

        let iconView = UIImageView(image: icon)
        iconView.tintColor = Palette.accent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false

        let titleLbl = UILabel()
        titleLbl.text = title
        titleLbl.font = .systemFont(ofSize: 15, weight: .medium)
        titleLbl.textColor = Palette.text

        let subLbl = UILabel()
        subLbl.text = subtitle
        subLbl.font = .systemFont(ofSize: 12, weight: .regular)
        subLbl.textColor = Palette.secondaryText

        textStack.addArrangedSubview(titleLbl)
        textStack.addArrangedSubview(subLbl)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = Palette.text4
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconView)
        row.addSubview(textStack)
        row.addSubview(chevron)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),

            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 16)
        ])

        row.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: true) {
                self.onAction?(action)
            }
        }, for: .touchUpInside)

        stackView.addArrangedSubview(row)
    }
}

// MARK: - SourceRuleCell

final class SourceRuleCell: UITableViewCell {
    static let reuseIdentifier = "SourceRuleCell"

    private let titleLabel = UILabel()
    private let vpnBadge = SourceVpnBadgeView()
    private let subtitleLabel = UILabel()
    private let enableSwitch = UISwitch()
    private let titleStack = UIStackView()
    private let contentStack = UIStackView()

    var onSwitchToggled: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setupViews() {
        backgroundColor = Palette.card
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = Palette.accentSoft

        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        vpnBadge.translatesAutoresizingMaskIntoConstraints = false
        vpnBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleStack.axis = .horizontal
        titleStack.spacing = 6
        titleStack.alignment = .center
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(vpnBadge)

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = Palette.secondaryText
        subtitleLabel.numberOfLines = 1

        contentStack.axis = .vertical
        contentStack.spacing = 3
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(titleStack)
        contentStack.addArrangedSubview(subtitleLabel)

        enableSwitch.translatesAutoresizingMaskIntoConstraints = false
        enableSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onSwitchToggled?(self.enableSwitch.isOn)
        }, for: .valueChanged)

        contentView.addSubview(contentStack)
        contentView.addSubview(enableSwitch)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: enableSwitch.leadingAnchor, constant: -12),
            contentStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            enableSwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            enableSwitch.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    func configure(
        entry: RuleStore.Entry,
        isBatchMode: Bool,
        isSelected: Bool
    ) {
        let rule = entry.rule
        titleLabel.text = rule.name
        vpnBadge.isHidden = !rule.requiresVpn
        vpnBadge.accessibilityIdentifier = "source.vpn.badge." + rule.id

        let host = URL(string: rule.baseUrl)?.host ?? rule.baseUrl
        let status = entry.enabled ? "已开启" : "已关闭"
        subtitleLabel.text = "\(host) · 规则 v\(rule.version) · \(status)"

        enableSwitch.isOn = entry.enabled
        enableSwitch.accessibilityIdentifier = "source.rule.enabled." + rule.id
        enableSwitch.accessibilityLabel = rule.name
        enableSwitch.isHidden = isBatchMode

        showsReorderControl = !isBatchMode
        accessoryType = isBatchMode ? (isSelected ? .checkmark : .none) : .disclosureIndicator
    }
}

// MARK: - SourceRuleImportPreviewSheet

@MainActor
final class SourceRuleImportPreviewSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let rules: [RuleDefinition]
    private let summary: String
    private let subscriptionUrl: String
    private let onConfirm: ([RuleDefinition]) -> Void

    private let headerLabel = UILabel()
    private let summaryLabel = UILabel()
    private let subUrlLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let cancelBtn = UIButton(type: .system)
    private let confirmBtn = UIButton(type: .system)
    private let actionsStack = UIStackView()

    init(
        rules: [RuleDefinition],
        summary: String,
        subscriptionUrl: String = "",
        onConfirm: @escaping ([RuleDefinition]) -> Void
    ) {
        self.rules = rules
        self.summary = summary
        self.subscriptionUrl = subscriptionUrl
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        title = "导入预览"
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        setupViews()
    }

    private func setupViews() {
        let topBar = UIStackView()
        topBar.axis = .vertical
        topBar.spacing = 6
        topBar.translatesAutoresizingMaskIntoConstraints = false

        headerLabel.text = "站源规则导入预览"
        headerLabel.font = .systemFont(ofSize: 17, weight: .bold)
        headerLabel.textColor = Palette.text

        summaryLabel.text = summary
        summaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        summaryLabel.textColor = Palette.accent
        summaryLabel.numberOfLines = 0

        topBar.addArrangedSubview(headerLabel)
        topBar.addArrangedSubview(summaryLabel)

        if !subscriptionUrl.isEmpty {
            subUrlLabel.text = "同时保存订阅：\(subscriptionUrl)"
            subUrlLabel.font = .systemFont(ofSize: 12, weight: .regular)
            subUrlLabel.textColor = Palette.secondaryText
            subUrlLabel.numberOfLines = 0
            topBar.addArrangedSubview(subUrlLabel)
        }

        view.addSubview(topBar)

        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PreviewCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        cancelBtn.setTitle("取消", for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cancelBtn.setTitleColor(Palette.text, for: .normal)
        cancelBtn.backgroundColor = Palette.cardSoft
        cancelBtn.layer.cornerRadius = 10
        cancelBtn.layer.borderWidth = 0.5
        cancelBtn.layer.borderColor = Palette.borderSoft.cgColor
        cancelBtn.accessibilityIdentifier = "source.rule.preview.cancel"
        cancelBtn.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        confirmBtn.setTitle("确认导入 (\(rules.count))", for: .normal)
        confirmBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        confirmBtn.setTitleColor(Palette.onAccent, for: .normal)
        confirmBtn.backgroundColor = Palette.accent
        confirmBtn.layer.cornerRadius = 10
        confirmBtn.accessibilityIdentifier = "source.rule.preview.confirm"
        confirmBtn.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: true) {
                self.onConfirm(self.rules)
            }
        }, for: .touchUpInside)

        actionsStack.axis = .horizontal
        actionsStack.spacing = 12
        actionsStack.distribution = .fillEqually
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.addArrangedSubview(cancelBtn)
        actionsStack.addArrangedSubview(confirmBtn)
        view.addSubview(actionsStack)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            topBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            topBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: actionsStack.topAnchor, constant: -12),

            actionsStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            actionsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            actionsStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            actionsStack.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rules.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "PreviewCell")
        cell.backgroundColor = Palette.card
        let rule = rules[indexPath.row]
        let vpnTag = rule.requiresVpn ? " [VPN]" : ""
        cell.textLabel?.text = "\(rule.name)\(vpnTag) · v\(rule.version)"
        cell.textLabel?.textColor = Palette.text
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .medium)

        let replaceTag = rule.replacesNative ? "更新现有站源 · " : ""
        cell.detailTextLabel?.text = "\(rule.id) · \(replaceTag)\(rule.baseUrl)"
        cell.detailTextLabel?.textColor = Palette.secondaryText
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        return cell
    }
}

// MARK: - RuleDetailSheet

@MainActor
final class RuleDetailSheet: UIViewController {
    private let entry: RuleStore.Entry
    private let onRollback: (() -> Void)?

    init(entry: RuleStore.Entry, onRollback: (() -> Void)?) {
        self.entry = entry
        self.onRollback = onRollback
        super.init(nibName: nil, bundle: nil)
        title = entry.rule.name
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.card
        setupLayout()
    }

    private func setupLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        let rule = entry.rule

        // Title and VPN badge
        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .center

        let nameLabel = UILabel()
        nameLabel.text = rule.name
        nameLabel.font = .systemFont(ofSize: 19, weight: .bold)
        nameLabel.textColor = Palette.text

        headerStack.addArrangedSubview(nameLabel)
        if rule.requiresVpn {
            let badge = SourceVpnBadgeView()
            headerStack.addArrangedSubview(badge)
        }
        headerStack.addArrangedSubview(UIView())
        stack.addArrangedSubview(headerStack)

        addInfoItem(stack: stack, label: "站源 ID", value: rule.id)
        addInfoItem(stack: stack, label: "规则版本", value: "v\(rule.version)")
        addInfoItem(stack: stack, label: "规则引擎", value: "API \(rule.engineApi)")
        addInfoItem(stack: stack, label: "站点地址", value: rule.baseUrl)
        addInfoItem(stack: stack, label: "网络要求", value: rule.requiresVpn ? "需要 VPN" : "直连")
        addInfoItem(stack: stack, label: "域名授权", value: rule.hosts.joined(separator: "、"))
        if !rule.cleartextHosts.isEmpty {
            addInfoItem(stack: stack, label: "明文域名", value: rule.cleartextHosts.sorted().joined(separator: "、"))
        }
        if !rule.requires.isEmpty {
            addInfoItem(stack: stack, label: "附加能力", value: rule.requires.sorted().joined(separator: "、"))
        }

        let noteLabel = UILabel()
        noteLabel.text = "仅允许访问规则中声明的域名；规则在沙盒内运行，不能读取设备敏感信息或账号。切换版本保留漫画与阅读记录。"
        noteLabel.font = .systemFont(ofSize: 12, weight: .regular)
        noteLabel.textColor = Palette.secondaryText
        noteLabel.numberOfLines = 0
        stack.addArrangedSubview(noteLabel)

        if !entry.previous.isEmpty {
            let rollbackBtn = UIButton(type: .system)
            rollbackBtn.setTitle("回退上一版", for: .normal)
            rollbackBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            rollbackBtn.setTitleColor(Palette.onAccent, for: .normal)
            rollbackBtn.backgroundColor = Palette.accent
            rollbackBtn.layer.cornerRadius = 10
            rollbackBtn.translatesAutoresizingMaskIntoConstraints = false
            rollbackBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true
            rollbackBtn.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.dismiss(animated: true) { self.onRollback?() }
            }, for: .touchUpInside)
            stack.addArrangedSubview(rollbackBtn)
        }
    }

    private func addInfoItem(stack: UIStackView, label: String, value: String) {
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 3

        let lbl = UILabel()
        lbl.text = label
        lbl.font = .systemFont(ofSize: 13, weight: .medium)
        lbl.textColor = Palette.text

        let val = UILabel()
        val.text = value
        val.font = .systemFont(ofSize: 12, weight: .regular)
        val.textColor = Palette.secondaryText
        val.numberOfLines = 0

        vStack.addArrangedSubview(lbl)
        vStack.addArrangedSubview(val)

        let div = UIView()
        div.backgroundColor = Palette.borderSoft
        div.translatesAutoresizingMaskIntoConstraints = false
        div.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        vStack.addArrangedSubview(div)

        stack.addArrangedSubview(vStack)
    }
}

// MARK: - SourceRuleManagerViewController

/// Full-page rule management view controller.
/// Replicates Android 2.0.44/2.0.45's `SourceRuleManager`.
///
/// Features:
/// 1. Empty-state onboarding card when no rules are installed ("暂无站源规则" + "订阅站源规则" / "从文件导入规则")
/// 2. Rule list with title, subtitle (domain/version/status), VPN badge, switch, and drag reordering
/// 3. Multi-select batch deletion footer ("全选" / "删除选中" / "开启" / "关闭" / "导出")
/// 4. Import preview confirmation screen
/// 5. Integrates with `RuleCatalog`, `RuleStore`, `RuleSubscriptionUpdate` from `ComicCore`
@MainActor
final class SourceRuleManagerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {

    let catalog: RuleCatalog
    let environment: AppEnvironment?

    private var items: [RuleStore.Entry] = []
    private var selectedIds = Set<String>()
    private var isBatchMode = false

    // UI Elements
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyScrollView = UIScrollView()
    private let emptyCard = UIView()
    private let batchFooter = UIView()
    private let selectAllBtn = UIButton(type: .system)
    private let selectedCountLabel = UILabel()
    private let batchEnableBtn = UIButton(type: .system)
    private let batchDisableBtn = UIButton(type: .system)
    private let batchExportBtn = UIButton(type: .system)
    private let batchDeleteBtn = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var autoQuickSubscribe: Bool

    init(environment: AppEnvironment? = nil, catalog: RuleCatalog? = nil, autoQuickSubscribe: Bool = false) {
        self.environment = environment
        self.catalog = catalog ?? environment?.ruleCatalog ?? .shared
        self.autoQuickSubscribe = autoQuickSubscribe
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "规则与批量管理"
        view.backgroundColor = Palette.background

        setupNavigationBar()
        setupTableView()
        setupEmptyState()
        setupBatchFooter()

        loadRules()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadRules()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if autoQuickSubscribe {
            autoQuickSubscribe = false
            quickSubscribeDefault()
        }
    }

    // MARK: - Navigation Bar

    private func setupNavigationBar() {
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(showMoreDrawer)
        )
        moreButton.accessibilityIdentifier = "source.rule.moreActions"
        moreButton.accessibilityLabel = "规则更多操作"
        navigationItem.rightBarButtonItem = moreButton
    }

    // MARK: - Setup Views

    private func setupTableView() {
        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SourceRuleCell.self, forCellReuseIdentifier: SourceRuleCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.accessibilityIdentifier = "source.rule.list"
        view.addSubview(tableView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Empty State Onboarding Card (feat(android): 引导首次站源订阅)

    private func setupEmptyState() {
        emptyScrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyScrollView.alwaysBounceVertical = true
        emptyScrollView.showsVerticalScrollIndicator = false
        view.addSubview(emptyScrollView)

        emptyCard.backgroundColor = Palette.card
        emptyCard.layer.cornerRadius = 16
        emptyCard.layer.borderWidth = 1
        emptyCard.layer.borderColor = Palette.borderSoft.cgColor
        emptyCard.translatesAutoresizingMaskIntoConstraints = false
        emptyCard.accessibilityIdentifier = "source.rule.empty.card"
        emptyScrollView.addSubview(emptyCard)

        let iconView = UIImageView(image: ParityIcon.source.image(size: 54))
        iconView.tintColor = Palette.accent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "暂无站源规则"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.textAlignment = .center
        titleLabel.accessibilityIdentifier = "source.rule.empty.title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = "订阅规则仓库或从文件导入规则后，即可浏览和搜索漫画。规则在沙盒内运行，可随时管理与更新。"
        descLabel.font = .systemFont(ofSize: 13, weight: .regular)
        descLabel.textColor = Palette.secondaryText
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let subscribeBtn = UIButton(type: .system)
        subscribeBtn.setTitle("订阅站源规则", for: .normal)
        subscribeBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        subscribeBtn.setTitleColor(Palette.onAccent, for: .normal)
        subscribeBtn.backgroundColor = Palette.accent
        subscribeBtn.layer.cornerRadius = 10
        subscribeBtn.accessibilityIdentifier = "source.rule.empty.subscribe"
        subscribeBtn.translatesAutoresizingMaskIntoConstraints = false
        subscribeBtn.addAction(UIAction { [weak self] _ in self?.quickSubscribeDefault() }, for: .touchUpInside)

        let importFileBtn = UIButton(type: .system)
        importFileBtn.setTitle("从文件导入规则", for: .normal)
        importFileBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        importFileBtn.setTitleColor(Palette.text, for: .normal)
        importFileBtn.backgroundColor = Palette.cardSoft
        importFileBtn.layer.cornerRadius = 10
        importFileBtn.layer.borderWidth = 0.5
        importFileBtn.layer.borderColor = Palette.borderSoft.cgColor
        importFileBtn.accessibilityIdentifier = "source.rule.empty.importFile"
        importFileBtn.translatesAutoresizingMaskIntoConstraints = false
        importFileBtn.addAction(UIAction { [weak self] _ in self?.pickImportFile() }, for: .touchUpInside)

        let buttonsStack = UIStackView(arrangedSubviews: [subscribeBtn, importFileBtn])
        buttonsStack.axis = .vertical
        buttonsStack.spacing = 10
        buttonsStack.distribution = .fillEqually
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false

        emptyCard.addSubview(iconView)
        emptyCard.addSubview(titleLabel)
        emptyCard.addSubview(descLabel)
        emptyCard.addSubview(buttonsStack)

        let widthConstraint = emptyCard.widthAnchor.constraint(equalTo: emptyScrollView.widthAnchor, constant: -40)
        widthConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            emptyScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyCard.centerXAnchor.constraint(equalTo: emptyScrollView.centerXAnchor),
            emptyCard.centerYAnchor.constraint(equalTo: emptyScrollView.centerYAnchor, constant: -20),
            emptyCard.leadingAnchor.constraint(greaterThanOrEqualTo: emptyScrollView.leadingAnchor, constant: 20),
            emptyCard.trailingAnchor.constraint(lessThanOrEqualTo: emptyScrollView.trailingAnchor, constant: -20),
            emptyCard.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            widthConstraint,

            iconView.topAnchor.constraint(equalTo: emptyCard.topAnchor, constant: 28),
            iconView.centerXAnchor.constraint(equalTo: emptyCard.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 54),
            iconView.heightAnchor.constraint(equalToConstant: 54),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: emptyCard.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: emptyCard.trailingAnchor, constant: -20),

            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: emptyCard.leadingAnchor, constant: 20),
            descLabel.trailingAnchor.constraint(equalTo: emptyCard.trailingAnchor, constant: -20),

            buttonsStack.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 20),
            buttonsStack.leadingAnchor.constraint(equalTo: emptyCard.leadingAnchor, constant: 20),
            buttonsStack.trailingAnchor.constraint(equalTo: emptyCard.trailingAnchor, constant: -20),
            buttonsStack.bottomAnchor.constraint(equalTo: emptyCard.bottomAnchor, constant: -24),

            subscribeBtn.heightAnchor.constraint(equalToConstant: 44),
            importFileBtn.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    // MARK: - Batch Footer

    private func setupBatchFooter() {
        batchFooter.backgroundColor = Palette.card
        batchFooter.layer.borderWidth = 0.5
        batchFooter.layer.borderColor = Palette.borderSoft.cgColor
        batchFooter.translatesAutoresizingMaskIntoConstraints = false
        batchFooter.isHidden = true
        view.addSubview(batchFooter)

        // Top line of footer: SelectAll button and Count
        let topBar = UIStackView()
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.distribution = .equalSpacing
        topBar.translatesAutoresizingMaskIntoConstraints = false

        selectAllBtn.setTitle("全选", for: .normal)
        selectAllBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        selectAllBtn.setTitleColor(Palette.accent, for: .normal)
        selectAllBtn.accessibilityIdentifier = "source.rule.selectAll"
        selectAllBtn.addAction(UIAction { [weak self] _ in self?.toggleSelectAll() }, for: .touchUpInside)

        selectedCountLabel.font = .systemFont(ofSize: 13, weight: .regular)
        selectedCountLabel.textColor = Palette.secondaryText
        selectedCountLabel.accessibilityIdentifier = "source.rule.selectedCount"

        topBar.addArrangedSubview(selectAllBtn)
        topBar.addArrangedSubview(selectedCountLabel)

        // Bottom line: Action buttons (开启, 关闭, 导出, 删除)
        let actionsBar = UIStackView()
        actionsBar.axis = .horizontal
        actionsBar.spacing = 8
        actionsBar.distribution = .fillEqually
        actionsBar.translatesAutoresizingMaskIntoConstraints = false

        batchEnableBtn.setTitle("开启", for: .normal)
        batchEnableBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        batchEnableBtn.setTitleColor(Palette.text, for: .normal)
        batchEnableBtn.backgroundColor = Palette.cardSoft
        batchEnableBtn.layer.cornerRadius = 8
        batchEnableBtn.layer.borderWidth = 0.5
        batchEnableBtn.layer.borderColor = Palette.borderSoft.cgColor
        batchEnableBtn.accessibilityIdentifier = "source.rule.batchEnable"
        batchEnableBtn.addAction(UIAction { [weak self] _ in self?.batchChange(action: "enable") }, for: .touchUpInside)

        batchDisableBtn.setTitle("关闭", for: .normal)
        batchDisableBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        batchDisableBtn.setTitleColor(Palette.text, for: .normal)
        batchDisableBtn.backgroundColor = Palette.cardSoft
        batchDisableBtn.layer.cornerRadius = 8
        batchDisableBtn.layer.borderWidth = 0.5
        batchDisableBtn.layer.borderColor = Palette.borderSoft.cgColor
        batchDisableBtn.accessibilityIdentifier = "source.rule.batchDisable"
        batchDisableBtn.addAction(UIAction { [weak self] _ in self?.batchChange(action: "disable") }, for: .touchUpInside)

        batchExportBtn.setTitle("导出", for: .normal)
        batchExportBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        batchExportBtn.setTitleColor(Palette.text, for: .normal)
        batchExportBtn.backgroundColor = Palette.cardSoft
        batchExportBtn.layer.cornerRadius = 8
        batchExportBtn.layer.borderWidth = 0.5
        batchExportBtn.layer.borderColor = Palette.borderSoft.cgColor
        batchExportBtn.accessibilityIdentifier = "source.rule.exportSelected"
        batchExportBtn.addAction(UIAction { [weak self] _ in self?.exportSelectedRules() }, for: .touchUpInside)

        batchDeleteBtn.setTitle("删除选中", for: .normal)
        batchDeleteBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        batchDeleteBtn.setTitleColor(Palette.danger, for: .normal)
        batchDeleteBtn.backgroundColor = Palette.cardSoft
        batchDeleteBtn.layer.cornerRadius = 8
        batchDeleteBtn.layer.borderWidth = 0.5
        batchDeleteBtn.layer.borderColor = Palette.borderSoft.cgColor
        batchDeleteBtn.accessibilityIdentifier = "source.rule.deleteSelected"
        batchDeleteBtn.addAction(UIAction { [weak self] _ in self?.confirmDeleteSelected() }, for: .touchUpInside)

        actionsBar.addArrangedSubview(batchEnableBtn)
        actionsBar.addArrangedSubview(batchDisableBtn)
        actionsBar.addArrangedSubview(batchExportBtn)
        actionsBar.addArrangedSubview(batchDeleteBtn)

        let footerStack = UIStackView(arrangedSubviews: [topBar, actionsBar])
        footerStack.axis = .vertical
        footerStack.spacing = 8
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        batchFooter.addSubview(footerStack)

        NSLayoutConstraint.activate([
            batchFooter.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            batchFooter.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            batchFooter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            footerStack.topAnchor.constraint(equalTo: batchFooter.topAnchor, constant: 10),
            footerStack.leadingAnchor.constraint(equalTo: batchFooter.leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: batchFooter.trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: batchFooter.bottomAnchor, constant: -10),

            actionsBar.heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    // MARK: - Data Loading

    func loadRules() {
        catalog.refresh()
        items = catalog.entries().filter { !$0.removed && !catalog.hidden($0.rule.id) }
        let hasRules = !items.isEmpty

        tableView.isHidden = !hasRules
        emptyScrollView.isHidden = hasRules

        if hasRules {
            tableView.reloadData()
        }
        updateBatchFooter()
    }

    private func updateBatchFooter() {
        if !isBatchMode {
            batchFooter.isHidden = true
            tableView.contentInset.bottom = 0
            return
        }

        batchFooter.isHidden = false
        tableView.contentInset.bottom = 96

        let count = selectedIds.count
        selectedCountLabel.text = count == 0 ? "共 \(items.count) 个" : "已选 \(count) 个"
        selectAllBtn.setTitle(count == items.count ? "取消全选" : "全选", for: .normal)

        let hasSelection = count > 0
        batchEnableBtn.isEnabled = hasSelection
        batchDisableBtn.isEnabled = hasSelection
        batchExportBtn.isEnabled = hasSelection
        batchDeleteBtn.isEnabled = hasSelection
    }

    // MARK: - Action Drawer

    @objc private func showMoreDrawer() {
        let drawer = SourceActionDrawerSheet()
        drawer.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .subscribe:
                self.showSubscribePrompt()
            case .importFile:
                self.pickImportFile()
            case .updateSubscriptions:
                self.updateSubscriptions()
            case .exportRules:
                self.exportAllRules()
            case .manageGroups:
                self.openGroupManager()
            case .batchSelect:
                self.toggleBatchMode()
            }
        }
        present(drawer, animated: true)
    }

    private func toggleBatchMode() {
        isBatchMode.toggle()
        selectedIds.removeAll()
        tableView.setEditing(isBatchMode, animated: true)

        if isBatchMode {
            let doneButton = UIBarButtonItem(
                title: "完成",
                style: .done,
                target: self,
                action: #selector(exitBatchMode)
            )
            doneButton.accessibilityIdentifier = "source.rule.exitBatch"
            navigationItem.rightBarButtonItem = doneButton
        } else {
            setupNavigationBar()
        }

        updateBatchFooter()
        tableView.reloadData()
    }

    @objc private func exitBatchMode() {
        if isBatchMode {
            toggleBatchMode()
        }
    }

    private func toggleSelectAll() {
        if selectedIds.count == items.count {
            selectedIds.removeAll()
        } else {
            selectedIds = Set(items.map(\.rule.id))
        }
        tableView.reloadData()
        updateBatchFooter()
    }

    // MARK: - UITableViewDataSource & UITableViewDelegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SourceRuleCell.reuseIdentifier, for: indexPath) as! SourceRuleCell
        let entry = items[indexPath.row]
        let isSelected = selectedIds.contains(entry.rule.id)

        cell.configure(entry: entry, isBatchMode: isBatchMode, isSelected: isSelected)
        cell.onSwitchToggled = { [weak self] enabled in
            self?.setRule(entry.rule.id, enabled: enabled)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = items[indexPath.row]
        if isBatchMode {
            if selectedIds.contains(entry.rule.id) {
                selectedIds.remove(entry.rule.id)
            } else {
                selectedIds.insert(entry.rule.id)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
            updateBatchFooter()
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
            showRuleDetail(entry: entry)
        }
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        !isBatchMode
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard sourceIndexPath.row != destinationIndexPath.row else { return }
        let moved = items.remove(at: sourceIndexPath.row)
        items.insert(moved, at: destinationIndexPath.row)

        if let env = environment {
            let ruleIds = items.map(\.rule.id)
            let ruleIdSet = Set(ruleIds.map(SourcePreferences.canonicalID))
            var merged: [String] = []
            var ruleIterator = ruleIds.makeIterator()
            for existing in env.sourcePreferences.orderedIDs {
                if ruleIdSet.contains(SourcePreferences.canonicalID(existing)) {
                    if let nextRule = ruleIterator.next() {
                        merged.append(nextRule)
                    }
                } else {
                    merged.append(existing)
                }
            }
            while let remaining = ruleIterator.next() {
                merged.append(remaining)
            }
            env.sourcePreferences.setOrder(merged)
            env.reloadSources()
        }
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    // MARK: - Rule Detail

    private func showRuleDetail(entry: RuleStore.Entry) {
        let sheet = RuleDetailSheet(entry: entry) { [weak self] in
            guard let self else { return }
            do {
                try self.catalog.store().change(ids: [entry.rule.id], action: "rollback")
                self.catalog.refresh()
                self.environment?.reloadSources()
                self.loadRules()
                self.showToast("已回退至上一版本")
            } catch {
                self.showAlert(title: "回退失败", message: error.localizedDescription)
            }
        }
        present(sheet, animated: true)
    }

    // MARK: - Rule Switch Action

    private func setRule(_ id: String, enabled: Bool) {
        do {
            try catalog.store().change(ids: [id], action: enabled ? "enable" : "disable")
            catalog.refresh()
            if let env = environment {
                env.sourcePreferences.setEnabled(enabled, id: id)
                env.reloadSources()
            }
            loadRules()
        } catch {
            showAlert(title: "设置失败", message: error.localizedDescription)
            loadRules()
        }
    }

    // MARK: - Batch Actions

    private func batchChange(action: String) {
        guard !selectedIds.isEmpty else { return }
        let ids = Array(selectedIds)
        do {
            try catalog.store().change(ids: ids, action: action)
            catalog.refresh()
            if let env = environment {
                for id in ids {
                    env.sourcePreferences.setEnabled(action == "enable", id: id)
                }
                env.reloadSources()
            }
            loadRules()
            showToast("已批量\(action == "enable" ? "开启" : "关闭") \(ids.count) 个规则")
        } catch {
            showAlert(title: "操作失败", message: error.localizedDescription)
        }
    }

    private func confirmDeleteSelected() {
        guard !selectedIds.isEmpty else { return }
        let count = selectedIds.count
        let alert = UIAlertController(
            title: "移除所选站源",
            message: "将删除 \(count) 个已安装规则。收藏、历史、阅读位置和下载内容继续保留；仍在订阅中的站源，下次更新站源时可重新加入。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认移除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let ids = Array(self.selectedIds)
            do {
                try self.catalog.store().change(ids: ids, action: "delete")
                self.catalog.refresh()
                if let env = self.environment {
                    if !env.usesLegacyBuiltinSources {
                        for id in ids {
                            env.defaults.removeObject(forKey: "source.\(SourcePreferences.canonicalID(id)).enabled")
                        }
                    }
                    env.reloadSources()
                }
                self.selectedIds.removeAll()
                self.loadRules()
                self.showToast("已移除 \(ids.count) 个规则")
            } catch {
                self.showAlert(title: "删除失败", message: error.localizedDescription)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Quick Subscribe & Subscriptions

    func quickSubscribeDefault() {
        showSubscribePrompt(defaultUrl: RuleRepository.DEFAULT_URL)
    }

    private func showSubscribePrompt(defaultUrl: String = RuleRepository.DEFAULT_URL) {
        let alert = UIAlertController(
            title: "添加规则订阅",
            message: "输入规则仓库 HTTPS 索引地址，读取后先预览，确认才会安装。",
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.text = defaultUrl
            $0.placeholder = "https://.../index.json"
            $0.keyboardType = .URL
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "读取订阅", style: .default) { [weak self, weak alert] _ in
            guard let self, let url = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { return }
            self.fetchAndPreviewUrl(url: url, isSubscription: true)
        })
        present(alert, animated: true)
    }

    private func fetchAndPreviewUrl(url: String, isSubscription: Bool) {
        activityIndicator.startAnimating()
        let catalog = self.catalog
        Task { [weak self] in
            do {
                let (rules, summary) = try await Task.detached(priority: .userInitiated) { () throws -> ([RuleDefinition], String) in
                    let content = try RuleRepository.fetch(url)
                    guard let data = content.data(using: .utf8),
                          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw RuleError("无法解析返回数据为 JSON")
                    }
                    let bundle = try RuleRepository.readCompatible(root: root, origin: url)
                    if bundle.rules.isEmpty && bundle.skipped > 0 {
                        throw UnsupportedRuleError("全部 \(bundle.skipped) 个规则需要升级客户端后才能安装")
                    }
                    var previewSummary = try catalog.store().preview(bundle.rules)
                    if bundle.skipped > 0 {
                        previewSummary += " · 跳过 \(bundle.skipped)（需升级客户端）"
                    }
                    return (bundle.rules, previewSummary)
                }.value
                guard let self else { return }
                self.activityIndicator.stopAnimating()
                self.showImportPreview(
                    rules: rules,
                    summary: summary,
                    subscriptionUrl: isSubscription ? url : ""
                )
            } catch {
                guard let self else { return }
                self.activityIndicator.stopAnimating()
                self.showAlert(title: "读取规则失败", message: error.localizedDescription)
            }
        }
    }

    private func showImportPreview(rules: [RuleDefinition], summary: String, subscriptionUrl: String) {
        let preview = SourceRuleImportPreviewSheet(
            rules: rules,
            summary: summary,
            subscriptionUrl: subscriptionUrl
        ) { [weak self] confirmedRules in
            self?.installRules(confirmedRules, subscriptionUrl: subscriptionUrl)
        }
        present(preview, animated: true)
    }

    func installRules(_ rules: [RuleDefinition], subscriptionUrl: String, showFeedback: Bool = true) {
        activityIndicator.startAnimating()
        let catalog = self.catalog
        Task { [weak self] in
            do {
                let msg = try await Task.detached(priority: .userInitiated) { () throws -> String in
                    let installedMsg = try catalog.store().install(
                        rules,
                        validator: { rule in try catalog.validate(rule) },
                        subscription: subscriptionUrl
                    )
                    catalog.refresh()
                    return installedMsg
                }.value
                guard let self else { return }
                self.activityIndicator.stopAnimating()
                self.environment?.reloadSources()
                self.loadRules()
                if showFeedback {
                    self.showToast("安装完成：\(msg)")
                }
            } catch {
                guard let self else { return }
                self.activityIndicator.stopAnimating()
                if showFeedback {
                    self.showAlert(title: "安装失败", message: error.localizedDescription)
                }
            }
        }
    }

    private func updateSubscriptions() {
        let repos = catalog.repositories()
        guard !repos.isEmpty else {
            showToast("暂无规则订阅，请先添加规则订阅")
            return
        }

        activityIndicator.startAnimating()
        let catalog = self.catalog
        Task { [weak self] in
            do {
                let message = try await Task.detached(priority: .userInitiated) { () throws -> String in
                    let prepared = try RuleSubscriptionUpdate.prepareCompatible(
                        urls: repos,
                        validator: { rule in try catalog.validate(rule) }
                    )
                    if prepared.rules.isEmpty && prepared.skipped > 0 {
                        throw UnsupportedRuleError("订阅中的 \(prepared.skipped) 个规则需要升级客户端后才能更新")
                    }
                    var msg = try catalog.store().updateSubscriptions(prepared.rules)
                    if prepared.skipped > 0 {
                        msg += " · 跳过 \(prepared.skipped)（需升级客户端）"
                    }
                    catalog.refresh()
                    return msg
                }.value
                guard let self else { return }
                self.activityIndicator.stopAnimating()
                self.environment?.reloadSources()
                self.loadRules()
                self.showAlert(title: "站源已更新", message: message)
            } catch {
                guard let self else { return }
                self.activityIndicator.stopAnimating()
                self.showAlert(title: "更新未完成", message: error.localizedDescription)
            }
        }
    }

    // MARK: - File Import & Export

    private func pickImportFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        activityIndicator.startAnimating()
        let catalog = self.catalog
        Task { [weak self] in
            do {
                let (rules, summary) = try await Task.detached(priority: .userInitiated) { () throws -> ([RuleDefinition], String) in
                    let data = try Data(contentsOf: url)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw RuleError("无法解析文件为 JSON")
                    }
                    let bundle: RuleStore.Bundle
                    if (json["schema"] as? String) == "xx-comic.rules" {
                        bundle = try RuleStore.parseCompatible(json: json)
                    } else if (json["schema"] as? String) == "xx-comic.source-bundle",
                              let rulesJson = json["rules"] as? [String: Any] {
                        bundle = try RuleStore.parseCompatible(json: rulesJson)
                    } else {
                        bundle = try RuleRepository.readCompatible(root: json, origin: nil)
                    }
                    if bundle.rules.isEmpty && bundle.skipped > 0 {
                        throw UnsupportedRuleError("文件中的 \(bundle.skipped) 个规则需要升级客户端后才能导入")
                    }
                    var previewSummary = try catalog.store().preview(bundle.rules)
                    if bundle.skipped > 0 {
                        previewSummary += " · 跳过 \(bundle.skipped)（需升级客户端）"
                    }
                    return (bundle.rules, previewSummary)
                }.value
                guard let self else { return }
                self.activityIndicator.stopAnimating()
                self.showImportPreview(rules: rules, summary: summary, subscriptionUrl: "")
            } catch {
                guard let self else { return }
                self.activityIndicator.stopAnimating()
                self.showAlert(title: "导入文件失败", message: error.localizedDescription)
            }
        }
    }

    private func exportSelectedRules() {
        let selectedRules = items.filter { selectedIds.contains($0.rule.id) }.map(\.rule)
        guard !selectedRules.isEmpty else {
            showToast("请先选择站源")
            return
        }
        exportRules(selectedRules)
    }

    private func exportAllRules() {
        let allRules = items.map(\.rule)
        guard !allRules.isEmpty else {
            showToast("当前暂无已安装规则可导出")
            return
        }
        exportRules(allRules)
    }

    private func exportRules(_ rules: [RuleDefinition]) {
        do {
            let packed = try RuleStore.pack(rules)
            let data = try JSONSerialization.data(withJSONObject: packed, options: [.prettyPrinted])
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("xx-comic-rules-\(Date().timeIntervalSince1970).json")
            try data.write(to: fileURL)

            let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        } catch {
            showAlert(title: "导出失败", message: error.localizedDescription)
        }
    }

    // MARK: - Manage Groups

    private func openGroupManager() {
        guard let env = environment else {
            showAlert(title: "站源分组", message: "分组功能需要主应用环境支持")
            return
        }
        let sheet = SourceGroupSheet(environment: env)
        sheet.onGroupsChanged = { [weak self] in
            self?.loadRules()
        }
        let nav = UINavigationController(rootViewController: sheet)
        present(nav, animated: true)
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        RemToastView.show(message: message, kind: .info, in: self)
    }
}
