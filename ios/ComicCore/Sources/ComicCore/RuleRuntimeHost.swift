import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(WebKit)
import WebKit
#endif

// MARK: - RuleCancelToken

/// Thread-safe cancellation token and resource registry for aborting in-flight rule IO and renders immediately.
public final class RuleCancelToken: @unchecked Sendable {
    private static let threadDictKey = "com.xxcomic.ruleCancelToken"

    public final class Handle: @unchecked Sendable {
        private weak var owner: RuleCancelToken?
        private let id: UInt64
        private var closed = false
        private let lock = NSLock()

        fileprivate init(owner: RuleCancelToken, id: UInt64) {
            self.owner = owner
            self.id = id
        }

        public func close() {
            lock.lock()
            if closed {
                lock.unlock()
                return
            }
            closed = true
            lock.unlock()
            owner?.unregister(id)
        }
    }

    private let lock = NSLock()
    private var cancelled = false
    private var nextId: UInt64 = 1
    private var resources: [UInt64: @Sendable () -> Void] = [:]

    public init() {}

    public static var current: RuleCancelToken? {
        Thread.current.threadDictionary[threadDictKey] as? RuleCancelToken
    }

    public static func withCurrent<T>(_ token: RuleCancelToken, body: () throws -> T) rethrows -> T {
        let dict = Thread.current.threadDictionary
        let previous = dict[threadDictKey]
        dict[threadDictKey] = token
        defer {
            if let previous {
                dict[threadDictKey] = previous
            } else {
                dict.removeObject(forKey: threadDictKey)
            }
        }
        return try body()
    }

    public var isCancelled: Bool {
        lock.lock()
        let flag = cancelled
        lock.unlock()
        return flag || Task.isCancelled
    }

    public var registeredResourceCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return resources.count
    }

    public func throwIfCancelled() throws {
        if isCancelled {
            throw RuleCancelledError("规则调用已取消")
        }
    }

    public func register(_ closeAction: @escaping @Sendable () -> Void) throws -> Handle {
        lock.lock()
        if cancelled || Task.isCancelled {
            cancelled = true
            lock.unlock()
            closeAction()
            throw RuleCancelledError("规则调用已取消")
        }
        let id = nextId
        nextId &+= 1
        resources[id] = closeAction
        lock.unlock()
        return Handle(owner: self, id: id)
    }

    fileprivate func unregister(_ id: UInt64) {
        lock.lock()
        resources.removeValue(forKey: id)
        lock.unlock()
    }

    public func cancel() {
        lock.lock()
        if cancelled && resources.isEmpty {
            lock.unlock()
            return
        }
        cancelled = true
        let actions = Array(resources.values)
        resources.removeAll()
        lock.unlock()
        for action in actions {
            action()
        }
    }
}

// MARK: - RuleCache

public enum RuleCache {
    private static let maxEntries = 256
    private static let maxKeyChars = 512
    private static let maxSerializedBytes = 8192

    private static let lock = NSLock()
    private static var order: [String] = []
    private static var values: [String: String] = [:]

    public static func clearAll() {
        lock.lock()
        order.removeAll()
        values.removeAll()
        lock.unlock()
    }

    public static func call(ruleHash: String, data: [String: Any]) throws -> String {
        guard let action = data["action"] as? String,
              let key = data["key"] as? String,
              !key.isEmpty, key.count <= maxKeyChars else {
            throw RuleError("规则缓存键无效")
        }
        let scoped = "\(ruleHash)\n\(key)"
        if action == "get" {
            lock.lock()
            defer { lock.unlock() }
            guard let existing = values[scoped] else {
                return "null"
            }
            if let idx = order.firstIndex(of: scoped) {
                order.remove(at: idx)
                order.append(scoped)
            }
            return existing
        }
        if action == "set" {
            let rawValue = data["value"]
            if rawValue == nil || rawValue is NSNull {
                lock.lock()
                values.removeValue(forKey: scoped)
                order.removeAll(where: { $0 == scoped })
                lock.unlock()
                return "null"
            }
            let serialized = try serializeJsonValue(rawValue!)
            guard serialized.utf8.count <= maxSerializedBytes else {
                throw RuleError("规则缓存值超过大小限制")
            }
            lock.lock()
            if values[scoped] == nil && order.count >= maxEntries, let oldest = order.first {
                order.removeFirst()
                values.removeValue(forKey: oldest)
            }
            order.removeAll(where: { $0 == scoped })
            order.append(scoped)
            values[scoped] = serialized
            lock.unlock()
            return "null"
        }
        throw RuleError("不支持的规则缓存操作")
    }

    private static func serializeJsonValue(_ val: Any) throws -> String {
        if let str = val as? String {
            return RuleScript.quoteJsonString(str)
        }
        if let num = val as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return num.stringValue
        }
        let wrapped = try JSONSerialization.data(withJSONObject: [val], options: [])
        guard let text = String(data: wrapped, encoding: .utf8),
              text.hasPrefix("["), text.hasSuffix("]") else {
            throw RuleError("规则缓存值无法序列化")
        }
        return String(text.dropFirst().dropLast())
    }
}

// MARK: - RuleHttp (Production Network Client)

