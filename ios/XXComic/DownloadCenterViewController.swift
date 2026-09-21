import UIKit
import ComicCore

@MainActor
final class DownloadCenterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyView = UIView()
    private var timer: Timer?

    private struct ComicDownloadGroup {
        let bookId: String
        let title: String
        let coverUrl: String?
        var tasks: [DownloadTask]
    }

    private var groups: [ComicDownloadGroup] = []

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "下载中心"
        view.backgroundColor = Palette.background

        setupNavigationBar()
        setupViews()
        loadTasks()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadTasks()
        startProgressTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopProgressTimer()
    }

    private func setupNavigationBar() {
        let wifiTitle = environment.downloadRuntime.isWifiOnly ? "仅 Wi-Fi" : "全网络"
        let wifiItem = UIBarButtonItem(title: wifiTitle, style: .plain, target: self, action: #selector(toggleWifiOnly))
        navigationItem.rightBarButtonItem = wifiItem
    }

    @objc private func toggleWifiOnly() {
        environment.downloadRuntime.isWifiOnly.toggle()
        setupNavigationBar()
        let mode = environment.downloadRuntime.isWifiOnly ? "仅 Wi-Fi 下载" : "允许移动网络下载"
        let alert = UIAlertController(title: "下载网络设置", message: "已切换为：\(mode)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func setupViews() {
        // Top Tools & Rem banner in table header
        let headerContainer = UIView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false

        let toolStack = UIStackView()
        toolStack.axis = .horizontal
        toolStack.spacing = 10
        toolStack.distribution = .fillEqually
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(toolStack)

        let pauseAllBtn = UIButton(type: .system)
        pauseAllBtn.setTitle("全部暂停", for: .normal)
        pauseAllBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        pauseAllBtn.backgroundColor = Palette.card
        pauseAllBtn.layer.cornerRadius = 8
        pauseAllBtn.setTitleColor(Palette.text, for: .normal)
        pauseAllBtn.layer.borderWidth = 1
        pauseAllBtn.layer.borderColor = Palette.secondaryText.withAlphaComponent(0.2).cgColor
        pauseAllBtn.addTarget(self, action: #selector(pauseAll), for: .touchUpInside)
        toolStack.addArrangedSubview(pauseAllBtn)

        let resumeAllBtn = UIButton(type: .system)
        resumeAllBtn.setTitle("继续下载", for: .normal)
        resumeAllBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        resumeAllBtn.backgroundColor = Palette.accent
        resumeAllBtn.layer.cornerRadius = 8
        resumeAllBtn.setTitleColor(.white, for: .normal)
        resumeAllBtn.addTarget(self, action: #selector(resumeAll), for: .touchUpInside)
        toolStack.addArrangedSubview(resumeAllBtn)

        let remBanner = UIView()
        remBanner.backgroundColor = Palette.accent.withAlphaComponent(0.08)
        remBanner.layer.cornerRadius = 8
        remBanner.layer.borderWidth = 1
        remBanner.layer.borderColor = Palette.accent.withAlphaComponent(0.2).cgColor
        remBanner.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(remBanner)

        let remIcon = UIImageView(image: UIImage(systemName: "books.vertical.fill"))
        remIcon.tintColor = Palette.accent
        remIcon.contentMode = .scaleAspectFit
        remIcon.translatesAutoresizingMaskIntoConstraints = false
        remBanner.addSubview(remIcon)

        let remLabel = UILabel()
        remLabel.text = "蕾姆会把完整章节收进本地书架"
        remLabel.font = .systemFont(ofSize: 13)
        remLabel.textColor = Palette.text
        remLabel.translatesAutoresizingMaskIntoConstraints = false
        remBanner.addSubview(remLabel)

        NSLayoutConstraint.activate([
            toolStack.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 12),
            toolStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            toolStack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            toolStack.heightAnchor.constraint(equalToConstant: 40),

            remBanner.topAnchor.constraint(equalTo: toolStack.bottomAnchor, constant: 10),
            remBanner.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            remBanner.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            remBanner.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -8),
            remBanner.heightAnchor.constraint(equalToConstant: 40),

            remIcon.leadingAnchor.constraint(equalTo: remBanner.leadingAnchor, constant: 12),
            remIcon.centerYAnchor.constraint(equalTo: remBanner.centerYAnchor),
            remIcon.widthAnchor.constraint(equalToConstant: 20),
            remIcon.heightAnchor.constraint(equalToConstant: 20),

            remLabel.leadingAnchor.constraint(equalTo: remIcon.trailingAnchor, constant: 8),
            remLabel.trailingAnchor.constraint(equalTo: remBanner.trailingAnchor, constant: -12),
            remLabel.centerYAnchor.constraint(equalTo: remBanner.centerYAnchor)
        ])

        headerContainer.layoutIfNeeded()
        let headerSize = headerContainer.systemLayoutSizeFitting(
            CGSize(width: view.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        headerContainer.frame = CGRect(origin: .zero, size: headerSize)
        tableView.tableHeaderView = headerContainer

        // TableView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DownloadTaskCell.self, forCellReuseIdentifier: "DownloadTaskCell")
        view.addSubview(tableView)

        // Empty state
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.isHidden = true
        view.addSubview(emptyView)

        let emptyLabel = UILabel()
        emptyLabel.text = "暂无离线下载任务"
        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = Palette.secondaryText
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor)
        ])
    }

    private func startProgressTimer() {
        stopProgressTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadTasks()
            }
        }
    }

    private func stopProgressTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func loadTasks() {
        let allTasks = environment.downloadRuntime.store.list()
        if allTasks.isEmpty {
            groups = []
            emptyView.isHidden = false
            tableView.reloadData()
            return
        }
        emptyView.isHidden = true

        var grouped: [String: [DownloadTask]] = [:]
        var groupOrder: [String] = []
        for t in allTasks {
            if grouped[t.bookId] == nil {
                grouped[t.bookId] = []
                groupOrder.append(t.bookId)
            }
            grouped[t.bookId]?.append(t)
        }

        groups = groupOrder.compactMap { bookId in
            guard let tasks = grouped[bookId], !tasks.isEmpty else { return nil }
            let snapshot = environment.downloadRuntime.store.snapshot(id: bookId)
            let title = snapshot?.summary.title ?? tasks.first?.title ?? "离线漫画"
            let cover = snapshot?.summary.coverUrl
            return ComicDownloadGroup(bookId: bookId, title: title, coverUrl: cover, tasks: tasks)
        }
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func pauseAll() {
        environment.downloadRuntime.pauseAll()
        loadTasks()
    }

    @objc private func resumeAll() {
        environment.downloadRuntime.resumeAll()
        loadTasks()
    }

    // MARK: - UITableViewDataSource & Delegate

    func numberOfSections(in tableView: UITableView) -> Int {
        groups.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        groups[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups[section].tasks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "DownloadTaskCell", for: indexPath) as? DownloadTaskCell else {
            return UITableViewCell()
        }
        let task = groups[indexPath.section].tasks[indexPath.row]
        cell.configure(with: task) { [weak self] action in
            self?.handleTaskAction(action, task: task)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let task = groups[indexPath.section].tasks[indexPath.row]
        guard task.state == .completed else { return }

        // If completed, attempt to open reader
        if let snapshot = environment.downloadRuntime.store.snapshot(id: task.bookId) {
            let summary = snapshot.summary
            guard let chapterIndex = snapshot.chapters.firstIndex(where: { $0.chapterId == task.chapterId }),
                  environment.source(for: summary) != nil else {
                let alert = UIAlertController(title: "无法打开章节", message: "下载目录中未找到对应章节或站源，请重新检查下载记录。", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好的", style: .default))
                present(alert, animated: true)
                return
            }
            let reader = ReaderViewController(comic: summary, chapters: snapshot.chapters,
                                              chapterIndex: chapterIndex, directoryIncomplete: false,
                                              environment: environment)
            navigationController?.pushViewController(reader, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let task = groups[indexPath.section].tasks[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            self?.environment.downloadRuntime.deleteChapter(id: task.id)
            self?.loadTasks()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    private func handleTaskAction(_ action: TaskCellAction, task: DownloadTask) {
        switch action {
        case .pause:
            environment.downloadRuntime.queue.pause(id: task.id)
        case .resume:
            environment.downloadRuntime.queue.resume(id: task.id)
            environment.downloadRuntime.kick()
        case .retry:
            environment.downloadRuntime.queue.resume(id: task.id)
            environment.downloadRuntime.kick()
        case .cancel:
            environment.downloadRuntime.cancel(id: task.id)
        }
        loadTasks()
    }
}

enum TaskCellAction {
    case pause, resume, retry, cancel
}

final class DownloadTaskCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let actionButton = UIButton(type: .system)
    private var onAction: ((TaskCellAction) -> Void)?
    private var currentAction: TaskCellAction?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setupViews() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = Palette.secondaryText
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = Palette.accent
        progressView.trackTintColor = Palette.secondaryText.withAlphaComponent(0.2)
        contentView.addSubview(progressView)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        contentView.addSubview(actionButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),

            progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            progressView.heightAnchor.constraint(equalToConstant: 3),

            statusLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            actionButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    func configure(with task: DownloadTask, onAction: @escaping (TaskCellAction) -> Void) {
        self.onAction = onAction
        titleLabel.text = task.title

        let progress = task.totalPages > 0 ? Float(task.donePages) / Float(task.totalPages) : 0
        progressView.progress = progress

        switch task.state {
        case .queued:
            statusLabel.text = "排队中..."
            progressView.isHidden = true
            setupActionButton(title: "暂停", action: .pause, tint: Palette.secondaryText)
        case .resolving:
            statusLabel.text = "解析章节中..."
            progressView.isHidden = false
            setupActionButton(title: "暂停", action: .pause, tint: Palette.secondaryText)
        case .downloading:
            statusLabel.text = "正在下载 (\(task.donePages)/\(task.totalPages) 页)"
            progressView.isHidden = false
            setupActionButton(title: "暂停", action: .pause, tint: Palette.secondaryText)
        case .verifying:
            statusLabel.text = "校验保存中..."
            progressView.isHidden = false
            setupActionButton(title: "稍候", action: nil, tint: Palette.secondaryText)
        case .completed:
            statusLabel.text = "已完成 · \(task.totalPages) 页"
            progressView.isHidden = true
            setupActionButton(title: "阅读", action: nil, tint: Palette.accent)
        case .pausedUser:
            statusLabel.text = "已暂停 (\(task.donePages)/\(task.totalPages) 页)"
            progressView.isHidden = false
            setupActionButton(title: "继续", action: .resume, tint: Palette.accent)
        case .waitingNetwork:
            statusLabel.text = "等待网络连接..."
            progressView.isHidden = false
            setupActionButton(title: "暂停", action: .pause, tint: Palette.secondaryText)
        case .waitingVerification:
            statusLabel.text = "等待站源验证..."
            progressView.isHidden = false
            setupActionButton(title: "暂停", action: .pause, tint: Palette.secondaryText)
        case .failed:
            statusLabel.text = "下载失败: \(task.error.isEmpty ? "请重试" : task.error)"
            progressView.isHidden = false
            setupActionButton(title: "重试", action: .retry, tint: .systemRed)
        case .cancelled, .deleting:
            statusLabel.text = "正在删除..."
            progressView.isHidden = true
            setupActionButton(title: nil, action: nil, tint: .clear)
        }
    }

    private func setupActionButton(title: String?, action: TaskCellAction?, tint: UIColor) {
        currentAction = action
        if let title {
            actionButton.isHidden = false
            actionButton.setTitle(title, for: .normal)
            actionButton.setTitleColor(tint, for: .normal)
            actionButton.isEnabled = action != nil
        } else {
            actionButton.isHidden = true
        }
    }

    @objc private func actionTapped() {
        guard let action = currentAction else { return }
        onAction?(action)
    }
}
