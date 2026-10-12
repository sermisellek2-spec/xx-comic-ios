import UIKit
import ComicCore

@MainActor
final class CacheCleanupViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private var cacheSizeText: String = "正在计算..."
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let confirmButton = UIButton(type: .system)
    private let feedbackLabel = UILabel()
    private var sizeTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var sizeGeneration = UUID()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "缓存清理"
        view.backgroundColor = Palette.background

        setupNavigation()
        setupViews()
        calculateCacheSize()
    }

    private func setupNavigation() {
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain,
            target: self,
            action: #selector(showMenu)
        )
        navigationItem.rightBarButtonItem = moreButton
    }

    private func setupViews() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.setTitle("确认清理", for: .normal)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.backgroundColor = Palette.accent
        confirmButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        confirmButton.layer.cornerRadius = 10
        confirmButton.addTarget(self, action: #selector(confirmCleanupTapped), for: .touchUpInside)
        feedbackLabel.font = .systemFont(ofSize: 14)
        feedbackLabel.textColor = Palette.secondaryText
        feedbackLabel.numberOfLines = 0
        feedbackLabel.accessibilityIdentifier = "cache.feedback"
        feedbackLabel.isHidden = true
        let footer = UIStackView(arrangedSubviews: [feedbackLabel, confirmButton])
        footer.axis = .vertical; footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            confirmButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func calculateCacheSize() {
        sizeTask?.cancel()
        let token = UUID(); sizeGeneration = token
        let cache = environment.responseCache
        sizeTask = Task { [weak self] in
            do {
                let usage = try await cache.usage()
                guard let self, self.sizeGeneration == token, !Task.isCancelled else { return }
                self.cacheSizeText = StorageCalculator.formatBytes(usage.totalBytes)
                self.tableView.reloadData()
            } catch {
                guard let self, self.sizeGeneration == token, !Task.isCancelled else { return }
                self.cacheSizeText = "计算失败，可重试"
                self.tableView.reloadData()
            }
        }
    }

    @objc private func showMenu() {
        let sheet = UIAlertController(title: "缓存操作", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "重新计算大小", style: .default) { [weak self] _ in
            self?.calculateCacheSize()
        })
        sheet.addAction(UIAlertAction(title: "清理全部缓存", style: .destructive) { [weak self] _ in
            self?.confirmCleanupTapped()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    @objc private func confirmCleanupTapped() {
        let alert = UIAlertController(
            title: "清理缓存",
            message: "将清理漫画图片与解析缓存，书架与阅读记录会始终保留。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "立即清理", style: .destructive) { [weak self] _ in
            self?.performCleanup()
        })
        present(alert, animated: true)
    }

    private func performCleanup() {
        guard cleanupTask == nil else { return }
        confirmButton.isEnabled = false
        feedbackLabel.text = "正在清理缓存…"; feedbackLabel.isHidden = false
        confirmButton.setTitle("正在清理…", for: .normal)
        let environment = environment
        cleanupTask = Task { [weak self] in
            defer {
                self?.cleanupTask = nil
                self?.confirmButton.isEnabled = true
                self?.confirmButton.setTitle("确认清理", for: .normal)
            }
            do {
                let remaining = try await environment.clearCaches()
                guard let self, !Task.isCancelled else { return }
                #if DEBUG
                self.feedbackLabel.accessibilityValue = "memory=\(remaining.memoryBytes); disk=\(remaining.diskBytes)"
                #endif
                self.calculateCacheSize()
                if remaining.isEmpty {
                    self.showToast("缓存已清理，收藏与本地漫画已保留")
                } else {
                    self.showToast("已执行缓存清理，收藏与本地漫画已保留\n当前占用 \(StorageCalculator.formatBytes(remaining.totalBytes))。系统可能保留管理文件，或有新请求生成缓存。")
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                #if DEBUG
                // Only the framework error code; never expose cookies, URLs or permissions.
                let nativeError = error as NSError
                let stage = nativeError.userInfo["cache.cleanup.stage"] as? String ?? "framework"
                self.feedbackLabel.accessibilityValue = "failure.code=\(nativeError.code); stage=\(stage)"
                #endif
                self.showToast("清理失败，请重试")
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sizeTask?.cancel()
        // Once started, cleanup finishes safely; a departed page receives no result.
        cleanupTask?.cancel()
    }

    private func showToast(_ message: String) {
        // A durable result remains readable and does not compete with the
        // confirmation alert's dismissal transition.
        feedbackLabel.text = message
        feedbackLabel.isHidden = false
    }

    // MARK: - UITableViewDataSource & Delegate

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 2 : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "将被清理" : "始终保留"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = Palette.card
        cell.selectionStyle = .none
        cell.textLabel?.textColor = Palette.text
        cell.textLabel?.font = .systemFont(ofSize: 15)

        if indexPath.section == 0 {
            if indexPath.row == 0 {
                let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
                cell.backgroundColor = Palette.card
                cell.selectionStyle = .none
                cell.imageView?.image = UIImage(systemName: "photo.stack")
                cell.imageView?.tintColor = Palette.accent
                cell.textLabel?.text = "漫画图片缓存"
                cell.textLabel?.textColor = Palette.text
                cell.textLabel?.font = .systemFont(ofSize: 15)
                cell.detailTextLabel?.text = "下次阅读时重新获取"
                cell.detailTextLabel?.textColor = Palette.secondaryText
                cell.detailTextLabel?.font = .systemFont(ofSize: 12)

                let valueLabel = UILabel()
                valueLabel.text = cacheSizeText
                valueLabel.textColor = Palette.secondaryText
                valueLabel.font = .systemFont(ofSize: 13)
                valueLabel.sizeToFit()
                cell.accessoryView = valueLabel
                return cell
            } else {
                let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
                cell.backgroundColor = Palette.card
                cell.selectionStyle = .none
                cell.imageView?.image = UIImage(systemName: "network")
                cell.imageView?.tintColor = Palette.accent
                cell.textLabel?.text = "页面解析与验证缓存"
                cell.textLabel?.textColor = Palette.text
                cell.textLabel?.font = .systemFont(ofSize: 15)
                cell.detailTextLabel?.text = "不会删除站源配置"
                cell.detailTextLabel?.textColor = Palette.secondaryText
                cell.detailTextLabel?.font = .systemFont(ofSize: 12)

                let badge = UILabel()
                badge.text = "清理"
                badge.textColor = Palette.secondaryText
                badge.font = .systemFont(ofSize: 13)
                badge.sizeToFit()
                cell.accessoryView = badge
                return cell
            }
        } else {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.backgroundColor = Palette.card
            cell.selectionStyle = .none
            cell.imageView?.image = UIImage(systemName: "bookmark.fill")
            cell.imageView?.tintColor = Palette.accent
            cell.textLabel?.text = "书架收藏、历史与进度"
            cell.textLabel?.textColor = Palette.text
            cell.textLabel?.font = .systemFont(ofSize: 15)
            cell.detailTextLabel?.text = "永久保留在本地"
            cell.detailTextLabel?.textColor = Palette.secondaryText
            cell.detailTextLabel?.font = .systemFont(ofSize: 12)

            let badge = UILabel()
            badge.text = "保留"
            badge.textColor = Palette.accent
            badge.font = .systemFont(ofSize: 13, weight: .bold)
            badge.sizeToFit()
            cell.accessoryView = badge
            return cell
        }
    }
}