private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class RuleHttp: @unchecked Sendable {
    public static let maxBodyBytes = 6 * 1024 * 1024
    public static let defaultUserAgent = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

    public let rule: RuleDefinition
    public let debug: Bool
    public let cancelToken: RuleCancelToken
    private let cancelledCheck: @Sendable () -> Bool
    private let timeoutMillis: Int

    private static let paceLock = NSLock()
    private static var nextTimes = [String: Int64]()

    private static let hostLock = NSLock()
    private static var verifiedPublicHosts = [String: Int64]()
    private static let hostCheckTtlMs: Int64 = 300_000

    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpMaximumConnectionsPerHost = 12
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
    }()

    /// Shared keep-alive session factory for rule requests and rule image fetches.
    internal static func getSharedSession() -> URLSession {
        sharedSession
    }

    public init(rule: RuleDefinition,
                debug: Bool = false,
                cancelToken: RuleCancelToken? = nil,
                cancelled: @escaping @Sendable () -> Bool = { false },
                timeoutMillis: Int = 20000) {
        self.rule = rule
        self.debug = debug
        self.cancelToken = cancelToken ?? RuleCancelToken.current ?? RuleCancelToken()
        self.cancelledCheck = cancelled
        self.timeoutMillis = max(500, timeoutMillis)
    }

    private var isAborted: Bool {
        cancelToken.isCancelled || cancelledCheck()
    }

    private func checkCall() throws {
        if isAborted {
            throw RuleCancelledError("规则调用已取消")
        }
    }

    public func checkUrl(_ urlString: String) throws {
        try checkCall()
        try RuleDefinition.validateHttp(urlString)
        guard let parsed = URL(string: urlString), let host = parsed.host else {
            throw RuleError("规则请求了未授权的域名")
        }
        guard rule.allows(host) else {
            throw RuleError("规则请求了未授权的域名")
        }
        let scheme = parsed.scheme?.lowercased() ?? ""
        let lowerHost = host.lowercased()
        if scheme == "http" && !(debug && (lowerHost == "127.0.0.1" || lowerHost == "localhost")) && !rule.allowsCleartext(lowerHost) {
            throw RuleError("规则未声明该域名的明文 HTTP 访问权限")
        }
        if !debug {
            try Self.checkNonLocalHost(lowerHost)
        }
        try checkCall()
    }

    public static func checkNonLocalHost(_ host: String) throws {
        let lower = host.lowercased()
        if lower.isEmpty || lower == "localhost" || lower.hasSuffix(".local") ||
           lower.hasPrefix("127.") || lower == "0.0.0.0" || lower == "::1" || lower == "[::1]" {
            throw RuleError("规则不能访问本地网络")
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        hostLock.lock()
        if let exp = verifiedPublicHosts[lower], exp > nowMs {
            hostLock.unlock()
            return
        }
        hostLock.unlock()

        var hints = addrinfo()
        #if canImport(Darwin)
        hints.ai_socktype = SOCK_STREAM
        #else
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #endif
        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(lower, nil, &hints, &res)
        if rc == 0, let first = res {
            defer { freeaddrinfo(first) }
            var cur: UnsafeMutablePointer<addrinfo>? = first
            while let info = cur {
                if let sa = info.pointee.ai_addr {
                    if Int32(sa.pointee.sa_family) == AF_INET {
                        let sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                        let ip = UInt32(bigEndian: sin.sin_addr.s_addr)
                        let b0 = (ip >> 24) & 0xff
                        let b1 = (ip >> 16) & 0xff
                        if b0 == 0 || b0 == 10 || b0 == 127 ||
                           (b0 == 169 && b1 == 254) ||
                           (b0 == 172 && (16...31).contains(b1)) ||
                           (b0 == 192 && b1 == 168) {
                            throw RuleError("规则不能访问本地网络")
                        }
                    } else if Int32(sa.pointee.sa_family) == AF_INET6 {
                        let sin6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                        let bytes = withUnsafeBytes(of: sin6.sin6_addr) { Array($0) }
                        if bytes.count == 16 {
                            let isUnspecified = bytes.allSatisfy { $0 == 0 }
                            let isLoopback = bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes[15] == 1
                            let isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
                            let isUniqueLocal = (bytes[0] & 0xfe) == 0xfc
                            if isUnspecified || isLoopback || isLinkLocal || isUniqueLocal {
                                throw RuleError("规则不能访问本地网络")
                            }
                        }
                    }
                }
                cur = info.pointee.ai_next
            }
            hostLock.lock()
            if verifiedPublicHosts.count >= 512 {
                verifiedPublicHosts.removeAll(keepingCapacity: true)
            }
            verifiedPublicHosts[lower] = nowMs + hostCheckTtlMs
            hostLock.unlock()
        }
    }

    public static func checkHeader(_ key: String, _ value: String) throws {
        guard key.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil,
              !value.unicodeScalars.contains(where: { $0.value == 10 || $0.value == 13 }),
              value.count <= 4096 else {
            throw RuleError("规则请求头无效或不支持")
        }
        let lowerKey = key.lowercased()
        if ["host", "connection", "content-length", "proxy-authorization", "cookie"].contains(lowerKey) {
            throw RuleError("规则请求头无效或不支持")
        }
    }

    private static func nowMillis() -> Int64 {
        Int64(ProcessInfo.processInfo.systemUptime * 1000.0)
    }

    private func pace() throws {
        let interval = Int64(rule.engineApi >= 3 ? rule.minIntervalMs : 50)
        guard interval > 0 else { return }
        var waitMs: Int64 = 0
        Self.paceLock.lock()
        let now = Self.nowMillis()
        let scheduled = Self.nextTimes[rule.id] ?? now
        if scheduled > now {
            waitMs = scheduled - now
            Self.nextTimes[rule.id] = scheduled + interval
        } else {
            Self.nextTimes[rule.id] = now + interval
        }
        Self.paceLock.unlock()

        if waitMs > 0 {
            let stepMs: Int64 = 25
            var remaining = waitMs
            while remaining > 0 {
                try checkCall()
                let slice = min(stepMs, remaining)
                Thread.sleep(forTimeInterval: Double(slice) / 1000.0)
                remaining -= slice
            }
        }
    }

    public func request(_ args: [String: Any]) throws -> [String: Any] {
        guard var url = args["url"] as? String else {
            throw RuleError("规则网络参数无效")
        }
        var method = ((args["method"] as? String) ?? "GET").uppercased()
        guard method == "GET" || method == "POST" else {
            throw RuleError("规则只支持 GET/POST")
        }
        let responseType = (args["responseType"] as? String) ?? "text"
        guard responseType == "text" || responseType == "base64" else {
            throw RuleError("不支持的响应类型")
        }
        if responseType == "base64" && rule.engineApi < 3 {
            throw RuleError("二进制响应需要规则引擎 API 3")
        }
        let bodyEncoding = (args["bodyEncoding"] as? String) ?? "utf8"
        guard bodyEncoding == "utf8" || bodyEncoding == "base64" else {
            throw RuleError("不支持的请求体编码")
        }
        if bodyEncoding == "base64" && rule.engineApi < 3 {
            throw RuleError("二进制请求体需要规则引擎 API 3")
        }

        var rawHeaders = args["headers"] as? [String: Any]
        var suppliedCookies = try RuleSessions.checked(args["cookies"] as? [String: Any])
        if !suppliedCookies.isEmpty && rule.engineApi < 2 {
            throw RuleError("站点会话需要规则引擎 API 2")
        }

        let charset = (args["charset"] as? String) ?? ""
        if !charset.isEmpty && !["UTF-8", "GBK", "GB2312", "Big5"].contains(charset) {
            throw RuleError("不支持此响应编码")
        }

        var requestBody: Data?
        if method == "POST" {
            let bodyStr = (args["body"] as? String) ?? ""
            if bodyEncoding == "base64" {
                requestBody = try RuleBase64.decode(bodyStr)
            } else {
                requestBody = Data(bodyStr.utf8)
            }
        }

        let persistCookies = (args["persistCookies"] as? Bool) ?? true
        let deadlineMs = Self.nowMillis() + Int64(timeoutMillis)

        for _ in 0..<6 {
            try checkCall()
            try checkUrl(url)
            try pace()

            var cookies = RuleSessions.get(rule: rule, url: url)
            for (k, v) in suppliedCookies {
                cookies[k] = v
            }

            var validatedHeaders = [String: String]()
            if let hdrs = rawHeaders {
                guard hdrs.count <= 32 else { throw RuleError("规则请求头过多") }
                for (k, v) in hdrs {
                    let valStr = String(describing: v)
                    try Self.checkHeader(k, valStr)
                    validatedHeaders[k] = valStr
                }
            }

            let httpResult: SingleHttpResult
            do {
                httpResult = try executeOnce(
                    url: url,
                    method: method,
                    headers: validatedHeaders,
                    cookies: cookies,
                    bodyBytes: method == "POST" ? requestBody : nil,
                    deadlineMs: deadlineMs
                )
            } catch let err as RuleCancelledError {
                throw err
            } catch {
                if isAborted {
                    throw RuleCancelledError("规则调用已取消")
                }
                if method != "GET" || !Self.isTransientNetworkError(error) {
                    throw error
                }
                try checkCall()
                try pace()
                httpResult = try executeOnce(
                    url: url,
                    method: method,
                    headers: validatedHeaders,
                    cookies: cookies,
                    bodyBytes: nil,
                    deadlineMs: deadlineMs
                )
            }

            if httpResult.statusCode >= 200 && httpResult.statusCode < 300 && persistCookies {
                RuleSessions.receive(rule: rule, url: url, fresh: cookies)
            }
            if persistCookies {
                RuleSessions.receiveResponse(rule: rule, url: url, fresh: httpResult.responseCookies)
            }
            try checkCall()

            let status = httpResult.statusCode
            if [301, 302, 303, 307, 308].contains(status) {
                guard let location = httpResult.location, !location.isEmpty,
                      let currentUrl = URL(string: url),
                      let nextUrl = URL(string: location, relativeTo: currentUrl)?.absoluteURL else {
                    throw RuleError("重定向缺少目标地址")
                }
                if let curHost = currentUrl.host, let nxtHost = nextUrl.host,
                   curHost.caseInsensitiveCompare(nxtHost) != .orderedSame {
                    rawHeaders = nil
                    suppliedCookies = [:]
                }
                url = nextUrl.absoluteString
                if status == 303 || ((status == 301 || status == 302) && method == "POST") {
                    method = "GET"
                    requestBody = nil
                }
                continue
            }

            if httpResult.bodyBytes.count >= Self.maxBodyBytes {
                throw RuleError("站点响应超过 6MiB")
            }

            var safeHeaders = [String: String]()
            if let ct = httpResult.contentType, !ct.isEmpty {
                safeHeaders["Content-Type"] = ct
            }
            let bodyOut: String
            if responseType == "base64" {
                bodyOut = RuleBase64.encode(httpResult.bodyBytes, false)
            } else {
                bodyOut = Self.decodeTextBody(httpResult.bodyBytes, explicitCharset: charset, contentType: httpResult.contentType)
            }
            let outCookies: [String: String] = rule.engineApi < 2 ? [:] : RuleSessions.get(rule: rule, url: url)
            return [
                "url": url,
                "status": status,
                "body": bodyOut,
                "headers": safeHeaders,
                "cookies": outCookies
            ]
        }
        throw RuleError("重定向过多")
    }

    private struct SingleHttpResult {
        let statusCode: Int
        let contentType: String?
        let location: String?
        let responseCookies: [String: String]
        let bodyBytes: Data
    }

    private func executeOnce(
        url: String,
        method: String,
        headers: [String: String],
        cookies: [String: String],
        bodyBytes: Data?,
        deadlineMs: Int64
    ) throws -> SingleHttpResult {
        try checkCall()
        let remainingMs = min(Int64(timeoutMillis), max(0, deadlineMs - Self.nowMillis()))
        if remainingMs <= 0 {
            throw RuleError("规则网络请求超时")
        }
        guard let targetUrl = URL(string: url) else {
            throw RuleError("请求地址无效")
        }

        var req = URLRequest(url: targetUrl)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = max(1.0, Double(remainingMs) / 1000.0)
        req.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        if !headers.keys.contains(where: { $0.caseInsensitiveCompare("Referer") == .orderedSame }) {
            req.setValue(rule.baseUrl + "/", forHTTPHeaderField: "Referer")
        }
        if !cookies.isEmpty {
            req.setValue(RuleSessions.header(cookies), forHTTPHeaderField: "Cookie")
        }
        var hasContentType = false
        for (k, v) in headers {
            if k.caseInsensitiveCompare("Content-Type") == .orderedSame {
                hasContentType = true
            }
            req.setValue(v, forHTTPHeaderField: k)
        }
        if method == "POST" {
            if !hasContentType {
                req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            }
            if let bodyBytes {
                req.httpBody = bodyBytes
            }
        }

        final class Box: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var error: Error?
        }
        let box = Box()
        let sema = DispatchSemaphore(value: 0)
        let dataTask = Self.sharedSession.dataTask(with: req) { d, r, e in
            box.data = d
            box.response = r
            box.error = e
            sema.signal()
        }
        let handle = try cancelToken.register {
            dataTask.cancel()
        }
        defer { handle.close() }

        dataTask.resume()
        let waitResult = sema.wait(timeout: .now() + .milliseconds(Int(remainingMs) + 250))
        if waitResult == .timedOut {
            dataTask.cancel()
            throw RuleError("规则网络请求超时")
        }
        if isAborted {
            dataTask.cancel()
            throw RuleCancelledError("规则调用已取消")
        }
        if let err = box.error {
            let nsErr = err as NSError
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                throw RuleCancelledError("规则调用已取消")
            }
            throw err
        }
        guard let http = box.response as? HTTPURLResponse else {
            throw RuleError("无效的网络响应")
        }
        let payload = box.data ?? Data()
        if payload.count > Self.maxBodyBytes {
            throw RuleError("站点响应超过 6MiB")
        }

        var contentType: String?
        var location: String?
        for (rawK, rawV) in http.allHeaderFields {
            let k = String(describing: rawK)
            let v = String(describing: rawV)
            if k.caseInsensitiveCompare("Content-Type") == .orderedSame {
                contentType = v
            } else if k.caseInsensitiveCompare("Location") == .orderedSame {
                location = v
            }
        }
        let respCookies = Self.parseResponseCookies(http: http, url: targetUrl)
        return SingleHttpResult(
            statusCode: http.statusCode,
            contentType: contentType,
            location: location,
            responseCookies: respCookies,
            bodyBytes: payload
        )
    }

    private static func parseResponseCookies(http: HTTPURLResponse, url: URL) -> [String: String] {
        var headerStrings = [String: String]()
        var rawSetCookies = [String]()
        for (k, v) in http.allHeaderFields {
            let key = String(describing: k)
            let val = String(describing: v)
            headerStrings[key] = val
            if key.caseInsensitiveCompare("Set-Cookie") == .orderedSame ||
               key.caseInsensitiveCompare("Set-Cookie2") == .orderedSame {
                rawSetCookies.append(val)
            }
        }
        var parsed = [String: String]()
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerStrings, for: url)
        for c in cookies {
            if isValidCookieNameValue(name: c.name, value: c.value) {
                parsed[c.name] = c.value
            }
        }
        for (name, value) in parseLenientSetCookies(rawSetCookies) where parsed[name] == nil {
            parsed[name] = value
        }
        return parsed
    }

    internal static func parseLenientSetCookies(_ rawHeaders: [String]) -> [String: String] {
        var parsed = [String: String]()
        for rawHeader in rawHeaders {
            for candidate in splitFoldedSetCookieHeader(rawHeader) {
                let firstPart = candidate.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? candidate
                guard let eqIdx = firstPart.firstIndex(of: "=") else { continue }
                let name = firstPart[..<eqIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = firstPart[firstPart.index(after: eqIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidCookieNameValue(name: name, value: value) {
                    parsed[name] = value
                }
            }
        }
        return parsed
    }

    private static func splitFoldedSetCookieHeader(_ rawHeader: String) -> [String] {
        // HTTP responses may join multiple Set-Cookie headers with commas; only split before a new `name=` pair so Expires dates stay intact.
        guard let regex = try? NSRegularExpression(pattern: #",\s*(?=[A-Za-z0-9_.$-]{1,128}=)"#) else {
            return [rawHeader]
        }
        let ns = rawHeader as NSString
        let matches = regex.matches(in: rawHeader, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty {
            return [rawHeader]
        }
        var segments = [String]()
        var cursor = 0
        for m in matches {
            let len = m.range.location - cursor
            if len > 0 {
                segments.append(ns.substring(with: NSRange(location: cursor, length: len)))
            }
            cursor = m.range.location + m.range.length
        }
        if cursor <= ns.length {
            segments.append(ns.substring(from: cursor))
        }
        return segments
    }

    private static func isValidCookieNameValue(name: String, value: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9_.$-]{1,128}$"#, options: .regularExpression) != nil &&
            value.count <= 4096 &&
            !value.contains(";") &&
            !value.contains("\r") &&
            !value.contains("\n")
    }

    private static func isTransientNetworkError(_ error: Error) -> Bool {
        let nsErr = error as NSError
        guard nsErr.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorSecureConnectionFailed,
            NSURLErrorCannotConnectToHost
        ].contains(nsErr.code)
    }

    static func decodeTextBody(_ data: Data, explicitCharset: String, contentType: String?) -> String {
        var bytes = data
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            bytes = bytes.dropFirst(3)
        }
        let detected = resolveCharset(explicitCharset: explicitCharset, contentType: contentType, head: bytes.prefix(4096))
        if detected == "GBK" || detected == "GB2312" || detected == "GB18030" {
            let cfEnc = CFStringEncodings.GB_18030_2000.rawValue
            let nsEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEnc)))
            if let str = String(data: bytes, encoding: nsEnc) {
                return str
            }
        } else if detected == "BIG5" {
            let cfEnc = CFStringEncodings.big5.rawValue
            let nsEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEnc)))
            if let str = String(data: bytes, encoding: nsEnc) {
                return str
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func resolveCharset(explicitCharset: String, contentType: String?, head: Data) -> String {
        if !explicitCharset.isEmpty {
            return explicitCharset.uppercased()
        }
        if let ct = contentType,
           let range = ct.range(of: #"charset\s*=\s*["']?([A-Za-z0-9_-]+)"#, options: [.regularExpression, .caseInsensitive]) {
            let sub = String(ct[range])
            if let eq = sub.firstIndex(of: "=") {
                let raw = sub[sub.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"';")).uppercased()
                if raw.contains("GB") { return "GB18030" }
                if raw.contains("BIG5") { return "BIG5" }
                if raw.contains("UTF-8") || raw.contains("UTF8") { return "UTF-8" }
            }
        }
        let asciiHead = String(decoding: head, as: UTF8.self)
        if let range = asciiHead.range(of: #"<meta[^>]+charset\s*=\s*["']?([A-Za-z0-9_-]+)"#, options: [.regularExpression, .caseInsensitive]) {
            let sub = String(asciiHead[range]).uppercased()
            if sub.contains("GBK") || sub.contains("GB2312") || sub.contains("GB18030") { return "GB18030" }
            if sub.contains("BIG5") { return "BIG5" }
        }
        return "UTF-8"
    }
}

