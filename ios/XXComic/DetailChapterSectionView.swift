import UIKit
import ComicCore

/// Inline chapter catalog section on the comic detail page.
/// Aligned 1:1 with Android 2.0.46's `DetailChapterSectionView`.
/// Features:
/// - Scheme A: Adaptive range segment tabs (e.g. 1-60, 61-120) for O(1) performance with large catalogs.
/// - Scheme B: Compact 12-chapter preview grid centered around reading progress, with expand/collapse toggle.
/// - Order toggle button (`detail.chapter.order`), segments bar (`detail.chapter.segments`), expand toggle (`detail.chapter.expand`).
/// - Downloaded badge and current reading chapter highlight.
public final class DetailChapterSectionView: UIView {

    public typealias Segment = DetailChapterSection.Segment

    // MARK: - State Properties

    public private(set) var chapters: [Chapter] = []
    public private(set) var currentChapterIndex: Int = 0
    public private(set) var hasCurrent: Bool = false
    public private(set) var isDesc: Bool = false
    public private(set) var downloadedChapterIds: Set<String> = []

    public private(set) var loading: Bool = false
    public private(set) var errorMessage: String = ""
    public private(set) var selectedSegmentIndex: Int = -1
    public private(set) var isExpanded: Bool = false

    private var lastRenderedColumns: Int = 0
    private var segmentScrollX: CGFloat = 0

    // MARK: - Callbacks

    public var onSelectChapter: ((Int) -> Void)?
    public var onOrderChanged: ((Bool) -> Void)?
    public var onOpenDrawer: (() -> Void)?
    public var onRetry: (() -> Void)?

    // MARK: - Subviews

    private let contentStack = UIStackView()
    private var activeSegmentScroller: UIScrollView?

    // MARK: - Initializer

