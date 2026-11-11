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
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
    }()

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
            RuleSessions.receive(rule: rule, url: url, fresh: httpResult.responseCookies)
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
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if !cookies.isEmpty {
            req.setValue(RuleSessions.header(cookies), forHTTPHeaderField: "Cookie")
        }
        if let bodyBytes {
            req.httpBody = bodyBytes
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
        for (k, v) in http.allHeaderFields {
            headerStrings[String(describing: k)] = String(describing: v)
        }
        var parsed = [String: String]()
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerStrings, for: url)
        for c in cookies {
            if c.name.range(of: #"^[A-Za-z0-9_.$-]{1,128}$"#, options: .regularExpression) != nil &&
               c.value.count <= 4096 && !c.value.contains(";") {
                parsed[c.name] = c.value
            }
        }
        return parsed
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
        let detected = resolveCharset(explicitCharset: explicitCharset, contentType: contentType, head: bytes.prefix(2048))
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

// MARK: - RuleWebRenderer

public enum RuleWebRenderer {
    public static let maxHtmlBytes = 6 * 1024 * 1024
    private static let concurrencyGuard = DispatchSemaphore(value: 2)

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
private final class WebKitHeadlessSession: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private static let ruleListLock = NSLock()
    private static var cachedBlockList: WKContentRuleList?

    private let http: RuleHttp
    private let waitSelector: String
    private let waitMs: Int
    private let timeoutMs: Int
    private let deadline: Date
    private let cancelToken: RuleCancelToken
    private let doneSemaphore = DispatchSemaphore(value: 0)

    private let stateLock = NSLock()
    private var finished = false
    private var resultDict: [String: Any]?
    private var resultError: Error?
    private var webView: WKWebView?
    private var pollTimer: DispatchSourceTimer?

    private init(http: RuleHttp, waitSelector: String, waitMs: Int, timeoutMs: Int, cancelToken: RuleCancelToken) {
        self.http = http
        self.waitSelector = waitSelector
        self.waitMs = waitMs
        self.timeoutMs = timeoutMs
        self.deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        self.cancelToken = cancelToken
        super.init()
    }

    private static func obtainBlockRuleList() -> WKContentRuleList? {
        ruleListLock.lock()
        if let cached = cachedBlockList {
            ruleListLock.unlock()
            return cached
        }
        ruleListLock.unlock()

        let rulesJson = #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}}]"#
        var compiled: WKContentRuleList?
        let done = DispatchSemaphore(value: 0)
        let runCompile = {
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "xxcomic.rule.render.blockmedia",
                encodedContentRuleList: rulesJson
            ) { list, _ in
                compiled = list
                done.signal()
            }
        }
        if Thread.isMainThread {
            runCompile()
            let deadline = Date(timeIntervalSinceNow: 2.0)
            while done.wait(timeout: .now()) == .timedOut && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        } else {
            DispatchQueue.main.async(execute: runCompile)
            _ = done.wait(timeout: .now() + .seconds(2))
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
        let session = WebKitHeadlessSession(http: http, waitSelector: waitSelector, waitMs: waitMs, timeoutMs: timeoutMs, cancelToken: cancelToken)
        let blockList = obtainBlockRuleList()

        let handle = try cancelToken.register {
            session.complete(error: RuleCancelledError("规则调用已取消"))
        }
        defer { handle.close() }

        let startWork = {
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
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
            wv.navigationDelegate = session
            wv.customUserAgent = userAgent
            session.stateLock.lock()
            session.webView = wv
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
            if session.doneSemaphore.wait(timeout: .now() + .milliseconds(timeoutMs + 1500)) == .timedOut {
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

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
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
        // Only enforce domain/cleartext check on main frame navigations; block non-HTTP schemes
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
            // Subframe: only allow authorized hosts
            if let host = url.host, http.rule.allows(host),
               (scheme == "https" || http.rule.allowsCleartext(host) || (http.debug && host == "127.0.0.1")) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        complete(error: RuleError("网页加载失败：" + error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        complete(error: RuleError("网页渲染失败：" + error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scheduleExtraction()
    }

    private func scheduleExtraction() {
        let selectorJson = RuleScript.quoteJsonString(waitSelector)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        stateLock.lock()
        if finished {
            stateLock.unlock()
            return
        }
        pollTimer?.cancel()
        pollTimer = timer
        stateLock.unlock()

        var readySince: Date?
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(120))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.cancelToken.isCancelled {
                self.complete(error: RuleCancelledError("规则调用已取消"))
                return
            }
            self.stateLock.lock()
            let wv = self.webView
            let isDone = self.finished
            self.stateLock.unlock()
            guard !isDone, let wv else { return }

            let pastDeadline = Date().addingTimeInterval(0.25) >= self.deadline
            let checkAndDumpJs: String
            if self.waitSelector.isEmpty || pastDeadline {
                checkAndDumpJs = "JSON.stringify({ready:true,url:String(location.href||''),body:document.documentElement?document.documentElement.outerHTML:''})"
            } else if let readyAt = readySince {
                if Date().timeIntervalSince(readyAt) * 1000.0 < Double(self.waitMs) {
                    return
                }
                checkAndDumpJs = "JSON.stringify({ready:true,url:String(location.href||''),body:document.documentElement?document.documentElement.outerHTML:''})"
            } else {
                checkAndDumpJs = "(function(){var el=document.querySelector(\(selectorJson));if(!el)return JSON.stringify({ready:false});return JSON.stringify({ready:true,url:String(location.href||''),body:document.documentElement?document.documentElement.outerHTML:''});})()"
            }
            wv.evaluateJavaScript(checkAndDumpJs) { [weak self] val, err in
                guard let self else { return }
                if let err {
                    self.complete(error: RuleError("读取渲染 DOM 失败：" + err.localizedDescription))
                    return
                }
                guard let jsonStr = val as? String,
                      let data = jsonStr.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    return
                }
                if (obj["ready"] as? Bool) == true {
                    if !self.waitSelector.isEmpty && !pastDeadline && readySince == nil && self.waitMs > 0 {
                        readySince = Date()
                        return
                    }
                    let body = (obj["body"] as? String) ?? ""
                    if body.utf8.count > RuleWebRenderer.maxHtmlBytes {
                        self.complete(error: RuleError("渲染网页内容超过 6MiB"))
                        return
                    }
                    let finalUrl = ((obj["url"] as? String) ?? "").components(separatedBy: "#")[0]
                    self.complete(dict: [
                        "url": finalUrl,
                        "status": 200,
                        "body": body,
                        "headers": [String: String](),
                        "cookies": [String: String]()
                    ])
                }
            }
        }
        timer.resume()
    }

    private func complete(dict: [String: Any]? = nil, error: Error? = nil) {
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
        let cleanup = { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let wv = self.webView
            self.webView = nil
            self.stateLock.unlock()
            wv?.stopLoading()
            wv?.navigationDelegate = nil
            wv?.configuration.userContentController.removeAllContentRuleLists()
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
    public static let searchPermitsCount = 12
    public static let foregroundPermitsCount = 4

    private static let searchSemaphore = DispatchSemaphore(value: searchPermitsCount)
    private static let foregroundSemaphore = DispatchSemaphore(value: foregroundPermitsCount)

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
        let semaphore = isSearch ? searchSemaphore : foregroundSemaphore
        let acquireBudgetSec = isSearch ? 10.0 : 25.0
        let deadline = Date(timeIntervalSinceNow: acquireBudgetSec)

        while semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            try token.throwIfCancelled()
            if Date() >= deadline {
                throw RuleError(isSearch ? "搜索并发繁忙，请稍后重试" : "站源请求繁忙，请稍后重试")
            }
        }
        defer { semaphore.signal() }
        try token.throwIfCancelled()

        let httpTimeoutMs = isSearch ? 8000 : min(max(10000, rule.timeoutSeconds * 1000), 20000)
        let http = RuleHttp(rule: rule, debug: debug, cancelToken: token, timeoutMillis: httpTimeoutMs)

        return try RuleCancelToken.withCurrent(token) {
            try RuleScript.invoke(rule: rule, method: method, args: args) { op, rawData in
                try token.throwIfCancelled()
                guard let bytes = rawData.data(using: .utf8),
                      let dict = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
                    return errorReply(RuleError("规则宿主参数无效"))
                }
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
