package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class CloudflareWebViewSessionTest {
    @Test
    public void readyBrowserContextSkipsRepeatedHttpProbe() {
        assertEquals(CloudflareWebViewSession.RequestTransport.BROWSER_CONTEXT,
                CloudflareWebViewSession.requestTransport(true, true));
    }

    @Test
    public void freshPreferredHttpSessionProbesHttp() {
        assertEquals(CloudflareWebViewSession.RequestTransport.HTTP,
                CloudflareWebViewSession.requestTransport(true, false));
    }

    @Test
    public void backgroundViewportIsOptInForMh18Only() {
        assertEquals(-1, CloudflareWebViewSession.backgroundExtent(true));
        assertEquals(1, CloudflareWebViewSession.backgroundExtent(false));
    }

    @Test
    public void browserOnlySourceKeepsNavigation() {
        assertEquals(CloudflareWebViewSession.RequestTransport.BROWSER_NAVIGATION,
                CloudflareWebViewSession.requestTransport(false, false));
    }

    @Test
    public void completeNormalPageIsCaptured() {
        assertEquals(CloudflareWebViewSession.PageAction.CAPTURE,
                CloudflareWebViewSession.pageAction(false, false, true));
    }

    @Test
    public void firstChallengeShowsVerification() {
        assertEquals(CloudflareWebViewSession.PageAction.SHOW_VERIFICATION,
                CloudflareWebViewSession.pageAction(false, true, true));
    }

    @Test
    public void activeChallengeKeepsVerifyingWithoutAnotherPrompt() {
        assertEquals(CloudflareWebViewSession.PageAction.KEEP_VERIFYING,
                CloudflareWebViewSession.pageAction(true, true, true));
    }

    @Test
    public void completedPageAfterChallengeIsCaptured() {
        assertEquals(CloudflareWebViewSession.PageAction.CAPTURE,
                CloudflareWebViewSession.pageAction(true, false, true));
    }

    @Test
    public void completedVerificationIgnoresChallengeResponseStatus() {
        assertEquals(CloudflareWebViewSession.PageAction.CAPTURE,
                CloudflareWebViewSession.pageAction(true, false, true, 403));
    }

    @Test
    public void normalPageWithCloudflarePrecursorIsNotAChallenge() {
        String html = "<html><head><title>全部漫画-18漫画</title>"
                + "<script src=\"/cdn-cgi/challenge-platform/scripts/precursor/main.js\"></script>"
                + "</head><body><main>全部漫画</main></body></html>";

        assertFalse(CloudflareWebViewSession.isChallenge(
                "https://18mh.org/manga", "全部漫画-18漫画", html, 200, "", false));
    }

    @Test
    public void orchestratedCloudflarePageIsAChallenge() {
        String html = "<script src=\"/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1\"></script>"
                + "<input id=\"cf-chl-widget-test_response\">";

        assertTrue(CloudflareWebViewSession.isChallenge(
                "https://18mh.org/manga", "请稍候…", html, 200, "", false));
    }

    @Test
    public void verifiedBusinessDomIgnoresTheOldChallengeResponse() {
        assertFalse(CloudflareWebViewSession.isChallenge(
                "https://18comic.vip/albums?o=mr&page=1",
                "最新的 Comics - 禁漫天堂",
                "<a href='/album/123'><img src='cover.jpg'></a>",
                403, "challenge", true));
    }

    @Test
    public void firstChallengeResponseStillStartsVerification() {
        assertTrue(CloudflareWebViewSession.isChallenge(
                "https://18comic.vip/albums?o=mr&page=1",
                "Just a moment...", "", 403, "challenge", false));
    }

    @Test
    public void finalPageMustMatchRequestedHostAndPath() {
        assertTrue(CloudflareWebViewSession.isExpectedPage(
                "https://18comic.vip/search/photos?search_query=test&page=2",
                "https://18comic.vip/search/photos?page=2&search_query=test"));
        assertFalse(CloudflareWebViewSession.isExpectedPage(
                "https://18comic.vip/album/1114754", "https://18comic.vip/albums?o=mr"));
        assertFalse(CloudflareWebViewSession.isExpectedPage(
                "https://18comic.vip/album/1114754", "https://example.com/album/1114754"));
    }

    @Test
    public void nonChallengeHttpErrorFailsInsteadOfCapturingErrorHtml() {
        assertEquals(CloudflareWebViewSession.PageAction.FAIL,
                CloudflareWebViewSession.pageAction(false, false, true, 404));
        assertEquals(CloudflareWebViewSession.PageAction.SHOW_VERIFICATION,
                CloudflareWebViewSession.pageAction(false, true, true, 403));
    }

    @Test
    public void successfulBusinessHttpResponseReturnsWithoutBrowser() {
        assertEquals(CloudflareWebViewSession.HttpAction.RETURN_BODY,
                CloudflareWebViewSession.httpAction(
                        200, "", "<a href='/album/123'><img title='漫画'></a>"));
    }

    @Test
    public void cloudflareHttpChallengeFallsBackToBrowser() {
        assertEquals(CloudflareWebViewSession.HttpAction.OPEN_BROWSER,
                CloudflareWebViewSession.httpAction(
                        403, "challenge", "<title>Just a moment...</title>"));
    }

    @Test
    public void ordinaryHttpErrorsNeverOpenVerification() {
        assertEquals(CloudflareWebViewSession.HttpAction.FAIL,
                CloudflareWebViewSession.httpAction(403, "", "Forbidden"));
        assertEquals(CloudflareWebViewSession.HttpAction.FAIL,
                CloudflareWebViewSession.httpAction(500, "", "Server error"));
    }

    @Test
    public void interactiveVerificationWaitsForAutomaticChallengeToFinish() {
        assertEquals(4000L, CloudflareWebViewSession.interactiveDelayMs());
    }

    @Test
    public void protectedRequestTimeoutIsTwoMinutes() {
        assertEquals(120000L, CloudflareWebViewSession.requestTimeoutMs());
    }

    @Test
    public void requestDeadlineIsSharedAcrossTransportPhases() {
        long deadline = CloudflareWebViewSession.requestDeadlineMs(1000L);

        assertEquals(121000L, deadline);
        assertEquals(90000L, CloudflareWebViewSession.remainingRequestMs(deadline, 31000L));
        assertEquals(0L, CloudflareWebViewSession.remainingRequestMs(deadline, 121001L));
    }

    @Test
    public void httpWatchdogUsesTheRemainingRequestBudget() {
        assertEquals(1000L, CloudflareWebViewSession.httpWatchdogDelayMs(121000L, 120000L));
        assertEquals(0L, CloudflareWebViewSession.httpWatchdogDelayMs(121000L, 121001L));
    }

    @Test
    public void automaticVerificationOnlyBecomesInteractiveWhenSessionOptsIn() {
        assertFalse(CloudflareWebViewSession.allowsInteractiveChallenge(false, false));
        assertTrue(CloudflareWebViewSession.allowsInteractiveChallenge(false, true));
        assertTrue(CloudflareWebViewSession.allowsInteractiveChallenge(true, false));
    }

    @Test
    public void manualVerificationOnlyShowsWhileChallengeIsActive() {
        assertTrue(CloudflareWebViewSession.shouldShowInteractive(true, true));
        assertFalse(CloudflareWebViewSession.shouldShowInteractive(true, false));
    }

    @Test
    public void completedTurnstileHandsVisibleVerificationBackToTheApp() {
        assertTrue(CloudflareWebViewSession.shouldHandOffInteractive(
                true, true, "", ""));
        assertFalse(CloudflareWebViewSession.shouldHandOffInteractive(
                false, true, "", ""));
    }

    @Test
    public void newClearanceHandsVisibleVerificationBackToTheApp() {
        assertTrue(CloudflareWebViewSession.shouldHandOffInteractive(
                true, false, "expired", "fresh"));
        assertFalse(CloudflareWebViewSession.shouldHandOffInteractive(
                true, false, "same", "same"));
        assertFalse(CloudflareWebViewSession.shouldHandOffInteractive(
                true, false, "", ""));
    }

    @Test
    public void clearanceCookieIsReadWithoutMatchingOtherCookies() {
        assertEquals("fresh-token", CloudflareWebViewSession.cookieValue(
                "session=one; cf_clearance=fresh-token; other=two", "cf_clearance"));
        assertEquals("", CloudflareWebViewSession.cookieValue(
                "session=one; other=two", "cf_clearance"));
    }
}
