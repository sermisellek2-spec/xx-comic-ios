import Foundation

public enum ReaderLayout: Int, CaseIterable, Sendable { case strip = 0, paged = 1 }
public enum ReaderTurnMode: Int, CaseIterable, Sendable { case tap = 0, buttons = 1, swipe = 2 }
public enum ReaderReadingMode: Int, CaseIterable, Sendable { case scroll = 0, normal = 1, manga = 2 }
public enum ReaderPageDirection: Equatable, Sendable { case leftToRight, rightToLeft }

public enum ReaderComfortPolicy {
    public static let prefKeepScreenMinutes = "reader.keep.screen.minutes"
    public static let keepScreenSystem = 0
    public static let keepScreen5Min = 5
    public static let keepScreen15Min = 15
    public static let keepScreen30Min = 30
    public static let keepScreenAlways = -1
    public static let defaultKeepScreenMinutes = keepScreen15Min
    public static let keepScreenOptions: [Int] = [
        keepScreenSystem,
        keepScreen5Min,
        keepScreen15Min,
        keepScreen30Min,
        keepScreenAlways
    ]

    public static let prefBrightnessFollowSystem = "reader.brightness.follow.system"
    public static let prefBrightnessLevel = "reader.brightness.level"
    public static let prefBrightnessDim = "reader.brightness.dim"
    public static let defaultBrightnessFollowSystem = true
    public static let defaultBrightnessLevel: Double = 0.60
    public static let minBrightnessLevel: Double = 0.01
    public static let maxBrightnessLevel: Double = 1.00
    public static let defaultExtraDim: Double = 0.0
    public static let minExtraDim: Double = 0.0
    public static let maxExtraDim: Double = 0.60

    public static func normalizeKeepScreenMinutes(_ minutes: Int) -> Int {
        keepScreenOptions.contains(minutes) ? minutes : defaultKeepScreenMinutes
    }

    public static func keepScreenLabel(_ minutes: Int) -> String {
        switch normalizeKeepScreenMinutes(minutes) {
        case keepScreenSystem: return "跟随系统"
        case keepScreen5Min: return "5分钟"
        case keepScreen30Min: return "30分钟"
        case keepScreenAlways: return "常亮"
        default: return "15分钟"
        }
    }

    public static func keepScreenTimeoutSeconds(_ minutes: Int) -> TimeInterval {
        let normalized = normalizeKeepScreenMinutes(minutes)
        return normalized > 0 ? TimeInterval(normalized * 60) : 0
    }

    public static func isKeepScreenIdleExpired(minutes: Int, lastInteractionUptime: TimeInterval, nowUptime: TimeInterval) -> Bool {
        let timeout = keepScreenTimeoutSeconds(minutes)
        guard timeout > 0, nowUptime >= lastInteractionUptime else { return false }
        return (nowUptime - lastInteractionUptime) >= timeout
    }

    public static func clampBrightness(_ level: Double) -> Double {
        guard level.isFinite else { return defaultBrightnessLevel }
        return max(minBrightnessLevel, min(maxBrightnessLevel, level))
    }

    public static func brightnessToPercent(_ level: Double) -> Int {
        max(1, min(100, Int((clampBrightness(level) * 100.0).rounded())))
    }

    public static func clampExtraDim(_ dim: Double) -> Double {
        guard dim.isFinite else { return defaultExtraDim }
        return max(minExtraDim, min(maxExtraDim, dim))
    }

    public static func extraDimToPercent(_ dim: Double) -> Int {
        max(0, min(60, Int((clampExtraDim(dim) * 100.0).rounded())))
    }

    public static func resolveExtraDimAlpha(readerVisible: Bool, dim: Double) -> Double {
        guard readerVisible else { return 0 }
        let clamped = clampExtraDim(dim)
        return clamped < 0.005 ? 0 : clamped
    }
}

public struct ReaderPreferences: Equatable, Sendable {
    public var readingMode: ReaderReadingMode = .scroll
    public var layout: ReaderLayout {
        get { readingMode == .scroll ? .strip : .paged }
        set { readingMode = newValue == .strip ? .scroll : .normal }
    }
    public var pageDirection: ReaderPageDirection {
        readingMode == .manga ? .rightToLeft : .leftToRight
    }
    public var turnMode: ReaderTurnMode = .tap
    public var theme: ReaderTheme = .system
    public var fullyImmersive = false
    public var inkScreen = false
    public var pinchZoom = true
    public var disablePageAnimation = false
    public var cropWhiteMargins = false
    public var enhancementMode: Int = 0
    public var enhancementComparison: Bool = false
    public var keepScreenMinutes: Int = ReaderComfortPolicy.defaultKeepScreenMinutes
    public var brightnessFollowSystem: Bool = ReaderComfortPolicy.defaultBrightnessFollowSystem
    public var brightnessLevel: Double = ReaderComfortPolicy.defaultBrightnessLevel
    public var brightnessDim: Double = ReaderComfortPolicy.defaultExtraDim
    public init() {}
}