// MARK: - RuleImages (Network Open / Cover Refresh / Header Application)

extension RuleImages {
    public static let coverConnectTimeoutMs = 6000
    public static let coverReadTimeoutMs = 10000
    public static let defaultConnectTimeoutMs = 10000
    public static let defaultReadTimeoutMs = 25000
    public static let imageAcceptHeader = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8"

    public struct ImageFetchResult: @unchecked Sendable {
        public let resolved: Resolved
        public let data: Data
        public let statusCode: Int
        public let contentType: String?
        public let finalUrl: String

        public init(resolved: Resolved, data: Data, statusCode: Int, contentType: String?, finalUrl: String) {
            self.resolved = resolved
            self.data = data
            self.statusCode = statusCode
            self.contentType = contentType
            self.finalUrl = finalUrl
        }
    }

    public static func open(
        catalog: RuleCatalog,
        tagged: String,
        debug: Bool = false,
        cancelToken: RuleCancelToken? = nil
    ) throws -> ImageFetchResult {
        let token = cancelToken ?? RuleCancelToken.current ?? RuleCancelToken()
        var tried = Set<String>()
        var lastError: Error?
        var success = false
        defer {
            if !success {
                invalidateResolved(tagged)
            }
        }
        for attempt in 0..<4 {
            try token.throwIfCancelled()
            let r = try resolve(catalog: catalog, tagged: tagged, force: attempt > 0)
            if attempt > 1 && !tried.insert(r.url).inserted {
                break
            }
            tried.insert(r.url)
            let fetched: ImageFetchResult
            do {
                fetched = try openResolved(
                    r,
                    debug: debug,
                    connectTimeoutMs: defaultConnectTimeoutMs,
                    readTimeoutMs: defaultReadTimeoutMs,
                    cancelToken: token
                )
            } catch let cancelErr as RuleCancelledError {
                throw cancelErr
            } catch {
                lastError = error
                if r.rule.imageRefresh && attempt < 3 && !token.isCancelled {
                    continue
                }
                throw error
            }
            let code = fetched.statusCode
            let canRetry = (attempt == 0 && (code == 403 || code == 410)) ||
                (r.rule.imageRefresh && attempt < 3 && (code >= 400 || isNonImageContentType(fetched.contentType)))
            if canRetry {
                lastError = RuleError("图片请求失败 HTTP \(code)")
                continue
            }
            success = true
            return fetched
        }
        if let lastError {
            throw lastError
        }
        throw RuleError("规则图片地址刷新失败")
    }

