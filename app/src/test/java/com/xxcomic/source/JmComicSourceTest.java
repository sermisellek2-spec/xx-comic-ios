package com.xxcomic.source;

import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class JmComicSourceTest {
    @Test
    public void parsesOnlyRealThemeRowsAndNormalizesLabels() {
        String html = "<div class=\"modal\"><h4>登录</h4><ul><li>广告</li></ul></div>"
                + row("熱門成人主題", "/search/photos?search_query=完結", "完結")
                + row("類別", "/albums?o=mr", "最新A漫")
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
