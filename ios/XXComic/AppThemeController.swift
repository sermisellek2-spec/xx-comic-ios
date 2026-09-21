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
        let now = Date(), calendar = Calendar.current
        root?.overrideUserInterfaceStyle = mode.isDark(hour: calendar.component(.hour, from: now)) ? .dark : .light
        guard mode == .automatic else { return }
        let next = [8, 18].compactMap {
            calendar.nextDate(after: now, matching: DateComponents(hour: $0, minute: 0, second: 0), matchingPolicy: .nextTime)
        }.min()
        if let next {
            timer = Timer.scheduledTimer(withTimeInterval: max(1, next.timeIntervalSince(now) + 0.25), repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
    }
    deinit { timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
}
