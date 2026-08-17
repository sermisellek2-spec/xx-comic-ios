package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class JmComicWebViewSessionTest {
    @Test
    public void credentialsResetOnlyWhenFingerprintVersionChanges() {
        assertTrue(JmComicWebViewSession.requiresCredentialReset("", "chrome124-v1"));
        assertTrue(JmComicWebViewSession.requiresCredentialReset("native-webview", "chrome124-v1"));
        assertFalse(JmComicWebViewSession.requiresCredentialReset("chrome124-v1", "chrome124-v1"));
    }

    @Test
    public void successfulBusinessHttpResponseReturnsWithoutBrowser() {
        assertEquals(JmComicWebViewSession.HttpAction.RETURN_BODY,
                JmComicWebViewSession.httpAction(
                        200, "", "<a href='/album/123/title'><img title='漫画' src='cover.jpg'></a>"));
    }

    @Test
    public void cloudflareHttpChallengeRequiresExplicitVerification() {
        assertEquals(JmComicWebViewSession.HttpAction.VERIFICATION_REQUIRED,
                JmComicWebViewSession.httpAction(
                        403, "challenge", "<title>Just a moment...</title>"));
        assertEquals(JmComicWebViewSession.HttpAction.VERIFICATION_REQUIRED,
                JmComicWebViewSession.httpAction(
                        200, "", "<div class='cf-turnstile-response'>Checking your browser</div>"));
    }

    @Test
    public void ordinaryHttpErrorsRemainFailures() {
        assertEquals(JmComicWebViewSession.HttpAction.FAIL,
                JmComicWebViewSession.httpAction(403, "", "Forbidden"));
        assertEquals(JmComicWebViewSession.HttpAction.FAIL,
                JmComicWebViewSession.httpAction(500, "", "Server error"));
    }

    @Test
    public void verificationRequiresCatalogInBrowserAndCachedProbe() {
        assertTrue(JmComicWebViewSession.verificationComplete(true, true));
        assertFalse(JmComicWebViewSession.verificationComplete(true, false));
        assertFalse(JmComicWebViewSession.verificationComplete(false, true));
        assertFalse(JmComicWebViewSession.verificationComplete(false, false));
    }

    @Test
    public void probeCompletionRequiresTheCapturedNavigationToRemainCurrent() {
        assertTrue(JmComicWebViewSession.probeCanComplete(true, true, false, 3, 3));
        assertFalse(JmComicWebViewSession.probeCanComplete(true, true, false, 3, 4));
        assertFalse(JmComicWebViewSession.probeCanComplete(true, true, true, 3, 3));
        assertFalse(JmComicWebViewSession.probeCanComplete(false, true, false, 3, 3));
    }

    @Test
    public void normalPageWithCloudflarePrecursorIsNotAChallenge() {
        String html = "<html><head><title>最新的 Comics - 禁漫天堂</title>"
                + "<script src=\"/cdn-cgi/challenge-platform/scripts/precursor/main.js\"></script>"
                + "</head><body><a href='/album/123/title'><img title='漫画'></a></body></html>";

        assertFalse(JmComicWebViewSession.isChallenge(
                "https://18comic.vip/albums?o=mr&page=1",
                "最新的 Comics - 禁漫天堂", html, 200, ""));
    }

    @Test
    public void orchestratedCloudflarePageIsAChallenge() {
        String html = "<script src=\"/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1\"></script>"
                + "<input id=\"cf-chl-widget-test_response\">";

        assertTrue(JmComicWebViewSession.isChallenge(
                "https://18comic.vip/albums?o=mr&page=1", "请稍候", html, 200, ""));
    }

    @Test
    public void finalAlbumsPageMustMatchRequestedSiteAndPath() {
        assertTrue(JmComicWebViewSession.isExpectedPage(
                "https://18comic.vip/albums?o=mr&page=1",
                "https://18comic.vip/albums?page=1&o=mr"));
        assertFalse(JmComicWebViewSession.isExpectedPage(
                "https://18comic.vip/albums?o=mr&page=1",
                "https://18comic.vip/album/123/title"));
        assertFalse(JmComicWebViewSession.isExpectedPage(
                "https://18comic.vip/albums?o=mr&page=1",
                "https://example.com/albums?o=mr&page=1"));
    }

    @Test
    public void fixedFingerprintUsesChrome124ForHttpAndWebView() {
        assertTrue(JmComicWebViewSession.fixedUserAgent().contains("Chrome/124.0.0.0"));
    }

    @Test
    public void protectedRequestTimeoutIsTwoMinutes() {
        assertEquals(120000L, JmComicWebViewSession.requestTimeoutMs());
        assertEquals(121000L, JmComicWebViewSession.requestDeadlineMs(1000L));
        assertEquals(90000L, JmComicWebViewSession.remainingRequestMs(121000L, 31000L));
        assertEquals(0L, JmComicWebViewSession.remainingRequestMs(121000L, 121001L));
    }
}
