package com.xxcomic.source;

import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Native HTML/AES adapter for 六漫画. It deliberately does not expose keyword search. */
public class LiumanhuaComicSource implements ComicSource {
    private static final String SOURCE_ID = "liumanhua";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String DEFAULT_BASE_URL = "https://www.liumanhua.com";
    private static final String IMAGE_HOST = "s2.bzcdn.net";
    private static final String AES_KEY = "9S8$vJnU2ANeSRoF";
    private static final String USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final String LIST_SELECTOR = "cy_list_mh > ul";
    private static final Pattern LIST_PATTERN = Pattern.compile(
            "<div[^>]*class=[\\\"'][^\\\"']*\\bcy_list_mh\\b[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</div>", Pattern.CASE_INSENSITIVE);
    private static final Pattern UL_PATTERN = Pattern.compile("<ul[^>]*>([\\s\\S]*?)</ul>", Pattern.CASE_INSENSITIVE);
    private static final Pattern FILTER_PATTERN = Pattern.compile(
            "<div[^>]*class=[\\\"'][^\\\"']*\\bcy_tag\\b[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</div>", Pattern.CASE_INSENSITIVE);
    private static final Pattern LINK_PATTERN = Pattern.compile(
            "<a[^>]+href=[\\\"']([^\\\"']+)[\\\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<li[^>]*class=[\\\"'][^\\\"']*\\bchapter__item\\b[^\\\"']*[\\\"'][^>]*>[\\s\\S]*?<a[^>]+href=[\\\"']([^\\\"']+)[\\\"'][^>]*>([\\s\\S]*?)</a>[\\s\\S]*?</li>", Pattern.CASE_INSENSITIVE);
    private static final String[] FILTER_KEYS = {"classification", "subject", "type", "quality", "region", "copyright", "state"};

    private final SourceConfig config;

    public LiumanhuaComicSource() {
        this(SourceConfig.liumanhua(true));
    }

