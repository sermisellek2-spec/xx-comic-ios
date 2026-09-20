import UIKit
import ComicCore

@MainActor
final class DownloadSelectionViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let detail: ComicDetail
    private let currentIndex: Int
    private let environment: AppEnvironment
    private let onAdded: (() -> Void)?

    private var visibleChapters: [Chapter]
    private var selectedChapterIds = Set<String>()
    private var completedChapterIds = Set<String>()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let startButton = UIButton(type: .system)
    private let hintLabel = UILabel()

    init(detail: ComicDetail, currentIndex: Int = 0, environment: AppEnvironment, onAdded: (() -> Void)? = nil) {
        self.detail = detail
        self.currentIndex = currentIndex
        self.environment = environment
        self.onAdded = onAdded
        self.visibleChapters = detail.chapters
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSheetPresentation()
        view.backgroundColor = Palette.card

        identifyCompletedChapters()
        preselectCurrentChapter()
        setupViews()
        updateStartButton()
    }

    private func setupSheetPresentation() {
        guard let sheet = sheetPresentationController else { return }
        if #available(iOS 16.0, *) {
            sheet.detents = [
                .custom(identifier: .init("downloadSelectionDetent")) { context in
                    context.maximumDetentValue * 0.76
                }
            ]
        } else {
            sheet.detents = [.medium(), .large()]
        }
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 18
    }

    private func identifyCompletedChapters() {
        completedChapterIds.removeAll()
        for ch in detail.chapters {
            if let taskId = try? DownloadModels.key(detail.summary.sourceId, detail.summary.comicId, ch.chapterId),
               let task = environment.downloadRuntime.store.get(id: taskId),
               task.state == .completed {
                completedChapterIds.insert(ch.chapterId)
            }
        }
    }

    private func preselectCurrentChapter() {
        if detail.chapters.indices.contains(currentIndex) {
            let currentId = detail.chapters[currentIndex].chapterId
            if !completedChapterIds.contains(currentId) {
                selectedChapterIds.insert(currentId)
            }
        }
    }

    private func setupViews() {
        // Header
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        let titleLabel = UILabel()
        titleLabel.text = "下载到本地书架"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        let isWifiOnly = environment.downloadRuntime.isWifiOnly
        let wifiHint = isWifiOnly ? "仅 Wi-Fi" : "允许移动网络"
        hintLabel.text = "仅保存本次选择的章节 · \(wifiHint)"
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = Palette.secondaryText
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(hintLabel)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = Palette.secondaryText
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)

        // Tools row
        let toolsStack = UIStackView()
        toolsStack.axis = .horizontal
        toolsStack.spacing = 8
        toolsStack.distribution = .fillEqually
        toolsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolsStack)

        toolsStack.addArrangedSubview(createToolChip(title: "本章", action: #selector(selectCurrentOnly)))
        toolsStack.addArrangedSubview(createToolChip(title: "全选", action: #selector(selectAllChapters)))
        toolsStack.addArrangedSubview(createToolChip(title: "清空", action: #selector(clearSelection)))
        toolsStack.addArrangedSubview(createToolChip(title: "区间", action: #selector(showRangeDialog)))
        toolsStack.addArrangedSubview(createToolChip(title: "倒序 ⇄", action: #selector(reverseList)))

        // TableView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ChapterCell")
        tableView.separatorColor = Palette.secondaryText.withAlphaComponent(0.2)
        view.addSubview(tableView)

        // Bottom start button
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.backgroundColor = Palette.accent
        startButton.setTitleColor(.white, for: .normal)
        startButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        startButton.layer.cornerRadius = 10
        startButton.clipsToBounds = true
        startButton.addTarget(self, action: #selector(startDownload), for: .touchUpInside)
        view.addSubview(startButton)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            hintLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            toolsStack.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            toolsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toolsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toolsStack.heightAnchor.constraint(equalToConstant: 32),

            tableView.topAnchor.constraint(equalTo: toolsStack.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: startButton.topAnchor, constant: -10),

            startButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            startButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            startButton.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func createToolChip(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.setTitleColor(Palette.accent, for: .normal)
        btn.backgroundColor = Palette.accent.withAlphaComponent(0.1)
        btn.layer.cornerRadius = 6
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func updateStartButton() {
        startButton.setTitle("下载选中章节 (\(selectedChapterIds.count))", for: .normal)
        startButton.isEnabled = !selectedChapterIds.isEmpty
        startButton.alpha = selectedChapterIds.isEmpty ? 0.5 : 1.0
    }

    // MARK: - Actions

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    @objc private func selectCurrentOnly() {
        selectedChapterIds.removeAll()
        preselectCurrentChapter()
        tableView.reloadData()
        updateStartButton()
    }

    @objc private func selectAllChapters() {
        for ch in visibleChapters where !completedChapterIds.contains(ch.chapterId) {
            selectedChapterIds.insert(ch.chapterId)
        }
        tableView.reloadData()
        updateStartButton()
    }

    @objc private func clearSelection() {
        selectedChapterIds.removeAll()
        tableView.reloadData()
        updateStartButton()
    }

    @objc private func reverseList() {
        visibleChapters.reverse()
        tableView.reloadData()
    }

    @objc private func showRangeDialog() {
        let alert = UIAlertController(title: "选择章节区间", message: "按当前目录顺序输入起止序号（1 - \(visibleChapters.count)）", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "起始序号"
            tf.keyboardType = .numberPad
        }
        alert.addTextField { tf in
            tf.placeholder = "结束序号"
            tf.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "选中", style: .default) { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            let fromText = alert.textFields?[0].text ?? ""
            let toText = alert.textFields?[1].text ?? ""
            guard let from = Int(fromText), let to = Int(toText), from > 0, to > 0 else { return }
            let start = min(from, to)
            let end = max(from, to)
            let count = self.visibleChapters.count
            guard start <= count else { return }

            let startIndex = start - 1
            let endIndex = min(end, count) - 1

            for i in startIndex...endIndex {
                let ch = self.visibleChapters[i]
                if !self.completedChapterIds.contains(ch.chapterId) {
                    self.selectedChapterIds.insert(ch.chapterId)
                }
            }
            self.tableView.reloadData()
            self.updateStartButton()
        })
        present(alert, animated: true)
    }

    @objc private func startDownload() {
        guard !selectedChapterIds.isEmpty else { return }
        let toDownload = visibleChapters.filter { selectedChapterIds.contains($0.chapterId) }
        guard !toDownload.isEmpty else { return }

        environment.downloadRuntime.enqueue(detail: detail, selectedChapterIds: toDownload.map(\.chapterId))
        dismiss(animated: true) { [weak self] in
            self?.onAdded?()
        }
    }

    // MARK: - UITableViewDataSource & Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleChapters.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChapterCell", for: indexPath)
        let ch = visibleChapters[indexPath.row]
        let isCompleted = completedChapterIds.contains(ch.chapterId)
        let isSelected = selectedChapterIds.contains(ch.chapterId)

        cell.backgroundColor = .clear
        var content = cell.defaultContentConfiguration()

        if isCompleted {
            content.text = "\(ch.title) · 已下载"
            content.textProperties.color = Palette.secondaryText
            cell.accessoryType = .checkmark
            cell.tintColor = Palette.secondaryText.withAlphaComponent(0.5)
            cell.selectionStyle = .none
        } else {
            content.text = ch.title
            content.textProperties.color = Palette.text
            cell.accessoryType = isSelected ? .checkmark : .none
            cell.tintColor = Palette.accent
            cell.selectionStyle = .default
        }

        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let ch = visibleChapters[indexPath.row]
        guard !completedChapterIds.contains(ch.chapterId) else { return }

        if selectedChapterIds.contains(ch.chapterId) {
            selectedChapterIds.remove(ch.chapterId)
        } else {
            selectedChapterIds.insert(ch.chapterId)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        updateStartButton()
    }
}
