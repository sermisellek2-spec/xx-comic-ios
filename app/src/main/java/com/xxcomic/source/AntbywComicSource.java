package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;

import org.json.JSONArray;
import org.json.JSONException;

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

public class AntbywComicSource implements ComicSource {
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern CARD_PATTERN = Pattern.compile(
            "<div[^>]*class=[\"'][^\"']*\\buk-card\\b[^\"']*\\buk-text-center\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)(?=<div[^>]*class=[\"'][^\"']*\\buk-card\\b[^\"']*\\buk-text-center\\b|$)",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<a[^>]+href=[\"']([^\"']*a=read[^\"']*kuid=(\\d+)[^\"']*zjid=(\\d+)[^\"']*)[\"'][^>]*class=[\"'][^\"']*\\bzj-container\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern URL_ARRAY_PATTERN = Pattern.compile(
            "(?:let|var|const)\\s+urls\\s*=\\s*(\\[[\\s\\S]*?\\])\\s*;",
            Pattern.CASE_INSENSITIVE);

    private final SourceConfig config;
    private final String prefix;
    private volatile Map<String, String> categoryIds = Collections.emptyMap();

    public AntbywComicSource() {
        this(SourceConfig.antbyw(true));
    }

    public AntbywComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.antbyw(true) : config;
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
        String html = fetch(absolute(config.route("categoryIndex")));
        String block = first(html, "<strong[^>]*>\\s*分类\\s*</strong>([\\s\\S]*?)(?=<div[^>]*class=[\"'][^\"']*\\bcl\\b|$)");
        LinkedHashMap<String, String> parsed = new LinkedHashMap<>();
        Matcher matcher = Pattern.compile(
                "<a[^>]+data-field=[\"']category_id[\"'][^>]+data-value=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>",
                Pattern.CASE_INSENSITIVE).matcher(block);
        while (matcher.find()) {
            String value = clean(matcher.group(1));
            String name = clean(matcher.group(2));
            if (!"empty".equals(value) && !TextUtils.isEmpty(name)) parsed.put(name, value);
        }
        if (parsed.isEmpty()) throw new IOException(config.name + " 分类解析失败");
        categoryIds = Collections.unmodifiableMap(parsed);
        return new ArrayList<>(parsed.keySet());
    }

