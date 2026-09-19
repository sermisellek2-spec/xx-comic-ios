import UIKit
import ComicCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var themeController: AppThemeController?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let defaults = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            ? UserDefaults(suiteName: "XXComic.UITests")! : .standard
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
        let settings = SettingsViewController(store: environment.preferences, defaults: defaults)
        tabs.viewControllers = [
            navigation(shelf, title: "书架", image: "books.vertical"),
            navigation(discover, title: "发现", image: "safari"),
            navigation(settings, title: "设置", image: "gearshape")
        ]
        tabs.tabBar.tintColor = Palette.accent
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.card
        tabs.tabBar.standardAppearance = appearance
        tabs.tabBar.scrollEdgeAppearance = appearance
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        themeController = AppThemeController(root: tabs, defaults: defaults)
        return true
    }

    private func navigation(_ root: UIViewController, title: String, image: String) -> UINavigationController {
        root.title = title
        let navigation = UINavigationController(rootViewController: root)
        navigation.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), selectedImage: nil)
        navigation.navigationBar.tintColor = Palette.accent
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
