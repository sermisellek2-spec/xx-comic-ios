import Foundation

public enum TextReaderTheme: Int, CaseIterable, Sendable { case light = 0, sepia = 1, dark = 2 }

public struct TextReaderPreferences: Equatable, Sendable {
    public var fontSize = 18
    public var lineHeight = 1.75
    public var theme: TextReaderTheme = .dark
    public var pagedMode = false
    public init() {}

    fileprivate var normalized: Self {
        var settings = self
        settings.fontSize = max(12, min(32, fontSize))
        settings.lineHeight = lineHeight.isFinite ? max(1.2, min(2.5, lineHeight)) : 1.75
        return settings
    }
}

public final class TextReaderPreferencesStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> TextReaderPreferences {
        var settings = TextReaderPreferences()
        settings.fontSize = (defaults.object(forKey: "text.reader.fontSize") as? Int) ?? 18
        settings.lineHeight = (defaults.object(forKey: "text.reader.lineHeight") as? Double) ?? 1.75
        settings.theme = TextReaderTheme(rawValue: (defaults.object(forKey: "text.reader.theme") as? Int) ?? 2) ?? .dark
        settings.pagedMode = defaults.bool(forKey: "text.reader.pagedMode")
        return settings.normalized
    }

    public func save(_ settings: TextReaderPreferences) {
        let settings = settings.normalized
        defaults.set(settings.fontSize, forKey: "text.reader.fontSize")
        defaults.set(settings.lineHeight, forKey: "text.reader.lineHeight")
        defaults.set(settings.theme.rawValue, forKey: "text.reader.theme")
        defaults.set(settings.pagedMode, forKey: "text.reader.pagedMode")
    }
}
