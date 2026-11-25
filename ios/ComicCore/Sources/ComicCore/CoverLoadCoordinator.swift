import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thread-safe in-flight request coalescer with generation-epoch cancellation protection.
public final class CoverInFlightCoalescer<T>: @unchecked Sendable {
    public typealias Listener = @Sendable (T?, Error?, Bool) -> Void

    private final class WaiterBucket {
        let epoch: Int64
        var listeners: [Listener] = []

        init(epoch: Int64) {
            self.epoch = epoch
        }
    }

    private let lock = NSLock()
    private var inFlight: [String: WaiterBucket] = [:]
    private var epoch: Int64 = 0

    public init() {}

    @discardableResult
    public func register(key: String?, listener: Listener?) -> Bool {
        registerLeader(key: key, listener: listener) >= 0
    }

    /// Registers a listener for `key`. Returns the active epoch (`>= 0`) if this caller is the
    /// leader that should perform the fetch, or `-1` if coalesced onto an existing in-flight request.
    public func registerLeader(key: String?, listener: Listener?) -> Int64 {
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            listener?(nil, NSError(
                domain: "CoverLoadCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cover key must not be empty"]
            ), false)
            return -1
        }
        lock.lock()
        if let existing = inFlight[key] {
            if let listener {
                existing.listeners.append(listener)
            }
            lock.unlock()
            return -1
        }
        let created = WaiterBucket(epoch: epoch)
        if let listener {
            created.listeners.append(listener)
        }
        inFlight[key] = created
        let currentEpoch = epoch
        lock.unlock()
        return currentEpoch
    }

    public func isEpochActive(_ expectedEpoch: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return epoch == expectedEpoch
    }

    public func finish(key: String?, value: T?, error: Error?, cancelled: Bool) {
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lock.lock()
        let bucket = inFlight.removeValue(forKey: key)
        lock.unlock()
        guard let waiters = bucket?.listeners, !waiters.isEmpty else { return }
        for listener in waiters {
            listener(value, error, cancelled)
        }
    }

    public func finishForEpoch(key: String?, expectedEpoch: Int64, value: T?, error: Error?, cancelled: Bool) {
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lock.lock()
        guard let bucket = inFlight[key], bucket.epoch == expectedEpoch else {
            lock.unlock()
            return
        }
        inFlight.removeValue(forKey: key)
        lock.unlock()
        guard !bucket.listeners.isEmpty else { return }
        for listener in bucket.listeners {
            listener(value, error, cancelled)
        }
    }

    public func clear() {
        lock.lock()
        epoch += 1
        inFlight.removeAll()
        lock.unlock()
    }
}

/// Pure Swift coordinator for comic cover candidate selection, retry classification,
/// throttled sanitized failure logging, and in-flight cover request coalescing.
public final class CoverLoadCoordinator<T>: @unchecked Sendable {
    public typealias InFlightCoalescer = CoverInFlightCoalescer<T>
    public typealias Listener = InFlightCoalescer.Listener

    public static var maxCandidateUrls: Int { 3 }
    public static var maxLoggedHosts: Int { 128 }
    public static var hostLogCooldownMs: Int64 { 600_000 }

    private static var maxCauseDepth: Int { 32 }

    private let inFlight = InFlightCoalescer()
    private let logLock = NSLock()
    private var loggedHostTimestamps: [String: Int64] = [:]
    private var loggedHostLruOrder: [String] = []

    public init() {}

    public static func buildCandidateUrls(primaryUrl: String?, fallbackUrls: [String]?) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        result.reserveCapacity(maxCandidateUrls)

