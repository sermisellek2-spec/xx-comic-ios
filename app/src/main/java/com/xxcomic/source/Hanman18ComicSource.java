package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;
import android.util.Base64;

import net.sourceforge.pinyin4j.PinyinHelper;
import net.sourceforge.pinyin4j.format.HanyuPinyinOutputFormat;
import net.sourceforge.pinyin4j.format.HanyuPinyinToneType;
import net.sourceforge.pinyin4j.format.exception.BadHanyuPinyinOutputFormatCombination;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Hanman18ComicSource implements ComicSource {
    private static final String SOURCE_ID = "hanman18";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern CARD_PATTERN = Pattern.compile("<a[^>]+href=[\"']([^\"']*/manhwa/[^\"']+)[\"'][\\s\\S]{0,900}?<img([^>]*)>[\\s\\S]{0,900}?(?:<h[23][^>]*>|class=[\"'][^\"']*(?:title|name)[^\"']*[\"'][^>]*>)([\\s\\S]*?)(?:</h[23]>|</[^>]+>)", Pattern.CASE_INSENSITIVE);
    private static final Pattern META_PATTERN = Pattern.compile("<meta[^>]+(?:property|name)=[\"']([^\"']+)[\"'][^>]+content=[\"']([^\"']*)[\"']", Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile("<a[^>]+href=[\"']([^\"']*/manhwa/[^\"']+)[\"'][^>]*class=[\"']chapter_num[\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE);
    private static final Pattern IMG_TAG_PATTERN = Pattern.compile("<img\\b[^>]*>", Pattern.CASE_INSENSITIVE);
    private static final Pattern SLIDES_ARRAY_PATTERN = Pattern.compile("slides_p_path\\s*=\\s*\\[([\\s\\S]*?)\\]", Pattern.CASE_INSENSITIVE);
    private static final Pattern SLIDES_TOKEN_PATTERN = Pattern.compile("[\"']([A-Za-z0-9+/=]+)[\"']");

    private final SourceConfig config;

    public Hanman18ComicSource() {
        this(SourceConfig.hanman18(true));
    }

    public Hanman18ComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.hanman18(true) : config;
    }

    @Override public String id() { return SOURCE_ID; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return parseCards(fetch(listUrl(page)));
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        String encoded = URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        String json = fetch(absolute(config.route("search").replace("{keyword}", encoded)));
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        try {
            JSONArray data = new JSONObject(json).optJSONArray("data");
            if (data == null) return result;
            for (int i = 0; i < data.length(); i++) {
                JSONObject item = data.optJSONObject(i);
                if (item == null) continue;
                String name = item.optString("name");
                String title = clean(name);
                if (TextUtils.isEmpty(title)) continue;
                // Try the API slug first (e.g. "37925.html"); if its page has no chapter list,
                // fall back to the pinyin of the name (e.g. "meilixinshijie"). Encode both in the
                // comic id as "primary|pinyin" so chapters() can try each.
                String primary = rawComicId(item.optString("slug"));
                String pinyin = pinyinSlug(name);
                if (TextUtils.isEmpty(primary)) primary = pinyin;
                if (TextUtils.isEmpty(primary)) continue;
                String rawId = (!TextUtils.isEmpty(pinyin) && !pinyin.equalsIgnoreCase(primary))
                        ? primary + "|" + pinyin : primary;
                result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, "", clean(item.optString("otherNames")), new ArrayList<String>()));
            }
        } catch (Exception error) {
            throw new IOException("Hanman18 search parse failed", error);
        }
        return result;
    }

    @Override
    public List<String> categories() {
        return Collections.singletonList("全部");
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        if ("popular".equals(region)) {
            return page <= 1 ? parsePopular(fetch(absolute(config.route("home")))) : new ArrayList<>();
        }
        return latest(page);
    }

    // "受欢迎的" carousel on the home page: <h5>受欢迎的</h5> ... <div class="story_item"> cards.
    private List<ComicModels.ComicSummary> parsePopular(String html) {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        if (html == null) return result;
        Set<String> seen = new LinkedHashSet<>();
        String body = html.replaceAll("<!--[\\s\\S]*?-->", " ");
        Matcher section = Pattern.compile("<h5[^>]*>受欢迎的</h5>([\\s\\S]*?)(?=<h5[^>]*>|$)", Pattern.CASE_INSENSITIVE).matcher(body);
        String sectionBody = section.find() ? section.group(1) : "";
        Pattern itemPattern = Pattern.compile("<div class=\"story_item\"[\\s\\S]*?(?=<div class=\"story_item\"|$)", Pattern.CASE_INSENSITIVE);
        Matcher items = itemPattern.matcher(sectionBody);
        while (items.find()) {
            String block = items.group(0);
            Matcher a = Pattern.compile("<a[^>]+href=[\"']([^\"']*/manhwa/[^\"']+)[\"'][^>]*title=[\"']([^\"']*)[\"']", Pattern.CASE_INSENSITIVE).matcher(block);
            if (!a.find()) continue;
            String title = clean(a.group(2));
            if (TextUtils.isEmpty(title)) continue;
            String primary = rawComicId(a.group(1));
            String pinyin = pinyinSlug(a.group(2));
            if (TextUtils.isEmpty(primary)) primary = pinyin;
            if (TextUtils.isEmpty(primary) || !seen.add(primary)) continue;
            String rawId = (!TextUtils.isEmpty(pinyin) && !pinyin.equalsIgnoreCase(primary)) ? primary + "|" + pinyin : primary;
            String cover = imageUrlFromTag(firstRaw(block, "<img\\b[^>]*>"));
            String time = first(block, "<span>([^<]+)</span>");
            result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, time, new ArrayList<String>()));
        }
        return result;
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetchDetailHtml(rawId);
        String title = clean(meta(html, "og:title"));
        if (TextUtils.isEmpty(title)) title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        String cover = cleanUrl(meta(html, "og:image"));
        if (TextUtils.isEmpty(cover)) cover = imageUrlFromTag(firstRaw(html, "<img\\b[^>]*>"));
        String description = clean(meta(html, "og:description"));
        if (TextUtils.isEmpty(description)) description = clean(first(html, "<div[^>]+class=[\"'][^\"']*(?:summary|desc|intro)[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>"));
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, comicId, title, cover, "", new ArrayList<String>());
        return new ComicModels.ComicDetail(summary, "", "", description, "", new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String primary = rawComicId(comicId);
        List<ComicModels.Chapter> chapters = parseChapters(primary);
        if (chapters.isEmpty()) {
            String fallback = pinyinFallbackSlug(comicId);
            if (!TextUtils.isEmpty(fallback) && !fallback.equalsIgnoreCase(primary)) {
                chapters = parseChapters(fallback);
            }
        }
        return chapters;
    }

    // comic ids encode "primary|pinyin" (see search()); the pinyin part is a fallback slug for
    // when the primary alias page (e.g. "37925.html") has no chapter list.
    private String pinyinFallbackSlug(String value) {
        String raw = decode(value);
        if (raw.startsWith(PREFIX)) raw = raw.substring(PREFIX.length());
        int pipe = raw.indexOf('|');
        if (pipe < 0) return "";
        String fallback = raw.substring(pipe + 1);
        int slash = fallback.indexOf('/');
        if (slash >= 0) fallback = fallback.substring(0, slash);
        return fallback.trim();
    }

    private List<ComicModels.Chapter> parseChapters(String slug) throws IOException {
        String html = fetchDetailHtml(slug);
        String block = firstRaw(html, "<div[^>]+class=[\"']chapter_box[\"'][\\s\\S]*?</ul>\\s*</div>");
        if (TextUtils.isEmpty(block)) block = html;
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = CHAPTER_PATTERN.matcher(block);
        int index = 0;
        while (matcher.find()) {
            String href = cleanUrl(matcher.group(1));
            String title = clean(matcher.group(2));
            if (TextUtils.isEmpty(href) || TextUtils.isEmpty(title) || !seen.add(href)) continue;
            chapters.add(new ComicModels.Chapter(rawChapterId(href), title, absolute(href), 0, index++));
        }
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = absolute(chapterUrl);
        String html = fetch(url);
        String title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        List<String> images = extractSlideImages(html);
        if (images.isEmpty()) {
            Set<String> seen = new LinkedHashSet<>();
            Matcher matcher = IMG_TAG_PATTERN.matcher(html);
            while (matcher.find()) {
                String image = imageUrlFromTag(matcher.group(0));
                if (isReaderImage(image) && seen.add(image)) images.add(image);
            }
        }
        if (images.isEmpty()) throw new IOException("Hanman18 chapter image list empty: " + url);
        return new ComicModels.ChapterPage(url, title, images, "");
    }

    // Reader pages store image URLs as base64 tokens in `var slides_p_path = [ ... ]`;
    // JS does atob(token) and injects <img> into #chapter_boxImages at load. We mirror that here
    // (no WebView): pull the array, base64-decode each token, keep the first non-empty server list.
    private List<String> extractSlideImages(String html) {
        List<String> empty = new ArrayList<>();
        if (html == null) return empty;
        Matcher arrays = SLIDES_ARRAY_PATTERN.matcher(html);
        while (arrays.find()) {
            List<String> images = new ArrayList<>();
            Set<String> seen = new LinkedHashSet<>();
            Matcher token = SLIDES_TOKEN_PATTERN.matcher(arrays.group(1));
            while (token.find()) {
                String image = decodeBase64(token.group(1));
                if (!TextUtils.isEmpty(image) && image.startsWith("http") && seen.add(image)) {
                    images.add(image);
                }
            }
            if (!images.isEmpty()) return images;
        }
        return empty;
    }

    private String decodeBase64(String value) {
        try {
            return new String(Base64.decode(value, Base64.DEFAULT), "UTF-8").trim();
        } catch (Exception ignored) {
            return "";
        }
    }

    @Override
    public boolean healthCheck() {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(config.baseUrl + "/list-manga").openConnection();
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
        Matcher matcher = CARD_PATTERN.matcher(html == null ? "" : html);
        while (matcher.find()) {
            String href = cleanUrl(matcher.group(1));
            String rawId = rawComicId(href);
            String title = clean(matcher.group(3));
            if (TextUtils.isEmpty(rawId) || TextUtils.isEmpty(title) || !seen.add(rawId)) continue;
            String cover = imageUrlFromTag("<img " + matcher.group(2) + ">");
            result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, "", new ArrayList<String>()));
        }
        return result;
    }

    private String listUrl(int page) {
        String route = config.route("latest").replace("{pagePath}", page <= 1 ? "" : "/" + page).replace("{page}", String.valueOf(page));
        return absolute(route);
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

    // Some comics are reachable via alias slugs (e.g. "37925.html") that serve a redirect/landing
    // page with og tags but no chapter_box; the canonical slug (e.g. "meilixinshijie") serves the
    // real page. HttpURLConnection won't run JS, so detect the canonical slug from og:url /
    // <link rel=canonical> / meta refresh / window.location and re-fetch the canonical URL.
    private String fetchDetailHtml(String rawId) throws IOException {
        String url = absolute(config.route("detail").replace("{comicId}", rawId));
        String html = fetch(url);
        String canonical = resolveCanonicalSlug(html);
        if (TextUtils.isEmpty(canonical) || canonical.equalsIgnoreCase(rawId)) return html;
        String resolvedUrl = absolute(config.route("detail").replace("{comicId}", canonical));
        if (resolvedUrl.equals(url)) return html;
        return fetch(resolvedUrl);
    }

    private String resolveCanonicalSlug(String html) {
        if (html == null) return "";
        String slug = slugFromUrl(meta(html, "og:url"));
        if (!TextUtils.isEmpty(slug)) return slug;
        String link = firstRaw(html, "<link[^>]+rel=[\"']canonical[\"'][^>]*>");
        slug = slugFromUrl(attr(link, "href"));
        if (!TextUtils.isEmpty(slug)) return slug;
        String refresh = firstRaw(html, "<meta[^>]+http-equiv=[\"']refresh[\"'][^>]*>");
        String content = attr(refresh, "content");
        if (!TextUtils.isEmpty(content)) {
            Matcher m = Pattern.compile("url=([^\"'\\s]+)", Pattern.CASE_INSENSITIVE).matcher(content);
            if (m.find()) {
                slug = slugFromUrl(m.group(1));
                if (!TextUtils.isEmpty(slug)) return slug;
            }
        }
        Matcher loc = Pattern.compile("location(?:\\.href|\\.replace)?\\s*[=(]\\s*[\"']([^\"']+)[\"']", Pattern.CASE_INSENSITIVE).matcher(html);
        if (loc.find()) {
            slug = slugFromUrl(loc.group(1));
            if (!TextUtils.isEmpty(slug)) return slug;
        }
        return "";
    }

    private String slugFromUrl(String url) {
        if (url == null) return "";
        int m = url.indexOf("/manhwa/");
        if (m < 0) return "";
        String tail = url.substring(m + 8);
        int cut = tail.indexOf('?');
        if (cut >= 0) tail = tail.substring(0, cut);
        cut = tail.indexOf('#');
        if (cut >= 0) tail = tail.substring(0, cut);
        cut = tail.indexOf('/');
        if (cut >= 0) tail = tail.substring(0, cut);
        return tail.trim();
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
        return first(html, "\\b" + name + "=[\"']([^\"']*)[\"']");
    }

    private String imageUrlFromTag(String tag) {
        String url = attr(tag, "data-src");
        if (TextUtils.isEmpty(url)) url = attr(tag, "data-original");
        if (TextUtils.isEmpty(url)) url = attr(tag, "data-lazy-src");
        if (TextUtils.isEmpty(url)) url = attr(tag, "src");
        return absolute(cleanUrl(url));
    }

    private boolean isReaderImage(String url) {
        if (TextUtils.isEmpty(url)) return false;
        String lower = url.toLowerCase();
        if (!(lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") || lower.contains(".webp"))) return false;
        return !lower.contains("logo") && !lower.contains("avatar") && !lower.contains("cover") && !lower.contains("banner");
    }

    private String rawComicId(String value) {
        String raw = decode(value);
        if (raw.startsWith(PREFIX)) raw = raw.substring(PREFIX.length());
        int manhwa = raw.indexOf("/manhwa/");
        if (manhwa >= 0) raw = raw.substring(manhwa + 8);
        int slash = raw.indexOf('/');
        if (slash >= 0) raw = raw.substring(0, slash);
        int pipe = raw.indexOf('|');
        if (pipe >= 0) raw = raw.substring(0, pipe);
        // NOTE: do NOT strip a trailing ".html" — for hanman18 it is part of the slug
        // (e.g. search returns slug "37925.html"); stripping it yields /manhwa/37925 (404).
        return raw.trim();
    }

    private String pinyinSlug(String name) {
        if (name == null || name.isEmpty()) return "";
        HanyuPinyinOutputFormat format = new HanyuPinyinOutputFormat();
        format.setToneType(HanyuPinyinToneType.WITHOUT_TONE);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            String[] pinyins = null;
            try {
                pinyins = PinyinHelper.toHanyuPinyinStringArray(c, format);
            } catch (BadHanyuPinyinOutputFormatCombination ignored) {
            }
            if (pinyins != null && pinyins.length > 0) {
                sb.append(pinyins[0]);
            } else if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
                sb.append(Character.toLowerCase(c));
            }
        }
        return sb.toString().toLowerCase();
    }

    private String rawChapterId(String value) {
        String raw = decode(value);
        int query = raw.indexOf('?');
        if (query >= 0) raw = raw.substring(0, query);
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
        int quote = decoded.indexOf('"');
        if (quote >= 0) decoded = decoded.substring(0, quote);
        int space = decoded.indexOf(' ');
        if (space > 0) decoded = decoded.substring(0, space);
        return decoded;
    }
}
