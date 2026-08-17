package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class Mh18WebViewSessionTest {
    @Test
    public void successfulBusinessHttpResponseReturnsWithoutBrowser() {
        assertEquals(Mh18WebViewSession.HttpAction.RETURN_BODY,
                Mh18WebViewSession.httpAction(
                        200, "", "<a href='/manga/demo'><h3 class='cardtitle'>漫画</h3></a>"));
    }

    @Test
    public void verifiedContentRequestsStayInTheBrowserNetworkContext() {
        assertEquals(Mh18WebViewSession.RequestTransport.HTTP,
                Mh18WebViewSession.requestTransport(false));
        assertEquals(Mh18WebViewSession.RequestTransport.BROWSER_CONTEXT,
                Mh18WebViewSession.requestTransport(true));
    }

    @Test
    public void cloudflareHttpChallengeRequiresExplicitVerification() {
        assertEquals(Mh18WebViewSession.HttpAction.VERIFICATION_REQUIRED,
                Mh18WebViewSession.httpAction(
                        403, "challenge", "<title>Just a moment...</title>"));
        assertEquals(Mh18WebViewSession.HttpAction.VERIFICATION_REQUIRED,
                Mh18WebViewSession.httpAction(
                        200, "", "<div class='cf-turnstile-response'>Checking your browser</div>"));
    }

    @Test
    public void interactivePreflightReusesAValidCatalogAndOpensOnlyForChallenge() {
        String catalog = "<a href=\"/manga/demo\"><img src=\"cover.jpg\">"
                + "<h3 class=\"cardtitle\">漫画</h3></a>";

        assertEquals(Mh18WebViewSession.InteractiveAction.COMPLETE,
                Mh18WebViewSession.interactiveAction(200, "", catalog));
        assertEquals(Mh18WebViewSession.InteractiveAction.OPEN_BROWSER,
                Mh18WebViewSession.interactiveAction(
                        403, "challenge", "<title>Just a moment...</title>"));
        assertEquals(Mh18WebViewSession.InteractiveAction.FAIL,
                Mh18WebViewSession.interactiveAction(200, "", "<main>not ready</main>"));
    }

    @Test
    public void ordinaryHttpErrorsRemainFailures() {
        assertEquals(Mh18WebViewSession.HttpAction.FAIL,
                Mh18WebViewSession.httpAction(403, "", "Forbidden"));
        assertEquals(Mh18WebViewSession.HttpAction.FAIL,
                Mh18WebViewSession.httpAction(500, "", "Server error"));
    }

    @Test
    public void verificationRequiresCatalogInBrowserAndCachedProbe() {
        assertTrue(Mh18WebViewSession.verificationComplete(true, true));
        assertFalse(Mh18WebViewSession.verificationComplete(true, false));
        assertFalse(Mh18WebViewSession.verificationComplete(false, true));
        assertFalse(Mh18WebViewSession.verificationComplete(false, false));
    }

    @Test
    public void probeCompletionRequiresTheCapturedNavigationToRemainCurrent() {
        assertTrue(Mh18WebViewSession.probeCanComplete(true, true, false, 3, 3));
        assertFalse(Mh18WebViewSession.probeCanComplete(true, true, false, 3, 4));
        assertFalse(Mh18WebViewSession.probeCanComplete(true, true, true, 3, 3));
        assertFalse(Mh18WebViewSession.probeCanComplete(false, true, false, 3, 3));
    }

    @Test
    public void normalPageWithCloudflarePrecursorIsNotAChallenge() {
        String html = "<html><head><title>全部漫画-18漫画</title>"
                + "<script src=\"/cdn-cgi/challenge-platform/scripts/precursor/main.js\"></script>"
                + "</head><body><main>全部漫画</main></body></html>";

        assertFalse(Mh18WebViewSession.isChallenge(
                "https://18mh.org/manga", "全部漫画-18漫画", html, 200, ""));
    }

    @Test
    public void orchestratedCloudflarePageIsAChallenge() {
        String html = "<script src=\"/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1\"></script>"
                + "<input id=\"cf-chl-widget-test_response\">";

        assertTrue(Mh18WebViewSession.isChallenge(
                "https://18mh.org/manga", "请稍候", html, 200, ""));
    }

    @Test
    public void finalMangaPageMustMatchRequestedSiteAndPath() {
        assertTrue(Mh18WebViewSession.isExpectedPage(
                "https://18mh.org/manga", "https://www.18mh.org/manga/"));
        assertFalse(Mh18WebViewSession.isExpectedPage(
                "https://18mh.org/manga", "https://18mh.org/"));
        assertFalse(Mh18WebViewSession.isExpectedPage(
                "https://18mh.org/manga", "https://example.com/manga"));
    }

    @Test
    public void externalNavigationIsBlockedWithoutRejectingThe18mhSite() {
        assertTrue(Mh18WebViewSession.shouldBlockNavigation(
                "https://18mh.org/manga", "https://ads.example/redirect"));
        assertFalse(Mh18WebViewSession.shouldBlockNavigation(
                "https://18mh.org/manga", "https://www.18mh.org/manga"));
        assertFalse(Mh18WebViewSession.shouldBlockNavigation(
                "https://18mh.org/manga", "https://18mh.org/manga?__cf_chl_rt_tk=token"));
    }

    @Test
    public void pageInspectionWaitsForChallengeAndIncompleteBusinessDom() {
        assertEquals(Mh18WebViewSession.PageAction.WAIT,
                Mh18WebViewSession.pageAction(true, false, false));
        assertEquals(Mh18WebViewSession.PageAction.WAIT,
                Mh18WebViewSession.pageAction(false, true, false));
        assertEquals(Mh18WebViewSession.PageAction.PROBE,
                Mh18WebViewSession.pageAction(false, true, true));
        assertEquals(Mh18WebViewSession.PageAction.PROBE,
                Mh18WebViewSession.pageAction(true, true, true));
        assertEquals(Mh18WebViewSession.PageAction.FAIL,
                Mh18WebViewSession.pageAction(false, false, false));
    }

    @Test
    public void requestTimeoutRemainsTerminalWhileProbeIsRunning() {
        assertTrue(Mh18WebViewSession.shouldStopForTimeout(true, false));
        assertFalse(Mh18WebViewSession.shouldStopForTimeout(false, false));
        assertFalse(Mh18WebViewSession.shouldStopForTimeout(true, true));
    }

    @Test
    public void fixedFingerprintUsesChrome124ForHttpAndWebView() {
        assertTrue(Mh18WebViewSession.fixedUserAgent().contains("Chrome/124.0.0.0"));
    }

    @Test
    public void protectedRequestTimeoutIsTwoMinutes() {
        assertEquals(120000L, Mh18WebViewSession.requestTimeoutMs());
        assertEquals(121000L, Mh18WebViewSession.requestDeadlineMs(1000L));
        assertEquals(90000L, Mh18WebViewSession.remainingRequestMs(121000L, 31000L));
        assertEquals(0L, Mh18WebViewSession.remainingRequestMs(121000L, 121001L));
    }
}
