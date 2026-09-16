package com.xxcomic.source;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import static org.junit.Assert.*;

public class ManwaComicSourceTest {
    private static final String CHAPTER = "https://manwace.cc/comic/163037/2161449";

    @Test public void categoryUsesTagPathAndResetRemovesItWithoutLosingPagination() throws Exception {
        Fake source = new Fake();
        Map<String, String> filters = new LinkedHashMap<>();
        filters.put("tag", "冒险"); filters.put("region", "3"); filters.put("state", "1");
        source.category(filters, 2);
        assertEquals("https://manwace.cc/api/cate/adventure", source.urls.get(0));
        assertEquals(2, source.body.getJSONObject("page").getInt("page"));
        assertEquals(3, source.body.getJSONObject("comic").getInt("areaId"));
        assertEquals(1, source.body.getJSONObject("comic").getInt("status"));
        filters.put("tag", "all");
        source.category(filters, 1);
        assertEquals("https://manwace.cc/api/cate", source.urls.get(1));
    }

    @Test public void everyDisplayedTagUsesItsWebsiteSlug() throws Exception {
        String[] slugs = {"hotblooded", "xuanhuan", "romance", "adventure", "historical", "urban", "transmigration",
                "fantasy", "comedy", "shounen", "action", "rebirth", "counterattack", "hilarious", "youth",
                "harem", "system", "bl", "manhwa", "fullversion", "19plus", "taiwanver"};
        Fake source = new Fake();
        List<ComicModels.FilterOption> options = source.filterGroups().get(2).options;
        assertEquals(slugs.length + 1, options.size());
        for (int i = 0; i < slugs.length; i++) {
            source.category(Collections.singletonMap("tag", options.get(i + 1).value), 1);
            assertEquals("https://manwace.cc/api/cate/" + slugs[i], source.urls.get(i));
        }
    }

