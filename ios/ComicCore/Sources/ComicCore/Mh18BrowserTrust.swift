import Foundation

/// The native browser boundary is deliberately narrower than Android's legacy sameSite rule.
public enum Mh18BrowserTrust {
    public static func allowsRequest(_ url: URL) -> Bool {
        secure(url) && belongs(url, to: "18mh.org")
    }

    public static func allowsNavigation(_ url: URL) -> Bool {
        if allowsRequest(url) { return true }
        guard secure(url), belongs(url, to: "challenges.cloudflare.com") else { return false }
        guard let rawPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              rawPath.hasPrefix("/cdn-cgi/challenge-platform/") || rawPath.hasPrefix("/turnstile/") else { return false }
        // Reject ambiguous traversal instead of trusting WebKit/server normalization to agree.
        // Decoding can only reject a path; it must never grant a challenge-prefix exception.
        let path = url.path.removingPercentEncoding ?? url.path
        guard !path.contains("\\"), !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
        return true
    }

    private static func secure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil
    }

    private static func belongs(_ url: URL, to root: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == root || host.hasSuffix("." + root)
    }
}
