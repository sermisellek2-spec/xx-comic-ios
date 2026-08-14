package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class FiveUmComicSource implements ComicSource {
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern CARD_PATTERN = Pattern.compile(
            "<div[^>]*class=[\"'][^\"']*\\bcomic-item\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CATEGORY_SECTION_PATTERN = Pattern.compile(
            "<div[^>]*class=[\"'][^\"']*\\bfilter-section\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)(?=<div[^>]*class=[\"'][^\"']*\\bfilter-section\\b|<div[^>]*class=[\"'][^\"']*\\bcomic-list\\b|$)",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CATEGORY_LINK_PATTERN = Pattern.compile(
            "<a[^>]+href=[\"']([^\"']*/category/tags/\\d+)/?[\"'][^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<a[^>]+href=[\"']([^\"']*/chapter_(\\d+)_(\\d+)\\.html)[\"'][^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern IMAGE_PATTERN = Pattern.compile("<img[^>]*>", Pattern.CASE_INSENSITIVE);

    private final SourceConfig config;
    private final String prefix;
    private volatile Map<String, String> categoryPaths = Collections.emptyMap();

    public FiveUmComicSource() {
        this(SourceConfig.manhuazhan(true));
    }

    public FiveUmComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.manhuazhan(true) : config;
        this.prefix = this.config.id + ":";
    }

    @Override public String id() { return config.id; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return category("all", "all", page);
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        if (page > 1) return new ArrayList<>();
        String encoded = URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        return parseCards(fetch(absolute(config.route("search").replace("{keyword}", encoded))));
    }

    @Override
    public List<String> categories() throws IOException {
        Map<String, String> parsed = parseCategoryPaths(fetch(absolute(config.route("categoryIndex"))));
        if (parsed.isEmpty()) throw new IOException(config.name + " 分类解析失败：缺少漫画类型标签");
        categoryPaths = Collections.unmodifiableMap(parsed);
        return new ArrayList<>(parsed.keySet());
    }

    @Override
    public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        Map<String, String> parsed = parseCategoryPaths(fetch(absolute(config.route("categoryIndex"))));
        if (parsed.isEmpty()) throw new IOException(config.name + " 分类解析失败：缺少漫画类型标签");
        categoryPaths = Collections.unmodifiableMap(parsed);
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        groups.add(SourceFilters.group("category", "题材", parsed));
        groups.add(SourceFilters.group("state", "状态",
                "全部", "all", "连载中", "1", "已完结", "2"));
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        String root = categoryPath(region);
        if (page > 1) root += "/page/" + page;
        return parseCards(fetch(absolute(root)));
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        String root = SourceFilters.value(filters, "category", "all");
        if ("all".equals(root)) root = "/category";
        String state = SourceFilters.value(filters, "state", "all");
        if (!"all".equals(state)) root += "/finish/" + state;
        if (page > 1) root += "/page/" + page;
        return parseCards(fetch(absolute(root)));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(detailUrl(rawId));
        String title = stripBookTitle(clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>")));
        if (TextUtils.isEmpty(title)) throw new IOException(config.name + " 详情解析失败：缺少标题");

        String mainInfo = firstRaw(html, "<div[^>]*class=[\"'][^\"']*\\bcomic-main-info\\b[^\"']*[\"'][^>]*>[\\s\\S]*?(?=<div[^>]*class=[\"'][^\"']*\\bcomic-description\\b|$)");
        String coverBlock = firstRaw(html, "<div[^>]*class=[\"'][^\"']*\\bcomic-cover-large\\b[^\"']*[\"'][^>]*>[\\s\\S]*?</div>");
        String cover = imageUrlFromTag(firstRaw(coverBlock, "<img[^>]*>"));
        if (TextUtils.isEmpty(cover)) {
            cover = attr(firstRaw(html, "<meta[^>]+(?:property|name)=[\"']og:image[\"'][^>]*>"), "content");
        }
        String author = clean(first(mainInfo, "作者[：:]\\s*([^<]*?)</span>"));
        if (TextUtils.isEmpty(author)) author = clean(first(mainInfo, "由\\s*([^，。<]+?)\\s*创作"));
        String description = clean(first(html, "<div[^>]*class=[\"'][^\"']*\\bcomic-description\\b[^\"']*[\"'][^>]*>[\\s\\S]*?<p[^>]*>([\\s\\S]*?)</p>"));
        List<String> tags = parseTags(mainInfo);
        String status = statusFromTags(tags);
        List<ComicModels.Chapter> parsedChapters = parseChapters(html);
        String latest = parsedChapters.isEmpty() ? "" : parsedChapters.get(parsedChapters.size() - 1).title;
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(
                config.id, prefix + rawId, title, absolute(cover), author, tags);
        return new ComicModels.ComicDetail(summary, author, status, description, latest, new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        return parseChapters(fetch(detailUrl(rawId)));
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = absolute(chapterUrl);
        String html = fetch(url);
        String content = first(html, "<div[^>]*class=[\"'][^\"']*\\bcomic-content\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>");
        List<String> images = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = IMAGE_PATTERN.matcher(content);
        while (matcher.find()) {
            String tag = matcher.group();
            if (!hasClass(tag, "comic-image")) continue;
            String image = absolute(imageUrlFromTag(tag));
            if (!TextUtils.isEmpty(image) && seen.add(image)) images.add(image);
        }
        if (images.isEmpty()) throw new IOException(config.name + " 章节解析失败：缺少正文图片");
        String title = stripBookTitle(clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>")));
        return new ComicModels.ChapterPage(url, title, images, "");
    }

    @Override
    public boolean healthCheck() {
        try {
            String html = fetch(absolute(config.route("categoryIndex")));
            return html.contains("comic-list") || html.contains("filter-section");
        } catch (IOException ignored) {
            return false;
        }
    }

    private List<ComicModels.ComicSummary> parseCards(String html) {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CARD_PATTERN.matcher(html == null ? "" : html);
        while (matcher.find()) {
            String card = matcher.group(1);
            String href = decode(first(card, "<a[^>]+href=[\"']([^\"']*/comic_[^\"']+\\.html)[\"'][^>]*>"));
            String rawId = rawComicId(href);
            String url = absolute(href);
            if (TextUtils.isEmpty(rawId) || !seen.add(url)) continue;
            String imageTag = firstRaw(card, "<img[^>]*>");
            String title = clean(attr(imageTag, "alt"));
            if (TextUtils.isEmpty(title)) title = clean(attr(card, "title"));
            if (TextUtils.isEmpty(title)) continue;
            String author = clean(first(card, "<p[^>]*class=[\"'][^\"']*\\bcomic-author\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</p>"));
            result.add(new ComicModels.ComicSummary(
                    config.id, prefix + rawId, title, absolute(imageUrlFromTag(imageTag)), author, new ArrayList<String>()));
        }
        return result;
    }

    private Map<String, String> parseCategoryPaths(String html) {
        LinkedHashMap<String, String> parsed = new LinkedHashMap<>();
        Matcher sections = CATEGORY_SECTION_PATTERN.matcher(html == null ? "" : html);
        while (sections.find()) {
            String section = sections.group(1);
            if (!clean(section).contains("漫画类型")) continue;
            Matcher links = CATEGORY_LINK_PATTERN.matcher(section);
            while (links.find()) {
                String name = clean(links.group(2));
                String path = decode(links.group(1)).replaceAll("/+$", "");
                if (!TextUtils.isEmpty(name) && !parsed.containsKey(name)) parsed.put(name, path);
            }
            break;
        }
        return parsed;
    }

    private List<ComicModels.Chapter> parseChapters(String html) {
        List<ComicModels.Chapter> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CHAPTER_PATTERN.matcher(html == null ? "" : html);
        int slot = 0;
        while (matcher.find()) {
            String url = absolute(decode(matcher.group(1)));
            String title = clean(matcher.group(4));
            if (TextUtils.isEmpty(title) || !seen.add(url)) continue;
            result.add(new ComicModels.Chapter(matcher.group(3), title, url, 0, slot++));
        }
        return result;
    }

    private List<String> parseTags(String html) {
        List<String> tags = new ArrayList<>();
        String block = firstRaw(html, "<div[^>]*class=[\"'][^\"']*\\bcomic-tags\\b[^\"']*[\"'][^>]*>[\\s\\S]*?</div>");
        Matcher matcher = Pattern.compile("<span[^>]*class=[\"'][^\"']*\\btag\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</span>", Pattern.CASE_INSENSITIVE).matcher(block);
        while (matcher.find()) {
            String tag = clean(matcher.group(1));
            if (!TextUtils.isEmpty(tag) && !tags.contains(tag)) tags.add(tag);
        }
        return tags;
    }

    private String statusFromTags(List<String> tags) {
        for (String tag : tags) {
            if (tag.contains("完结") || tag.contains("完成")) return "已完结";
            if (tag.contains("连载")) return "连载中";
        }
        return "";
    }

    private String categoryPath(String region) throws IOException {
        if (TextUtils.isEmpty(region) || "all".equals(region) || "全部".equals(region)) return "/category";
        String path = categoryPaths.get(region);
        if (TextUtils.isEmpty(path)) {
            categories();
            path = categoryPaths.get(region);
        }
        if (TextUtils.isEmpty(path)) throw new IOException(config.name + " 分类不存在：" + region);
        return path;
    }

    private String detailUrl(String rawId) {
        return absolute(config.route("detail").replace("{comicId}", rawId));
    }

    private String rawComicId(String value) {
        if (value == null) return "";
        if (value.startsWith(prefix)) value = value.substring(prefix.length());
        Matcher matcher = Pattern.compile("(?:^|/)comic_([^/\"'?]+)\\.html", Pattern.CASE_INSENSITIVE).matcher(value);
        if (matcher.find()) return matcher.group(1);
        return value.replaceAll("^comic_|\\.html$", "").trim();
    }

    private String fetch(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(20000);
        connection.setRequestProperty("User-Agent", UA);
        connection.setRequestProperty("Referer", config.referer);
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
        try {
            int code = connection.getResponseCode();
            if (code < 200 || code >= 400) throw new IOException(config.name + " HTTP " + code + ": " + url);
            try (InputStream stream = connection.getInputStream()) {
                return new String(readAllBytes(stream), "UTF-8");
            }
        } finally {
            connection.disconnect();
        }
    }

    private byte[] readAllBytes(InputStream stream) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = stream.read(buffer)) != -1) out.write(buffer, 0, read);
        return out.toByteArray();
    }

    private String first(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group(1) : "";
    }

    private String firstRaw(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group() : "";
    }

    private String attr(String html, String name) {
        Matcher matcher = Pattern.compile("\\b" + Pattern.quote(name) + "=[\"']([^\"']*)[\"']", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? decode(matcher.group(1)) : "";
    }

    private boolean hasClass(String tag, String className) {
        return (" " + attr(tag, "class") + " ").contains(" " + className + " ");
    }

    private String imageUrlFromTag(String tag) {
        String url = attr(tag, "data-src");
        if (TextUtils.isEmpty(url)) url = attr(tag, "data-original");
        if (TextUtils.isEmpty(url)) url = attr(tag, "src");
        return url.replace("\\/", "/").trim();
    }

    private String absolute(String value) {
        if (TextUtils.isEmpty(value)) return "";
        String url = decode(value).trim();
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        return config.baseUrl + (url.startsWith("/") ? url : "/" + url);
    }

    private String stripBookTitle(String value) {
        if (value.startsWith("《") && value.endsWith("》") && value.length() > 2) {
            return value.substring(1, value.length() - 1).trim();
        }
        return value;
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
}
