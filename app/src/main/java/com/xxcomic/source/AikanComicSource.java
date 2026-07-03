package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class AikanComicSource implements ComicSource {
    private static final String SOURCE_ID = "aikan";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String DESKTOP_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern CATEGORY_CARD_PATTERN = Pattern.compile(
            "<div class=\"comics-card[\\s\\S]*?<a[^>]+href=\"([^\"]*?/youbooks/\\d+\\.html)\"[^>]+title=\"([^\"]*)\"[\\s\\S]*?<amp-img[^>]+src=\"([^\"]+)\"[\\s\\S]*?<span class=\"tab\">([\\s\\S]*?)</span>[\\s\\S]*?<small class=\"tags\">([\\s\\S]*?)</small>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern SEARCH_CARD_PATTERN = Pattern.compile(
            "<a href=\"([^\"]*?/youbooks/\\d+\\.html)\"[\\s\\S]*?<div class=\"comic-item\"[\\s\\S]*?<img[^>]+src=\"([^\"]+)\"[^>]+alt=\"([^\"]*)\"[\\s\\S]*?<h3 class=\"title\"[^>]*>([\\s\\S]*?)</h3>[\\s\\S]*?<div class=\"author txt-inner\"[^>]*>([\\s\\S]*?)</div>[\\s\\S]*?<span class=\"txt-inner\"[^>]*>([\\s\\S]*?)</span>[\\s\\S]*?<span class=\"txt-inner\"[^>]*>([\\s\\S]*?)</span>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<a href=\"([^\"]*?/chook/\\d+)\"[^>]*class=\"comics-chapters__item[^\"]*\"[\\s\\S]*?<span[^>]*>([\\s\\S]*?)</span>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern SCRIPT_IMAGE_PATTERN = Pattern.compile(
            "data-original=\"\\s*\"\\s*\\+\\s*picx\\[i\\]\\.img\\s*\\+\\s*\"",
            Pattern.CASE_INSENSITIVE);
    private final SourceConfig config;

    public AikanComicSource() {
        this(SourceConfig.aikan(true));
    }

    public AikanComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.aikan(true) : config;
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
        String path = config.route("search")
                .replace("{keyword}", encoded)
                .replace("{page}", String.valueOf(page))
                .replace("{pagePath}", page <= 1 ? "" : "&page=" + page)
                .replace("{pageQuery}", page <= 1 ? "" : "&page=" + page);
        return parseCards(fetch(absolute(path)));
    }

    @Override
    public List<String> categories() {
        return Arrays.asList("连载中", "已完结");
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        return parseCards(fetch(categoryUrl(state, page)));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        String title = first(html, "<h1 class=\"comics-detail__title\"[^>]*>([\\s\\S]*?)(?:<a|</h1>)");
        String cover = first(html, "<div class=\"comics-detail[\\s\\S]*?<img[^>]+src=\"([^\"]+)\"");
        String author = first(html, "<h2 class=\"comics-detail__author\"[^>]*>([\\s\\S]*?)</h2>");
        String status = first(html, "<span class=\"tag\">([\\s\\S]*?)</span>");
        String latest = first(html, "最新[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>");
        String description = first(html, "<p class=\"comics-detail__desc[^\"]*\"[^>]*>([\\s\\S]*?)</p>");
        List<String> tags = detailTags(html);
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, clean(title), cleanUrl(cover), clean(latest), tags);
        return new ComicModels.ComicDetail(summary, clean(author), clean(status), clean(description), clean(latest), new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawComicId(comicId))));
        String chapterBlock = chapterDirectoryBlock(html);
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CHAPTER_PATTERN.matcher(chapterBlock);
        int index = 0;
        while (matcher.find()) {
            String href = decode(matcher.group(1));
            String title = clean(matcher.group(2));
            if (TextUtils.isEmpty(title) || isNoticeChapter(title) || !seen.add(href)) continue;
            chapters.add(new ComicModels.Chapter(rawChapterId(href), title, absolute(href), 0, index++));
        }
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = chapterUrl(chapterUrl);
        String html = fetch(url);
        String title = first(html, "<title>([\\s\\S]*?)</title>");
        List<String> images = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher direct = Pattern.compile("data-original=\"(https?://[^\"]+)\"", Pattern.CASE_INSENSITIVE).matcher(html);
        while (direct.find()) {
            String image = cleanReaderImageUrl(direct.group(1));
            if (isReaderImage(image) && seen.add(image)) images.add(image);
        }
        Matcher json = Pattern.compile("\"img\"\\s*:\\s*\"(https?://[^\"]+)\"", Pattern.CASE_INSENSITIVE).matcher(html);
        while (json.find()) {
            String image = cleanReaderImageUrl(json.group(1));
            if (isReaderImage(image) && seen.add(image)) images.add(image);
        }
        String next = first(html, "next_chapter'\\)\\.html\\('<a href=\"([^\"]+)\"");
        if (images.isEmpty() && SCRIPT_IMAGE_PATTERN.matcher(html).find()) {
            title = clean(title, "图片由站点脚本加密加载，当前版本未解析到图片");
        }
        return new ComicModels.ChapterPage(url, clean(title), images, TextUtils.isEmpty(next) ? "" : absolute(next));
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
        List<ComicModels.ComicSummary> summaries = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher search = SEARCH_CARD_PATTERN.matcher(html);
        while (search.find()) {
            String rawId = rawComicId(search.group(1));
            if (rawId.isEmpty() || !seen.add(rawId)) continue;
            String title = clean(search.group(4));
            if (title.isEmpty()) title = clean(search.group(3));
            List<String> tags = parseTags(search.group(6));
            summaries.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cleanUrl(search.group(2)), clean(search.group(7), search.group(5)), tags));
        }
        if (!summaries.isEmpty()) return summaries;

        Matcher category = CATEGORY_CARD_PATTERN.matcher(html);
        while (category.find()) {
            String rawId = rawComicId(category.group(1));
            if (rawId.isEmpty() || !seen.add(rawId)) continue;
            String tag = clean(category.group(4));
            List<String> tags = parseTags(tag);
            summaries.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, clean(category.group(2)), cleanUrl(category.group(3)), clean(category.group(5), tag), tags));
        }
        return summaries;
    }

    private String categoryUrl(String state, int page) {
        String finish = finishId(state);
        String path = config.route("category")
                .replace("{finish}", finish)
                .replace("{finishPath}", finish.isEmpty() ? "" : "/finish/" + finish)
                .replace("{page}", String.valueOf(page))
                .replace("{pagePath}", page <= 1 ? "" : "/page/" + page);
        return absolute(path);
    }

    private String finishId(String state) {
        if (state == null || state.isEmpty() || "all".equals(state)) return "";
        return config.filter("finish." + state);
    }

    private List<String> detailTags(String html) {
        List<String> tags = new ArrayList<>();
        Matcher matcher = Pattern.compile("<span class=\"tag\">([\\s\\S]*?)</span>", Pattern.CASE_INSENSITIVE).matcher(html);
        while (matcher.find()) {
            String tag = clean(matcher.group(1));
            if (!tag.isEmpty() && !tag.matches("\\d+.*") && !"连载".equals(tag) && !"完结".equals(tag)) tags.addAll(parseTags(tag));
        }
        return tags;
    }

    private String chapterDirectoryBlock(String html) {
        int title = html == null ? -1 : html.indexOf("章节目录");
        if (title < 0) return html == null ? "" : html;
        int start = html.indexOf("comics-chapters__item", title);
        if (start < 0) return html.substring(title);
        int end = html.indexOf("but-vip", start);
        if (end < 0) end = html.indexOf("section-title", start + 1);
        if (end < 0) end = html.length();
        return html.substring(start, end);
    }

    private List<String> parseTags(String value) {
        List<String> tags = new ArrayList<>();
        if (value == null) return tags;
        for (String part : value.split("[,，、\\s]+")) {
            String tag = clean(part);
            if (!tag.isEmpty() && tag.length() <= 6 && !tags.contains(tag)) tags.add(tag);
        }
        return tags;
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

    private String rawComicId(String value) {
        if (value == null) return "";
        if (value.startsWith(PREFIX)) value = value.substring(PREFIX.length());
        int slash = value.lastIndexOf('/');
        if (slash >= 0) value = value.substring(slash + 1);
        return value.replace(".html", "").trim();
    }

    private String rawChapterId(String value) {
        String decoded = decode(value);
        int query = decoded.indexOf('?');
        if (query >= 0) decoded = decoded.substring(0, query);
        int slash = decoded.lastIndexOf('/');
        return slash >= 0 ? decoded.substring(slash + 1).trim() : decoded.trim();
    }

    private String chapterUrl(String value) {
        String decoded = decode(value);
        if (decoded.startsWith(PREFIX)) decoded = decoded.substring(PREFIX.length());
        if (!decoded.contains("/") && decoded.matches("\\d+")) {
            return absolute(config.route("chapter").replace("{chapterId}", decoded));
        }
        return absolute(decoded);
    }

    private boolean isReaderImage(String url) {
        return !TextUtils.isEmpty(url) && (url.contains("/colafm/") || url.contains("/colatj/") || url.contains("/scomic/"));
    }

    private boolean isNoticeChapter(String title) {
        return title.contains("公告") || title.contains("查看更多");
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

    private String clean(String preferred, String fallback) {
        return TextUtils.isEmpty(preferred) ? fallback : preferred;
    }

    private String decode(String value) {
        return value == null ? "" : value.replace("&amp;", "&").replace("&quot;", "\"");
    }

    private String cleanUrl(String value) {
        String decoded = decode(value).replace("\\/", "/");
        int amp = decoded.indexOf("&");
        return amp > 0 ? decoded.substring(0, amp) : decoded;
    }

    private String cleanReaderImageUrl(String value) {
        String url = cleanUrl(value);
        if (url.startsWith("http://f2-img.534zm.com/")) {
            return "https://" + url.substring("http://".length());
        }
        return url;
    }
}
