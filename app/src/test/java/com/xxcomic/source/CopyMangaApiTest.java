package com.xxcomic.source;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.Assert.*;

public class CopyMangaApiTest {
    private static final String SLUG = "bajiaolongdediwang";
    private static final String CHAPTER = "4cdb2472-697a-11ed-a96e-024352452ce0";

    @Test public void readsAllApiPagesEvenWhenGroupCountIsSmaller() throws Exception {
        List<String> requests = new ArrayList<>();
        CopyMangaComicSource source = new CopyMangaComicSource() {
            @Override protected String fetch(String url) { throw new AssertionError("Directory must not depend on web HTML"); }
            @Override protected String fetchApi(String url) throws IOException {
                requests.add(url);
                if (url.contains("/comic2/")) return fixture("api-detail.json");
                return fixture(url.endsWith("offset=100") ? "api-chapters-page2.json" : "api-chapters-page1.json");
            }
        };
        List<ComicModels.Chapter> chapters = source.chapters("copy4000:" + SLUG);
        assertEquals(190, chapters.size());
        assertEquals(3, requests.size());
        assertEquals(CHAPTER, chapters.get(0).chapterId);
        assertEquals("第192話", chapters.get(189).title);
        assertEquals(189, chapters.get(189).chapterSlot);
        assertEquals("https://www.copy4000.com/comic/" + SLUG + "/chapter/" + CHAPTER, chapters.get(0).url);
    }

    @Test public void emptyPartialRepeatedAndWrongComicPagesFail() throws Exception {
        JSONObject page = new JSONObject(fixture("api-chapters-page2.json"));
        page.getJSONObject("results").put("list", new JSONArray());
        assertThrows(IOException.class, () -> directoryWithSecondPage(page.toString()).chapters(SLUG));
        JSONObject repeated = new JSONObject(fixture("api-chapters-page1.json"));
        repeated.getJSONObject("results").put("offset", 100);
        assertThrows(IOException.class, () -> directoryWithSecondPage(repeated.toString()).chapters(SLUG));
        JSONObject wrong = new JSONObject(fixture("api-chapters-page2.json"));
        wrong.getJSONObject("results").getJSONArray("list").getJSONObject(0).put("comic_path_word", "wrong");
        assertThrows(IOException.class, () -> directoryWithSecondPage(wrong.toString()).chapters(SLUG));
        assertThrows(IOException.class, () -> directoryWithSecondPage("{\"code\":200,\"results\":null}").chapters(SLUG));
    }

    @Test public void readsEveryGroupIncludingGroupWithUnreliableZeroCount() throws Exception {
        JSONObject detail = new JSONObject(fixture("api-detail.json"));
        detail.getJSONObject("results").put("groups", new JSONObject()
                .put("default", new JSONObject().put("path_word", "default").put("count", 0))
                .put("extra", new JSONObject().put("path_word", "extra").put("count", 0)));
        CopyMangaComicSource source = new CopyMangaComicSource() {
            @Override protected String fetchApi(String url) throws IOException {
                if (url.contains("/comic2/")) return detail.toString();
                try {
                    String group = url.contains("/extra/") ? "extra" : "default";
                    JSONObject item = new JSONObject().put("uuid", group).put("name", group)
                            .put("comic_path_word", SLUG).put("group_path_word", group);
                    return new JSONObject().put("code", 200).put("results", new JSONObject()
                            .put("offset", 0).put("total", 1).put("list", new JSONArray().put(item))).toString();
                } catch (Exception e) { throw new IOException(e); }
            }
        };
        List<ComicModels.Chapter> chapters = source.chapters(SLUG);
        assertEquals(2, chapters.size());
        assertNotEquals(chapters.get(0).sectionSlot, chapters.get(1).sectionSlot);
    }

