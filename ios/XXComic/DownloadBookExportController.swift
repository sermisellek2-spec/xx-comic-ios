import UIKit
import Photos
import UniformTypeIdentifiers
import ComicCore

/// Export sheet for completed offline chapters, porting Android's `DownloadBookDrawer`
/// export flow + `DownloadImageExporter` integration (Files folder, Photos, and System Share).
@MainActor
final class DownloadBookExportController: UIViewController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    private enum ExportTarget {
        case filesFolder
        case photosLibrary
        case systemShare
    }

    private let environment: AppEnvironment
    private let bookId: String
    private let initialChapterIds: Set<String>

    private var bookTitle = "离线漫画"
    private var exportableTasks: [DownloadTask] = []
    private var selectedFormat: DownloadImageExporter.Format
    private var exportTask: Task<Void, Never>?
    private var activeTempExportDir: URL?
    private var isExporting = false

    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private lazy var gridView: ChapterSelectionGridView = ChapterSelectionGridView(compact: true) { [weak self] in
        self?.updateSelectionSummary()
    }
    private let formatHeadingRow = UIStackView()
    private let formatDescLabel = UILabel()
    private let formatChipsStack = UIStackView()
    private var formatButtons: [(format: DownloadImageExporter.Format, button: UIButton)] = []
    private let webpFallbackNoteLabel = UILabel()

    private let selectedInfoLabel = UILabel()
    private let primaryExportButton = UIButton(type: .system)
    private let photosButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)

    private weak var progressAlert: UIAlertController?
    private var folderPicker: UIDocumentPickerViewController?

    static func present(
        from presenter: UIViewController,
        environment: AppEnvironment,
        bookId: String,
        initialChapterIds: [String]? = nil
    ) {
        let controller = DownloadBookExportController(
            environment: environment,
            bookId: bookId,
            initialChapterIds: initialChapterIds
        )
        let nav = UINavigationController(rootViewController: controller)
        if let sheet = nav.sheetPresentationController {
            if #available(iOS 16.0, *) {
                sheet.detents = [
                    .custom(identifier: .init("exportDrawer")) { $0.maximumDetentValue * 0.88 },
                    .large()
                ]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 18
        }
        presenter.present(nav, animated: true)
    }

    init(
        environment: AppEnvironment,
        bookId: String,
        initialChapterIds: [String]? = nil
    ) {
        self.environment = environment
        self.bookId = bookId
        self.initialChapterIds = Set(initialChapterIds ?? [])
        self.selectedFormat = DownloadImageExporter.loadPreferredFormat(defaults: environment.defaults)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    deinit {
        exportTask?.cancel()
        if let tempDir = activeTempExportDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.card
        loadExportableChapters()
        setupHeader()
        setupLayout()
        syncChapterGrid()
        updateFormatUI()
        updateSelectionSummary()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            exportTask?.cancel()
            cleanupTempExportDir()
        }
    }

    private func loadExportableChapters() {
        let runtime = environment.downloadRuntime
        let snapshot = runtime.store.snapshot(id: bookId)
        let tasks = runtime.store.list()
            .filter { $0.bookId == bookId && !$0.isFileTask && $0.state == .completed }
            .sorted { $0.order < $1.order }
        exportableTasks = tasks
        bookTitle = snapshot?.summary.title ?? tasks.first?.title ?? "离线漫画"
    }

    private func setupHeader() {
        SecondaryHeaderBar.apply(to: self, title: "导出离线图片", meta: bookTitle)
        navigationItem.rightBarButtonItem = SecondaryHeaderBar.iconButton(
            icon: .close,
            accessibilityLabel: "关闭导出",
            accessibilityIdentifier: "export.close",
            target: self,
            action: #selector(closeTapped)
        )
    }

    private func setupLayout() {
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = Palette.text2
        statusLabel.numberOfLines = 2
        statusLabel.accessibilityIdentifier = "export.status"
        statusLabel.text = exportableTasks.isEmpty
            ? "\(bookTitle) · 暂无可导出章节"
            : "\(bookTitle) · \(exportableTasks.count) 章可导出"

        progressView.progressTintColor = Palette.accent
        progressView.trackTintColor = Palette.borderSoft
        progressView.isHidden = true
        progressView.progress = 0

        gridView.accessibilityIdentifier = "export.chapters.grid"
        gridView.translatesAutoresizingMaskIntoConstraints = false

        let formatSection = buildFormatSection()

        let divider = UIView()
        divider.backgroundColor = Palette.borderSoft
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true

        selectedInfoLabel.font = .systemFont(ofSize: 12)
        selectedInfoLabel.textColor = Palette.text3
        selectedInfoLabel.accessibilityIdentifier = "export.selected.info"

        primaryExportButton.setTitle("导出到文件夹", for: .normal)
        primaryExportButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        primaryExportButton.setTitleColor(Palette.onAccent, for: .normal)
        primaryExportButton.backgroundColor = Palette.accent
        primaryExportButton.layer.cornerRadius = 10
        primaryExportButton.accessibilityIdentifier = "export.target.files"
        primaryExportButton.addTarget(self, action: #selector(exportToFilesTapped), for: .touchUpInside)

        photosButton.setTitle("保存到相册", for: .normal)
        photosButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        photosButton.setTitleColor(Palette.accentText, for: .normal)
        photosButton.backgroundColor = Palette.accentSoft
        photosButton.layer.cornerRadius = 8
        photosButton.layer.borderWidth = 1
        photosButton.layer.borderColor = Palette.borderSoft.cgColor
        photosButton.accessibilityIdentifier = "export.target.photos"
        photosButton.addTarget(self, action: #selector(exportToPhotosTapped), for: .touchUpInside)

        shareButton.setTitle("系统分享", for: .normal)
        shareButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        shareButton.setTitleColor(Palette.accentText, for: .normal)
        shareButton.backgroundColor = Palette.accentSoft
        shareButton.layer.cornerRadius = 8
        shareButton.layer.borderWidth = 1
        shareButton.layer.borderColor = Palette.borderSoft.cgColor
        shareButton.accessibilityIdentifier = "export.target.share"
        shareButton.addTarget(self, action: #selector(exportToShareTapped), for: .touchUpInside)

        let secondaryRow = UIStackView(arrangedSubviews: [photosButton, shareButton])
        secondaryRow.axis = .horizontal
        secondaryRow.spacing = 8
        secondaryRow.distribution = .fillEqually

        let footerStack = UIStackView(arrangedSubviews: [selectedInfoLabel, primaryExportButton, secondaryRow])
        footerStack.axis = .vertical
        footerStack.spacing = 8

        let rootStack = UIStackView(arrangedSubviews: [
            statusLabel,
            progressView,
            gridView,
            formatSection,
            divider,
            footerStack
        ])
        rootStack.axis = .vertical
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            primaryExportButton.heightAnchor.constraint(equalToConstant: 44),
            photosButton.heightAnchor.constraint(equalToConstant: 40),
            shareButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func buildFormatSection() -> UIView {
        let wrap = UIStackView()
        wrap.axis = .vertical
        wrap.spacing = 6

        let heading = UILabel()
        heading.text = "导出格式"
        heading.font = .systemFont(ofSize: 12, weight: .bold)
        heading.textColor = Palette.text2
        heading.setContentHuggingPriority(.required, for: .horizontal)

        formatDescLabel.font = .systemFont(ofSize: 11)
        formatDescLabel.textColor = Palette.text3
        formatDescLabel.lineBreakMode = .byTruncatingTail

        formatHeadingRow.axis = .horizontal
        formatHeadingRow.spacing = 8
        formatHeadingRow.alignment = .center
        formatHeadingRow.addArrangedSubview(heading)
        formatHeadingRow.addArrangedSubview(formatDescLabel)
        wrap.addArrangedSubview(formatHeadingRow)

        formatChipsStack.axis = .horizontal
        formatChipsStack.spacing = 6
        formatChipsStack.distribution = .fillEqually
        formatButtons.removeAll()

        for fmt in DownloadImageExporter.Format.allCases {
            let btn = UIButton(type: .system)
            let shortTitle: String
            switch fmt {
            case .jpg: shortTitle = "JPG"
            case .png: shortTitle = "PNG"
            case .webp: shortTitle = "WebP"
            case .original: shortTitle = "原图格式"
            }
            btn.setTitle(shortTitle, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.titleLabel?.adjustsFontSizeToFitWidth = true
            btn.titleLabel?.minimumScaleFactor = 0.8
            btn.layer.cornerRadius = 8
            btn.layer.borderWidth = 1
            btn.accessibilityIdentifier = "export.format.\(fmt.id)"
            btn.accessibilityLabel = "\(fmt.label)，\(fmt.description)"
            btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
            btn.addAction(UIAction { [weak self] _ in
                guard let self, !self.isExporting else { return }
                self.selectedFormat = fmt
                DownloadImageExporter.savePreferredFormat(fmt, defaults: self.environment.defaults)
                self.updateFormatUI()
            }, for: .touchUpInside)
            formatButtons.append((fmt, btn))
            formatChipsStack.addArrangedSubview(btn)
        }
        wrap.addArrangedSubview(formatChipsStack)

        webpFallbackNoteLabel.font = .systemFont(ofSize: 11)
        webpFallbackNoteLabel.textColor = Palette.text3
        webpFallbackNoteLabel.numberOfLines = 0
        webpFallbackNoteLabel.text = "说明：当前 iOS 系统不支持原生 WebP 编码，选择 WebP 时将自动无损保存为 PNG（.png 后缀，不会误标为 .webp）；原有离线副本保持不变。"
        webpFallbackNoteLabel.accessibilityIdentifier = "export.webp.note"
        wrap.addArrangedSubview(webpFallbackNoteLabel)

        return wrap
    }

    private func syncChapterGrid() {
        let items = exportableTasks.map { task -> ChapterSelectionGridView.Item in
            let subtitle = "\(task.donePages) 页 · \(StorageCalculator.formatBytes(task.bytes))"
            return ChapterSelectionGridView.Item(
                id: task.id,
                title: DetailChapterSection.cleanChapterTitle(chapter: Chapter(chapterId: task.chapterId, title: task.title, url: task.url), index: task.order),
                subtitle: subtitle,
                fullTitle: task.title,
                selectable: true,
                isDownloaded: false
            )
        }
        let preselected: Set<String>
        if !initialChapterIds.isEmpty {
            let valid = Set(items.map(\.id))
            let matched = initialChapterIds.intersection(valid)
            preselected = matched.isEmpty ? valid : matched
        } else {
            preselected = Set(items.map(\.id))
        }
        gridView.setItems(items, selected: preselected)
    }

    private func updateFormatUI() {
        formatDescLabel.text = "\(selectedFormat.label) · \(selectedFormat.description)"
        for (fmt, btn) in formatButtons {
            let selected = fmt == selectedFormat
            btn.isEnabled = !isExporting
            btn.alpha = isExporting ? (selected ? 0.85 : 0.45) : 1.0
            btn.backgroundColor = selected ? Palette.accent : Palette.surface
            btn.setTitleColor(selected ? Palette.onAccent : Palette.text, for: .normal)
            btn.layer.borderColor = (selected ? Palette.accent : Palette.border).cgColor
        }
        let showWebpNote = (selectedFormat == .webp) && !DownloadImageExporter.isWebPEncodeSupported()
        webpFallbackNoteLabel.isHidden = !showWebpNote
    }

    private func updateSelectionSummary() {
        let selectedIds = gridView.selectedIds()
        let selectedTasks = exportableTasks.filter { selectedIds.contains($0.id) }
        let pages = selectedTasks.reduce(0) { $0 + max(0, $1.donePages) }
        selectedInfoLabel.text = "已选 \(selectedTasks.count) 章 · \(pages) 页"

        let enabled = !selectedTasks.isEmpty && !isExporting
        for btn in [primaryExportButton, photosButton, shareButton] {
            btn.isEnabled = enabled
            btn.alpha = enabled ? 1.0 : 0.45
        }
        if isExporting {
            primaryExportButton.setTitle("正在导出…", for: .normal)
        } else {
            primaryExportButton.setTitle("选择保存目录并导出", for: .normal)
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        if isExporting {
            cancelActiveExport()
            return
        }
        dismiss(animated: true)
    }

    @objc private func exportToFilesTapped() {
        guard !isExporting, !gridView.selectedIds().isEmpty else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        folderPicker = picker
        present(picker, animated: true)
        picker.presentationController?.delegate = self
    }

    @objc private func exportToPhotosTapped() {
        guard !isExporting, !gridView.selectedIds().isEmpty else { return }
        let ids = Array(gridView.selectedIds())
        let format = selectedFormat
        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                let alert = UIAlertController(
                    title: "需要相册写入权限",
                    message: "请在系统设置中允许访问“仅添加照片”，以便将导出的漫画图片保存到相册。",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "知道了", style: .default))
                self.present(alert, animated: true)
                return
            }
            self.startExport(chapterIds: ids, format: format, target: .photosLibrary, destinationFolderURL: nil)
        }
    }

    @objc private func exportToShareTapped() {
        guard !isExporting, !gridView.selectedIds().isEmpty else { return }
        let ids = Array(gridView.selectedIds())
        startExport(chapterIds: ids, format: selectedFormat, target: .systemShare, destinationFolderURL: nil)
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        folderPicker = nil
        guard let folderURL = urls.first else { return }
        let ids = Array(gridView.selectedIds())
        guard !ids.isEmpty else { return }
        startExport(chapterIds: ids, format: selectedFormat, target: .filesFolder, destinationFolderURL: folderURL)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        folderPicker = nil
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if presentationController.presentedViewController === folderPicker {
            folderPicker = nil
        }
    }

    // MARK: - Export Pipeline

    private func startExport(
        chapterIds: [String],
        format: DownloadImageExporter.Format,
        target: ExportTarget,
        destinationFolderURL: URL?
    ) {
        guard !isExporting else { return }
        isExporting = true
        gridView.setInteractionEnabled(false)
        progressView.isHidden = false
        progressView.progress = 0
        statusLabel.text = "正在准备导出 \(chapterIds.count) 章…"
        updateFormatUI()
        updateSelectionSummary()
        presentProgressAlert(totalChapters: chapterIds.count)

        let runtime = environment.downloadRuntime
        let targetBookId = bookId
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XXComicExport-\(UUID().uuidString)", isDirectory: true)
        cleanupTempExportDir()
        activeTempExportDir = stagingDir

        exportTask = Task { [weak self] in
            guard let self else { return }
            var finalResult: DownloadImageExporter.ExportResult?
            var finalError: Error?
            var shareItems: [URL] = []

            do {
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                let stagedResult = try await DownloadImageExporter.export(
                    runtime: runtime,
                    bookId: targetBookId,
                    chapterIds: chapterIds,
                    format: format,
                    destinationDirectory: stagingDir
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.isExporting else { return }
                        let safeTotal = max(1, progress.totalPages)
                        let ratio = Float(progress.donePages) / Float(safeTotal)
                        let pct = min(100, Int((ratio * 100).rounded()))
                        self.progressView.progress = ratio
                        let msg = "正在导出 \(progress.donePages) / \(progress.totalPages) 页 (\(pct)%) · \(progress.currentChapterTitle)"
                        self.statusLabel.text = msg
                        self.progressAlert?.message = msg
                    }
                }

                if stagedResult.cancelled {
                    finalResult = stagedResult
                } else {
                    switch target {
                    case .filesFolder:
                        guard let destinationFolderURL else {
                            throw DownloadError.corruptedData("未选择保存文件夹")
                        }
                        try await self.publishStagingDirectory(stagingDir, toSecurityScopedFolder: destinationFolderURL)
                        finalResult = DownloadImageExporter.ExportResult(
                            totalChapters: stagedResult.totalChapters,
                            exportedChapters: stagedResult.exportedChapters,
                            totalPages: stagedResult.totalPages,
                            exportedPages: stagedResult.exportedPages,
                            skippedPages: stagedResult.skippedPages,
                            cancelled: stagedResult.cancelled,
                            folderDisplayName: destinationFolderURL.lastPathComponent,
                            lastError: stagedResult.lastError,
                            fallbackReason: stagedResult.fallbackReason
                        )
                    case .photosLibrary:
                        let imageFiles = Self.collectExportedImageFiles(under: stagingDir)
                        var savedCount = 0
                        var skippedByPhotos = 0
                        var lastPhotosError = stagedResult.lastError
                        for fileURL in imageFiles {
                            if Task.isCancelled {
                                throw CancellationError()
                            }
                            do {
                                try await Self.saveImageFileToPhotos(fileURL)
                                savedCount += 1
                            } catch {
                                skippedByPhotos += 1
                                lastPhotosError = error.localizedDescription
                            }
                        }
                        finalResult = DownloadImageExporter.ExportResult(
                            totalChapters: stagedResult.totalChapters,
                            exportedChapters: stagedResult.exportedChapters,
                            totalPages: stagedResult.totalPages,
                            exportedPages: savedCount,
                            skippedPages: stagedResult.skippedPages + skippedByPhotos,
                            cancelled: false,
                            folderDisplayName: "系统相册",
                            lastError: lastPhotosError,
                            fallbackReason: stagedResult.fallbackReason
                        )
                    case .systemShare:
                        let imageFiles = Self.collectExportedImageFiles(under: stagingDir)
                        let bookFolders = (try? FileManager.default.contentsOfDirectory(
                            at: stagingDir,
                            includingPropertiesForKeys: nil,
                            options: [.skipsHiddenFiles]
                        )) ?? []
                        if imageFiles.count <= 30 && !imageFiles.isEmpty {
                            shareItems = imageFiles
                        } else if let firstBookDir = bookFolders.first {
                            shareItems = [firstBookDir]
                        } else {
                            shareItems = imageFiles
                        }
                        finalResult = stagedResult
                    }
                }
            } catch is CancellationError {
                finalResult = DownloadImageExporter.ExportResult(
                    totalChapters: chapterIds.count,
                    exportedChapters: 0,
                    totalPages: 0,
                    exportedPages: 0,
                    skippedPages: 0,
                    cancelled: true,
                    folderDisplayName: destinationFolderURL?.lastPathComponent ?? "",
                    lastError: ""
                )
            } catch {
                finalError = error
            }

            let preserveTempForShare = (target == .systemShare && finalError == nil && finalResult?.cancelled == false && !shareItems.isEmpty)
            if !preserveTempForShare {
                self.cleanupTempExportDir()
            }

            await self.finishExportUI(
                format: format,
                target: target,
                result: finalResult,
                error: finalError,
                shareItems: shareItems
            )
        }
    }

    private func presentProgressAlert(totalChapters: Int) {
        let alert = UIAlertController(
            title: "正在导出图片",
            message: "准备导出 \(totalChapters) 章，原有离线副本保留不变…",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "停止导出", style: .cancel) { [weak self] _ in
            self?.cancelActiveExport()
        })
        progressAlert = alert
        present(alert, animated: true)
    }

    private func cancelActiveExport() {
        exportTask?.cancel()
        statusLabel.text = "正在停止导出，请稍候…"
    }

    private func finishExportUI(
        format: DownloadImageExporter.Format,
        target: ExportTarget,
        result: DownloadImageExporter.ExportResult?,
        error: Error?,
        shareItems: [URL]
    ) async {
        isExporting = false
        exportTask = nil
        gridView.setInteractionEnabled(true)
        progressView.isHidden = true
        statusLabel.text = "\(bookTitle) · \(exportableTasks.count) 章可导出"
        updateFormatUI()
        updateSelectionSummary()

        if let alert = progressAlert, alert.presentingViewController != nil {
            await withCheckedContinuation { cont in
                alert.dismiss(animated: true) { cont.resume() }
            }
        }
        progressAlert = nil

        if target == .systemShare, error == nil, result?.cancelled == false, !shareItems.isEmpty {
            let activity = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
            activity.completionWithItemsHandler = { [weak self] _, completed, _, actError in
                self?.cleanupTempExportDir()
                guard let self, self.viewIfLoaded?.window != nil else { return }
                if let actError {
                    self.presentOutcomeAlert(format: format, result: nil, error: actError)
                } else if completed, let result {
                    self.presentOutcomeAlert(format: format, result: result, error: nil)
                }
            }
            if let popover = activity.popoverPresentationController {
                popover.sourceView = shareButton
                popover.sourceRect = shareButton.bounds
            }
            present(activity, animated: true)
            return
        }

        presentOutcomeAlert(format: format, result: result, error: error)
    }

    private func presentOutcomeAlert(
        format: DownloadImageExporter.Format,
        result: DownloadImageExporter.ExportResult?,
        error: Error?
    ) {
        guard viewIfLoaded?.window != nil else { return }
        let title: String
        var message: String
        if let error {
            title = "导出失败"
            message = error.localizedDescription
        } else if let result, result.cancelled {
            title = "导出已停止"
            message = "已停止导出并清理未完成的临时文件。\n\n原有离线下载副本已完整保留。"
        } else if let result {
            let effectiveLabel = result.fallbackReason.isEmpty ? format.label : "PNG (.png)"
            let destinationLabel = result.folderDisplayName.isEmpty ? "目标位置" : result.folderDisplayName
            if result.skippedPages > 0 {
                title = "导出完成（部分跳过）"
                message = "已导出 \(result.exportedChapters) 章共 \(result.exportedPages) 张图片（\(effectiveLabel)）至「\(destinationLabel)」，跳过 \(result.skippedPages) 张异常页。"
                if !result.lastError.isEmpty {
                    message += "\n原因：\(result.lastError)"
                }
            } else {
                title = "导出成功"
                message = "已导出 \(result.exportedChapters) 章共 \(result.exportedPages) 张图片（\(effectiveLabel)）至「\(destinationLabel)」。"
            }
            if !result.fallbackReason.isEmpty {
                message += "\n\n\(result.fallbackReason)"
            }
            message += "\n\n原有离线下载副本已保留。"
        } else {
            return
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func cleanupTempExportDir() {
        if let tempDir = activeTempExportDir {
            try? FileManager.default.removeItem(at: tempDir)
            activeTempExportDir = nil
        }
    }

    private func publishStagingDirectory(_ stagingDir: URL, toSecurityScopedFolder folderURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let accessed = folderURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { folderURL.stopAccessingSecurityScopedResource() }
            }
            let fm = FileManager.default
            let bookDirs = try fm.contentsOfDirectory(
                at: stagingDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for bookDir in bookDirs {
                try Task.checkCancellation()
                let targetBookDir = folderURL.appendingPathComponent(bookDir.lastPathComponent, isDirectory: true)
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var copyError: Error?
                coordinator.coordinate(writingItemAt: targetBookDir, options: .forMerging, error: &coordError) { coordinatedURL in
                    do {
                        try Self.mergeDirectoryContents(from: bookDir, to: coordinatedURL, fileManager: fm)
                    } catch {
                        copyError = error
                    }
                }
                if let coordError { throw coordError }
                if let copyError { throw copyError }
            }
        }.value
    }

    nonisolated private static func mergeDirectoryContents(from srcDir: URL, to dstDir: URL, fileManager fm: FileManager) throws {
        if !fm.fileExists(atPath: dstDir.path) {
            try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        }
        let items = try fm.contentsOfDirectory(
            at: srcDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for item in items {
            try Task.checkCancellation()
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let target = dstDir.appendingPathComponent(item.lastPathComponent, isDirectory: isDir)
            if isDir {
                try mergeDirectoryContents(from: item, to: target, fileManager: fm)
            } else {
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    nonisolated private static func collectExportedImageFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    nonisolated private static func saveImageFileToPhotos(_ fileURL: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
        }
    }
}
