package com.xxcomic.source;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.Assert.*;

public class CopyMangaComicSourceTest {
    private final CopyMangaComicSource source = new CopyMangaComicSource();

    @Test public void parsesCapturedSearchPages() throws Exception {
        List<ComicModels.ComicSummary> first = source.parseSearch(fixture("search-page1.json"));
        List<ComicModels.ComicSummary> second = source.parseSearch(fixture("search-page2.json"));
        assertEquals(12, first.size());
        assertEquals(12, second.size());
        assertEquals("copy4000:haiwuyu", first.get(0).comicId);
        assertEquals("葛城彰", first.get(0).subtitle);
        for (ComicModels.ComicSummary a : first) for (ComicModels.ComicSummary b : second) assertNotEquals(a.comicId, b.comicId);
    }

    @Test public void parsesUnrenderedCategoryAndLegitimateEmptyPage() throws Exception {
        List<ComicModels.ComicSummary> cards = source.parseCards(fixture("category.html"));
        assertEquals(50, cards.size());
        assertEquals("copy4000:renzhehejidao", cards.get(0).comicId);
        assertTrue(source.parseCards("<div class='exemptComic-box' total='522' list='[]'></div>").isEmpty());
        assertThrows(IOException.class, () -> source.parseCards("<html>verification</html>"));
    }

    @Test public void literalParserPreservesQuotesEscapesAndDoesNotExecuteExpressions() throws Exception {
        JSONArray array = (JSONArray) CopyMangaLiteral.parse("[{'name': 'Don\\'t \\\"replace\\\"', 'value': '字\\u4f60\\x21', 'flag': True, 'nil': None}]");
        assertEquals("Don't \"replace\"", array.getJSONObject(0).getString("name"));
        assertEquals("字你!", array.getJSONObject(0).getString("value"));
        assertTrue(array.getJSONObject(0).getBoolean("flag"));
        assertTrue(array.getJSONObject(0).isNull("nil"));
        assertThrows(IOException.class, () -> CopyMangaLiteral.parse("[alert('x')]"));
        assertThrows(IOException.class, () -> CopyMangaLiteral.parse("[]; document.cookie"));
        assertThrows(IOException.class, () -> CopyMangaLiteral.parse("['unterminated]"));
        String html = "<div class=\"exemptComic-box\" list=\"[{'path_word':'a','name':&quot;Don&#x27;t &amp; &#x4f60;&quot;,'author':[]}]\"></div>";
        assertEquals("Don't & 你", source.parseCards(html).get(0).title);
        assertEquals("&quot;", CopyMangaComicSource.attribute(" value='&amp;quot;'", "value"));
    }

    @Test public void filtersRetainCaseAndSortFirst() throws Exception {
        List<ComicModels.FilterGroup> groups = source.parseFilterGroups(fixture("filters.html"));
        assertEquals(4, groups.size());
        assertEquals("ordering", groups.get(0).key);
        assertEquals("-datetime_updated", groups.get(0).options.get(0).value);
        assertEquals(66, groups.get(1).options.size());
        boolean found = false;
        for (ComicModels.FilterOption option : groups.get(1).options) if ("COLOR".equals(option.value)) found = true;
        assertTrue(found);
        assertEquals("0", groups.get(2).options.get(1).value);
        assertEquals("0", groups.get(3).options.get(1).value);
    }

    @Test public void paginationAndAllFiltersUseRealParameters() throws Exception {
        Map<String, String> filters = new HashMap<>();
        filters.put("theme", "COLOR"); filters.put("region", "0"); filters.put("status", "0");
        assertEquals("/comics?limit=50&offset=50&ordering=-datetime_updated&theme=COLOR&region=0&status=0", source.categoryPath(filters, 2));
        filters.put("theme", "all"); filters.put("region", "all"); filters.put("status", "all");
        assertEquals("/comics?limit=50&offset=0&ordering=-datetime_updated", source.categoryPath(filters, 1));
        assertThrows(IOException.class, () -> source.categoryPath(filters, 0));
        filters.put("ordering", "bogus");
        assertThrows(IOException.class, () -> source.categoryPath(filters, 1));
    }

