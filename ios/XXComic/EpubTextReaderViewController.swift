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
        // A stale locator must not restore its percent into the fallback spine.
        self.locator = locator.flatMap { $0.bookID == session.book.id && $0.chapterIndex == session.chapterIndex && $0.spineIndex == session.spineIndex && $0.resourceHref == session.entry.fullZipPath ? $0 : nil }
        settings = environment.textPreferences.load()
        super.init(nibName: nil, bundle: nil); hidesBottomBarWhenPushed = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
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
        title = chapters[session.chapterIndex].title
        let pages = session.book.chapters![session.chapterIndex].pages
        let localIndex = pages.firstIndex(of: session.book.pages[session.spineIndex]) ?? 0
        sectionLabel.text = "\(localIndex + 1)/\(pages.count) 节"
        sectionLabel.accessibilityValue = "第\(session.chapterIndex + 1)章，第\(localIndex + 1)节"
        progress.value = Float((locator?.scrollPercentage ?? 0) * 100)
        progress.accessibilityValue = "\(Int(progress.value))%"
        overlayChanged()
        content.load(book: session.book, entry: session.entry, library: environment.localLibrary, preferences: settings, locator: locator)
    }
    private func save() {
        guard readable, let locator else { return }
        do {
            try environment.library.saveTextReading(comic, chapter: chapters[session.chapterIndex], chapterIndex: session.chapterIndex, locator: locator)
            environment.notifyLibraryChanged()
        } catch { state.isHidden = false; state.setTitle("阅读位置保存失败：\(error.localizedDescription)", for: .normal) }
    }
    private func selectChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        save()
        do {
            let saved = environment.library.textPosition(for: comic, chapterID: chapters[index].chapterId)
            session = try EpubTextSession(book: session.book, chapterIndex: index, locator: saved)
            locator = saved.flatMap { $0.spineIndex == session.spineIndex && $0.resourceHref == session.entry.fullZipPath && $0.bookID == session.book.id && $0.chapterIndex == index ? $0 : nil }
            load(); environment.readingHabits.userDidRead()
        } catch { showError(error) }
    }
    private func move(_ delta: Int) {
        save(); guard session.moveSpine(delta: delta) else { return }
        locator = nil; load(); environment.readingHabits.userDidRead()
    }
    @objc private func previousChapter() { selectChapter(session.chapterIndex - 1) }
    @objc private func nextChapter() { selectChapter(session.chapterIndex + 1) }
    @objc private func previousSpine() { move(-1) }
    @objc private func nextSpine() { move(1) }
    @objc private func retry() { load() }
    @objc private func seek() { content.restore(anchor: "", percent: Double(progress.value) / 100); environment.readingHabits.userDidRead() }
    @objc private func detail() { save(); navigationController?.pushViewController(DetailViewController(comic: comic, environment: environment), animated: true) }
    private func overlayChanged() { environment.readingHabits.overlayVisibilityChanged(isVisible: !readable || !controls.isHidden || presentedViewController != nil) }
    private func presentPanel(_ controller: UIViewController) {
        environment.readingHabits.overlayVisibilityChanged(isVisible: true)
        present(controller, animated: true); controller.presentationController?.delegate = self
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { overlayChanged() }
    @objc private func directory() {
        let items = chapters
        let controller = ChapterListViewController(load: { items }, selectedID: chapters[session.chapterIndex].chapterId, defaults: environment.defaults,
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