    public LiumanhuaComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.liumanhua(true) : config;
    }

    @Override public String id() { return config.id; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }
    @Override public boolean supportsSearch() { return false; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return parseCards(fetch(categoryPath(null, page), false));
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        throw new IOException(config.name + "暂不支持搜索");
    }

    @Override
    public List<String> categories() throws IOException {
        List<ComicModels.FilterGroup> groups = filterGroups();
        List<String> result = new ArrayList<>();
        if (!groups.isEmpty()) {
            for (ComicModels.FilterOption option : groups.get(0).options) {
                if (!"all".equals(option.value)) result.add(option.label);
            }
        }
        return result;
    }

    @Override
    public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        List<ComicModels.FilterGroup> groups = parseFilterGroups(fetch(categoryPath(null, 1), false));
        if (groups.isEmpty()) throw new IOException(config.name + "分类解析失败");
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        return latest(page);
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        return parseCards(fetch(categoryPath(filters, page), false));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        if (empty(rawId)) throw new IOException(config.name + "详情 ID 为空");
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)), false);
        ComicModels.ComicDetail parsed = parseDetail(rawId, html);
        return new ComicModels.ComicDetail(parsed.summary, parsed.author, parsed.status,
                parsed.description, parsed.latestChapter, parseChapters(html, rawId));
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        List<ComicModels.Chapter> chapters = parseChapters(
                fetch(absolute(config.route("detail").replace("{comicId}", rawId)), false), rawId);
        if (chapters.isEmpty()) throw new IOException(config.name + "目录解析失败");
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = absolute(chapterUrl);
        String html = fetch(url, true);
        String encoded = first(html, "\\bparams\\s*=\\s*[\\\"']([^\\\"']+)[\\\"']");
        if (empty(encoded)) throw new IOException(config.name + "章节解析失败：缺少阅读参数");
        String comicId = comicIdFromChapterUrl(url);
        String chapterId = chapterIdFromChapterUrl(url);
        List<String> images = decryptImages(encoded, comicId, chapterId);
        String title = clean(first(html, "<title[^>]*>([\\s\\S]*?)</title>"));
        if (title.contains(" - ")) title = title.substring(0, title.indexOf(" - ")).trim();
        if (empty(title)) title = chapterId;
        return new ComicModels.ChapterPage(chapterId, title, images, "");
    }

    @Override
    public boolean healthCheck() {
        try {
            String html = fetch(categoryPath(null, 1), false);
            return html.contains("cy_list_mh") && html.contains("cy_tag");
        } catch (IOException ignored) {
            return false;
        }
    }

    static List<ComicModels.ComicSummary> parseCards(String html) {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher listMatcher = LIST_PATTERN.matcher(value(html));
        while (listMatcher.find()) {
            Matcher cards = UL_PATTERN.matcher(listMatcher.group(1));
            while (cards.find()) {
                String card = cards.group(1);
                String picture = firstRaw(card, "<a[^>]*class=[\\\"'][^\\\"']*\\bpic\\b[^\\\"']*[\\\"'][^>]*>");
                String rawId = rawComicIdStatic(attr(picture, "href"));
                if (empty(rawId) || !seen.add(rawId)) continue;
                String image = firstRaw(card, "<img[^>]*>");
                String titleBlock = first(card, "<li[^>]*class=[\\\"'][^\\\"']*\\btitle\\b[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</li>");
                String title = clean(first(titleBlock, "<a[^>]*>([\\s\\S]*?)</a>"));
                if (empty(title)) title = clean(attr(image, "alt")).replaceAll("漫画$", "");
                if (empty(title)) continue;
                String status = clean(first(card, "<li[^>]*class=[\\\"'][^\\\"']*\\bzuozhe\\b[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</li>"));
                status = status.replaceFirst("^状态[：:]\\s*", "");
                String latest = clean(first(card, "<li[^>]*class=[\\\"'][^\\\"']*\\bupdata\\b[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</li>"));
                String description = clean(first(card, "<li[^>]*class=[\\\"'][^\\\"']*\\binfo\\b[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</li>"));
                List<String> tags = linkTexts(first(card, "<li[^>]*class=[\\\"'][^\\\"']*\\bbiaoqian\\b[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</li>"));
                String subtitle = empty(status) ? latest : status;
                if (!empty(description) && empty(subtitle)) subtitle = description;
                result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title,
                        absoluteDefault(imageUrl(image)), subtitle, tags));
            }
        }
        return result;
    }

    static List<ComicModels.FilterGroup> parseFilterGroups(String html) {
        List<ComicModels.FilterGroup> result = new ArrayList<>();
        Matcher blocks = FILTER_PATTERN.matcher(value(html));
        while (blocks.find()) {
            String block = blocks.group(1);
            String originalLabel = clean(first(block, "<span[^>]*>([\\s\\S]*?)</span>"));
            String key = filterKey(originalLabel);
            if (empty(key) || "资费".equals(originalLabel)) continue;
            LinkedHashMap<String, String> options = new LinkedHashMap<>();
            options.put("全部", "all");
            Matcher links = LINK_PATTERN.matcher(block);
            while (links.find()) {
                String label = clean(links.group(2));
                String path = filterPath(links.group(1));
                if (empty(label) || "全部".equals(label) || empty(path) || options.containsKey(label)) continue;
                options.put(label, path);
            }
            List<ComicModels.FilterOption> parsed = new ArrayList<>();
            for (Map.Entry<String, String> option : options.entrySet()) {
                parsed.add(new ComicModels.FilterOption(option.getKey(), option.getValue()));
            }
            result.add(new ComicModels.FilterGroup(key, displayFilterLabel(originalLabel), parsed));
        }
        return result;
    }

    static List<ComicModels.Chapter> parseChapters(String html, String comicId) {
        List<ComicModels.Chapter> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        // Only cy_plist/cy_kan are chapter sources; rd-guess__comic is recommendation content.
        String catalog = elementContentByClass(html, "cy_plist");
        int slot = 0;
        if (!empty(catalog)) {
            Matcher matcher = CHAPTER_PATTERN.matcher(catalog);
            while (matcher.find()) {
                String href = decode(matcher.group(1));
                String url = absoluteDefault(href);
                if (!href.matches("(?i)/" + Pattern.quote(comicId) + "/[^/]+\\.html(?:[?#].*)?")) continue;
                if (!seen.add(url)) continue;
                String title = clean(matcher.group(2));
                if (empty(title)) continue;
                result.add(new ComicModels.Chapter(chapterIdFromChapterUrl(url), title, url, 0, slot++));
            }
        }
        if (!result.isEmpty()) return result;
        String online = first(elementContentByClass(html, "cy_kan"), "<a[^>]*href=[\\\"']([^\\\"']+)[\\\"'][^>]*>");
        if (!empty(online) && online.matches("(?i)/" + Pattern.quote(comicId) + "/[^/]+\\.html(?:[?#].*)?")) {
            String url = absoluteDefault(online);
            result.add(new ComicModels.Chapter(chapterIdFromChapterUrl(url), "在线阅读", url, 0, 0));
        }
        return result;
    }

    static List<String> decryptImages(String encoded, String expectedComicId, String expectedChapterId) throws IOException {
        final byte[] payload;
        try {
            payload = Base64.decode(decode(encoded), Base64.DEFAULT);
        } catch (IllegalArgumentException error) {
            throw new IOException("六漫画章节解析失败：阅读参数格式错误", error);
        }
        return decryptPayload(payload, expectedComicId, expectedChapterId);
    }

    static List<String> decryptPayload(byte[] payload, String expectedComicId, String expectedChapterId) throws IOException {
        if (payload.length <= 16) throw new IOException("六漫画章节解析失败：阅读参数过短");
        try {
            Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
            cipher.init(Cipher.DECRYPT_MODE,
                    new SecretKeySpec(AES_KEY.getBytes(StandardCharsets.UTF_8), "AES"),
                    new IvParameterSpec(Arrays.copyOfRange(payload, 0, 16)));
            JSONObject json = new JSONObject(new String(cipher.doFinal(Arrays.copyOfRange(payload, 16, payload.length)), StandardCharsets.UTF_8));
            if (json.optInt("comic_down", 0) != 0) throw new IOException("六漫画章节已被站点限制");
            if (json.optInt("source_id", 6) != 6) throw new IOException("六漫画章节来源不匹配");
            String host = json.optString("host", "");
            if (!empty(host) && !host.contains("liumanhua.com")) throw new IOException("六漫画章节域名不匹配");
            validateJsonId(json, "comic_id", expectedComicId, "漫画");
            validateJsonId(json, "comicId", expectedComicId, "漫画");
            validateJsonId(json, "chapter_id", expectedChapterId, "章节");
            validateJsonId(json, "chapterId", expectedChapterId, "章节");
            JSONArray array = json.optJSONArray("images");
            if (array == null || array.length() == 0) throw new IOException("六漫画章节解析失败：缺少正文图片");
            List<String> images = new ArrayList<>();
            Set<String> seen = new LinkedHashSet<>();
            for (int i = 0; i < array.length(); i++) {
                String image = cleanUrl(array.optString(i));
                if (!image.startsWith("http://") && !image.startsWith("https://")) {
                    throw new IOException("六漫画章节解析失败：图片地址无效");
                }
                if (seen.add(image)) images.add(image);
            }
            if (images.isEmpty()) throw new IOException("六漫画章节解析失败：正文图片为空");
            return images;
        } catch (GeneralSecurityException | JSONException error) {
            throw new IOException("六漫画章节解析失败：无法解密阅读参数", error);
        }
    }

    private ComicModels.ComicDetail parseDetail(String rawId, String html) throws IOException {
        String title = clean(first(html, "<div[^>]*class=[\\\"'][^\\\"']*\\bcy_title\\b[^\\\"']*[\\\"'][^>]*>[\\s\\S]*?<h1[^>]*>([\\s\\S]*?)</h1>"));
        if (empty(title)) title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        if (empty(title)) throw new IOException(config.name + "详情解析失败：缺少标题");
        String coverBlock = first(html, "<[^>]*class=[\\\"'][^\\\"']*\\bcy_info_cover\\b[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</(?:div|a)>" );
        String cover = absoluteDefault(imageUrl(firstRaw(coverBlock, "<img[^>]*>")));
        String author = labelledText(html, "作者");
        String status = labelledText(html, "状态");
        String latest = labelledText(html, "最新");
        String description = clean(first(html, "<[^>]*id=[\\\"']comic-description[\\\"'][^>]*>([\\s\\S]*?)</(?:p|div)>"));
        List<String> tags = linkTexts(first(html, "<[^>]*class=[\\\"'][^\\\"']*\\bcy_type\\b[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</(?:span|div)>"));
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, author, tags);
        return new ComicModels.ComicDetail(summary, author, status, description, latest, new ArrayList<ComicModels.Chapter>());
    }

    private String categoryPath(Map<String, String> filters, int page) {
        String selected = "";
        if (filters != null) {
            for (String key : FILTER_KEYS) {
                String value = filters.get(key);
                if (!empty(value) && !"all".equals(value)) {
                    selected = value;
                    break;
                }
            }
        }
        String path = "/category" + (selected.startsWith("/") ? selected : selected.isEmpty() ? "" : "/" + selected);
        if (page > 1) path += "/page/" + page;
        return absolute(path);
    }

    private String fetch(String url, boolean chapter) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(chapter ? 30000 : 20000);
        connection.setRequestProperty("User-Agent", USER_AGENT);
        connection.setRequestProperty("Referer", config.referer);
        connection.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8");
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
        connection.setRequestProperty("Accept-Encoding", "gzip");
        try {
            int code = connection.getResponseCode();
            if (code < 200 || code >= 300) throw new IOException(config.name + " HTTP " + code + ": " + url);
            try (InputStream raw = connection.getInputStream(); InputStream stream = isGzip(connection) ? new java.util.zip.GZIPInputStream(raw) : raw) {
                return new String(readAllBytes(stream), StandardCharsets.UTF_8);
            }
        } finally {
            connection.disconnect();
        }
    }

    private boolean isGzip(HttpURLConnection connection) {
        return "gzip".equalsIgnoreCase(connection.getContentEncoding());
    }

    private byte[] readAllBytes(InputStream stream) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = stream.read(buffer)) != -1) output.write(buffer, 0, read);
        return output.toByteArray();
    }

    private String absolute(String value) {
        if (empty(value)) return "";
        String url = decode(value).trim();
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        return config.baseUrl + (url.startsWith("/") ? url : "/" + url);
    }

    private static String absoluteDefault(String value) {
        if (empty(value)) return "";
        String url = decode(value).trim();
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        return DEFAULT_BASE_URL + (url.startsWith("/") ? url : "/" + url);
    }

    private String rawComicId(String value) {
        return rawComicIdStatic(value != null && value.startsWith(PREFIX) ? value.substring(PREFIX.length()) : value);
    }

    private static String rawComicIdStatic(String value) {
        if (empty(value)) return "";
        String input = decode(value).trim();
        int query = input.indexOf('?');
        if (query >= 0) input = input.substring(0, query);
        while (input.endsWith("/")) input = input.substring(0, input.length() - 1);
        int slash = input.lastIndexOf('/');
        return slash >= 0 ? input.substring(slash + 1) : input;
    }

    private static String comicIdFromChapterUrl(String value) {
        Matcher matcher = Pattern.compile("/([^/]+)/[^/]+\\.html(?:[?#].*)?$").matcher(value == null ? "" : value);
        return matcher.find() ? matcher.group(1) : "";
    }

    private static String chapterIdFromChapterUrl(String value) {
        Matcher matcher = Pattern.compile("/([^/]+)\\.html(?:[?#].*)?$").matcher(value == null ? "" : value);
        return matcher.find() ? matcher.group(1) : value == null ? "" : value;
    }

    private static String filterPath(String href) {
        String value = decode(href).trim();
        if (value.startsWith("https://www.liumanhua.com")) value = value.substring("https://www.liumanhua.com".length());
        if (value.startsWith("http://www.liumanhua.com")) value = value.substring("http://www.liumanhua.com".length());
        if (value.startsWith("/category")) value = value.substring("/category".length());
        int query = value.indexOf('?');
        if (query >= 0) value = value.substring(0, query);
        value = value.replaceAll("/+$", "");
        return value.isEmpty() || "/".equals(value) ? "all" : value;
    }

    private static String filterKey(String label) {
        if ("分类".equals(label)) return "classification";
        if ("题材".equals(label) || "标签".equals(label)) return "subject";
        if ("类型".equals(label)) return "type";
        if ("品质".equals(label)) return "quality";
        if ("地区".equals(label)) return "region";
        if ("版权".equals(label)) return "copyright";
        if ("进度".equals(label)) return "state";
        return "";
    }

    private static String displayFilterLabel(String label) {
        return "标签".equals(label) ? "题材" : "进度".equals(label) ? "状态" : label;
    }

    private static String labelledText(String html, String label) {
        String value = clean(first(html, "(?:<span|<p|<li)[^>]*>([\\s\\S]*?" + Pattern.quote(label) + "[：:][\\s\\S]*?)</(?:span|p|li)>"));
        return value.replaceFirst("^.*?" + Pattern.quote(label) + "[：:]\\s*", "").trim();
    }

    private static void validateJsonId(JSONObject json, String key, String expected, String label) throws IOException {
        if (empty(expected) || !json.has(key)) return;
        String actual = json.optString(key, "");
        if (!empty(actual) && !expected.equals(actual)) throw new IOException("六漫画章节" + label + " ID 不匹配");
    }

    private static List<String> linkTexts(String html) {
        List<String> result = new ArrayList<>();
        Matcher matcher = LINK_PATTERN.matcher(value(html));
        while (matcher.find()) {
            String text = clean(matcher.group(2));
            if (!empty(text) && !result.contains(text)) result.add(text);
        }
        return result;
    }

    private static String elementContentByClass(String html, String className) {
        Matcher open = Pattern.compile("<([a-z0-9]+)[^>]*class=[\\\"'][^\\\"']*\\b" + Pattern.quote(className) + "\\b[^\\\"']*[\\\"'][^>]*>", Pattern.CASE_INSENSITIVE).matcher(value(html));
        if (!open.find()) return "";
        String tag = open.group(1);
        Pattern tags = Pattern.compile("</?" + Pattern.quote(tag) + "\\b[^>]*>", Pattern.CASE_INSENSITIVE);
        Matcher matcher = tags.matcher(html);
        matcher.region(open.end(), html.length());
        int depth = 1;
        while (matcher.find()) {
            String token = matcher.group();
            if (token.startsWith("</")) depth--;
            else if (!token.endsWith("/>") && !token.matches("(?i)<(?:img|input|br|hr|meta|link)\\b[^>]*>")) depth++;
            if (depth == 0) return html.substring(open.end(), matcher.start());
        }
        return html.substring(open.end());
    }

    private static String imageUrl(String tag) {
        String url = attr(tag, "data-original");
        if (empty(url)) url = attr(tag, "data-src");
        if (empty(url)) url = attr(tag, "src");
        return url;
    }

    private static String attr(String tag, String name) {
        return first(tag, "\\b" + Pattern.quote(name) + "=[\\\"']([^\\\"']*)[\\\"']");
    }

    private static String first(String html, String regex) {
        Matcher matcher = Pattern.compile(regex, Pattern.CASE_INSENSITIVE).matcher(value(html));
        return matcher.find() ? matcher.group(1) : "";
    }

    private static String firstRaw(String html, String regex) {
        Matcher matcher = Pattern.compile(regex, Pattern.CASE_INSENSITIVE).matcher(value(html));
        return matcher.find() ? matcher.group() : "";
    }

    private static String clean(String value) {
        return decode(value).replaceAll("<[^>]+>", " ").replaceAll("\\s+", " ").trim();
    }

    private static String cleanUrl(String value) {
        return decode(value).replace("\\/", "/").trim();
    }

    private static String decode(String value) {
        return value(value).replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'")
                .replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">");
    }

    private static boolean empty(String value) {
        return value == null || value.trim().isEmpty();
    }

    private static String value(String value) {
        return value == null ? "" : value;
    }
}
