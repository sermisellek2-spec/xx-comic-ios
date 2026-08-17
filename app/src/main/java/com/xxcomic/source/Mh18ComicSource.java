package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;

import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Mh18ComicSource implements ComicSource {
    private static final String SOURCE_ID = "mh18";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String DESKTOP_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern CARD_PATTERN = Pattern.compile(
            "<a[^>]+href=\"([^\"]*?/manga/[^\"]+)\"[\\s\\S]{0,900}?<img[^>]+(?:src|data-src)=\"([^\"]+)\"[\\s\\S]{0,900}?<h3[^>]*class=\"[^\"]*cardtitle[^\"]*\"[^>]*>([\\s\\S]*?)</h3>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern SCRIPT_PATTERN = Pattern.compile("<script\\b([^>]*)>([\\s\\S]*?)</script>", Pattern.CASE_INSENSITIVE);
    private static final Pattern ANCHOR_PATTERN = Pattern.compile("<a\\b[^>]*>", Pattern.CASE_INSENSITIVE);
    private static final Pattern IMAGE_PATTERN = Pattern.compile("<img\\b[^>]*>", Pattern.CASE_INSENSITIVE);
    private static final Pattern TAG_LINK_PATTERN = Pattern.compile(
            "<a[^>]+href=[\"']/manga-tag/[^\"']+[\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE);
    private final SourceConfig config;
    private final BrowserSession browserSession;

    private static final class CloudflareChallengeException extends IOException {
        CloudflareChallengeException() {
            super("18漫画需要浏览器验证");
        }
    }

    public Mh18ComicSource() {
        this(SourceConfig.mh18(true), null);
    }

    public Mh18ComicSource(SourceConfig config) {
        this(config, null);
    }

    public Mh18ComicSource(SourceConfig config, BrowserSession browserSession) {
        this.config = config == null ? SourceConfig.mh18(true) : config;
        this.browserSession = browserSession;
    }

    @Override public String id() { return SOURCE_ID; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return parseCards(fetch(categoryUrl("all", page)));
    }

    public void verifyAccess() throws IOException {
        String html = fetchInteractive(config.baseUrl + "/manga");
        if (!CARD_PATTERN.matcher(html == null ? "" : html).find()) {
            throw new IOException(config.name + " 页面未就绪");
        }
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        return parseCards(fetch(absolute(searchPath(keyword, page))));
    }

    static String searchPath(String keyword, int page) throws IOException {
        String encoded = java.net.URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        return "/s/" + encoded + (page > 1 ? "/page/" + page : "");
    }

    @Override
    public List<String> categories() {
        return Arrays.asList("韩漫", "真人写真", "日漫", "AI写真", "热门漫画");
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
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        JSONObject data = structuredData(html, "ComicSeries");
        String title = clean(data.optString("name"));
        if (TextUtils.isEmpty(title)) title = clean(meta(html, "og:title").replaceFirst("-18漫畫\\s*-?\\s*18漫畫$", ""));
        String cover = jsonString(data.opt("image"));
        if (TextUtils.isEmpty(cover)) cover = meta(html, "og:image");
        String description = clean(data.optString("description"));
        if (TextUtils.isEmpty(description)) description = meta(html, "description");
        String status = clean(data.optString("creativeWorkStatus"))
                .replace("連載中", "连载中").replace("完結", "已完结");
        String latestChapter = "";
        JSONObject latest = data.optJSONObject("hasPart");
        if (latest != null) latestChapter = clean(latest.optString("name"));
        List<String> tags = jsonStrings(data.opt("genre"));
        if (tags.isEmpty()) tags.addAll(parseTags(html));
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(
                SOURCE_ID, PREFIX + rawId, title, cleanUrl(cover), "", tags);
        return new ComicModels.ComicDetail(summary, parseAuthors(data.opt("author")), status,
                description, latestChapter, new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String catalog = fetch(absolute("/chapterlist/" + rawId));
        String html = fetch(catalogApiUrl(catalog, config.domain));
        List<ComicModels.Chapter> chapters = parseChapters(html, rawId, config.baseUrl);
        if (chapters.isEmpty()) throw new IOException("18漫画目录解析失败");
        return chapters;
    }

    static String catalogApiUrl(String html, String domain) throws IOException {
        String holder = tagWithAttribute(html, "id", "allchapters");
        String mangaId = attribute(holder, "data-mid");
        if (!mangaId.matches("\\d+")) throw new IOException("18漫画目录参数解析失败");
        return trustedApiBase(holder, domain, "18漫画目录参数解析失败")
                + "/manga/get?mid=" + mangaId + "&mode=all";
    }

    static List<ComicModels.Chapter> parseChapters(String html, String rawId, String baseUrl) {
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher anchors = ANCHOR_PATTERN.matcher(html);
        while (anchors.find()) {
            String tag = anchors.group();
            String href = attribute(tag, "href");
            if (!href.matches("(?:https?://[^/]+)?/manga/" + Pattern.quote(rawId) + "/[^/?#]+") || !seen.add(href)) continue;
            String chapterId = attribute(tag, "data-cs");
            String title = cleanAttribute(attribute(tag, "data-ct"));
            if (chapterId.isEmpty() || title.isEmpty()) continue;
            chapters.add(new ComicModels.Chapter(chapterId, title,
                    joinUrl(baseUrl, href), 0, chapters.size()));
        }
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String html = fetch(absolute(chapterUrl));
        String contentTag = tagWithAttribute(html, "id", "chapterContent");
        String mangaId = attribute(contentTag, "data-ms");
        String chapterId = attribute(contentTag, "data-cs");
        String title = clean(attribute(contentTag, "data-ct"));
        if (!mangaId.matches("\\d+") || !chapterId.matches("\\d+")) {
            throw new IOException("18漫画章节参数解析失败");
        }
        String content = fetch(chapterApiUrl(html, config.domain));
        List<String> images = parseChapterImages(content);
        if (images.isEmpty()) throw new IOException("18漫画正文图片解析失败");
        return new ComicModels.ChapterPage(chapterUrl, title, images, "");
    }

    static String chapterApiUrl(String html, String domain) throws IOException {
        String holder = tagWithAttribute(html, "id", "chapterContent");
        String mangaId = attribute(holder, "data-ms");
        String chapterId = attribute(holder, "data-cs");
        if (!mangaId.matches("\\d+") || !chapterId.matches("\\d+")) {
            throw new IOException("18漫画章节参数解析失败");
        }
        return trustedApiBase(holder, domain, "18漫画章节参数解析失败")
                + "/chapter/getcontent?m=" + mangaId + "&c=" + chapterId;
    }

    @Override
    public boolean healthCheck() {
        try {
            return !TextUtils.isEmpty(fetch(config.baseUrl + "/manga"));
        } catch (IOException ignored) {
            return false;
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
            String title = clean(matcher.group(3));
            if (title.matches("[a-z0-9\\-]+")) title = rawId.replace('-', ' ');
            list.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title,
                    cleanUrl(matcher.group(2)), "", new ArrayList<String>()));
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

    static JSONObject structuredData(String html, String type) {
        Matcher scripts = SCRIPT_PATTERN.matcher(html == null ? "" : html);
        while (scripts.find()) {
            if (!"application/ld+json".equalsIgnoreCase(attribute(scripts.group(1), "type"))) continue;
            try {
                JSONObject object = findStructuredObject(
                        new JSONTokener(scripts.group(2).trim()).nextValue(), type);
                if (object != null) return object;
            } catch (Exception ignored) {
            }
        }
        return new JSONObject();
    }

    private static JSONObject findStructuredObject(Object value, String type) {
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            if (matchesStructuredType(object.opt("@type"), type)) return object;
            JSONObject nested = findStructuredObject(object.opt("@graph"), type);
            if (nested != null) return nested;
        } else if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            for (int i = 0; i < array.length(); i++) {
                JSONObject nested = findStructuredObject(array.opt(i), type);
                if (nested != null) return nested;
            }
        }
        return null;
    }

    private static boolean matchesStructuredType(Object value, String type) {
        if (value instanceof JSONArray) {
            JSONArray types = (JSONArray) value;
            for (int i = 0; i < types.length(); i++) {
                if (type.equalsIgnoreCase(types.optString(i))) return true;
            }
            return false;
        }
        return value != null && type.equalsIgnoreCase(String.valueOf(value));
    }

    private String parseAuthors(Object value) {
        List<String> authors = new ArrayList<>();
        if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            for (int i = 0; i < array.length(); i++) {
                JSONObject author = array.optJSONObject(i);
                String name = author == null ? clean(array.optString(i)) : clean(author.optString("name"));
                if (!TextUtils.isEmpty(name)) authors.add(name);
            }
        } else if (value instanceof JSONObject) {
            String name = clean(((JSONObject) value).optString("name"));
            if (!TextUtils.isEmpty(name)) authors.add(name);
        } else if (value != null) {
            String name = clean(String.valueOf(value));
            if (!TextUtils.isEmpty(name)) authors.add(name);
        }
        return TextUtils.join(" / ", authors);
    }

    private List<String> jsonStrings(Object value) {
        List<String> values = new ArrayList<>();
        if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            for (int i = 0; i < array.length(); i++) {
                String item = clean(array.optString(i));
                if (!TextUtils.isEmpty(item)) values.add(item);
            }
        } else if (value != null) {
            String item = clean(String.valueOf(value));
            if (!TextUtils.isEmpty(item)) values.add(item);
        }
        return values;
    }

    private List<String> parseTags(String html) {
        List<String> tags = new ArrayList<>();
        Matcher matcher = TAG_LINK_PATTERN.matcher(html == null ? "" : html);
        while (matcher.find()) {
            String tag = clean(matcher.group(1)).replaceFirst("^#", "");
            if (!TextUtils.isEmpty(tag) && !tags.contains(tag)) tags.add(tag);
        }
        return tags;
    }

    static List<String> parseChapterImages(String html) {
        List<String> images = new ArrayList<>();
        Matcher matcher = IMAGE_PATTERN.matcher(html == null ? "" : html);
        while (matcher.find()) {
            String tag = matcher.group();
            String url = attribute(tag, "data-src");
            if (url.isEmpty()) url = attribute(tag, "src");
            url = decode(url).replace("\\/", "/").trim();
            if ((url.startsWith("http://") || url.startsWith("https://")) && !images.contains(url)) images.add(url);
        }
        return images;
    }

    private static String tagWithAttribute(String html, String name, String value) {
        Matcher tags = Pattern.compile("<[^>]+>", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        while (tags.find()) if (value.equals(attribute(tags.group(), name))) return tags.group();
        return "";
    }

    private static String trustedApiBase(String tag, String domain,
                                         String errorMessage) throws IOException {
        try {
            URL url = new URL(attribute(tag, "data-host"));
            String host = url.getHost().toLowerCase(java.util.Locale.US);
            String root = domain == null ? "" : domain.toLowerCase(java.util.Locale.US);
            boolean trusted = host.equals(root) || host.endsWith("." + root);
            boolean defaultPort = url.getPort() == -1 || url.getPort() == 443;
            if (!"https".equalsIgnoreCase(url.getProtocol()) || !trusted || !defaultPort) {
                throw new IllegalArgumentException();
            }
            return "https://" + host;
        } catch (Exception error) {
            throw new IOException(errorMessage, error);
        }
    }

    private static String cleanAttribute(String value) {
        return decode(value).replaceAll("<[^>]+>", " ").replaceAll("\\s+", " ").trim();
    }

    private static String joinUrl(String baseUrl, String value) {
        if (value.startsWith("http://") || value.startsWith("https://")) return value;
        if (value.startsWith("//")) return "https:" + value;
        String root = baseUrl == null ? "" : baseUrl.replaceAll("/+$", "");
        return root + (value.startsWith("/") ? value : "/" + value);
    }

    private static String attribute(String tag, String name) {
        Matcher matcher = Pattern.compile("\\b" + Pattern.quote(name) + "\\s*=\\s*([\"'])([\\s\\S]*?)\\1", Pattern.CASE_INSENSITIVE)
                .matcher(tag == null ? "" : tag);
        return matcher.find() ? decode(matcher.group(2)) : "";
    }

    private String jsonString(Object value) {
        if (value instanceof JSONObject) return clean(((JSONObject) value).optString("url"));
        return value == null ? "" : clean(String.valueOf(value));
    }

    private String fetchInteractive(String url) throws IOException {
        if (browserSession != null && isMainSite(url)) return browserSession.fetchInteractive(url);
        return fetch(url);
    }

    private String fetch(String url) throws IOException {
        if (browserSession != null && isMainSite(url)) return browserSession.fetch(url);
        return fetchOnce(url);
    }

    private String fetchOnce(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(15000);
        applyRequestHeaders(connection);
        try {
            int code = connection.getResponseCode();
            if (code == 403 && "challenge".equalsIgnoreCase(connection.getHeaderField("Cf-Mitigated"))) {
                throw new CloudflareChallengeException();
            }
            if (code < 200 || code >= 400) throw new IOException("18漫画请求失败：HTTP " + code);
            try (InputStream stream = connection.getInputStream()) {
                BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
                StringBuilder builder = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) builder.append(line).append('\n');
                return builder.toString();
            }
        } finally {
            connection.disconnect();
        }
    }

    private void applyRequestHeaders(HttpURLConnection connection) {
        connection.setRequestProperty("User-Agent", DESKTOP_USER_AGENT);
        connection.setRequestProperty("Referer", config.referer);
    }

    private boolean isMainSite(String url) {
        try {
            String host = new URL(url).getHost();
            return config.domain.equalsIgnoreCase(host)
                    || (host != null && host.toLowerCase(java.util.Locale.US)
                    .endsWith("." + config.domain.toLowerCase(java.util.Locale.US)));
        } catch (Exception ignored) {
            return false;
        }
    }

    private String meta(String html, String key) {
        return clean(metaValue(html, key));
    }

    static String metaValue(String html, String key) {
        Matcher tags = Pattern.compile("<meta\\b[^>]*>", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        while (tags.find()) {
            String tag = tags.group();
            if (key.equalsIgnoreCase(attribute(tag, "property")) || key.equalsIgnoreCase(attribute(tag, "name"))) {
                return decode(attribute(tag, "content")).trim();
            }
        }
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

    private static String decode(String value) {
        return value == null ? "" : value.replace("&amp;", "&").replace("&quot;", "\"");
    }

    private String cleanUrl(String value) {
        return decode(value).replace("\\/", "/").trim();
    }
}
