package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class CloudflareWebViewSessionTest {
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
}
