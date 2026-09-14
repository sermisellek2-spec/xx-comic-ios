package com.xxcomic.source;

import android.net.Uri;
import android.os.Build;
import android.text.Html;
import android.text.TextUtils;

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
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class BaoziComicSource implements ComicSource {
    private static final String SOURCE_ID = "baozimh";
    private static final String DESKTOP_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern CARD_PATTERN = Pattern.compile(
            "<div class=\"comics-card[\\s\\S]*?<a href=\"([^\"]+)\" title=\"([^\"]+)\"[\\s\\S]*?src=\"([^\"]+)\"[\\s\\S]*?<small class=\"tags text-truncate\">([\\s\\S]*?)</small>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern META_PATTERN = Pattern.compile(
            "<meta[^>]+(?:name|property|data-hid)=\"([^\"]+)\"[^>]+content=\"([^\"]*)\"",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<a href=\"([^\"]*page_direct[^\"]*)\"[^>]*class=\"comics-chapters__item\"[\\s\\S]*?<span[^>]*>([\\s\\S]*?)</span>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern IMAGE_PATTERN = Pattern.compile(
            "<amp-img[^>]+(?:data-src|src)=\"(https://[^\"]+?\\.(?:jpg|jpeg|png|webp)[^\"]*)\"",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern NEXT_PAGE_PATTERN = Pattern.compile(
            "<div class=\"next_chapter\">[\\s\\S]*?<a href=\"([^\"]+)\"",
            Pattern.CASE_INSENSITIVE);
    private static final List<String> SITE_CATEGORIES = Arrays.asList(
            "国漫", "日本", "韩国", "欧美",
            "连载中", "已完结");
    private final SourceConfig config;

    public BaoziComicSource() {
        this(SourceConfig.baozi(true));
    }

    public BaoziComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.baozi(true) : config;
    }

    @Override
    public String id() {
        return SOURCE_ID;
    }

    @Override
    public String name() {
        return config.name;
    }

    @Override
    public String domain() {
        return config.domain;
    }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return parseCards(fetch(buildLatestUrl(page)));
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        String encoded = java.net.URLEncoder.encode(keyword == null ? "" : keyword, "UTF-8");
        return parseCards(fetch(absolute(config.route("search")
                .replace("{keyword}", encoded)
                .replace("{page}", String.valueOf(page))
                .replace("{pageQuery}", page > 1 ? "&page=" + page : ""))));
    }

    @Override
    public List<String> categories() throws IOException {
        return new ArrayList<>(SITE_CATEGORIES);
    }

    @Override
    public List<ComicModels.FilterGroup> filterGroups() {
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        groups.add(SourceFilters.group("region", "地区",
                "全部", "all", "国漫", "cn", "日本", "jp", "韩国", "kr", "欧美", "en"));
        groups.add(SourceFilters.group("state", "状态",
                "全部", "all", "连载中", "serial", "已完结", "pub"));
        groups.add(SourceFilters.group("type", "题材",
                "全部", "all", "恋爱", "lianai", "纯爱", "chunai", "古风", "gufeng",
                "异能", "yineng", "悬疑", "xuanyi", "剧情", "juqing", "科幻", "kehuan",
                "奇幻", "qihuan", "玄幻", "xuanhuan", "穿越", "chuanyue", "冒险", "mouxian",
                "推理", "tuili", "武侠", "wuxia", "格斗", "gedou", "战争", "zhanzheng",
                "热血", "rexie", "搞笑", "gaoxiao", "大女主", "danuzhu", "都市", "dushi",
                "总裁", "zongcai", "后宫", "hougong", "日常", "richang", "韩漫", "hanman",
                "少年", "shaonian", "其它", "qita"));
        groups.add(SourceFilters.group("filter", "字母",
                "全部", "*", "ABCD", "ABCD", "EFGH", "EFGH", "IJKL", "IJKL",
                "MNOP", "MNOP", "QRST", "QRST", "UVW", "UVW", "XYZ", "XYZ", "0-9", "0-9"));
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        String safeRegion = safeRegion(region);
        String safeState = safeState(state);
        if (page > 1) {
            String api = config.route("categoryApi");
            if (!api.isEmpty()) {
                return parseApiCards(fetch(buildCategoryUrl(api, "all", safeRegion, safeState, "*", page)));
            }
        }
        return parseCards(fetch(buildCategoryUrl(config.route("category"), "all", safeRegion, safeState, "*", page)));
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        String region = SourceFilters.value(filters, "region", "all");
        String state = SourceFilters.value(filters, "state", "all");
        String type = SourceFilters.value(filters, "type", "all");
        String filter = SourceFilters.value(filters, "filter", "*");
        String route = page > 1 && !TextUtils.isEmpty(config.route("categoryApi"))
                ? config.route("categoryApi") : config.route("category");
        String body = fetch(buildCategoryUrl(route, type, region, state, filter, page));
        return page > 1 && route.equals(config.route("categoryApi")) ? parseApiCards(body) : parseCards(body);
    }

    private String buildCategoryUrl(String route, String type, String region, String state, String filter, int page) {
        String path = route.replace("{region}", region).replace("{state}", state)
                .replace("{type}", type).replace("{filter}", filter)
                .replace("{page}", String.valueOf(page))
                .replace("{pageQuery}", page > 1 ? "&page=" + page : "");
        return withCategoryFilters(absolute(path), type, region, state, filter, page);
    }

    static String withCategoryFilters(String url, String type, String region, String state, String filter, int page) {
        int fragmentStart = url.indexOf('#');
        String fragment = fragmentStart >= 0 ? url.substring(fragmentStart) : "";
        String withoutFragment = fragmentStart >= 0 ? url.substring(0, fragmentStart) : url;
        int queryStart = withoutFragment.indexOf('?');
        String base = queryStart >= 0 ? withoutFragment.substring(0, queryStart) : withoutFragment;
        String query = queryStart >= 0 ? withoutFragment.substring(queryStart + 1) : "";
        List<String> parts = new ArrayList<>();
        if (!query.isEmpty()) {
            for (String part : query.split("&")) {
                if (part.isEmpty()) continue;
                int separator = part.indexOf('=');
                String key = separator >= 0 ? part.substring(0, separator) : part;
                if (!"type".equals(key) && !"region".equals(key) && !"state".equals(key)
                        && !"filter".equals(key) && !"page".equals(key)) {
                    parts.add(part);
                }
            }
        }
        parts.add("type=" + type);
        parts.add("region=" + region);
        parts.add("state=" + state);
        parts.add("filter=" + filter);
        if (page > 1) parts.add("page=" + page);
        StringBuilder result = new StringBuilder(base).append('?');
        for (int i = 0; i < parts.size(); i++) {
            if (i > 0) result.append('&');
            result.append(parts.get(i));
        }
        return result.append(fragment).toString();
    }

    private String safeRegion(String value) {
        if (value == null || value.isEmpty()) value = "all";
        String mapped = config.filter("region." + value);
        return mapped.isEmpty() ? "all" : mapped;
    }

    private String safeState(String value) {
        if (value == null || value.isEmpty()) value = "all";
        String mapped = config.filter("state." + value);
        return mapped.isEmpty() ? "all" : mapped;
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String html = fetch(absolute(config.route("detail").replace("{comicId}", comicId)));
        String title = meta(html, "og:novel:book_name");
        String author = meta(html, "og:novel:author");
        String status = meta(html, "og:novel:status");
        String description = meta(html, "og:description");
        String latest = meta(html, "og:novel:latest_chapter_name");
        String cover = cleanUrl(meta(html, "og:image"));
        String categories = meta(html, "og:novel:category");

        List<String> tags = new ArrayList<>();
        if (!categories.isEmpty()) {
            for (String tag : categories.split(",")) {
                String cleaned = clean(tag);
                if (!cleaned.startsWith("types.") && !cleaned.isEmpty()) tags.add(cleaned);
            }
        }

        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, comicId, title, cover, latest, tags);
        return new ComicModels.ComicDetail(summary, author, status, description, latest, new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String html = fetch(absolute(config.route("detail").replace("{comicId}", comicId)));
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        Matcher matcher = CHAPTER_PATTERN.matcher(html);
        while (matcher.find()) {
            String url = absolute(decode(matcher.group(1)));
            String chapterTitle = clean(matcher.group(2));
            int sectionSlot = intQuery(url, "section_slot");
            int chapterSlot = intQuery(url, "chapter_slot");
            chapters.add(new ComicModels.Chapter(sectionSlot + "_" + chapterSlot, chapterTitle, url, sectionSlot, chapterSlot));
        }
        Collections.sort(chapters, new Comparator<ComicModels.Chapter>() {
            @Override
            public int compare(ComicModels.Chapter a, ComicModels.Chapter b) {
                if (a.sectionSlot != b.sectionSlot) return a.sectionSlot - b.sectionSlot;
                return a.chapterSlot - b.chapterSlot;
            }
        });
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String html = fetch(absolute(chapterUrl));
        String title = titleFromHtml(html);
        List<String> imageUrls = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = IMAGE_PATTERN.matcher(html);
        while (matcher.find()) {
            String url = cleanUrl(decode(matcher.group(1)));
            if (url.contains("/scomic/") && seen.add(url)) imageUrls.add(url);
        }
        String nextPage = "";
        Matcher next = NEXT_PAGE_PATTERN.matcher(html);
        if (next.find()) nextPage = absolute(decode(next.group(1)));
        return new ComicModels.ChapterPage(chapterUrl, title, imageUrls, nextPage);
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
        Matcher matcher = CARD_PATTERN.matcher(html);
        while (matcher.find()) {
            String href = decode(matcher.group(1));
            String title = clean(matcher.group(2));
            String cover = cleanUrl(decode(matcher.group(3)));
            String subtitle = clean(matcher.group(4));
            summaries.add(new ComicModels.ComicSummary(SOURCE_ID, comicIdFromHref(href), title, cover, subtitle, parseTags(subtitle)));
        }
        return summaries;
    }

    private List<ComicModels.ComicSummary> parseApiCards(String json) {
        List<ComicModels.ComicSummary> summaries = new ArrayList<>();
        try {
            JSONArray items = new JSONObject(json).optJSONArray("items");
            if (items == null) return summaries;
            for (int i = 0; i < items.length(); i++) {
                JSONObject item = items.getJSONObject(i);
                String id = item.optString("comic_id");
                String title = item.optString("name");
                String author = item.optString("author");
                String cover = item.optString("topic_img");
                List<String> tags = new ArrayList<>();
                JSONArray typeNames = item.optJSONArray("type_names");
                if (typeNames != null) {
                    for (int j = 0; j < typeNames.length(); j++) {
                        String tag = clean(typeNames.optString(j));
                        if (!tag.isEmpty() && !tags.contains(tag)) tags.add(tag);
                    }
                }
                if (!id.isEmpty()) summaries.add(new ComicModels.ComicSummary(SOURCE_ID, id, title, coverUrl(cover), author, tags));
            }
        } catch (Exception ignored) {
        }
        return summaries;
    }

    private List<String> parseTags(String value) {
        List<String> tags = new ArrayList<>();
        if (value == null) return tags;
        for (String part : value.split("[,，/|·\\s]+")) {
            String tag = clean(part);
            if (!tag.isEmpty() && !tag.contains("最新") && !tag.contains("更新") && !tags.contains(tag)) tags.add(tag);
        }
        return tags;
    }

    private String fetch(String url) throws IOException {
        return fetch(url, 0);
    }

    private String fetch(String url, int redirects) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(15000);
        connection.setRequestProperty("User-Agent", DESKTOP_USER_AGENT);
        connection.setRequestProperty("Referer", config.referer);
        int code = connection.getResponseCode();
        if (code >= 300 && code < 400 && redirects < 5) {
            String location = connection.getHeaderField("Location");
            connection.disconnect();
            if (location != null && !location.isEmpty()) return fetch(absolute(location), redirects + 1);
        }
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

    private String meta(String html, String key) {
        Matcher matcher = META_PATTERN.matcher(html);
        while (matcher.find()) {
            if (key.equals(matcher.group(1))) return clean(matcher.group(2));
        }
        return "";
    }

    private String titleFromHtml(String html) {
        Matcher matcher = Pattern.compile("<title>([\\s\\S]*?)</title>", Pattern.CASE_INSENSITIVE).matcher(html);
        return matcher.find() ? clean(matcher.group(1)) : "";
    }

    private String comicIdFromHref(String href) {
        int index = href.lastIndexOf("/comic/");
        if (index >= 0) return href.substring(index + 7);
        return href.replace("/comic/", "");
    }

    private String absolute(String url) {
        url = SourceConfig.migrateBaoziUrl(url);
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        if (url.startsWith("/")) return config.baseUrl + url;
        return config.baseUrl + "/" + url;
    }

    private String buildLatestUrl(int page) {
        String path = config.route("latest")
                .replace("{page}", String.valueOf(page))
                .replace("{pagePath}", page <= 1 ? "" : "/" + page)
                .replace("{pageQuery}", page <= 1 ? "" : "?page=" + page);
        return absolute(path);
    }

    private int intQuery(String url, String key) {
        try {
            String value = Uri.parse(url).getQueryParameter(key);
            return value == null ? 0 : Integer.parseInt(value);
        } catch (NumberFormatException ignored) {
            return 0;
        }
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
        String decoded = decode(value);
        int amp = decoded.indexOf("&");
        return amp > 0 ? decoded.substring(0, amp) : decoded;
    }

    private String coverUrl(String topicImg) {
        if (topicImg == null || topicImg.isEmpty()) return "";
        if (topicImg.startsWith("http://") || topicImg.startsWith("https://")) return topicImg;
        return "https://static-tw.baozimh.com/cover/" + topicImg + "?w=285&h=375&q=100";
    }
}
