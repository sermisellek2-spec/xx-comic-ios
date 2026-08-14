package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class GmhComicSource implements ComicSource {
    private static final String SOURCE_ID = "gmh";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String DESKTOP_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern CARD_PATTERN = Pattern.compile(
            "<a[^>]+href=\"([^\"]*?/manga/[^\"]+)\"[\\s\\S]{0,900}?<img[^>]+(?:src|data-src)=\"([^\"]+)\"[\\s\\S]{0,900}?<h3[^>]*class=\"[^\"]*cardtitle[^\"]*\"[^>]*>([\\s\\S]*?)</h3>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern META_PATTERN = Pattern.compile(
            "<meta[^>]+(?:property|name)=\"([^\"]+)\"[^>]+content=\"([^\"]*)\"",
            Pattern.CASE_INSENSITIVE);
    private static final String GMH_IMAGE_PREFIX = "J7r";
    private static final String GMH_IMAGE_SUFFIX = "nQ";
    private static final String GMH_MARKER_ONE = "kD";
    private static final String GMH_MARKER_TWO = "W4s";
    private static final String GMH_SOURCE_ALPHABET = "_-9876543210abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    private static final String GMH_TARGET_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    private final SourceConfig config;
    private final Map<String, String> midCache = new HashMap<>();
    private final Map<String, JSONObject> mangaCache = new HashMap<>();

    public GmhComicSource() {
        this(SourceConfig.gmh(true));
    }

    public GmhComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.gmh(true) : config;
    }

    @Override public String id() { return SOURCE_ID; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return parseCards(fetch(categoryUrl("all", page)));
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        String encoded = java.net.URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        return parseCards(fetch(absolute(config.route("search").replace("{keyword}", encoded))));
    }

    @Override
    public List<String> categories() {
        return Arrays.asList("韩漫", "热门", "国漫", "日漫");
    }

    @Override
    public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        String html = fetch(categoryUrl("all", 1));
        LinkedHashMap<String, String> genres = new LinkedHashMap<>();
        LinkedHashMap<String, String> tags = new LinkedHashMap<>();
        Matcher links = Pattern.compile("<a[^>]+href=[\"']/(manga-(genre|tag)/([^/\"']+))[\"'][^>]*>[\\s\\S]*?<button[^>]*>([\\s\\S]*?)</button>[\\s\\S]*?</a>", Pattern.CASE_INSENSITIVE).matcher(html);
        while (links.find()) {
            String label = clean(links.group(4)).replaceFirst("^#", "");
            if (TextUtils.isEmpty(label)) continue;
            ("genre".equalsIgnoreCase(links.group(2)) ? genres : tags).put(label, links.group(3));
        }
        if (genres.isEmpty() || tags.isEmpty()) throw new IOException(config.name + " 分类解析失败");
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        groups.add(SourceFilters.group("genre", "漫画类型", genres));
        groups.add(SourceFilters.group("tag", "热门标签", tags));
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        return parseCards(fetch(categoryUrl(region, page)));
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        String tag = SourceFilters.value(filters, "tag", "all");
        String genre = SourceFilters.value(filters, "genre", "all");
        String path = !"all".equals(tag) ? "/manga-tag/" + tag
                : !"all".equals(genre) ? "/manga-genre/" + genre : "/manga";
        if (page > 1) path += "/page/" + page;
        return parseCards(fetch(absolute(path)));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetchDetailHtml(rawId);
        String mid = midFor(rawId, html);
        JSONObject data = TextUtils.isEmpty(mid) ? null : mangaData(mid);
        String title = data == null ? clean(meta(html, "og:title").replace("-G社漫畫 - G社漫畫", "")) : data.optString("title");
        String cover = data == null ? meta(html, "og:image") : data.optString("cover");
        String description = data == null ? meta(html, "description") : data.optString("desc");
        String status = "";
        if (data != null) status = "1".equals(data.optString("status")) ? "连载中" : "已完结";
        List<String> tags = new ArrayList<>();
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, clean(title), cleanUrl(cover), "", tags);
        return new ComicModels.ComicDetail(summary, "", status, clean(description), "", new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String mid = midFor(rawId, null);
        JSONObject data = mangaData(mid);
        JSONArray array = data.optJSONArray("chapters");
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        List<ComicModels.Chapter> visibleChapters = new ArrayList<>();
        if (array == null) return chapters;
        for (int i = 0; i < array.length(); i++) {
            JSONObject item = array.optJSONObject(i);
            if (item == null) continue;
            JSONObject attrs = item.optJSONObject("attributes");
            if (attrs == null) continue;
            String title = clean(attrs.optString("title"));
            String slug = attrs.optString("slug");
            String id = item.optString("id");
            if (TextUtils.isEmpty(id) || TextUtils.isEmpty(slug) || TextUtils.isEmpty(title)) continue;
            ComicModels.Chapter chapter = new ComicModels.Chapter(id, title, absolute(config.route("chapter").replace("{comicId}", rawId).replace("{chapterSlug}", slug)), 0, attrs.optInt("order", i));
            chapters.add(chapter);
            if (attrs.optInt("isAd", 0) == 0) visibleChapters.add(chapter);
        }
        return visibleChapters.isEmpty() ? chapters : visibleChapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String rawComicId = rawComicId(chapterUrl);
        String chapterSlug = rawChapterSlug(chapterUrl);
        String mid = midFor(rawComicId, null);
        JSONObject data = mangaData(mid);
        JSONArray chapterArray = data.optJSONArray("chapters");
        String chapterId = "";
        String title = "";
        if (chapterArray != null) {
            for (int i = 0; i < chapterArray.length(); i++) {
                JSONObject item = chapterArray.optJSONObject(i);
                JSONObject attrs = item == null ? null : item.optJSONObject("attributes");
                if (attrs != null && chapterSlug.equals(attrs.optString("slug"))) {
                    chapterId = item.optString("id");
                    title = attrs.optString("title");
                    break;
                }
            }
        }
        List<String> images = new ArrayList<>();
        if (!TextUtils.isEmpty(chapterId)) {
            JSONObject info = chapterInfo(mid, chapterId).optJSONObject("info");
            if (info != null) {
                title = clean(info.optString("title", title));
                images.addAll(decodeChapterImages(info.optJSONObject("images")));
            }
        }
        return new ComicModels.ChapterPage(chapterUrl, clean(title), images, "");
    }

    @Override
    public boolean healthCheck() {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(config.baseUrl + "/manga").openConnection();
            connection.setRequestMethod("HEAD");
            connection.setConnectTimeout(5000);
            connection.setReadTimeout(5000);
            int code = connection.getResponseCode();
            return code >= 200 && code < 400;
        } catch (IOException ignored) {
            return false;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private List<ComicModels.ComicSummary> parseCards(String html) {
        List<ComicModels.ComicSummary> list = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CARD_PATTERN.matcher(html == null ? "" : html);
        while (matcher.find()) {
            String href = decode(matcher.group(1));
            String rawId = rawComicId(href);
            if (TextUtils.isEmpty(rawId) || !seen.add(rawId)) continue;
            String cover = cleanUrl(matcher.group(2));
            String title = clean(matcher.group(3));
            if (title.matches("[a-z0-9\\-]+")) title = rawId.replace('-', ' ');
            list.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, "", new ArrayList<String>()));
        }
        return list;
    }

    private String categoryUrl(String region, int page) {
        String genre = config.filter("genre." + (TextUtils.isEmpty(region) ? "all" : region));
        String path = config.route("category")
                .replace("{genrePath}", TextUtils.isEmpty(genre) ? "" : "-genre/" + genre)
                .replace("{pagePath}", page <= 1 ? "" : "/page/" + page);
        if (TextUtils.isEmpty(genre) && page > 1) path = "/manga/page/" + page;
        return absolute(path);
    }

    private JSONObject mangaData(String mid) throws IOException {
        if (TextUtils.isEmpty(mid)) return new JSONObject();
        JSONObject cached = mangaCache.get(mid);
        if (cached != null) return cached;
        try {
            String json = fetch(config.route("mangaApi").replace("{mid}", mid));
            JSONObject root = new JSONObject(json);
            JSONObject data = root.optJSONObject("data");
            JSONObject result = data == null ? new JSONObject() : data;
            String slug = result.optString("slug");
            if (!TextUtils.isEmpty(slug)) midCache.put(slug, mid);
            mangaCache.put(mid, result);
            return result;
        } catch (Exception error) {
            throw new IOException("G社漫画详情解析失败", error);
        }
    }

    private JSONObject chapterInfo(String mid, String chapterId) throws IOException {
        try {
            String json = fetch(config.route("chapterApi").replace("{mid}", mid).replace("{chapterId}", chapterId));
            JSONObject data = new JSONObject(json).optJSONObject("data");
            return data == null ? new JSONObject() : data;
        } catch (Exception error) {
            throw new IOException("G社漫画章节解析失败", error);
        }
    }

    private String fetchDetailHtml(String rawId) throws IOException {
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        String mid = first(html, "data-mid=\"(\\d+)\"");
        if (!TextUtils.isEmpty(mid)) midCache.put(rawId, mid);
        return html;
    }

    private String midFor(String rawId, String html) throws IOException {
        String cached = midCache.get(rawId);
        if (!TextUtils.isEmpty(cached)) return cached;
        String sourceHtml = html == null ? fetchDetailHtml(rawId) : html;
        String mid = first(sourceHtml, "data-mid=\"(\\d+)\"");
        if (!TextUtils.isEmpty(mid)) midCache.put(rawId, mid);
        return mid;
    }

    private List<String> decodeChapterImages(JSONObject imagesObject) throws IOException {
        List<String> images = new ArrayList<>();
        if (imagesObject == null) return images;
        JSONArray plain = imagesObject.optJSONArray("images");
        if (plain != null) {
            for (int i = 0; i < plain.length(); i++) addImageUrl(images, imagesObject, plain.opt(i));
            return images;
        }
        String encrypted = imagesObject.optString("images");
        if (TextUtils.isEmpty(encrypted)) return images;
        try {
            JSONArray decoded = new JSONArray(decodeEncryptedImages(encrypted));
            for (int i = 0; i < decoded.length(); i++) addImageUrl(images, imagesObject, decoded.opt(i));
            return images;
        } catch (Exception error) {
            throw new IOException("G社漫画图片解密失败", error);
        }
    }

    private void addImageUrl(List<String> images, JSONObject imagesObject, Object item) {
        String url = "";
        if (item instanceof JSONObject) url = ((JSONObject) item).optString("url");
        else if (item != null) url = String.valueOf(item);
        url = cleanUrl(url);
        if (TextUtils.isEmpty(url)) return;
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            String host = cleanUrl(imagesObject.optString("host"));
            if (TextUtils.isEmpty(host)) host = hostForLine(imagesObject.optInt("line", 1));
            url = host + (url.startsWith("/") ? url : "/" + url);
        }
        if (!images.contains(url)) images.add(url);
    }

    private String hostForLine(int line) {
        if (line == 2) return "https://f40-1-4.g-mh.online";
        return "https://t40-1-4.g-mh.online";
    }

    private String decodeEncryptedImages(String encrypted) throws Exception {
        if (!encrypted.startsWith(GMH_IMAGE_PREFIX) || !encrypted.endsWith(GMH_IMAGE_SUFFIX)) {
            throw new IllegalArgumentException("bad boundary");
        }
        String body = encrypted.substring(GMH_IMAGE_PREFIX.length(), encrypted.length() - GMH_IMAGE_SUFFIX.length());
        int payloadLength = body.length() - GMH_MARKER_ONE.length() - GMH_MARKER_TWO.length();
        int tailLength = payloadLength / 3;
        int headLength = (payloadLength - tailLength) / 2;
        int middleLength = payloadLength - tailLength - headLength;
        int markerOneStart = headLength;
        int middleStart = markerOneStart + GMH_MARKER_ONE.length();
        int markerTwoStart = middleStart + middleLength;
        int tailStart = markerTwoStart + GMH_MARKER_TWO.length();
        if (!GMH_MARKER_ONE.equals(body.substring(markerOneStart, middleStart))
                || !GMH_MARKER_TWO.equals(body.substring(markerTwoStart, tailStart))) {
            throw new IllegalArgumentException("bad markers");
        }
        String head = body.substring(0, headLength);
        String middle = body.substring(middleStart, markerTwoStart);
        String tail = body.substring(tailStart);
        String mixed = tail + head + middle;
        StringBuilder restored = new StringBuilder(mixed.length());
        for (int i = 0, index = 0; i < mixed.length(); i += 7, index++) {
            String chunk = mixed.substring(i, Math.min(i + 7, mixed.length()));
            restored.append(index % 2 == 0 ? chunk : new StringBuilder(chunk).reverse().toString());
        }
        StringBuilder base64Url = new StringBuilder(restored.length());
        for (int i = 0; i < restored.length(); i++) {
            int position = GMH_SOURCE_ALPHABET.indexOf(restored.charAt(i));
            if (position < 0) throw new IllegalArgumentException("bad alphabet");
            base64Url.append(GMH_TARGET_ALPHABET.charAt(position));
        }
        byte[] decoded = Base64.decode(base64Url.toString(), Base64.URL_SAFE | Base64.NO_WRAP);
        return new String(decoded, "UTF-8");
    }

    private String fetch(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(15000);
        connection.setRequestProperty("User-Agent", DESKTOP_USER_AGENT);
        connection.setRequestProperty("Referer", config.referer);
        try (InputStream stream = connection.getInputStream()) {
            BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
            StringBuilder builder = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) builder.append(line).append('\n');
            return builder.toString();
        } finally {
            connection.disconnect();
        }
    }

    private String first(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? clean(matcher.group(1)) : "";
    }

    private String meta(String html, String key) {
        Matcher matcher = META_PATTERN.matcher(html == null ? "" : html);
        while (matcher.find()) if (key.equals(matcher.group(1))) return clean(matcher.group(2));
        return "";
    }

    private String rawComicId(String value) {
        if (value == null) return "";
        if (value.startsWith(PREFIX)) value = value.substring(PREFIX.length());
        int manga = value.indexOf("/manga/");
        if (manga >= 0) value = value.substring(manga + 7);
        int slash = value.indexOf('/');
        if (slash >= 0) value = value.substring(0, slash);
        return value.trim();
    }

    private String rawChapterSlug(String value) {
        if (value == null) return "";
        int query = value.indexOf('?');
        if (query >= 0) value = value.substring(0, query);
        int slash = value.lastIndexOf('/');
        return slash >= 0 ? value.substring(slash + 1).trim() : value.trim();
    }

    private String absolute(String url) {
        if (TextUtils.isEmpty(url)) return "";
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        if (url.startsWith("/")) return config.baseUrl + url;
        return config.baseUrl + "/" + url;
    }

    private String clean(String value) {
        if (value == null) return "";
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            return Html.fromHtml(value, Html.FROM_HTML_MODE_LEGACY).toString().replaceAll("\\s+", " ").trim();
        }
        return Html.fromHtml(value).toString().replaceAll("\\s+", " ").trim();
    }

    private String decode(String value) {
        return value == null ? "" : value.replace("&amp;", "&").replace("&quot;", "\"");
    }

    private String cleanUrl(String value) {
        String decoded = decode(value).replace("\\/", "/");
        int amp = decoded.indexOf("&");
        return amp > 0 ? decoded.substring(0, amp) : decoded;
    }
}
