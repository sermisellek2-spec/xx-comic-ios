import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct UsageStatsApplicationInfo: Codable, Sendable {
    public let appVersion: String
    public let versionCode: Int
    public let osVersion: String
    public let deviceModel: String
    public init(appVersion: String, versionCode: Int, osVersion: String, deviceModel: String) {
        self.appVersion = appVersion; self.versionCode = versionCode
        self.osVersion = osVersion; self.deviceModel = deviceModel
    }
}

public enum UsageStatsError: LocalizedError {
    case unreadableState
    public var errorDescription: String? { "使用统计设置无法读取，原文件已保留" }
}

private final class UsageStatsNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

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
    private var readable = true
    private var consentGeneration = 0
    private var retryAfter: TimeInterval = 0
    private let transport: any HTTPTransport
    private let reportingURL: URL

    private static let defaultTransport: any HTTPTransport = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        return URLSessionHTTPTransport(session: URLSession(configuration: configuration, delegate: UsageStatsNoRedirect(), delegateQueue: nil), timeoutInterval: 3)
    }()

    public init(directory: URL? = nil, reportingURL: URL = URL(string: endpoint)!, transport: (any HTTPTransport)? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        self.fileURL = dir.appendingPathComponent("usage-stats.json")
        self.state = UsageStatsState()
        self.reportingURL = reportingURL
        self.transport = transport ?? Self.defaultTransport
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

    public func setEnabled(_ value: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        guard readable else { throw UsageStatsError.unreadableState }
        let previous = state
        state.enabled = value
        state.decided = true
        do { try saveLocked(); consentGeneration += 1 }
        catch { state = previous; throw error }
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
        guard readable, state.enabled, state.decided else { return nil }

        if state.installId.isEmpty {
            state.installId = UUID().uuidString
            do { try saveLocked() } catch { state.installId = ""; return nil }
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
        guard readable else { return }
        state.lastDay = day
        try? saveLocked()
    }

    public var lastReportedDay: String {
        lock.lock()
        defer { lock.unlock() }
        return state.lastDay
    }

    /// Once per Beijing day, with Android's 15-minute foreground retry cooldown.
    /// Tests inject an isolated HTTP transport; no test contacts the production endpoint.
    @discardableResult
    public func reportIfNeeded(info: UsageStatsApplicationInfo, date: Date = Date(),
                               uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) async -> Bool {
        guard !Task.isCancelled, let report = beginReport(info: info, date: date, uptime: uptime) else { return false }
        var accepted = false
        do {
            try Task.checkCancellation()
            let response = try await transport.post(reportingURL, headers: ["Content-Type": "application/json; charset=UTF-8"], body: report.body)
            try Task.checkCancellation()
            accepted = response.statusCode == 200
        } catch { /* Offline/timeout never interrupts reading or displays an alert. */ }
        return finishReport(day: report.day, generation: report.generation, accepted: accepted, uptime: uptime)
    }

    private func beginReport(info: UsageStatsApplicationInfo, date: Date, uptime: TimeInterval) -> (body: Data, day: String, generation: Int)? {
        lock.lock(); defer { lock.unlock() }
        let day = Self.beijingDay(date: date)
        guard readable, state.enabled, state.decided, !isRunning, state.lastDay != day, uptime >= retryAfter else { return nil }
        let previousID = state.installId
        do {
            if state.installId.isEmpty { state.installId = UUID().uuidString; try saveLocked() }
            let body = try JSONSerialization.data(withJSONObject: [
                "installId": state.installId, "appVersion": info.appVersion, "versionCode": info.versionCode,
                "osVersion": info.osVersion, "deviceModel": info.deviceModel
            ])
            isRunning = true
            return (body, day, consentGeneration)
        } catch { state.installId = previousID; return nil }
    }

    private func finishReport(day: String, generation: Int, accepted: Bool, uptime: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        isRunning = false; retryAfter = uptime + 15 * 60
        guard accepted, state.enabled, readable, consentGeneration == generation else { return false }
        let previous = state.lastDay
        state.lastDay = day
        do { try saveLocked(); return true } catch { state.lastDay = previous; return false }
    }

    // MARK: - Private Persistence

    private func loadLocked() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            state = UsageStatsState(enabled: true, decided: true, installId: "", lastDay: "")
            isLoaded = true
            return
        }
        do { state = try JSONDecoder().decode(UsageStatsState.self, from: Data(contentsOf: fileURL)) }
        catch { readable = false; state = UsageStatsState(enabled: false, decided: false) }
        isLoaded = true
    }

    private func saveLocked() throws {
        guard readable else { throw UsageStatsError.unreadableState }
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
        #if canImport(Darwin)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var url = fileURL; try url.setResourceValues(values)
        #endif
    }
}
