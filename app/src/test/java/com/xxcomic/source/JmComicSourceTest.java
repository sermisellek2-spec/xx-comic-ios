package com.xxcomic.source;

import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertEquals;

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

    private static String row(String label, String href, String option) {
        return "<div class=\"row\"><h4>" + label + "</h4>"
                + "<ul class=\"btn-toolbar btnmg\"><li><a href=\"" + href + "\">"
                + option + "</a></li></ul></div>";
    }
}
