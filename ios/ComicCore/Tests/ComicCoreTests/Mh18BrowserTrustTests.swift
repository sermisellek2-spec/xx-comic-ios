import Foundation
import XCTest
@testable import ComicCore

final class Mh18BrowserTrustTests: XCTestCase {
    func testBusinessURLsAllowOnlyHTTPSRootAndDottedSubdomains() {
        for raw in ["https://18mh.org/manga", "https://api.18mh.org:443/chapter/getcontent?m=1&c=2", "https://WWW.18MH.ORG/manga"] {
            XCTAssertTrue(Mh18BrowserTrust.allowsRequest(URL(string: raw)!), raw)
            XCTAssertTrue(Mh18BrowserTrust.allowsNavigation(URL(string: raw)!), raw)
        }
        for raw in ["https://org/manga", "https://evil18mh.org/", "https://18mh.org.evil.com/", "http://18mh.org/", "ftp://18mh.org/", "comic://18mh.org/", "https://18mh.org:444/", "https://user@18mh.org/", "https://user:pass@18mh.org/", "file:///manga", "about:blank"] {
            XCTAssertFalse(Mh18BrowserTrust.allowsRequest(URL(string: raw)!), raw)
            XCTAssertFalse(Mh18BrowserTrust.allowsNavigation(URL(string: raw)!), raw)
        }
    }

    func testCloudflareIsNavigationOnlyAndRestrictedToChallengePaths() {
        for raw in ["https://challenges.cloudflare.com/turnstile/v0/api.js", "https://a.challenges.cloudflare.com:443/cdn-cgi/challenge-platform/h/b"] {
            XCTAssertTrue(Mh18BrowserTrust.allowsNavigation(URL(string: raw)!), raw)
            XCTAssertFalse(Mh18BrowserTrust.allowsRequest(URL(string: raw)!), raw)
        }
        for raw in ["https://challenges.cloudflare.com/", "https://challenges.cloudflare.com/elsewhere/turnstile/", "https://challenges.cloudflare.com/turnstile/../private", "https://challenges.cloudflare.com/turnstile/%2e%2e/private", "https://evilchallenges.cloudflare.com/turnstile/", "https://challenges.cloudflare.com.evil.org/turnstile/", "http://challenges.cloudflare.com/turnstile/", "https://challenges.cloudflare.com:444/turnstile/", "https://user@challenges.cloudflare.com/turnstile/"] {
            XCTAssertFalse(Mh18BrowserTrust.allowsNavigation(URL(string: raw)!), raw)
        }
    }
}
