import UIKit
import ComicCore

@MainActor
final class SourceSwitchSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private let originalComic: ComicSummary
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()

    private struct CandidateItem {
        let source: any ComicSource
        let candidate: ComicSummary
        var latestChapter: String?
    }

    private var candidates: [CandidateItem] = []
    private var isSearching = false
    private var searchTask: Task<Void, Never>?

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
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])

        startSearch()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        searchTask?.cancel()
    }

    @objc private func cancelTapped() {
        searchTask?.cancel()
        dismiss(animated: true)
    }

    private func startSearch() {
        isSearching = true
        activityIndicator.startAnimating()
        statusLabel.text = "正在全网搜索可用站源…"
        tableView.isHidden = true

        let query = originalComic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchSources = environment.searchSources.filter { $0.id != originalComic.sourceId }

        searchTask = Task { [weak self] in
            guard let self else { return }
            var found: [CandidateItem] = []

            for source in searchSources {
                if Task.isCancelled { break }
                do {
                    let results = try await source.search(keyword: query, page: 1)
                    if let exact = results.first(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == query }) ?? results.first {
                        found.append(CandidateItem(source: source, candidate: exact, latestChapter: exact.subtitle))
                    }
                } catch {
                    continue
                }
            }

            guard !Task.isCancelled else { return }
            self.candidates = found
            self.isSearching = false
            self.activityIndicator.stopAnimating()

            if found.isEmpty {
                self.statusLabel.text = "未在其他站源找到同名漫画"
                self.tableView.isHidden = true
            } else {
                self.statusLabel.text = ""
                self.tableView.isHidden = false
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        candidates.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "candidate_cell", for: indexPath) as! CandidateCell
        let item = candidates[indexPath.row]
        cell.configure(item: item, environment: environment) { [weak self] in
            self?.performSwitch(to: item)
        }
        return cell
    }

    private func performSwitch(to item: CandidateItem) {
        let loadingAlert = UIAlertController(title: "正在换源…", message: "正在获取目录并对应阅读进度", preferredStyle: .alert)
        present(loadingAlert, animated: true)

        Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await item.source.detail(comicId: item.candidate.comicId)
                guard !detail.chapters.isEmpty else {
                    loadingAlert.dismiss(animated: true) {
                        self.showError(NSError(domain: "XXComic", code: -1, userInfo: [NSLocalizedDescriptionKey: "目标源目录为空，换源已取消，已保留原站源"]))
                    }
                    return
                }

                // Match chapter index
                var matchingChapter: Chapter?
                var matchingIndex = 0
                if let oldEntry = self.environment.library.entry(for: self.originalComic), let oldReading = oldEntry.reading {
                    let oldTitle = oldReading.chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let foundIdx = detail.chapters.firstIndex(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == oldTitle }) {
                        matchingIndex = foundIdx
                        matchingChapter = detail.chapters[foundIdx]
                    } else if oldReading.chapterIndex < detail.chapters.count {
                        matchingIndex = oldReading.chapterIndex
                        matchingChapter = detail.chapters[matchingIndex]
                    } else {
                        matchingIndex = 0
                        matchingChapter = detail.chapters.first
                    }
                } else {
                    matchingChapter = detail.chapters.first
                }

                try self.environment.replaceSource(
                    original: self.originalComic,
                    target: detail,
                    matchingChapter: matchingChapter,
                    matchingChapterIndex: matchingIndex
                )

                loadingAlert.dismiss(animated: true) { [weak self] in
                    guard let self else { return }
                    self.onSourceReplaced?(detail)
                    self.dismiss(animated: true)
                }
            } catch {
                loadingAlert.dismiss(animated: true) { [weak self] in
                    self?.showError(NSError(domain: "XXComic", code: -1, userInfo: [NSLocalizedDescriptionKey: "换源失败：\(error.localizedDescription)，已保留原站源"]))
                }
            }
        }
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
                coverView.heightAnchor.constraint(equalToConstant: 64),

                textStack.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
                textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: switchButton.leadingAnchor, constant: -8),

                switchButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
                switchButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                switchButton.widthAnchor.constraint(equalToConstant: 58),
                switchButton.heightAnchor.constraint(equalToConstant: 28),

                contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 78)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:)") }

        @objc private func switchTapped() {
            onSwitch?()
        }

        func configure(item: CandidateItem, environment: AppEnvironment, onSwitch: @escaping () -> Void) {
            self.onSwitch = onSwitch
            titleLabel.text = item.candidate.title
            sourceLabel.text = item.source.name
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
