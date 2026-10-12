import UIKit

/// The application owns the same vertical tab layout at every window size.
/// UIKit navigation controllers still manage each tab's push/pop stack.
@MainActor
final class RootTabsViewController: UIViewController, UINavigationControllerDelegate {
    private let navigationControllers: [UINavigationController]
    private let bar: RootTabBar
    private(set) var selectedIndex = 0
    private var activeNavigation: UINavigationController { navigationControllers[selectedIndex] }
    private var hidesBar = false

    init(navigationControllers: [UINavigationController]) {
        precondition(!navigationControllers.isEmpty)
        self.navigationControllers = navigationControllers
        bar = RootTabBar(items: navigationControllers.map { $0.tabBarItem ?? UITabBarItem() })
        super.init(nibName: nil, bundle: nil)
        bar.onSelect = { [weak self] in self?.selectTab($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        for navigation in navigationControllers { navigation.delegate = self }
        attach(activeNavigation)
        view.addSubview(bar)
        updateBar(for: activeNavigation.topViewController)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let barHeight = RootTabBar.contentHeight + view.safeAreaInsets.bottom
        bar.frame = CGRect(x: 0, y: view.bounds.maxY - barHeight, width: view.bounds.width, height: barHeight)
        activeNavigation.view.frame = CGRect(x: 0, y: 0, width: view.bounds.width,
                                            height: hidesBar ? view.bounds.height : bar.frame.minY)
    }

    override var childForStatusBarHidden: UIViewController? { activeNavigation }
    override var childForStatusBarStyle: UIViewController? { activeNavigation }
    override var childForHomeIndicatorAutoHidden: UIViewController? { activeNavigation }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { activeNavigation.supportedInterfaceOrientations }
    override var shouldAutorotate: Bool { activeNavigation.shouldAutorotate }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard navigationController === activeNavigation else { return }
        updateBar(for: viewController)
        // Cancelled interactive pops must restore the source page's bar state.
        navigationController.transitionCoordinator?.animate(alongsideTransition: nil) { [weak self, weak navigationController] _ in
            guard let self, let navigationController, navigationController === self.activeNavigation else { return }
            self.updateBar(for: navigationController.topViewController)
        }
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        guard navigationController === activeNavigation else { return }
        updateBar(for: viewController)
    }

    private func selectTab(_ index: Int) {
        guard navigationControllers.indices.contains(index), index != selectedIndex else { return }
        let previous = activeNavigation
        previous.beginAppearanceTransition(false, animated: false)
        previous.willMove(toParent: nil)
        previous.view.removeFromSuperview()
        previous.removeFromParent()
        selectedIndex = index
        addChild(activeNavigation)
        activeNavigation.beginAppearanceTransition(true, animated: false)
        view.insertSubview(activeNavigation.view, at: 0)
        activeNavigation.didMove(toParent: self)
        bar.select(index, animated: true)
        updateBar(for: activeNavigation.topViewController)
        previous.endAppearanceTransition()
        activeNavigation.endAppearanceTransition()
    }

    private func attach(_ navigation: UINavigationController) {
        addChild(navigation)
        view.insertSubview(navigation.view, at: 0)
        navigation.didMove(toParent: self)
    }

    private func updateBar(for controller: UIViewController?) {
        hidesBar = controller?.hidesBottomBarWhenPushed ?? false
        bar.isHidden = hidesBar
        view.setNeedsLayout()
        view.layoutIfNeeded()
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }
}

@MainActor
final class RootTabBar: UITabBar {
    static let contentHeight: CGFloat = 60
    var onSelect: ((Int) -> Void)?
    private let row = UIStackView()
    private let separator = UIView()
    private var buttons: [RootTabButton] = []

    init(items: [UITabBarItem]) {
        super.init(frame: .zero)
        accessibilityIdentifier = "navigation.tabs"
        isTranslucent = false
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.card
        appearance.shadowColor = .clear
        standardAppearance = appearance
        scrollEdgeAppearance = appearance
        layer.cornerRadius = 8
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clipsToBounds = true
        separator.backgroundColor = Palette.border
        row.axis = .horizontal; row.distribution = .fillEqually
        for (index, item) in items.enumerated() {
            let button = RootTabButton(item: item)
            button.accessibilityIdentifier = "navigation.tab.\(index)"
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            buttons.append(button); row.addArrangedSubview(button)
        }
        addSubview(separator); addSubview(row)
        // Native tab-bar discovery and VoiceOver expose the actual controls,
        // without duplicate system items or private UIKit subview mutations.
        accessibilityElements = buttons
        select(0, animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let line: CGFloat = 0.5
        separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: line)
        row.frame = CGRect(x: 0, y: line, width: bounds.width, height: Self.contentHeight - line)
    }

    func select(_ index: Int, animated: Bool) {
        let changes = { [self] in
            for (i, button) in buttons.enumerated() { button.setSelection(i == index) }
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else { changes() }
    }
}

@MainActor
private final class RootTabButton: UIControl {
    private let icon: UIImageView
    private let label = UILabel()

    init(item: UITabBarItem) {
        icon = UIImageView(image: item.image)
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = item.title
        accessibilityTraits = .button
        label.text = item.title; label.textAlignment = .center
        icon.contentMode = .scaleAspectFit
        for child in [icon, label] {
            child.isUserInteractionEnabled = false
            child.isAccessibilityElement = false
            addSubview(child)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Symbol images can supply alignment insets which shrink an Auto Layout
        // image view's actual frame. Keep the application's 20/4 geometry exact.
        icon.frame = CGRect(x: bounds.midX - 10, y: bounds.midY - 18, width: 20, height: 20)
        label.frame = CGRect(x: 4, y: icon.frame.maxY + 4, width: max(0, bounds.width - 8), height: ceil(label.font.lineHeight))
    }

    func setSelection(_ selected: Bool) {
        isSelected = selected
        let color = selected ? Palette.accent : Palette.text3
        icon.tintColor = color; label.textColor = color
        label.font = .systemFont(ofSize: 10, weight: selected ? .bold : .medium)
        accessibilityTraits = selected ? [.button, .selected] : .button
        setNeedsLayout()
    }
}
