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
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let appendButton = UIButton(type: .system)
    private let cancelAppendButton = UIButton(type: .system)
    private let countLabel = UILabel(), feedback = UILabel(), undoLabel = UILabel()
    private let undoContainer = UIStackView(), undoButton = UIButton(type: .system)
    private var loadTask: Task<Void, Never>?
    private var appendTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private var busy = false, expanded = false
    private struct PendingDeletion { let volume: LocalBook; let index: Int; let timer: Timer }
    private var pendingDeletion: PendingDeletion?

    init(seriesId: String, seriesTitle: String, environment: AppEnvironment, onVolumesChanged: @escaping () -> Void) {
        self.seriesId = seriesId; self.seriesTitle = seriesTitle
        self.environment = environment; self.onVolumesChanged = onVolumesChanged
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { loadTask?.cancel(); pendingDeletion?.timer.invalidate() }

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = Palette.card
        let handleHost = UIView(), handle = UIView()
        handle.backgroundColor = Palette.border; handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false; handleHost.addSubview(handle)
        NSLayoutConstraint.activate([
            handleHost.heightAnchor.constraint(equalToConstant: 24),
            handle.centerXAnchor.constraint(equalTo: handleHost.centerXAnchor), handle.centerYAnchor.constraint(equalTo: handleHost.centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: 32), handle.heightAnchor.constraint(equalToConstant: 4)
        ])
        handleHost.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleHeight)))
        handleHost.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHeader(_:))))
        let heading = UILabel(); heading.text = "管理分卷"; heading.font = .boldSystemFont(ofSize: 17); heading.textColor = Palette.text
        countLabel.font = .systemFont(ofSize: 11); countLabel.textColor = Palette.text3; countLabel.accessibilityIdentifier = "volumes.count"
        var configuration = UIButton.Configuration.plain()
        configuration.title = "添加分卷"; configuration.image = ParityIcon.plus.image(size: 16); configuration.imagePadding = 4
        configuration.baseForegroundColor = Palette.accent; configuration.background.backgroundColor = Palette.accentSoft
        configuration.background.cornerRadius = 14; configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes; updated.font = .boldSystemFont(ofSize: 12); return updated
        }
        appendButton.configuration = configuration; appendButton.accessibilityIdentifier = "volumes.append"
        appendButton.addTarget(self, action: #selector(openDocumentPicker), for: .touchUpInside)
        let close = UIButton(type: .system); close.setTitle("完成", for: .normal); close.tintColor = Palette.accent
        close.accessibilityIdentifier = "volumes.close"; close.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        let spacer = UIView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = UIStackView(arrangedSubviews: [heading, countLabel, spacer, appendButton, close]); header.alignment = .center; header.spacing = 8
        header.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        let subtitle = UILabel(); subtitle.text = "拖动右侧手柄排序；移除分卷仅清理 App 副本，原文件保留。"
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = Palette.text3; subtitle.numberOfLines = 0
        feedback.font = .systemFont(ofSize: 12); feedback.textColor = Palette.accent; feedback.numberOfLines = 0; feedback.accessibilityIdentifier = "volumes.feedback"
        cancelAppendButton.setTitle("取消追加", for: .normal); cancelAppendButton.tintColor = Palette.accent
        cancelAppendButton.accessibilityIdentifier = "volumes.append.cancel"; cancelAppendButton.isHidden = true
        cancelAppendButton.addTarget(self, action: #selector(cancelAppend), for: .touchUpInside)
        let feedbackRow = UIStackView(arrangedSubviews: [feedback, cancelAppendButton]); feedbackRow.alignment = .center; feedbackRow.spacing = 8
        tableView.dataSource = self; tableView.delegate = self; tableView.backgroundColor = .clear
        tableView.separatorStyle = .none; tableView.rowHeight = 66; tableView.setEditing(true, animated: false)
        tableView.accessibilityIdentifier = "volumes.list"; tableView.register(VolumeRowCell.self, forCellReuseIdentifier: "volume")
        undoLabel.font = .boldSystemFont(ofSize: 12); undoLabel.textColor = Palette.text; undoLabel.lineBreakMode = .byTruncatingTail
        undoButton.setTitle("撤销", for: .normal); undoButton.tintColor = Palette.accent; undoButton.accessibilityIdentifier = "volumes.undo"
        undoButton.addTarget(self, action: #selector(undoDeleteTapped), for: .touchUpInside)
        undoContainer.addArrangedSubview(undoLabel); undoContainer.addArrangedSubview(undoButton)
        undoContainer.alignment = .center; undoContainer.spacing = 12; undoContainer.isHidden = true
        undoContainer.backgroundColor = Palette.surface; undoContainer.layer.cornerRadius = 10
        undoContainer.isLayoutMarginsRelativeArrangement = true; undoContainer.layoutMargins = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        let stack = UIStackView(arrangedSubviews: [handleHost, header, subtitle, feedbackRow, tableView, undoContainer])
        stack.axis = .vertical; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor), stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        loadVolumes()
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); updateHeight() }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator); coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.updateHeight() }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true { loadGeneration = UUID(); loadTask?.cancel(); appendTask?.cancel(); commitPendingDeletion() }
    }
    private func updateHeight() {
        let height = navigationController?.presentingViewController?.view.bounds.height ?? UIScreen.main.bounds.height
        navigationController?.preferredContentSize.height = height * (expanded ? 0.92 : 0.72)
    }
    @objc private func toggleHeight() { expanded.toggle(); updateHeight() }
    @objc private func dragHeader(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let delta = gesture.translation(in: view).y
        if delta > 60 { dismissSelf() } else if delta < -30 { expanded = true; updateHeight() }
    }
    private func setBusy(_ value: Bool, message: String? = nil) {
        busy = value; tableView.isUserInteractionEnabled = !value; appendButton.isEnabled = !value
        if let message { feedback.text = message }
        if !value { tableView.reloadData() }
    }
    private func refreshRows() { countLabel.text = "共 \(volumes.count) 卷"; tableView.reloadData() }
    private func loadVolumes(completionMessage: String? = nil) {
        loadTask?.cancel(); let token = UUID(); loadGeneration = token; setBusy(true, message: "正在读取分卷…")
        let library = environment.localLibrary, id = seriesId
        let worker = Task.detached(priority: .userInitiated) { () async throws -> (LocalSeriesRecord?, [LocalBook]) in
            let series = try await library.series(id: id); try Task.checkCancellation()
            return (series, try series.map { try library.volumes(for: $0) } ?? [])
        }
        loadTask = Task { [weak self] in
            do {
                let (series, loaded) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, self.loadGeneration == token, !Task.isCancelled else { return }
                if let series { self.seriesTitle = series.displayTitle }
                self.volumes = loaded; self.refreshRows(); self.setBusy(false, message: completionMessage ?? (loaded.isEmpty ? "暂无分卷" : ""))
            } catch {
                guard let self, self.loadGeneration == token, !Task.isCancelled else { return }
                self.setBusy(false, message: "分卷读取失败"); self.showVolumeError(error, retry: { [weak self] in self?.loadVolumes() })
            }
        }
    }
    @objc private func dismissSelf() { commitPendingDeletion(); dismiss(animated: true, completion: onVolumesChanged) }
    private func commitPendingDeletion(onSuccess: (() -> Void)? = nil) {
        guard let pending = pendingDeletion else { return }
        pending.timer.invalidate(); pendingDeletion = nil; undoContainer.isHidden = true; setBusy(true, message: "正在保存…")
        let library = environment.localLibrary, seriesID = seriesId, changed = onVolumesChanged
        // Retain the owner independently of the sheet: a confirmed deletion
        // must finish even when the sheet is dismissed before this task starts.
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) { try await library.deleteVolume(seriesId: seriesID, volumeId: pending.volume.id) }.value
                changed(); guard let self else { return }
                self.setBusy(false, message: "分卷已移除，原文件保留")
                if self.volumes.isEmpty { self.dismiss(animated: true) } else { onSuccess?() }
            } catch {
                ErrorLogStore.shared.append(title: "分卷移除失败", error: error); changed()
                guard let self else { return }; self.setBusy(false); self.loadVolumes()
                self.showVolumeError(error, retry: { [weak self] in self?.removeVolume(id: pending.volume.id) })
            }
        }
    }
    private func removeVolume(id: String) {
        guard !busy, let index = volumes.firstIndex(where: { $0.id == id }) else { return }
        if pendingDeletion != nil { commitPendingDeletion(onSuccess: { [weak self] in self?.removeVolume(id: id) }); return }
        let volume = volumes.remove(at: index); undoLabel.text = "已移出《\(volume.title)》"; undoContainer.isHidden = false
        let timer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.commitPendingDeletion() } }
        pendingDeletion = PendingDeletion(volume: volume, index: index, timer: timer); refreshRows()
    }
    @objc private func undoDeleteTapped() {
        guard let pending = pendingDeletion else { return }; pending.timer.invalidate(); pendingDeletion = nil; undoContainer.isHidden = true
        volumes.insert(pending.volume, at: min(pending.index, volumes.count)); refreshRows(); feedback.text = "已撤销移除"
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { volumes.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "volume", for: indexPath) as! VolumeRowCell, volume = volumes[indexPath.row]
        cell.configure(volume, index: indexPath.row); cell.remove = { [weak self] in self?.removeVolume(id: volume.id) }; return cell
    }
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { !busy && pendingDeletion == nil }
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard sourceIndexPath.row != destinationIndexPath.row, !busy, pendingDeletion == nil else { refreshRows(); return }
        let previous = volumes; volumes.insert(volumes.remove(at: sourceIndexPath.row), at: destinationIndexPath.row)
        let ids = volumes.map(\.id), library = environment.localLibrary, seriesID = seriesId, changed = onVolumesChanged
        setBusy(true, message: "正在保存顺序…")
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) { try await library.reorderVolumes(seriesId: seriesID, newVolumeIDs: ids) }.value
                changed(); guard let self else { return }; self.refreshRows(); self.setBusy(false, message: "分卷顺序已保存")
            } catch {
                guard let self else { return }; self.volumes = previous; self.refreshRows(); self.setBusy(false, message: "顺序未保存，原顺序已恢复")
                self.showVolumeError(error, retry: { [weak self] in self?.loadVolumes() })
            }
        }
    }
    @objc private func openDocumentPicker() {
        guard !busy else { return }
        if pendingDeletion != nil { commitPendingDeletion(onSuccess: { [weak self] in self?.openDocumentPicker() }); return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .epub, .pdf, .folder, .image, .data], asCopy: false)
        picker.allowsMultipleSelection = true; picker.delegate = self; present(picker, animated: true)
    }
    @objc private func cancelAppend() { appendTask?.cancel(); feedback.text = "正在停止追加…"; cancelAppendButton.isEnabled = false }
    private func showVolumeError(_ error: Error, retry: @escaping () -> Void) {
        guard view.window != nil, presentedViewController == nil else { return }
        let alert = UIAlertController(title: "操作失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重试", style: .default) { _ in retry() }); alert.addAction(UIAlertAction(title: "取消", style: .cancel)); present(alert, animated: true)
    }
}

