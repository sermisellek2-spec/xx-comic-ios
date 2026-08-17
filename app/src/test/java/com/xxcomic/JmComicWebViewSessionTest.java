package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class JmComicWebViewSessionTest {
    @Test
    public void readyBrowserContextSkipsRepeatedHttpProbe() {
        assertEquals(JmComicWebViewSession.RequestTransport.BROWSER_CONTEXT,
                JmComicWebViewSession.requestTransport(true, true));
    }

    @Test
    public void freshPreferredHttpSessionProbesHttp() {
        assertEquals(JmComicWebViewSession.RequestTransport.HTTP,
                JmComicWebViewSession.requestTransport(true, false));
    }

    @Test
    public void backgroundViewportIsOptInForMh18Only() {
        assertEquals(-1, JmComicWebViewSession.backgroundExtent(true));
        assertEquals(1, JmComicWebViewSession.backgroundExtent(false));
    }

    @Test
    public void browserOnlySourceKeepsNavigation() {
        assertEquals(JmComicWebViewSession.RequestTransport.BROWSER_NAVIGATION,
                JmComicWebViewSession.requestTransport(false, false));
    }

    @Test
    public void completeNormalPageIsCaptured() {
        assertEquals(JmComicWebViewSession.PageAction.CAPTURE,
                JmComicWebViewSession.pageAction(false, false, true));
    }

    @Test
    public void firstChallengeShowsVerification() {
        assertEquals(JmComicWebViewSession.PageAction.SHOW_VERIFICATION,
                JmComicWebViewSession.pageAction(false, true, true));
    }

    @Test
    public void activeChallengeKeepsVerifyingWithoutAnotherPrompt() {
        assertEquals(JmComicWebViewSession.PageAction.KEEP_VERIFYING,
                JmComicWebViewSession.pageAction(true, true, true));
    }

    @Test
    public void completedPageAfterChallengeIsCaptured() {
        assertEquals(JmComicWebViewSession.PageAction.CAPTURE,
                JmComicWebViewSession.pageAction(true, false, true));
    }

    @Test
    public void completedVerificationIgnoresChallengeResponseStatus() {
        assertEquals(JmComicWebViewSession.PageAction.CAPTURE,
                JmComicWebViewSession.pageAction(true, false, true, 403));
    }

    @Test
    public void normalPageWithCloudflarePrecursorIsNotAChallenge() {
        String html = "<html><head><title>全部漫画-18漫画</title>"
                + "<script src=\"/cdn-cgi/challenge-platform/scripts/precursor/main.js\"></script>"
                + "</head><body><main>全部漫画</main></body></html>";

        assertFalse(JmComicWebViewSession.isChallenge(
                "https://18mh.org/manga", "全部漫画-18漫画", html, 200, "", false));
    }

    @Test
    public void orchestratedCloudflarePageIsAChallenge() {
        String html = "<script src=\"/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1\"></script>"
                + "<input id=\"cf-chl-widget-test_response\">";

        assertTrue(JmComicWebViewSession.isChallenge(
                "https://18mh.org/manga", "请稍候…", html, 200, "", false));
    }

    @Test
    public void verifiedBusinessDomIgnoresTheOldChallengeResponse() {
        assertFalse(JmComicWebViewSession.isChallenge(
                "https://18comic.vip/albums?o=mr&page=1",
                "最新的 Comics - 禁漫天堂",
                "<a href='/album/123'><img src='cover.jpg'></a>",
                403, "challenge", true));
    }

    @Test
    public void firstChallengeResponseStillStartsVerification() {
        assertTrue(JmComicWebViewSession.isChallenge(
                "https://18comic.vip/albums?o=mr&page=1",
                "Just a moment...", "", 403, "challenge", false));
    }

    @Test
    public void finalPageMustMatchRequestedHostAndPath() {
        assertTrue(JmComicWebViewSession.isExpectedPage(
                "https://18comic.vip/search/photos?search_query=test&page=2",
                "https://18comic.vip/search/photos?page=2&search_query=test"));
        assertFalse(JmComicWebViewSession.isExpectedPage(
                "https://18comic.vip/album/1114754", "https://18comic.vip/albums?o=mr"));
        assertFalse(JmComicWebViewSession.isExpectedPage(
                "https://18comic.vip/album/1114754", "https://example.com/album/1114754"));
    }

    @Test
    public void nonChallengeHttpErrorFailsInsteadOfCapturingErrorHtml() {
        assertEquals(JmComicWebViewSession.PageAction.FAIL,
                JmComicWebViewSession.pageAction(false, false, true, 404));
        assertEquals(JmComicWebViewSession.PageAction.SHOW_VERIFICATION,
                JmComicWebViewSession.pageAction(false, true, true, 403));
    }

    @Test
    public void successfulBusinessHttpResponseReturnsWithoutBrowser() {
        assertEquals(JmComicWebViewSession.HttpAction.RETURN_BODY,
                JmComicWebViewSession.httpAction(
                        200, "", "<a href='/album/123'><img title='漫画'></a>"));
    }

    @Test
    public void cloudflareHttpChallengeFallsBackToBrowser() {
        assertEquals(JmComicWebViewSession.HttpAction.OPEN_BROWSER,
                JmComicWebViewSession.httpAction(
                        403, "challenge", "<title>Just a moment...</title>"));
    }

    @Test
    public void ordinaryHttpErrorsNeverOpenVerification() {
        assertEquals(JmComicWebViewSession.HttpAction.FAIL,
                JmComicWebViewSession.httpAction(403, "", "Forbidden"));
        assertEquals(JmComicWebViewSession.HttpAction.FAIL,
                JmComicWebViewSession.httpAction(500, "", "Server error"));
    }

    @Test
    public void interactiveVerificationWaitsForAutomaticChallengeToFinish() {
        assertEquals(4000L, JmComicWebViewSession.interactiveDelayMs());
    }

    @Test
    public void protectedRequestTimeoutIsTwoMinutes() {
        assertEquals(120000L, JmComicWebViewSession.requestTimeoutMs());
    }

    @Test
    public void requestDeadlineIsSharedAcrossTransportPhases() {
        long deadline = JmComicWebViewSession.requestDeadlineMs(1000L);

        assertEquals(121000L, deadline);
        assertEquals(90000L, JmComicWebViewSession.remainingRequestMs(deadline, 31000L));
        assertEquals(0L, JmComicWebViewSession.remainingRequestMs(deadline, 121001L));
    }

    @Test
    public void httpWatchdogUsesTheRemainingRequestBudget() {
        assertEquals(1000L, JmComicWebViewSession.httpWatchdogDelayMs(121000L, 120000L));
        assertEquals(0L, JmComicWebViewSession.httpWatchdogDelayMs(121000L, 121001L));
    }

    @Test
    public void automaticVerificationOnlyBecomesInteractiveWhenSessionOptsIn() {
        assertFalse(JmComicWebViewSession.allowsInteractiveChallenge(false, false));
        assertTrue(JmComicWebViewSession.allowsInteractiveChallenge(false, true));
        assertTrue(JmComicWebViewSession.allowsInteractiveChallenge(true, false));
    }

    @Test
    public void manualVerificationOnlyShowsWhileChallengeIsActive() {
        assertTrue(JmComicWebViewSession.shouldShowInteractive(true, true));
        assertFalse(JmComicWebViewSession.shouldShowInteractive(true, false));
    }

    @Test
    public void completedTurnstileHandsVisibleVerificationBackToTheApp() {
        assertTrue(JmComicWebViewSession.shouldHandOffInteractive(
                false, true, true, "", ""));
        assertFalse(JmComicWebViewSession.shouldHandOffInteractive(
                false, false, true, "", ""));
    }

    @Test
    public void newClearanceHandsVisibleVerificationBackToTheApp() {
        assertTrue(JmComicWebViewSession.shouldHandOffInteractive(
                false, true, false, "expired", "fresh"));
        assertFalse(JmComicWebViewSession.shouldHandOffInteractive(
                false, true, false, "same", "same"));
        assertFalse(JmComicWebViewSession.shouldHandOffInteractive(
                false, true, false, "", ""));
    }

    @Test
    public void strictCompletionKeepsVerificationVisibleUntilTheTargetPageIsReady() {
        assertFalse(JmComicWebViewSession.shouldHandOffInteractive(
                true, true, true, "", ""));
        assertFalse(JmComicWebViewSession.shouldHandOffInteractive(
                true, true, false, "expired", "fresh"));
    }

    @Test
    public void fixedFingerprintUsesChrome124ForHttpAndWebView() {
        String selected = JmComicWebViewSession.fixedUserAgent();

        assertTrue(selected.contains("Chrome/124.0.0.0"));
        assertEquals(selected, JmComicWebViewSession.fixedUserAgent());
    }

    @Test
    public void clearanceCookieIsReadWithoutMatchingOtherCookies() {
        assertEquals("fresh-token", JmComicWebViewSession.cookieValue(
                "session=one; cf_clearance=fresh-token; other=two", "cf_clearance"));
        assertEquals("", JmComicWebViewSession.cookieValue(
                "session=one; other=two", "cf_clearance"));
    }
}
