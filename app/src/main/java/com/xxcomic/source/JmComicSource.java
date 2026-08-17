package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;

import org.json.JSONArray;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class JmComicSource implements ComicSource {
    private static final String SOURCE_ID = "jmcomic";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern ALBUM_LINK = Pattern.compile(
            "<a\\b([^>]*href\\s*=\\s*([\"'])([^\"']*/album/(\\d+)[^\"']*)\\2[^>]*)>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern ANCHOR = Pattern.compile("<a\\b([^>]*)>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE);
    private static final Pattern THEME_SECTION = Pattern.compile(
            "<h4[^>]*>([\\s\\S]*?)</h4>(?:(?!<h4\\b)[\\s\\S]){0,1600}?"
                    + "<ul\\b[^>]*class\\s*=\\s*[\"'][^\"']*\\bbtnmg\\b[^\"']*[\"'][^>]*>"
                    + "([\\s\\S]*?)</ul>", Pattern.CASE_INSENSITIVE);
    private static final Pattern IMAGE_TAG = Pattern.compile("<img\\b[^>]*>", Pattern.CASE_INSENSITIVE);
    private final SourceConfig config;
    private final BrowserSession browserSession;
    private List<ComicModels.FilterGroup> filterGroupsCache;
    private String detailPageId = "";
    private String detailPageHtml = "";

    public JmComicSource() {
        this(SourceConfig.jmcomic(true), null);
    }

    public JmComicSource(SourceConfig config, BrowserSession browserSession) {
        this.config = config == null ? SourceConfig.jmcomic(true) : config;
        this.browserSession = browserSession;
    }

    @Override public String id() { return SOURCE_ID; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return requireCatalogCards(fetch(pageUrl(absolute(config.route("latest")), page)));
    }

    public void verifyAccess() throws IOException {
        String html = fetch(pageUrl(absolute(config.route("latest")), 1));
        if (!hasCatalogMarker(html)) throw new IOException(config.name + " 页面未就绪");
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        String encoded = URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        String path = config.route("search").replace("{keyword}", encoded);
        return parseCards(fetch(pageUrl(absolute(path), page)));
    }

    @Override
    public List<String> categories() throws IOException {
        List<ComicModels.FilterGroup> groups = filterGroups();
        List<String> result = new ArrayList<>();
        for (ComicModels.FilterGroup group : groups) result.add(group.label);
        return result;
    }

    @Override
    public synchronized List<ComicModels.FilterGroup> filterGroups() throws IOException {
        if (filterGroupsCache != null) return new ArrayList<>(filterGroupsCache);
        List<ComicModels.FilterGroup> groups = parseFilterGroups(
                fetch(absolute(config.route("categoryIndex"))), config.baseUrl);
        if (groups.isEmpty()) throw new IOException(config.name + " 分类解析失败");
        filterGroupsCache = new ArrayList<>(groups);
        return new ArrayList<>(filterGroupsCache);
    }

    static List<ComicModels.FilterGroup> parseFilterGroups(String html, String baseUrl) {
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        Matcher sections = THEME_SECTION.matcher(html == null ? "" : html);
        int index = 0;
        while (sections.find()) {
            String label = normalizeThemeLabel(cleanMarkup(sections.group(1)));
            List<ComicModels.FilterOption> options = new ArrayList<>();
            options.add(new ComicModels.FilterOption("全部", "all"));
            Set<String> seen = new LinkedHashSet<>();
            Matcher links = ANCHOR.matcher(sections.group(2));
            while (links.find()) {
                String href = decode(attribute(links.group(1), "href")).trim();
                if (!isCatalogPath(href, baseUrl) || !seen.add(href)) continue;
                String optionLabel = cleanMarkup(links.group(2));
                if (!optionLabel.isEmpty()) options.add(new ComicModels.FilterOption(optionLabel, href));
            }
            if (!label.isEmpty() && options.size() > 1) {
                groups.add(new ComicModels.FilterGroup("theme_" + index++, label, options));
            }
        }
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        String path = TextUtils.isEmpty(region) || "all".equals(region) ? config.route("latest") : region;
        return parseCards(fetch(pageUrl(absolute(path), page)));
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        String path = config.route("latest");
        boolean filtered = false;
        if (filters != null) {
            for (Map.Entry<String, String> item : filters.entrySet()) {
                if (item.getKey().startsWith("theme_") && isCatalogPath(item.getValue())) {
                    path = item.getValue();
                    filtered = true;
                    break;
                }
            }
        }
        String html = fetch(pageUrl(absolute(path), page));
        return !filtered && page == 1 ? requireCatalogCards(html) : parseCards(html);
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = detailPage(rawId);
        String title = clean(first(html, "<[^>]+id=[\"']book-name[\"'][^>]*>([\\s\\S]*?)</[^>]+>"));
        if (TextUtils.isEmpty(title)) title = clean(meta(html, "og:title"));
        String cover = parseCover(html, rawId);
        String description = clean(first(html, "<h2[^>]*>\\s*敘述\\s*[:：]([\\s\\S]*?)</h2>"));
        if (TextUtils.isEmpty(description)) description = clean(meta(html, "description"));
        String scope = detailScope(html);
        List<String> authors = linkTexts(scope, "main_tag=2");
        List<String> tags = tagTexts(scope);
        String status = tags.contains("完結") || tags.contains("完结") ? "已完结"
                : tags.contains("連載中") || tags.contains("连载中") ? "连载中" : "";
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(
                SOURCE_ID, PREFIX + rawId, title, absolute(cover), TextUtils.join(" / ", authors), tags);
        return new ComicModels.ComicDetail(summary, TextUtils.join(" / ", authors), status,
                description, "", new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = detailPage(rawId);
        List<ComicModels.Chapter> result = parseChapters(html, config.baseUrl);
        if (result.isEmpty()) throw new IOException(config.name + " 目录解析失败");
        return result;
    }

    private synchronized String detailPage(String rawId) throws IOException {
        if (rawId.equals(detailPageId) && !detailPageHtml.isEmpty()) return detailPageHtml;
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        if (html != null && !html.isEmpty()) {
            detailPageId = rawId;
            detailPageHtml = html;
        }
        return html;
    }

    static List<ComicModels.Chapter> parseChapters(String html, String baseUrl) {
        List<ComicModels.Chapter> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher links = ANCHOR.matcher(episodeScope(html));
        while (links.find()) {
            String href = decode(attribute(links.group(1), "href"));
            Matcher id = Pattern.compile("(?:https?://[^/]+)?/photo/(\\d+)", Pattern.CASE_INSENSITIVE).matcher(href);
            if (!id.find()) continue;
            String chapterId = id.group(1);
            String dataAlbum = attribute(links.group(1), "data-album");
            if (dataAlbum.isEmpty() || !chapterId.equals(dataAlbum)) continue;
            String title = cleanMarkup(firstValue(links.group(2),
                    "<h3[^>]*class=[\"'][^\"']*h2_series[^\"']*[\"'][^>]*>([\\s\\S]*?)</h3>"));
            if (title.isEmpty() || !seen.add(chapterId)) continue;
            result.add(new ComicModels.Chapter(chapterId, title,
                    absolute(baseUrl, href), 0, result.size()));
        }
        return result;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = absolute(chapterUrl);
        String html = fetch(url);
        List<String> images = parseChapterImages(html);
        if (images.isEmpty()) throw new IOException(config.name + " 正文图片解析失败");
        String title = clean(first(html,
                "<h3[^>]*class=[\"'][^\"']*h2_series[^\"']*[\"'][^>]*>([\\s\\S]*?)</h3>"));
        return new ComicModels.ChapterPage(url, title, images, "");
    }

    static List<String> parseChapterImages(String html) throws IOException {
        String aid = first(html, "(?:var\\s+)?aid\\s*=\\s*(\\d+)");
        String scrambleId = first(html, "(?:var\\s+)?scramble_id\\s*=\\s*(\\d+)");
        String cdnHost = decode(first(html, "cdnImgHost\\s*:\\s*[\"']([^\"']+)[\"']"));
        String pageArray = first(html, "(?:var\\s+)?page_arr\\s*=\\s*(\\[[\\s\\S]*?\\])\\s*;?");
        if (!aid.matches("\\d+") || !scrambleId.matches("\\d+") || cdnHost.isEmpty() || pageArray.isEmpty()) {
            throw new IOException("正文参数解析失败");
        }
        List<String> images = new ArrayList<>();
        try {
            JSONArray pages = new JSONArray(pageArray);
            for (int i = 0; i < pages.length(); i++) {
                String fileName = pages.optString(i).trim();
                if (fileName.isEmpty()) continue;
                String image = fileName.startsWith("http://") || fileName.startsWith("https://")
                        ? fileName : trimSlash(cdnHost) + "/media/photos/" + aid + "/" + fileName;
                images.add(image + (image.contains("?") ? "&" : "?") + "scramble_id=" + scrambleId);
            }
        } catch (Exception error) {
            throw new IOException("图片列表解析失败", error);
        }
        return images;
    }

    @Override
    public boolean healthCheck() {
        try {
            return fetch(absolute(config.route("categoryIndex"))).contains("btnmg");
        } catch (IOException ignored) {
            return false;
        }
    }

    private List<ComicModels.ComicSummary> parseCards(String html) {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher cards = ALBUM_LINK.matcher(html == null ? "" : html);
        while (cards.find()) {
            String rawId = cards.group(4);
            if (!seen.add(rawId)) continue;
            String imageTag = firstRaw(cards.group(5), "<img\\b[^>]*>");
            String title = cleanMarkup(attribute(imageTag, "title"));
            if (title.isEmpty()) title = cleanMarkup(attribute(imageTag, "alt"));
            if (title.isEmpty()) continue;
            result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title,
                    absolute(imageUrl(imageTag)), "", new ArrayList<String>()));
        }
        return result;
    }

    static boolean hasCatalogMarker(String html) {
        Matcher links = ALBUM_LINK.matcher(html == null ? "" : html);
        while (links.find()) {
            if (IMAGE_TAG.matcher(links.group(5)).find()) return true;
        }
        return false;
    }

    private List<ComicModels.ComicSummary> requireCatalogCards(String html) throws IOException {
        List<ComicModels.ComicSummary> result = parseCards(html);
        if (result.isEmpty()) throw new IOException(config.name + " 漫画列表解析失败");
        return result;
    }

    private String detailScope(String html) {
        int start = html == null ? -1 : html.indexOf("book-name");
        if (start < 0) return html == null ? "" : html;
        int end = html.indexOf("class=\"episode\"", start);
        if (end < 0) end = Math.min(html.length(), start + 50000);
        return html.substring(start, end);
    }

    private static String episodeScope(String html) {
        String source = html == null ? "" : html;
        Matcher opening = Pattern.compile("<div\\b[^>]*class\\s*=\\s*([\"'])[^\"']*\\bepisode\\b[^\"']*\\1[^>]*>",
                Pattern.CASE_INSENSITIVE).matcher(source);
        if (!opening.find()) return "";
        Matcher tags = Pattern.compile("</?div\\b[^>]*>", Pattern.CASE_INSENSITIVE).matcher(source);
        tags.region(opening.start(), source.length());
        int depth = 0;
        while (tags.find()) {
            if (tags.group().startsWith("</")) depth--;
            else depth++;
            if (depth == 0) return source.substring(opening.end(), tags.start());
        }
        return source.substring(opening.end());
    }

    private static String firstValue(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group(1) : "";
    }

    private static String absolute(String baseUrl, String value) {
        String url = decode(value).trim();
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        return baseUrl + (url.startsWith("/") ? url : "/" + url);
    }

    private List<String> linkTexts(String html, String hrefToken) {
        List<String> result = new ArrayList<>();
        Matcher links = ANCHOR.matcher(html == null ? "" : html);
        while (links.find()) {
            String href = decode(attribute(links.group(1), "href"));
            String text = clean(links.group(2));
            if (href.contains(hrefToken) && !TextUtils.isEmpty(text) && !result.contains(text)) result.add(text);
        }
        return result;
    }

    private List<String> tagTexts(String html) {
        List<String> result = new ArrayList<>();
        Matcher links = ANCHOR.matcher(html == null ? "" : html);
        while (links.find()) {
            String href = decode(attribute(links.group(1), "href"));
            String classes = attribute(links.group(1), "class");
            if (!href.contains("/search/photos") || href.contains("main_tag=2")
                    || (!classes.contains("tag") && !href.contains("search_query="))) continue;
            String text = clean(links.group(2));
            if (!TextUtils.isEmpty(text) && !result.contains(text)) result.add(text);
        }
        return result;
    }

    private static String imageUrl(String tag) {
        String url = attribute(tag, "data-original");
        if (url.isEmpty()) url = attribute(tag, "data-src");
        if (url.isEmpty()) url = attribute(tag, "src");
        return decode(url).trim();
    }

    private String pageUrl(String url, int page) {
        String cleanUrl = url.replaceAll("([?&])page=\\d+&?", "$1").replaceAll("[?&]+$", "");
        return cleanUrl + (cleanUrl.contains("?") ? "&" : "?") + "page=" + Math.max(1, page);
    }

    private boolean isCatalogPath(String value) {
        return isCatalogPath(value, config.baseUrl);
    }

    private static boolean isCatalogPath(String value, String baseUrl) {
        if (value == null || value.trim().isEmpty() || "all".equals(value)) return false;
        String path = decode(value).trim();
        return path.startsWith("/search/photos") || path.startsWith("/albums")
                || path.startsWith(baseUrl + "/search/photos")
                || path.startsWith(baseUrl + "/albums");
    }

    static String parseCover(String html, String rawId) {
        String fallback = "";
        Matcher images = IMAGE_TAG.matcher(html == null ? "" : html);
        Pattern albumImage = Pattern.compile("/media/albums/" + Pattern.quote(rawId)
                + "(?:[._/?#-]|$)", Pattern.CASE_INSENSITIVE);
        while (images.find()) {
            String tag = images.group();
            String url = imageUrl(tag);
            if (!albumImage.matcher(url).find()) continue;
            if ("album_photo_cover".equals(attribute(tag, "id"))) return url;
            if (fallback.isEmpty()) fallback = url;
        }
        return fallback;
    }

    private static String normalizeThemeLabel(String value) {
        if (value.contains("熱門成人主題") || value.contains("热门成人主题")) return "热门";
        if (value.contains("類別") || value.contains("类别")) return "类别";
        if (value.contains("漫畫排行榜") || value.contains("漫画排行榜")) return "排行榜";
        if (value.contains("主題A漫") || value.contains("主题A漫")) return "主题";
        if (value.contains("角色") && value.contains("扮演")) return "角色";
        if (value.toUpperCase(java.util.Locale.US).contains("PLAY")) return "特殊";
        return value;
    }

    private static String cleanMarkup(String value) {
        return decode(value == null ? "" : value.replaceAll("<[^>]+>", " "))
                .replaceAll("\\s+", " ").trim();
    }

    private String rawComicId(String value) {
        if (value == null) return "";
        if (value.startsWith(PREFIX)) value = value.substring(PREFIX.length());
        Matcher matcher = Pattern.compile("(?:/album/)?(\\d+)").matcher(value);
        return matcher.find() ? matcher.group(1) : "";
    }

    private String fetch(String url) throws IOException {
        if (browserSession != null && isMainSite(url)) return browserSession.fetch(url);
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(25000);
        connection.setRequestProperty("User-Agent", UA);
        connection.setRequestProperty("Referer", config.referer);
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
        try {
            int code = connection.getResponseCode();
            if (code < 200 || code >= 400) throw new IOException(config.name + " HTTP " + code);
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

    private boolean isMainSite(String value) {
        try {
            String host = new URL(value).getHost();
            return config.domain.equalsIgnoreCase(host)
                    || host.toLowerCase(java.util.Locale.US).endsWith("." + config.domain.toLowerCase(java.util.Locale.US));
        } catch (Exception ignored) {
            return false;
        }
    }

    private String meta(String html, String key) {
        Matcher tags = Pattern.compile("<meta\\b[^>]*>", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        while (tags.find()) {
            String tag = tags.group();
            if (key.equalsIgnoreCase(attribute(tag, "property")) || key.equalsIgnoreCase(attribute(tag, "name"))) {
                return clean(attribute(tag, "content"));
            }
        }
        return "";
    }

    private static String first(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group(1) : "";
    }

    private String firstRaw(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group() : "";
    }

    private static String attribute(String tag, String name) {
        Matcher matcher = Pattern.compile("\\b" + Pattern.quote(name)
                + "\\s*=\\s*([\"'])([\\s\\S]*?)\\1", Pattern.CASE_INSENSITIVE).matcher(tag == null ? "" : tag);
        return matcher.find() ? decode(matcher.group(2)) : "";
    }

    private String absolute(String value) {
        if (value == null || value.isEmpty()) return "";
        String url = decode(value).trim();
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        return config.baseUrl + (url.startsWith("/") ? url : "/" + url);
    }

    private String clean(String value) {
        if (value == null) return "";
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            return Html.fromHtml(value, Html.FROM_HTML_MODE_LEGACY).toString().replaceAll("\\s+", " ").trim();
        }
        return Html.fromHtml(value).toString().replaceAll("\\s+", " ").trim();
    }

    private static String decode(String value) {
        return value == null ? "" : value.replace("&amp;", "&").replace("&quot;", "\"")
                .replace("&#39;", "'").replace("&nbsp;", " ");
    }

    private static String trimSlash(String value) {
        String result = value == null ? "" : value.trim();
        while (result.endsWith("/")) result = result.substring(0, result.length() - 1);
        return result;
    }
}