extension VolumeManagerViewController: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { feedback.text = "已取消选择，分卷未改变" }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty, !busy else { return }; setBusy(true, message: "正在追加分卷…")
        cancelAppendButton.isHidden = false; cancelAppendButton.isEnabled = true
        let library = environment.localLibrary, id = seriesId, title = seriesTitle, changed = onVolumesChanged
        appendTask = Task { [weak self] in
            defer { self?.appendTask = nil; self?.cancelAppendButton.isHidden = true }
            do {
                let operation = Task.detached(priority: .userInitiated) {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--volume-append-held-until-cancel") {
                        // Hold only work scheduling. The real selection, cancel
                        // propagation and unchanged owned library are still used.
                        while true { try await Task.sleep(nanoseconds: 50_000_000) }
                    }
                    #endif
                    try Task.checkCancellation()
                    let session = try BatchImportSession(file: library.directory.appendingPathComponent("batch_import_session.json"))
                    let worker = BatchImportWorker(library: library, session: session, isReadableImage: LocalImageProbe.isReadable,
                        inspectPdf: PdfRenderer.inspect, renderPdfCover: { try PdfRenderer.render($0, pageIndex: 0, maximumDimension: 720, quality: 0.85) })
                    return try await worker.appendVolumes(urls: urls, toSeriesId: id, seriesTitle: title)
                }
                let summary = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
                changed(); guard let self else { return }
                self.loadVolumes(completionMessage: summary.cancelled ? "已取消追加，已完成分卷保留" : "追加完成：\(summary.succeededCount) 卷成功，\(summary.skippedCount) 卷重复跳过")
                if summary.failedCount > 0 {
                    let alert = UIAlertController(title: "追加结果", message: "成功 \(summary.succeededCount) 卷，失败 \(summary.failedCount) 卷。失败项可重新选择文件，已完成分卷不会重复追加。", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "选择文件重试", style: .default) { [weak self] _ in self?.openDocumentPicker() })
                    alert.addAction(UIAlertAction(title: "稍后", style: .cancel)); self.present(alert, animated: true)
                }
            } catch is CancellationError {
                changed(); self?.loadVolumes(completionMessage: "已取消追加，现有分卷保留")
            } catch {
                ErrorLogStore.shared.append(title: "分卷追加失败", error: error); changed()
                guard let self else { return }; self.setBusy(false, message: "追加未完成，现有分卷保留")
                self.showVolumeError(error, retry: { [weak self] in self?.openDocumentPicker() })
            }
        }
    }
}