    public init(
        chapters: [Chapter] = [],
        currentChapterIndex: Int = 0,
        hasCurrent: Bool = false,
        isDesc: Bool = false,
        downloadedChapterIds: Set<String> = [],
        onSelectChapter: ((Int) -> Void)? = nil,
        onOrderChanged: ((Bool) -> Void)? = nil,
        onOpenDrawer: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.chapters = chapters
        self.currentChapterIndex = currentChapterIndex
        self.hasCurrent = hasCurrent
        self.isDesc = isDesc
        self.downloadedChapterIds = downloadedChapterIds
        self.onSelectChapter = onSelectChapter
        self.onOrderChanged = onOrderChanged
        self.onOpenDrawer = onOpenDrawer
        self.onRetry = onRetry
        super.init(frame: .zero)

        setupView()
        render(autoScrollSegment: true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        render(autoScrollSegment: true)
    }

    private func setupView() {
        accessibilityIdentifier = "detail-chapter-section"
        translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.distribution = .fill
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let cols = resolveColumns()
        if cols != lastRenderedColumns && !chapters.isEmpty {
            render(autoScrollSegment: false)
        }
    }

    // MARK: - Public API

    public func showLoading() {
        if loading && chapters.isEmpty { return }
        loading = true
        errorMessage = ""
        render(autoScrollSegment: false)
    }

    public func showError(_ message: String?) {
        loading = false
        errorMessage = (message == nil || message!.isEmpty) ? "目录加载失败" : message!
        render(autoScrollSegment: false)
    }

    public func bindChapters(
        _ loadedChapters: [Chapter]?,
        currentChapterIndex: Int,
        hasCurrent: Bool,
        downloadedChapterIds: Set<String> = []
    ) {
        self.chapters = loadedChapters ?? []
        self.currentChapterIndex = currentChapterIndex
        self.hasCurrent = hasCurrent
        self.downloadedChapterIds = downloadedChapterIds
        self.loading = false
        self.errorMessage = ""
        self.selectedSegmentIndex = -1
        render(autoScrollSegment: true)
    }

    public func setOrder(desc: Bool) {
        if isDesc == desc { return }
        isDesc = desc
        selectedSegmentIndex = -1
        segmentScrollX = 0
        render(autoScrollSegment: true)
    }

    public func copyStateFrom(_ previous: DetailChapterSectionView?) {
        guard let prev = previous else { return }
        self.selectedSegmentIndex = prev.selectedSegmentIndex
        self.isExpanded = prev.isExpanded
        self.segmentScrollX = prev.activeSegmentScroller?.contentOffset.x ?? prev.segmentScrollX
        render(autoScrollSegment: false)
    }

    // MARK: - Rendering

    private func render(autoScrollSegment: Bool) {
        if let scroller = activeSegmentScroller {
            segmentScrollX = scroller.contentOffset.x
        }
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Top divider
        let divider = UIView()
        divider.backgroundColor = Palette.borderSoft
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        contentStack.addArrangedSubview(divider)

        // Header Row
        let header = buildHeaderRow()
        contentStack.addArrangedSubview(header)
        contentStack.setCustomSpacing(10, after: header)

        if chapters.isEmpty {
            if loading {
                let loadingBody = buildLoadingBody()
                contentStack.addArrangedSubview(loadingBody)
            } else if !errorMessage.isEmpty {
                let errorBody = buildErrorBody()
                contentStack.addArrangedSubview(errorBody)
            } else {
                let emptyBody = buildEmptyBody()
                contentStack.addArrangedSubview(emptyBody)
            }
            return
        }

        let total = chapters.count
        let columns = resolveColumns()
        lastRenderedColumns = columns

        let segments = DetailChapterSection.buildSegments(totalChapters: total, isDesc: isDesc)
        if selectedSegmentIndex < 0 || selectedSegmentIndex >= segments.count {
            selectedSegmentIndex = DetailChapterSection.selectDefaultSegmentIndex(
                segments: segments,
                currentChapterIndex: currentChapterIndex,
                hasCurrent: hasCurrent
            )
        }
        let activeSegment = segments[selectedSegmentIndex]

        // Segment Bar
        if total > DetailChapterSection.previewLimit && segments.count > 1 {
            let segBar = buildSegmentBar(segments: segments, activeIdx: selectedSegmentIndex, autoScroll: autoScrollSegment)
            contentStack.addArrangedSubview(segBar)
            contentStack.setCustomSpacing(10, after: segBar)
        }

        // Chapter Grid
        let visibleIndices = DetailChapterSection.selectVisibleWindow(
            segmentIndices: activeSegment.chapterIndices,
            currentChapterIndex: currentChapterIndex,
            hasCurrent: hasCurrent,
            expanded: isExpanded,
            columns: columns
        )
        let grid = buildChapterGrid(visibleIndices: visibleIndices, columns: columns)
        contentStack.addArrangedSubview(grid)

        // Footer Expand/Collapse Toggle
        if activeSegment.chapterIndices.count > DetailChapterSection.previewLimit {
            contentStack.setCustomSpacing(6, after: grid)
            let footer = buildFooterRow(activeSegment: activeSegment)
            contentStack.addArrangedSubview(footer)
        }
    }

    // MARK: - Header Row

    private func buildHeaderRow() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = UIStackView()
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = 8
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleStack)

        let titleLabel = UILabel()
        titleLabel.text = "章节目录"
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleStack.addArrangedSubview(titleLabel)

        var statusText = ""
        if !chapters.isEmpty {
            statusText = "共 \(chapters.count) 话"
            if hasCurrent && currentChapterIndex >= 0 && currentChapterIndex < chapters.count {
                let curTitle = DetailChapterSection.cleanChapterTitle(chapter: chapters[currentChapterIndex], index: currentChapterIndex)
                statusText += " · 读至 \(curTitle)"
            }
        } else if loading {
            statusText = "正在加载…"
        } else if !errorMessage.isEmpty {
            statusText = errorMessage
        }

        if !statusText.isEmpty {
            let subLabel = UILabel()
            subLabel.text = statusText
            subLabel.font = .systemFont(ofSize: 12)
            subLabel.textColor = Palette.text3
            subLabel.lineBreakMode = .byTruncatingTail
            titleStack.addArrangedSubview(subLabel)
        }

