package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class MkzhanComicSource implements ComicSource {
    private static final String SOURCE_ID = "mkzhan";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final List<String> SITE_CATEGORIES = Arrays.asList("国漫", "热门", "韩漫", "日漫");
    private static final Pattern CARD_PATTERN = Pattern.compile(
            "<div class=\"common-comic-item\"[^>]*>[\\s\\S]*?(?=<div class=\"common-comic-item\"|<div id=\"Pagination\"|$)",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<a[^>]+data-hreflink=\"(/\\d+/\\d+\\.html)\"[^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);

    private final SourceConfig config;

    public MkzhanComicSource() {
        this(SourceConfig.mkzhan(true));
    }

    public MkzhanComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.mkzhan(true) : config;
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
        if (page > 1) return Collections.emptyList();
        String encoded = URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        return parseCards(fetch(absolute(config.route("search").replace("{keyword}", encoded))));
    }

    @Override
    public List<String> categories() {
        return new ArrayList<>(SITE_CATEGORIES);
    }

    @Override
    public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        String html = fetch(categoryUrl("all", 1));
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        Matcher sections = Pattern.compile("<div[^>]*class=[\"'][^\"']*\\bcate-col\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)(?=<div[^>]*class=[\"'][^\"']*\\bcate-col\\b|</div>\\s*</div>)", Pattern.CASE_INSENSITIVE).matcher(html);
        while (sections.find()) {
            String block = sections.group(1);
            String label = clean(first(block, "<p[^>]*class=[\"'][^\"']*\\bcate-title\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</p>")).replace("：", "");
            String key = "题材".equals(label) ? "theme_id"
                    : "进度".equals(label) ? "finish"
                    : "受众".equals(label) ? "audience"
                    : "版权".equals(label) ? "copyright" : "";
            if (TextUtils.isEmpty(key)) continue;
            List<ComicModels.FilterOption> options = new ArrayList<>();
            Matcher links = Pattern.compile("<a[^>]*href=[\"']([^\"']*)[\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE).matcher(block);
            while (links.find()) {
                String optionLabel = clean(links.group(2));
                String value = queryValue(decode(links.group(1)), key);
                if (TextUtils.isEmpty(value)) value = "all";
                if (!TextUtils.isEmpty(optionLabel)) options.add(new ComicModels.FilterOption(optionLabel, value));
            }
            if (!options.isEmpty()) groups.add(new ComicModels.FilterGroup(key, label, options));
        }
        if (groups.isEmpty()) throw new IOException(config.name + " 分类解析失败");
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        return parseCards(fetch(categoryUrl(state, page)));
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        StringBuilder query = new StringBuilder("is_free=1");
        for (String key : new String[]{"theme_id", "finish", "audience", "copyright"}) {
            String value = SourceFilters.value(filters, key, "all");
            if (!"all".equals(value)) query.append('&').append(key).append('=').append(value);
        }
        if (page > 1) query.append("&page=").append(page);
        String path = config.route("category").replace("{query}", "?" + query)
                .replace("{page}", String.valueOf(page)).replace("{pagePath}", "");
        return parseCards(fetch(absolute(path)));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        String title = first(html, "<h1[^>]*>([\\s\\S]*?)</h1>");
        if (TextUtils.isEmpty(title)) title = first(html, "<title>([\\s\\S]*?)(?:_|-)");
        String cover = imageUrlFromTag(firstRaw(html, "<div class=\"de-info__cover\">[\\s\\S]*?<img[^>]+>"));
        if (TextUtils.isEmpty(cover)) cover = imageUrlFromTag(firstRaw(html, "<img[^>]+(?:data-src|src)=\"[^\"]+\"[^>]*>"));
        String author = first(html, "<span[^>]*>作者[:：]?</span>\\s*<[^>]+>([\\s\\S]*?)</");
        String status = first(html, "<div class=\"de-chapter__title\">\\s*<span>([\\s\\S]*?)</span>");
        String latest = first(html, "<span class=\"update-time\">([\\s\\S]*?)</span>");
        String description = first(html, "<p class=\"intro-total\">([\\s\\S]*?)</p>");
        if (TextUtils.isEmpty(description)) description = first(html, "<p class=\"intro\">([\\s\\S]*?)</p>");
        List<ComicModels.Chapter> chapters = parseChapters(html);
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, clean(title), absoluteImage(cover), clean(latest), new ArrayList<String>());
        return new ComicModels.ComicDetail(summary, clean(author), clean(status), clean(description), clean(latest), chapters);
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawComicId(comicId))));
        return parseChapters(html);
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String path = chapterPath(chapterUrl);
        String[] ids = chapterIds(path);
        String api = config.route("chapterApi")
                .replace("{comicId}", ids[0])
                .replace("{chapterId}", ids[1]);
        JSONObject root;
        try {
            root = new JSONObject(fetch(absoluteApi(api)));
        } catch (JSONException error) {
            throw new IOException("Invalid mkzhan chapter response", error);
        }
        List<String> images = new ArrayList<>();
        JSONArray pages = root.optJSONObject("data") == null ? null : root.optJSONObject("data").optJSONArray("page");
        if (pages != null) {
            Set<String> seen = new LinkedHashSet<>();
            for (int i = 0; i < pages.length(); i++) {
                String image = pages.optJSONObject(i) == null ? "" : pages.optJSONObject(i).optString("image");
                image = cleanImageUrl(image);
                if (!TextUtils.isEmpty(image) && seen.add(image)) images.add(image);
            }
        }
        String title = "";
        return new ComicModels.ChapterPage(chapterUrl(path), title, images, "");
    }

    @Override
    public boolean healthCheck() {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(config.baseUrl + "/").openConnection();
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
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CARD_PATTERN.matcher(cardListBlock(html));
        while (matcher.find()) {
            String block = matcher.group(0);
            String coverLink = firstRaw(block, "<a[^>]+class=\"[^\"]*cover[^\"]*\"[^>]*>");
            String rawId = clean(attr(block, "data-cid"));
            if (TextUtils.isEmpty(rawId)) rawId = rawComicId(attr(coverLink, "href"));
            if (TextUtils.isEmpty(rawId) || !seen.add(rawId)) continue;
            String imageTag = firstRaw(block, "<img[^>]+>");
            String title = clean(first(block, "<p class=\"comic__title\">[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>"));
            if (TextUtils.isEmpty(title)) title = clean(attr(imageTag, "alt"));
            String latest = clean(first(block, "<p class=\"comic-update\">[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>"));
            String count = clean(first(block, "<p class=\"comic-count\">([\\s\\S]*?)</p>"));
            result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, absoluteImage(imageUrlFromTag(imageTag)), clean(latest, count), new ArrayList<String>()));
        }
        return result;
    }

    private String cardListBlock(String html) {
        String block = firstRaw(html, "<div class=\"cate-comic-list clearfix\">[\\s\\S]*?<div id=\"Pagination\"");
        if (!TextUtils.isEmpty(block)) return block;
        block = firstRaw(html, "<div class=\"search-comic-list\">[\\s\\S]*?<div id=\"Pagination\"");
        return TextUtils.isEmpty(block) ? html : block;
    }

    private List<ComicModels.Chapter> parseChapters(String html) {
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CHAPTER_PATTERN.matcher(html);
        int index = 0;
        while (matcher.find()) {
            String href = decode(matcher.group(1));
            String title = clean(matcher.group(2));
            if (TextUtils.isEmpty(title) || title.contains("开始阅读") || !seen.add(href)) continue;
            chapters.add(new ComicModels.Chapter(rawChapterId(href), title, chapterUrl(href), 0, index++));
        }
        return chapters;
    }

    private String categoryUrl(String filter, int page) {
        String query = filterQuery(filter);
        if (page > 1) query = TextUtils.isEmpty(query) ? "page=" + page : query + "&page=" + page;
        if (!TextUtils.isEmpty(query)) query = "?" + query;
        String path = config.route("category")
                .replace("{query}", query)
                .replace("{genre}", "")
                .replace("{genrePath}", "")
                .replace("{page}", String.valueOf(page))
                .replace("{pagePath}", "");
        return absolute(path);
    }

    private String filterQuery(String value) {
        if (TextUtils.isEmpty(value) || "all".equals(value)) return "";
        return config.filter("filter." + value);
    }

    private String queryValue(String href, String key) {
        Matcher matcher = Pattern.compile("[?&]" + Pattern.quote(key) + "=([^&#]+)", Pattern.CASE_INSENSITIVE).matcher(href == null ? "" : href);
        return matcher.find() ? matcher.group(1) : "";
    }

    private String fetch(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(15000);
        connection.setRequestProperty("User-Agent", UA);
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

    private String rawComicId(String value) {
        String raw = decode(value);
        if (raw.startsWith(PREFIX)) raw = raw.substring(PREFIX.length());
        Matcher matcher = Pattern.compile("/(\\d+)/?").matcher(raw);
        if (matcher.find()) return matcher.group(1);
        return raw.replaceAll("[^0-9]", "").trim();
    }

    private String rawChapterId(String href) {
        String[] ids = chapterIds(href);
        return ids[0] + "/" + ids[1];
    }

    private String[] chapterIds(String href) {
        Matcher matcher = Pattern.compile("/?(\\d+)/(\\d+)(?:\\.html)?/?").matcher(decode(href));
        if (matcher.find()) return new String[]{matcher.group(1), matcher.group(2)};
        return new String[]{"", ""};
    }

    private String chapterPath(String value) {
        String decoded = decode(value);
        if (decoded.startsWith("http")) {
            try {
                decoded = new URL(decoded).getPath();
            } catch (Exception ignored) {
            }
        }
        if (!decoded.startsWith("/")) decoded = "/" + decoded;
        return decoded;
    }

    private String chapterUrl(String href) {
        String path = chapterPath(href);
        return absolute(path);
    }

    private String first(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? clean(matcher.group(1)) : "";
    }

    private String firstRaw(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group(0) : "";
    }

    private String attr(String html, String name) {
        Matcher matcher = Pattern.compile(name + "=\"([^\"]*)\"", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group(1) : "";
    }

    private String imageUrlFromTag(String imageTag) {
        String url = attr(imageTag, "data-src");
        if (TextUtils.isEmpty(url)) url = attr(imageTag, "data-original");
        if (TextUtils.isEmpty(url)) url = attr(imageTag, "src");
        return cleanImageUrl(url);
    }

    private String cleanImageUrl(String value) {
        String decoded = decode(value);
        if (decoded.startsWith("http://")) decoded = "https://" + decoded.substring(7);
        return decoded.trim();
    }

    private String absoluteImage(String url) {
        if (TextUtils.isEmpty(url)) return "";
        if (url.startsWith("//")) return "https:" + url;
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        return absolute(url);
    }

    private String absolute(String url) {
        if (TextUtils.isEmpty(url)) return "";
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        if (url.startsWith("/")) return config.baseUrl + url;
        return config.baseUrl + "/" + url;
    }

    private String absoluteApi(String url) {
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        return absolute(url);
    }

    private String clean(String value) {
        if (value == null) return "";
        String decoded = decode(value).replaceAll("<i[\\s\\S]*?</i>", " ");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            return Html.fromHtml(decoded, Html.FROM_HTML_MODE_LEGACY).toString().replaceAll("\\s+", " ").trim();
        }
        return Html.fromHtml(decoded).toString().replaceAll("\\s+", " ").trim();
    }

    private String clean(String preferred, String fallback) {
        return TextUtils.isEmpty(preferred) ? fallback : preferred;
    }

    private String decode(String value) {
        return value == null ? "" : value.replace("&amp;", "&").replace("&quot;", "\"").replace("\\/", "/");
    }
}
