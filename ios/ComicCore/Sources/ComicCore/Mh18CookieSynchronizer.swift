import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Waits for a stable WebKit snapshot before a request may use the shared HTTP jar.
@MainActor
public final class Mh18CookieSynchronizer {
    private var revision = 0
    public init() {}
    public func invalidate() { revision += 1 }
    public func synchronize(read: () async -> [HTTPCookie], storage: HTTPCookieStorage) async {
        while !Task.isCancelled {
            let captured = revision
            let cookies = await read()
            guard !Task.isCancelled else { return }
            guard captured == revision else { continue }
            let siteCookies = cookies.filter(Self.isSiteCookie)
            for cookie in storage.cookies ?? [] where Self.isSiteCookie(cookie) {
                if !siteCookies.contains(where: { $0.domain == cookie.domain && $0.path == cookie.path && $0.name == cookie.name }) { storage.deleteCookie(cookie) }
            }
            for cookie in siteCookies { storage.setCookie(cookie) }
            return
        }
    }
    public static func isSiteCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
        return domain.lowercased() == "18mh.org" || domain.lowercased().hasSuffix(".18mh.org")
    }
}
