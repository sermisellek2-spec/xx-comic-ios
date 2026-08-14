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
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class D5d6ComicSource implements ComicSource {
    private static final String SOURCE_ID = "d5d6";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern CATEGORY_LINK_PATTERN = Pattern.compile(
            "href=[\"'](?:https?://www\\.d5d6\\.com)?/jiujiucate_(jiujiu[^_/]+)_allvisit_\\d+_\\d+/?[\"'][^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<li>\\s*<a[^>]+href=[\"']([^\"']+\\.html)[\"'][^>]*>([\\s\\S]*?)</a>\\s*</li>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern IMAGE_TAG_PATTERN = Pattern.compile(
            "<img[^>]+(?:data-original|data-src|src)=[\"']([^\"']+)[\"'][^>]*>",
            Pattern.CASE_INSENSITIVE);
    private final SourceConfig config;
    private final Map<String, String> categorySlugs = new LinkedHashMap<>();

    public D5d6ComicSource() {
        this(SourceConfig.d5d6(true));
    }

    public D5d6ComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.d5d6(true) : config;
    }

    @Override public String id() { return SOURCE_ID; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return parseCards(fetch(categoryUrl("all", "all", page)));
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        if (page > 1) return new ArrayList<>();
        String encoded = URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        String html = fetch(absolute(config.route("search").replace("{keyword}", encoded)));
        if (isEmptySearchPage(html)) return new ArrayList<>();
        return parseCards(html);
    }

    @Override
    public List<String> categories() throws IOException {
        List<String> values = parseCategoryIndex(fetch(absolute(config.route("categoryIndex"))));
        return values.isEmpty() ? Arrays.asList("\u5927\u9646", "\u65e5\u672c", "\u97e9\u56fd", "\u6b27\u7f8e") : values;
    }

    @Override
    public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        parseCategoryIndex(fetch(absolute(config.route("categoryIndex"))));
        if (categorySlugs.isEmpty()) throw new IOException(config.name + " 分类解析失败");
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        groups.add(SourceFilters.group("category", "题材", categorySlugs));
        groups.add(SourceFilters.group("state", "状态",
                "全部", "all", "连载中", "serial", "已完成", "pub"));
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        return parseCards(fetch(categoryUrl(region, state, page)));
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        String slug = SourceFilters.value(filters, "category", "jiujiuquanbu");
        if ("all".equals(slug)) slug = "jiujiuquanbu";
        String state = SourceFilters.value(filters, "state", "all");
        return parseCards(fetch(absolute(config.route("category")
                .replace("{slug}", slug)
                .replace("{finish}", finishId(state))
                .replace("{page}", String.valueOf(Math.max(1, page))))));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        String info = detailInfoBlock(html);
        String title = clean(first(info, "<h1[^>]+class=[\"'][^\"']*title[^\"']*[\"'][^>]*>([\\s\\S]*?)</h1>"));
        if (TextUtils.isEmpty(title)) title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        if (TextUtils.isEmpty(title)) title = clean(first(html, "<title>([\\s\\S]*?)(?:-|_).*?</title>"));
        String cover = imageUrlFromTag(firstRaw(html, "<div[^>]+class=[\"'][^\"']*cover-box[^\"']*[\"'][^>]*>[\\s\\S]*?<img[^>]+>"));
        if (TextUtils.isEmpty(cover)) cover = imageUrlFromTag(firstRaw(html, "<div[^>]+class=[\"'][^\"']*(?:cover|book|pic|thumb)[^\"']*[\"'][\\s\\S]*?<img[^>]+>"));
        if (TextUtils.isEmpty(cover) && !TextUtils.isEmpty(title)) cover = imageUrlFromTag(firstRaw(html, "<img[^>]+(?:alt|title)=[\"'][^\"']*" + Pattern.quote(title) + "[^\"']*[\"'][^>]*>"));
        String author = extractTextAfterLabel(info, "\u4f5c\u8005");
        String status = detectDetailStatus(html);
        String description = extractParagraphAfterLabel(info, "\u7b80\u4ecb");
        String latest = extractLinkTextAfterLabel(info, "\u6700\u65b0\u7ae0\u8282");
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, absolute(cover), latest, new ArrayList<String>());
        return new ComicModels.ComicDetail(summary, author, status, description, latest, new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        String block = firstRaw(html, "<ul[^>]+class=[\"'][^\"']*chapter-list[^\"']*[\"'][^>]*>[\\s\\S]*?</ul>");
        if (TextUtils.isEmpty(block)) block = html;
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CHAPTER_PATTERN.matcher(block);
        int index = 0;
        while (matcher.find()) {
            String href = decode(matcher.group(1));
            String title = clean(matcher.group(2));
            if (TextUtils.isEmpty(title) || !seen.add(href)) continue;
            chapters.add(new ComicModels.Chapter(rawChapterId(href), title, chapterUrl(rawId, href), 0, index++));
        }
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = absolute(chapterUrl);
        String html = fetch(url);
        String title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        if (TextUtils.isEmpty(title)) title = clean(first(html, "<title>([\\s\\S]*?)(?:-|_).*?</title>"));
        String readerHtml = readerBlock(html);
        List<String> images = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher img = IMAGE_TAG_PATTERN.matcher(readerHtml);
        while (img.find()) {
            String image = cleanUrl(img.group(1));
            if (isReaderImage(image) && seen.add(image)) images.add(absolute(image));
        }
        Matcher script = Pattern.compile("[\"'](https?:[^\"']+\\.(?:jpg|jpeg|png|webp)(?:\\?[^\"']*)?)[\"']", Pattern.CASE_INSENSITIVE).matcher(readerHtml);
        while (script.find()) {
            String image = cleanUrl(script.group(1).replace("\\/", "/"));
            if (isReaderImage(image) && seen.add(image)) images.add(absolute(image));
        }
        return new ComicModels.ChapterPage(url, title, images, "");
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

    private List<String> parseCategoryIndex(String html) {
        List<String> values = new ArrayList<>();
        categorySlugs.clear();
        Matcher matcher = CATEGORY_LINK_PATTERN.matcher(html == null ? "" : html);
        while (matcher.find()) {
            String slug = matcher.group(1);
            String title = clean(matcher.group(2));
            if (TextUtils.isEmpty(slug) || TextUtils.isEmpty(title) || "jiujiuquanbu".equals(slug)) continue;
            if (!values.contains(title)) values.add(title);
            categorySlugs.put(title, slug);
        }
        return values;
    }
    private List<ComicModels.ComicSummary> parseCards(String html) {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher cardMatcher = Pattern.compile(
                "<li[^>]*>\\s*<div[^>]+class=[\"'][^\"']*cart-item[^\"']*[\"'][^>]*>[\\s\\S]*?</li>",
                Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        while (cardMatcher.find()) {
            String block = cardMatcher.group(0);
            String href = decode(first(block, "<a[^>]+class=[\"'][^\"']*cart-cover[^\"']*[\"'][^>]+href=[\"']([^\"']+)[\"']"));
            if (TextUtils.isEmpty(href)) href = decode(first(block, "<a[^>]+href=[\"']([^\"']*jiujiucomic_\\d+/?)[\"']"));
            String rawId = rawComicId(href);
            if (TextUtils.isEmpty(rawId) || !seen.add(rawId)) continue;
            String imageTag = firstRaw(block, "<img[^>]+>");
            String info = firstRaw(block, "<div[^>]+class=[\"'][^\"']*cart-info[^\"']*[\"'][^>]*>[\\s\\S]*?</div>");
            String title = clean(first(info, "<p[^>]*>[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>"));
            if (TextUtils.isEmpty(title)) title = clean(attr(imageTag, "alt"));
            if (TextUtils.isEmpty(title)) title = clean(attr(block, "title"));
            if (TextUtils.isEmpty(title)) continue;
            String latest = clean(first(block, "<span[^>]+class=[\"'][^\"']*new-chapter[^\"']*[\"'][^>]*>([\\s\\S]*?)</span>"));
            String cover = imageUrlFromTag(imageTag);
            result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, absolute(cover), latest, new ArrayList<String>()));
        }
        return result;
    }

    private boolean isEmptySearchPage(String html) {
        return clean(html).matches("(?s).*\u641c\u7d22\u300a[^\u300b]+\u300b\u7ed3\u679c\u4e3a\u7a7a\uff0c\u4ee5\u4e0b\u662f\u4e3a\u60a8\u63a8\u8350\u7684\u70ed\u95e8\u4f5c\u54c1.*");
    }

    private String categoryUrl(String region, String state, int page) throws IOException {
        String slug = slugForRegion(region);
        String finish = finishId(state);
        return absolute(config.route("category")
                .replace("{slug}", slug)
                .replace("{finish}", finish)
                .replace("{page}", String.valueOf(Math.max(1, page))));
    }

    private String slugForRegion(String region) throws IOException {
        if (TextUtils.isEmpty(region) || "all".equals(region)) return "jiujiuquanbu";
        String value = config.filter("category." + region);
        if (!TextUtils.isEmpty(value)) return value;
        value = categorySlugs.get(region);
        if (!TextUtils.isEmpty(value)) return value;
        parseCategoryIndex(fetch(absolute(config.route("categoryIndex"))));
        value = categorySlugs.get(region);
        return TextUtils.isEmpty(value) ? "jiujiuquanbu" : value;
    }

    private String finishId(String state) {
        if (TextUtils.isEmpty(state) || "all".equals(state)) return "0";
        String value = config.filter("state." + state);
        return TextUtils.isEmpty(value) ? "0" : value;
    }

    private String fetch(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(15000);
        connection.setRequestProperty("User-Agent", UA);
        connection.setRequestProperty("Referer", config.referer);
        try (InputStream stream = connection.getInputStream()) {
            byte[] bytes = readAllBytes(stream);
            String charset = charsetFrom(connection.getContentType());
            if (TextUtils.isEmpty(charset)) {
                String head = new String(bytes, 0, Math.min(bytes.length, 4096), "ISO-8859-1");
                charset = charsetFrom(head);
            }
            if (TextUtils.isEmpty(charset)) charset = "GBK";
            return new String(bytes, charset);
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

    private String charsetFrom(String value) {
        if (TextUtils.isEmpty(value)) return "";
        Matcher matcher = Pattern.compile("charset\\s*=\\s*['\"]?([A-Za-z0-9_\\-]+)", Pattern.CASE_INSENSITIVE).matcher(value);
        if (!matcher.find()) return "";
        String charset = matcher.group(1);
        if ("gb2312".equalsIgnoreCase(charset)) return "GBK";
        return charset;
    }

    private String rawComicId(String value) {
        if (value == null) return "";
        if (value.startsWith(PREFIX)) value = value.substring(PREFIX.length());
        Matcher matcher = Pattern.compile("jiujiucomic_(\\d+)").matcher(value);
        if (matcher.find()) return matcher.group(1);
        return value.replaceAll("[^0-9]", "");
    }

    private String rawChapterId(String href) {
        String value = decode(href);
        int slash = value.lastIndexOf('/');
        if (slash >= 0) value = value.substring(slash + 1);
        return value.replace(".html", "").trim();
    }

    private String chapterUrl(String comicId, String href) {
        String decoded = decode(href);
        if (decoded.startsWith("http")) return decoded;
        if (decoded.startsWith("/")) return absolute(decoded);
        return absolute(config.route("chapter").replace("{comicId}", comicId).replace("{chapterId}", rawChapterId(decoded)));
    }

    private String readerBlock(String html) {
        String block = firstRaw(html, "<div[^>]+class=[\"'][^\"']*(?:comicpage|comic-page|read-content|reading|chapter-content|article-content|comic-content|read-img|manga-content)[^\"']*[\"'][^>]*>[\\s\\S]*?</div>");
        return TextUtils.isEmpty(block) ? html : block;
    }
    private boolean isReaderImage(String url) {
        if (TextUtils.isEmpty(url)) return false;
        return url.matches("(?i).+\\.(jpe?g|png|webp)(\\?.*)?$")
                && !url.contains("logo")
                && !url.contains("avatar")
                && !url.contains("icon");
    }

    private String detailInfoBlock(String html) {
        String block = firstRaw(html, "<div[^>]+class=[\"'][^\"']*article-info-item[^\"']*[\"'][^>]*>[\\s\\S]*?<div[^>]+class=[\"'][^\"']*mt20[^\"']*[\"'][^>]*>");
        return TextUtils.isEmpty(block) ? (html == null ? "" : html) : block;
    }

    private String extractTextAfterLabel(String html, String label) {
        return clean(first(html, "<span[^>]+class=[\"'][^\"']*tag[^\"']*[\"'][^>]*>\\s*" + label + "[\\uFF1A:]\\s*</span>\\s*([^<\\r\\n]+)"));
    }

    private String extractParagraphAfterLabel(String html, String label) {
        return clean(first(html, "<span[^>]+class=[\"'][^\"']*tag[^\"']*[\"'][^>]*>\\s*" + label + "[\\uFF1A:]\\s*</span>\\s*([\\s\\S]*?)</p>"));
    }

    private String extractLinkTextAfterLabel(String html, String label) {
        return clean(first(html, "<span[^>]+class=[\"'][^\"']*tag[^\"']*[\"'][^>]*>\\s*" + label + "[\\uFF1A:]\\s*</span>\\s*<a[^>]*>([\\s\\S]*?)</a>"));
    }
    private String detectDetailStatus(String html) {
        String value = html == null ? "" : html.toLowerCase();
        if (value.matches("(?s).*tag-serialize[^\"']*(?:done|finish|end|complete).*")) return "\u5df2\u5b8c\u6210";
        if (value.matches("(?s).*tag-serialize[^\"']*(?:doing|serial|ongoing).*")) return "\u8fde\u8f7d\u4e2d";
        return "";
    }
    private String first(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group(1) : "";
    }

    private String firstRaw(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group(0) : "";
    }

    private String attr(String html, String name) {
        Matcher matcher = Pattern.compile("\\b" + Pattern.quote(name) + "=[\"']([^\"']*)[\"']", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? decode(matcher.group(1)) : "";
    }

    private String imageUrlFromTag(String tag) {
        String url = attr(tag, "data-original");
        if (TextUtils.isEmpty(url)) url = attr(tag, "data-src");
        if (TextUtils.isEmpty(url)) url = attr(tag, "src");
        return cleanUrl(url);
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
        String url = decode(value).replace("\\/", "/").trim();
        int amp = url.indexOf("&");
        return amp > 0 ? url.substring(0, amp) : url;
    }
}


