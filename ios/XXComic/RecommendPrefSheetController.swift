import UIKit
import ComicCore

@MainActor
final class RecommendPrefSheetController: UIViewController {
    private let environment: AppEnvironment
    private let availableGenres: [String]
    var onChanged: (() -> Void)?

    private let backdropView = UIView()
    private let panelView = UIView()
    private let dragHandle = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let personalizationSwitch = UISwitch()
    private let genreContainer = DiscoveryChipFlowContainer(maxWidth: 320)
    private var genreButtons: [String: UIButton] = [:]

    private let dislikedHeaderButton = UIButton(type: .system)
    private let dislikedTitleLabel = UILabel()
    private let dislikedChevron = UIImageView()
    private let dislikedListStack = UIStackView()
    private let resetDislikedButton = UIButton(type: .system)
    private var isDislikedExpanded = false

    private let blacklistRowButton = UIButton(type: .system)
    private let blacklistCountLabel = UILabel()

    private var panelBottomConstraint: NSLayoutConstraint!
    private var panelWidthConstraint: NSLayoutConstraint!
    private var panelHeightConstraint: NSLayoutConstraint!
    private var isClosing = false

    init(
        environment: AppEnvironment,
        availableGenres: [String] = [],
        onChanged: (() -> Void)? = nil
    ) {
        self.environment = environment
        self.availableGenres = availableGenres
        self.onChanged = onChanged
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
        refreshState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePanelDimensions()
        refreshState()
        animateIn()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePanelDimensions()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        panelView.layer.borderColor = Palette.borderSoft.cgColor
    }

    private func setupUI() {
        backdropView.backgroundColor = Palette.scrim
        backdropView.alpha = 0
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        view.addSubview(backdropView)

        panelView.backgroundColor = Palette.background
        panelView.layer.cornerRadius = 16
        panelView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panelView.layer.borderWidth = 0.5
        panelView.layer.borderColor = Palette.borderSoft.cgColor
        panelView.clipsToBounds = true
        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.accessibilityIdentifier = "recommend.pref.sheet"
        view.addSubview(panelView)

        dragHandle.backgroundColor = Palette.border
        dragHandle.layer.cornerRadius = 2
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(dragHandle)

        titleLabel.text = "推荐偏好"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = Palette.text

        subtitleLabel.text = "管理个性化题材、不感兴趣屏蔽与推荐重置"
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = Palette.secondaryText

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        closeButton.setImage(ParityIcon.close.image(size: 15), for: .normal)
        closeButton.tintColor = Palette.secondaryText
        closeButton.backgroundColor = Palette.surface
        closeButton.layer.cornerRadius = 15
        closeButton.accessibilityIdentifier = "recommend.pref.close"
        closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [titleStack, UIView(), closeButton])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 10
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(headerRow)

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(buildPersonalizationCard())
        contentStack.addArrangedSubview(buildGenreCard())
        contentStack.addArrangedSubview(buildDislikedCard())
        contentStack.addArrangedSubview(buildManagementCard())

