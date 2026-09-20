import Foundation

public enum Mh18VerificationRules {
    public enum HTTPAction: Sendable { case returnBody, verificationRequired, fail }
    public enum InteractiveAction: Sendable { case complete, openBrowser, fail }
    public enum PageAction: Sendable { case wait, probe, fail }
    public enum ProbeAction: Sendable { case complete, reload, fail }
    public enum RequestTransport: Sendable { case http, browserContext }
    public static let requestTimeout: TimeInterval = 120
    public static let inspectionDelay: TimeInterval = 0.6
    public static let successDelay: TimeInterval = 0.6
    public static let maxProbeRecoveries = 2
    public static func httpAction(statusCode: Int, mitigated: String?, body: String) -> HTTPAction {
        if isChallenge(body: body, statusCode: statusCode, mitigated: mitigated) { return .verificationRequired }
        return (200..<400).contains(statusCode) ? .returnBody : .fail
    }

    public static func interactiveAction(statusCode: Int, mitigated: String?, body: String) -> InteractiveAction {
        switch httpAction(statusCode: statusCode, mitigated: mitigated, body: body) {
        case .verificationRequired: return .openBrowser
        case .fail: return .fail
        case .returnBody: return Mh18ComicSource.hasCatalogMarker(body) ? .complete : .fail
        }
    }

    public static func pageAction(challenge: Bool, expectedPage: Bool, browserCatalog: Bool) -> PageAction {
        if challenge { return .wait }
        if expectedPage && browserCatalog { return .probe }
        return expectedPage ? .wait : .fail
    }

    public static func probeAction(_ action: HTTPAction) -> ProbeAction {
        switch action {
        case .verificationRequired: return .reload
        case .returnBody: return .complete
        case .fail: return .fail
        }
    }

    public static func isChallenge(url: String = "", title: String = "", body: String, statusCode: Int = 200, mitigated: String? = nil) -> Bool {
        if statusCode == 403 && mitigated?.lowercased() == "challenge" { return true }
        let content = (url + " " + title + " " + body).lowercased()
        return ["/orchestrate/chl_page/", "_cf_chl_opt", "challenge-error-text", "cf-chl-widget",
                "cf-turnstile-response", "just a moment", "attention required", "checking your browser",
                "performing security verification", "verify you are human", "请稍候", "正在验证", "安全验证"]
            .contains(where: content.contains)
    }

    /// Android parity helper, not a trust boundary: parents and differing ports are accepted.
    /// Consumers must first constrain URLs to their configured root, HTTPS and default port.
    public static func sameSite(requested: URL, actual: URL) -> Bool {
        guard let expected = requested.host?.lowercased(), let received = actual.host?.lowercased(),
              !expected.isEmpty, !received.isEmpty, let scheme = requested.scheme,
              scheme.lowercased() == actual.scheme?.lowercased() else { return false }
        return expected == received || expected.hasSuffix("." + received) || received.hasSuffix("." + expected)
    }

    public static func isExpectedPage(requested: URL, actual: URL) -> Bool {
        sameSite(requested: requested, actual: actual)
            && normalizedPath(requested) == "/manga" && normalizedPath(actual) == "/manga"
    }

    /// Preserves Android's Cloudflare exception; the consumer must enforce HTTPS/443 first.
    public static func shouldBlockNavigation(requested: URL, actual: URL) -> Bool {
        if sameSite(requested: requested, actual: actual) { return false }
        let host = actual.host?.lowercased() ?? ""
        let path = normalizedPath(actual)
        let challengeHost = host == "challenges.cloudflare.com" || host.hasSuffix(".challenges.cloudflare.com")
        return !(challengeHost && (path.hasPrefix("/cdn-cgi/challenge-platform/") || path.hasPrefix("/turnstile/")))
    }

    public static func verificationComplete(browserCatalog: Bool, probeCatalog: Bool) -> Bool { browserCatalog && probeCatalog }
    public static func probeCanComplete(activeAttempt: Bool, probeRunning: Bool, stopped: Bool, capturedNavigation: Int, currentNavigation: Int) -> Bool {
        activeAttempt && probeRunning && !stopped && capturedNavigation == currentNavigation
    }
    public static func shouldStopForTimeout(active: Bool, succeeded: Bool) -> Bool { active && !succeeded }
    public static func requestDeadline(startedAt: TimeInterval) -> TimeInterval { startedAt + requestTimeout }
    public static func remainingRequest(deadline: TimeInterval, now: TimeInterval) -> TimeInterval { max(0, deadline - now) }
    public static func requestTransport(browserContextReady: Bool) -> RequestTransport { browserContextReady ? .browserContext : .http }

    private static func normalizedPath(_ url: URL) -> String {
        let path = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path)
            .replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        return path.isEmpty ? "/" : path
    }
}
