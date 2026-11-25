import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Shared HTTP fetch helper for protected/WebView verification sessions with bounded manual 3xx redirects,
/// cross-origin Cookie stripping, and per-hop Set-Cookie persistence.
public enum ProtectedSessionHttp {
    public static let maxRedirects = 5

    public protocol CookieStore: Sendable {
        func getCookie(for url: String) -> String?
        func setCookie(url: String, value: String)
        func flush()
    }

    public struct HttpFetch: Equatable, Sendable {
        public let statusCode: Int
        public let mitigated: String
        public let body: String
        public let finalUrl: String

        public init(statusCode: Int, mitigated: String = "", body: String = "", finalUrl: String = "") {
            self.statusCode = statusCode
            self.mitigated = mitigated
            self.body = body
            self.finalUrl = finalUrl
        }
    }

    private final class SystemCookieStore: CookieStore, @unchecked Sendable {
        func getCookie(for url: String) -> String? {
            guard let parsed = URL(string: url),
                  let cookies = HTTPCookieStorage.shared.cookies(for: parsed),
                  !cookies.isEmpty else {
                return nil
            }
            return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }

        func setCookie(url: String, value: String) {
            guard let parsed = URL(string: url) else { return }
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: parsed)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }

        func flush() {}
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private static let systemCookieStore: CookieStore = SystemCookieStore()

    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()

    private static let commaCookieSplitRegex = try! NSRegularExpression(
        pattern: #",\s*(?=[A-Za-z0-9_.$-]{1,128}=)"#,
        options: []
    )

    public static func systemCookies() -> CookieStore {
        systemCookieStore
    }

    public static func isSameOrigin(_ left: URL?, _ right: URL?) -> Bool {
        guard let left, let right,
              let leftScheme = left.scheme?.lowercased(),
              let rightScheme = right.scheme?.lowercased(),
              let leftHost = left.host?.lowercased(),
              let rightHost = right.host?.lowercased() else {
            return false
        }
        let leftPort = left.port ?? defaultPort(for: leftScheme)
        let rightPort = right.port ?? defaultPort(for: rightScheme)
        return leftScheme == rightScheme && leftHost == rightHost && leftPort == rightPort
    }

    public static func fetch(
        url: String,
        userAgent: String,
        connectTimeoutMs: Int,
        readTimeoutMs: Int,
        cancelLabel: String = "",
        cookieStore: CookieStore? = nil
    ) throws -> HttpFetch {
        let cookies = cookieStore ?? systemCookieStore
        let label = cancelLabel
        guard let initialParsed = URL(string: url) else {
            throw RuleError("不支持的协议")
        }
        try validateHttpProtocol(initialParsed)
        var currentParsed = initialParsed
        var currentUrl = url
        var sendCookies = true

        for redirects in 0...maxRedirects {
            if let token = RuleCancelToken.current, token.isCancelled {
                throw RuleCancelledError("\(label)请求已取消")
            }
            if Task.isCancelled {
                throw RuleCancelledError("\(label)请求已取消")
            }

            let timeoutSec = max(1.0, Double(max(connectTimeoutMs, readTimeoutMs)) / 1000.0)
            var request = URLRequest(url: currentParsed)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = timeoutSec
            if !userAgent.isEmpty {
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            if sendCookies && isSameOrigin(initialParsed, currentParsed),
               let cookieHeader = cookies.getCookie(for: currentUrl),
               !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }

            let (data, http) = try executeOnce(request: request, timeoutSec: timeoutSec, label: label)
            let statusCode = http.statusCode
            let mitigated = headerValue(http, name: "cf-mitigated") ?? ""
            persistResponseCookies(url: currentUrl, http: http, cookieStore: cookies)

            if isRedirectStatus(statusCode) {
                if redirects >= maxRedirects {
                    throw RuleError("\(label)重定向过多")
                }
                guard let location = headerValue(http, name: "Location")?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !location.isEmpty else {
                    throw RuleError("\(label)重定向缺少目标地址")
                }
                guard let nextParsed = URL(string: location, relativeTo: currentParsed)?.absoluteURL else {
                    throw RuleError("\(label)重定向缺少目标地址")
                }
                try validateHttpProtocol(nextParsed)
                if !isSameOrigin(currentParsed, nextParsed) {
                    sendCookies = false
                }
                currentParsed = nextParsed
                currentUrl = nextParsed.absoluteString
                continue
            }

            if statusCode == 403 && mitigated.caseInsensitiveCompare("challenge") == .orderedSame {
                return HttpFetch(statusCode: statusCode, mitigated: mitigated, body: "", finalUrl: currentUrl)
            }

            let bodyText = String(decoding: data, as: UTF8.self)
            return HttpFetch(statusCode: statusCode, mitigated: mitigated, body: bodyText, finalUrl: currentUrl)
        }
        throw RuleError("\(label)重定向过多")
    }