    @Override
    public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        String html = fetch(absolute(config.route("categoryIndex")));
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        Matcher sections = Pattern.compile(
                "<strong[^>]*>([^<]+)</strong>([\\s\\S]*?)(?=<div[^>]*class=[\"'][^\"']*\\bcl\\b|</div>\\s*</div>)",
                Pattern.CASE_INSENSITIVE).matcher(html);
        while (sections.find()) {
            String siteLabel = clean(sections.group(1));
            String label = "分类".equals(siteLabel) ? "题材" : "首字母".equals(siteLabel) ? "字母" : siteLabel;
            String key = "分类".equals(siteLabel) ? "category_id"
                    : "进度".equals(siteLabel) ? "jindu"
                    : "地区".equals(siteLabel) ? "region"
                    : "首字母".equals(siteLabel) ? "letter"
                    : "年份".equals(siteLabel) ? "search_age"
                    : "受众".equals(siteLabel) ? "shouzhong" : "";
            if (TextUtils.isEmpty(key)) continue;
            List<ComicModels.FilterOption> options = new ArrayList<>();
            Matcher links = Pattern.compile("<a[^>]*data-field=[\"']" + Pattern.quote(key) + "[\"'][^>]*>[\\s\\S]*?</a>", Pattern.CASE_INSENSITIVE)
                    .matcher(sections.group(2));
            while (links.find()) {
                String tag = links.group();
                String optionLabel = clean(first(tag, ">([\\s\\S]*?)</a>"));
                String value = attr(tag, "data-value");
                if ("empty".equals(value)) value = "all";
                if (!TextUtils.isEmpty(optionLabel) && !TextUtils.isEmpty(value)) {
                    options.add(new ComicModels.FilterOption(optionLabel, value));
                }
            }
            if (!options.isEmpty()) groups.add(new ComicModels.FilterGroup(key, label, options));
        }
        groups.add(SourceFilters.group("sort", "排序",
                "上架时间", "addtime:asc", "更新时间", "edittime:desc",
                "阅读量", "views:desc", "收藏量", "favores:desc"));
        if (groups.size() == 1) throw new IOException(config.name + " 分类解析失败");
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        StringBuilder url = new StringBuilder(absolute(config.route("category")));
        String categoryId = categoryId(region);
        if (!TextUtils.isEmpty(categoryId)) url.append("&category_id=").append(categoryId);
        String orderField = "all".equals(state) || TextUtils.isEmpty(state) ? "addtime" : state;
        url.append("&odfie=").append(orderField).append("&order=desc&page=").append(Math.max(1, page));
        return parseCards(fetch(url.toString()));
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        StringBuilder url = new StringBuilder(absolute(config.route("category")));
        for (String key : new String[]{"category_id", "jindu", "region", "letter", "search_age", "shouzhong"}) {
            String value = SourceFilters.value(filters, key, "all");
            if (!"all".equals(value)) url.append('&').append(key).append('=').append(value);
        }
        String[] order = SourceFilters.value(filters, "sort", "addtime:asc").split(":", 2);
        url.append("&odfie=").append(order[0])
                .append("&order=").append(order.length > 1 ? order[1] : "desc")
                .append("&page=").append(Math.max(1, page));
        return parseCards(fetch(url.toString()));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(detailUrl(rawId));
        String info = first(html, "<!--\\s*作品信息 内容栏(?:\\s*开始)?\\s*-->([\\s\\S]*?)<!--\\s*作品信息 内容栏\\s*结束\\s*-->");
        String title = clean(first(info, "<h3[^>]*class=[\"'][^\"']*\\buk-heading-line\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</h3>"));
        if (TextUtils.isEmpty(title)) throw new IOException(config.name + " 详情解析失败：缺少标题");
        String cover = imageUrlFromTag(firstRaw(html, "<img[^>]+(?:mh_cover|/mh_cover/)[^>]*>"));
        String author = clean(first(info, "漫畫作者\\s*:\\s*([\\s\\S]*?)(?=</div>)"));
        String status = clean(first(info, "<a[^>]+(?:[?&]|&amp;)jindu=\\d+[^>]*>([\\s\\S]*?)</a>"));
        String description = clean(first(info, "<div[^>]*class=[\"'][^\"']*\\buk-alert\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>"));
        List<String> tags = parseTags(info);
        List<ComicModels.Chapter> parsedChapters = parseChapters(html);
        String latest = clean(first(info, "更新到\\s*:\\s*([^<]+)"));
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(
                config.id, prefix + rawId, title, absolute(cover), author, tags);
        return new ComicModels.ComicDetail(summary, author, status, description, latest, new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        List<ComicModels.Chapter> result = parseChapters(fetch(detailUrl(rawComicId(comicId))));
        if (result.isEmpty()) throw new IOException(config.name + " 目录解析失败");
        return result;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String baseUrl = withoutPage(absolute(chapterUrl));
        String firstHtml = fetch(pageUrl(baseUrl, 1));
        int pageCount = pageCount(firstHtml);
        List<String> images = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        addImages(firstHtml, images, seen);
        for (int page = 2; page <= pageCount; page++) addImages(fetch(pageUrl(baseUrl, page)), images, seen);
        if (images.isEmpty()) throw new IOException(config.name + " 章节解析失败：缺少正文图片");
        String title = clean(first(firstHtml, "<h3[^>]*class=[\"'][^\"']*\\buk-heading-line\\b[^\"']*[\"'][^>]*>[\\s\\S]*?<span[^>]*>([\\s\\S]*?)</span>"));
        return new ComicModels.ChapterPage(baseUrl, title, images, "");
    }

    @Override
    public boolean healthCheck() {
        try {
            return fetch(absolute(config.route("categoryIndex"))).contains("shaixuancont");
        } catch (IOException ignored) {
            return false;
        }
    }

    private List<ComicModels.ComicSummary> parseCards(String html) {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher cards = CARD_PATTERN.matcher(html == null ? "" : html);
        while (cards.find()) {
            String card = cards.group(1);
            String href = decode(first(card, "<a[^>]+href=[\"']([^\"']*a=bofang[^\"']*kuid=\\d+[^\"']*)[\"']"));
            String rawId = rawComicId(href);
            if (TextUtils.isEmpty(rawId) || !seen.add(rawId)) continue;
            String imageTag = firstRaw(card, "<img[^>]*>");
            String title = clean(first(card, "<p[^>]*>[\\s\\S]*?<a[^>]+a=bofang[^>]*>([\\s\\S]*?)</a>"));
            if (TextUtils.isEmpty(title)) continue;
            String reads = clean(first(card, "<a[^>]+a=bofang[^>]*>\\s*(阅读\\s*\\d+)\\s*</a>"));
            result.add(new ComicModels.ComicSummary(
                    config.id, prefix + rawId, title, absolute(imageUrlFromTag(imageTag)), reads, new ArrayList<String>()));
        }
        return result;
    }