        panelWidthConstraint = panelView.widthAnchor.constraint(equalToConstant: view.bounds.width)
        panelHeightConstraint = panelView.heightAnchor.constraint(equalToConstant: 520)
        panelBottomConstraint = panelView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 700)

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panelView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panelBottomConstraint,
            panelWidthConstraint,
            panelHeightConstraint,

            dragHandle.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 10),
            dragHandle.centerXAnchor.constraint(equalTo: panelView.centerXAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 36),
            dragHandle.heightAnchor.constraint(equalToConstant: 4),

            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            headerRow.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: 10),
            headerRow.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 16),
            headerRow.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: panelView.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -18),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panelView.addGestureRecognizer(pan)
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 0.5
        card.layer.borderColor = Palette.borderSoft.cgColor
        return card
    }

    private func buildPersonalizationCard() -> UIView {
        let card = makeCard()
        let title = UILabel()
        title.text = "个性化推荐"
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = Palette.text

        let desc = UILabel()
        desc.text = "结合书架收藏、浏览记录与题材偏好动态排序；关闭后停止学习与个性化排序"
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = Palette.secondaryText
        desc.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [title, desc])
        textStack.axis = .vertical
        textStack.spacing = 4

        personalizationSwitch.onTintColor = Palette.accent
        personalizationSwitch.accessibilityIdentifier = "recommend.pref.personalizationSwitch"
        personalizationSwitch.addTarget(self, action: #selector(personalizationChanged), for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [textStack, personalizationSwitch])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func buildGenreCard() -> UIView {
        let card = makeCard()
        let title = UILabel()
        title.text = "偏好题材"
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = Palette.text

        let hint = UILabel()
        hint.text = "选择感兴趣的题材，推荐流将优先匹配相关作品"
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = Palette.secondaryText
        hint.numberOfLines = 0

        var orderedGenres: [String] = []
        var seen = Set<String>()
        for g in RecommendSourceClassifier.canonicalGenres + availableGenres {
            let trimmed = g.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && seen.insert(trimmed).inserted {
                orderedGenres.append(trimmed)
            }
        }
        genreButtons.removeAll()
        genreContainer.clearChips()
        for genre in orderedGenres {
            let btn = UIButton(type: .system)
            btn.setTitle(genre, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.layer.cornerRadius = 15
            btn.layer.borderWidth = 0.5
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            btn.accessibilityIdentifier = "recommend.pref.genre.\(genre)"
            btn.addAction(UIAction { [weak self] _ in
                self?.toggleGenre(genre)
            }, for: .touchUpInside)
            genreButtons[genre] = btn
            genreContainer.addChip(btn)
        }

        let stack = UIStackView(arrangedSubviews: [title, hint, genreContainer])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func buildDislikedCard() -> UIView {
        let card = makeCard()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        dislikedTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        dislikedTitleLabel.textColor = Palette.text

        dislikedChevron.image = ParityIcon.chevronDown.image(size: 13)
        dislikedChevron.tintColor = Palette.secondaryText

        let headerRow = UIStackView(arrangedSubviews: [dislikedTitleLabel, UIView(), dislikedChevron])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.isUserInteractionEnabled = false
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        dislikedHeaderButton.accessibilityIdentifier = "recommend.pref.dislikedToggle"
        dislikedHeaderButton.addTarget(self, action: #selector(toggleDislikedSection), for: .touchUpInside)
        dislikedHeaderButton.addSubview(headerRow)
        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: dislikedHeaderButton.topAnchor, constant: 2),
            headerRow.leadingAnchor.constraint(equalTo: dislikedHeaderButton.leadingAnchor),
            headerRow.trailingAnchor.constraint(equalTo: dislikedHeaderButton.trailingAnchor),
            headerRow.bottomAnchor.constraint(equalTo: dislikedHeaderButton.bottomAnchor, constant: -2),
            dislikedHeaderButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        ])

        dislikedListStack.axis = .vertical
        dislikedListStack.spacing = 8
        dislikedListStack.isHidden = true

        resetDislikedButton.setTitle("重置不感兴趣", for: .normal)
        resetDislikedButton.setTitleColor(Palette.danger, for: .normal)
        resetDislikedButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        resetDislikedButton.contentHorizontalAlignment = .leading
        resetDislikedButton.accessibilityIdentifier = "recommend.pref.resetDisliked"
        resetDislikedButton.addTarget(self, action: #selector(resetDislikedTapped), for: .touchUpInside)

        stack.addArrangedSubview(dislikedHeaderButton)
        stack.addArrangedSubview(dislikedListStack)
        stack.addArrangedSubview(resetDislikedButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func buildManagementCard() -> UIView {
        let card = makeCard()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        // Blacklist row
        let blTitle = UILabel()
        blTitle.text = "黑名单列表"
        blTitle.font = .systemFont(ofSize: 15, weight: .medium)
        blTitle.textColor = Palette.text

        blacklistCountLabel.font = .systemFont(ofSize: 13)
        blacklistCountLabel.textColor = Palette.secondaryText

        let chevron = UIImageView(image: ParityIcon.chevronRight.image(size: 13))
        chevron.tintColor = Palette.text3

        let blRow = UIStackView(arrangedSubviews: [blTitle, UIView(), blacklistCountLabel, chevron])
        blRow.axis = .horizontal
        blRow.alignment = .center
        blRow.spacing = 6
        blRow.isUserInteractionEnabled = false
        blRow.translatesAutoresizingMaskIntoConstraints = false

        blacklistRowButton.accessibilityIdentifier = "recommend.pref.blacklist"
        blacklistRowButton.addTarget(self, action: #selector(openBlacklistTapped), for: .touchUpInside)
        blacklistRowButton.addSubview(blRow)
        NSLayoutConstraint.activate([
            blRow.topAnchor.constraint(equalTo: blacklistRowButton.topAnchor, constant: 10),
            blRow.leadingAnchor.constraint(equalTo: blacklistRowButton.leadingAnchor),
            blRow.trailingAnchor.constraint(equalTo: blacklistRowButton.trailingAnchor),
            blRow.bottomAnchor.constraint(equalTo: blacklistRowButton.bottomAnchor, constant: -10),
            blacklistRowButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        let divider1 = makeDivider()
        let clearImpBtn = makeActionRow(title: "清除推荐曝光", color: Palette.text, identifier: "recommend.pref.clearImpressions", action: #selector(clearImpressionsTapped))
        let divider2 = makeDivider()
        let resetAllBtn = makeActionRow(title: "重置推荐学习数据", color: Palette.danger, identifier: "recommend.pref.resetLearning", action: #selector(resetLearningTapped))

        stack.addArrangedSubview(blacklistRowButton)
        stack.addArrangedSubview(divider1)
        stack.addArrangedSubview(clearImpBtn)
        stack.addArrangedSubview(divider2)
        stack.addArrangedSubview(resetAllBtn)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4)
        ])
        return card
    }

    private func makeDivider() -> UIView {
        let line = UIView()
        line.backgroundColor = Palette.borderSoft
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return line
    }

    private func makeActionRow(title: String, color: UIColor, identifier: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(color, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        btn.contentHorizontalAlignment = .leading
        btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        btn.accessibilityIdentifier = identifier
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func updatePanelDimensions() {
        let maxW: CGFloat = traitCollection.horizontalSizeClass == .regular ? 600 : view.bounds.width
        panelWidthConstraint.constant = min(view.bounds.width, maxW)
        panelHeightConstraint.constant = min(max(360, view.bounds.height * 0.84), 680)
    }

    private func animateIn() {
        panelBottomConstraint.constant = 0
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.backdropView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    private func animateOut(completion: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        panelBottomConstraint.constant = panelHeightConstraint.constant + 40
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
            self.backdropView.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }

    private func refreshState() {
        let store = environment.recommendProfileStore
        personalizationSwitch.isOn = store.isPersonalizationEnabled

        let selectedGenres = Set(store.getSelectedGenres())
        for (genre, btn) in genreButtons {
            let active = selectedGenres.contains(genre)
            btn.backgroundColor = active ? Palette.accent : Palette.surface
            btn.setTitleColor(active ? Palette.onAccent : Palette.text, for: .normal)
            btn.layer.borderColor = (active ? Palette.accent : Palette.borderSoft).cgColor
        }

        let disliked = store.listDisliked()
        dislikedTitleLabel.text = "不感兴趣管理 (\(disliked.count))"
        resetDislikedButton.isHidden = disliked.isEmpty
        dislikedListStack.isHidden = !isDislikedExpanded
        dislikedChevron.transform = isDislikedExpanded ? CGAffineTransform(rotationAngle: .pi) : .identity

        dislikedListStack.arrangedSubviews.forEach {
            dislikedListStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if isDislikedExpanded {
            if disliked.isEmpty {
                let empty = UILabel()
                empty.text = "暂无“不感兴趣”的记录"
                empty.font = .systemFont(ofSize: 13)
                empty.textColor = Palette.secondaryText
                dislikedListStack.addArrangedSubview(empty)
            } else {
                for record in disliked {
                    dislikedListStack.addArrangedSubview(makeDislikedRow(record))
                }
            }
        }

        let blacklistCount = environment.blacklistStore.size
        blacklistCountLabel.text = "\(blacklistCount) 部"
    }

    private func makeDislikedRow(_ record: DislikedRecord) -> UIView {
        let title = UILabel()
        title.text = record.displayTitle
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = Palette.text
        title.lineBreakMode = .byTruncatingTail

        var metaParts: [String] = []
        if !record.author.isEmpty { metaParts.append(record.author) }
        if !record.genres.isEmpty { metaParts.append(record.genres.prefix(2).joined(separator: "·")) }
        let meta = UILabel()
        meta.text = metaParts.isEmpty ? "已减少此类推荐" : metaParts.joined(separator: " · ")
        meta.font = .systemFont(ofSize: 11)
        meta.textColor = Palette.secondaryText

        let textStack = UIStackView(arrangedSubviews: [title, meta])
        textStack.axis = .vertical
        textStack.spacing = 2

        let removeBtn = UIButton(type: .system)
        removeBtn.setTitle("移除", for: .normal)
        removeBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        removeBtn.setTitleColor(Palette.accentText, for: .normal)
        removeBtn.backgroundColor = Palette.accentSoft
        removeBtn.layer.cornerRadius = 12
        removeBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        removeBtn.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            _ = self.environment.recommendProfileStore.removeDislike(record.normalizedTitle)
            self.notifyProfileChanged()
            self.refreshState()
        }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [textStack, removeBtn])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        removeBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func notifyProfileChanged() {
        NotificationCenter.default.post(name: AppEnvironment.recommendProfileChanged, object: nil)
        onChanged?()
    }

    @objc private func personalizationChanged() {
        environment.recommendProfileStore.setPersonalizationEnabled(personalizationSwitch.isOn)
        notifyProfileChanged()
    }

    private func toggleGenre(_ genre: String) {
        _ = environment.recommendProfileStore.togglePreferredGenre(genre)
        refreshState()
        notifyProfileChanged()
    }

    @objc private func toggleDislikedSection() {
        isDislikedExpanded.toggle()
        refreshState()
    }

    @objc private func resetDislikedTapped() {
        let disliked = environment.recommendProfileStore.listDisliked()
        guard !disliked.isEmpty else { return }
        let alert = UIAlertController(
            title: "重置不感兴趣",
            message: "将移除全部 \(disliked.count) 条“不感兴趣”记录，确定继续吗？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重置", style: .destructive) { [weak self] _ in
            guard let self else { return }
            for entry in disliked {
                _ = self.environment.recommendProfileStore.removeDislike(entry.normalizedTitle)
            }
            self.refreshState()
            self.notifyProfileChanged()
            RemToastView.show(message: "已清空不感兴趣记录", kind: .info, window: self.view.window)
        })
        present(alert, animated: true)
    }

    @objc private func openBlacklistTapped() {
        let controller = BlacklistSettingsViewController(environment: environment)
        let nav = UINavigationController(rootViewController: controller)
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak nav] _ in
            nav?.dismiss(animated: true)
        })
        present(nav, animated: true)
    }

    @objc private func clearImpressionsTapped() {
        environment.recommendHarvester.clearFeedCache()
        notifyProfileChanged()
        RemToastView.show(message: "已清除推荐缓存与曝光记录", kind: .info, window: view.window)
    }

    @objc private func resetLearningTapped() {
        let alert = UIAlertController(
            title: "重置推荐学习数据",
            message: "将清空偏好题材、点击权重、曝光历史与不感兴趣记录，并重新生成推荐。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重置", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.environment.recommendProfileStore.resetLearningData()
            self.environment.recommendHarvester.clearFeedCache()
            self.refreshState()
            self.notifyProfileChanged()
            RemToastView.show(message: "推荐学习数据已重置", kind: .info, window: self.view.window)
        })
        present(alert, animated: true)
    }

    @objc private func dismissTapped() {
        animateOut()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: panelView)
        switch gesture.state {
        case .changed:
            if translation.y > 0 {
                panelBottomConstraint.constant = translation.y
            }
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: panelView).y
            if translation.y > 120 || velocity > 800 {
                animateOut()
            } else {
                panelBottomConstraint.constant = 0
                UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
            }
        default:
            break
        }
    }
}
