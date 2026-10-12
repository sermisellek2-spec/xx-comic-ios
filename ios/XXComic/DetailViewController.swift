import UIKit
import ComicCore

@MainActor
final class DetailViewController: UIViewController {
    private let environment: AppEnvironment
    private var comic: ComicSummary
    private var source: any ComicSource
    private let cover = RemoteImageView()
    private let heading = UILabel()
    private let descriptionLabel = UILabel()
    private let metadataLabel = UILabel()
    private let tagsRow = UIStackView()
    private var heroHeight: NSLayoutConstraint!
    private var heroTopInset: NSLayoutConstraint!
    private let favorite = UIButton(type: .system)
    private let read = UIButton(type: .system)
    private let directory = UIButton(type: .system)
    private let directoryArrow = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)))
    private let downloadButton = UIButton(type: .system)
    private let sourceSwitchButton = UIButton(type: .system)
    private let manageVolumes = UIButton(type: .system)
    private let retry = UIButton(type: .system)
    private var cachedDetail: ComicDetail?
    private var detailTask: Task<Void, Never>?
    private var directoryTask: Task<[Chapter], Error>?
    private var cachedChapters: [Chapter]?
    private var detailLoaded = false
    private var directoryID = UUID()
    private var readTask: Task<Void, Never>?
    private var readID = UUID()
    private var downloadTask: Task<Void, Never>?
    private var downloadID = UUID()
    private var feedback = DetailFeedbackState()
    private var favoriteArtworkID = UUID()
    private var favoriteArtworkName: String?
    private var favoriteArtworkScale: CGFloat = 0
    private var resumeOnAppear: Bool

    init(comic: ComicSummary, environment: AppEnvironment, resumeOnAppear: Bool = false) {
        self.comic = comic; self.environment = environment
        self.resumeOnAppear = resumeOnAppear
        source = environment.source(for: comic)!
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { detailTask?.cancel(); directoryTask?.cancel(); readTask?.cancel(); downloadTask?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = source.name
        navigationItem.titleView = UIView(frame: .zero)
        let appearance = UINavigationBarAppearance(); appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance; navigationItem.scrollEdgeAppearance = appearance; navigationItem.compactAppearance = appearance
        view.backgroundColor = Palette.card
        let scroll = UIScrollView()
        scroll.contentInsetAdjustmentBehavior = .never
        let content = UIStackView()
        content.axis = .vertical; content.spacing = 0
        let body = UIStackView()
        body.axis = .vertical; body.spacing = 10
        body.isLayoutMarginsRelativeArrangement = true
        body.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        body.backgroundColor = Palette.card; body.layer.cornerRadius = 12
        body.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let titleRow = UIStackView(arrangedSubviews: [heading, downloadButton, sourceSwitchButton])
        titleRow.spacing = 8; titleRow.alignment = .center
        heading.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sourceSwitchButton.setContentHuggingPriority(.required, for: .horizontal)
        sourceSwitchButton.titleLabel?.font = .systemFont(ofSize: 12)
        sourceSwitchButton.titleLabel?.lineBreakMode = .byTruncatingTail
        sourceSwitchButton.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
        downloadButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let dot = UIView(); dot.backgroundColor = Palette.accent; dot.layer.cornerRadius = 3
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        metadataLabel.font = .systemFont(ofSize: 12); metadataLabel.textColor = Palette.text2
        metadataLabel.numberOfLines = 2; metadataLabel.accessibilityIdentifier = "detail.metadata"
        metadataLabel.text = "未知状态 · 未知作者"
        let metadata = UIStackView(arrangedSubviews: [dot, metadataLabel]); metadata.spacing = 7; metadata.alignment = .center
        tagsRow.spacing = 6; tagsRow.alignment = .leading; tagsRow.isHidden = true
        let actions = UIStackView(arrangedSubviews: [favorite, read])
        actions.axis = .horizontal; actions.spacing = 8
        actions.backgroundColor = Palette.card
        actions.isLayoutMarginsRelativeArrangement = true
        actions.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 10, right: 16)
        actions.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(content); view.addSubview(actions)
        favorite.widthAnchor.constraint(equalToConstant: 44).isActive = true
        favorite.accessibilityIdentifier = "detail.favorite"
        read.backgroundColor = Palette.accent
        read.setTitleColor(Palette.onAccent, for: .normal)
        read.layer.cornerRadius = 12
        read.titleLabel?.textAlignment = .center
        cover.contentMode = .scaleAspectFill; cover.clipsToBounds = true
        cover.accessibilityIdentifier = "detail.cover"; cover.isAccessibilityElement = true
        cover.accessibilityLabel = "封面"
        heroHeight = cover.heightAnchor.constraint(equalToConstant: 190)
        heroHeight.isActive = true
        heading.text = comic.title; heading.numberOfLines = 2
        heading.accessibilityIdentifier = "detail.title"
        read.accessibilityIdentifier = "detail.read"
        sourceSwitchButton.accessibilityIdentifier = "detail.switch-source"
        heading.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 20, weight: .bold)); heading.textColor = Palette.text
        descriptionLabel.numberOfLines = 0; descriptionLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13))
        descriptionLabel.text = "暂无简介"
        descriptionLabel.textColor = Palette.secondaryText
        heading.adjustsFontForContentSizeCategory = true; descriptionLabel.adjustsFontForContentSizeCategory = true
        favorite.addTarget(self, action: #selector(toggleFavorite), for: .touchUpInside)
        let longFav = UILongPressGestureRecognizer(target: self, action: #selector(favoriteLongPressed(_:)))
        favorite.addGestureRecognizer(longFav)
        read.addTarget(self, action: #selector(startReading), for: .touchUpInside)
        read.titleLabel?.numberOfLines = 2
        directory.accessibilityIdentifier = "detail.directory"
        directory.accessibilityLabel = "章节目录"
        directory.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        directory.addTarget(self, action: #selector(showDirectory), for: .touchUpInside)
        directoryArrow.translatesAutoresizingMaskIntoConstraints = false
        directoryArrow.isUserInteractionEnabled = false
        directoryArrow.contentMode = .scaleAspectFit
        directory.addSubview(directoryArrow)
        NSLayoutConstraint.activate([
            directoryArrow.trailingAnchor.constraint(equalTo: directory.trailingAnchor, constant: -12),
            directoryArrow.centerYAnchor.constraint(equalTo: directory.centerYAnchor),
            directoryArrow.widthAnchor.constraint(equalToConstant: 12), directoryArrow.heightAnchor.constraint(equalToConstant: 20)
        ])
        setDownloadButton(loading: false)
        downloadButton.accessibilityIdentifier = "detail.download"
        downloadButton.addTarget(self, action: #selector(openDownloadSelection), for: .touchUpInside)
        sourceSwitchButton.setTitle(source.name, for: .normal)
        sourceSwitchButton.accessibilityLabel = "切换站源，当前" + source.name
        var sourceConfiguration = UIButton.Configuration.plain()
        sourceConfiguration.title = source.name; sourceConfiguration.image = ParityIcon.swap.image(size: 20)
        sourceConfiguration.imagePlacement = .trailing; sourceConfiguration.imagePadding = 6
        sourceConfiguration.baseForegroundColor = Palette.accent
        sourceConfiguration.contentInsets = .zero
        sourceConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes; updated.font = .systemFont(ofSize: 12); return updated
        }
        sourceSwitchButton.configuration = sourceConfiguration
        sourceSwitchButton.tintColor = Palette.accent
        sourceSwitchButton.addTarget(self, action: #selector(openSourceSwitchSheet), for: .touchUpInside)
        retry.addTarget(self, action: #selector(retryDetail), for: .touchUpInside)
        retry.accessibilityIdentifier = "detail.feedback"
        retry.titleLabel?.numberOfLines = 0

        var items: [UIView] = [titleRow, metadata, tagsRow, descriptionLabel, directory]
        var buttons = [favorite, directory, read, retry]
        if comic.sourceId == "local" {
            sourceSwitchButton.isHidden = true; downloadButton.isHidden = true
            manageVolumes.setTitle("管理分卷", for: .normal)
            manageVolumes.accessibilityIdentifier = "detail.volumes"
            manageVolumes.addTarget(self, action: #selector(openVolumeManager), for: .touchUpInside)
            items.append(manageVolumes)
            buttons.append(manageVolumes)
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "管理", style: .plain, target: self, action: #selector(showLocalManagementMenu))
        } else {
            sourceSwitchButton.isHidden = false
            buttons.append(contentsOf: [sourceSwitchButton, downloadButton])
        }
        items.append(retry)
        let topInset = UIView(); topInset.backgroundColor = Palette.background
        heroTopInset = topInset.heightAnchor.constraint(equalToConstant: 0); heroTopInset.isActive = true
        content.addArrangedSubview(topInset); content.addArrangedSubview(cover); content.addArrangedSubview(body)
        content.setCustomSpacing(-12, after: cover)
        for item in items { body.addArrangedSubview(item) }
        let bodyFill = UIView(); bodyFill.setContentHuggingPriority(.defaultLow, for: .vertical)
        body.addArrangedSubview(bodyFill)
        for button in buttons {
            let height = button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            height.priority = .init(999); height.isActive = true
        }
        NSLayoutConstraint.activate([
            actions.leadingAnchor.constraint(equalTo: view.leadingAnchor), actions.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), actions.heightAnchor.constraint(equalToConstant: 62),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: actions.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        cover.loadCover(comic, referer: source.referer, library: environment.localLibrary)
        loadDetail()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let topInset = view.window?.safeAreaInsets.top ?? 0
        if heroTopInset.constant != topInset { heroTopInset.constant = topInset }
        let height: CGFloat = width > 900 ? 250 : (width > 600 ? 220 : 190)
        if heroHeight.constant != height { heroHeight.constant = height }
    }
    private func setDownloadButton(loading: Bool) {
        downloadButton.setTitle(nil, for: .normal)
        downloadButton.setImage(loading ? UIImage(systemName: "xmark.circle") : ParityIcon.download.image(), for: .normal)
        downloadButton.tintColor = Palette.accent
        downloadButton.accessibilityLabel = loading ? "正在加载目录 · 点击取消" : "下载章节"
    }
    private func updateDetailText(_ detail: ComicDetail) {
        metadataLabel.text = (detail.status.isEmpty ? "未知状态" : detail.status) + " · " + (detail.author.isEmpty ? "未知作者" : detail.author)
        descriptionLabel.text = detail.description.isEmpty ? "暂无简介" : detail.description
        tagsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tag in detail.summary.tags.prefix(5) {
            let label = DetailTagLabel(); label.text = tag
            label.font = .systemFont(ofSize: 12); label.textColor = Palette.text2
            label.backgroundColor = Palette.card; label.layer.cornerRadius = 14; label.clipsToBounds = true
            label.layer.borderWidth = 1 / UIScreen.main.scale; label.layer.borderColor = Palette.border.cgColor
            tagsRow.addArrangedSubview(label)
        }
        let spacer = UIView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); tagsRow.addArrangedSubview(spacer)
        tagsRow.isHidden = detail.summary.tags.isEmpty
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); updateButtons()
        if !detailLoaded && detailTask == nil { loadDetail() }
        if cover.needsReload { cover.loadCover(comic, referer: source.referer, library: environment.localLibrary) }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if resumeOnAppear {
            resumeOnAppear = false
            startReading()
        }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentedViewController == nil else { return }
        detailTask?.cancel(); detailTask = nil
        directoryID = UUID(); directoryTask?.cancel(); directoryTask = nil
        readID = UUID(); readTask?.cancel(); readTask = nil; read.isEnabled = true
        cancelDownloadSelection()
        cover.cancel()
        favoriteArtworkID = UUID(); favoriteArtworkName = nil
    }
    private func updateButtons() {
        let isFav = environment.library.entry(for: comic)?.isFavorite == true
        favorite.setTitle(nil, for: .normal)
        favorite.accessibilityLabel = isFav ? "取消收藏" : "收藏"
        updateFavoriteArtwork(isFavorite: isFav)
        let saved = environment.library.entry(for: comic)?.reading
        read.setTitle(nil, for: .normal)
        let title = saved.map { "继续阅读\n第 \($0.chapterIndex + 1) 话" } ?? "开始阅读"
        let text = NSMutableAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: saved == nil ? 15 : 13, weight: .semibold), .foregroundColor: Palette.onAccent])
        if let newline = title.firstIndex(of: "\n") {
            let start = title.distance(from: title.startIndex, to: newline) + 1
            text.addAttributes([.font: UIFont.systemFont(ofSize: 12), .foregroundColor: Palette.onAccent.withAlphaComponent(0.85)], range: NSRange(location: start, length: text.length - start))
        }
        read.setAttributedTitle(text, for: .normal)
        read.accessibilityLabel = saved.map { "继续阅读，第 \($0.chapterIndex + 1) 话" } ?? "开始阅读"
        updateDirectoryButton()
    }
    private func updateFavoriteArtwork(isFavorite: Bool) {
        let name = isFavorite ? "rem_in_bookshelf" : "rem_not_in_bookshelf"
        let scale = max(1, traitCollection.displayScale)
        guard favoriteArtworkName != name || favoriteArtworkScale != scale else { return }
        let token = UUID(); favoriteArtworkID = token
        favoriteArtworkName = name; favoriteArtworkScale = scale
        guard let image = UIImage(named: name) else { return }
        // The source artwork is 1254px. Decode off the UI thread at the
        // screen's pixel density, then retain a 44pt display size.
        image.prepareThumbnail(of: CGSize(width: 44 * scale, height: 44 * scale)) { [weak self] thumbnail in
            guard let cgImage = thumbnail?.cgImage else { return }
            let prepared = UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation).withRenderingMode(.alwaysOriginal)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.favoriteArtworkID == token else { return }
                self.favorite.setImage(prepared, for: .normal)
            }
        }
    }
    private func setReadStatus(_ text: String) {
        read.setAttributedTitle(nil, for: .normal); read.setTitle(text, for: .normal); read.accessibilityLabel = text
    }
    private func updateDirectoryButton() {
        let count = (cachedChapters ?? cachedDetail?.chapters ?? []).count
        let subtitle = count > 0 ? "\(count) 话 · 已缓存" : (detailLoaded ? "点击加载章节" : "正在加载…")
        var configuration = UIButton.Configuration.plain()
        var headingAttributes = AttributeContainer(); headingAttributes.font = .systemFont(ofSize: 14, weight: .bold); headingAttributes.foregroundColor = Palette.text
        var subtitleAttributes = AttributeContainer(); subtitleAttributes.font = .systemFont(ofSize: 11); subtitleAttributes.foregroundColor = Palette.text3
        configuration.attributedTitle = AttributedString("章节目录", attributes: headingAttributes)
        configuration.attributedSubtitle = AttributedString(subtitle, attributes: subtitleAttributes)
        configuration.titleAlignment = .leading; configuration.titlePadding = 3
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 36)
        configuration.background.backgroundColor = Palette.surface; configuration.background.cornerRadius = 8
        configuration.background.strokeColor = Palette.border; configuration.background.strokeWidth = 1 / UIScreen.main.scale
        configuration.baseForegroundColor = Palette.text3
        directory.configuration = configuration; directory.contentHorizontalAlignment = .leading
        directoryArrow.tintColor = Palette.text3
        directory.bringSubviewToFront(directoryArrow)
        directory.accessibilityValue = subtitle
    }
    private func updateFeedback() {
        retry.setTitle(feedback.message, for: .normal)
        retry.isHidden = feedback.message == nil
        retry.isEnabled = feedback.action != .none
    }
    @objc private func loadDetail() {
        detailTask?.cancel()
        feedback.setDetail("正在加载详情…")
        updateFeedback()
        let id = comic.comicId
        detailTask = Task { [weak self, source] in
            do {
                let detail: ComicDetail
                do {
                    detail = try await source.detail(comicId: id)
                } catch {
                    if let self,
                       let bookId = try? DownloadModels.bookId(source: self.comic.sourceId, comic: id),
                       let snapshot = self.environment.downloadStore.snapshot(id: bookId) {
                        detail = snapshot
                    } else {
                        throw error
                    }
                }
                try Task.checkCancellation()
                guard let self else { return }
                self.comic = detail.summary
                self.cachedDetail = detail
                self.detailLoaded = true
                self.heading.text = detail.summary.title
                self.updateDetailText(detail)
                self.cover.loadCover(detail.summary, referer: source.referer, library: self.environment.localLibrary)
                self.feedback.setDetail(nil)
                self.updateFeedback()
                self.updateButtons()
                let revision = FavoriteRevision.fromChapters(latestChapterName: detail.latestChapter, chapters: detail.chapters)
                self.environment.favoriteUpdateCoordinator.acknowledge(sourceId: detail.summary.sourceId, comicId: detail.summary.comicId, revision: revision)
            } catch {
                guard let self, !Task.isCancelled else { return }
                if !(error is CancellationError) {
                    ErrorLogStore.shared.append(title: "详情加载失败: \(self.comic.title)", error: error)
                }
                let needsVerification = (error as? Mh18SourceError) == .verificationRequired
                if (error as? LocalCatalogError) == .targetNotFound {
                    self.feedback.setDetail("书籍已删除 · 重新导入相同内容即可恢复")
                } else {
                    self.feedback.setDetail(needsVerification ? "需要验证 · 去验证" : (error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试", action: needsVerification ? .verifyDetail : .reloadDetail)
                }
                self.updateFeedback()
            }
        }
    }
    @objc private func retryDetail() {
        switch feedback.action {
        case .retryDownload: openDownloadSelection()
        case .verifyDetail:
            showSourceManagement(environment: environment) { [weak self] in self?.loadDetail() }
        case .reloadDetail: loadDetail()
        case .none: return
        }
    }
    @objc private func openDownloadSelection() {
        if downloadTask != nil { cancelDownloadSelection(); return }
        cancelPreparingRead()
        downloadID = UUID()
        let token = downloadID, target = comic, targetSource = source, cached = cachedDetail
        feedback.beginDownload(message: "正在加载目录…")
        setDownloadButton(loading: true)
        updateFeedback()
        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.downloadID == token {
                    self.downloadTask = nil
                    self.setDownloadButton(loading: false)
                }
            }
            do {
                let detail: ComicDetail
                if let cached { detail = cached }
                else { detail = try await targetSource.detail(comicId: target.comicId) }
                try Task.checkCancellation()
                guard self.downloadID == token else { return }
                let prepared = try await detail.ensuringChapters { [weak self] in
                    guard let self, self.downloadID == token else { throw CancellationError() }
                    return try await self.chapters()
                }
                try Task.checkCancellation()
                guard self.downloadID == token else { return }
                guard self.comic.sourceId == target.sourceId, self.comic.comicId == target.comicId,
                      self.viewIfLoaded?.window != nil, self.presentedViewController == nil else {
                    self.feedback.endDownload(); self.updateFeedback()
                    return
                }
                self.cachedDetail = prepared
                self.cachedChapters = prepared.chapters
                let saved = self.environment.library.entry(for: target)?.reading
                let current = prepared.chapters.firstIndex { $0.chapterId == saved?.chapter.chapterId } ?? saved?.chapterIndex ?? 0
                let selection = DownloadSelectionViewController(detail: prepared, currentIndex: current, environment: self.environment) { [weak self] in
                    guard let self, self.downloadID == token else { return }
                    self.feedback.downloadQueued(); self.updateFeedback()
                }
                self.feedback.endDownload(); self.updateFeedback()
                self.present(selection, animated: true)
            } catch {
                guard self.downloadID == token, !Task.isCancelled else { return }
                if (error as? Mh18SourceError) == .verificationRequired {
                    self.feedback.endDownload(); self.updateFeedback()
                    self.showSourceError(error, environment: self.environment) { [weak self] in self?.openDownloadSelection() }
                } else {
                    self.feedback.failDownload((error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试")
                    self.updateFeedback()
                }
            }
        }
    }
    private func cancelDownloadSelection() {
        downloadID = UUID(); downloadTask?.cancel(); downloadTask = nil
        setDownloadButton(loading: false)
        directoryID = UUID(); directoryTask?.cancel(); directoryTask = nil
        feedback.endDownload(); updateFeedback()
    }
    private func cancelPreparingRead() {
        let wasPreparing = readTask != nil
        readID = UUID(); readTask?.cancel(); readTask = nil
        if wasPreparing {
            // The directory worker is a shared unstructured Task. Cancelling
            // only its reader waiter leaves the request alive and can block the
            // download that takes over. Invalidate and cancel the actual work.
            directoryID = UUID(); directoryTask?.cancel(); directoryTask = nil
        }
        read.isEnabled = true; updateButtons()
    }
    @objc private func toggleFavorite() {
        do {
            try environment.library.setFavorite(comic, favorite: environment.library.entry(for: comic)?.isFavorite != true)
            environment.notifyLibraryChanged(); updateButtons()
        } catch { showError(error) }
    }
    @objc private func favoriteLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        if environment.library.entry(for: comic)?.isFavorite != true {
            try? environment.library.setFavorite(comic, favorite: true)
            environment.notifyLibraryChanged()
            updateButtons()
        }
        let sheet = BookshelfGroupSelectSheet(environment: environment, scope: .online, comicId: comic.comicId, comicTitle: comic.title)
        present(sheet, animated: true)
    }
    @objc private func openSourceSwitchSheet() {
        cancelDownloadSelection()
        let sheet = SourceSwitchSheet(comic: comic, environment: environment) { [weak self] targetDetail in
            guard let self else { return }
            self.applySwitchedSource(targetDetail: targetDetail)
        }
        let navigation = UINavigationController(rootViewController: sheet)
        navigation.navigationBar.tintColor = Palette.accent
        present(navigation, animated: true)
    }
    private func applySwitchedSource(targetDetail: ComicDetail) {
        guard let newSource = environment.source(for: targetDetail.summary) else { return }
        cancelDownloadSelection()
        detailTask?.cancel(); detailTask = nil
        cancelPreparingRead()
        feedback = DetailFeedbackState()
        self.comic = targetDetail.summary
        self.source = newSource
        self.title = newSource.name
        self.sourceSwitchButton.setTitle(newSource.name, for: .normal)
        self.sourceSwitchButton.accessibilityLabel = "切换站源，当前" + newSource.name
        self.sourceSwitchButton.isEnabled = true
        self.cachedDetail = targetDetail
        self.cachedChapters = targetDetail.chapters.isEmpty ? nil : targetDetail.chapters
        self.detailLoaded = true
        self.heading.text = targetDetail.summary.title
        self.updateDetailText(targetDetail)
        self.cover.loadCover(targetDetail.summary, referer: newSource.referer, library: self.environment.localLibrary)
        self.updateFeedback()
        self.updateButtons()
        let revision = FavoriteRevision.fromChapters(latestChapterName: targetDetail.latestChapter, chapters: targetDetail.chapters)
        self.environment.favoriteUpdateCoordinator.acknowledge(sourceId: targetDetail.summary.sourceId, comicId: targetDetail.summary.comicId, revision: revision)
    }
    @objc private func openVolumeManager() {
        let vm = VolumeManagerViewController(seriesId: comic.comicId, seriesTitle: comic.title, environment: environment) { [weak self] in
            self?.localVolumesChanged()
        }
        let nav = FilterDrawerNavigationController(rootViewController: vm)
        present(nav, animated: true)
    }
    private func localVolumesChanged() {
        cachedChapters = nil; environment.notifyLibraryChanged()
        let library = environment.localLibrary, id = comic.comicId
        detailTask?.cancel()
        detailTask = Task { [weak self] in
            do {
                let series = try await Task.detached(priority: .utility) { try await library.series(id: id) }.value
                guard let self, !Task.isCancelled, self.view.window != nil else { return }
                if series == nil { self.navigationController?.popViewController(animated: true) }
                else { self.loadDetail() }
            } catch {
                guard let self, !Task.isCancelled else { return }; self.loadDetail()
            }
        }
    }
    @objc private func showLocalManagementMenu() {
        let alert = UIAlertController(title: "漫画管理", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "管理分卷", style: .default) { [weak self] _ in
            self?.openVolumeManager()
        })
        alert.addAction(UIAlertAction(title: "修改作品名称", style: .default) { [weak self] _ in
            self?.renameLocalSeries()
        })
        alert.addAction(UIAlertAction(title: "删除本地漫画", style: .destructive) { [weak self] _ in
            self?.confirmDeleteLocalSeries()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }
    @objc private func renameLocalSeries() {
        let alert = UIAlertController(title: "修改作品名称", message: "修改当前漫画的展示名称", preferredStyle: .alert)
        alert.addTextField { [weak self] in
            $0.text = self?.comic.title
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self, let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            Task {
                do {
                    _ = try await self.environment.localLibrary.renameSeries(id: self.comic.comicId, newTitle: title)
                    self.loadDetail()
                    self.environment.notifyLibraryChanged()
                } catch {
                    self.showError(error)
                }
            }
        })
        present(alert, animated: true)
    }
    @objc private func confirmDeleteLocalSeries() {
        let alert = UIAlertController(
            title: "删除本地漫画",
            message: "将从书架和 App 本地存储中移除此漫画，原导入文件不受影响。\n（若以后重新导入相同文件，阅读历史和进度将自动恢复）",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "删除 App 副本", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.environment.localDeletion.schedule([.init(target: .localSeries(self.comic.comicId), title: self.comic.title, groupComicID: self.comic.comicId)], from: self)
            self.navigationController?.popViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }
    private func chapters() async throws -> [Chapter] {
        if let cachedChapters { return cachedChapters }
        if directoryTask == nil {
            directoryID = UUID()
            let id = comic.comicId
            let sourceId = comic.sourceId
            directoryTask = Task { [source, weak self] in
                do {
                    return try await source.chapters(comicId: id)
                } catch {
                    guard !(error is CancellationError), !Task.isCancelled else { throw CancellationError() }
                    if let self,
                       let bookId = try? DownloadModels.bookId(source: sourceId, comic: id),
                       let snapshot = self.environment.downloadStore.snapshot(id: bookId),
                       !snapshot.chapters.isEmpty {
                        return snapshot.chapters
                    }
                    throw error
                }
            }
        }
        let token = directoryID
        do {
            let result = try await directoryTask!.value
            guard directoryID == token else { throw CancellationError() }
            cachedChapters = result.isEmpty ? nil : result; directoryTask = nil
            updateDirectoryButton()
            return result
        } catch { if directoryID == token { directoryTask = nil }; throw error }
    }
    @objc private func showDirectory() {
        if downloadTask != nil { cancelDownloadSelection() }
        feedback.endDownload(); updateFeedback()
        cancelPreparingRead()
        let controller = ChapterListViewController(load: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.chapters()
        }, selectedID: environment.library.entry(for: comic)?.reading?.chapter.chapterId, defaults: environment.defaults, environment: environment) { [weak self] chapters, index in
            guard let self else { return }
            self.openReader(chapters: chapters, index: index, incomplete: false)
        }
        present(ChapterListViewController.navigation(controller), animated: true)
    }
    @objc private func startReading() {
        if downloadTask != nil { cancelDownloadSelection() }
        feedback.endDownload(); updateFeedback()
        if let saved = environment.library.entry(for: comic)?.reading {
            // Saved chapter URL is sufficient; do not block resume on directory loading.
            openReader(chapters: [saved.chapter], index: 0, incomplete: true)
        } else {
            guard readTask == nil else { return }
            readID = UUID()
            let token = readID
            read.isEnabled = false; setReadStatus("正在加载章节…")
            readTask = Task { [weak self] in
                guard let self else { return }
                var independentlyCancelled = false
                defer {
                    if self.readID == token && !Task.isCancelled {
                        self.readTask = nil; self.read.isEnabled = true; self.updateButtons()
                        if independentlyCancelled { self.setReadStatus("已取消 · 点击重试") }
                    }
                }
                do {
                    let items = try await self.chapters(); try Task.checkCancellation()
                    guard self.readID == token else { return }
                    guard !items.isEmpty else {
                        self.feedback.setDetail("暂无章节 · 点击章节目录刷新")
                        self.updateFeedback()
                        return
                    }
                    self.openReader(chapters: items, index: 0, incomplete: false)
                } catch {
                    if self.readID == token && !Task.isCancelled {
                        if error is CancellationError { independentlyCancelled = true; return }
                        ErrorLogStore.shared.append(title: "目录加载失败: \(self.comic.title)", error: error)
                        self.showSourceError(error, environment: self.environment) { [weak self] in self?.startReading() }
                    }
                }
            }
        }
    }
    private func openReader(chapters: [Chapter], index: Int, incomplete: Bool) {
        guard chapters.indices.contains(index) else { return }
        if comic.sourceId == "local" {
            readID = UUID(); readTask?.cancel()
            let token = readID, targetChapter = chapters[index], library = environment.localLibrary, id = comic.comicId
            read.isEnabled = false; setReadStatus("正在打开本地书籍…")
            readTask = Task { [weak self] in
                do {
                    let target = try await library.readingTarget(seriesId: id, chapterId: targetChapter.chapterId)
                    guard let self, self.readID == token, !Task.isCancelled else { return }
                    let complete = incomplete ? try await self.source.chapters(comicId: id) : chapters
                    try Task.checkCancellation()
                    guard self.readID == token, !complete.isEmpty else { return }
                    let realIndex = complete.firstIndex { $0.chapterId == targetChapter.chapterId } ?? target.globalChapterIndex
                    self.navigationController?.pushViewController(ReaderViewController(comic: self.comic, chapters: complete, chapterIndex: realIndex, directoryIncomplete: false, environment: self.environment), animated: true)
                    self.readTask = nil; self.read.isEnabled = true; self.updateButtons()
                } catch {
                    guard let self, self.readID == token, !Task.isCancelled else { return }
                    self.readTask = nil; self.read.isEnabled = true
                    let alert = UIAlertController(title: error is CancellationError ? "已取消打开" : "无法打开书籍", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                    if (error as? LocalLibraryError) != .unsupportedTextContent {
                        alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in self?.openReader(chapters: chapters, index: index, incomplete: incomplete) })
                    }
                    self.present(alert, animated: true)
                }
            }
            return
        }
        let reader = ReaderViewController(comic: comic, chapters: chapters,
            chapterIndex: index, directoryIncomplete: incomplete, environment: environment)
        reader.onSourceChanged = { [weak self] detail in self?.applySwitchedSource(targetDetail: detail) }
        navigationController?.pushViewController(reader, animated: true)
    }
}

