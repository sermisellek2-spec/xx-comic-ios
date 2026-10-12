import UIKit
import ComicCore

@MainActor
final class SourceSwitchSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private let originalComic: ComicSummary
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private let retrySearch = UIButton(type: .system)

    private struct CandidateItem {
        let source: any ComicSource
        let candidate: ComicSummary
        var latestChapter: String?
    }

    private var candidates: [CandidateItem] = []
    private var isSearching = false
    private var searchGeneration = UUID()
    private var pendingSources: [any ComicSource] = []
    private var searchTasks: [String: Task<Void, Never>] = [:]
    private var searchTimeouts: [String: Task<Void, Never>] = [:]
    private var searchRequests: [String: UUID] = [:]
    private var switchGeneration = UUID()
    private var switchTask: Task<Void, Never>?
    private var switchTimeout: Task<Void, Never>?
    private weak var loadingAlert: UIAlertController?

    var onSourceReplaced: ((ComicDetail) -> Void)?

    init(environment: AppEnvironment, originalComic: ComicSummary, onSourceReplaced: ((ComicDetail) -> Void)? = nil) {
        self.environment = environment
        self.originalComic = originalComic
        self.onSourceReplaced = onSourceReplaced
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(comic: ComicSummary, environment: AppEnvironment, onSourceReplaced: ((ComicDetail) -> Void)? = nil) {
        self.init(environment: environment, originalComic: comic, onSourceReplaced: onSourceReplaced)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "换源 · \(originalComic.title)"
        view.backgroundColor = Palette.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "source-switch.cancel"

        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.accessibilityIdentifier = "source-switch.candidates"
        tableView.register(CandidateCell.self, forCellReuseIdentifier: "candidate_cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = Palette.text2
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        activityIndicator.hidesWhenStopped = true
        statusLabel.accessibilityIdentifier = "source-switch.status"
        retrySearch.setTitle("重新查找", for: .normal)
        retrySearch.accessibilityIdentifier = "source-switch.retry"
        retrySearch.addTarget(self, action: #selector(startSearch), for: .touchUpInside)
        retrySearch.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let feedback = UIStackView(arrangedSubviews: [activityIndicator, statusLabel, retrySearch])
        feedback.spacing = 8; feedback.alignment = .center
        feedback.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(feedback)

        NSLayoutConstraint.activate([
            feedback.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            feedback.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            feedback.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            feedback.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            tableView.topAnchor.constraint(equalTo: feedback.bottomAnchor, constant: 4),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        startSearch()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            cancelSearch(); cancelSwitch()
        }
    }

    @objc private func cancelTapped() {
        cancelSearch(); cancelSwitch()
        dismiss(animated: true)
    }

    private func cancelSearch() {
        searchGeneration = UUID()
        searchTasks.values.forEach { $0.cancel() }
        searchTimeouts.values.forEach { $0.cancel() }
        searchTasks.removeAll(); searchTimeouts.removeAll(); searchRequests.removeAll()
        pendingSources.removeAll(); isSearching = false
    }

    @objc private func startSearch() {
        guard switchTask == nil else { return }
        cancelSearch(); candidates = []
        if let source = environment.source(for: originalComic) {
            candidates = [CandidateItem(source: source, candidate: originalComic, latestChapter: originalComic.subtitle)]
        }
        let query = SearchRules.trim(originalComic.title)
        pendingSources = query.isEmpty ? [] : environment.searchSources.filter { $0.id != originalComic.sourceId }
        startNextSearches(query: query, generation: searchGeneration)
    }

    private func startNextSearches(query: String, generation: UUID) {
        guard searchGeneration == generation else { return }
        // Android runs three requests and starts each 10-second timeout when
        // it leaves the queue. One slow source must not hide ready candidates.
        while searchTasks.count < 3, !pendingSources.isEmpty {
            let source = pendingSources.removeFirst(), id = source.id, request = UUID()
            searchRequests[id] = request
            searchTasks[id] = Task { [weak self] in
                let items = (try? await source.search(keyword: query, page: 1)) ?? []
                guard !Task.isCancelled else { return }
                let exact = items.first { $0.sourceId == id && !$0.comicId.isEmpty && SearchRules.isExact(title: $0.title, query: query) }
                self?.finishSearch(source: source, candidate: exact, query: query, generation: generation, request: request)
            }
            searchTimeouts[id] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                self?.finishSearch(source: source, candidate: nil, query: query, generation: generation, request: request)
            }
        }
        renderSearch()
    }

    private func finishSearch(source: any ComicSource, candidate: ComicSummary?, query: String, generation: UUID, request: UUID) {
        guard searchGeneration == generation, searchRequests[source.id] == request else { return }
        searchTasks.removeValue(forKey: source.id)?.cancel()
        searchTimeouts.removeValue(forKey: source.id)?.cancel()
        searchRequests.removeValue(forKey: source.id)
        if let candidate { candidates.append(CandidateItem(source: source, candidate: candidate, latestChapter: candidate.subtitle)) }
        let order = [originalComic.sourceId] + environment.searchSources.map(\.id)
        candidates.sort { (order.firstIndex(of: $0.source.id) ?? Int.max) < (order.firstIndex(of: $1.source.id) ?? Int.max) }
        startNextSearches(query: query, generation: generation)
    }

    private func renderSearch() {
        isSearching = !pendingSources.isEmpty || !searchTasks.isEmpty
        title = "换源列表（\(candidates.count)）"
        statusLabel.text = isSearching ? "正在查找同名漫画…" : candidates.count <= 1 ? "暂未找到其他同名站源" : "选择站源，保留收藏与阅读进度"
        isSearching ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
        retrySearch.isHidden = isSearching
        retrySearch.isEnabled = switchTask == nil
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        candidates.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "candidate_cell", for: indexPath) as! CandidateCell
        let item = candidates[indexPath.row]
        cell.accessibilityIdentifier = "source-switch.row." + item.source.id
        cell.configure(item: item, current: item.source.id == originalComic.sourceId, environment: environment) { [weak self] in
            self?.performSwitch(to: item)
        }
        return cell
    }

    private func performSwitch(to item: CandidateItem) {
        guard switchTask == nil, item.source.id != originalComic.sourceId else { return }
        let token = UUID(); switchGeneration = token
        let loadingAlert = UIAlertController(title: "正在换源…", message: "正在获取目录并对应阅读进度", preferredStyle: .alert)
        self.loadingAlert = loadingAlert
        loadingAlert.addAction(UIAlertAction(title: "取消换源", style: .cancel) { [weak self] _ in self?.cancelSwitch() })
        present(loadingAlert, animated: true)

        switchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.switchGeneration == token {
                    self.switchTimeout?.cancel(); self.switchTimeout = nil
                    self.switchTask = nil; self.retrySearch.isEnabled = true
                }
            }
            do {
                let raw = try await item.source.detail(comicId: item.candidate.comicId)
                guard raw.summary.sourceId == item.source.id, raw.summary.comicId == item.candidate.comicId else { throw SourceSwitchError.mismatchedDetail }
                let detail = try await raw.ensuringChapters { try await item.source.chapters(comicId: item.candidate.comicId) }
                try Task.checkCancellation()
                guard self.switchGeneration == token else { return }
                let oldReading = self.environment.library.entry(for: self.originalComic)?.reading
                let matchingIndex = ChapterMatching.findMatchingChapterIndex(chapters: detail.chapters, currentTitle: oldReading?.chapter.title, defaultIndex: oldReading?.chapterIndex ?? 0)

                loadingAlert.actions.first?.isEnabled = false
                try self.environment.replaceSource(
                    original: self.originalComic,
                    target: detail,
                    matchingChapter: detail.chapters[matchingIndex],
                    matchingChapterIndex: matchingIndex
                )

                loadingAlert.dismiss(animated: true) { [weak self] in
                    guard let self, self.switchGeneration == token else { return }
                    self.onSourceReplaced?(detail)
                    self.dismiss(animated: true)
                }
            } catch {
                guard self.switchGeneration == token, !Task.isCancelled else { return }
                loadingAlert.dismiss(animated: true) { [weak self] in
                    guard let self, self.switchGeneration == token else { return }
                    let failure = UIAlertController(title: "换源失败", message: error.localizedDescription + "；已保留原站源和阅读记录。", preferredStyle: .alert)
                    failure.addAction(UIAlertAction(title: "取消", style: .cancel))
                    failure.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in self?.performSwitch(to: item) })
                    self.present(failure, animated: true)
                }
            }
        }
        switchTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard let self, self.switchGeneration == token else { return }
            self.cancelSwitch(dismissAlert: false)
            loadingAlert.dismiss(animated: true) { [weak self] in
                guard let self, self.viewIfLoaded?.window != nil else { return }
                let failure = UIAlertController(title: "换源失败", message: "这个站源响应超时；已保留原站源和阅读记录。", preferredStyle: .alert)
                failure.addAction(UIAlertAction(title: "取消", style: .cancel))
                failure.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in self?.performSwitch(to: item) })
                self.present(failure, animated: true)
            }
        }
    }

    private func cancelSwitch(dismissAlert: Bool = true) {
        switchGeneration = UUID(); switchTask?.cancel(); switchTask = nil
        switchTimeout?.cancel(); switchTimeout = nil
        if dismissAlert { loadingAlert?.dismiss(animated: true) }
        loadingAlert = nil
        retrySearch.isEnabled = true
    }

    private enum SourceSwitchError: LocalizedError {
        case mismatchedDetail
        var errorDescription: String? { "目标详情与选择的漫画不匹配" }
    }

    private final class CandidateCell: UITableViewCell {
        private let coverView = RemoteImageView()
        private let titleLabel = UILabel()
        private let sourceLabel = UILabel()
        private let latestLabel = UILabel()
        private let switchButton = UIButton(type: .system)
        private var onSwitch: (() -> Void)?

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            backgroundColor = Palette.card
            contentView.backgroundColor = Palette.card

            coverView.contentMode = .scaleAspectFill
            coverView.clipsToBounds = true
            coverView.layer.cornerRadius = 6
            coverView.translatesAutoresizingMaskIntoConstraints = false

            titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            titleLabel.textColor = Palette.text

            sourceLabel.font = .systemFont(ofSize: 13, weight: .medium)
            sourceLabel.textColor = Palette.accent

            latestLabel.font = .systemFont(ofSize: 12)
            latestLabel.textColor = Palette.text2

            switchButton.setTitle("切换", for: .normal)
            switchButton.setTitleColor(.white, for: .normal)
            switchButton.backgroundColor = Palette.accent
            switchButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            switchButton.layer.cornerRadius = 14
            switchButton.translatesAutoresizingMaskIntoConstraints = false
            switchButton.addTarget(self, action: #selector(switchTapped), for: .touchUpInside)

            let textStack = UIStackView(arrangedSubviews: [titleLabel, sourceLabel, latestLabel])
            textStack.axis = .vertical
            textStack.spacing = 3
            textStack.translatesAutoresizingMaskIntoConstraints = false

            contentView.addSubview(coverView)
            contentView.addSubview(textStack)
            contentView.addSubview(switchButton)

            NSLayoutConstraint.activate([
                coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
                coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                coverView.widthAnchor.constraint(equalToConstant: 48),
                coverView.heightAnchor.constraint(equalToConstant: 66),

                textStack.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
                textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: switchButton.leadingAnchor, constant: -8),

                switchButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
                switchButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                switchButton.widthAnchor.constraint(equalToConstant: 58),
                switchButton.heightAnchor.constraint(equalToConstant: 44),

                contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 78)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:)") }

        @objc private func switchTapped() {
            onSwitch?()
        }

        func configure(item: CandidateItem, current: Bool, environment: AppEnvironment, onSwitch: @escaping () -> Void) {
            self.onSwitch = onSwitch
            titleLabel.text = item.candidate.title
            sourceLabel.text = item.source.name + (current ? " · 当前站源" : "")
            switchButton.setTitle(current ? "当前" : "切换", for: .normal)
            switchButton.isEnabled = !current
            switchButton.accessibilityIdentifier = "source-switch.select." + item.source.id
            latestLabel.text = item.latestChapter?.isEmpty == false ? "最新: \(item.latestChapter!)" : "可用"
            coverView.loadCover(item.candidate, referer: item.source.referer, library: environment.localLibrary)
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            coverView.cancel()
            coverView.image = nil
        }
    }
}