    public static func openForCover(
        catalog: RuleCatalog,
        tagged: String,
        debug: Bool = false,
        cancelToken: RuleCancelToken? = nil
    ) throws -> ImageFetchResult {
        let token = cancelToken ?? RuleCancelToken.current ?? RuleCancelToken()
        return try openForCoverWithResolver(
            resolver: { force in try resolve(catalog: catalog, tagged: tagged, force: force) },
            cacheKey: tagged,
            debug: debug,
            connectTimeoutMs: coverConnectTimeoutMs,
            readTimeoutMs: coverReadTimeoutMs,
            cancelToken: token
        )
    }

    internal static func openForCoverWithResolver(
        resolver: (Bool) throws -> Resolved,
        cacheKey: String?,
        debug: Bool,
        connectTimeoutMs: Int,
        readTimeoutMs: Int,
        cancelToken: RuleCancelToken = RuleCancelToken(),
        transport: ((Resolved, Bool, Int, Int, RuleCancelToken) throws -> ImageFetchResult)? = nil
    ) throws -> ImageFetchResult {
        var tried = Set<String>()
        var lastError: Error?
        var success = false
        defer {
            if !success, let cacheKey {
                invalidateResolved(cacheKey)
            }
        }
        for attempt in 0..<3 {
            try cancelToken.throwIfCancelled()
            let r = try resolver(attempt > 0)
            if attempt > 0 && !tried.insert(r.url).inserted {
                break
            }
            tried.insert(r.url)
            let fetched: ImageFetchResult
            do {
                if let transport {
                    fetched = try transport(r, debug, connectTimeoutMs, readTimeoutMs, cancelToken)
                } else {
                    fetched = try openResolved(
                        r,
                        debug: debug,
                        connectTimeoutMs: connectTimeoutMs,
                        readTimeoutMs: readTimeoutMs,
                        cancelToken: cancelToken
                    )
                }
            } catch let cancelErr as RuleCancelledError {
                throw cancelErr
            } catch {
                lastError = error
                if r.rule.imageRefresh && attempt < 2 && !cancelToken.isCancelled {
                    continue
                }
                throw error
            }
            let code = fetched.statusCode
            let canRetry = (attempt == 0 && (code == 403 || code == 410)) ||
                (r.rule.imageRefresh && attempt < 2 && (code >= 400 || isNonImageContentType(fetched.contentType)))
            if canRetry {
                lastError = RuleError("图片请求失败 HTTP \(code)")
                continue
            }
            success = true
            return fetched
        }
        if let lastError {
            throw lastError
        }
        throw RuleError("规则图片地址刷新失败")
    }

