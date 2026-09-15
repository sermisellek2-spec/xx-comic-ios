package com.xxcomic.source;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import org.junit.Test;
import org.json.JSONObject;

public class BaoziComicSourceTest {
    @Test
    public void persistedTwmangaSourceMigratesRequestOriginAndReferer() throws Exception {
        JSONObject saved = new JSONObject().put("baseUrl", "https://www.twmanga.com")
                .put("domain", "www.twmanga.com").put("referer", "https://www.twmanga.com/")
                .put("routes", new JSONObject().put("categoryApi",
                        "/api/bzmhq/amp_comic_list?__amp_source_origin=https%3A%2F%2Fwww.twmanga.com"));
        SourceConfig restored = SourceConfig.fromJson(saved, SourceConfig.baozi(true));
        assertEquals("https://cn.dzmanga.com", restored.baseUrl);
        assertEquals("cn.dzmanga.com", restored.domain);
        assertEquals("https://cn.dzmanga.com/", restored.referer);
        assertEquals("/api/bzmhq/amp_comic_list?__amp_source_origin=https%3A%2F%2Fcn.dzmanga.com", restored.route("categoryApi"));
    }
    @Test
    public void paginatedCoverUsesTheSitesCurrentImageHost() throws Exception {
        BaoziComicSource source = new BaoziComicSource();
        java.lang.reflect.Method coverUrl = BaoziComicSource.class.getDeclaredMethod("coverUrl", String.class);
        coverUrl.setAccessible(true);
        assertEquals("https://static-tw.baozimh.com/cover/sample.jpg?w=285&h=375&q=100",
                coverUrl.invoke(source, "sample.jpg"));
        assertEquals("https://images.example/sample.jpg", coverUrl.invoke(source, "https://images.example/sample.jpg"));
    }

    @Test
    public void cachedChapterUrlUsesCurrentHostAndKeepsEncodedPath() throws Exception {
        BaoziComicSource source = new BaoziComicSource();
        java.lang.reflect.Method absolute = BaoziComicSource.class.getDeclaredMethod("absolute", String.class);
        absolute.setAccessible(true);
        assertEquals("https://cn.dzmanga.com/comic/chapter/test/0_1.html?q=%E6%AD%A6&x=1",
                absolute.invoke(source, "https://www.baozimh.com/comic/chapter/test/0_1.html?q=%E6%AD%A6&x=1"));
        assertEquals("https://cn.bzmgcn.com.example/comic/test", absolute.invoke(source,
                "https://cn.bzmgcn.com.example/comic/test"));
    }

    @Test
    public void persistedLegacySourceMovesToCurrentHostWithoutLosingSettings() throws Exception {
        JSONObject saved = new JSONObject();
        saved.put("id", "baozimh");
        saved.put("name", "My Baozi");
        saved.put("baseUrl", "https://cn.bzmgcn.com/");
        saved.put("domain", "cn.bzmgcn.com");
        saved.put("referer", "https://cn.bzmgcn.com/");
        saved.put("enabled", false);
        saved.put("routes", new JSONObject()
                .put("search", "https://cn.bzmgcn.com/search?q={keyword}")
                .put("categoryApi", "/api/bzmhq/amp_comic_list?limit=36&__amp_source_origin=https%3A%2F%2Fcn.bzmgcn.com"));
        saved.put("filters", new JSONObject().put("region.cn", "custom"));

        SourceConfig restored = SourceConfig.fromJson(saved, SourceConfig.baozi(true));

        assertEquals("https://cn.dzmanga.com", restored.baseUrl);
        assertEquals("cn.dzmanga.com", restored.domain);
        assertEquals("https://cn.dzmanga.com/", restored.referer);
        assertEquals("https://cn.dzmanga.com/search?q={keyword}", restored.route("search"));
        assertEquals("/api/bzmhq/amp_comic_list?limit=36&__amp_source_origin=https%3A%2F%2Fcn.dzmanga.com", restored.route("categoryApi"));
        assertEquals("My Baozi", restored.name);
        assertEquals("custom", restored.filter("region.cn"));
        assertFalse(restored.enabled);
        assertEquals("https://cn.bzmgcn.com/", saved.getString("baseUrl"));
    }

    @Test
    public void customSourceHostAndRoutesArePreserved() throws Exception {
        JSONObject saved = new JSONObject().put("baseUrl", "https://custom.example")
                .put("domain", "custom.example").put("referer", "https://custom.example/")
                .put("routes", new JSONObject().put("search", "/find?q={keyword}"));
        SourceConfig restored = SourceConfig.fromJson(saved, SourceConfig.baozi(true));
        assertEquals("https://custom.example", restored.baseUrl);
        assertEquals("custom.example", restored.domain);
        assertEquals("/find?q={keyword}", restored.route("search"));
    }

    @Test
    public void categoryFiltersOverrideValuesFromOldPersistedRoute() {
        String oldUrl = "https://cn.bzmgcn.com/classify?type=all&region=all&state=all&filter=all";

        assertEquals(
                "https://cn.bzmgcn.com/classify?type=rexie&region=jp&state=serial&filter=ABCD",
                BaoziComicSource.withCategoryFilters(oldUrl, "rexie", "jp", "serial", "ABCD", 1));
    }

    @Test
    public void categoryFiltersKeepApiOptionsAndSetPage() {
        String oldUrl = "https://cn.bzmgcn.com/api/bzmhq/amp_comic_list?type=all&region=all&state=all&filter=*&page=2&limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.bzmgcn.com";

        assertEquals(
                "https://cn.bzmgcn.com/api/bzmhq/amp_comic_list?limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.bzmgcn.com&type=qihuan&region=kr&state=pub&filter=XYZ&page=3",
                BaoziComicSource.withCategoryFilters(oldUrl, "qihuan", "kr", "pub", "XYZ", 3));
    }
}
