import Foundation
import XCTest
@testable import ComicCore

final class Mh18VerificationRulesTests: XCTestCase {
    private typealias Rules = Mh18VerificationRules
    private let requested = URL(string: "https://18mh.org/manga")!

    func testHTTPChallengeTakesPriorityOverSuccessOrFailure() {
        XCTAssertEqual(Rules.httpAction(statusCode: 200, mitigated: nil, body: "business"), .returnBody)
        XCTAssertEqual(Rules.httpAction(statusCode: 399, mitigated: nil, body: "business"), .returnBody)
        XCTAssertEqual(Rules.httpAction(statusCode: 403, mitigated: "CHALLENGE", body: ""), .verificationRequired)
        XCTAssertEqual(Rules.httpAction(statusCode: 200, mitigated: nil, body: "Checking your browser"), .verificationRequired)
        XCTAssertEqual(Rules.httpAction(statusCode: 403, mitigated: nil, body: "Forbidden"), .fail)
        XCTAssertEqual(Rules.httpAction(statusCode: 500, mitigated: nil, body: "Server error"), .fail)
        XCTAssertEqual(Rules.httpAction(statusCode: 199, mitigated: nil, body: ""), .fail)
    }

    func testEachChallengeMarkerIncludingModernMarkupAndLocalizedText() {
        for marker in ["/orchestrate/chl_page/", "_cf_chl_opt", "challenge-error-text", "cf-chl-widget", "cf-turnstile-response", "just a moment", "attention required", "checking your browser", "performing security verification", "verify you are human", "请稍候", "正在验证", "安全验证"] {
            XCTAssertTrue(Rules.isChallenge(body: marker.uppercased()), marker)
        }
        XCTAssertTrue(Rules.isChallenge(url: "https://18mh.org/orchestrate/chl_page/", body: ""))
        XCTAssertTrue(Rules.isChallenge(title: "Just a moment", body: ""))
    }

    func testPrecursorScriptDoesNotPreventReadingBusinessPage() {
        let body = "<title>全部漫画</title><script src='/cdn-cgi/challenge-platform/scripts/precursor/main.js'></script>"
        XCTAssertFalse(Rules.isChallenge(body: body))
        XCTAssertEqual(Rules.httpAction(statusCode: 200, mitigated: nil, body: body), .returnBody)
    }

    func testInteractivePreflightRequiresCatalogOrExplicitChallenge() {
        let catalog = #"<a href="/manga/hero"><img src="a.jpg"><h3 class="cardtitle">漫画</h3></a>"#
        XCTAssertEqual(Rules.interactiveAction(statusCode: 200, mitigated: nil, body: catalog), .complete)
        XCTAssertEqual(Rules.interactiveAction(statusCode: 403, mitigated: "challenge", body: ""), .openBrowser)
        XCTAssertEqual(Rules.interactiveAction(statusCode: 200, mitigated: nil, body: "not ready"), .fail)
        XCTAssertEqual(Rules.interactiveAction(statusCode: 503, mitigated: nil, body: catalog), .fail)
    }

    func testExpectedCatalogRequiresSameProtocolAndMangaOnBothURLs() {
        for actual in ["https://18mh.org/manga", "https://www.18mh.org/manga///", "https://18mh.org/manga?x=1"] {
            XCTAssertTrue(Rules.isExpectedPage(requested: requested, actual: URL(string: actual)!))
        }
        for actual in ["https://18mh.org/", "https://18mh.org/manga/hero", "https://evil18mh.org/manga", "https://18mh.org.evil.com/manga", "http://18mh.org/manga"] {
            XCTAssertFalse(Rules.isExpectedPage(requested: requested, actual: URL(string: actual)!))
        }
        XCTAssertFalse(Rules.isExpectedPage(requested: URL(string: "https://18mh.org/")!, actual: requested))
    }

    func testNavigationAllowsOnlySameSiteOrCloudflareChallengePath() {
        for actual in ["https://www.18mh.org/manga", "https://18mh.org/cdn-cgi/challenge-platform/x", "https://challenges.cloudflare.com/cdn-cgi/challenge-platform/h/g/turnstile", "https://sub.challenges.cloudflare.com/turnstile/v1"] {
            XCTAssertFalse(Rules.shouldBlockNavigation(requested: requested, actual: URL(string: actual)!))
        }
        for actual in ["https://ads.example/redirect", "http://18mh.org/manga", "https://challenges.cloudflare.com/ads", "https://evilchallenges.cloudflare.com/turnstile/v1", "https://challenges.cloudflare.com.evil/turnstile/v1"] {
            XCTAssertTrue(Rules.shouldBlockNavigation(requested: requested, actual: URL(string: actual)!))
        }
    }

