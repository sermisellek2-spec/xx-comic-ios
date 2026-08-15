package com.xxcomic.source;

import android.util.Base64;

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

public class CuimhComicSource implements ComicSource {
    private static final String SOURCE_ID = "cuimh";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String DEFAULT_BASE_URL = "https://www.cuimh.com";
    private static final String IMAGE_BASE_URL = "https://img1.baipiaoguai.org";
    private static final String AES_KEY = "9S8$vJnU2ANeSRoF";
    private static final String USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final long CATEGORY_CACHE_TTL_MS = 5 * 60 * 1000L;
    private static final long MIN_REQUEST_INTERVAL_MS = 1000L;
    private static final long FORBIDDEN_COOLDOWN_MS = 30 * 60 * 1000L;
    private static final int CATEGORY_CACHE_LIMIT = 8;
    private static final Pattern LIST_PATTERN = Pattern.compile(
            "<div[^>]*class=[\"'][^\"']*\\bcy_list_mh\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern LIST_ITEM_PATTERN = Pattern.compile("<ul[^>]*>([\\s\\S]*?)</ul>", Pattern.CASE_INSENSITIVE);
    private static final Pattern FILTER_PATTERN = Pattern.compile(
            "<div[^>]*class=[\"'][^\"']*\\bcy_tag\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern LINK_PATTERN = Pattern.compile(
            "<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<li[^>]*class=[\"'][^\"']*\\bchapter__item\\b[^\"']*[\"'][^>]*>[\\s\\S]*?<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>[\\s\\S]*?</li>",
            Pattern.CASE_INSENSITIVE);
    private static final String[] FILTER_ORDER = {
            "classification", "subject", "type", "quality", "region", "copyright", "state"
    };
    private static final String[] FILTER_PREFIXES = {
            "/list/", "/tags/", "/theme/", "/quality/", "/city/", "/copyright/", "/finish/"
    };

    private final SourceConfig config;
    private final Map<String, CachedDocument> categoryDocuments = new LinkedHashMap<String, CachedDocument>(
            CATEGORY_CACHE_LIMIT, 0.75f, true) {
        @Override
        protected boolean removeEldestEntry(Map.Entry<String, CachedDocument> eldest) {
            return size() > CATEGORY_CACHE_LIMIT;
        }
    };
    private long lastRequestStartedAtMs;
    private long forbiddenUntilMs;

    public CuimhComicSource() {
        this(SourceConfig.cuimh(true));
    }

    public CuimhComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.cuimh(true) : config;
    }

    @Override public String id() { return config.id; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }
    @Override public boolean supportsSearch() { return false; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return parseCards(fetchCategoryDocument(buildCategoryPath(null, page)));
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        throw new IOException(config.name + "暂不支持搜索");
    }

    @Override
    public List<String> categories() throws IOException {
        List<ComicModels.FilterGroup> groups = filterGroups();
        List<String> result = new ArrayList<>();
        if (groups.isEmpty()) return result;
        for (ComicModels.FilterOption option : groups.get(0).options) {
            if (!"all".equals(option.value)) result.add(option.label);
        }
        return result;
    }

