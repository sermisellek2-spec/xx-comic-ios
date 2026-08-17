package com.xxcomic.source;

import org.junit.Test;
import org.json.JSONObject;

import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class Mh18ComicSourceTest {
    @Test
    public void searchUsesRequestedPage() throws Exception {
        assertEquals("/s/%E6%B5%8B%E8%AF%95/page/2",
                Mh18ComicSource.searchPath("测试", 2));
    }

    @Test
    public void metaParsingDoesNotDependOnAttributeOrder() {
        String html = "<meta content=\"目标漫画\" property=\"og:title\">";

        assertEquals("目标漫画", Mh18ComicSource.metaValue(html, "og:title"));
    }

    @Test
    public void structuredDataFindsComicInsideGraph() throws Exception {
        String html = "<script type=\"application/ld+json\">{\"@context\":\"https://schema.org\","
                + "\"@graph\":[{\"@type\":\"BreadcrumbList\"},{\"@type\":\"ComicSeries\","
                + "\"name\":\"目标漫画\"}]}</script>";

        JSONObject comic = Mh18ComicSource.structuredData(html, "ComicSeries");

        assertEquals("目标漫画", comic.getString("name"));
    }

    @Test
    public void chapterImagesAcceptLazyImagesWithoutFragileAltText() {
        String html = "<img data-src=\"https://img.18mh.org/upload/1.webp\" alt=\"第1页\">"
                + "<img src=\"https://img.18mh.org/upload/2.webp\">"
                + "<img src=\"/static/logo.png\">";

        List<String> images = Mh18ComicSource.parseChapterImages(html);

        assertEquals(2, images.size());
        assertEquals("https://img.18mh.org/upload/2.webp", images.get(1));
    }

    @Test
    public void verificationProbeUsesInteractiveBrowserFetch() throws Exception {
        java.util.concurrent.atomic.AtomicBoolean interactive =
                new java.util.concurrent.atomic.AtomicBoolean();
        BrowserSession session = new BrowserSession() {
            @Override public String fetch(String url) throws java.io.IOException {
                throw new java.io.IOException("silent fetch should not run");
            }

            @Override public String fetchInteractive(String url) {
                interactive.set(true);
                return "<a href=\"/manga/demo\"><img src=\"cover.jpg\">"
                        + "<h3 class=\"cardtitle\">测试漫画</h3></a>";
            }
        };

        new Mh18ComicSource(SourceConfig.mh18(true), session).verifyAccess();

        assertTrue(interactive.get());
    }
}
