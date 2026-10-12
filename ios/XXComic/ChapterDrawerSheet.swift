import UIKit
import ComicCore

/// Bottom sheet chapter catalog drawer aligned 1:1 with Android 2.0.40's `ChapterDrawerSheet`.
/// Two-stage height (starts half-screen ~55%, expands to ~92%), order toggle (正序/倒序),
/// left vertical blue indicator bar (▌) on current chapter, fast scroller, and NO search box.
@MainActor
final class ChapterDrawerSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let chapters: [Chapter]
    private let currentChapterIndex: Int
    private let hasCurrent: Bool
    private let isReader: Bool
    private let isDarkReader: Bool
    private var isDesc: Bool
    private let onOrderChanged: ((Bool) -> Void)?
    private let onChapterSelected: (Int) -> Void

    private var orderIndexes: [Int] = []
    private let backdrop = UIButton(type: .custom)
    private let panel = UIView()
    private let handle = UIView()
    private let headerTitle = UILabel()
    private let orderBtn = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var fastScroller: ChapterFastScroller?

    private var collapsedHeight: CGFloat = 0
    private var expandedHeight: CGFloat = 0
    private var panelHeightConstraint: NSLayoutConstraint?
    private var panelBottomConstraint: NSLayoutConstraint?
    private var isExpanded = false

    init(
        chapters: [Chapter],
        currentChapterIndex: Int,
        hasCurrent: Bool,
        isReader: Bool = true,
        isDarkReader: Bool = true,
        isDesc: Bool = false,
        onOrderChanged: ((Bool) -> Void)? = nil,
        onChapterSelected: @escaping (Int) -> Void
    ) {
        self.chapters = chapters
        self.currentChapterIndex = currentChapterIndex
        self.hasCurrent = hasCurrent
        self.isReader = isReader
        self.isDarkReader = isDarkReader
        self.isDesc = isDesc
        self.onOrderChanged = onOrderChanged
        self.onChapterSelected = onChapterSelected
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        rebuildOrderIndexes()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func rebuildOrderIndexes() {
        let indices = Array(0..<chapters.count)
        orderIndexes = isDesc ? indices.reversed() : indices
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let screenHeight = view.bounds.height > 0 ? view.bounds.height : UIScreen.main.bounds.height
        collapsedHeight = round(screenHeight * 0.55)
        expandedHeight = round(screenHeight * 0.92)

        // Backdrop
        backdrop.backgroundColor = isReader
            ? (isDarkReader ? UIColor(white: 0, alpha: 0.51) : UIColor(white: 0, alpha: 0.35))
            : UIColor(red: 10/255, green: 24/255, blue: 37/255, alpha: 0.43)
        backdrop.alpha = 0
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)
        backdrop.accessibilityLabel = "关闭目录"
        backdrop.accessibilityIdentifier = "chapter.drawer.dismiss"
        backdrop.addTarget(self, action: #selector(dismissSheet), for: .touchUpInside)

        // Panel
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer.cornerRadius = 16
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.layer.masksToBounds = true

        if isReader {
            panel.backgroundColor = isDarkReader
                ? UIColor(red: 28/255, green: 33/255, blue: 40/255, alpha: 0.94) // #1C2128
                : UIColor(white: 1.0, alpha: 0.97)
        } else {
            panel.backgroundColor = Palette.card
        }
        view.addSubview(panel)

        // Handle host
        let handleHost = UIView()
        handleHost.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(handleHost)

        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.backgroundColor = isReader
            ? (isDarkReader ? UIColor(red: 68/255, green: 76/255, blue: 86/255, alpha: 1.0) : UIColor(red: 208/255, green: 215/255, blue: 222/255, alpha: 1.0))
            : Palette.border
        handle.layer.cornerRadius = 2
        handleHost.addSubview(handle)

        let tapHandle = UITapGestureRecognizer(target: self, action: #selector(toggleHeight))
        handleHost.addGestureRecognizer(tapHandle)

        // Header
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(header)

        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.text = "全部章节"
        headerTitle.font = .boldSystemFont(ofSize: 16)
        headerTitle.textColor = isReader
            ? (isDarkReader ? UIColor(red: 230/255, green: 237/255, blue: 243/255, alpha: 1.0) : UIColor(red: 31/255, green: 35/255, blue: 40/255, alpha: 1.0))
            : Palette.text
        header.addSubview(headerTitle)

        orderBtn.translatesAutoresizingMaskIntoConstraints = false
        orderBtn.accessibilityIdentifier = "chapter.drawer.order"
        orderBtn.setTitle(isDesc ? "倒序" : "正序", for: .normal)
        orderBtn.titleLabel?.font = .systemFont(ofSize: 12)
        let btnTextColor = isReader
            ? (isDarkReader ? UIColor(red: 139/255, green: 148/255, blue: 158/255, alpha: 1.0) : UIColor(red: 101/255, green: 109/255, blue: 118/255, alpha: 1.0))
            : Palette.secondaryText
        orderBtn.setTitleColor(btnTextColor, for: .normal)
        orderBtn.backgroundColor = isReader
            ? (isDarkReader ? UIColor(white: 1.0, alpha: 0.15) : UIColor(black: 0.08))
            : Palette.cardSoft
        orderBtn.layer.cornerRadius = 14
        orderBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        orderBtn.addTarget(self, action: #selector(toggleOrder), for: .touchUpInside)
        header.addSubview(orderBtn)

        // TableView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.accessibilityIdentifier = "chapter.drawer.list"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.register(ChapterRowCell.self, forCellReuseIdentifier: "ChapterRowCell")
        panel.addSubview(tableView)

        // Fast Scroller
        let scroller = ChapterFastScroller(tableView: tableView)
        scroller.accessibilityIdentifier = "chapter.drawer.fast-scroll"
        scroller.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroller)
        fastScroller = scroller

        // Pan gesture for dragging panel
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panel.addGestureRecognizer(pan)

        panelHeightConstraint = panel.heightAnchor.constraint(equalToConstant: collapsedHeight)
        panelBottomConstraint = panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: collapsedHeight)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panelHeightConstraint!,
            panelBottomConstraint!,

            handleHost.topAnchor.constraint(equalTo: panel.topAnchor),
            handleHost.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            handleHost.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            handleHost.heightAnchor.constraint(equalToConstant: 24),

            handle.centerXAnchor.constraint(equalTo: handleHost.centerXAnchor),
            handle.centerYAnchor.constraint(equalTo: handleHost.centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: 32),
            handle.heightAnchor.constraint(equalToConstant: 4),

            header.topAnchor.constraint(equalTo: handleHost.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            header.heightAnchor.constraint(equalToConstant: 40),

            headerTitle.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerTitle.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            orderBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            orderBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            orderBtn.heightAnchor.constraint(equalToConstant: 28),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: scroller.leadingAnchor),
            tableView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),

            scroller.topAnchor.constraint(equalTo: tableView.topAnchor),
            scroller.trailingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.trailingAnchor),
            scroller.widthAnchor.constraint(equalToConstant: 44),
            scroller.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        panelBottomConstraint?.constant = 0
        UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut) {
            self.backdrop.alpha = 1.0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.scrollToCurrentChapter()
        }
    }

    private func scrollToCurrentChapter() {
        guard hasCurrent, let row = orderIndexes.firstIndex(of: currentChapterIndex) else { return }
        let indexPath = IndexPath(row: row, section: 0)
        tableView.scrollToRow(at: indexPath, at: .top, animated: false)
    }

    @objc private func toggleOrder() {
        isDesc.toggle()
        onOrderChanged?(isDesc)
        orderBtn.setTitle(isDesc ? "倒序" : "正序", for: .normal)
        rebuildOrderIndexes()
        tableView.reloadData()
        scrollToCurrentChapter()
    }

    @objc private func toggleHeight() {
        setPanelHeight(isExpanded ? collapsedHeight : expandedHeight)
        isExpanded.toggle()
    }

    private func setPanelHeight(_ height: CGFloat) {
        panelHeightConstraint?.constant = height
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        let currentH = panelHeightConstraint?.constant ?? collapsedHeight
        switch recognizer.state {
        case .changed:
            if translation.y < 0 { // dragging up
                let newH = min(expandedHeight, currentH - translation.y)
                panelHeightConstraint?.constant = newH
            } else if translation.y > 0 && currentH <= collapsedHeight { // dragging down to dismiss
                panelBottomConstraint?.constant = translation.y
            }
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: view)
            if velocity.y > 400 || (panelBottomConstraint?.constant ?? 0) > 100 {
                dismissSheet()
            } else if velocity.y < -300 {
                setPanelHeight(expandedHeight)
                isExpanded = true
            } else {
                panelBottomConstraint?.constant = 0
                if (panelHeightConstraint?.constant ?? 0) > (collapsedHeight + expandedHeight) / 2 {
                    setPanelHeight(expandedHeight)
                    isExpanded = true
                } else {
                    setPanelHeight(collapsedHeight)
                    isExpanded = false
                }
            }
        default: break
        }
    }

    @objc private func dismissSheet() {
        panelBottomConstraint?.constant = panelHeightConstraint?.constant ?? collapsedHeight
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseIn) {
            self.backdrop.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }

    // MARK: - UITableViewDataSource & Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return orderIndexes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChapterRowCell", for: indexPath) as! ChapterRowCell
        let chapterIndex = orderIndexes[indexPath.row]
        let chapter = chapters[chapterIndex]
        let isCurrent = hasCurrent && (chapterIndex == currentChapterIndex)
        cell.configure(
            title: chapter.title,
            isCurrent: isCurrent,
            isReader: isReader,
            isDarkReader: isDarkReader
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let chapterIndex = orderIndexes[indexPath.row]
        dismissSheet()
        onChapterSelected(chapterIndex)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        fastScroller?.setNeedsDisplay()
    }
}

