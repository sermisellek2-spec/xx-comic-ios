import Foundation

/// Monotonic attempt identity shared by native preflight, DOM and network completions.
public struct Mh18VerificationAttempt {
    public struct Token: Equatable, Sendable {
        let request: UUID
        let navigation: Int
    }
    public let deadline: TimeInterval
    public private(set) var token = Token(request: UUID(), navigation: 0)
    public private(set) var succeeded = false
    public private(set) var stopped = false
    private var recoveries = 0

    public init(startedAt: TimeInterval) { deadline = Mh18VerificationRules.requestDeadline(startedAt: startedAt) }
    public func accepts(_ captured: Token, now: TimeInterval) -> Bool {
        captured == token && !stopped && !succeeded && now < deadline
    }
    @discardableResult
    public mutating func navigationStarted() -> Bool {
        guard !succeeded && !stopped else { return false }
        token = Token(request: token.request, navigation: token.navigation + 1)
        return true
    }
    public mutating func recover(now: TimeInterval) -> Bool {
        guard accepts(token, now: now), recoveries < Mh18VerificationRules.maxProbeRecoveries else { return false }
        recoveries += 1
        navigationStarted()
        return true
    }
    public mutating func complete(_ captured: Token, now: TimeInterval) -> Bool {
        guard accepts(captured, now: now) else { return false }
        succeeded = true
        return true
    }
    public mutating func stop() { stopped = true }
}