    @Override
    public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        List<ComicModels.FilterGroup> groups = parseFilterGroups(fetchCategoryDocument("/category/"));
        if (groups.isEmpty()) throw new IOException(config.name + "分类解析失败");
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        return parseCards(fetchCategoryDocument(buildCategoryPath(null, page)));
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        return parseCards(fetchCategoryDocument(buildCategoryPath(filters, page)));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        ComicModels.ComicDetail detail = parseDetail(rawId, html);
        return new ComicModels.ComicDetail(detail.summary, detail.author, detail.status,
                detail.description, detail.latestChapter, parseChapters(html));
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        List<ComicModels.Chapter> chapters = parseChapters(fetch(absolute(config.route("detail").replace("{comicId}", rawId))));
        if (chapters.isEmpty()) throw new IOException(config.name + "目录解析失败");
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = absolute(chapterUrl);
        String html = fetch(url);
        String encoded = first(html, "\\bparams\\s*=\\s*[\"']([^\"']+)[\"']");
        if (empty(encoded)) throw new IOException(config.name + "章节解析失败：缺少阅读参数");
        List<String> images;
        try {
            images = decryptPayload(Base64.decode(encoded, Base64.DEFAULT));
        } catch (IllegalArgumentException error) {
            throw new IOException(config.name + "章节解析失败：阅读参数格式错误", error);
        }
        String title = clean(first(html, "<title[^>]*>([\\s\\S]*?)</title>"));
        int suffix = title.indexOf("-下拉式");
        if (suffix > 0) title = title.substring(0, suffix).trim();
        return new ComicModels.ChapterPage(url, title, images, "");
    }

    @Override
    public boolean healthCheck() {
        try {
            String html = fetch(absolute("/category/"));
            return html.contains("cy_list_mh") && html.contains("cy_tag");
        } catch (IOException ignored) {
            return false;
        }
    }

    static List<ComicModels.ComicSummary> parseCards(String html) {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher list = LIST_PATTERN.matcher(value(html));
        if (!list.find()) return result;
        Matcher items = LIST_ITEM_PATTERN.matcher(list.group(1));
        while (items.find()) {
            String card = items.group(1);
            String pictureLink = firstRaw(card, "<a[^>]*class=[\"'][^\"']*\\bpic\\b[^\"']*[\"'][^>]*>");
            String href = attr(pictureLink, "href");
            String rawId = rawComicIdStatic(href);
            if (empty(rawId) || !seen.add(rawId)) continue;
            String image = firstRaw(card, "<img[^>]*>");
            String titleBlock = first(card, "<li[^>]*class=[\"'][^\"']*\\btitle\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</li>");
            String title = clean(first(titleBlock, "<a[^>]*>([\\s\\S]*?)</a>"));
            if (empty(title)) title = clean(attr(image, "alt")).replaceAll("漫画$", "");
            if (empty(title)) continue;
            String status = clean(first(card, "<li[^>]*class=[\"'][^\"']*\\bzuozhe\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</li>"));
            status = status.replaceFirst("^状态[：:]\\s*", "");
            List<String> tags = linkTexts(first(card,
                    "<li[^>]*class=[\"'][^\"']*\\bbiaoqian\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</li>"));
            result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title,
                    absoluteDefault(imageUrl(image)), status, tags));
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
            if (empty(key)) continue;
            String label = "标签".equals(originalLabel) ? "题材" : "进度".equals(originalLabel) ? "状态" : originalLabel;
            LinkedHashMap<String, String> options = new LinkedHashMap<>();
            options.put("全部", "all");
            Matcher links = LINK_PATTERN.matcher(block);
            while (links.find()) {
                String option = clean(links.group(2));
                String path = categorySegment(decode(links.group(1)));
                if (empty(option) || "全部".equals(option) || "all".equals(path) || options.containsKey(option)) continue;
                options.put(option, path);
            }
            List<ComicModels.FilterOption> parsed = new ArrayList<>();
            for (Map.Entry<String, String> option : options.entrySet()) {
                parsed.add(new ComicModels.FilterOption(option.getKey(), option.getValue()));
            }
            result.add(new ComicModels.FilterGroup(key, label, parsed));
        }
        return result;
    }

    static String buildCategoryPath(Map<String, String> filters, int page) {
        StringBuilder path = new StringBuilder("/category");
        for (int i = 0; i < FILTER_ORDER.length; i++) {
            String selected = filters == null ? null : filters.get(FILTER_ORDER[i]);
            if (selected != null && selected.startsWith(FILTER_PREFIXES[i])) path.append(selected);
        }
        if (page > 1) path.append("/page/").append(page);
        return path.toString();
    }

    static ComicModels.ComicDetail parseDetail(String rawId, String html) throws IOException {
        String title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        if (empty(title)) throw new IOException("催漫画详情解析失败：缺少标题");
        String coverBlock = first(html,
                "<div[^>]*class=[\"'][^\"']*\\bcy_info_cover\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>");
        String cover = absoluteDefault(imageUrl(firstRaw(coverBlock, "<img[^>]*>")));
        String author = labelledText(html, "cy_author", "作者");
        String status = labelledText(html, "cy_serialize", "状态");
        String latest = labelledText(html, "cy_newpic", "最新话");
        String description = clean(first(html,
                "<p[^>]*id=[\"']comic-description[\"'][^>]*>([\\s\\S]*?)</p>"));
        List<String> tags = linkTexts(first(html,
                "<span[^>]*class=[\"'][^\"']*\\bcy_type\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</span>"));
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(
                SOURCE_ID, PREFIX + rawComicIdStatic(rawId), title, cover, author, tags);
        return new ComicModels.ComicDetail(summary, author, status, description, latest,
                new ArrayList<ComicModels.Chapter>());
    }

    static List<ComicModels.Chapter> parseChapters(String html) {
        List<ComicModels.Chapter> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CHAPTER_PATTERN.matcher(value(html));
        int slot = 0;
        while (matcher.find()) {
            String href = decode(matcher.group(1));
            String url = absoluteDefault(href);
            if (!href.matches("(?i).*/?\\d+-\\d+\\.html(?:[?#].*)?") || !seen.add(url)) continue;
            String title = clean(matcher.group(2));
            if (empty(title)) continue;
            String chapterId = href.replaceFirst("^.*?/", "").replaceFirst("\\.html(?:[?#].*)?$", "");
            result.add(new ComicModels.Chapter(chapterId, title, url, 0, slot++));
        }
        return result;
    }

    static List<String> decryptPayload(byte[] payload) throws IOException {
        if (payload == null || payload.length <= 16) throw new IOException("催漫画章节解析失败：阅读参数过短");
        try {
            Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
            cipher.init(Cipher.DECRYPT_MODE,
                    new SecretKeySpec(AES_KEY.getBytes(StandardCharsets.UTF_8), "AES"),
                    new IvParameterSpec(Arrays.copyOfRange(payload, 0, 16)));
            String json = new String(cipher.doFinal(Arrays.copyOfRange(payload, 16, payload.length)), StandardCharsets.UTF_8);
            if (!"www.cuimh.com".equals(jsonString(json, "host"))) {
                throw new IOException("催漫画章节解析失败：阅读参数域名不匹配");
            }
            List<String> images = jsonStringArray(json, "images");
            if (images.isEmpty()) throw new IOException("催漫画章节解析失败：缺少正文图片");
            List<String> result = new ArrayList<>();
            Set<String> seen = new LinkedHashSet<>();
            for (String image : images) {
                String url = image.startsWith("/") ? IMAGE_BASE_URL + image : image;
                if (!empty(url) && seen.add(url)) result.add(url);
            }
            return result;
        } catch (GeneralSecurityException | IllegalArgumentException error) {
            throw new IOException("催漫画章节解析失败：无法解密阅读参数", error);
        }
    }

    private String fetchCategoryDocument(String path) throws IOException {
        String url = absolute(path);
        if (url.equals(absolute("/category"))) url = absolute("/category/");
        return fetch(url, true);
    }

    private String fetch(String url) throws IOException {
        return fetch(url, false);
    }

    private synchronized String fetch(String url, boolean cacheable) throws IOException {
        long now = System.currentTimeMillis();
        if (now < forbiddenUntilMs) {
            throw new IOException(config.name + "暂时访问受限，请稍后再试");
        }
        if (cacheable) {
            CachedDocument cached = categoryDocuments.get(url);
            if (cached != null && now - cached.savedAtMs < CATEGORY_CACHE_TTL_MS) return cached.html;
            categoryDocuments.remove(url);
        }
        long waitMs = MIN_REQUEST_INTERVAL_MS - (now - lastRequestStartedAtMs);
        if (waitMs > 0) {
            try {
                Thread.sleep(waitMs);
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                throw new IOException(config.name + "请求已取消", error);
            }
        }
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(30000);
        connection.setRequestProperty("User-Agent", USER_AGENT);
        connection.setRequestProperty("Referer", config.referer);
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
        try {
            lastRequestStartedAtMs = System.currentTimeMillis();
            int code = connection.getResponseCode();
            if (code == HttpURLConnection.HTTP_FORBIDDEN) {
                forbiddenUntilMs = System.currentTimeMillis() + FORBIDDEN_COOLDOWN_MS;
            }
            if (code < 200 || code >= 400) throw new IOException(config.name + " HTTP " + code + ": " + url);
            try (InputStream stream = connection.getInputStream()) {
                String html = new String(readAllBytes(stream), StandardCharsets.UTF_8);
                forbiddenUntilMs = 0L;
                if (cacheable) categoryDocuments.put(url, new CachedDocument(html, System.currentTimeMillis()));
                return html;
            }
        } finally {
            connection.disconnect();
        }
    }

    private static final class CachedDocument {
        final String html;
        final long savedAtMs;

        CachedDocument(String html, long savedAtMs) {
            this.html = html;
            this.savedAtMs = savedAtMs;
        }
    }

    private byte[] readAllBytes(InputStream stream) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = stream.read(buffer)) != -1) output.write(buffer, 0, read);
        return output.toByteArray();
    }

    private String absolute(String input) {
        if (empty(input)) return "";
        String url = decode(input).trim();
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        return config.baseUrl + (url.startsWith("/") ? url : "/" + url);
    }

    private String rawComicId(String input) {
        return rawComicIdStatic(input != null && input.startsWith(PREFIX) ? input.substring(PREFIX.length()) : input);
    }

    private static String rawComicIdStatic(String input) {
        String value = decode(input).trim();
        int query = value.indexOf('?');
        if (query >= 0) value = value.substring(0, query);
        while (value.endsWith("/")) value = value.substring(0, value.length() - 1);
        int slash = value.lastIndexOf('/');
        return slash >= 0 ? value.substring(slash + 1) : value;
    }

    private static String filterKey(String label) {
        if ("分类".equals(label)) return "classification";
        if ("标签".equals(label)) return "subject";
        if ("类型".equals(label)) return "type";
        if ("品质".equals(label)) return "quality";
        if ("地区".equals(label)) return "region";
        if ("版权".equals(label)) return "copyright";
        if ("进度".equals(label)) return "state";
        return "";
    }

    private static String categorySegment(String href) {
        int category = href.indexOf("/category");
        if (category < 0) return "all";
        String path = href.substring(category + "/category".length());
        int query = path.indexOf('?');
        if (query >= 0) path = path.substring(0, query);
        path = path.replaceAll("/+$", "");
        return empty(path) ? "all" : path;
    }

    private static String labelledText(String html, String className, String label) {
        String text = clean(first(html, "<span[^>]*class=[\"'][^\"']*\\b" + Pattern.quote(className)
                + "\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</span>"));
        return text.replaceFirst("^" + Pattern.quote(label) + "[：:]\\s*", "");
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

    private static String imageUrl(String tag) {
        String url = attr(tag, "data-original");
        if (empty(url)) url = attr(tag, "data-src");
        if (empty(url)) url = attr(tag, "src");
        return decode(url).replace("\\/", "/").trim();
    }

    private static String absoluteDefault(String input) {
        if (empty(input)) return "";
        String url = decode(input).trim();
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        return DEFAULT_BASE_URL + (url.startsWith("/") ? url : "/" + url);
    }

    private static String jsonString(String json, String key) throws IOException {
        Matcher matcher = Pattern.compile("[\"']" + Pattern.quote(key) + "[\"']\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"")
                .matcher(value(json));
        if (!matcher.find()) throw new IOException("催漫画章节解析失败：缺少 " + key);
        return unescapeJson(matcher.group(1));
    }

    private static List<String> jsonStringArray(String json, String key) throws IOException {
        Matcher array = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*\\[([\\s\\S]*?)]")
                .matcher(value(json));
        if (!array.find()) throw new IOException("催漫画章节解析失败：缺少 " + key);
        List<String> result = new ArrayList<>();
        Matcher values = Pattern.compile("\"((?:\\\\.|[^\"\\\\])*)\"").matcher(array.group(1));
        while (values.find()) result.add(unescapeJson(values.group(1)));
        return result;
    }

    private static String unescapeJson(String input) throws IOException {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < input.length(); i++) {
            char current = input.charAt(i);
            if (current != '\\' || i + 1 >= input.length()) {
                result.append(current);
                continue;
            }
            char escaped = input.charAt(++i);
            if (escaped == 'u' && i + 4 < input.length()) {
                try {
                    result.append((char) Integer.parseInt(input.substring(i + 1, i + 5), 16));
                    i += 4;
                } catch (NumberFormatException error) {
                    throw new IOException("催漫画章节解析失败：JSON 转义无效", error);
                }
            } else if (escaped == 'n') result.append('\n');
            else if (escaped == 'r') result.append('\r');
            else if (escaped == 't') result.append('\t');
            else if (escaped == 'b') result.append('\b');
            else if (escaped == 'f') result.append('\f');
            else result.append(escaped);
        }
        return result.toString();
    }

    private static String first(String html, String regex) {
        Matcher matcher = Pattern.compile(regex, Pattern.CASE_INSENSITIVE).matcher(value(html));
        return matcher.find() ? matcher.group(1) : "";
    }

    private static String firstRaw(String html, String regex) {
        Matcher matcher = Pattern.compile(regex, Pattern.CASE_INSENSITIVE).matcher(value(html));
        return matcher.find() ? matcher.group() : "";
    }

    private static String attr(String tag, String name) {
        Matcher matcher = Pattern.compile("\\b" + Pattern.quote(name) + "=[\"']([^\"']*)[\"']", Pattern.CASE_INSENSITIVE)
                .matcher(value(tag));
        return matcher.find() ? decode(matcher.group(1)) : "";
    }

    private static String clean(String input) {
        return decode(value(input).replaceAll("<[^>]+>", " ")).replaceAll("\\s+", " ").trim();
    }

    private static String decode(String input) {
        return value(input)
                .replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'")
                .replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">")
                .replace("&ldquo;", "“").replace("&rdquo;", "”").replace("&hellip;", "…");
    }

    private static boolean empty(String input) {
        return input == null || input.trim().isEmpty();
    }

    private static String value(String input) {
        return input == null ? "" : input;
    }
}