    @Test public void detailsAreIndependentFromDirectoryLoading() throws Exception {
        String html = "<title>测试漫画-测试漫畫-第192話-已完結</title><div class='comicParticulars-left-img'><img data-src='/cover.jpg'></div>"
                + "<div class='comicParticulars-title-right'><ul><li><h6>测试漫画</h6></li>"
                + "<li><span>狀態：</span><span>已完結</span></li>"
                + "<li><a href='/author/a/comics'>作者A</a><a href='/author/b/comics'>作者B</a></li>"
                + "<li><a href='/comics?theme=rexue'>#热血</a></li></ul></div>"
                + "<p class='intro'>简介&lt;文字&gt; &amp; 其他</p>";
        ComicModels.ComicDetail detail = source.parseDetail("sample", html);
        assertEquals("copy4000:sample", detail.summary.comicId);
        assertEquals("https://www.copy4000.com/cover.jpg", detail.summary.coverUrl);
        assertEquals("作者A / 作者B", detail.author);
        assertEquals("已完結", detail.status);
        assertEquals("第192話", detail.latestChapter);
        assertEquals("简介<文字> & 其他", detail.description);
        assertEquals("热血", detail.summary.tags.get(0));
        assertTrue(detail.chapters.isEmpty());
    }

    @Test public void capturedDirectoryUsesFullArrayInsteadOfInconsistentCount() throws Exception {
        String payload = new JSONObject(fixture("directory-encrypted.json")).getString("results");
        String key = new JSONObject(fixture("reader-chapter1-encrypted.json")).getString("cct");
        List<ComicModels.Chapter> chapters = source.parseChapters("bajiaolongdediwang", CopyMangaComicSource.decrypt(payload, key));
        assertEquals(190, chapters.size());
        assertEquals("4cdb2472-697a-11ed-a96e-024352452ce0", chapters.get(0).chapterId);
        assertEquals("第192話", chapters.get(189).title);
        assertEquals(189, chapters.get(189).chapterSlot);
        assertTrue(chapters.get(0).url.startsWith("https://www.copy4000.com/comic/bajiaolongdediwang/chapter/"));
    }

    @Test public void directoryPreservesMultipleGroupsAndRejectsEmptyOrWrongComic() throws Exception {
        String plain = "{\"build\":{\"path_word\":\"a\"},\"groups\":{"
                + "\"default\":{\"chapters\":[{\"id\":\"one\",\"name\":\"第1话\",\"type\":1}]},"
                + "\"extra\":{\"chapters\":[{\"id\":\"zero\",\"name\":\"番外0\",\"type\":3}]}}}";
        List<ComicModels.Chapter> list = source.parseChapters("a", plain);
        assertEquals(2, list.size());
        assertNotEquals(list.get(0).sectionSlot, list.get(1).sectionSlot);
        assertThrows(IOException.class, () -> source.parseChapters("wrong", plain));
        assertThrows(IOException.class, () -> source.parseChapters("a", "{\"build\":{\"path_word\":\"a\"},\"groups\":{}}"));
    }

    @Test public void capturedReadersDecodeAllImagesInOriginalOrder() throws Exception {
        for (int chapter = 1; chapter <= 2; chapter++) {
            JSONObject fixture = new JSONObject(fixture("reader-chapter" + chapter + "-encrypted.json"));
            String html = "<h4 class='header'>测试章</h4><script>var cct = '" + fixture.getString("cct")
                    + "'; var contentKey = '" + fixture.getString("contentKey") + "';</script>";
            ComicModels.ChapterPage page = source.parseReader("https://www.copy4000.com/comic/a/chapter/b", html);
            JSONArray expected = new JSONArray(fixture("reader-chapter" + chapter + "-images.json"));
            assertEquals(chapter == 1 ? 86 : 96, page.imageUrls.size());
            for (int i = 0; i < expected.length(); i++) assertEquals(expected.getJSONObject(i).getString("url"), page.imageUrls.get(i));
            assertEquals("", page.nextPageUrl);
        }
    }

    @Test public void emptyAndCorruptResponsesAreErrorsNotSuccessfulEmptyReaders() throws Exception {
        assertThrows(IOException.class, () -> source.parseReader("u", "<script>var contentKey = '';</script>"));
        assertThrows(IOException.class, () -> source.parseReader("u", "<html>challenge</html>"));
        assertThrows(IOException.class, () -> CopyMangaComicSource.decrypt("0123456789abcdefzz", "0123456789abcdef"));
        assertThrows(IOException.class, () -> source.parseSearch("{\"code\":403}"));
        assertThrows(IOException.class, () -> source.parseSearch("<html>error</html>"));
        assertTrue(source.parseSearch("{\"code\":200,\"results\":{\"list\":[]}}").isEmpty());
        JSONObject fixture = new JSONObject(fixture("reader-chapter1-encrypted.json"));
        assertThrows(IOException.class, () -> CopyMangaComicSource.decrypt(fixture.getString("contentKey"), "wrong-key"));
    }

