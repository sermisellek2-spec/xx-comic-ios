package com.xxcomic.source;

import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class JmComicSourceTest {
    @Test
    public void successfulCategoryGroupsAreReused() throws Exception {
        java.util.concurrent.atomic.AtomicInteger requests =
                new java.util.concurrent.atomic.AtomicInteger();
        BrowserSession session = url -> {
            requests.incrementAndGet();
            return row("類別", "/albums?o=mr", "最新A漫");
        };
        JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true), session);

        assertEquals(1, source.filterGroups().size());
        assertEquals(1, source.filterGroups().size());
        assertEquals(1, requests.get());
    }

    @Test
    public void detailAndDirectoryReuseOneAlbumDocument() throws Exception {
        java.util.concurrent.atomic.AtomicInteger requests =
                new java.util.concurrent.atomic.AtomicInteger();
        String html = "<h1 id=\"book-name\">漫画甲</h1>"
                + "<img id=\"album_photo_cover\" src=\"/media/albums/123.jpg\">"
                + "<div class=\"episode\"><a href=\"/photo/456\" data-album=\"456\">"
                + "<h3 class=\"h2_series\">第1话</h3></a></div>";
        JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true), url -> {
            requests.incrementAndGet();
            return html;
        });

        try {
            source.detail("jmcomic:123");
        } catch (RuntimeException androidStub) {
            assertTrue(androidStub.getMessage().contains("not mocked"));
        }
        assertEquals(1, source.chapters("jmcomic:123").size());
        assertEquals(1, requests.get());
    }

    @Test
    public void parsesOnlyRealThemeRowsAndNormalizesLabels() {
        String html = "<div class=\"modal\"><h4>登录</h4><ul><li>广告</li></ul></div>"
                + row("熱門成人主題", "/search/photos?search_query=完結", "完結")
                + "<div class=\"row\"><h4>類別</h4><ul class=\"btn-toolbar btnmg\">"
                + "<li><a href=\"/albums?o=mr\">最新A漫</a></li>"
                + "<li><a href=\"/albums/another/sub/cosplay\">Cosplay</a></li>"
                + "<li><a href=\"/blog_library/\">书库</a></li></ul></div>"
                + row("漫畫排行榜", "/albums?o=mv", "總排行")
                + row("主題A漫", "/search/photos?search_query=純愛", "純愛")
                + row("角色 / 扮演", "/search/photos?search_query=御姐", "御姐")
                + row("特殊PLAY", "/search/photos?search_query=束縛", "束縛")
                + row("其他", "/search/photos?search_query=CG", "CG");

        List<ComicModels.FilterGroup> groups = JmComicSource.parseFilterGroups(
                html, "https://18comic.vip");

        assertEquals(7, groups.size());
        assertEquals("热门", groups.get(0).label);
        assertEquals("类别", groups.get(1).label);
        assertEquals("排行榜", groups.get(2).label);
        assertEquals("主题", groups.get(3).label);
        assertEquals("角色", groups.get(4).label);
        assertEquals("特殊", groups.get(5).label);
        assertEquals("其他", groups.get(6).label);
        assertTrue(groups.get(1).options.stream()
                .anyMatch(option -> option.value.contains("/albums/another/sub/cosplay")));
        assertTrue(groups.stream().flatMap(group -> group.options.stream())
                .noneMatch(option -> option.value.contains("blog_library")));
    }

    @Test
    public void categoryGroupsDoNotDependOnTheOuterRowWrapper() {
        String html = "<section class=\"theme-block\"><header><h4>熱門成人主題</h4></header>"
                + "<div><ul class=\"btnmg compact btn-toolbar\">"
                + "<li><a href=\"/search/photos?search_query=完結\">完結</a></li>"
                + "</ul></div></section>"
                + "<article><h4>類別</h4><div><ul class=\"btn-toolbar x btnmg\">"
                + "<li><a href=\"/albums?o=mr\">最新A漫</a></li>"
                + "</ul></div></article>";

        List<ComicModels.FilterGroup> groups = JmComicSource.parseFilterGroups(
                html, "https://18comic.vip");

        assertEquals(2, groups.size());
        assertEquals("热门", groups.get(0).label);
        assertEquals("类别", groups.get(1).label);
    }

    @Test
    public void currentCatalogCardsParseFromSlugLinksAndSrcCovers() throws Exception {
        String html = "<a href=\"/album/209225\"><img src=\"/paper_box.svg\"></a>"
                + "<a href=\"/album/1462132/current-title\">"
                + "<img src=\"https://cdn-msp3.18comic.vip/media/albums/1462132_3x4.jpg?u=1\" "
                + "title=\"漫画甲\" alt=\"漫画甲\"></a>"
                + "<a href=\"/album/1247117/second-title\">"
                + "<img data-original=\"https://cdn-msp3.18comic.vip/media/albums/1247117_3x4.jpg\" "
                + "alt=\"漫画乙\"></a>"
                + "<a href=\"/advert/1\"><img title=\"广告\"></a>";
        BrowserSession session = url -> html;
        JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true), session);

        List<ComicModels.ComicSummary> result = source.latest(1);

        assertEquals(2, result.size());
        assertEquals("jmcomic:1462132", result.get(0).comicId);
        assertEquals("漫画甲", result.get(0).title);
        assertEquals("https://cdn-msp3.18comic.vip/media/albums/1247117_3x4.jpg",
                result.get(1).coverUrl);
    }

    @Test
    public void verificationProbeChecksBusinessPageWithoutParsingCards() throws Exception {
        java.util.concurrent.atomic.AtomicReference<String> requested =
                new java.util.concurrent.atomic.AtomicReference<>();
        BrowserSession session = url -> {
            requested.set(url);
            return "<html><a href=\"/album/123/title\"><img src=\"cover.jpg\"></a></html>";
        };
        JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true), session);

        source.verifyAccess();

        assertTrue(requested.get().contains("/albums?o=mr"));
        assertTrue(requested.get().contains("page=1"));
    }

    @Test(expected = java.io.IOException.class)
    public void latestRejectsACompletedPageWithoutCatalogCards() throws Exception {
        JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true),
                url -> "<html><title>禁漫天堂</title><body>广告</body></html>");
        source.latest(1);
    }

    @Test(expected = java.io.IOException.class)
    public void defaultCategoryRejectsACompletedPageWithoutCatalogCards() throws Exception {
        JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true),
                url -> "<html><title>禁漫天堂</title><body>广告</body></html>");
        source.category(java.util.Collections.emptyMap(), 1);
    }

    @Test
    public void laterDefaultCategoryPageCanBeEmpty() throws Exception {
        JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true),
                url -> "<html><title>禁漫天堂</title><body>没有更多了</body></html>");

        assertTrue(source.category(java.util.Collections.emptyMap(), 2).isEmpty());
    }

    @Test
    public void coverIgnoresAdvertAndUsesCurrentAlbumCover() {
        String html = "<img itemprop=\"image\" src=\"https://cdn.test/static/resources/ad.gif\">"
                + "<img id=\"album_photo_cover\" data-original=\"https://cdn-msp.18comic.vip/media/albums/1236835.jpg?t=1\">"
                + "<img src=\"https://cdn-msp.18comic.vip/media/photos/1236835/00001.webp\">";

        assertEquals("https://cdn-msp.18comic.vip/media/albums/1236835.jpg?t=1",
                JmComicSource.parseCover(html, "1236835"));
    }

    @Test
    public void chaptersOnlyComeFromEpisodeAndNeverUseRecommendations() {
        String html = "<a href=\"/photo/999\"><h3 class=\"h2_series\">推荐漫画</h3></a>"
                + "<div class=\"episode\"><ul>"
                + "<a href=\"/photo/1114754\" data-album=\"1114754\" data-index=\"0\">"
                + "<li><h3 class=\"h2_series\">第1话 美丽新世界</h3></li></a>"
                + "<a href=\"/photo/390215\" data-album=\"390215\" data-index=\"1\">"
                + "<li><h3 class=\"h2_series\">第2话 3</h3></li></a>"
                + "</ul></div>"
                + "<a href=\"/photo/888\" data-album=\"888\"><h3 class=\"h2_series\">猜你喜欢</h3></a>";

        List<ComicModels.Chapter> chapters = JmComicSource.parseChapters(
                html, "https://18comic.vip");

        assertEquals(2, chapters.size());
        assertEquals("1114754", chapters.get(0).chapterId);
        assertEquals("https://18comic.vip/photo/390215", chapters.get(1).url);
    }

    @Test
    public void missingEpisodeDoesNotFabricateAChapter() {
        assertTrue(JmComicSource.parseChapters(
                "<a href=\"/photo/999\">推荐漫画</a>", "https://18comic.vip").isEmpty());
    }

    @Test
    public void chapterImagesParseWithoutDependingOnTrailingSemicolon() throws Exception {
        String html = "<script>var aid = 1114754; var scramble_id = 220980;"
                + "window.reader={cdnImgHost:'https://cdn-msp2.18comic.vip'};"
                + "var page_arr = [\"00010.webp\",\"00031.webp\"]</script>";

        List<String> images = JmComicSource.parseChapterImages(html);

        assertEquals(2, images.size());
        assertEquals("https://cdn-msp2.18comic.vip/media/photos/1114754/00010.webp?scramble_id=220980",
                images.get(0));
    }

    private static String row(String label, String href, String option) {
        return "<div class=\"row\"><h4>" + label + "</h4>"
                + "<ul class=\"btn-toolbar btnmg\"><li><a href=\"" + href + "\">"
                + option + "</a></li></ul></div>";
    }
}
