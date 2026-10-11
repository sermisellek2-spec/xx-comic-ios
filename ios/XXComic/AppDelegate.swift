import UIKit
import ComicCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var themeController: AppThemeController?
    private var environment: AppEnvironment?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if !process.arguments.contains("--ui-testing"),
           process.environment["XXCOMIC_NATIVE_TEST_HOST"] == "1" || process.environment["XCTestConfigurationFilePath"] != nil {
            // Hosted unit tests exercise the real components without starting the
            // production library, source refresh, or launch statistics reporter.
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = UIViewController()
            window.makeKeyAndVisible()
            self.window = window
            return true
        }
        #endif
        let defaults = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            ? UserDefaults(suiteName: "XXComic.UITests" + (EpubUITestFixtures.sessionID.map { "." + $0 } ?? ""))! : .standard
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("--dark-mode") {
                defaults.set(2, forKey: "theme.mode")
            } else if ProcessInfo.processInfo.arguments.contains("--light-mode") {
                defaults.set(1, forKey: "theme.mode")
            }
        }
        #if DEBUG
        let referenceSystemTheme = ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--matrix-reference-automatic-theme")
        if referenceSystemTheme { defaults.set(0, forKey: "theme.mode") }
        #endif
        let tabs = UITabBarController()
        let environment: AppEnvironment
        do { environment = try AppEnvironment(defaults: defaults) }
        catch {
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = DevelopmentPage(title: "本地数据读取失败", message: "书架数据无法读取，原文件已保留。\n\n" + error.localizedDescription)
            window.makeKeyAndVisible(); self.window = window
            return true
        }
        let shelf = BookshelfViewController(environment: environment)
        let discover = DiscoverViewController(environment: environment)
        let settings = SettingsViewController(environment: environment)
        tabs.viewControllers = [
            navigation(shelf, title: "书架", icon: .bookshelf),
            navigation(discover, title: "发现", icon: .search),
            navigation(settings, title: "设置", icon: .profile)
        ]
        tabs.tabBar.tintColor = Palette.accent
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.card
        appearance.shadowColor = Palette.borderSoft
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = Palette.text3
            layout.selected.iconColor = Palette.accent
            layout.normal.titleTextAttributes = [.foregroundColor: Palette.text3, .font: UIFont.systemFont(ofSize: 10, weight: .medium)]
            layout.selected.titleTextAttributes = [.foregroundColor: Palette.accent, .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
        }
        tabs.tabBar.standardAppearance = appearance
        tabs.tabBar.scrollEdgeAppearance = appearance
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tabs
        #if DEBUG
        if referenceSystemTheme {
            // Inject the window's system appearance while the app preference stays automatic.
            window.overrideUserInterfaceStyle = ProcessInfo.processInfo.arguments.contains("--dark-mode") ? .dark : .light
        }
        #endif
        window.makeKeyAndVisible()
        self.window = window
        self.environment = environment
        themeController = AppThemeController(root: tabs, defaults: defaults)
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        environment?.readingHabits.appDidEnterBackground()
        environment?.cancelUsageStatsReport()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        environment?.readingHabits.appWillEnterForeground()
        environment?.reportUsageStatsIfNeeded()
    }

    private func navigation(_ root: UIViewController, title: String, icon: ParityIcon) -> UINavigationController {
        root.title = title
        let heading = UILabel()
        heading.text = title; heading.textColor = Palette.text
        heading.font = .systemFont(ofSize: 20, weight: .bold)
        heading.accessibilityTraits = .header
        heading.accessibilityIdentifier = "navigation.title"
        heading.sizeToFit()
        root.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: heading)
        root.navigationItem.titleView = UIView(frame: .zero)
        let navigation = UINavigationController(rootViewController: root)
        // The bookshelf owns the complete Android-style text-tab header.
        // A system bar may omit left items when sufficient space is unavailable.
        if root is BookshelfViewController { navigation.setNavigationBarHidden(true, animated: false) }
        navigation.tabBarItem = UITabBarItem(title: title, image: icon.image(size: 20), selectedImage: nil)
        navigation.navigationBar.tintColor = Palette.accent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.background
        appearance.shadowColor = Palette.borderSoft
        appearance.titleTextAttributes = [.foregroundColor: Palette.text, .font: UIFont.systemFont(ofSize: 20, weight: .medium)]
        navigation.navigationBar.standardAppearance = appearance
        navigation.navigationBar.scrollEdgeAppearance = appearance
        navigation.navigationBar.compactAppearance = appearance
        return navigation
    }
}

private final class DevelopmentPage: UIViewController {
    private let message: String
    init(title: String, message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        let label = UILabel()
        label.text = message
        label.textColor = Palette.secondaryText
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28)
        ])
    }
}