    public static func applyImageHeaders(
        to request: inout URLRequest,
        urlString: String,
        referer: String?
    ) {
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(imageAcceptHeader, forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("image", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("no-cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
            if ManwaImageDecoder.usesImageHost(urlString),
               let refUrl = URL(string: referer),
               let scheme = refUrl.scheme,
               let host = refUrl.host {
                let portSuffix = refUrl.port.map { ":\($0)" } ?? ""
                request.setValue("\(scheme)://\(host)\(portSuffix)", forHTTPHeaderField: "Origin")
            }
        }
    }

    private static func openResolved(
        _ r: Resolved,
        debug: Bool,
        connectTimeoutMs: Int,
        readTimeoutMs: Int,
        cancelToken: RuleCancelToken
    ) throws -> ImageFetchResult {
        let guardHttp = RuleHttp(rule: r.rule, debug: debug, cancelToken: cancelToken, timeoutMillis: max(connectTimeoutMs, readTimeoutMs))
        var url = r.url
        var headers = r.headers
        let descriptorCookies = (try? RuleSessions.checked(r.descriptor["cookies"] as? [String: Any])) ?? [:]
        let initialHost = URL(string: r.url)?.host?.lowercased() ?? ""

        for _ in 0..<6 {
            try cancelToken.throwIfCancelled()
            try guardHttp.checkUrl(url)
            guard let targetUrl = URL(string: url) else {
                throw RuleError("图片地址无效")
            }
            var req = URLRequest(url: targetUrl)
            req.httpMethod = "GET"
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = max(1.0, Double(max(connectTimeoutMs, readTimeoutMs)) / 1000.0)
            applyImageHeaders(to: &req, urlString: url, referer: r.referer)
            var cookies = RuleSessions.get(rule: r.rule, url: url)
            if (targetUrl.host?.lowercased() ?? "") == initialHost {
                for (k, v) in descriptorCookies {
                    cookies[k] = v
                }
            }
            if !cookies.isEmpty {
                req.setValue(RuleSessions.header(cookies), forHTTPHeaderField: "Cookie")
            }
            for (k, v) in headers {
                req.setValue(v, forHTTPHeaderField: k)
            }

            final class Box: @unchecked Sendable {
                var data: Data?
                var response: URLResponse?
                var error: Error?
            }
            let box = Box()
            let sema = DispatchSemaphore(value: 0)
            let dataTask = RuleHttp.getSharedSession().dataTask(with: req) { d, resp, err in
                box.data = d
                box.response = resp
                box.error = err
                sema.signal()
            }
            let handle = try cancelToken.register {
                dataTask.cancel()
            }
            defer { handle.close() }

            dataTask.resume()
            let totalWaitMs = max(connectTimeoutMs, readTimeoutMs) + 500
            if sema.wait(timeout: .now() + .milliseconds(totalWaitMs)) == .timedOut {
                dataTask.cancel()
                throw RuleError("图片请求超时")
            }
            if cancelToken.isCancelled {
                dataTask.cancel()
                throw RuleCancelledError("规则调用已取消")
            }
            if let err = box.error {
                let nsErr = err as NSError
                if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                    throw RuleCancelledError("规则调用已取消")
                }
                throw err
            }
            guard let http = box.response as? HTTPURLResponse else {
                throw RuleError("无效的图片响应")
            }
            let status = http.statusCode
            if [301, 302, 303, 307, 308].contains(status) {
                var location: String?
                for (rk, rv) in http.allHeaderFields {
                    if String(describing: rk).caseInsensitiveCompare("Location") == .orderedSame {
                        location = String(describing: rv)
                        break
                    }
                }
                guard let location, !location.isEmpty,
                      let nextUrl = URL(string: location, relativeTo: targetUrl)?.absoluteURL else {
                    throw RuleError("图片重定向缺少地址")
                }
                if (nextUrl.host?.lowercased() ?? "") != (targetUrl.host?.lowercased() ?? "") {
                    headers = [:]
                }
                url = nextUrl.absoluteString
                continue
            }
            var contentType: String?
            for (rk, rv) in http.allHeaderFields {
                if String(describing: rk).caseInsensitiveCompare("Content-Type") == .orderedSame {
                    contentType = String(describing: rv)
                    break
                }
            }
            return ImageFetchResult(
                resolved: r,
                data: box.data ?? Data(),
                statusCode: status,
                contentType: contentType,
                finalUrl: url
            )
        }
        throw RuleError("图片重定向过多")
    }
}

// MARK: - RuleWebRenderer

public enum RuleWebRenderer {
    public static let maxHtmlBytes = 6 * 1024 * 1024
    private static let concurrencyGuard = DispatchSemaphore(value: 2)
    private static let heavyExtensions = [
        ".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif", ".svg", ".ico",
        ".woff", ".woff2", ".ttf", ".otf", ".mp4", ".webm", ".mp3", ".m4a"
    ]

    public static func isErrorOrBlankUrl(_ url: String?) -> Bool {
        guard let url else { return true }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        return lower == "about:blank" || lower.hasPrefix("chrome-error://")
    }

