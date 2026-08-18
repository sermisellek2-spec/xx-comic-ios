package com.xxcomic.source;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.util.List;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

public class LiumanhuaComicSourceTest {
    private static final String KEY = "9S8$vJnU2ANeSRoF";

    @Test
    public void parsesOnlyScopedComicCards() {
        String html = "<div class=\"cy_list_mh\"><ul>"
                + "<li><a href=\"/302262\" class=\"pic\"><img src=\"https://img.test/cover.jpg\" alt=\"可爱过敏原漫画\"></a></li>"
                + "<li class=\"title\"><a href=\"/302262\">可爱过敏原</a></li>"
                + "<li class=\"zuozhe\">状态：连载中</li>"
                + "<li class=\"biaoqian\"><a href=\"/category/tags/1\">恋爱</a></li>"
                + "</ul></div><div class=\"rd-guess__comic\"><a href=\"/999\">推荐漫画</a></div>";

        List<ComicModels.ComicSummary> comics = LiumanhuaComicSource.parseCards(html);

        assertEquals(1, comics.size());
        assertEquals("liumanhua:302262", comics.get(0).comicId);
        assertEquals("可爱过敏原", comics.get(0).title);
        assertEquals("连载中", comics.get(0).subtitle);
    }

    @Test
    public void parsesFiltersAndSkipsPaidGroup() {
        String html = filter("分类", "国产漫画", "/category/list/1")
                + filter("标签", "热血", "/category/tags/2572")
                + filter("资费", "免费", "/category/pay/1")
                + filter("进度", "完结", "/category/finish/2");

        List<ComicModels.FilterGroup> groups = LiumanhuaComicSource.parseFilterGroups(html);

        assertEquals(3, groups.size());
        assertEquals("classification", groups.get(0).key);
        assertEquals("题材", groups.get(1).label);
        assertEquals("/tags/2572", groups.get(1).options.get(1).value);
        assertEquals("状态", groups.get(2).label);
    }

    @Test
    public void parsesCatalogWithoutRecommendations() {
        String html = "<div class=\"cy_plist\"><ul>"
                + "<li class=\"chapter__item\"><a href=\"/302262/217344.html\"><p>第119话</p></a></li>"
                + "</ul></div><div class=\"rd-guess__comic\">"
                + "<li class=\"chapter__item\"><a href=\"/999/1.html\">推荐章节</a></li></div>";

        List<ComicModels.Chapter> chapters = LiumanhuaComicSource.parseChapters(html, "302262");

        assertEquals(1, chapters.size());
        assertEquals("217344", chapters.get(0).chapterId);
        assertEquals("https://www.liumanhua.com/302262/217344.html", chapters.get(0).url);
    }

    @Test
    public void usesOnlineReadingAsSingleChapterFallback() {
        String html = "<div class=\"cy_kan\"><a href=\"/302262/217344.html\">在线阅读</a></div>"
                + "<div class=\"rd-guess__comic\"><a href=\"/999/1.html\">推荐漫画</a></div>";

        List<ComicModels.Chapter> chapters = LiumanhuaComicSource.parseChapters(html, "302262");

        assertEquals(1, chapters.size());
        assertEquals("在线阅读", chapters.get(0).title);
        assertEquals("217344", chapters.get(0).chapterId);
    }

    @Test
    public void decryptsAndValidatesChapterPayload() throws Exception {
        String json = "{\"host\":\"www.liumanhua.com\",\"source_id\":\"6\",\"comic_id\":\"302262\","
                + "\"comic_down\":0,\"chapter_id\":\"217344\",\"images\":["
                + "\"https:\\/\\/s2.bzcdn.net\\/comic\\/1.jpg\",\"https:\\/\\/s2.bzcdn.net\\/comic\\/2.jpg\"]}";

        List<String> images = LiumanhuaComicSource.decryptPayload(encrypt(json), "302262", "217344");

        assertEquals(2, images.size());
        assertEquals("https://s2.bzcdn.net/comic/1.jpg", images.get(0));
    }

    @Test
    public void reportsKeywordSearchAsUnsupported() {
        assertFalse(new LiumanhuaComicSource().supportsSearch());
    }

    private static byte[] encrypt(String json) throws Exception {
        byte[] iv = "0123456789abcdef".getBytes(StandardCharsets.UTF_8);
        Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(KEY.getBytes(StandardCharsets.UTF_8), "AES"), new IvParameterSpec(iv));
        byte[] encrypted = cipher.doFinal(json.getBytes(StandardCharsets.UTF_8));
        byte[] payload = new byte[iv.length + encrypted.length];
        System.arraycopy(iv, 0, payload, 0, iv.length);
        System.arraycopy(encrypted, 0, payload, iv.length, encrypted.length);
        return payload;
    }

    private static String filter(String name, String option, String path) {
        return "<div class=\"cy_tag\"><span>" + name + "</span><ul>"
                + "<li><a href=\"/category/\">全部</a></li>"
                + "<li><a href=\"" + path + "\">" + option + "</a></li>"
                + "</ul></div>";
    }
}