@MainActor
private final class VolumeRowCell: UITableViewCell {
    var remove: (() -> Void)?
    private let card = UIView()
    private let badge = UILabel(), titleLabel = UILabel(), formatLabel = UILabel(), deleteButton = UIButton(type: .system)
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier); backgroundColor = .clear; selectionStyle = .none; showsReorderControl = true
        card.backgroundColor = Palette.surface; card.layer.cornerRadius = 10; card.layer.borderWidth = 1; card.layer.borderColor = Palette.border.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(card)
        badge.font = .boldSystemFont(ofSize: 11); badge.textColor = Palette.text3; badge.textAlignment = .center; badge.backgroundColor = Palette.cardSoft; badge.layer.cornerRadius = 11; badge.clipsToBounds = true
        titleLabel.font = .systemFont(ofSize: 13); titleLabel.textColor = Palette.text; titleLabel.numberOfLines = 2
        formatLabel.font = .systemFont(ofSize: 11); formatLabel.textColor = Palette.text3
        let titles = UIStackView(arrangedSubviews: [titleLabel, formatLabel]); titles.axis = .vertical; titles.spacing = 2
        deleteButton.setImage(ParityIcon.trash.image(size: 20), for: .normal); deleteButton.tintColor = Palette.danger; deleteButton.backgroundColor = Palette.cardSoft; deleteButton.layer.cornerRadius = 16
        deleteButton.addAction(UIAction { [weak self] _ in self?.remove?() }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [badge, titles, deleteButton]); row.spacing = 10; row.alignment = .center; row.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(row)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4), card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12), row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8), row.topAnchor.constraint(equalTo: card.topAnchor, constant: 6), row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
            badge.widthAnchor.constraint(equalToConstant: 22), badge.heightAnchor.constraint(equalToConstant: 22), deleteButton.widthAnchor.constraint(equalToConstant: 32), deleteButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        card.layer.borderColor = Palette.border.cgColor
    }
    func configure(_ volume: LocalBook, index: Int) {
        badge.text = String(index + 1); titleLabel.text = volume.title
        let format = volume.epub != nil ? "EPUB" : (volume.pdf != nil ? "PDF" : (volume.importFormat == .zip || volume.importFormat == .cbz ? "ZIP" : "图片"))
        formatLabel.text = "\(volume.pages.count) 页 · \(format)"; accessibilityIdentifier = "volume.row." + volume.id; accessibilityLabel = volume.title; accessibilityValue = "第 \(index + 1) 卷；\(volume.pages.count) 页；\(format)"
        deleteButton.accessibilityIdentifier = "volume.remove." + volume.id; deleteButton.accessibilityLabel = "移除 " + volume.title
    }
}