    private List<ComicModels.Chapter> parseChapters(String html) {
        List<ComicModels.Chapter> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        String regularSection = first(html, "<!--\\s*单话内容 开始\\s*-->([\\s\\S]*?)<!--\\s*单话内容 结束\\s*-->");
        if (TextUtils.isEmpty(regularSection)) regularSection = section(html, "单话");
        List<ComicModels.Chapter> regular = parseChapterSection(regularSection, 0, seen);
        List<ComicModels.Chapter> extras = parseChapterSection(section(html, "番外篇"), 1, seen);
        Collections.reverse(regular);
        Collections.reverse(extras);
        result.addAll(regular);
        result.addAll(extras);
        for (int i = 0; i < result.size(); i++) {
            ComicModels.Chapter item = result.get(i);
            result.set(i, new ComicModels.Chapter(item.chapterId, item.title, item.url, item.sectionSlot, i));
        }
        return result;
    }

    private List<ComicModels.Chapter> parseChapterSection(String html, int sectionSlot, Set<String> seen) {
        List<ComicModels.Chapter> result = new ArrayList<>();
        Matcher matcher = CHAPTER_PATTERN.matcher(html);
        while (matcher.find()) {
            String url = absolute(decode(matcher.group(1)));
            String chapterId = matcher.group(3);
            String title = clean(matcher.group(4));
            if (!TextUtils.isEmpty(title) && seen.add(chapterId)) {
                result.add(new ComicModels.Chapter(chapterId, title, url, sectionSlot, result.size()));
            }
        }
        return result;
    }

    private String section(String html, String name) {
        return first(html, "<!--\\s*" + Pattern.quote(name) + " 展示栏 开始\\s*-->([\\s\\S]*?)<!--\\s*" + Pattern.quote(name) + " 展示栏 结束\\s*-->");
    }

    private List<String> parseTags(String info) {
        List<String> tags = new ArrayList<>();
        Matcher matcher = Pattern.compile("<a[^>]+a=ku[^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE).matcher(info);
        while (matcher.find()) {
            String tag = clean(matcher.group(1));
            if (!TextUtils.isEmpty(tag) && !tags.contains(tag)) tags.add(tag);
        }
        return tags;
    }

    private void addImages(String html, List<String> images, Set<String> seen) throws IOException {
        Matcher matcher = URL_ARRAY_PATTERN.matcher(html == null ? "" : html);
        if (!matcher.find()) return;
        try {
            JSONArray array = new JSONArray(matcher.group(1));
            for (int i = 0; i < array.length(); i++) {
                String image = absolute(array.optString(i));
                if (!TextUtils.isEmpty(image) && seen.add(image)) images.add(image);
            }
        } catch (JSONException e) {
            throw new IOException(config.name + " 图片列表解析失败", e);
        }
    }

    private int pageCount(String html) {
        int max = 1;
        Matcher matcher = Pattern.compile("[?&](?:amp;)?page=(\\d+)", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        while (matcher.find()) {
            try {
                max = Math.max(max, Integer.parseInt(matcher.group(1)));
            } catch (NumberFormatException ignored) {
            }
        }
        return max;
    }

    private String categoryId(String region) throws IOException {
        if (TextUtils.isEmpty(region) || "all".equals(region) || "全部".equals(region)) return "";
        String id = categoryIds.get(region);
        if (TextUtils.isEmpty(id)) {
            categories();
            id = categoryIds.get(region);
        }
        if (TextUtils.isEmpty(id)) throw new IOException(config.name + " 分类不存在：" + region);
        return id;
    }

    private String detailUrl(String rawId) {
        return absolute(config.route("detail").replace("{comicId}", rawId));
    }

    private String rawComicId(String value) {
        if (value == null) return "";
        if (value.startsWith(prefix)) value = value.substring(prefix.length());
        Matcher matcher = Pattern.compile("[?&](?:amp;)?kuid=(\\d+)", Pattern.CASE_INSENSITIVE).matcher(value);
        return matcher.find() ? matcher.group(1) : value.replaceAll("\\D+", "");
    }

    private String withoutPage(String url) {
        return url.replaceAll("([?&])page=\\d+&?", "$1").replaceAll("[?&]+$", "");
    }

    private String pageUrl(String url, int page) {
        return url + (url.contains("?") ? "&" : "?") + "page=" + page;
    }

    private String fetch(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(25000);
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

    private String imageUrlFromTag(String tag) {
        String url = attr(tag, "data-src");
        if (TextUtils.isEmpty(url)) url = attr(tag, "data-original");
        if (TextUtils.isEmpty(url)) url = attr(tag, "src");
        return url.trim();
    }

    private String absolute(String value) {
        if (TextUtils.isEmpty(value)) return "";
        String url = decode(value).trim();
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        if (url.startsWith("./")) url = url.substring(1);
        return config.baseUrl + (url.startsWith("/") ? url : "/" + url);
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
