public enum AppTheme: Int, Sendable {
    case automatic = 0, light = 1, dark = 2
    public func isDark(hour: Int) -> Bool { self == .dark || (self == .automatic && (hour < 8 || hour >= 18)) }
    public func isDark(systemDark: Bool) -> Bool {
        switch self {
        case .automatic: return systemDark
        case .light: return false
        case .dark: return true
        }
    }
}