    public static func isDocumentReadyForCapture(pageFinished: Bool, actualUrl: String?, readyState: String?) -> Bool {
        guard pageFinished, !isErrorOrBlankUrl(actualUrl) else { return false }
        let state = (readyState ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state == "complete"
    }

    public static func isBlankHtml(_ html: String?) -> Bool {
        guard let html else { return true }
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        guard let regex = try? NSRegularExpression(pattern: #"</?(?:html|head|body)\b[^>]*>|\s+"#, options: [.caseInsensitive]) else {
            return html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let range = NSRange(location: 0, length: (html as NSString).length)
        let stripped = regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
        return stripped.isEmpty
    }

    public static func isHeavySubresource(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        let lowerPath = (URL(string: path)?.path ?? path).lowercased()
        return heavyExtensions.contains { lowerPath.hasSuffix($0) }
    }

    public static func buildRenderResult(
        requestedUrl: String,
        actualUrl: String?,
        html: String?,
        httpStatus: Int,
        networkError: String?
    ) throws -> [String: Any] {
        let safeActual = actualUrl ?? ""
        let safeHtml = html ?? ""
        let blankOrErrorUrl = isErrorOrBlankUrl(safeActual)
        let blankHtml = isBlankHtml(safeHtml)
        if let networkError, !networkError.isEmpty, (blankOrErrorUrl || blankHtml) {
            throw RuleError("网页加载失败: " + networkError)
        }
        if blankOrErrorUrl {
            if httpStatus >= 400 {
                throw RuleError("网页请求失败 HTTP \(httpStatus)")
            }
            throw RuleError("网页未加载完成")
        }
        if httpStatus >= 400 && blankHtml {
            throw RuleError("网页请求失败 HTTP \(httpStatus)")
        }
        if safeHtml.isEmpty {
            throw RuleError("未能读取渲染后的网页内容")
        }
        if safeHtml.utf8.count > maxHtmlBytes {
            throw RuleError("渲染网页内容超过 6MiB")
        }
        let status = httpStatus >= 400 ? httpStatus : 200
        let chosenUrl = safeActual.isEmpty ? requestedUrl : safeActual
        let finalUrl = chosenUrl.components(separatedBy: "#")[0]
        return [
            "url": finalUrl,
            "status": status,
            "body": safeHtml,
            "headers": [String: String](),
            "cookies": [String: String]()
        ]
    }

    public static func render(
        rule: RuleDefinition,
        http: RuleHttp,
        args: [String: Any],
        cancelToken: RuleCancelToken
    ) throws -> [String: Any] {
        guard rule.engineApi >= 3 && rule.requiresCapability("render") else {
            throw RuleError("此规则未声明网页渲染权限")
        }
        guard let urlString = args["url"] as? String else {
            throw RuleError("网页渲染缺少地址")
        }
        try http.checkUrl(urlString)

        let waitSelector = (args["waitSelector"] as? String) ?? ""
        guard waitSelector.count <= 256 else {
            throw RuleError("等待选择器过长")
        }
        let rawTimeout = (args["timeoutMs"] as? Int) ?? 15000
        let timeoutMs = min(25000, max(3000, rawTimeout))
        let rawWait = (args["waitMs"] as? Int) ?? 300
        let waitMs = min(8000, max(0, rawWait))
        let userAgent = (args["userAgent"] as? String) ?? RuleHttp.defaultUserAgent
        guard userAgent.count <= 512, !userAgent.contains("\r"), !userAgent.contains("\n") else {
            throw RuleError("网页渲染 User-Agent 无效")
        }
        var extraHeaders = [String: String]()
        if let hdrs = args["headers"] as? [String: Any] {
            guard hdrs.count <= 24 else { throw RuleError("网页渲染请求头过多") }
            for (k, v) in hdrs {
                let valStr = String(describing: v)
                try RuleHttp.checkHeader(k, valStr)
                extraHeaders[k] = valStr
            }
        }

        #if canImport(WebKit)
        let acquireTimeout = DispatchTime.now() + .milliseconds(timeoutMs)
        if Thread.isMainThread {
            while concurrencyGuard.wait(timeout: .now()) == .timedOut {
                try cancelToken.throwIfCancelled()
                if DispatchTime.now() >= acquireTimeout {
                    throw RuleError("网页渲染队列繁忙，请稍后重试")
                }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        } else {
            if concurrencyGuard.wait(timeout: acquireTimeout) == .timedOut {
                throw RuleError("网页渲染队列繁忙，请稍后重试")
            }
        }
        defer { concurrencyGuard.signal() }
        try cancelToken.throwIfCancelled()

        return try WebKitHeadlessSession.execute(
            urlString: urlString,
            http: http,
            waitSelector: waitSelector,
            waitMs: waitMs,
            timeoutMs: timeoutMs,
            userAgent: userAgent,
            headers: extraHeaders,
            cancelToken: cancelToken
        )
        #else
        throw RuleError("当前测试环境不支持 WebKit 渲染")
        #endif
    }
}

#if canImport(WebKit)
private final class WebKitNavigationBridge: NSObject, WKNavigationDelegate {
    weak var session: WebKitHeadlessSession?

    init(session: WebKitHeadlessSession) {
        self.session = session
        super.init()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        session?.handleNavigationPolicy(navigationAction: navigationAction, decisionHandler: decisionHandler) ?? decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        session?.handlePageStarted(urlString: webView.url?.absoluteString)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame,
           let httpResp = navigationResponse.response as? HTTPURLResponse,
           httpResp.statusCode >= 400 {
            session?.recordMainHttpStatus(httpResp.statusCode)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        session?.handleNavigationFailure(urlString: webView.url?.absoluteString, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        session?.handleNavigationFailure(urlString: webView.url?.absoluteString, error: error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        session?.handlePageFinished(urlString: webView.url?.absoluteString)
    }
}

private final class WebKitHeadlessSession: @unchecked Sendable {
    private static let ruleListLock = NSLock()
    private static var cachedBlockList: WKContentRuleList?

    private let requestedUrl: String
    private let http: RuleHttp
    private let waitSelector: String
    private let waitMs: Int
    private let timeoutMs: Int
    private var deadline: Date
    private let cancelToken: RuleCancelToken
    private let startedSemaphore = DispatchSemaphore(value: 0)
    private let doneSemaphore = DispatchSemaphore(value: 0)

    private let stateLock = NSLock()
    private var finished = false
    private var pageFinished = false
    private var pollStarted = false
    private var mainHttpStatus = 0
    private var networkError: String?
    private var resultDict: [String: Any]?
    private var resultError: Error?
    private var webView: WKWebView?
    private var navBridge: WebKitNavigationBridge?
    private var pollTimer: DispatchSourceTimer?

    private init(requestedUrl: String, http: RuleHttp, waitSelector: String, waitMs: Int, timeoutMs: Int, cancelToken: RuleCancelToken) {
        self.requestedUrl = requestedUrl
        self.http = http
        self.waitSelector = waitSelector
        self.waitMs = waitMs
        self.timeoutMs = timeoutMs
        self.deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        self.cancelToken = cancelToken
    }

    private static func obtainBlockRuleList() -> WKContentRuleList? {
        ruleListLock.lock()
        if let cached = cachedBlockList {
            ruleListLock.unlock()
            return cached
        }
        ruleListLock.unlock()

        let rulesJson = #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}},{"trigger":{"url-filter":".*\\.[aA][vV][iI][fF]$"},"action":{"type":"block"}},{"trigger":{"url-filter":".*\\.[aA][vV][iI][fF]\\?.*"},"action":{"type":"block"}}]"#
        var compiled: WKContentRuleList?
        let done = DispatchSemaphore(value: 0)
        let runCompile = {
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "xxcomic.rule.render.blockmedia.v2",
                encodedContentRuleList: rulesJson
            ) { list, _ in
                compiled = list
                done.signal()
            }
        }
        if Thread.isMainThread {
            runCompile()
            let deadline = Date(timeIntervalSinceNow: 15.0)
            while done.wait(timeout: .now()) == .timedOut && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        } else {
            DispatchQueue.main.async(execute: runCompile)
            _ = done.wait(timeout: .now() + .seconds(15))
        }
        if let compiled {
            ruleListLock.lock()
            cachedBlockList = compiled
            ruleListLock.unlock()
        }
        return compiled
    }

    static func execute(
        urlString: String,
        http: RuleHttp,
        waitSelector: String,
        waitMs: Int,
        timeoutMs: Int,
        userAgent: String,
        headers: [String: String],
        cancelToken: RuleCancelToken
    ) throws -> [String: Any] {
        let session = WebKitHeadlessSession(requestedUrl: urlString, http: http, waitSelector: waitSelector, waitMs: waitMs, timeoutMs: timeoutMs, cancelToken: cancelToken)
        let blockList = obtainBlockRuleList()
        try cancelToken.throwIfCancelled()

        let handle = try cancelToken.register {
            session.complete(error: RuleCancelledError("规则调用已取消"))
        }
        defer { handle.close() }

        let startWork = {
            defer { session.startedSemaphore.signal() }
            guard let targetUrl = URL(string: urlString) else {
                session.complete(error: RuleError("网页渲染地址无效"))
                return
            }
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            if #available(iOS 14.0, *) {
                config.defaultWebpagePreferences.allowsContentJavaScript = true
            }
            if let blockList {
                config.userContentController.add(blockList)
            }
            let bridge = WebKitNavigationBridge(session: session)
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
            wv.navigationDelegate = bridge
            wv.customUserAgent = userAgent
            session.stateLock.lock()
            session.webView = wv
            session.navBridge = bridge
            session.deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
            let alreadyDone = session.finished
            session.stateLock.unlock()
            if alreadyDone {
                wv.stopLoading()
                wv.navigationDelegate = nil
                return
            }
            var req = URLRequest(url: targetUrl)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = Double(timeoutMs) / 1000.0
            for (k, v) in headers {
                req.setValue(v, forHTTPHeaderField: k)
            }
            wv.load(req)
            // Fallback poll if didFinish is delayed or suppressed on dynamic pages.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) { [weak session] in
                session?.startPollingIfNeeded(initialDelayMs: 250)
            }
        }

        if Thread.isMainThread {
            startWork()
            let outerDeadline = Date(timeIntervalSinceNow: Double(timeoutMs + 1500) / 1000.0)
            while session.doneSemaphore.wait(timeout: .now()) == .timedOut {
                if cancelToken.isCancelled {
                    session.complete(error: RuleCancelledError("规则调用已取消"))
                    break
                }
                if Date() >= outerDeadline {
                    session.complete(error: RuleError("网页渲染超时"))
                    break
                }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.015))
            }
        } else {
            DispatchQueue.main.async(execute: startWork)
            let startupDeadline = Date(timeIntervalSinceNow: 45.0)
            var started = false
            while Date() < startupDeadline {
                if session.startedSemaphore.wait(timeout: .now() + .milliseconds(100)) == .success {
                    started = true
                    break
                }
                if cancelToken.isCancelled {
                    session.complete(error: RuleCancelledError("规则调用已取消"))
                    break
                }
            }
            if !started {
                if !cancelToken.isCancelled {
                    session.complete(error: RuleError("网页渲染启动超时"))
                }
            } else if session.doneSemaphore.wait(timeout: .now() + .milliseconds(timeoutMs + 1500)) == .timedOut {
                session.complete(error: RuleError("网页渲染超时"))
            }
        }

        session.teardownOnMain()
        session.stateLock.lock()
        let dict = session.resultDict
        let err = session.resultError
        session.stateLock.unlock()

        if let err { throw err }
        guard let dict else { throw RuleError("网页渲染未返回内容") }
        return dict
    }

    fileprivate func handlePageStarted(urlString: String?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if !RuleWebRenderer.isErrorOrBlankUrl(urlString) {
            pageFinished = false
            mainHttpStatus = 0
            networkError = nil
        }
    }

    fileprivate func recordMainHttpStatus(_ statusCode: Int) {
        stateLock.lock()
        mainHttpStatus = statusCode
        stateLock.unlock()
    }

    fileprivate func handleNavigationFailure(urlString: String?, error: Error) {
        let desc = error.localizedDescription.isEmpty ? "ERR_\((error as NSError).code)" : error.localizedDescription
        stateLock.lock()
        if finished {
            stateLock.unlock()
            return
        }
        networkError = desc
        let isErrorPage = RuleWebRenderer.isErrorOrBlankUrl(urlString)
        stateLock.unlock()
        if isErrorPage {
            complete(error: RuleError("网页加载失败: " + desc))
        }
    }

    fileprivate func handlePageFinished(urlString: String?) {
        stateLock.lock()
        if finished {
            stateLock.unlock()
            return
        }
        let netErr = networkError
        let blankOrError = RuleWebRenderer.isErrorOrBlankUrl(urlString)
        if let netErr, !netErr.isEmpty, blankOrError {
            stateLock.unlock()
            complete(error: RuleError("网页加载失败: " + netErr))
            return
        }
        if !blankOrError {
            pageFinished = true
        }
        stateLock.unlock()
        startPollingIfNeeded(initialDelayMs: 50)
    }

    fileprivate func handleNavigationPolicy(navigationAction: WKNavigationAction,
                                            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let str = url.absoluteString
        if str == "about:blank" {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame != false {
            let cleanUrl = str.components(separatedBy: "#")[0]
            do {
                try http.checkUrl(cleanUrl)
                decisionHandler(.allow)
            } catch {
                decisionHandler(.cancel)
                complete(error: error)
            }
        } else {
            if !RuleWebRenderer.isHeavySubresource(url.path),
               let host = url.host, http.rule.allows(host),
               (scheme == "https" || http.rule.allowsCleartext(host) || (http.debug && host == "127.0.0.1")) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }

    fileprivate func startPollingIfNeeded(initialDelayMs: Int) {
        stateLock.lock()
        if finished || pollStarted {
            stateLock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        pollStarted = true
        pollTimer?.cancel()
        pollTimer = timer
        stateLock.unlock()

        let selectorJson = RuleScript.quoteJsonString(waitSelector)
        var readySince: Date?
        timer.schedule(deadline: .now() + .milliseconds(initialDelayMs), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.cancelToken.isCancelled {
                self.complete(error: RuleCancelledError("规则调用已取消"))
                return
            }
            self.stateLock.lock()
            let wv = self.webView
            let isDone = self.finished
            let isPageFinished = self.pageFinished
            let netErr = self.networkError
            let httpStatus = self.mainHttpStatus
            let currentDeadline = self.deadline
            self.stateLock.unlock()
            guard !isDone, let wv else { return }

            let now = Date()
            let pastDeadline = now >= currentDeadline || now.addingTimeInterval(0.25) >= currentDeadline

            let captureNow = {
                let extractJs = "JSON.stringify({url:String(location.href||''),body:document&&document.documentElement?document.documentElement.outerHTML:''})"
                wv.evaluateJavaScript(extractJs) { [weak self] val, err in
                    guard let self else { return }
                    if let err {
                        self.complete(error: RuleError("读取渲染 DOM 失败：" + err.localizedDescription))
                        return
                    }
                    guard let jsonStr = val as? String,
                          let data = jsonStr.data(using: .utf8),
                          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                        self.complete(error: RuleError("未能读取渲染后的网页内容"))
                        return
                    }
                    self.stateLock.lock()
                    let latestStatus = self.mainHttpStatus
                    let latestNetErr = self.networkError
                    self.stateLock.unlock()
                    do {
                        let built = try RuleWebRenderer.buildRenderResult(
                            requestedUrl: self.requestedUrl,
                            actualUrl: obj["url"] as? String,
                            html: obj["body"] as? String,
                            httpStatus: latestStatus > 0 ? latestStatus : httpStatus,
                            networkError: latestNetErr ?? netErr
                        )
                        self.complete(dict: built)
                    } catch {
                        self.complete(error: error)
                    }
                }
            }

            if pastDeadline {
                captureNow()
                return
            }

            if self.waitSelector.isEmpty {
                guard isPageFinished else { return }
                let readyJs = "(function(){try{return JSON.stringify({url:String(location.href||''),ready:String(document&&document.readyState||'')});}catch(e){return '';}})()"
                wv.evaluateJavaScript(readyJs) { [weak self] val, _ in
                    guard let self else { return }
                    var actualUrl = ""
                    var readyState = ""
                    if let jsonStr = val as? String,
                       let data = jsonStr.data(using: .utf8),
                       let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        actualUrl = (obj["url"] as? String) ?? ""
                        readyState = (obj["ready"] as? String) ?? ""
                    }
                    if let netErr, !netErr.isEmpty, RuleWebRenderer.isErrorOrBlankUrl(actualUrl) {
                        self.complete(error: RuleError("网页加载失败: " + netErr))
                        return
                    }
                    if RuleWebRenderer.isDocumentReadyForCapture(pageFinished: isPageFinished, actualUrl: actualUrl, readyState: readyState) {
                        if readySince == nil && self.waitMs > 0 {
                            readySince = Date()
                            return
                        }
                        if let readyAt = readySince, Date().timeIntervalSince(readyAt) * 1000.0 < Double(self.waitMs) {
                            return
                        }
                        captureNow()
                    }
                }
                return
            }

            let checkJs = "(function(){try{return JSON.stringify({url:String(location.href||''),found:Boolean(document&&document.querySelector(\(selectorJson)))});}catch(e){return '';}})()"
            wv.evaluateJavaScript(checkJs) { [weak self] val, _ in
                guard let self else { return }
                var actualUrl = ""
                var found = false
                if let jsonStr = val as? String,
                   let data = jsonStr.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    actualUrl = (obj["url"] as? String) ?? ""
                    found = (obj["found"] as? Bool) == true
                }
                if let netErr, !netErr.isEmpty, RuleWebRenderer.isErrorOrBlankUrl(actualUrl) {
                    self.complete(error: RuleError("网页加载失败: " + netErr))
                    return
                }
                if found && !RuleWebRenderer.isErrorOrBlankUrl(actualUrl) {
                    if readySince == nil && self.waitMs > 0 {
                        readySince = Date()
                        return
                    }
                    if let readyAt = readySince, Date().timeIntervalSince(readyAt) * 1000.0 < Double(self.waitMs) {
                        return
                    }
                    captureNow()
                }
            }
        }
        timer.resume()
    }

    fileprivate func complete(dict: [String: Any]? = nil, error: Error? = nil) {
        stateLock.lock()
        if finished {
            stateLock.unlock()
            return
        }
        finished = true
        resultDict = dict
        resultError = error
        let timer = pollTimer
        pollTimer = nil
        stateLock.unlock()

        timer?.cancel()
        teardownOnMain()
        doneSemaphore.signal()
    }

    private func teardownOnMain() {
        stateLock.lock()
        let wv = self.webView
        let bridge = self.navBridge
        self.webView = nil
        self.navBridge = nil
        stateLock.unlock()
        guard wv != nil || bridge != nil else { return }
        let cleanup = {
            wv?.stopLoading()
            wv?.navigationDelegate = nil
            wv?.configuration.userContentController.removeAllContentRuleLists()
            _ = bridge
        }
        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }
    }
}
#endif

// MARK: - RuleHostExecutor (Production Budgeted Invoker)

public enum RuleHostExecutor {
    public enum PermitChannel: String, Sendable {
        case foreground
        case search
        case background
    }

