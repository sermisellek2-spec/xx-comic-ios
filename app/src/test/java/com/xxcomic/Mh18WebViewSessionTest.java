package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class Mh18WebViewSessionTest {
    @Test
    public void readyBrowserContextSkipsRepeatedHttpProbe() {
        assertEquals(Mh18WebViewSession.RequestTransport.BROWSER_CONTEXT,
                Mh18WebViewSession.requestTransport(true, true));
    }

    @Test
    public void freshPreferredHttpSessionProbesHttp() {
        assertEquals(Mh18WebViewSession.RequestTransport.HTTP,
                Mh18WebViewSession.requestTransport(true, false));
    }

    @Test
    public void backgroundViewportIsOptInForMh18Only() {
        assertEquals(-1, Mh18WebViewSession.backgroundExtent(true));
        assertEquals(1, Mh18WebViewSession.backgroundExtent(false));
    }

    @Test
    public void browserOnlySourceKeepsNavigation() {
        assertEquals(Mh18WebViewSession.RequestTransport.BROWSER_NAVIGATION,
                Mh18WebViewSession.requestTransport(false, false));
    }

    @Test
    public void completeNormalPageIsCaptured() {
        assertEquals(Mh18WebViewSession.PageAction.CAPTURE,
                Mh18WebViewSession.pageAction(false, false, true));
    }

    @Test
    public void firstChallengeShowsVerification() {
        assertEquals(Mh18WebViewSession.PageAction.SHOW_VERIFICATION,
                Mh18WebViewSession.pageAction(false, true, true));
    }

    @Test
    public void activeChallengeKeepsVerifyingWithoutAnotherPrompt() {
        assertEquals(Mh18WebViewSession.PageAction.KEEP_VERIFYING,
                Mh18WebViewSession.pageAction(true, true, true));
    }

    @Test
    public void completedPageAfterChallengeIsCaptured() {
        assertEquals(Mh18WebViewSession.PageAction.CAPTURE,
                Mh18WebViewSession.pageAction(true, false, true));
    }

    @Test
    public void completedVerificationIgnoresChallengeResponseStatus() {
        assertEquals(Mh18WebViewSession.PageAction.CAPTURE,
                Mh18WebViewSession.pageAction(true, false, true, 403));
    }

    @Test
    public void normalPageWithCloudflarePrecursorIsNotAChallenge() {
        String html = "<html><head><title>全部漫画-18漫画</title>"
                + "<script src=\"/cdn-cgi/challenge-platform/scripts/precursor/main.js\"></script>"
                + "</head><body><main>全部漫画</main></body></html>";

        assertFalse(Mh18WebViewSession.isChallenge(
                "https://18mh.org/manga", "全部漫画-18漫画", html, 200, "", false));
    }

    @Test
    public void orchestratedCloudflarePageIsAChallenge() {
        String html = "<script src=\"/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1\"></script>"
                + "<input id=\"cf-chl-widget-test_response\">";

        assertTrue(Mh18WebViewSession.isChallenge(
                "https://18mh.org/manga", "请稍候…", html, 200, "", false));
    }

    @Test
    public void verifiedBusinessDomIgnoresTheOldChallengeResponse() {
        assertFalse(Mh18WebViewSession.isChallenge(
                "https://18comic.vip/albums?o=mr&page=1",
                "最新的 Comics - 禁漫天堂",
                "<a href='/album/123'><img src='cover.jpg'></a>",
                403, "challenge", true));
    }

    @Test
    public void firstChallengeResponseStillStartsVerification() {
        assertTrue(Mh18WebViewSession.isChallenge(
                "https://18comic.vip/albums?o=mr&page=1",
                "Just a moment...", "", 403, "challenge", false));
    }

    @Test
    public void finalPageMustMatchRequestedHostAndPath() {
        assertTrue(Mh18WebViewSession.isExpectedPage(
                "https://18comic.vip/search/photos?search_query=test&page=2",
                "https://18comic.vip/search/photos?page=2&search_query=test"));
        assertFalse(Mh18WebViewSession.isExpectedPage(
                "https://18comic.vip/album/1114754", "https://18comic.vip/albums?o=mr"));
        assertFalse(Mh18WebViewSession.isExpectedPage(
                "https://18comic.vip/album/1114754", "https://example.com/album/1114754"));
    }

    @Test
    public void nonChallengeHttpErrorFailsInsteadOfCapturingErrorHtml() {
        assertEquals(Mh18WebViewSession.PageAction.FAIL,
                Mh18WebViewSession.pageAction(false, false, true, 404));
        assertEquals(Mh18WebViewSession.PageAction.SHOW_VERIFICATION,
                Mh18WebViewSession.pageAction(false, true, true, 403));
    }

    @Test
    public void successfulBusinessHttpResponseReturnsWithoutBrowser() {
        assertEquals(Mh18WebViewSession.HttpAction.RETURN_BODY,
                Mh18WebViewSession.httpAction(
                        200, "", "<a href='/album/123'><img title='漫画'></a>"));
    }

    @Test
    public void cloudflareHttpChallengeFallsBackToBrowser() {
        assertEquals(Mh18WebViewSession.HttpAction.OPEN_BROWSER,
                Mh18WebViewSession.httpAction(
                        403, "challenge", "<title>Just a moment...</title>"));
    }

    @Test
    public void ordinaryHttpErrorsNeverOpenVerification() {
        assertEquals(Mh18WebViewSession.HttpAction.FAIL,
                Mh18WebViewSession.httpAction(403, "", "Forbidden"));
        assertEquals(Mh18WebViewSession.HttpAction.FAIL,
                Mh18WebViewSession.httpAction(500, "", "Server error"));
    }

    @Test
    public void interactiveVerificationWaitsForAutomaticChallengeToFinish() {
        assertEquals(4000L, Mh18WebViewSession.interactiveDelayMs());
    }

    @Test
    public void protectedRequestTimeoutIsTwoMinutes() {
        assertEquals(120000L, Mh18WebViewSession.requestTimeoutMs());
    }

    @Test
    public void requestDeadlineIsSharedAcrossTransportPhases() {
        long deadline = Mh18WebViewSession.requestDeadlineMs(1000L);

        assertEquals(121000L, deadline);
        assertEquals(90000L, Mh18WebViewSession.remainingRequestMs(deadline, 31000L));
        assertEquals(0L, Mh18WebViewSession.remainingRequestMs(deadline, 121001L));
    }

    @Test
    public void httpWatchdogUsesTheRemainingRequestBudget() {
        assertEquals(1000L, Mh18WebViewSession.httpWatchdogDelayMs(121000L, 120000L));
        assertEquals(0L, Mh18WebViewSession.httpWatchdogDelayMs(121000L, 121001L));
    }

    @Test
    public void automaticVerificationOnlyBecomesInteractiveWhenSessionOptsIn() {
        assertFalse(Mh18WebViewSession.allowsInteractiveChallenge(false, false));
        assertTrue(Mh18WebViewSession.allowsInteractiveChallenge(false, true));
        assertTrue(Mh18WebViewSession.allowsInteractiveChallenge(true, false));
    }

    @Test
    public void manualVerificationOnlyShowsWhileChallengeIsActive() {
        assertTrue(Mh18WebViewSession.shouldShowInteractive(true, true));
        assertFalse(Mh18WebViewSession.shouldShowInteractive(true, false));
    }

    @Test
    public void completedTurnstileHandsVisibleVerificationBackToTheApp() {
        assertTrue(Mh18WebViewSession.shouldHandOffInteractive(
                false, true, true, "", ""));
        assertFalse(Mh18WebViewSession.shouldHandOffInteractive(
                false, false, true, "", ""));
    }

    @Test
    public void newClearanceHandsVisibleVerificationBackToTheApp() {
        assertTrue(Mh18WebViewSession.shouldHandOffInteractive(
                false, true, false, "expired", "fresh"));
        assertFalse(Mh18WebViewSession.shouldHandOffInteractive(
                false, true, false, "same", "same"));
        assertFalse(Mh18WebViewSession.shouldHandOffInteractive(
                false, true, false, "", ""));
    }

    @Test
    public void strictCompletionKeepsVerificationVisibleUntilTheTargetPageIsReady() {
        assertFalse(Mh18WebViewSession.shouldHandOffInteractive(
                true, true, true, "", ""));
        assertFalse(Mh18WebViewSession.shouldHandOffInteractive(
                true, true, false, "expired", "fresh"));
    }

    @Test
    public void nativeFingerprintUsesTheActualWebViewUserAgent() {
        String nativeAgent = "Mozilla/5.0 Chrome/139.0.0.0 Mobile";
        assertEquals(nativeAgent, Mh18WebViewSession.selectedUserAgent(nativeAgent));
        assertFalse(Mh18WebViewSession.selectedUserAgent("").isEmpty());
    }

    @Test
    public void clearanceCookieIsReadWithoutMatchingOtherCookies() {
        assertEquals("fresh-token", Mh18WebViewSession.cookieValue(
                "session=one; cf_clearance=fresh-token; other=two", "cf_clearance"));
        assertEquals("", Mh18WebViewSession.cookieValue(
                "session=one; other=two", "cf_clearance"));
    }
}
