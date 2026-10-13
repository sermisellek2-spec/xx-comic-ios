import Foundation

public enum ErrorLogSanitizer {
    private static let sensitiveKeys: Set<String> = [
        "token", "auth", "authorization", "signature", "sig", "key",
        "apikey", "api_key", "password", "pwd", "secret", "session",
        "cookie", "ticket", "access_token", "refresh_token"
    ]

    public static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text

        // 1. 脱敏 Authorization Bearer
        if let bearerRegex = try? NSRegularExpression(pattern: #"(?i)bearer\s+[a-zA-Z0-9_\-\.]+"#) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = bearerRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "Bearer [REDACTED]")
        }

        // 2. 脱敏 Cookie: ... 头部
        if let cookieRegex = try? NSRegularExpression(pattern: #"(?i)cookie:\s*[^\r\n]+"#) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = cookieRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "Cookie: [REDACTED]")
        }

        // 3. 脱敏 URL query 及独立行中的敏感键值对
        if let kvRegex = try? NSRegularExpression(pattern: #"(?:[?&]|\b)([a-zA-Z0-9_]+)=([^&#\s;]*)"#, options: .caseInsensitive) {
            let matches = kvRegex.matches(in: result, options: [], range: NSRange(location: 0, length: (result as NSString).length))
            for match in matches.reversed() {
                guard match.numberOfRanges == 3 else { continue }
                let keyRange = match.range(at: 1)
                let valRange = match.range(at: 2)
                let key = (result as NSString).substring(with: keyRange).lowercased()
                if sensitiveKeys.contains(key) {
                    let nsResult = result as NSString
                    result = nsResult.replacingCharacters(in: valRange, with: "[REDACTED]")
                }
            }
        }

        return result
    }
}
