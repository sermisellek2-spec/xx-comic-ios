package com.xxcomic.source;

import org.junit.Test;

import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public class CuimhComicSourceTest {
    @Test
    public void parsesListCards() {
        String html = "<div class=\"cy_list_mh\"><ul>"
                + "<li><a href=\"/yirenzhixia_260264\" class=\"pic\"><img src=\"https://img.test/cover.webp\" alt=\"一人之下漫画\"></a></li>"
                + "<li class=\"title\"><a href=\"/yirenzhixia_260264\">一人之下</a></li>"
                + "<li class=\"zuozhe\">状态：连载中</li>"
                + "<li class=\"biaoqian\">标签：<a href=\"/category/tags/2591\">冒险</a><a href=\"/category/tags/2572\">热血</a></li>"
                + "</ul></div>";

        List<ComicModels.ComicSummary> comics = CuimhComicSource.parseCards(html);

        assertEquals(1, comics.size());
        assertEquals("cuimh:yirenzhixia_260264", comics.get(0).comicId);
        assertEquals("一人之下", comics.get(0).title);
        assertEquals("https://img.test/cover.webp", comics.get(0).coverUrl);
        assertEquals("连载中", comics.get(0).subtitle);
        assertEquals("冒险", comics.get(0).tags.get(0));
        assertEquals("热血", comics.get(0).tags.get(1));
    }

    @Test
    public void parsesSupportedFilterGroupsAndBuildsOrderedPath() {
        String html = filter("分类", "全部", "/category/", "国产漫画", "/category/list/1")
                + filter("标签", "全部", "/category/", "热血", "/category/tags/2572", "热血", "/category/tags/9999")
                + filter("资费", "全部", "/category/", "免费", "/category/pay/1")
                + filter("进度", "全部", "/category/", "连载", "/category/finish/1");

        List<ComicModels.FilterGroup> groups = CuimhComicSource.parseFilterGroups(html);

        assertEquals(3, groups.size());
        assertEquals("分类", groups.get(0).label);
        assertEquals("题材", groups.get(1).label);
        assertEquals(2, groups.get(1).options.size());
        assertEquals("状态", groups.get(2).label);

        Map<String, String> selected = new HashMap<>();
        selected.put("state", "/finish/1");
        selected.put("subject", "/tags/2572");
        selected.put("classification", "/list/1");
        assertEquals("/category/list/1/tags/2572/finish/1/page/2",
                CuimhComicSource.buildCategoryPath(selected, 2));
    }

    @Test
    public void parsesDetailAndChapters() throws IOException {
        String html = "<div class=\"cy_info_cover\"><img src=\"/cover/tree.jpg\"></div>"
                + "<div class=\"cy_title\"><h1>从大树开始的进化</h1></div>"
                + "<span class=\"cy_author\">作者：<a>黑鸟社</a></span>"
                + "<span class=\"cy_type\">类别：<a href=\"/category/tags/2616\">异能</a><a href=\"/category/tags/2625\">格斗</a></span>"
                + "<span class=\"cy_serialize\">状态：<font>连载中</font></span>"
                + "<span class=\"cy_newpic\">最新话：<a>第528话</a></span>"
                + "<p id=\"comic-description\">重生成一株柳树。</p>"
                + "<li class=\"chapter__item\"><a href=\"/419013-227267.html\"><p>第528话</p></a></li>"
                + "<li class=\"chapter__item\"><a href=\"/419013-227234.html\" title=\"第527话\"><p>第527话</p></a></li>";

        ComicModels.ComicDetail detail = CuimhComicSource.parseDetail("congdashukaishidejinhua", html);
        List<ComicModels.Chapter> chapters = CuimhComicSource.parseChapters(html);

        assertEquals("cuimh:congdashukaishidejinhua", detail.summary.comicId);
        assertEquals("从大树开始的进化", detail.summary.title);
        assertEquals("https://www.cuimh.com/cover/tree.jpg", detail.summary.coverUrl);
        assertEquals("黑鸟社", detail.author);
        assertEquals("连载中", detail.status);
        assertEquals("第528话", detail.latestChapter);
        assertEquals(2, detail.summary.tags.size());
        assertEquals(2, chapters.size());
        assertEquals("419013-227267", chapters.get(0).chapterId);
        assertEquals("https://www.cuimh.com/419013-227267.html", chapters.get(0).url);
    }

    @Test
    public void decryptsChapterImagesWithNativeAes() throws IOException {
        String payload = "MDEyMzQ1Njc4OWFiY2RlZutEhySNBDxh7+9pX7lLguDwdPqtjE0tJLVG7+xCkHDt8wNN7cqhoHcwG3tUWN0IQwe7JEqUHI+AXvzwvUk6n4EgljPPb5F5MAJn2Knj9EpWbv2K8oHdIjj7c8x5IkNvnFDCV2qy8rDuJUDhSUFw4lU=";

        List<String> images = CuimhComicSource.decryptPayload(java.util.Base64.getDecoder().decode(payload));

        assertEquals(2, images.size());
        assertEquals("https://img.example/1.webp", images.get(0));
        assertEquals("https://img1.baipiaoguai.org/static/2.webp", images.get(1));
    }

    @Test
    public void reportsSearchAsUnsupported() throws Exception {
        CuimhComicSource source = new CuimhComicSource();

        assertFalse(source.supportsSearch());
        try {
            source.search("一人之下", 1);
            fail("search should fail explicitly");
        } catch (IOException error) {
            assertTrue(error.getMessage().contains("不支持搜索"));
        }
    }

    private static String filter(String name, String... pairs) {
        StringBuilder html = new StringBuilder("<div class=\"cy_tag\"><span>").append(name).append("</span><ul>");
        for (int i = 0; i + 1 < pairs.length; i += 2) {
            html.append("<li><a href=\"").append(pairs[i + 1]).append("\">").append(pairs[i]).append("</a></li>");
        }
        return html.append("</ul></div>").toString();
    }
}