    @Test public void readerUsesOriginalArrayOrderAndCompatibleSavedUrl() throws Exception {
        JSONObject saved = SourceConfig.copy4000(true).toJson();
        JSONObject routes = saved.getJSONObject("routes");
        for (String key : new String[]{"apiBaseUrl", "apiFallbackUrls", "apiDetail", "apiChapters", "apiChapter"}) routes.remove(key);
        SourceConfig restored = SourceConfig.fromJson(saved, SourceConfig.copy4000(true));
        assertEquals("https://api.manga2026.xyz", restored.route("apiBaseUrl"));
        assertTrue(restored.route("apiFallbackUrls").contains("mapi.elfgjfghkk.club"));
        List<String> urls = new ArrayList<>();
        CopyMangaComicSource source = new CopyMangaComicSource(restored) {
            @Override protected String fetchApi(String url) throws IOException { urls.add(url); return fixture("api-reader.json"); }
        };
        ComicModels.ChapterPage page = source.chapter("https://old.example/comic/" + SLUG + "/chapter/" + CHAPTER);
        assertEquals("https://api.manga2026.xyz/api/v3/comic/" + SLUG + "/chapter/" + CHAPTER + "?platform=3", urls.get(0));
        assertEquals("https://www.copy4000.com/comic/" + SLUG + "/chapter/" + CHAPTER, page.chapterId);
        JSONArray expected = new JSONObject(fixture("api-reader.json")).getJSONObject("results").getJSONObject("chapter").getJSONArray("contents");
        assertEquals(86, page.imageUrls.size());
        for (int i = 0; i < expected.length(); i++) assertEquals(expected.getJSONObject(i).getString("url"), page.imageUrls.get(i));
        assertEquals("", page.nextPageUrl);
    }

    @Test public void rejectsNullLockedMismatchedAndIncompleteReaders() throws Exception {
        CopyMangaComicSource source = new CopyMangaComicSource();
        assertThrows(IOException.class, () -> source.parseApiReader("u", SLUG, CHAPTER, "{\"code\":200,\"results\":null}"));
        for (String invalid : new String[]{"locked", "uuid", "comic", "size", "empty"}) {
            JSONObject response = new JSONObject(fixture("api-reader.json"));
            JSONObject data = response.getJSONObject("results"), chapter = data.getJSONObject("chapter");
            if (invalid.equals("locked")) data.put("is_lock", true);
            if (invalid.equals("uuid")) chapter.put("uuid", "wrong");
            if (invalid.equals("comic")) data.getJSONObject("comic").put("path_word", "wrong");
            if (invalid.equals("size")) chapter.put("size", 999);
            if (invalid.equals("empty")) chapter.put("contents", new JSONArray());
            assertThrows(invalid, IOException.class, () -> source.parseApiReader("u", SLUG, CHAPTER, response.toString()));
        }
    }

    @Test public void apiHostOverrideAndHeadersReachTheHttpServer() throws Exception {
        try (ServerSocket server = new ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))) {
            server.setSoTimeout(5000);
            AtomicReference<String> headers = new AtomicReference<>();
            AtomicReference<Exception> failure = new AtomicReference<>();
            byte[] body = fixture("api-reader.json").getBytes(StandardCharsets.UTF_8);
            Thread responder = new Thread(() -> {
                try (Socket socket = server.accept()) {
                    socket.setSoTimeout(5000);
                    BufferedReader reader = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
                    StringBuilder request = new StringBuilder(); String line;
                    while ((line = reader.readLine()) != null && !line.isEmpty()) request.append(line).append('\n');
                    headers.set(request.toString().toLowerCase(Locale.ROOT));
                    socket.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Length: " + body.length + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII));
                    socket.getOutputStream().write(body);
                    socket.getOutputStream().flush();
                } catch (Exception e) { failure.set(e); }
            });
            responder.start();
            JSONObject override = SourceConfig.copy4000(true).toJson();
            override.getJSONObject("routes").put("apiBaseUrl", "http://127.0.0.1:" + server.getLocalPort());
            CopyMangaComicSource source = new CopyMangaComicSource(SourceConfig.fromJson(override, SourceConfig.copy4000(true)));
            assertEquals(86, source.chapter("https://www.copy4000.com/comic/" + SLUG + "/chapter/" + CHAPTER).imageUrls.size());
            responder.join(6000);
            assertNull(failure.get());
            for (String expected : new String[]{"user-agent: copy/3.0.9", "accept: application/json", "platform: 3", "version: 3.0.9", "region: 1", "webp: 1"})
                assertTrue(expected, headers.get().contains(expected));
            assertFalse(headers.get().contains("dnts:"));
        }
    }

    private CopyMangaComicSource directoryWithSecondPage(String secondPage) {
        return new CopyMangaComicSource() {
            @Override protected String fetchApi(String url) throws IOException {
                if (url.contains("/comic2/")) return fixture("api-detail.json");
                return url.endsWith("offset=100") ? secondPage : fixture("api-chapters-page1.json");
            }
        };
    }

    private static String fixture(String name) throws IOException {
        try (InputStream in = CopyMangaApiTest.class.getResourceAsStream("/copy4000/" + name); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            if (in == null) throw new IOException("Missing fixture " + name);
            byte[] buffer = new byte[8192]; int read;
            while ((read = in.read(buffer)) != -1) out.write(buffer, 0, read);
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
    }
}
