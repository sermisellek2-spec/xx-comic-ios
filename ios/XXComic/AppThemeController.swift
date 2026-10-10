import UIKit
import ComicCore

@MainActor
final class AppThemeController {
    static let changed = Notification.Name("XXComic.themeChanged")
    private weak var root: UIViewController?
    private let defaults: UserDefaults
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(root: UIViewController, defaults: UserDefaults) {
        self.root = root; self.defaults = defaults
        for name in [Self.changed, UIApplication.didBecomeActiveNotification, UIApplication.significantTimeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
        refresh()
    }
    private func refresh() {
        timer?.invalidate()
        let mode = AppTheme(rawValue: defaults.integer(forKey: "theme.mode")) ?? .automatic
        switch mode {
        case .automatic:
            root?.overrideUserInterfaceStyle = .unspecified
        case .light:
            root?.overrideUserInterfaceStyle = .light
        case .dark:
            root?.overrideUserInterfaceStyle = .dark
        }
    }
    deinit { timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
}