    @Test public void realTransportSendsTypeCookiePerRequestAndDoesNotLeakToSearch() throws Exception {
        java.net.ServerSocket server = new java.net.ServerSocket(0, 3, java.net.InetAddress.getByName("127.0.0.1"));
        server.setSoTimeout(5000);
        List<String> cookies = new java.util.concurrent.CopyOnWriteArrayList<>();
        java.util.concurrent.FutureTask<Void> serve = new java.util.concurrent.FutureTask<>(() -> {
            for (int i = 0; i < 3; i++) {
                try (java.net.Socket socket = server.accept()) {
                    socket.setSoTimeout(5000);
                    java.io.BufferedReader input = new java.io.BufferedReader(new java.io.InputStreamReader(
                            socket.getInputStream(), java.nio.charset.StandardCharsets.UTF_8));
                    String line, cookie = "null";
                    int length = 0;
                    while ((line = input.readLine()) != null && !line.isEmpty()) {
                        if (line.toLowerCase(java.util.Locale.ROOT).startsWith("cookie:")) cookie = line.substring(7).trim();
                        if (line.toLowerCase(java.util.Locale.ROOT).startsWith("content-length:")) length = Integer.parseInt(line.substring(15).trim());
                    }
                    for (int j = 0; j < length; j++) if (input.read() == -1) throw new IOException("Truncated request");
                    cookies.add(cookie);
                    byte[] body = "{\"code\":200,\"data\":{\"list\":[]}}".getBytes(java.nio.charset.StandardCharsets.UTF_8);
                    java.io.OutputStream output = socket.getOutputStream();
                    output.write(("HTTP/1.1 200 OK\r\nContent-Length: " + body.length + "\r\nConnection: close\r\n\r\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
                    output.write(body);
                    output.flush();
                }
            }
            return null;
        });
        Thread worker = new Thread(serve, "manwa-test-http");
        worker.setDaemon(true);
        worker.start();
        try {
            SourceConfig original = SourceConfig.manwa(true);
            String base = "http://127.0.0.1:" + server.getLocalPort();
            ManwaComicSource source = new ManwaComicSource(new SourceConfig("manwa", "漫蛙", "127.0.0.1",
                    base, base + "/", "", "", "", "", true, original.routes, original.filters));
            source.category(Collections.singletonMap("type", "2"), 1);
            source.category(Collections.singletonMap("type", "all"), 1);
            source.search("漫画", 1);
            serve.get(5, java.util.concurrent.TimeUnit.SECONDS);
            assertEquals("typeId=2", cookies.get(0));
            assertEquals("typeId=0", cookies.get(1));
            assertEquals("null", cookies.get(2));
        } finally { server.close(); worker.join(5000); }
    }

    @Test public void searchEncodesKeywordAndUsesRealMangaTypeAndPage() throws Exception {
        Fake source = new Fake();
        List<ComicModels.ComicSummary> result = source.search("  史莱姆 & A  ", 2);
        assertTrue(source.urls.get(0).contains("type=mh&page=2&pageSize=20&keyword=%E5%8F%B2%E8%8E%B1%E5%A7%86+%26+A"));
        assertEquals(2, result.size());
        assertEquals("manwa:10395", result.get(0).comicId);
        assertEquals("史莱姆圣女", result.get(0).title);
        assertTrue(result.get(0).coverUrl.startsWith("https://mwtuwu.cc/"));
        assertEquals("魔幻", result.get(0).tags.get(0));
        assertTrue(source.search(" ", 1).isEmpty());
        assertEquals(1, source.urls.size());
    }

    @Test public void categoryDefaultsToOrdinaryAndPostsPageTwo() throws Exception {
        Fake source = new Fake();
        assertFalse(source.latest(2).isEmpty());
        assertEquals("https://manwace.cc/api/cate", source.urls.get(0));
        assertEquals(2, source.body.getJSONObject("page").getInt("page"));
        assertEquals(36, source.body.getJSONObject("page").getInt("pageSize"));
        assertEquals(1, source.body.getJSONObject("comic").getInt("level"));
        assertEquals(-1, source.body.getJSONObject("comic").getInt("status"));
    }

    @Test public void allFilterAxesAreCombinedAndExplicitAllLevelIsZero() throws Exception {
        Map<String, String> filters = new LinkedHashMap<>();
        filters.put("level", "0"); filters.put("type", "1"); filters.put("region", "3");
        filters.put("state", "0"); filters.put("day", "2"); filters.put("tag", "冒险"); filters.put("sort", "3");
        JSONObject body = ManwaComicSource.categoryBody(filters, 3);
        JSONObject comic = body.getJSONObject("comic");
        assertEquals(0, comic.getInt("level")); assertEquals(1, comic.getInt("typeId"));
        assertEquals(3, comic.getInt("areaId")); assertEquals(0, comic.getInt("status"));
        assertEquals(2, comic.getInt("day")); assertEquals("冒险", comic.getString("tag"));
        assertEquals(3, body.getInt("sort")); assertEquals(3, body.getJSONObject("page").getInt("page"));
        for (String key : filters.keySet()) filters.put(key, "all");
        comic = ManwaComicSource.categoryBody(filters, -1).getJSONObject("comic");
        assertEquals(1, comic.getInt("level")); assertEquals("", comic.getString("tag"));
        assertEquals(-1, comic.getInt("status"));
        List<ComicModels.FilterGroup> groups = new ManwaComicSource().filterGroups();
        assertEquals(7, groups.size());
        assertEquals("普通", groups.get(0).options.get(0).label);
    }

    @Test public void detailDecodesEntitiesAndUsesActualCoverNotPlaceholder() throws Exception {
        ComicModels.ComicDetail detail = new Fake().detail("manwa:163037");
        assertEquals("最速进化的史莱姆无双", detail.summary.title);
        assertEquals("艇駆いいじ，野口祥汰", detail.author);
        assertEquals("连载中", detail.status);
        assertEquals("第01话", detail.latestChapter);
        assertTrue(detail.summary.coverUrl.contains("/en_images/202609/cover/"));
        assertFalse(detail.description.isEmpty()); assertFalse(detail.summary.tags.isEmpty());
        assertTrue(detail.chapters.isEmpty());
    }

    @Test public void malformedDetailAndErrorJsonNeverBecomeEmptySuccess() throws Exception {
        ManwaComicSource source = new ManwaComicSource();
        assertThrows(IOException.class, () -> source.parseDetail("1", "<title>Access denied</title>"));
        assertThrows(IOException.class, () -> source.parseCards("{\"code\":403,\"msg\":\"VIP\"}"));
        assertThrows(IOException.class, () -> source.parseCards("{\"code\":200,\"data\":{}}"));
        assertTrue(source.parseCards("{\"code\":200,\"data\":{\"list\":[]}}").isEmpty());
    }

    @Test public void chaptersPreserveFractionalBonusOrderAndDeduplicate() throws Exception {
        Fake source = new Fake();
        source.directory = "{\"code\":200,\"data\":{\"list\":["
                + "{\"id\":90,\"title\":\"第2话\",\"sortId\":2},"
                + "{\"id\":500,\"title\":\"第1话\",\"sortId\":1},"
                + "{\"id\":3,\"title\":\"番外\",\"sortId\":1.5},"
                + "{\"id\":90,\"title\":\"第2话\",\"sortId\":2}]}}";
        List<ComicModels.Chapter> chapters = source.chapters("manwa:163037");
        assertEquals(3, chapters.size());
        assertEquals("500", chapters.get(0).chapterId); assertEquals("3", chapters.get(1).chapterId);
        assertEquals("90", chapters.get(2).chapterId); assertEquals(2, chapters.get(2).chapterSlot);
        assertEquals("https://manwace.cc/comic/163037/500", chapters.get(0).url);
    }

    @Test public void fullDirectoryIsNotLimitedToTwentyVisibleHtmlChapters() throws Exception {
        Fake source = new Fake();
        JSONArray rows = new JSONArray();
        for (int i = 1; i <= 878; i++) rows.put(new JSONObject().put("id", i).put("title", "第" + i + "话").put("sortId", i));
        source.directory = new JSONObject().put("code", 200).put("data", new JSONObject().put("list", rows)).toString();
        assertEquals(878, source.chapters("manwa:7751").size());
        assertEquals(1, source.urls.size());
    }

    @Test public void realChapterReturnsAllThirtyEightImagesAndNoNextPage() throws Exception {
        ComicModels.ChapterPage page = new Fake().chapter(CHAPTER);
        assertEquals(38, page.imageUrls.size()); assertEquals(CHAPTER, page.chapterId);
        assertEquals("第01话", page.title); assertEquals("", page.nextPageUrl);
        assertTrue(page.imageUrls.get(0).contains("f74f09d566f4404ba555fd441345c358.jpg"));
        assertTrue(page.imageUrls.get(37).contains("e60030a3d4754da590fd46060eb94dc1.jpg"));
    }

    @Test public void imagePagesAreFetchedInOrderWithoutDroppingLaterPages() throws Exception {
        Fake source = new Fake(); source.images = new ArrayList<>();
        source.images.add(imagePage(1, 2, 3, "a", "b")); source.images.add(imagePage(2, 2, 3, "c"));
        ComicModels.ChapterPage page = source.chapter(CHAPTER);
        assertEquals(3, page.imageUrls.size()); assertTrue(page.imageUrls.get(2).endsWith("/c.jpg"));
        assertTrue(source.urls.get(2).contains("?page=2&page_size=100&image_source=https%3A%2F%2Ftu.mwzu.cc"));
    }

    @Test public void incompleteRepeatedAndChangingImagePagesFailClearly() throws Exception {
        for (List<String> responses : java.util.Arrays.asList(
                java.util.Arrays.asList(imagePage(1, 2, 3, "a", "b"), imagePage(2, 2, 3, "b")),
                Collections.singletonList(imagePage(1, 1, 3, "a", "b")),
                java.util.Arrays.asList(imagePage(1, 2, 3, "a", "b"), imagePage(1, 2, 3, "c")),
                java.util.Arrays.asList(imagePage(1, 2, 3, "a", "b"), imagePage(2, 2, 4, "c", "d")),
                Collections.singletonList("{\"code\":403,\"msg\":\"需登录\"}"))) {
            Fake source = new Fake(); source.images = responses;
            assertThrows(IOException.class, () -> source.chapter(CHAPTER));
        }
    }

    @Test public void invalidIdsAndMismatchedChapterFailBeforeImageRequest() throws Exception {
        Fake source = new Fake();
        assertThrows(IOException.class, () -> source.detail("copy4000:abc"));
        assertThrows(IOException.class, () -> source.chapter("https://manwace.cc/search"));
        assertThrows(IOException.class, () -> source.chapter("https://manwace.cc/comic/123/2161449"));
        assertEquals(1, source.urls.size());
    }

    @Test public void sourceConfigRoundTripsRoutesAndEnabledState() throws Exception {
        SourceConfig defaults = SourceConfig.manwa(false);
        JSONObject override = defaults.toJson();
        override.getJSONObject("routes").put("imageSource", "https://mwtuwu.cc");
        SourceConfig restored = SourceConfig.fromJson(override, SourceConfig.manwa(true));
        assertFalse(restored.enabled); assertEquals("manwa", restored.id);
        assertEquals("https://mwtuwu.cc", restored.route("imageSource"));
        assertTrue(restored.route("search").contains("type=mh"));
    }

    private static String imagePage(int page, int pages, int total, String... names) throws Exception {
        JSONArray images = new JSONArray();
        for (String name : names) images.put(new JSONObject().put("url", "https://tu.mwzu.cc/" + name + ".jpg"));
        return new JSONObject().put("code", 200).put("data", new JSONObject().put("images", images)
                .put("pagination", new JSONObject().put("current_page", page).put("total_pages", pages).put("total", total))).toString();
    }

    static String fixture(String name) throws IOException {
        try (InputStream input = ManwaComicSourceTest.class.getResourceAsStream("/manwa/" + name);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            assertNotNull(input); byte[] buffer = new byte[4096]; int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            return output.toString("UTF-8");
        }
    }

    private static class Fake extends ManwaComicSource {
        final List<String> urls = new ArrayList<>();
        JSONObject body;
        String directory;
        List<String> images;
        int imageIndex;
        @Override protected String request(String url, JSONObject requestBody, String referer) throws IOException {
            urls.add(url); body = requestBody;
            assertTrue(referer.startsWith("https://manwace.cc/"));
            if (url.contains("/api/search")) return fixture("search.json");
            if (url.contains("/api/cate")) return fixture("cate.json");
            if (url.endsWith("/chapters")) return directory == null ? fixture("chapters.json") : directory;
            if (url.contains("/chapter/info/")) return fixture("chapter-info.json");
            if (url.contains("/image/")) return images == null ? fixture("images.json") : images.get(imageIndex++);
            return fixture("detail.html");
        }
    }
}
