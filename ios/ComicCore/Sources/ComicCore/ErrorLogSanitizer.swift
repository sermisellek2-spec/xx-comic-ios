import Foundation

public enum ErrorLogSanitizer {
    private static let sensitiveKeys: Set<String> = [
        "token", "auth", "authorization", "proxy-authorization",
        "signature", "sig", "key", "apikey", "api_key", "api-key",
        "x-api-key", "x-auth-token", "x-access-token", "x-token",
        "password", "pwd", "secret", "session", "session_id", "session-id",
        "cookie", "set-cookie", "ticket",
        "access_token", "access-token", "accesstoken",
        "refresh_token", "refresh-token", "refreshtoken"
    ]

    private static let queryRegex = try? NSRegularExpression(
        pattern: #"(https?://[^\s?#]+)\?[^\s#"'<>)]+"#
    )
    private static let authSchemeRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9\-._~+/=]+"#
    )
    private static let cookieHeaderRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(set-cookie|cookie):\s*[^\r\n]+"#
    )
    private static let kvRegex = try? NSRegularExpression(
        pattern: #"(?i)(?:[?&]|\b)([a-zA-Z0-9_\-]+)(\s*[:=]\s*)([^\r\n,;&]+)"#
    )

    public static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text

        // 1. 脱敏非白名单 URL 查询参数为 ?[redacted]
        if let queryRegex {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = queryRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1?[redacted]"
            )
        }

        // 2. 脱敏 Authorization Bearer / Basic <base64>
        if let authSchemeRegex {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = authSchemeRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1 [REDACTED]"
            )
        }

        // 3. 脱敏 Cookie / Set-Cookie 头部
        if let cookieHeaderRegex {
            let matches = cookieHeaderRegex.matches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: (result as NSString).length)
            )
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let headerName = (result as NSString).substring(with: match.range(at: 1))
                let nsResult = result as NSString
                result = nsResult.replacingCharacters(in: match.range, with: "\(headerName): [REDACTED]")
            }
        }

        // 4. 脱敏独立键值及连字符请求头（如 x-auth-token），避免覆盖已脱敏的 Basic / Bearer Scheme
        if let kvRegex {
            let matches = kvRegex.matches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: (result as NSString).length)
            )
            for match in matches.reversed() {
                guard match.numberOfRanges == 4 else { continue }
                let nsResult = result as NSString
                let key = nsResult.substring(with: match.range(at: 1)).lowercased()
                let valRange = match.range(at: 3)
                let currentVal = nsResult.substring(with: valRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if currentVal == "[REDACTED]" || currentVal.hasPrefix("Basic [REDACTED]") || currentVal.hasPrefix("Bearer [REDACTED]") {
                    continue
                }
                if sensitiveKeys.contains(key) {
                    result = nsResult.replacingCharacters(in: valRange, with: "[REDACTED]")
                }
            }
        }

        return result
    }
}