    public static let foregroundPermitsCount = 4
    public static let searchPermitsCount = 12
    public static let backgroundPermitsCount = 2
    public static let hostThreadsCount = 24
    public static let hostQueueCapacity = 64
    public static let searchQueueReserveForForeground = 8

    private static let foregroundSemaphore = DispatchSemaphore(value: foregroundPermitsCount)
    private static let searchSemaphore = DispatchSemaphore(value: searchPermitsCount)
    private static let backgroundSemaphore = DispatchSemaphore(value: backgroundPermitsCount)
    private static let hostSlotSemaphore = DispatchSemaphore(value: hostThreadsCount)
    private static let hostQueueLock = NSLock()
    private static var queuedHostTasksCount = 0

    public static func selectPermitChannel(method: String, isBackground: Bool = RuleCallPriority.currentIsBackground()) -> PermitChannel {
        if method == "search" {
            return .search
        }
        return isBackground ? .background : .foreground
    }

    public static func shouldRejectForForegroundReserve(isSearch: Bool, isBackground: Bool, queuedHostTasks: Int) -> Bool {
        (isSearch || isBackground) && queuedHostTasks >= (hostQueueCapacity - searchQueueReserveForForeground)
    }

    public static func hostTimeoutMillis(rule: RuleDefinition, method: String) -> Int {
        method == "search" ? 8000 : min(max(10000, rule.timeoutSeconds * 1000), 20000)
    }

