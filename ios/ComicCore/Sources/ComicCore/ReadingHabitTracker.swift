import Foundation

public final class ReadingHabitTracker {
    public enum LaunchMode: Int, Sendable {
        case automatic = 0
        case my = 1
        case local = 2
    }

    public enum Preference: Int, Sendable {
        case none = 0
        case my = 1
        case local = 2
    }

    public struct Sample: Codable, Equatable, Sendable {
        public let timestamp: TimeInterval
        public let isLocal: Bool

        public init(timestamp: TimeInterval, isLocal: Bool) {
            self.timestamp = timestamp
            self.isLocal = isLocal
        }

        private enum CodingKeys: String, CodingKey {
            case timestamp = "t"
            case isLocal = "l"
        }
    }

    public struct Clocks {
        let monotonic: () -> TimeInterval
        let wall: () -> TimeInterval

        public init(monotonic: @escaping () -> TimeInterval, wall: @escaping () -> TimeInterval) {
            self.monotonic = monotonic
            self.wall = wall
        }

        public static let system = Clocks(
            monotonic: { ProcessInfo.processInfo.systemUptime },
            wall: { Date().timeIntervalSince1970 }
        )
    }

    public final class Session {
        public let comicID: String
        public let isLocal: Bool
        public fileprivate(set) var accumulatedReadingTime: TimeInterval = 0
        public fileprivate(set) var voted = false

        fileprivate var followsHabit = true
        fileprivate var contentReadable = false
        fileprivate var hasUserAction = false
        fileprivate var isForeground = true
        fileprivate var overlayVisible = false
        fileprivate var lastActiveTime: TimeInterval
        fileprivate var lastTickTime: TimeInterval
        fileprivate var backgroundTime: TimeInterval?

        fileprivate init(comicID: String, isLocal: Bool, now: TimeInterval) {
            self.comicID = comicID
            self.isLocal = isLocal
            lastActiveTime = now
            lastTickTime = now
        }
    }

    public static let minimumReadingTime: TimeInterval = 60
    public static let inactivityTimeout: TimeInterval = 120
    public static let backgroundTimeout: TimeInterval = 300
    public static let sampleExpiry: TimeInterval = 30 * 24 * 60 * 60
    public static let maximumSamples = 10
    public static let minimumSamplesToDecide = 5

    private enum DefaultsKey {
        static let launchMode = "habit.launchBookshelfMode"
        static let lastManualTab = "habit.lastManualBookshelfTab"
        static let learnedPreference = "habit.learnedPreference"
        static let samples = "habit.samples"
    }

    private let clocks: Clocks
    private var publishesChanges = true
    public var onChange: (() -> Void)?
    public private(set) var samples: [Sample] = []
    public private(set) var learnedPreference: Preference = .none
    public private(set) var currentSession: Session?
    public var launchMode: LaunchMode = .automatic {
        didSet {
            currentSession?.followsHabit = launchMode == .automatic
            if publishesChanges { onChange?() }
        }
    }
    public var lastManualTab = 0 {
        didSet {
            if lastManualTab != 0 && lastManualTab != 1 { lastManualTab = 0; return }
            if publishesChanges { onChange?() }
        }
    }

    public init(clocks: Clocks = .system) {
        self.clocks = clocks
    }

