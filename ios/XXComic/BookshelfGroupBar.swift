import UIKit
import ComicCore

@MainActor
final class BookshelfGroupBar: UIView {
    private let scrollView = UIScrollView()
    private let tabsStack = UIStackView()
    private let addGroupButton = UIButton(type: .system)

    private var groups: [BookshelfGroup] = []
    private var selectedGroupId: String = BookshelfGroupStore.builtinOnlineAllId
    private var tabViews: [String: (container: UIView, title: UILabel, indicator: UIView)] = [:]

    var onGroupSelected: ((BookshelfGroup) -> Void)?
    var onManageGroups: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setupView() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        tabsStack.axis = .horizontal
        tabsStack.spacing = 16
        tabsStack.alignment = .center
        tabsStack.distribution = .fill
        tabsStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(tabsStack)

        addGroupButton.setImage(ParityIcon.plus.image(size: 18), for: .normal)
        addGroupButton.tintColor = Palette.text2
        addGroupButton.accessibilityLabel = "分组管理"
        addGroupButton.accessibilityIdentifier = "bookshelf.groups"
        let disc = UIView()
        disc.backgroundColor = Palette.cardSoft; disc.layer.cornerRadius = 15
        disc.layer.zPosition = -1
        disc.isUserInteractionEnabled = false; disc.translatesAutoresizingMaskIntoConstraints = false
        addGroupButton.insertSubview(disc, at: 0)
        NSLayoutConstraint.activate([
            disc.centerXAnchor.constraint(equalTo: addGroupButton.centerXAnchor),
            disc.centerYAnchor.constraint(equalTo: addGroupButton.centerYAnchor),
            disc.widthAnchor.constraint(equalToConstant: 30), disc.heightAnchor.constraint(equalToConstant: 30)
        ])
        addGroupButton.translatesAutoresizingMaskIntoConstraints = false
        addGroupButton.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)
        addSubview(addGroupButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: addGroupButton.leadingAnchor, constant: -4),

            tabsStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            tabsStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            tabsStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 4),
            tabsStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -4),
            tabsStack.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            addGroupButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addGroupButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            addGroupButton.widthAnchor.constraint(equalToConstant: 36),
            addGroupButton.heightAnchor.constraint(equalToConstant: 36),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
    }

    @objc private func plusTapped() {
        onManageGroups?()
    }

    func configure(groups: [BookshelfGroup], selectedId: String) {
        self.groups = groups
        self.selectedGroupId = selectedId

        tabsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        for group in groups {
            let isSelected = (group.id == selectedId)

            let container = UIView()
            container.isUserInteractionEnabled = true

            let titleLabel = UILabel()
            titleLabel.text = group.name
            titleLabel.font = isSelected ? .systemFont(ofSize: 15, weight: .bold) : .systemFont(ofSize: 15, weight: .medium)
            titleLabel.textColor = isSelected ? Palette.accent : Palette.text2
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(titleLabel)

            let indicator = UIView()
            indicator.backgroundColor = Palette.accent
            indicator.layer.cornerRadius = 1.5
            indicator.isHidden = !isSelected
            indicator.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(indicator)

            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
                titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 4),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -4),

                indicator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
                indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 20),
                indicator.heightAnchor.constraint(equalToConstant: 3),
                indicator.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
            ])

            let tap = UITapGestureRecognizer(target: self, action: #selector(tabTapped(_:)))
            container.addGestureRecognizer(tap)
            container.tag = groups.firstIndex(where: { $0.id == group.id }) ?? 0

            tabsStack.addArrangedSubview(container)
            tabViews[group.id] = (container, titleLabel, indicator)
        }

        scrollToSelectedTab(animated: false)
    }

    @objc private func tabTapped(_ sender: UITapGestureRecognizer) {
        guard let view = sender.view, view.tag < groups.count else { return }
        let group = groups[view.tag]
        selectGroup(id: group.id, animated: true)
        onGroupSelected?(group)
    }

    func selectGroup(id: String, animated: Bool) {
        selectedGroupId = id
        for (groupId, views) in tabViews {
            let isSelected = (groupId == id)
            views.title.font = isSelected ? .systemFont(ofSize: 15, weight: .bold) : .systemFont(ofSize: 15, weight: .medium)
            views.title.textColor = isSelected ? Palette.accent : Palette.text2
            views.indicator.isHidden = !isSelected
        }
        scrollToSelectedTab(animated: animated)
    }

    private func scrollToSelectedTab(animated: Bool) {
        guard let views = tabViews[selectedGroupId] else { return }
        layoutIfNeeded()
        let rect = views.container.convert(views.container.bounds, to: scrollView)
        scrollView.scrollRectToVisible(rect.insetBy(dx: -20, dy: 0), animated: animated)
    }
}