    private static func semaphore(for channel: PermitChannel) -> DispatchSemaphore {
        switch channel {
        case .foreground: return foregroundSemaphore
        case .search: return searchSemaphore
        case .background: return backgroundSemaphore
        }
    }

    public static func errorReply(_ error: Error) -> String {
        var raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if raw.isEmpty {
            raw = "规则网络请求失败"
        }
        if raw.count > 240 {
            raw = String(raw.prefix(240))
        }
        let prefix = raw.contains("RULE_VERIFICATION_REQUIRED:") ? "" :
            ((String(describing: type(of: error)).contains("VerificationRequired") || raw.contains("需要验证")) ? "RULE_VERIFICATION_REQUIRED:" : "")
        let payload: [String: Any] = [
            "status": 599,
            "url": "",
            "body": "",
            "error": prefix + raw
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return #"{"status":599,"url":"","body":"","error":"规则网络请求失败"}"#
    }

    public static func invoke(
        rule: RuleDefinition,
        method: String,
        args: [Any],
        debug: Bool,
        cancelToken: RuleCancelToken? = nil
    ) throws -> String {
        let token = cancelToken ?? RuleCancelToken.current ?? RuleCancelToken()
        try token.throwIfCancelled()

        let isSearch = (method == "search")
        let isBackground = RuleCallPriority.currentIsBackground()
        let channel = selectPermitChannel(method: method, isBackground: isBackground)
        let semaphore = Self.semaphore(for: channel)
        let acquireBudgetSec = isSearch ? 10.0 : 25.0
        let deadline = Date(timeIntervalSinceNow: acquireBudgetSec)

        while semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            try token.throwIfCancelled()
            if Date() >= deadline {
                let msg: String
                switch channel {
                case .search: msg = "搜索并发繁忙，请稍后重试"
                case .background: msg = "后台规则任务繁忙，请稍后重试"
                case .foreground: msg = "站源请求繁忙，请稍后重试"
                }
                throw RuleError(msg)
            }
        }
        defer { semaphore.signal() }
        try token.throwIfCancelled()

        let httpTimeoutMs = hostTimeoutMillis(rule: rule, method: method)
        let http = RuleHttp(rule: rule, debug: debug, cancelToken: token, timeoutMillis: httpTimeoutMs)

        return try RuleCancelToken.withCurrent(token) {
            try RuleScript.invoke(rule: rule, method: method, args: args) { op, rawData in
                try token.throwIfCancelled()
                guard let bytes = rawData.data(using: .utf8),
                      let dict = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
                    return errorReply(RuleError("规则宿主参数无效"))
                }

                hostQueueLock.lock()
                if queuedHostTasksCount >= hostQueueCapacity ||
                   shouldRejectForForegroundReserve(isSearch: isSearch, isBackground: isBackground, queuedHostTasks: queuedHostTasksCount) {
                    hostQueueLock.unlock()
                    return errorReply(RuleError("规则宿主队列繁忙，请稍后重试"))
                }
                queuedHostTasksCount += 1
                hostQueueLock.unlock()

                var acquiredHostSlot = false
                defer {
                    if !acquiredHostSlot {
                        hostQueueLock.lock()
                        queuedHostTasksCount = max(0, queuedHostTasksCount - 1)
                        hostQueueLock.unlock()
                    } else {
                        hostSlotSemaphore.signal()
                    }
                }

                while hostSlotSemaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
                    try token.throwIfCancelled()
                }
                hostQueueLock.lock()
                queuedHostTasksCount = max(0, queuedHostTasksCount - 1)
                hostQueueLock.unlock()
                acquiredHostSlot = true

                do {
                    if op == "cache" {
                        return try RuleCache.call(ruleHash: rule.hash, data: dict)
                    }
                    if op == "render" {
                        let rendered = try RuleWebRenderer.render(rule: rule, http: http, args: dict, cancelToken: token)
                        let out = try JSONSerialization.data(withJSONObject: rendered, options: [])
                        return String(decoding: out, as: UTF8.self)
                    }
                    if op == "http" {
                        if (dict["browser"] as? Bool) == true {
                            let reqMethod = ((dict["method"] as? String) ?? "GET").uppercased()
                            guard reqMethod == "GET", dict["body"] == nil,
                                  let url = dict["url"] as? String else {
                                throw RuleError("验证会话仅支持网页 GET")
                            }
                            try http.checkUrl(url)
                            if let html = try RuleWebSessions.fetch(rule: rule, url: url) {
                                guard html.utf8.count <= RuleHttp.maxBodyBytes else {
                                    throw RuleError("站点响应过大")
                                }
                                let resp: [String: Any] = [
                                    "url": url,
                                    "status": 200,
                                    "body": html,
                                    "headers": [String: String](),
                                    "cookies": [String: String]()
                                ]
                                let out = try JSONSerialization.data(withJSONObject: resp, options: [])
                                return String(decoding: out, as: UTF8.self)
                            }
                        }
                        let resp = try http.request(dict)
                        let out = try JSONSerialization.data(withJSONObject: resp, options: [])
                        return String(decoding: out, as: UTF8.self)
                    }
                    throw RuleError("不支持的规则宿主操作")
                } catch let cancelErr as RuleCancelledError {
                    throw cancelErr
                } catch {
                    return errorReply(error)
                }
            }
        }
    }
}
