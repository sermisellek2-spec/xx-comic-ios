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
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Mhua5ComicSource implements ComicSource {
    private static final String SOURCE_ID = "mhua5";
    private static final String BASE_URL = "https://www.mhua5.com";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String DESKTOP_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern COMMON_CARD_PATTERN = Pattern.compile(
            "<div class=\"common-comic-item\"[\\s\\S]*?<a class=\"cover\" href=\"([^\"]+)\"[\\s\\S]*?<img([^>]*)>[\\s\\S]*?<p class=\"comic-feature\">([\\s\\S]*?)</p>[\\s\\S]*?<p class=\"comic-update\">[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern HOME_CARD_PATTERN = Pattern.compile(
            "<a href=\"(/index\\.php/comic/[^\"]+)\"[^>]*>\\s*<img([^>]*)>[\\s\\S]*?</a>[\\s\\S]*?<p class=\"comic__title\">[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern MOBILE_GRID_PATTERN = Pattern.compile(
            "<li class=\"comic-item\"[\\s\\S]*?<a href=\"([^\"]+)\"[^>]*>\\s*<img([^>]*)>[\\s\\S]*?</a>[\\s\\S]*?<p class=\"comic-name\">([\\s\\S]*?)</p>[\\s\\S]*?<p class=\"comic-tip\">([\\s\\S]*?)</p>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern MOBILE_SEARCH_PATTERN = Pattern.compile(
            "<div class=\"comic-list-item[^\"]*\"[\\s\\S]*?<a class=\"cover\" href=\"([^\"]+)\"[^>]*>\\s*<img([^>]*)>[\\s\\S]*?</a>[\\s\\S]*?<p class=\"comic-name\">[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>[\\s\\S]*?</p>[\\s\\S]*?<p class=\"comic-update-at\">([\\s\\S]*?)</p>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<li class=\"j-chapter-item[\\s\\S]*?<a class=\"j-chapter-link\" href=\"([^\"]+)\"[^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern MOBILE_CHAPTER_PATTERN = Pattern.compile(
            "<li class=\"chapter-item[^\"]*\"[\\s\\S]*?<a href=\"([^\"]+)\"[^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern IMAGE_PATTERN = Pattern.compile(
            "<img class=\"lazy-read\"[^>]+data-original=\"(https?://[^\"]+)\"",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern READER_IMAGE_PATTERN = Pattern.compile(
            "<img[^>]+(?:data-original|data-src|src)=\"([^\"]+)\"[^>]*>",
            Pattern.CASE_INSENSITIVE);
    private static final List<String> SITE_CATEGORIES = Arrays.asList("国漫", "日本", "韩国", "欧美", "连载中", "已完结");
    private final SourceConfig config;

    public Mhua5ComicSource() {
        this(SourceConfig.mhua5(true));
    }

    public Mhua5ComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.mhua5(true) : config;
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
        return parseCards(fetch(categoryUrl("all", "all", page)));
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        String encoded = java.net.URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        String url = absolute(config.route("search")
                .replace("{keyword}", encoded)
                .replace("{page}", String.valueOf(page))
                .replace("{pagePath}", page <= 1 ? "" : "&page=" + page)
                .replace("{pageQuery}", page <= 1 ? "" : "&page=" + page));
        return parseCards(fetch(url));
    }

    @Override
    public List<String> categories() {
        return new ArrayList<>(SITE_CATEGORIES);
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        return parseCards(fetch(categoryUrl(region, state, page)));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        String title = first(html, "<p class=\"comic-title j-comic-title\">([\\s\\S]*?)</p>");
        String cover = first(html, "<div class=\"de-info__cover\">[\\s\\S]*?<img[^>]+src=\"([^\"]+)\"");
        String author = first(html, "<div class=\"comic-author\">[\\s\\S]*?<span class=\"name\">[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>");
        String status = first(html, "<div class=\"de-chapter__title\">\\s*<span>([\\s\\S]*?)</span>");
        String latest = first(html, "<span class=\"update-time\">([\\s\\S]*?)</span>");
        String description = first(html, "<p class=\"intro-total\">([\\s\\S]*?)</p>");
        if (TextUtils.isEmpty(description)) description = first(html, "<p class=\"intro\">([\\s\\S]*?)(?:<p class=\"show\"|</p>)");
        if (TextUtils.isEmpty(title)) title = first(html, "<h1 class=\"comic-name\">([\\s\\S]*?)</h1>");
        if (TextUtils.isEmpty(cover)) cover = first(html, "<div class=\"box-back\"[^>]+background-image:\\s*url\\('([^']+)'\\)");
        if (TextUtils.isEmpty(author)) author = first(html, "<div class=\"au-name\">\\s*作者[:：]\\s*([\\s\\S]*?)</div>");
        if (TextUtils.isEmpty(description)) description = first(html, "<span class=\"comic-intro\">([\\s\\S]*?)</span>");
        if (TextUtils.isEmpty(latest)) latest = first(html, "<p class=\"comic-update-info\">([\\s\\S]*?)</p>");
        if (TextUtils.isEmpty(status) && latest.contains("：")) status = latest.substring(0, latest.indexOf("：")).trim();

        List<String> tags = new ArrayList<>();
        String tagBlock = first(html, "<span class=\"text\">题材:\\s*<b>([\\s\\S]*?)</b></span>");
        Matcher tagMatcher = Pattern.compile("<a[^>]*>([\\s\\S]*?)</a>").matcher(tagBlock);
        while (tagMatcher.find()) {
            String tag = clean(tagMatcher.group(1));
            if (!tag.isEmpty() && !tags.contains(tag)) tags.add(tag);
        }
        if (tags.isEmpty()) {
            String mobileTags = first(html, "<p class=\"comic-tags\">([\\s\\S]*?)</p>").replaceAll("<span[\\s\\S]*?</span>", " ");
            tags.addAll(parseTags(mobileTags));
        }

        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, clean(title), absolute(cover), clean(latest), tags);
        return new ComicModels.ComicDetail(summary, clean(author), clean(status), clean(description), clean(latest), new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawComicId(comicId))));
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CHAPTER_PATTERN.matcher(html);
        int index = 0;
        while (matcher.find()) {
            String href = decode(matcher.group(1));
            String title = clean(matcher.group(2));
            if (TextUtils.isEmpty(title) || !seen.add(href)) continue;
            chapters.add(new ComicModels.Chapter(rawChapterId(href), title, chapterUrl(href), 0, index++));
        }
        if (!chapters.isEmpty()) return chapters;

        Matcher mobileMatcher = MOBILE_CHAPTER_PATTERN.matcher(html);
        while (mobileMatcher.find()) {
            String href = decode(mobileMatcher.group(1));
            String title = clean(mobileMatcher.group(2));
            if (TextUtils.isEmpty(title) || !seen.add(href)) continue;
            chapters.add(new ComicModels.Chapter(rawChapterId(href), title, chapterUrl(href), 0, index++));
        }
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = chapterUrl(chapterUrl);
        String html = fetch(url);
        String title = clean(first(html, "<h1 class=\"comic-title\">[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>"));
        if (TextUtils.isEmpty(title)) title = first(html, "<h1 class=\"comic-name\">([\\s\\S]*?)</h1>");
        List<String> imageUrls = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = IMAGE_PATTERN.matcher(html);
        while (matcher.find()) {
            String imageUrl = cleanUrl(decode(matcher.group(1)));
            if (isReaderImage(imageUrl) && seen.add(imageUrl)) imageUrls.add(imageUrl);
        }
        if (imageUrls.isEmpty()) {
            String imageBlock = firstRaw(html, "<ul class=\"comic-list\"[\\s\\S]*?</ul>");
            if (TextUtils.isEmpty(imageBlock)) imageBlock = html;
            Matcher imageMatcher = READER_IMAGE_PATTERN.matcher(imageBlock);
            while (imageMatcher.find()) {
                String imageUrl = cleanUrl(imageUrlFromTag(imageMatcher.group(0)));
                if (isReaderImage(imageUrl) && seen.add(imageUrl)) imageUrls.add(imageUrl);
            }
        }
        String next = first(html, "<a class=\"rd-aside__item j-rd-next\" _href=\"([^\"]+)\"");
        if (TextUtils.isEmpty(next)) next = first(html, "<[^>]+class=\"[^\"]*next[^\"]*\"[^>]+_href=\"([^\"]*)\"");
        return new ComicModels.ChapterPage(url, title, imageUrls, TextUtils.isEmpty(next) ? "" : chapterUrl(next));
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
        Matcher common = COMMON_CARD_PATTERN.matcher(html);
        while (common.find()) {
            String href = decode(common.group(1));
            String rawId = rawComicId(href);
            if (rawId.isEmpty() || !seen.add(rawId)) continue;
            String imageTag = common.group(2);
            String title = clean(attr(imageTag, "alt"));
            String cover = imageUrlFromTag(imageTag);
            String feature = clean(common.group(3));
            String latest = clean(common.group(4));
            summaries.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, absolute(cover), clean(latest, feature), parseTags(feature)));
        }
        if (!summaries.isEmpty()) return summaries;

        Matcher mobileSearch = MOBILE_SEARCH_PATTERN.matcher(html);
        while (mobileSearch.find()) {
            String rawId = rawComicId(decode(mobileSearch.group(1)));
            if (rawId.isEmpty() || !seen.add(rawId)) continue;
            String imageTag = mobileSearch.group(2);
            String title = clean(mobileSearch.group(3));
            if (title.isEmpty()) title = clean(attr(imageTag, "alt"));
            String cover = imageUrlFromTag(imageTag);
            String latest = clean(mobileSearch.group(4));
            summaries.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, absolute(cover), latest, new ArrayList<String>()));
        }
        if (!summaries.isEmpty()) return summaries;

        Matcher mobileGrid = MOBILE_GRID_PATTERN.matcher(html);
        while (mobileGrid.find()) {
            String rawId = rawComicId(decode(mobileGrid.group(1)));
            if (rawId.isEmpty() || !seen.add(rawId)) continue;
            String imageTag = mobileGrid.group(2);
            String title = clean(mobileGrid.group(3));
            if (title.isEmpty()) title = clean(attr(imageTag, "alt"));
            String cover = imageUrlFromTag(imageTag);
            String latest = clean(mobileGrid.group(4));
            summaries.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, absolute(cover), latest, new ArrayList<String>()));
        }
        if (!summaries.isEmpty()) return summaries;

        Matcher home = HOME_CARD_PATTERN.matcher(html);
        while (home.find()) {
            String rawId = rawComicId(decode(home.group(1)));
            if (rawId.isEmpty() || !seen.add(rawId)) continue;
            String imageTag = home.group(2);
            String title = clean(home.group(3));
            if (title.isEmpty()) title = clean(attr(imageTag, "alt"));
            String cover = imageUrlFromTag(imageTag);
            summaries.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, absolute(cover), "", new ArrayList<String>()));
        }
        return summaries;
    }

    private String imageUrlFromTag(String imageTag) {
        String url = clean(attr(imageTag, "data-original"), attr(imageTag, "data-src"));
        if (TextUtils.isEmpty(url)) url = attr(imageTag, "src");
        return cleanUrl(decode(url));
    }

    private List<String> parseTags(String value) {
        if (TextUtils.isEmpty(value)) return Collections.emptyList();
        List<String> tags = new ArrayList<>();
        for (String part : value.split("[,，/|·\\s]+")) {
            String tag = clean(part);
            if (!tag.isEmpty() && tag.length() <= 4 && !tags.contains(tag)) tags.add(tag);
        }
        return tags;
    }

    private String categoryUrl(String region, String state, int page) {
        String path = config.route("category");
        String city = cityId(region);
        String finish = finishId(state);
        path = path.replace("{city}", city)
                .replace("{finish}", finish)
                .replace("{cityPath}", city.isEmpty() ? "" : "/city/" + city)
                .replace("{finishPath}", finish.isEmpty() ? "" : "/finish/" + finish)
                .replace("{page}", String.valueOf(page))
                .replace("{pagePath}", page <= 1 ? "" : "/page/" + page);
        return absolute(path);
    }

    private String cityId(String region) {
        if (region == null || region.isEmpty() || "all".equals(region)) return "";
        return config.filter("city." + region);
    }

    private String finishId(String state) {
        if (state == null || state.isEmpty() || "all".equals(state)) return "";
        return config.filter("finish." + state);
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
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html);
        return matcher.find() ? clean(matcher.group(1)) : "";
    }

    private String firstRaw(String html, String pattern) {
        Matcher matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html);
        return matcher.find() ? matcher.group(0) : "";
    }

    private String attr(String html, String name) {
        Matcher matcher = Pattern.compile(name + "=\"([^\"]*)\"", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? matcher.group(1) : "";
    }

    private String rawComicId(String comicIdOrHref) {
        if (comicIdOrHref == null) return "";
        String value = comicIdOrHref;
        if (value.startsWith(PREFIX)) value = value.substring(PREFIX.length());
        int index = value.lastIndexOf("/index.php/comic/");
        if (index >= 0) value = value.substring(index + 17);
        int slash = value.lastIndexOf('/');
        if (slash >= 0) value = value.substring(slash + 1);
        int query = value.indexOf('?');
        if (query >= 0) value = value.substring(0, query);
        return value.trim();
    }

    private String rawChapterId(String href) {
        String value = decode(href);
        int query = value.indexOf('?');
        if (query >= 0) value = value.substring(0, query);
        int slash = value.lastIndexOf('/');
        return slash >= 0 ? value.substring(slash + 1).trim() : value.trim();
    }

    private String chapterUrl(String value) {
        String decoded = decode(value);
        if (TextUtils.isEmpty(decoded)) return "";
        if (!decoded.contains("/") && decoded.matches("\\d+")) {
            String route = config.route("chapter").replace("{chapterId}", decoded);
            if (!TextUtils.isEmpty(route)) return absolute(route);
        }
        return absolute(decoded);
    }

    private boolean isReaderImage(String url) {
        return !TextUtils.isEmpty(url) && url.contains("/scomic/");
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
        String decoded = decode(value);
        int amp = decoded.indexOf("&");
        return amp > 0 ? decoded.substring(0, amp) : decoded;
    }
}
