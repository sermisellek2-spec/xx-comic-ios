package com.xxcomic.source;

import org.junit.Test;
import org.json.JSONObject;

import java.util.List;

import static org.junit.Assert.assertEquals;

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
}
