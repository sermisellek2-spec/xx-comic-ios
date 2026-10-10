import Foundation

public struct UsageStatsState: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var decided: Bool
    public var installId: String
    public var lastDay: String

    public init(enabled: Bool = true, decided: Bool = true, installId: String = "", lastDay: String = "") {
        self.enabled = enabled
        self.decided = decided
        self.installId = installId
        self.lastDay = lastDay
    }
}

public final class UsageStatsClient: @unchecked Sendable {
    public static let shared = UsageStatsClient()
    public static let endpoint = "https://weifeng.cloud/xx-comic/telemetry/collect"

    private let lock = NSLock()
    private let fileURL: URL
    private var state: UsageStatsState
    private var isLoaded: Bool = false
    private var isRunning: Bool = false

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        self.fileURL = dir.appendingPathComponent("usage-stats.json")
        self.state = UsageStatsState()
        loadLocked()
    }

    public var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.enabled
    }

    public var isDecided: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.decided
    }

    public func setEnabled(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        state.enabled = value
        state.decided = true
        saveLocked()
    }

    public static func beijingDay(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return formatter.string(from: date)
    }

    public func payload(
        appVersion: String = "2.0.40",
        versionCode: Int = 340,
        osVersion: String = "iOS 16.0",
        deviceModel: String = "Apple iPhone"
    ) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard state.enabled, state.decided else { return nil }

        if state.installId.isEmpty {
            state.installId = UUID().uuidString
            saveLocked()
        }

        return [
            "installId": state.installId,
            "appVersion": appVersion,
            "versionCode": versionCode,
            "osVersion": osVersion,
            "deviceModel": deviceModel
        ]
    }

    public func markDayReported(_ day: String) {
        lock.lock()
        defer { lock.unlock() }
        state.lastDay = day
        saveLocked()
    }

    public var lastReportedDay: String {
        lock.lock()
        defer { lock.unlock() }
        return state.lastDay
    }

    // MARK: - Private Persistence

    private func loadLocked() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode(UsageStatsState.self, from: data) else {
            state = UsageStatsState(enabled: true, decided: true, installId: "", lastDay: "")
            isLoaded = true
            return
        }
        state = loaded
        isLoaded = true
    }

    private func saveLocked() {
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