    @Test public void customDomainConfigRoundTripAndRequests() throws Exception {
        JSONObject override = SourceConfig.copy4000(false).toJson();
        override.put("baseUrl", "https://mirror.test"); override.put("domain", "mirror.test");
        override.put("referer", "https://mirror.test/");
        SourceConfig config = SourceConfig.fromJson(override, SourceConfig.copy4000(true));
        assertFalse(config.enabled);
        final List<String> urls = new ArrayList<>();
        CopyMangaComicSource fake = new CopyMangaComicSource(config) {
            @Override protected String fetch(String url) throws IOException {
                urls.add(url);
                if (url.contains("/searchci/")) return "{\"code\":200,\"results\":{\"list\":[]}}";
                return "<script>var contentKey='';</script>";
            }
        };
        fake.search("海 & 空", 3);
        assertEquals("https://mirror.test/api/kb/web/searchci/comics?offset=24&platform=2&limit=12&q=%E6%B5%B7%20%26%20%E7%A9%BA&q_type=", urls.get(0));
        assertThrows(IOException.class, () -> fake.chapter("https://www.copy4000.com/comic/a/chapter/b"));
        assertEquals("https://mirror.test/comic/a/chapter/b", urls.get(1));
    }

    @Test public void recognizesCdnByHostBoundary() {
        assertTrue(CopyMangaComicSource.usesImageHost("https://sb.mangafunb.fun/a.jpg"));
        assertFalse(CopyMangaComicSource.usesImageHost("https://mangafunb.fun.evil.test/a.jpg"));
        assertFalse(CopyMangaComicSource.usesImageHost("https://other.test/mangafunb.fun/a.jpg"));
        assertFalse(CopyMangaComicSource.usesImageHost(null));
    }

    @Test public void nativeHttpRequestsPreferJsonAndDoNotSendDnts() throws Exception {
        try (java.net.ServerSocket server = new java.net.ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress())) {
            server.setSoTimeout(5000);
            java.util.concurrent.atomic.AtomicReference<String> request = new java.util.concurrent.atomic.AtomicReference<>();
            java.util.concurrent.atomic.AtomicReference<Exception> failure = new java.util.concurrent.atomic.AtomicReference<>();
            Thread responder = new Thread(() -> {
                try (java.net.Socket socket = server.accept()) {
                    socket.setSoTimeout(5000);
                    java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(socket.getInputStream(), java.nio.charset.StandardCharsets.UTF_8));
                    StringBuilder headers = new StringBuilder(); String line;
                    while ((line = reader.readLine()) != null && !line.isEmpty()) headers.append(line).append('\n');
                    request.set(headers.toString().toLowerCase(java.util.Locale.ROOT));
                    byte[] body = "{\"code\":200,\"results\":{\"list\":[]}}".getBytes(java.nio.charset.StandardCharsets.UTF_8);
                    socket.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Length: " + body.length + "\r\nConnection: close\r\n\r\n").getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                    socket.getOutputStream().write(body);
                    socket.getOutputStream().flush();
                } catch (Exception e) { failure.set(e); }
            });
            responder.start();
            String response = source.fetch("http://" + server.getInetAddress().getHostAddress() + ":" + server.getLocalPort() + "/api/search");
            responder.join(6000);
            assertNull(failure.get());
            assertTrue(source.parseSearch(response).isEmpty());
            assertTrue(request.get().contains("accept: application/json"));
            assertTrue(request.get().contains("referer: https://www.copy4000.com/"));
            assertFalse(request.get().contains("dnts:"));
        }
    }

    private static String fixture(String name) throws IOException {
        try (InputStream in = CopyMangaComicSourceTest.class.getResourceAsStream("/copy4000/" + name);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            if (in == null) throw new IOException("Missing fixture " + name);
            byte[] buffer = new byte[8192]; int read;
            while ((read = in.read(buffer)) != -1) out.write(buffer, 0, read);
            return new String(out.toByteArray(), java.nio.charset.StandardCharsets.UTF_8);
        }
    }
}