private extension UIColor {
    convenience init(black alpha: CGFloat) {
        self.init(white: 0, alpha: alpha)
    }
}

// MARK: - ChapterRowCell

private final class ChapterRowCell: UITableViewCell {
    private let indicator = UIView()
    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.layer.cornerRadius = 2
        contentView.addSubview(indicator)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.numberOfLines = 1
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),

            indicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            indicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 3.5),
            indicator.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func configure(title: String, isCurrent: Bool, isReader: Bool, isDarkReader: Bool) {
        titleLabel.text = title
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = isCurrent ? [.selected] : []

        let indicatorColor = isReader && !isDarkReader
            ? UIColor(red: 9/255, green: 105/255, blue: 218/255, alpha: 1.0) // #0969DA
            : UIColor(red: 46/255, green: 121/255, blue: 230/255, alpha: 1.0) // #2E79E6
        indicator.backgroundColor = indicatorColor
        indicator.isHidden = !isCurrent

        if isCurrent {
            titleLabel.textColor = isReader && isDarkReader ? .white : indicatorColor
            titleLabel.font = .boldSystemFont(ofSize: 14)
        } else {
            titleLabel.textColor = isReader
                ? (isDarkReader ? UIColor(red: 230/255, green: 237/255, blue: 243/255, alpha: 1.0) : UIColor(red: 31/255, green: 35/255, blue: 40/255, alpha: 1.0))
                : Palette.text
            titleLabel.font = .systemFont(ofSize: 14)
        }
    }
}
