package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class CloudflareWebViewSessionTest {
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
                "https://18mh.org/manga", "全部漫画-18漫画", html, 200, ""));
    }

    @Test
    public void orchestratedCloudflarePageIsAChallenge() {
        String html = "<script src=\"/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1\"></script>"
                + "<input id=\"cf-chl-widget-test_response\">";

        assertTrue(CloudflareWebViewSession.isChallenge(
                "https://18mh.org/manga", "请稍候…", html, 200, ""));
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
}
