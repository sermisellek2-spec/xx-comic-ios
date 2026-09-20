import UIKit
import ComicCore

@MainActor
final class ErrorLogsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private var entries: [ErrorLogEntry] = []

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyView = UIStackView()
    private let emptyImage = UIImageView()
    private let emptyTitle = UILabel()
    private let emptySubtitle = UILabel()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "错误日志"
        view.backgroundColor = Palette.background

        setupNavigation()
        setupViews()
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }

    private func setupNavigation() {
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain,
            target: self,
            action: #selector(showMoreMenu)
        )
        navigationItem.rightBarButtonItem = moreButton
    }

    private func setupViews() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.axis = .vertical
        emptyView.alignment = .center
        emptyView.spacing = 8
        view.addSubview(emptyView)

        emptyImage.image = UIImage(named: "rem_empty")
        emptyImage.contentMode = .scaleAspectFit
        emptyImage.translatesAutoresizingMaskIntoConstraints = false
        emptyImage.widthAnchor.constraint(equalToConstant: 80).isActive = true
        emptyImage.heightAnchor.constraint(equalToConstant: 80).isActive = true

        emptyTitle.text = "这里很干净"
        emptyTitle.font = .systemFont(ofSize: 16, weight: .bold)
        emptyTitle.textColor = Palette.text

        emptySubtitle.text = "暂时没有错误日志"
        emptySubtitle.font = .systemFont(ofSize: 13)
        emptySubtitle.textColor = Palette.secondaryText

        emptyView.addArrangedSubview(emptyImage)
        emptyView.addArrangedSubview(emptyTitle)
        emptyView.addArrangedSubview(emptySubtitle)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadData() {
        entries = ErrorLogStore.shared.entries()
        navigationItem.prompt = entries.isEmpty ? nil : "\(entries.count) 条"
        emptyView.isHidden = !entries.isEmpty
        tableView.isHidden = entries.isEmpty
        tableView.reloadData()
    }

    @objc private func showMoreMenu() {
        let sheet = UIAlertController(title: "日志操作", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "导出全部日志", style: .default) { [weak self] _ in
            self?.exportAllLogs()
        })
        sheet.addAction(UIAlertAction(title: "清空错误日志", style: .destructive) { [weak self] _ in
            self?.confirmClearLogs()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func exportAllLogs() {
        let allLogs = ErrorLogStore.shared.allText()
        guard !allLogs.isEmpty else {
            showToast("当前暂无错误日志可导出")
            return
        }
        let activityVC = UIActivityViewController(activityItems: [allLogs], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    private func confirmClearLogs() {
        let alert = UIAlertController(
            title: "清空错误日志",
            message: "所有本地错误记录都会移除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            ErrorLogStore.shared.clear()
            self?.loadData()
            self?.showToast("错误日志已清空")
        })
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            alert.dismiss(animated: true)
        }
    }

    // MARK: - UITableViewDataSource & Delegate

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return entries.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "日志只保存在本机，导出时调用系统分享。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let entry = entries[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "errorRow")
        cell.backgroundColor = Palette.card
        cell.accessoryType = .disclosureIndicator

        cell.imageView?.image = UIImage(systemName: "bolt.fill")
        cell.imageView?.tintColor = .systemRed

        cell.textLabel?.text = entry.title
        cell.textLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        cell.textLabel?.textColor = Palette.text
        cell.textLabel?.numberOfLines = 1

        cell.detailTextLabel?.text = entry.message.isEmpty ? entry.timestamp : "\(entry.timestamp) · \(entry.message)"
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.detailTextLabel?.textColor = Palette.secondaryText
        cell.detailTextLabel?.numberOfLines = 1

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]
        let detailVC = ErrorLogDetailViewController(entry: entry)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

@MainActor
final class ErrorLogDetailViewController: UIViewController {
    private let entry: ErrorLogEntry

    private let scrollView = UIScrollView()
    private let contentView = UIStackView()
    private let headerLabel = UILabel()
    private let logTextView = UITextView()
    private let tipLabel = UILabel()
    private let actionStack = UIStackView()
    private let copyButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)

    init(entry: ErrorLogEntry) {
        self.entry = entry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "错误日志"
        navigationItem.prompt = "详细信息"
        view.backgroundColor = Palette.background

        setupViews()
    }

    private func setupViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.axis = .vertical
        contentView.spacing = 10

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        headerLabel.text = entry.title
        headerLabel.font = .systemFont(ofSize: 14, weight: .bold)
        headerLabel.textColor = Palette.secondaryText
        contentView.addArrangedSubview(headerLabel)

        logTextView.isEditable = false
        logTextView.isScrollEnabled = false
        logTextView.text = entry.fullText
        logTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.textColor = Palette.text
        logTextView.backgroundColor = Palette.card
        logTextView.layer.cornerRadius = 8
        logTextView.layer.borderWidth = 1
        logTextView.layer.borderColor = Palette.border.cgColor
        logTextView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        contentView.addArrangedSubview(logTextView)

        tipLabel.text = "可长按复制。日志不会自动发送给任何服务器。"
        tipLabel.font = .systemFont(ofSize: 11)
        tipLabel.textColor = Palette.secondaryText
        contentView.addArrangedSubview(tipLabel)

        actionStack.axis = .horizontal
        actionStack.spacing = 12
        actionStack.distribution = .fillEqually

        copyButton.setTitle("复制", for: .normal)
        copyButton.setTitleColor(Palette.accent, for: .normal)
        copyButton.backgroundColor = Palette.card
        copyButton.layer.cornerRadius = 8
        copyButton.layer.borderWidth = 1
        copyButton.layer.borderColor = Palette.border.cgColor
        copyButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)

        exportButton.setTitle("导出日志", for: .normal)
        exportButton.setTitleColor(Palette.accent, for: .normal)
        exportButton.backgroundColor = Palette.card
        exportButton.layer.cornerRadius = 8
        exportButton.layer.borderWidth = 1
        exportButton.layer.borderColor = Palette.border.cgColor
        exportButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)

        actionStack.addArrangedSubview(copyButton)
        actionStack.addArrangedSubview(exportButton)
        contentView.addArrangedSubview(actionStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = entry.fullText
        let alert = UIAlertController(title: nil, message: "日志已复制", preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            alert.dismiss(animated: true)
        }
    }

    @objc private func exportTapped() {
        let activityVC = UIActivityViewController(activityItems: [entry.fullText], applicationActivities: nil)
        present(activityVC, animated: true)
    }
}