    private static func executeOnce(
        request: URLRequest,
        timeoutSec: TimeInterval,
        label: String
    ) throws -> (Data, HTTPURLResponse) {
        final class Box: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var error: Error?
        }
        let box = Box()
        let sema = DispatchSemaphore(value: 0)
        let dataTask = sharedSession.dataTask(with: request) { d, r, e in
            box.data = d
            box.response = r
            box.error = e
            sema.signal()
        }

        let handle = try RuleCancelToken.current?.register {
            dataTask.cancel()
        }
        defer { handle?.close() }

        dataTask.resume()
        let waitMs = Int(timeoutSec * 1000.0) + 500
        if sema.wait(timeout: .now() + .milliseconds(waitMs)) == .timedOut {
            dataTask.cancel()
            throw RuleError("\(label)请求超时")
        }
        if let token = RuleCancelToken.current, token.isCancelled {
            dataTask.cancel()
            throw RuleCancelledError("\(label)请求已取消")
        }
        if Task.isCancelled {
            dataTask.cancel()
            throw RuleCancelledError("\(label)请求已取消")
        }
        if let err = box.error {
            let nsErr = err as NSError
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                throw RuleCancelledError("\(label)请求已取消")
            }
            throw err
        }
        guard let http = box.response as? HTTPURLResponse else {
            throw RuleError("无效的网络响应")
        }
        return (box.data ?? Data(), http)
    }

    private static func defaultPort(for scheme: String) -> Int {
        switch scheme {
        case "http": return 80
        case "https": return 443
        default: return -1
        }
    }

    private static func isRedirectStatus(_ statusCode: Int) -> Bool {
        statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308
    }

    private static func validateHttpProtocol(_ parsed: URL) throws {
        let protocolName = parsed.scheme?.lowercased() ?? ""
        guard protocolName == "http" || protocolName == "https" else {
            throw RuleError("不支持的协议")
        }
    }

    private static func headerValue(_ http: HTTPURLResponse, name: String) -> String? {
        for (rawKey, rawValue) in http.allHeaderFields {
            if String(describing: rawKey).caseInsensitiveCompare(name) == .orderedSame {
                return String(describing: rawValue)
            }
        }
        return nil
    }

    private static func persistResponseCookies(
        url: String,
        http: HTTPURLResponse,
        cookieStore: CookieStore
    ) {
        var wrote = false
        for (rawKey, rawValue) in http.allHeaderFields {
            let key = String(describing: rawKey)
            guard key.caseInsensitiveCompare("Set-Cookie") == .orderedSame else { continue }
            let rawHeader = String(describing: rawValue)
            guard !rawHeader.isEmpty else { continue }
            for single in splitSetCookieHeader(rawHeader) where !single.isEmpty {
                cookieStore.setCookie(url: url, value: single)
                wrote = true
            }
        }
        if wrote {
            cookieStore.flush()
        }
    }

    private static func splitSetCookieHeader(_ raw: String) -> [String] {
        let nsRange = NSRange(raw.startIndex..., in: raw)
        let matches = commaCookieSplitRegex.matches(in: raw, options: [], range: nsRange)
        guard !matches.isEmpty else {
            return [raw]
        }
        var parts = [String]()
        var currentStart = raw.startIndex
        for match in matches {
            guard let range = Range(match.range, in: raw) else { continue }
            let piece = String(raw[currentStart..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty {
                parts.append(piece)
            }
            currentStart = range.upperBound
        }
        let tail = String(raw[currentStart...]).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            parts.append(tail)
        }
        return parts
    }
}
