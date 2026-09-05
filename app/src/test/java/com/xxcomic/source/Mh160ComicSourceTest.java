package com.xxcomic.source;

import org.junit.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class Mh160ComicSourceTest {
    @Test
    public void configUsesMh160Routes() {
        SourceConfig config = SourceConfig.mh160(true);
        assertEquals("mh160", config.id);
        assertEquals("漫画160", config.name);
        assertEquals("www.mh160mh.com", config.domain);
        assertEquals("/kanmanhua/{filterPath}{pagePath}", config.route("category"));
        assertEquals("/statics/searchelxt1e1.aspx?key={keyword}{pageQuery}", config.route("search"));
    }

    @Test
    public void parsesSearchCardsAndSkipsNestedRecommendationCards() {
        String html = "<div class=\"mh-search-result\"><ul class=\"mh-search-list clearfix\">"
                + "<li><div class=\"mh-worksbox\"><div class=\"mh-worksbord\">"
                + "<div class=\"mh-nlook-w\"><a href=\"/kanmanhua/4974/\"><img src=\"https://img.test/cover.jpg@!180x240\" alt=\"雏蜂\"></a></div>"
                + "<p class=\"cover-list-updata\"><span>560话</span></p></div></div>"
                + "<div class=\"mh-works-info\"><h4><a title=\"雏蜂\">雏蜂</a></h4>"
                + "<p class=\"mh-works-author\">状态:连载中</p><p class=\"mh-works-tags\"><a>科幻</a><span>作者：出云</span></p>"
                + "<p class=\"mh-works-decs\">简介</p></div></li>"
                + "</ul></div><div class=\"recommend\"><a href=\"/kanmanhua/999/\"><img src=\"recommend.jpg\"></a></div>";

        List<ComicModels.ComicSummary> cards = Mh160ComicSource.parseCards(html);

        assertEquals(1, cards.size());
        assertEquals("mh160:4974", cards.get(0).comicId);
        assertEquals("雏蜂", cards.get(0).title);
        assertEquals("https://img.test/cover.jpg", cards.get(0).coverUrl);
        assertTrue(cards.get(0).tags.contains("科幻"));
    }

    @Test
    public void parsesAllFilterGroupsAndBuildsCategoryPath() {
        String html = "<div class=\"mh-tags\"><h4 class=\"mh-tags-lx\">进度</h4><div class=\"mh-tags-box\">"
                + "<a class=\"on\" href=\"/kanmanhua/all/\">全部</a><a href=\"/kanmanhua/wanjie/\">完结</a></div></div>"
                + "<div class=\"mh-tags\"><h4 class=\"mh-tags-lx\">题材</h4><div class=\"mh-tags-box\">"
                + "<a class=\"on\" href=\"/kanmanhua/all/\">全部</a><a href=\"/kanmanhua/rexue/\">热血</a></div></div>"
                + "<div class=\"mh-tags\"><h4 class=\"mh-tags-lx\">字母</h4><div class=\"mh-tags-box\">"
                + "<a class=\"on\" href=\"/kanmanhua/all/\">全部</a><a href=\"/kanmanhua/lettera/\">A</a></div></div>";

        List<ComicModels.FilterGroup> groups = Mh160ComicSource.parseFilterGroups(html);
        Map<String, String> selected = new LinkedHashMap<>();
        selected.put("state", "/wanjie");

        assertEquals(3, groups.size());
        assertEquals("state", groups.get(0).key);
        assertEquals("状态", groups.get(0).label);
        assertEquals("/wanjie", groups.get(0).options.get(1).value);
        assertEquals("/kanmanhua/wanjie/2.html", Mh160ComicSource.buildCategoryPath(selected, 2));
    }

    @Test
    public void readerRequestUsesCurrentImageCdn() throws Exception {
        String payload = java.util.Base64.getEncoder().encodeToString(
                "/mh160tuku/c/comic/0001.jpg".getBytes(java.nio.charset.StandardCharsets.UTF_8));

        List<String> images = Mh160ComicSource.resolveChapterImages(
                "<script>var qTcms_S_p_id=\"2055611\";var qTcms_S_m_murl_e=\"" + payload + "\";</script>");

        assertEquals("https://xwdf.tgmhfc.uk/mh160tuku/c/comic/0001.jpg", images.get(0));
    }

    @Test
    public void oldReaderRequestUsesLegacyImageCdn() {
        String payload = java.util.Base64.getEncoder().encodeToString(
                "/mh160tuku/c/comic/0001.jpg".getBytes(java.nio.charset.StandardCharsets.UTF_8));

        List<String> images = Mh160ComicSource.resolveChapterImages(
                "<script>var qTcms_S_p_id=\"20380\";var qTcms_S_m_murl_e=\"" + payload + "\";</script>");

        assertEquals("https://mhpic6.tgmhfc.uk/mh160tuku/c/comic/0001.jpg", images.get(0));
    }

    @Test
    public void parsesDetailAndCatalogScopedToComic() throws Exception {
        String html = "<div class=\"mh-date-info fl\"><div class=\"mh-date-info-name\"><h4><a>雏蜂</a></h4></div>"
                + "<p class=\"works-info-tc\"><span>作者：<em>出云</em></span></p><p class=\"works-info-tc\"><span>状态：<em>连载中</em></span></p>"
                + "<div class=\"work-introd\"><div id=\"workint\"><p>简介内容</p></div></div></div>"
                + "<div class=\"mh-cover\"><img src=\"https://img.test/cover.jpg@!180x240@!180x240\"></div>"
                + "<div class=\"cy_plist\"><ul><li><a href=\"/kanmanhua/4974/1799276218.html\"><p>560话</p></a></li></ul></div>"
                + "<div class=\"recommend\"><a href=\"/kanmanhua/999/1.html\"><p>推荐章节</p></a></div>";

        ComicModels.ComicDetail detail = Mh160ComicSource.parseDetail("4974", html);
        List<ComicModels.Chapter> chapters = Mh160ComicSource.parseChapters(html, "4974");

        assertEquals("雏蜂", detail.summary.title);
        assertEquals("https://img.test/cover.jpg", detail.summary.coverUrl);
        assertEquals("出云", detail.author);
        assertEquals("连载中", detail.status);
        assertEquals(1, chapters.size());
        assertEquals("1799276218", chapters.get(0).chapterId);
    }

    @Test
    public void returnsCatalogOldestFirstForReaderNavigation() {
        String html = "<div class=\"cy_plist\"><ul>"
                + "<li><a href=\"/kanmanhua/4974/103.html\"><p>第3话</p></a></li>"
                + "<li><a href=\"/kanmanhua/4974/102.html\"><p>第2话</p></a></li>"
                + "<li><a href=\"/kanmanhua/4974/101.html\"><p>第1话</p></a></li>"
                + "</ul></div>";

        List<ComicModels.Chapter> chapters = Mh160ComicSource.parseChapters(html, "4974");

        assertEquals("第1话", chapters.get(0).title);
        assertEquals("101", chapters.get(0).chapterId);
        assertEquals("第3话", chapters.get(2).title);
        assertEquals("103", chapters.get(2).chapterId);
    }

    @Test
    public void decodesOnlyReaderImagesFromPayload() {
        String payload = java.util.Base64.getEncoder().encodeToString(
                ("/mh160tuku/c/comic/0001.jpg$qingtiandy$/mh160tuku/c/comic/0002.jpg")
                        .getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String html = "<script>var qTcms_S_m_murl_e=\"" + payload + "\";</script>"
                + "<div class=\"recommend\"><img src=\"https://img.test/recommend.jpg\"></div>";

        List<String> images = Mh160ComicSource.parseChapterImages(html);

        assertEquals(2, images.size());
        assertEquals("http://auto.mangafiles.com:88/mh160tuku/c/comic/0001.jpg", images.get(0));
        assertEquals("http://auto.mangafiles.com:88/mh160tuku/c/comic/0002.jpg", images.get(1));
    }
}
