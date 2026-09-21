import UIKit
import ComicCore

@MainActor
final class EpubTextReaderViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let environment: AppEnvironment
    private let comic: ComicSummary
    private let chapters: [Chapter]
    private var session: EpubTextSession
    private var settings: TextReaderPreferences
    private let content = EpubTextContentView()
    private let controls = UIStackView()
    private let progress = UISlider()
    private let sectionLabel = UILabel()
    private let state = UIButton(type: .system)
    private var readable = false
    private var locator: TextLocator?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var needsReload = false

    init(comic: ComicSummary, chapters: [Chapter], session: EpubTextSession, locator: TextLocator?, environment: AppEnvironment) {
        self.comic = comic; self.chapters = chapters; self.session = session; self.environment = environment
        let volLocator = locator?.toVolumeLocator(volumeId: session.book.id, volumeChapterIndex: session.chapterIndex)
        self.locator = volLocator.flatMap { $0.bookID == session.book.id && $0.chapterIndex == session.chapterIndex && $0.spineIndex == session.spineIndex && $0.resourceHref == session.entry.fullZipPath ? $0 : nil }
        settings = environment.textPreferences.load()
        super.init(nibName: nil, bundle: nil); hidesBottomBarWhenPushed = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    private var currentGlobalChapterIndex: Int {
        if let chapters = session.book.chapters, chapters.indices.contains(session.chapterIndex) {
            let chId = chapters[session.chapterIndex].id
            return self.chapters.firstIndex(where: { $0.chapterId == chId }) ?? session.chapterIndex
        }
        return self.chapters.firstIndex(where: { $0.chapterId == session.book.id }) ?? session.chapterIndex
    }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = Palette.background
        controls.axis = .vertical; controls.spacing = 8; controls.backgroundColor = Palette.background.withAlphaComponent(0.96)
        controls.isLayoutMarginsRelativeArrangement = true; controls.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        let chapterRow = UIStackView(arrangedSubviews: [button("上一章", #selector(previousChapter)), button("目录", #selector(directory)), button("下一章", #selector(nextChapter))])
        let sectionRow = UIStackView(arrangedSubviews: [button("上一节", #selector(previousSpine)), sectionLabel, button("下一节", #selector(nextSpine))])
        let settingsRow = UIStackView(arrangedSubviews: [button("详情", #selector(detail)), button("排版", #selector(layoutSettings)), button("主题", #selector(cycleTheme))])
        for row in [chapterRow, sectionRow, settingsRow] { row.distribution = .fillEqually; row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true }
        sectionLabel.textAlignment = .center; sectionLabel.adjustsFontSizeToFitWidth = true; sectionLabel.accessibilityIdentifier = "epub.section"
        progress.minimumValue = 0; progress.maximumValue = 100; progress.accessibilityIdentifier = "epub.progress"
        progress.addTarget(self, action: #selector(seek), for: .valueChanged)
        [chapterRow, sectionRow, progress, settingsRow].forEach { controls.addArrangedSubview($0) }
        state.titleLabel?.numberOfLines = 0; state.accessibilityIdentifier = "epub.state"
        state.addTarget(self, action: #selector(retry), for: .touchUpInside)
        [content, controls, state].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor), content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor), controls.trailingAnchor.constraint(equalTo: view.trailingAnchor), controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            state.centerXAnchor.constraint(equalTo: view.centerXAnchor), state.centerYAnchor.constraint(equalTo: view.centerYAnchor), state.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])
        content.onReadable = { [weak self] in
            guard let self else { return }
            self.readable = true; self.state.isHidden = true
            self.locator = self.session.locator(anchorID: self.content.anchor, percent: self.content.percent)
            self.progress.value = Float(self.content.percent * 100)
            self.progress.accessibilityValue = "\(Int(self.content.percent * 100))%"
            self.environment.readingHabits.contentBecameReadable(); self.overlayChanged(); self.save()
        }
        content.onPosition = { [weak self] anchor, percent in
            guard let self, self.readable else { return }
            self.locator = self.session.locator(anchorID: anchor, percent: percent)
            self.progress.value = Float(percent * 100)
            self.progress.accessibilityValue = "\(Int(percent * 100))%"
        }
        content.onUserRead = { [weak self] in self?.environment.readingHabits.userDidRead() }
        content.onToggleControls = { [weak self] in
            guard let self else { return }
            self.controls.isHidden.toggle()
            self.navigationController?.setNavigationBarHidden(self.controls.isHidden, animated: true)
            self.overlayChanged()
        }
        content.onLink = { [weak self] path, anchor in
            guard let self else { return }
            self.save()
            let old = self.session.spineIndex
            guard self.session.navigate(path: path) else { return }
            if old == self.session.spineIndex { self.content.restore(anchor: anchor, percent: 0) }
            else { self.locator = self.session.locator(anchorID: anchor, percent: 0); self.load() }
            self.environment.readingHabits.userDidRead()
        }
        content.onExternalLink = { [weak self] url in self?.confirmExternal(url) }
        content.onFailure = { [weak self] error in
            guard let self else { return }
            self.readable = false; self.state.isHidden = false
            self.state.setTitle((error is CancellationError ? "已取消" : error.localizedDescription) + " · 点击重试", for: .normal)
            self.overlayChanged()
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save(); self?.environment.readingHabits.appDidEnterBackground() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environment.readingHabits.appWillEnterForeground(); self?.overlayChanged() }
        })
        load()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        environment.readingHabits.enterReader(comicID: comic.comicId, isLocal: true)
        if needsReload { needsReload = false; load() }
        overlayChanged()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.environment.readingHabits.tick(); self?.save() }
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); save()
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentedViewController == nil else { return }
        timer?.invalidate(); timer = nil
        content.cancel(); readable = false; needsReload = true
        environment.readingHabits.exitReader()
    }
    deinit { timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let position = locator
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self, let position, position.spineIndex == self.session.spineIndex else { return }
            self.content.restore(anchor: position.anchorID, percent: position.scrollPercentage)
        }
    }
    private func button(_ title: String, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.addTarget(self, action: action, for: .touchUpInside); return button
    }
    private func load() {
        readable = false; state.isHidden = false; state.setTitle("正在加载正文…", for: .normal)
        let gIdx = currentGlobalChapterIndex
        title = chapters.indices.contains(gIdx) ? chapters[gIdx].title : ""
        let pages = session.book.chapters![session.chapterIndex].pages
        let localIndex = pages.firstIndex(of: session.book.pages[session.spineIndex]) ?? 0
        sectionLabel.text = "\(localIndex + 1)/\(pages.count) 节"
        sectionLabel.accessibilityValue = "第\(gIdx + 1)章，第\(localIndex + 1)节"
        progress.value = Float((locator?.scrollPercentage ?? 0) * 100)
        progress.accessibilityValue = "\(Int(progress.value))%"
        overlayChanged()
        content.load(book: session.book, entry: session.entry, library: environment.localLibrary, preferences: settings, locator: locator)
    }
    private func save() {
        guard readable, let locator else { return }
        let gIdx = currentGlobalChapterIndex
        guard chapters.indices.contains(gIdx) else { return }
        let seriesLocator = locator.toSeriesLocator(seriesId: comic.comicId, globalChapterIndex: gIdx)
        do {
            try environment.library.saveTextReading(comic, chapter: chapters[gIdx], chapterIndex: gIdx, locator: seriesLocator)
            environment.notifyLibraryChanged()
        } catch { state.isHidden = false; state.setTitle("阅读位置保存失败：\(error.localizedDescription)", for: .normal) }
    }
    private func selectChapter(_ index: Int, atEnd: Bool = false) {
        guard chapters.indices.contains(index) else { return }
        save()
        let targetChapter = chapters[index]
        let library = environment.localLibrary
        Task { [weak self] in
            guard let self else { return }
            do {
                let target = try await library.readingTarget(seriesId: self.comic.comicId, chapterId: targetChapter.chapterId)
                if target.kind == .comic {
                    self.switchToComicReader(chapterIndex: target.globalChapterIndex, atEnd: atEnd)
                    return
                }
                let book = try library.book(id: target.volumeId)
                let saved = self.environment.library.textPosition(for: self.comic, chapterID: targetChapter.chapterId)
                let volLocator: TextLocator?
                if let saved {
                    volLocator = saved.toVolumeLocator(volumeId: target.volumeId, volumeChapterIndex: target.volumeChapterIndex)
                } else if atEnd {
                    let spineCount = book.chapters?[target.volumeChapterIndex].pages.count ?? 1
                    volLocator = TextLocator(bookID: target.volumeId, chapterIndex: target.volumeChapterIndex,
                                             spineIndex: max(0, spineCount - 1), resourceHref: "", anchorID: "", scrollPercentage: 1.0)
                } else {
                    volLocator = TextLocator(bookID: target.volumeId, chapterIndex: target.volumeChapterIndex,
                                             spineIndex: 0, resourceHref: "", anchorID: "", scrollPercentage: 0.0)
                }
                self.session = try EpubTextSession(book: book, chapterIndex: target.volumeChapterIndex, locator: volLocator)
                self.locator = volLocator
                self.load()
                self.environment.readingHabits.userDidRead()
            } catch {
                self.showError(error)
            }
        }
    }
    private func switchToComicReader(chapterIndex: Int, atEnd: Bool) {
        let reader = ReaderViewController(comic: comic, chapters: chapters, chapterIndex: chapterIndex, directoryIncomplete: false, environment: environment)
        if let nav = navigationController {
            var vcs = nav.viewControllers
            if let idx = vcs.lastIndex(where: { $0 === self }) {
                vcs[idx] = reader
                nav.setViewControllers(vcs, animated: false)
            }
        }
    }
    private func move(_ delta: Int) {
        save()
        if session.moveSpine(delta: delta) {
            locator = nil; load(); environment.readingHabits.userDidRead()
            return
        }
        if delta == 1 {
            nextChapter()
        } else if delta == -1 {
            previousChapter()
        }
    }
    @objc private func previousChapter() {
        let current = currentGlobalChapterIndex
        guard current > 0 else {
            boundary()
            return
        }
        selectChapter(current - 1, atEnd: true)
    }
    @objc private func nextChapter() {
        let current = currentGlobalChapterIndex
        guard current + 1 < chapters.count else {
            boundary()
            return
        }
        selectChapter(current + 1, atEnd: false)
    }
    private func boundary() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "没有更多章节了", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    @objc private func previousSpine() { move(-1) }
    @objc private func nextSpine() { move(1) }
    @objc private func retry() { load() }
    @objc private func seek() { content.restore(anchor: "", percent: Double(progress.value) / 100); environment.readingHabits.userDidRead() }
    @objc private func detail() {
        save()
        if let nav = navigationController {
            if let detailVC = nav.viewControllers.first(where: { $0 is DetailViewController }) {
                nav.popToViewController(detailVC, animated: true)
                return
            }
        }
        navigationController?.pushViewController(DetailViewController(comic: comic, environment: environment), animated: true)
    }
    private func overlayChanged() { environment.readingHabits.overlayVisibilityChanged(isVisible: !readable || !controls.isHidden || presentedViewController != nil) }
    private func presentPanel(_ controller: UIViewController) {
        environment.readingHabits.overlayVisibilityChanged(isVisible: true)
        present(controller, animated: true)
        // UIKit owns UIAlertController's presentation delegate; replacing it raises an exception.
        if !(controller is UIAlertController) { controller.presentationController?.delegate = self }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { overlayChanged() }
    @objc private func directory() {
        let items = chapters
        let current = currentGlobalChapterIndex
        let currentChapterId = chapters.indices.contains(current) ? chapters[current].chapterId : nil
        let controller = ChapterListViewController(load: { items }, selectedID: currentChapterId, defaults: environment.defaults,
            onDismiss: { [weak self] in self?.overlayChanged() }, onSelect: { [weak self] _, index in self?.selectChapter(index) })
        presentPanel(ChapterListViewController.navigation(controller))
    }
    @objc private func layoutSettings() {
        let controller = TextReaderSettingsViewController(settings: settings) { [weak self] settings in self?.updateSettings(settings) }
        controller.onDismiss = { [weak self] in self?.overlayChanged() }
        presentPanel(UINavigationController(rootViewController: controller))
    }
    @objc private func cycleTheme() {
        var next = settings; next.theme = TextReaderTheme(rawValue: (next.theme.rawValue + 1) % 3)!
        updateSettings(next)
    }
    private func updateSettings(_ settings: TextReaderPreferences) {
        self.settings = settings; environment.textPreferences.save(settings); content.apply(settings)
    }
    private func confirmExternal(_ url: URL) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "打开外部链接？", message: url.absoluteString, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.overlayChanged() })
        alert.addAction(UIAlertAction(title: "在浏览器打开", style: .default) { [weak self] _ in
            UIApplication.shared.open(url); self?.overlayChanged()
        })
        presentPanel(alert)
    }
}