        if let primary = primaryUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            if seen.insert(primary).inserted {
                result.append(primary)
            }
        }
        if let fallbackUrls {
            for candidate in fallbackUrls {
                if result.count >= maxCandidateUrls { break }
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if seen.insert(trimmed).inserted {
                    result.append(trimmed)
                }
            }
        }
        return result
    }

    public static func extractSafeHost(_ url: String?) -> String {
        guard let url else { return "" }
        let clean = stripFragment(url.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !clean.isEmpty,
              let parsed = parseHttpStyleUrl(clean),
              let host = parsed.host else {
            return ""
        }
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return isValidSafeHost(normalized) ? normalized : ""
    }

    public static func sanitizeUrlForLog(_ url: String?) -> String {
        guard let url else { return "" }
        var clean = stripFragment(url.trimmingCharacters(in: .whitespacesAndNewlines))
        if let qIdx = clean.firstIndex(of: "?") {
            clean = String(clean[..<qIdx])
        }
        guard !clean.isEmpty,
              let parsed = parseHttpStyleUrl(clean),
              !parsed.scheme.isEmpty,
              let host = parsed.host else {
            return ""
        }
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidSafeHost(normalizedHost) else { return "" }

        var out = "\(parsed.scheme.lowercased())://\(normalizedHost)"
        if let port = parsed.port, port > 0 {
            out += ":\(port)"
        }
        if !parsed.path.isEmpty {
            out += parsed.path
        }
        return out
    }

    public static func isRetryableCoverError(_ error: Error?, httpCode: Int) -> Bool {
        if hasNonRetryableCause(error) {
            return false
        }
        if httpCode > 0 {
            return httpCode == 408
                || httpCode == 429
                || (httpCode >= 500 && httpCode <= 599)
        }
        return hasRetryableNetworkCause(error)
    }

    public func shouldLogHostFailure(host: String?, nowMillis: Int64) -> Bool {
        let normalized = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        logLock.lock()
        defer { logLock.unlock() }

        let last = loggedHostTimestamps[normalized]
        if last == nil || nowMillis - last! >= Self.hostLogCooldownMs {
            loggedHostTimestamps[normalized] = nowMillis
            touchHostLruLocked(normalized)
            return true
        }
        touchHostLruLocked(normalized)
        return false
    }

    @discardableResult
    public func register(key: String?, listener: Listener?) -> Bool {
        inFlight.register(key: key, listener: listener)
    }

    public func registerLeader(key: String?, listener: Listener?) -> Int64 {
        inFlight.registerLeader(key: key, listener: listener)
    }

    public func isInFlightEpoch(_ expectedEpoch: Int64) -> Bool {
        inFlight.isEpochActive(expectedEpoch)
    }

    public func finish(key: String?, value: T?, error: Error?, cancelled: Bool) {
        inFlight.finish(key: key, value: value, error: error, cancelled: cancelled)
    }

    public func finishForEpoch(key: String?, expectedEpoch: Int64, value: T?, error: Error?, cancelled: Bool) {
        inFlight.finishForEpoch(key: key, expectedEpoch: expectedEpoch, value: value, error: error, cancelled: cancelled)
    }

    public func clearInFlight() {
        inFlight.clear()
    }

    private func touchHostLruLocked(_ host: String) {
        loggedHostLruOrder.removeAll { $0 == host }
        loggedHostLruOrder.append(host)
        while loggedHostLruOrder.count > Self.maxLoggedHosts {
            let evicted = loggedHostLruOrder.removeFirst()
            loggedHostTimestamps.removeValue(forKey: evicted)
        }
    }

    private static func stripFragment(_ url: String) -> String {
        guard let hashIdx = url.firstIndex(of: "#") else { return url }
        return String(url[..<hashIdx])
    }

    private static func parseHttpStyleUrl(_ raw: String) -> (scheme: String, host: String?, port: Int?, path: String)? {
        guard let comps = URLComponents(string: raw),
              let scheme = comps.scheme, !scheme.isEmpty,
              comps.host != nil else {
            return nil
        }
        return (scheme, comps.host, comps.port, comps.percentEncodedPath)
    }

    private static func isValidSafeHost(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        for scalar in host.unicodeScalars {
            if scalar.properties.isWhitespace || scalar == "/" || scalar == "\\" || scalar == "?" || scalar == "#" {
                return false
            }
        }
        return true
    }

    private static func hasNonRetryableCause(_ error: Error?) -> Bool {
        var current: Error? = error
        var depth = 0
        while let err = current, depth < maxCauseDepth {
            depth += 1
            if err is CancellationError {
                return true
            }
            if let urlErr = err as? URLError {
                switch urlErr.code {
                case .cancelled,
                     .userCancelledAuthentication,
                     .serverCertificateHasBadDate,
                     .serverCertificateUntrusted,
                     .serverCertificateHasUnknownRoot,
                     .serverCertificateNotYetValid,
                     .clientCertificateRejected,
                     .clientCertificateRequired:
                    return true
                default:
                    break
                }
            }
            let ns = err as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorCancelled,
                     NSURLErrorUserCancelledAuthentication,
                     NSURLErrorServerCertificateHasBadDate,
                     NSURLErrorServerCertificateUntrusted,
                     NSURLErrorServerCertificateHasUnknownRoot,
                     NSURLErrorServerCertificateNotYetValid,
                     NSURLErrorClientCertificateRejected,
                     NSURLErrorClientCertificateRequired:
                    return true
                default:
                    break
                }
            }
            current = ns.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return false
    }

    private static func hasRetryableNetworkCause(_ error: Error?) -> Bool {
        var current: Error? = error
        var depth = 0
        while let err = current, depth < maxCauseDepth {
            depth += 1
            if let urlErr = err as? URLError {
                switch urlErr.code {
                case .timedOut,
                     .cannotFindHost,
                     .cannotConnectToHost,
                     .networkConnectionLost,
                     .dnsLookupFailed,
                     .notConnectedToInternet,
                     .secureConnectionFailed,
                     .resourceUnavailable,
                     .internationalRoamingOff,
                     .callIsActive,
                     .dataNotAllowed:
                    return true
                default:
                    break
                }
            }
            let ns = err as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorTimedOut,
                     NSURLErrorCannotFindHost,
                     NSURLErrorCannotConnectToHost,
                     NSURLErrorNetworkConnectionLost,
                     NSURLErrorDNSLookupFailed,
                     NSURLErrorNotConnectedToInternet,
                     NSURLErrorSecureConnectionFailed,
                     NSURLErrorResourceUnavailable:
                    return true
                default:
                    break
                }
            }
            if ns.domain == NSPOSIXErrorDomain {
                return true
            }
            current = ns.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return false
    }
}
