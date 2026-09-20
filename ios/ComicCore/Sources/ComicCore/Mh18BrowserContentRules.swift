import Foundation

/// Production WebKit rule data; its restricted regex grammar does not support alternation.
public enum Mh18BrowserContentRules {
    public static func encoded() throws -> String {
        var rules: [[String: Any]] = [
            ["trigger": ["url-filter": ".*", "resource-type": ["document", "raw"]], "action": ["type": "block"]],
            ["trigger": ["url-filter": #"^https://([a-z0-9-]+\.)*18mh\.org(:443)?/"#, "resource-type": ["document", "raw"]], "action": ["type": "ignore-previous-rules"]]
        ]
        // Keep scheme/host case insensitive while requiring the raw challenge path's exact case.
        let host = "challenges.cloudflare.com".map { $0 == "." ? #"\."# : "[\($0.lowercased())\($0.uppercased())]" }.joined()
        let origin = #"^[hH][tT][tT][pP][sS]://([a-zA-Z0-9-]+\.)*"# + host + #"(:443)?/"#
        for path in ["cdn-cgi/challenge-platform/", "turnstile/"] {
            let prefix = origin + path
            rules.append(["trigger": ["url-filter": prefix, "url-filter-is-case-sensitive": true, "resource-type": ["document", "raw"]], "action": ["type": "ignore-previous-rules"]])
        }
        // Block rules follow all allow rules so no later ignore-previous-rules can undo them.
        for path in ["cdn-cgi/challenge-platform/", "turnstile/"] {
            let prefix = origin + path
            let invalidPaths = [#"[^?]*[%\\]"#] + ["/", #"\?"#, "#", "$"].map { #"([^?]*/)?\.\.?"# + $0 }
            for suffix in invalidPaths {
                rules.append(["trigger": ["url-filter": prefix + suffix, "url-filter-is-case-sensitive": true, "resource-type": ["document", "raw"]], "action": ["type": "block"]])
            }
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
    }
}