    func testPercentEncodedCatalogPathDoesNotBroadenAndroidExpectedPageRule() {
        XCTAssertFalse(Rules.isExpectedPage(requested: requested, actual: URL(string: "https://18mh.org/%6danga")!))
        XCTAssertTrue(Rules.shouldBlockNavigation(requested: requested, actual: URL(string: "https://challenges.cloudflare.com/%74urnstile/v1")!))
    }

    func testSameSitePreservesAndroidParentAndPortSemantics() {
        XCTAssertTrue(Rules.sameSite(requested: URL(string: "https://www.18mh.org/manga")!, actual: requested))
        XCTAssertTrue(Rules.sameSite(requested: requested, actual: URL(string: "https://18mh.org:8443/manga")!))
        XCTAssertFalse(Rules.sameSite(requested: requested, actual: URL(string: "http://18mh.org/manga")!))
    }

    func testPageInspectionWaitsForChallengeOrIncompleteDOM() {
        XCTAssertEqual(Rules.pageAction(challenge: true, expectedPage: false, browserCatalog: false), .wait)
        XCTAssertEqual(Rules.pageAction(challenge: true, expectedPage: true, browserCatalog: true), .wait)
        XCTAssertEqual(Rules.pageAction(challenge: false, expectedPage: true, browserCatalog: false), .wait)
        XCTAssertEqual(Rules.pageAction(challenge: false, expectedPage: true, browserCatalog: true), .probe)
        XCTAssertEqual(Rules.pageAction(challenge: false, expectedPage: false, browserCatalog: true), .fail)
    }

    func testProbeChallengeRequestsReloadOrdinaryFailureStops() {
        XCTAssertEqual(Rules.probeAction(.verificationRequired), .reload)
        XCTAssertEqual(Rules.probeAction(.returnBody), .complete)
        XCTAssertEqual(Rules.probeAction(.fail), .fail)
    }

    func testSuccessRequiresBothBrowserDOMAndProbeCatalog() {
        XCTAssertTrue(Rules.verificationComplete(browserCatalog: true, probeCatalog: true))
        XCTAssertFalse(Rules.verificationComplete(browserCatalog: true, probeCatalog: false))
        XCTAssertFalse(Rules.verificationComplete(browserCatalog: false, probeCatalog: true))
        XCTAssertFalse(Rules.verificationComplete(browserCatalog: false, probeCatalog: false))
    }

    func testStaleNavigationCancelledAttemptAndStoppedProbeCannotComplete() {
        XCTAssertTrue(Rules.probeCanComplete(activeAttempt: true, probeRunning: true, stopped: false, capturedNavigation: 3, currentNavigation: 3))
        XCTAssertFalse(Rules.probeCanComplete(activeAttempt: true, probeRunning: true, stopped: false, capturedNavigation: 3, currentNavigation: 4))
        XCTAssertFalse(Rules.probeCanComplete(activeAttempt: false, probeRunning: true, stopped: false, capturedNavigation: 3, currentNavigation: 3))
        XCTAssertFalse(Rules.probeCanComplete(activeAttempt: true, probeRunning: false, stopped: false, capturedNavigation: 3, currentNavigation: 3))
        XCTAssertFalse(Rules.probeCanComplete(activeAttempt: true, probeRunning: true, stopped: true, capturedNavigation: 3, currentNavigation: 3))
    }

    func testAbsoluteDeadlineDoesNotRestartOnLaterProbeAndTimeoutIsTerminal() {
        let deadline = Rules.requestDeadline(startedAt: 1)
        XCTAssertEqual(Rules.remainingRequest(deadline: deadline, now: 31), 90)
        XCTAssertEqual(Rules.remainingRequest(deadline: deadline, now: 120), 1)
        XCTAssertEqual(Rules.remainingRequest(deadline: deadline, now: 122), 0)
        XCTAssertTrue(Rules.shouldStopForTimeout(active: true, succeeded: false))
        XCTAssertFalse(Rules.shouldStopForTimeout(active: false, succeeded: false))
        XCTAssertFalse(Rules.shouldStopForTimeout(active: true, succeeded: true))
    }

    func testVerifiedRequestsRequireRetainedBrowserContext() {
        XCTAssertEqual(Rules.requestTransport(browserContextReady: false), .http)
        XCTAssertEqual(Rules.requestTransport(browserContextReady: true), .browserContext)
    }
}
