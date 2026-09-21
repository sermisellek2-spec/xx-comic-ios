import UIKit
import ComicCore
import UniformTypeIdentifiers

@MainActor
final class VolumeManagerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment
    private let seriesId: String
    private var seriesTitle: String
    private let onVolumesChanged: () -> Void

    private var volumes: [LocalBook] = []
    private var seriesRecord: LocalSeriesRecord?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let appendButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    // Pending deletion with 3.5s undo timer
    private struct PendingDeletion {
        let volume: LocalBook
        let originalIndex: Int
        let timer: Timer
    }
    private var pendingDeletion: PendingDeletion?

    // Undo snackbar views
    private let undoContainer = UIView()
    private let undoLabel = UILabel()
    private let undoButton = UIButton(type: .system)
    private var undoBottomConstraint: NSLayoutConstraint?

    init(seriesId: String, seriesTitle: String, environment: AppEnvironment, onVolumesChanged: @escaping () -> Void) {
        self.seriesId = seriesId
        self.seriesTitle = seriesTitle
        self.environment = environment
        self.onVolumesChanged = onVolumesChanged
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSheetPresentation()
        view.backgroundColor = Palette.background
        title = "管理分卷"

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(dismissSelf))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(toggleEditMode))

        setupViews()
        loadVolumes()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        commitPendingDeletionImmediately()
    }

    deinit {
        // Ensure any pending timer is invalidated
        pendingDeletion?.timer.invalidate()
    }

    private func setupSheetPresentation() {
        if #available(iOS 15.0, *) {
            if let sheet = sheetPresentationController {
                if #available(iOS 16.0, *) {
                    let customDetent = UISheetPresentationController.Detent.custom(identifier: .init("72percent")) { context in
                        return context.maximumDetentValue * 0.72
                    }
                    sheet.detents = [customDetent, .large()]
                } else {
                    sheet.detents = [.medium(), .large()]
                }
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16
            }
        }
    }

    private func setupViews() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.dragInteractionEnabled = true
        view.addSubview(tableView)

        appendButton.translatesAutoresizingMaskIntoConstraints = false
        appendButton.setTitle("＋ 追加新分卷", for: .normal)
        appendButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        appendButton.backgroundColor = Palette.accent
        appendButton.setTitleColor(.white, for: .normal)
        appendButton.layer.cornerRadius = 12
        appendButton.clipsToBounds = true
        appendButton.addTarget(self, action: #selector(openDocumentPicker), for: .touchUpInside)
        view.addSubview(appendButton)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        // Undo container setup
        undoContainer.translatesAutoresizingMaskIntoConstraints = false
        undoContainer.backgroundColor = UIColor(white: 0.15, alpha: 0.95)
        undoContainer.layer.cornerRadius = 10
        undoContainer.clipsToBounds = true
        undoContainer.isHidden = true
        view.addSubview(undoContainer)

        undoLabel.translatesAutoresizingMaskIntoConstraints = false
        undoLabel.textColor = .white
        undoLabel.font = .preferredFont(forTextStyle: .subheadline)
        undoContainer.addSubview(undoLabel)

        undoButton.translatesAutoresizingMaskIntoConstraints = false
        undoButton.setTitle("撤销", for: .normal)
        undoButton.setTitleColor(UIColor.systemYellow, for: .normal)
        undoButton.titleLabel?.font = .boldSystemFont(ofSize: 15)
        undoButton.addTarget(self, action: #selector(undoDeleteTapped), for: .touchUpInside)
        undoContainer.addSubview(undoButton)

        undoBottomConstraint = undoContainer.bottomAnchor.constraint(equalTo: appendButton.topAnchor, constant: -12)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: appendButton.topAnchor, constant: -12),

            appendButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            appendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            appendButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            appendButton.heightAnchor.constraint(equalToConstant: 48),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            undoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            undoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            undoBottomConstraint!,
            undoContainer.heightAnchor.constraint(equalToConstant: 44),

            undoLabel.leadingAnchor.constraint(equalTo: undoContainer.leadingAnchor, constant: 16),
            undoLabel.centerYAnchor.constraint(equalTo: undoContainer.centerYAnchor),
            undoLabel.trailingAnchor.constraint(lessThanOrEqualTo: undoButton.leadingAnchor, constant: -8),

            undoButton.trailingAnchor.constraint(equalTo: undoContainer.trailingAnchor, constant: -16),
            undoButton.centerYAnchor.constraint(equalTo: undoContainer.centerYAnchor)
        ])
    }

    private func loadVolumes() {
        loadingIndicator.startAnimating()
        Task { [weak self] in
            guard let self else { return }
            do {
                let library = self.environment.localLibrary
                guard let series = try await library.series(id: self.seriesId) else {
                    self.loadingIndicator.stopAnimating()
                    return
                }
                self.seriesRecord = series
                self.seriesTitle = series.displayTitle
                self.title = "管理分卷 · \(series.displayTitle)"
                let loadedVolumes = try library.volumes(for: series)
                self.volumes = loadedVolumes
                self.tableView.reloadData()
            } catch {
                self.showVolumeError(error)
            }
            self.loadingIndicator.stopAnimating()
        }
    }

    @objc private func dismissSelf() {
        commitPendingDeletionImmediately()
        dismiss(animated: true) { [onVolumesChanged] in
            onVolumesChanged()
        }
    }

    @objc private func toggleEditMode() {
        let isEditing = !tableView.isEditing
        tableView.setEditing(isEditing, animated: true)
        navigationItem.rightBarButtonItem?.title = isEditing ? "完成" : "排序"
    }

    // MARK: - Deletion & Undo

    private func commitPendingDeletionImmediately() {
        guard let pending = pendingDeletion else { return }
        pending.timer.invalidate()
        let volumeIdToDelete = pending.volume.id
        self.pendingDeletion = nil
        self.undoContainer.isHidden = true

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.environment.localLibrary.deleteVolume(seriesId: self.seriesId, volumeId: volumeIdToDelete)
                self.onVolumesChanged()
            } catch {
                self.showVolumeError(error)
                self.loadVolumes()
            }
        }
    }

    private func scheduleVolumeDeletion(_ volume: LocalBook, at index: Int) {
        // If there was an earlier pending deletion, commit it now
        commitPendingDeletionImmediately()

        // Remove from table visually
        volumes.remove(at: index)
        tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)

        // Show undo banner with 3.5s countdown
        undoLabel.text = "已移除分卷「\(volume.title)」"
        undoContainer.isHidden = false

        let timer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.commitPendingDeletionImmediately()
            }
        }
        pendingDeletion = PendingDeletion(volume: volume, originalIndex: index, timer: timer)
    }

    @objc private func undoDeleteTapped() {
        guard let pending = pendingDeletion else { return }
        pending.timer.invalidate()
        let restoredVolume = pending.volume
        let restoredIndex = min(pending.originalIndex, volumes.count)
        self.pendingDeletion = nil
        self.undoContainer.isHidden = true

        volumes.insert(restoredVolume, at: restoredIndex)
        tableView.insertRows(at: [IndexPath(row: restoredIndex, section: 0)], with: .automatic)
    }

    // MARK: - Table View Data Source & Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return volumes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "VolumeCell") ??
            UITableViewCell(style: .subtitle, reuseIdentifier: "VolumeCell")
        let volume = volumes[indexPath.row]

        let formatLabel: String
        if volume.epub != nil { formatLabel = "EPUB" }
        else if volume.pdf != nil { formatLabel = "PDF" }
        else if volume.importFormat == .zip || volume.importFormat == .cbz { formatLabel = "ZIP" }
        else { formatLabel = "图片" }

        cell.textLabel?.text = "第 \(indexPath.row + 1) 卷 · \(volume.title)"
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.text = "\(volume.pages.count) 页 · \(formatLabel)"
        cell.detailTextLabel?.textColor = Palette.secondaryText
        cell.showsReorderControl = true
        return cell
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard sourceIndexPath.row != destinationIndexPath.row else { return }
        commitPendingDeletionImmediately()

        let moved = volumes.remove(at: sourceIndexPath.row)
        volumes.insert(moved, at: destinationIndexPath.row)

        let newVolumeIds = volumes.map(\.id)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.environment.localLibrary.reorderVolumes(seriesId: self.seriesId, newVolumeIDs: newVolumeIds)
                self.tableView.reloadData()
                self.onVolumesChanged()
            } catch {
                self.showVolumeError(error)
                self.loadVolumes()
            }
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let volume = volumes[indexPath.row]
            if volumes.count <= 1 {
                let alert = UIAlertController(title: "无法删除唯一分卷", message: "这是该漫画的最后一个分卷。如需删除整个漫画，请在详情页选择删除漫画。", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好的", style: .default))
                present(alert, animated: true)
                return
            }
            scheduleVolumeDeletion(volume, at: indexPath.row)
        }
    }

    // MARK: - Append Volumes

    @objc private func openDocumentPicker() {
        commitPendingDeletionImmediately()
        let types: [UTType] = [.zip, .epub, .pdf, .folder, .image]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    private func showVolumeError(_ error: Error) {
        let alert = UIAlertController(title: "操作失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        present(alert, animated: true)
    }
}

extension VolumeManagerViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        loadingIndicator.startAnimating()
        appendButton.isEnabled = false

        Task { [weak self] in
            guard let self else { return }
            do {
                let sessionURL = self.environment.localLibrary.directory.appendingPathComponent("batch_import_session.json")
                let session = try BatchImportSession(file: sessionURL)
                let worker = BatchImportWorker(
                    library: self.environment.localLibrary,
                    session: session,
                    isReadableImage: LocalImageProbe.isReadable,
                    inspectPdf: PdfRenderer.inspect,
                    renderPdfCover: { try PdfRenderer.render($0, pageIndex: 0, maximumDimension: 720, quality: 0.85) }
                )
                let summary = try await worker.appendVolumes(urls: urls, toSeriesId: self.seriesId, seriesTitle: self.seriesTitle)
                self.loadVolumes()
                self.onVolumesChanged()

                if summary.failedCount > 0 {
                    let alert = UIAlertController(title: "追加完成", message: "成功追加 \(summary.succeededCount) 卷，\(summary.failedCount) 个文件失败。", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "好的", style: .default))
                    self.present(alert, animated: true)
                }
            } catch {
                self.showVolumeError(error)
            }
            self.loadingIndicator.stopAnimating()
            self.appendButton.isEnabled = true
        }
    }
}
