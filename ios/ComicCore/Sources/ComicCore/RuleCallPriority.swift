import Foundation

/// TaskLocal + ThreadLocal background priority marker for rule engine calls.
///
/// Background callers (recommend harvesting, favorite update checks, download workers, detail
/// alternative-source search) wrap execution in `withBackgroundPriority` so `RuleHostExecutor`
/// routes non-search rule invocations to the dedicated background semaphore and protects
/// foreground concurrency capacity.
public enum RuleCallPriority {
    @TaskLocal public static var isBackground: Bool = false

    private static let threadDictKey = "com.xxcomic.ruleCallPriority.isBackground"

    public static func currentIsBackground() -> Bool {
        isBackground || (Thread.current.threadDictionary[threadDictKey] as? Bool == true)
    }

    public static func withBackgroundPriority<T>(_ op: () throws -> T) rethrows -> T {
        try withPriority(isBackground: true, op)
    }

    public static func withBackgroundPriority<T>(_ op: () async throws -> T) async rethrows -> T {
        try await $isBackground.withValue(true, operation: op)
    }

    public static func withPriority<T>(isBackground background: Bool, _ op: () throws -> T) rethrows -> T {
        try $isBackground.withValue(background) {
            let dict = Thread.current.threadDictionary
            let previous = dict[threadDictKey]
            if background {
                dict[threadDictKey] = true
            } else {
                dict.removeObject(forKey: threadDictKey)
            }
            defer {
                if let previous {
                    dict[threadDictKey] = previous
                } else {
                    dict.removeObject(forKey: threadDictKey)
                }
            }
            return try op()
        }
    }
}