public final class ReaderPreferencesStore {
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> ReaderPreferences {
        var settings = ReaderPreferences()
        settings.layout = ReaderLayout(rawValue: defaults.integer(forKey: "reader.layout.mode")) ?? .strip
        if let value = defaults.object(forKey: "reader.reading.mode") as? Int,
           let mode = ReaderReadingMode(rawValue: value) {
            settings.readingMode = mode
        }
        let pageMode = (defaults.object(forKey: "reader.page.mode") as? Int)
            ?? (defaults.bool(forKey: "reader.button.mode") ? 1 : 0)
        settings.turnMode = ReaderTurnMode(rawValue: max(0, min(2, pageMode))) ?? .tap
        settings.theme = ReaderTheme(rawValue: defaults.integer(forKey: "reader.theme.mode")) ?? .system
        settings.fullyImmersive = defaults.bool(forKey: "reader.fully.immersive")
        settings.inkScreen = defaults.integer(forKey: "reader.display.mode") == 1
        settings.pinchZoom = (defaults.object(forKey: "reader.pinch.zoom") as? Bool) ?? true
        settings.disablePageAnimation = defaults.bool(forKey: "reader.disable.page.animation")
        settings.cropWhiteMargins = defaults.bool(forKey: "reader.crop.white.margins")
        settings.enhancementMode = validEnhancementMode(defaults.integer(forKey: "reader.enhancement.mode"))
        settings.enhancementComparison = defaults.bool(forKey: "reader.enhancement.comparison")
        if let rawMinutes = defaults.object(forKey: ReaderComfortPolicy.prefKeepScreenMinutes) as? Int {
            settings.keepScreenMinutes = ReaderComfortPolicy.normalizeKeepScreenMinutes(rawMinutes)
        } else {
            settings.keepScreenMinutes = ReaderComfortPolicy.defaultKeepScreenMinutes
        }
        settings.brightnessFollowSystem = (defaults.object(forKey: ReaderComfortPolicy.prefBrightnessFollowSystem) as? Bool)
            ?? ReaderComfortPolicy.defaultBrightnessFollowSystem
        if let rawLevel = defaults.object(forKey: ReaderComfortPolicy.prefBrightnessLevel) as? Double {
            settings.brightnessLevel = ReaderComfortPolicy.clampBrightness(rawLevel)
        } else if let rawFloat = defaults.object(forKey: ReaderComfortPolicy.prefBrightnessLevel) as? Float {
            settings.brightnessLevel = ReaderComfortPolicy.clampBrightness(Double(rawFloat))
        } else {
            settings.brightnessLevel = ReaderComfortPolicy.defaultBrightnessLevel
        }
        if let rawDim = defaults.object(forKey: ReaderComfortPolicy.prefBrightnessDim) as? Double {
            settings.brightnessDim = ReaderComfortPolicy.clampExtraDim(rawDim)
        } else if let rawFloat = defaults.object(forKey: ReaderComfortPolicy.prefBrightnessDim) as? Float {
            settings.brightnessDim = ReaderComfortPolicy.clampExtraDim(Double(rawFloat))
        } else {
            settings.brightnessDim = ReaderComfortPolicy.defaultExtraDim
        }
        return settings
    }

    public func save(_ settings: ReaderPreferences) {
        defaults.set(settings.layout.rawValue, forKey: "reader.layout.mode")
        defaults.set(settings.readingMode.rawValue, forKey: "reader.reading.mode")
        defaults.set(settings.turnMode.rawValue, forKey: "reader.page.mode")
        defaults.set(settings.theme.rawValue, forKey: "reader.theme.mode")
        defaults.set(settings.fullyImmersive, forKey: "reader.fully.immersive")
        defaults.set(settings.inkScreen ? 1 : 0, forKey: "reader.display.mode")
        defaults.set(settings.pinchZoom, forKey: "reader.pinch.zoom")
        defaults.set(settings.disablePageAnimation, forKey: "reader.disable.page.animation")
        defaults.set(settings.cropWhiteMargins, forKey: "reader.crop.white.margins")
        defaults.set(validEnhancementMode(settings.enhancementMode), forKey: "reader.enhancement.mode")
        defaults.set(settings.enhancementComparison, forKey: "reader.enhancement.comparison")
        defaults.set(ReaderComfortPolicy.normalizeKeepScreenMinutes(settings.keepScreenMinutes), forKey: ReaderComfortPolicy.prefKeepScreenMinutes)
        defaults.set(settings.brightnessFollowSystem, forKey: ReaderComfortPolicy.prefBrightnessFollowSystem)
        defaults.set(ReaderComfortPolicy.clampBrightness(settings.brightnessLevel), forKey: ReaderComfortPolicy.prefBrightnessLevel)
        defaults.set(ReaderComfortPolicy.clampExtraDim(settings.brightnessDim), forKey: ReaderComfortPolicy.prefBrightnessDim)
    }

    private func validEnhancementMode(_ value: Int) -> Int {
        value == ImageEnhancementPolicy.modeFast || value == ImageEnhancementPolicy.modeSmart
            ? value : ImageEnhancementPolicy.modeOff
    }
}