@MainActor
private final class DetailTagLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize; return CGSize(width: size.width + 20, height: size.height + 12)
    }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 10, dy: 6)) }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = Palette.border.resolvedColor(with: traitCollection).cgColor
    }
}

@MainActor
final class ChapterListViewController: UITableViewController {
    static func navigation(_ controller: ChapterListViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [
                .custom(identifier: .init("collapsed")) { $0.maximumDetentValue * 0.55 },
                .custom(identifier: .init("expanded")) { $0.maximumDetentValue * 0.92 }
            ]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        return navigation
    }
    private let load: () async throws -> [Chapter]
    private let onSelect: ([Chapter], Int) -> Void
    private let onDismiss: () -> Void
    private let selectedID: String?
    private let defaults: UserDefaults
    private let environment: AppEnvironment?
    private var needsVerification = false
    private var chapters: [Chapter] = []
    private var descending = false
    private var task: Task<Void, Never>?
    private let state = UIButton(type: .system)
    init(load: @escaping () async throws -> [Chapter], selectedID: String?, defaults: UserDefaults = .standard, environment: AppEnvironment? = nil,
         onDismiss: @escaping () -> Void = {}, onSelect: @escaping ([Chapter], Int) -> Void) {
        self.load = load; self.selectedID = selectedID; self.onDismiss = onDismiss; self.onSelect = onSelect
        self.defaults = defaults; descending = defaults.bool(forKey: "chapter.desc")
        self.environment = environment
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "全部章节"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: descending ? "倒序" : "正序", style: .plain, target: self, action: #selector(reverseOrder))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "chapter.list.order"
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "chapter.list.close"
        tableView.accessibilityIdentifier = "chapter.list"
        state.titleLabel?.numberOfLines = 0
        state.addTarget(self, action: #selector(stateTapped), for: .touchUpInside)
        tableView.backgroundView = state
        reload()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToSelected()
    }
    @objc private func reload() {
        needsVerification = false
        task?.cancel(); state.isHidden = false; state.setTitle("正在加载目录…", for: .normal)
        let loader = load
        task = Task { [weak self] in
            do {
                let chapters = try await loader(); try Task.checkCancellation()
                guard let self else { return }
                self.chapters = chapters
                self.state.setTitle(chapters.isEmpty ? "暂无章节 · 点击刷新" : nil, for: .normal)
                self.state.isHidden = !chapters.isEmpty
                self.tableView.reloadData()
                self.scrollToSelected()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.needsVerification = self.environment != nil && (error as? Mh18SourceError) == .verificationRequired
                self.state.setTitle(self.needsVerification ? "需要验证 · 去验证" : (error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试", for: .normal)
            }
        }
    }
    @objc private func stateTapped() {
        if needsVerification, let environment {
            showSourceManagement(environment: environment) { [weak self] in self?.reload() }
        } else { reload() }
    }
    @objc private func close() { dismissSheet() }
    @objc private func reverseOrder() {
        descending.toggle()
        defaults.set(descending, forKey: "chapter.desc")
        navigationItem.leftBarButtonItem?.title = descending ? "倒序" : "正序"
        tableView.reloadData()
        scrollToSelected()
    }
    private func scrollToSelected() {
        guard let selectedID, let selected = chapters.firstIndex(where: { $0.chapterId == selectedID }) else { return }
        tableView.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: descending ? chapters.count - 1 - selected : selected, section: 0), at: .top, animated: false)
    }
    private func index(_ row: Int) -> Int { descending ? chapters.count - 1 - row : row }
    private func dismissSheet(then completion: (() -> Void)? = nil) {
        dismiss(animated: true) { [onDismiss] in onDismiss(); completion?() }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { chapters.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let chapter = chapters[index(indexPath.row)]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = chapter.title; cell.textLabel?.numberOfLines = 2
        cell.accessoryType = chapter.chapterId == selectedID ? .checkmark : .none
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selected = index(indexPath.row), items = chapters
        dismissSheet { [onSelect] in onSelect(items, selected) }
    }
}
