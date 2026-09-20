import UIKit
import ComicCore
import UniformTypeIdentifiers

@MainActor
class ComicGridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    let environment: AppEnvironment
    let header = UIStackView()
    let statusButton = UIButton(type: .system)
    let collection: UICollectionView
    var comics: [ComicSummary] = []
    var retry: (() -> Void)?
    private let emptyArtwork = UIImageView(image: UIImage(named: "rem_empty"))

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
        emptyArtwork.contentMode = .scaleAspectFit
        let emptyHost = UIView()
        emptyArtwork.translatesAutoresizingMaskIntoConstraints = false; emptyHost.addSubview(emptyArtwork)
        NSLayoutConstraint.activate([
            emptyArtwork.centerXAnchor.constraint(equalTo: emptyHost.centerXAnchor),
            emptyArtwork.centerYAnchor.constraint(equalTo: emptyHost.centerYAnchor),
            emptyArtwork.widthAnchor.constraint(equalToConstant: 180),
            emptyArtwork.heightAnchor.constraint(equalToConstant: 180)
        ])
        collection.backgroundView = emptyHost
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
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentedViewController == nil else { return }
        collection.visibleCells.forEach { ($0 as? ComicCell)?.cover.cancel() }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collection.reloadData()
    }
    func status(_ text: String, retry: (() -> Void)? = nil) {
        statusButton.setTitle(text, for: .normal); self.retry = retry
        emptyArtwork.isHidden = !comics.isEmpty
        emptyArtwork.image = UIImage(named: retry != nil ? "rem_error" : (text.contains("正在") ? "rem_loading" : "rem_empty"))
    }
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
final class BookshelfViewController: ComicGridViewController, UIDocumentPickerDelegate {
    private let historyOnly: Bool
    private let resume = UIButton(type: .system)
    private let shelfMode = UISegmentedControl(items: ["我的书架", "本地书架"])
    private var importTask: Task<Void, Never>?
    private var importingFolder = false
    private var localMode: Bool { !historyOnly && shelfMode.selectedSegmentIndex == 1 }
    init(environment: AppEnvironment, historyOnly: Bool = false) {
        self.historyOnly = historyOnly
        super.init(environment: environment)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = historyOnly ? "阅读历史" : "书架"
        if !historyOnly {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: "导入", style: .plain, target: self, action: #selector(importImages)),
                UIBarButtonItem(title: "历史", style: .plain, target: self, action: #selector(showHistory))
            ]
            shelfMode.selectedSegmentIndex = environment.readingHabits.currentLaunchTab
            shelfMode.addTarget(self, action: #selector(shelfChanged), for: .valueChanged)
            header.addArrangedSubview(shelfMode)
            resume.titleLabel?.numberOfLines = 2
            resume.contentHorizontalAlignment = .leading
            resume.addTarget(self, action: #selector(continueReading), for: .touchUpInside)
            header.addArrangedSubview(resume)
        }
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); refresh() }
    private func refresh() {
        if localMode {
            resume.isHidden = true
            do {
                comics = try environment.localLibrary.books().map { try environment.localLibrary.summary(for: $0) }
                collection.reloadData()
                status(comics.isEmpty ? "本地书架空空的，点击导入添加图片" : "")
            } catch { status(error.localizedDescription) }
            return
        }
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
    @objc private func shelfChanged() {
        environment.readingHabits.lastManualTab = shelfMode.selectedSegmentIndex
        refresh()
    }
    @objc private func importImages() {
        if let importTask { importTask.cancel(); return }
        let menu = UIAlertController(title: "导入本地漫画", message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "图片文件", style: .default) { [weak self] _ in self?.pickImport(folder: false) })
        menu.addAction(UIAlertAction(title: "图片文件夹", style: .default) { [weak self] _ in self?.pickImport(folder: true) })
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        menu.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(menu, animated: true)
    }
    private func pickImport(folder: Bool) {
        importingFolder = folder
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: folder ? [.folder] : [.image], asCopy: !folder)
        picker.allowsMultipleSelection = !folder; picker.delegate = self
        present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        let folder = importingFolder
        let alert = UIAlertController(title: folder ? "导入文件夹漫画" : "导入图片漫画", message: folder ? "支持图片和章节子目录，按自然顺序导入。" : "所选图片合并为一本漫画，按文件名自然排序。", preferredStyle: .alert)
        alert.addTextField { $0.text = folder ? urls.first?.lastPathComponent : urls.first?.deletingPathExtension().lastPathComponent }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "导入", style: .default) { [weak self, weak alert] _ in
            self?.beginImport(urls, title: alert?.textFields?.first?.text ?? "本地漫画", folder: folder)
        })
        if presentedViewController === controller {
            controller.dismiss(animated: true) { [weak self] in self?.present(alert, animated: true) }
        } else { present(alert, animated: true) }
    }
    private func beginImport(_ urls: [URL], title: String, folder: Bool) {
        let library = environment.localLibrary
        status("正在导入…，再次点击导入可取消")
        let worker = Task.detached(priority: .userInitiated) {
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            if folder, let url = urls.first {
                return try library.importFolder(title: title, folder: url, isReadableImage: LocalImageProbe.isReadable)
            }
            for url in urls {
                try Task.checkCancellation()
                guard try LocalImageProbe.isReadable(url) else { throw LocalLibraryError.invalidBook }
            }
            return try library.importImages(title: title, files: urls)
        }
        importTask = Task { [weak self] in
            do {
                _ = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self else { return }
                self.shelfMode.selectedSegmentIndex = 1; self.refresh()
                self.status("导入完成")
            } catch {
                self?.status(error is CancellationError ? "已取消导入，原文件未改动" : error.localizedDescription)
            }
            self?.importTask = nil
        }
    }
    deinit { importTask?.cancel() }
    @objc private func continueReading() { if let recent = environment.library.history.first { open(recent.summary) } }
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !historyOnly, !localMode else { return nil }
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