        let rightStack = UIStackView()
        rightStack.axis = .horizontal
        rightStack.alignment = .center
        rightStack.spacing = 8
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rightStack)

        if !chapters.isEmpty {
            let orderBtn = UIButton(type: .custom)
            orderBtn.accessibilityIdentifier = "detail.chapter.order"
            let orderText = isDesc ? "⇅ 倒序" : "⇅ 正序"
            orderBtn.setTitle(orderText, for: .normal)
            orderBtn.setTitleColor(Palette.accent, for: .normal)
            orderBtn.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
            orderBtn.backgroundColor = Palette.accentSoft
            orderBtn.layer.cornerRadius = 12
            orderBtn.clipsToBounds = true
            orderBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
            orderBtn.accessibilityLabel = "切换章节排序，当前\(isDesc ? "倒序" : "正序")"
            orderBtn.addTarget(self, action: #selector(orderTapped), for: .touchUpInside)
            orderBtn.translatesAutoresizingMaskIntoConstraints = false
            orderBtn.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
            rightStack.addArrangedSubview(orderBtn)
        }

        // "全部" Drawer Button
        let allBtn = UIButton(type: .custom)
        allBtn.accessibilityIdentifier = "detail.chapter.all"
        allBtn.setTitle("全部", for: .normal)
        allBtn.setTitleColor(Palette.text2, for: .normal)
        allBtn.titleLabel?.font = .systemFont(ofSize: 12)
        if #available(iOS 13.0, *) {
            let chevron = UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate)
            allBtn.setImage(chevron, for: .normal)
            allBtn.tintColor = Palette.text3
            allBtn.semanticContentAttribute = .forceRightToLeft
            allBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: -3)
        }
        allBtn.accessibilityLabel = "打开全部章节抽屉"
        allBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 0)
        allBtn.addTarget(self, action: #selector(openDrawerTapped), for: .touchUpInside)
        rightStack.addArrangedSubview(allBtn)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            titleStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),

            rightStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    // MARK: - Segment Bar

    private func buildSegmentBar(segments: [Segment], activeIdx: Int, autoScroll: Bool) -> UIView {
        let scroller = UIScrollView()
        scroller.accessibilityIdentifier = "detail.chapter.segments"
        scroller.showsHorizontalScrollIndicator = false
        scroller.showsVerticalScrollIndicator = false
        scroller.bounces = true
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.heightAnchor.constraint(equalToConstant: 30).isActive = true
        activeSegmentScroller = scroller

        let rowStack = UIStackView()
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 6
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: scroller.topAnchor),
            rowStack.leadingAnchor.constraint(equalTo: scroller.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: scroller.trailingAnchor),
            rowStack.bottomAnchor.constraint(equalTo: scroller.bottomAnchor),
            rowStack.heightAnchor.constraint(equalTo: scroller.heightAnchor)
        ])

        var targetButton: UIButton?

        for (i, seg) in segments.enumerated() {
            let selected = (i == activeIdx)
            let tab = UIButton(type: .custom)
            tab.tag = seg.index
            tab.setTitle(seg.label, for: .normal)
            tab.titleLabel?.font = .systemFont(ofSize: 12, weight: selected ? .bold : .regular)
            tab.setTitleColor(selected ? Palette.accent : Palette.text3, for: .normal)
            tab.backgroundColor = selected ? Palette.accentSoft : .clear
            tab.layer.cornerRadius = 13
            tab.clipsToBounds = true
            tab.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            tab.translatesAutoresizingMaskIntoConstraints = false
            tab.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
            tab.addTarget(self, action: #selector(segmentTapped(_:)), for: .touchUpInside)

            rowStack.addArrangedSubview(tab)
            if selected {
                targetButton = tab
            }
        }

        let savedOffset = segmentScrollX
        DispatchQueue.main.async { [weak scroller, weak targetButton] in
            guard let scroller = scroller else { return }
            if autoScroll, let target = targetButton, scroller.bounds.width > 0 {
                let targetCenter = target.frame.midX
                let scrollX = max(0, min(targetCenter - scroller.bounds.width / 2, scroller.contentSize.width - scroller.bounds.width))
                scroller.setContentOffset(CGPoint(x: scrollX, y: 0), animated: false)
            } else if savedOffset > 0 {
                scroller.setContentOffset(CGPoint(x: savedOffset, y: 0), animated: false)
            }
        }

        return scroller
    }

    // MARK: - Chapter Grid

    private func buildChapterGrid(visibleIndices: [Int], columns: Int) -> UIView {
        let gridStack = UIStackView()
        gridStack.axis = .vertical
        gridStack.alignment = .fill
        gridStack.distribution = .fillEqually
        gridStack.spacing = 8
        gridStack.translatesAutoresizingMaskIntoConstraints = false

        let rowCount = (visibleIndices.count + columns - 1) / columns

        for r in 0..<rowCount {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually
            rowStack.spacing = 8
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            rowStack.heightAnchor.constraint(equalToConstant: 36).isActive = true

            for c in 0..<columns {
                let itemIndex = r * columns + c
                if itemIndex < visibleIndices.count {
                    let chIdx = visibleIndices[itemIndex]
                    let chapter = chapters[chIdx]
                    let cell = buildChapterCell(chapter: chapter, index: chIdx)
                    rowStack.addArrangedSubview(cell)
                } else {
                    let spacer = UIView()
                    rowStack.addArrangedSubview(spacer)
                }
            }
            gridStack.addArrangedSubview(rowStack)
        }

        return gridStack
    }

    private func buildChapterCell(chapter: Chapter, index: Int) -> UIButton {
        let isCurrent = hasCurrent && (index == currentChapterIndex)
        let isRead = hasCurrent && (index < currentChapterIndex)
        let isDownloaded = downloadedChapterIds.contains(chapter.chapterId)
        let title = DetailChapterSection.cleanChapterTitle(chapter: chapter, index: index)

        let btn = UIButton(type: .custom)
        btn.tag = index
        btn.accessibilityIdentifier = "chapter.cell.\(index)"
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12, weight: isCurrent ? .bold : .regular)
        btn.titleLabel?.lineBreakMode = .byTruncatingTail
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)

        if isCurrent {
            btn.setTitleColor(Palette.accent, for: .normal)
            btn.backgroundColor = Palette.accentSoft
            btn.layer.borderColor = Palette.accent.cgColor
            btn.layer.borderWidth = 1.0
        } else if isRead {
            btn.setTitleColor(Palette.text3, for: .normal)
            btn.backgroundColor = Palette.surface
            btn.layer.borderColor = UIColor.clear.cgColor
            btn.layer.borderWidth = 0
        } else {
            btn.setTitleColor(Palette.text, for: .normal)
            btn.backgroundColor = Palette.surface
            btn.layer.borderColor = UIColor.clear.cgColor
            btn.layer.borderWidth = 0
        }
        btn.layer.cornerRadius = 8
        btn.clipsToBounds = true

        var desc = title
        if isCurrent { desc += "，当前阅读章节" }
        if isDownloaded { desc += "，已下载" }
        if isRead { desc += "，已读" }
        btn.accessibilityLabel = desc

        // Small badge indicator for downloaded chapter
        if isDownloaded {
            let badge = UIView()
            badge.backgroundColor = Palette.accent
            badge.layer.cornerRadius = 3
            badge.clipsToBounds = true
            badge.isUserInteractionEnabled = false
            badge.translatesAutoresizingMaskIntoConstraints = false
            btn.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: btn.topAnchor, constant: 4),
                badge.trailingAnchor.constraint(equalTo: btn.trailingAnchor, constant: -4),
                badge.widthAnchor.constraint(equalToConstant: 6),
                badge.heightAnchor.constraint(equalToConstant: 6)
            ])
        }

        btn.addTarget(self, action: #selector(chapterCellTapped(_:)), for: .touchUpInside)
        return btn
    }

    // MARK: - Footer Row (Expand / Collapse)

    private func buildFooterRow(activeSegment: Segment) -> UIView {
        let footerBtn = UIButton(type: .custom)
        footerBtn.accessibilityIdentifier = "detail.chapter.expand"
        let label = isExpanded ? "收起章节" : "展开更多章节"
        footerBtn.setTitle(label, for: .normal)
        footerBtn.setTitleColor(Palette.accent, for: .normal)
        footerBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)

        if #available(iOS 13.0, *) {
            let chevronSystemName = isExpanded ? "chevron.up" : "chevron.down"
            let chevron = UIImage(systemName: chevronSystemName)?.withRenderingMode(.alwaysTemplate)
            footerBtn.setImage(chevron, for: .normal)
            footerBtn.tintColor = Palette.accent
            footerBtn.semanticContentAttribute = .forceRightToLeft
            footerBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        }

        footerBtn.accessibilityLabel = label
        footerBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        footerBtn.translatesAutoresizingMaskIntoConstraints = false
        footerBtn.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        footerBtn.addTarget(self, action: #selector(footerToggleTapped), for: .touchUpInside)

        return footerBtn
    }

    // MARK: - Loading, Error & Empty Bodies

    private func buildLoadingBody() -> UIView {
        let wrap = UIStackView()
        wrap.axis = .vertical
        wrap.alignment = .fill
        wrap.distribution = .fillEqually
        wrap.spacing = 8
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let cols = resolveColumns()
        let rows = DetailChapterSection.previewLimit / max(1, cols)

        for _ in 0..<rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.distribution = .fillEqually
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 36).isActive = true

            for _ in 0..<cols {
                let cell = UILabel()
                cell.text = "···"
                cell.font = .systemFont(ofSize: 12)
                cell.textColor = Palette.text3
                cell.textAlignment = .center
                cell.backgroundColor = Palette.surface
                cell.layer.cornerRadius = 8
                cell.clipsToBounds = true
                row.addArrangedSubview(cell)
            }
            wrap.addArrangedSubview(row)
        }
        return wrap
    }

    private func buildErrorBody() -> UIView {
        let row = UIView()
        row.backgroundColor = Palette.surface
        row.layer.cornerRadius = 8
        row.clipsToBounds = true
        row.translatesAutoresizingMaskIntoConstraints = false

        let msgLabel = UILabel()
        msgLabel.text = errorMessage.isEmpty ? "章节加载失败，可点击重试或打开全部目录" : errorMessage
        msgLabel.font = .systemFont(ofSize: 12)
        msgLabel.textColor = Palette.text2
        msgLabel.numberOfLines = 2
        msgLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(msgLabel)

        let retryBtn = UIButton(type: .custom)
        retryBtn.setTitle("重试", for: .normal)
        retryBtn.setTitleColor(Palette.accent, for: .normal)
        retryBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        retryBtn.backgroundColor = Palette.accentSoft
        retryBtn.layer.cornerRadius = 12
        retryBtn.clipsToBounds = true
        retryBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        retryBtn.translatesAutoresizingMaskIntoConstraints = false
        retryBtn.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        row.addSubview(retryBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            msgLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            msgLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            msgLabel.trailingAnchor.constraint(lessThanOrEqualTo: retryBtn.leadingAnchor, constant: -8),

            retryBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            retryBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            retryBtn.heightAnchor.constraint(equalToConstant: 24)
        ])

        return row
    }

    private func buildEmptyBody() -> UIView {
        let btn = UIButton(type: .system)
        btn.setTitle("点击加载章节目录", for: .normal)
        btn.setTitleColor(Palette.accent, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12)
        btn.contentHorizontalAlignment = .left
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        btn.addTarget(self, action: #selector(emptyTapped), for: .touchUpInside)
        return btn
    }

    // MARK: - Actions

    @objc private func orderTapped() {
        if let scroller = activeSegmentScroller {
            segmentScrollX = 0
            scroller.setContentOffset(.zero, animated: false)
        }
        isDesc.toggle()
        selectedSegmentIndex = -1
        onOrderChanged?(isDesc)
        render(autoScrollSegment: true)
    }

    @objc private func openDrawerTapped() {
        onOpenDrawer?()
    }

    @objc private func segmentTapped(_ sender: UIButton) {
        if selectedSegmentIndex == sender.tag { return }
        selectedSegmentIndex = sender.tag
        render(autoScrollSegment: false)
    }

    @objc private func chapterCellTapped(_ sender: UIButton) {
        let idx = sender.tag
        onSelectChapter?(idx)
    }

    @objc private func footerToggleTapped() {
        isExpanded.toggle()
        render(autoScrollSegment: false)
    }

    @objc private func retryTapped() {
        onRetry?()
    }

    @objc private func emptyTapped() {
        if let onRetry = onRetry {
            onRetry()
        } else {
            onOpenDrawer?()
        }
    }

    // MARK: - Column Resolution

    private func resolveColumns() -> Int {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        return width >= 600 ? 4 : 3
    }
}
