import Foundation

public enum ReaderLayout: Int, CaseIterable, Sendable { case strip = 0, paged = 1 }
public enum ReaderTurnMode: Int, CaseIterable, Sendable { case tap = 0, buttons = 1, swipe = 2 }

public struct ReaderPreferences: Equatable, Sendable {
    public var layout: ReaderLayout = .strip
    public var turnMode: ReaderTurnMode = .tap
    public var theme: ReaderTheme = .system
    public var leftHand = false
    public var fullyImmersive = false
    public var inkScreen = false
    public var pinchZoom = true
    public var disablePageAnimation = false
    public var cropWhiteMargins = false
    public init() {}
}

public final class ReaderPreferencesStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> ReaderPreferences {
        var settings = ReaderPreferences()
        settings.layout = ReaderLayout(rawValue: defaults.integer(forKey: "reader.layout.mode")) ?? .strip
        let pageMode = (defaults.object(forKey: "reader.page.mode") as? Int)
            ?? (defaults.bool(forKey: "reader.button.mode") ? 1 : 0)
        settings.turnMode = ReaderTurnMode(rawValue: max(0, min(2, pageMode))) ?? .tap
        settings.theme = ReaderTheme(rawValue: defaults.integer(forKey: "reader.theme.mode")) ?? .system
        settings.leftHand = defaults.bool(forKey: "reader.left.hand")
        settings.fullyImmersive = defaults.bool(forKey: "reader.fully.immersive")
        settings.inkScreen = defaults.integer(forKey: "reader.display.mode") == 1
        settings.pinchZoom = (defaults.object(forKey: "reader.pinch.zoom") as? Bool) ?? true
        settings.disablePageAnimation = defaults.bool(forKey: "reader.disable.page.animation")
        settings.cropWhiteMargins = defaults.bool(forKey: "reader.crop.white.margins")
        return settings
    }

    public func save(_ settings: ReaderPreferences) {
        defaults.set(settings.layout.rawValue, forKey: "reader.layout.mode")
        defaults.set(settings.turnMode.rawValue, forKey: "reader.page.mode")
        defaults.set(settings.theme.rawValue, forKey: "reader.theme.mode")
        defaults.set(settings.leftHand, forKey: "reader.left.hand")
        defaults.set(settings.fullyImmersive, forKey: "reader.fully.immersive")
        defaults.set(settings.inkScreen ? 1 : 0, forKey: "reader.display.mode")
        defaults.set(settings.pinchZoom, forKey: "reader.pinch.zoom")
        defaults.set(settings.disablePageAnimation, forKey: "reader.disable.page.animation")
        defaults.set(settings.cropWhiteMargins, forKey: "reader.crop.white.margins")
    }
}
