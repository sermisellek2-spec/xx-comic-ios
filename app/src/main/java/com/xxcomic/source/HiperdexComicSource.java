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
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class HiperdexComicSource implements ComicSource {
    private static final String SOURCE_ID = "hiperdex";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern META_PATTERN = Pattern.compile(
            "<meta[^>]+(?:property|name)=\"([^\"]+)\"[^>]+content=\"([^\"]*)\"",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern IMAGE_TAG_PATTERN = Pattern.compile(
            "<img\\b[^>]*>",
            Pattern.CASE_INSENSITIVE);
    private static final List<String> SITE_CATEGORIES = Arrays.asList("Manhwa", "Webtoon", "Romance", "Drama");

    private final SourceConfig config;

    public HiperdexComicSource() {
        this(SourceConfig.hiperdex(true));
    }

    public HiperdexComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.hiperdex(true) : config;
    }

    @Override public String id() { return SOURCE_ID; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return parseCards(fetch(buildLatestUrl(page)));
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        String encoded = URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8").replace("+", "%20");
        String route = config.route("search")
                .replace("{keyword}", encoded)
                .replace("{pageQuery}", page > 1 ? "&paged=" + page : "")
                .replace("{page}", String.valueOf(page));
        return parseCards(fetch(absolute(route)));
    }

    @Override
    public List<String> categories() {
        return new ArrayList<>(SITE_CATEGORIES);
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        String genre = genreFor(region, state);
        String path = config.route("category")
                .replace("{genrePath}", TextUtils.isEmpty(genre) ? "" : genre + "/")
                .replace("{pagePath}", page > 1 ? "page/" + page + "/" : "")
                .replace("{page}", String.valueOf(page));
        return parseCards(fetch(absolute(path)));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        String title = clean(meta(html, "og:title"));
        if (TextUtils.isEmpty(title)) title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        title = title.replace(" - HiperDEX", "").trim();
        String cover = cleanUrl(meta(html, "og:image"));
        String description = clean(meta(html, "og:description"));
        if (TextUtils.isEmpty(description)) description = clean(first(html, "<div[^>]+class=\"[^\"]*summary__[^\"]*\"[^>]*>([\\s\\S]*?)</div>"));
        String author = clean(first(html, "(?:Author|Artist)[\\s\\S]{0,200}?<a[^>]*>([\\s\\S]*?)</a>"));
        String status = clean(first(html, "Status[\\s\\S]{0,200}?<a[^>]*>([\\s\\S]*?)</a>"));
        String latest = latestChapterTitle(html);
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, latest, new ArrayList<String>());
        return new ComicModels.ComicDetail(summary, author, status, description, latest, new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId)));
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = Pattern.compile(
                "<a[^>]+href=\"([^\"]*/manga/" + Pattern.quote(rawId) + "/[^\"]+/)\"[^>]*>([\\s\\S]*?)</a>",
                Pattern.CASE_INSENSITIVE).matcher(html);
        int index = 0;
        while (matcher.find()) {
            String href = cleanUrl(decode(matcher.group(1)));
            String slug = rawChapterSlug(href);
            String title = clean(matcher.group(2));
            if (TextUtils.isEmpty(slug) || TextUtils.isEmpty(title) || !seen.add(href)) continue;
            chapters.add(new ComicModels.Chapter(slug, title, href, 0, index++));
        }
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String html = fetch(absolute(chapterUrl));
        String title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        List<String> images = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        String block = firstRaw(html, "<div[^>]+class=\"[^\"]*reading-content[^\"]*\"[\\s\\S]*?(?=<div[^>]+class=\"[^\"]*comments-area|</body>|$)");
        if (TextUtils.isEmpty(block)) block = html;
        Matcher matcher = IMAGE_TAG_PATTERN.matcher(block);
        while (matcher.find()) {
            String tag = matcher.group(0);
            String image = imageUrlFromTag(tag);
            if (isReaderImage(image) && seen.add(image)) images.add(image);
        }
        if (images.isEmpty()) throw new IOException("HiperDEX chapter image list empty: " + chapterUrl);
        return new ComicModels.ChapterPage(chapterUrl, title, images, "");
    }

    @Override
    public boolean healthCheck() {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(config.baseUrl + "/").openConnection();
            connection.setRequestMethod("HEAD");
            connection.setConnectTimeout(5000);
            connection.setReadTimeout(5000);
            connection.setRequestProperty("User-Agent", UA);
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
        Matcher matcher = Pattern.compile(
                "<div[^>]+class=\"[^\"]*(?:page-listing-item|manga__item|manga-item)[^\"]*\"[\\s\\S]*?(?=<div[^>]+class=\"[^\"]*(?:page-listing-item|manga__item|manga-item)[^\"]*\"|</main>|</body>|$)",
                Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        while (matcher.find()) addCard(result, seen, matcher.group(0));
        if (!result.isEmpty()) return result;

        Matcher linkMatcher = Pattern.compile("<a[^>]+href=\"([^\"]*/manga/[^\"]+/)\"[^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        while (linkMatcher.find()) {
            String href = cleanUrl(decode(linkMatcher.group(1)));
            String rawId = rawComicId(href);
            String title = clean(linkMatcher.group(2));
            if (!TextUtils.isEmpty(rawId) && !TextUtils.isEmpty(title) && seen.add(rawId)) {
                result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, "", "", new ArrayList<String>()));
            }
        }
        return result;
    }

    private void addCard(List<ComicModels.ComicSummary> result, Set<String> seen, String block) {
        String href = cleanUrl(decode(first(block, "<a[^>]+href=\"([^\"]*/manga/[^\"]+/)\"")));
        String rawId = rawComicId(href);
        if (TextUtils.isEmpty(rawId) || !seen.add(rawId)) return;
        String imageTag = firstRaw(block, "<img[^>]+>");
        String title = clean(first(block, "<h[23][^>]*>[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>"));
        if (TextUtils.isEmpty(title)) title = clean(attr(imageTag, "alt"));
        String cover = cleanUrl(decode(first(imageTag, "(?:data-src|data-lazy-src|src)=\"([^\"]+)\"")));
        String latest = clean(first(block, "<a[^>]+href=\"[^\"]*/manga/" + Pattern.quote(rawId) + "/[^\"]+/\"[^>]*>(Chapter[^<]*)</a>"));
        result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, latest, new ArrayList<String>()));
    }

    private String buildLatestUrl(int page) {
        return absolute(config.route("latest")
                .replace("{pageQuery}", page > 1 ? "&paged=" + page : "")
                .replace("{page}", String.valueOf(page)));
    }

    private String genreFor(String region, String state) {
        String key = TextUtils.isEmpty(region) || "all".equals(region) ? state : region;
        if (TextUtils.isEmpty(key) || "all".equals(key)) return "";
        String genre = config.filter("genre." + key);
        return TextUtils.isEmpty(genre) ? "" : genre;
    }

    private String latestChapterTitle(String html) {
        Matcher matcher = Pattern.compile("<a[^>]+href=\"[^\"]*/manga/[^\"]+/[^\"]+/\"[^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE).matcher(html == null ? "" : html);
        return matcher.find() ? clean(matcher.group(1)) : "";
    }

    private boolean isReaderImage(String url) {
        if (TextUtils.isEmpty(url)) return false;
        String lower = url.toLowerCase();
        if (!(lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".png") || lower.endsWith(".webp") || lower.contains(".jpg?") || lower.contains(".jpeg?") || lower.contains(".png?") || lower.contains(".webp?"))) return false;
        return !lower.contains("logo") && !lower.contains("avatar") && !lower.contains("cover");
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

    private String meta(String html, String key) {
        Matcher matcher = META_PATTERN.matcher(html == null ? "" : html);
        while (matcher.find()) if (key.equals(matcher.group(1))) return clean(matcher.group(2));
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
        return first(html, name + "=\"([^\"]*)\"");
    }

    private String imageUrlFromTag(String tag) {
        String url = attr(tag, "data-src");
        if (TextUtils.isEmpty(url)) url = attr(tag, "data-lazy-src");
        if (TextUtils.isEmpty(url)) url = attr(tag, "src");
        return cleanUrl(url);
    }

    private String rawComicId(String value) {
        String raw = decode(value);
        if (raw.startsWith(PREFIX)) raw = raw.substring(PREFIX.length());
        int manga = raw.indexOf("/manga/");
        if (manga >= 0) raw = raw.substring(manga + 7);
        int slash = raw.indexOf('/');
        if (slash >= 0) raw = raw.substring(0, slash);
        return raw.trim();
    }

    private String rawChapterSlug(String value) {
        String raw = decode(value);
        if (raw.endsWith("/")) raw = raw.substring(0, raw.length() - 1);
        int slash = raw.lastIndexOf('/');
        return slash >= 0 ? raw.substring(slash + 1).trim() : raw.trim();
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
        String decoded = decode(value).replaceAll("<script[\\s\\S]*?</script>", " ").replaceAll("<style[\\s\\S]*?</style>", " ");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            return Html.fromHtml(decoded, Html.FROM_HTML_MODE_LEGACY).toString().replaceAll("\\s+", " ").trim();
        }
        return Html.fromHtml(decoded).toString().replaceAll("\\s+", " ").trim();
    }

    private String decode(String value) {
        return value == null ? "" : value.replace("&amp;", "&").replace("&quot;", "\"").replace("\\/", "/");
    }

    private String cleanUrl(String value) {
        String decoded = decode(value).trim();
        if (decoded.startsWith("//")) decoded = "https:" + decoded;
        int quote = decoded.indexOf('"');
        if (quote >= 0) decoded = decoded.substring(0, quote);
        return decoded;
    }
}