    public static func evaluatePreference(_ samples: [Sample], previous: Preference, now: TimeInterval) -> Preference {
        let cutoff = now - sampleExpiry
        let recent = samples.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }.prefix(maximumSamples)
        guard recent.count >= minimumSamplesToDecide else { return previous }
        let localCount = recent.lazy.filter(\.isLocal).count
        if localCount * 10 >= recent.count * 7 { return .local }
        if (recent.count - localCount) * 10 >= recent.count * 7 { return .my }
        return previous
    }

    public static func resolveLaunchTab(mode: LaunchMode, learned: Preference, lastManualTab: Int) -> Int {
        switch mode {
        case .my: return 0
        case .local: return 1
        case .automatic:
            if learned == .local { return 1 }
            if learned == .my { return 0 }
            return lastManualTab == 1 ? 1 : 0
        }
    }

    public static func autoSubtitle(learned: Preference, effectiveTab: Int) -> String {
        switch learned {
        case .local: return "当前偏好：本地书架"
        case .my: return "当前偏好：我的书架"
        case .none: return "学习中 · 启动显示" + (effectiveTab == 1 ? "本地书架" : "我的书架")
        }
    }

    public var currentLaunchTab: Int {
        Self.resolveLaunchTab(mode: launchMode, learned: learnedPreference, lastManualTab: lastManualTab)
    }

    public var currentAutoSubtitle: String {
        Self.autoSubtitle(learned: learnedPreference, effectiveTab: currentLaunchTab)
    }

    public func enterReader(comicID: String, isLocal: Bool) {
        let now = clocks.monotonic()
        if let session = currentSession, session.comicID == comicID {
            if let backgroundTime = session.backgroundTime, now - backgroundTime > Self.backgroundTimeout {
                currentSession = makeSession(comicID: comicID, isLocal: isLocal, now: now)
            } else {
                if let backgroundTime = session.backgroundTime { session.lastActiveTime += now - backgroundTime }
                session.isForeground = true
                session.backgroundTime = nil
                session.lastTickTime = now
                session.followsHabit = launchMode == .automatic
            }
            return
        }
        flushSessionTime()
        currentSession = makeSession(comicID: comicID, isLocal: isLocal, now: now)
    }

    public func contentBecameReadable() {
        guard let session = currentSession else { return }
        if !session.contentReadable {
            let now = clocks.monotonic()
            session.contentReadable = true
            session.lastActiveTime = now
            session.lastTickTime = now
        }
        checkVote()
    }

    public func userDidRead() {
        guard let session = currentSession else { return }
        flushSessionTime()
        let now = clocks.monotonic()
        session.hasUserAction = true
        session.lastActiveTime = now
        session.lastTickTime = now
        checkVote()
    }

    public func overlayVisibilityChanged(isVisible: Bool) {
        guard let session = currentSession else { return }
        let now = clocks.monotonic()
        flushSessionTime()
        if !isVisible, session.overlayVisible { session.lastActiveTime += now - session.lastTickTime }
        session.overlayVisible = isVisible
        session.lastTickTime = now
        checkVote()
    }

    public func appDidEnterBackground() {
        guard let session = currentSession else { return }
        let now = clocks.monotonic()
        flushSessionTime()
        session.isForeground = false
        session.backgroundTime = now
        session.lastTickTime = now
    }

    public func appWillEnterForeground() {
        guard let session = currentSession else { return }
        let now = clocks.monotonic()
        if let backgroundTime = session.backgroundTime, now - backgroundTime > Self.backgroundTimeout {
            let replacement = makeSession(comicID: session.comicID, isLocal: session.isLocal, now: now)
            replacement.contentReadable = true
            currentSession = replacement
        } else {
            if let backgroundTime = session.backgroundTime { session.lastActiveTime += now - backgroundTime }
            session.isForeground = true
            session.backgroundTime = nil
            session.lastTickTime = now
        }
    }

    public func exitReader() {
        flushSessionTime()
        currentSession = nil
    }

    public func tick() {
        flushSessionTime()
        checkVote()
    }

    public func resetHabit() {
        samples.removeAll()
        learnedPreference = .none
        currentSession?.voted = false
        onChange?()
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(launchMode.rawValue, forKey: DefaultsKey.launchMode)
        defaults.set(lastManualTab, forKey: DefaultsKey.lastManualTab)
        defaults.set(learnedPreference.rawValue, forKey: DefaultsKey.learnedPreference)
        defaults.set(try? JSONEncoder().encode(samples), forKey: DefaultsKey.samples)
    }

    public func restore(from defaults: UserDefaults) {
        publishesChanges = false
        defer { publishesChanges = true }
        launchMode = LaunchMode(rawValue: defaults.integer(forKey: DefaultsKey.launchMode)) ?? .automatic
        lastManualTab = defaults.integer(forKey: DefaultsKey.lastManualTab) == 1 ? 1 : 0
        learnedPreference = Preference(rawValue: defaults.integer(forKey: DefaultsKey.learnedPreference)) ?? .none
        if let data = defaults.data(forKey: DefaultsKey.samples), let decoded = try? JSONDecoder().decode([Sample].self, from: data) {
            samples = decoded.filter { $0.timestamp > 0 }
        } else {
            samples = []
        }
        learnedPreference = Self.evaluatePreference(samples, previous: learnedPreference, now: clocks.wall())
    }

    private func makeSession(comicID: String, isLocal: Bool, now: TimeInterval) -> Session {
        let session = Session(comicID: comicID, isLocal: isLocal, now: now)
        session.followsHabit = launchMode == .automatic
        return session
    }

    private func flushSessionTime() {
        guard let session = currentSession else { return }
        let now = clocks.monotonic()
        guard session.contentReadable, session.isForeground, !session.overlayVisible else {
            session.lastTickTime = now
            return
        }
        let periodStart = session.lastTickTime
        session.lastTickTime = now
        guard now > periodStart else { return }
        let effectiveEnd = min(now, session.lastActiveTime + Self.inactivityTimeout)
        if effectiveEnd > periodStart { session.accumulatedReadingTime += effectiveEnd - periodStart }
    }

    private func checkVote() {
        guard let session = currentSession, !session.voted, session.followsHabit,
              session.hasUserAction, session.accumulatedReadingTime >= Self.minimumReadingTime else { return }
        session.voted = true
        samples.append(Sample(timestamp: clocks.wall(), isLocal: session.isLocal))
        learnedPreference = Self.evaluatePreference(samples, previous: learnedPreference, now: clocks.wall())
        onChange?()
    }
}
