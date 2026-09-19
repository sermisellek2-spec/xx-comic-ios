import UIKit
import ComicCore

@MainActor
class ComicGridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    let environment: AppEnvironment
    let header = UIStackView()
    let statusButton = UIButton(type: .system)
    let collection: UICollectionView
    var comics: [ComicSummary] = []
    var retry: (() -> Void)?

    init(environment: AppEnvironment) {
        self.environment = environment
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 12, left: 14, bottom: 24, right: 14)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        header.axis = .vertical
        header.spacing = 8
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        statusButton.titleLabel?.numberOfLines = 0
        statusButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        statusButton.addTarget(self, action: #selector(retryPressed), for: .touchUpInside)
        collection.backgroundColor = Palette.background
        collection.register(ComicCell.self, forCellWithReuseIdentifier: "comic")
        collection.dataSource = self
        collection.delegate = self
        for item in [header, collection, statusButton] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor), collection.topAnchor.constraint(equalTo: header.bottomAnchor),
            collection.leadingAnchor.constraint(equalTo: view.leadingAnchor), collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: statusButton.topAnchor), statusButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), statusButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
    }
    @objc private func retryPressed() { retry?() }
    func status(_ text: String, retry: (() -> Void)? = nil) { statusButton.setTitle(text, for: .normal); self.retry = retry }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { comics.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "comic", for: indexPath) as! ComicCell
        let comic = comics[indexPath.item]
        cell.configure(comic, referer: environment.source(for: comic)?.referer ?? "")
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = floor((collectionView.bounds.width - 48) / 3)
        return CGSize(width: max(1, width), height: max(1, width) * 4 / 3 + 42)
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        open(comics[indexPath.item])
    }
    func open(_ comic: ComicSummary) {
        guard environment.source(for: comic) != nil else { status("该站源暂不可用，已保留阅读记录。"); return }
        navigationController?.pushViewController(DetailViewController(comic: comic, environment: environment), animated: true)
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.collection.collectionViewLayout.invalidateLayout() })
    }
}

@MainActor
final class BookshelfViewController: ComicGridViewController {
    private let historyOnly: Bool
    private let resume = UIButton(type: .system)
    init(environment: AppEnvironment, historyOnly: Bool = false) {
        self.historyOnly = historyOnly
        super.init(environment: environment)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = historyOnly ? "阅读历史" : "书架"
        if !historyOnly {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "历史", style: .plain, target: self, action: #selector(showHistory))
            resume.titleLabel?.numberOfLines = 2
            resume.contentHorizontalAlignment = .leading
            resume.addTarget(self, action: #selector(continueReading), for: .touchUpInside)
            header.addArrangedSubview(resume)
        }
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); refresh() }
    private func refresh() {
        comics = (historyOnly ? environment.library.history : environment.library.favorites).map(\.summary)
        collection.reloadData()
        status(comics.isEmpty ? (historyOnly ? "还没有阅读记录" : "书架空空的，去发现页找漫画吧") : "")
        let recent = environment.library.history.first
        resume.isHidden = recent == nil
        resume.setTitle(recent.map { "继续阅读 · \($0.summary.title)\n\($0.reading?.chapter.title ?? "")" }, for: .normal)
    }
    @objc private func showHistory() {
        navigationController?.pushViewController(BookshelfViewController(environment: environment, historyOnly: true), animated: true)
    }
    @objc private func continueReading() { if let recent = environment.library.history.first { open(recent.summary) } }
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !historyOnly else { return nil }
        let comic = comics[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [UIAction(title: "移出收藏", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                guard let self else { return }
                do {
                    try self.environment.library.setFavorite(comic, favorite: false)
                    self.refresh()
                    self.status("已移出收藏 · 点击撤销") { [weak self] in
                        guard let self else { return }
                        do { try self.environment.library.setFavorite(comic, favorite: true); self.refresh() }
                        catch { self.showError(error) }
                    }
                } catch { self.showError(error) }
            }])
        }
    }
}
