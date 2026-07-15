package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;

public class ManbenComicSource implements ComicSource {
    private static final String SOURCE_ID = "manben";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern CHAPTER_LINK_PATTERN = Pattern.compile(
            "<a[^>]*href=[\"'][^\"']*/m(\\d+)/?[^\"']*[\"'][^>]*>([\\s\\S]*?)</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern META_PATTERN = Pattern.compile(
            "<meta[^>]+(?:property|name)=[\"']([^\"']+)[\"'][^>]+content=[\"']([^\"']*)[\"']",
            Pattern.CASE_INSENSITIVE);
    private final SourceConfig config;

    public ManbenComicSource() {
        this(SourceConfig.manben(true));
    }

    public ManbenComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.manben(true) : config;
    }

    @Override public String id() { return SOURCE_ID; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override
    public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return fetchCategory("all", "all", page);
    }

    @Override
    public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        if (page < 1) page = 1;
        String encoded = URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        String path = config.route("search")
                .replace("{page}", String.valueOf(page))
                .replace("{keyword}", encoded);
        String html = fetchGet(absolute(path), config.referer);
        return parseSearchCards(html);
    }

    @Override
    public List<String> categories() throws IOException {
        List<String> values = new ArrayList<>();
        Iterator<String> keys = config.filters.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            if (key.startsWith("category.")) values.add(key.substring("category.".length()));
        }
        if (!values.contains("全部")) values.add(0, "全部");
        return values;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        return fetchCategory(region, state, page);
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetchGet(absolute(config.route("detail").replace("{comicId}", rawId)), config.referer);
        String infoHtml = elementContentByClass(html, "comicInfo");
        if (TextUtils.isEmpty(infoHtml)) infoHtml = html;
        // <p class="title"><span class="grading">9.2分…</span> 妖神记</p> — grading span nests inner spans,
        // so regex span-stripping fails; take the text after the last </span> instead.
        String titleContent = first(infoHtml, "<p[^>]*class=[\"']title[\"'][^>]*>([\\s\\S]*?)</p>");
        String title = "";
        if (!TextUtils.isEmpty(titleContent)) {
            int lastSpan = titleContent.lastIndexOf("</span>");
            title = clean(lastSpan >= 0 ? titleContent.substring(lastSpan + "</span>".length()) : titleContent);
        }
        if (TextUtils.isEmpty(title)) title = clean(first(infoHtml, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        if (TextUtils.isEmpty(title)) {
            title = clean(first(html, "<title>([\\s\\S]*?)</title>"));
            if (title.contains(" - ")) title = title.substring(0, title.indexOf(" - ")).trim();
            else if (title.contains("_")) title = title.substring(0, title.indexOf("_")).trim();
        }
        if (TextUtils.isEmpty(title)) title = rawId;
        // cover: <div class="…cover…">…<img src="…">
        String coverTag = firstRaw(infoHtml, "<div[^>]*class=[\"'][^\"']*\\bcover\\b[^\"']*[\"'][^>]*>[\\s\\S]*?<img[^>]+>");
        String cover = absolute(imageUrlFromTag(coverTag));
        if (TextUtils.isEmpty(cover)) cover = absolute(cleanUrl(meta(html, "og:image")));
        if (TextUtils.isEmpty(cover)) cover = absolute(imageUrlFromTag(firstRaw(infoHtml, "<img[^>]+(?:alt|title)=[\"'][^\"']*" + Pattern.quote(title) + "[^\"']*[\"'][^>]*>")));
        // author: <a class="avatar">踏雪动漫</a>
        String author = "";
        Matcher avatar = Pattern.compile(
                "<a\\b(?:(?:\"[^\"]*\")|(?:'[^']*')|[^>])*\\bclass\\s*=\\s*[\"'][^\"']*\\bavatar\\b[^\"']*[\"'](?:(?:\"[^\"]*\")|(?:'[^']*')|[^>])*>",
                Pattern.CASE_INSENSITIVE).matcher(infoHtml);
        if (avatar.find()) {
            int authorEnd = infoHtml.indexOf("</a>", avatar.end());
            if (authorEnd >= avatar.end()) author = clean(infoHtml.substring(avatar.end(), authorEnd));
        }
        if (TextUtils.isEmpty(author)) author = clean(first(infoHtml, "作\\s*者[：:]?\\s*<a[^>]*>([\\s\\S]*?)</a>"));
        // status: 状  态：连载中
        String status = clean(first(infoHtml, "状\\s*态[：:]?\\s*([^<]+)"));
        // description: <p class="content">…</p>
        String description = clean(first(infoHtml, "<p[^>]*class=[\"']content[\"'][^>]*>([\\s\\S]*?)</p>"));
        if (TextUtils.isEmpty(description)) description = clean(meta(html, "Description"));
        // latest chapter: <a href="/m…/" class="…op…">第522回</a>
        String latest = clean(first(infoHtml, "<a[^>]*href=[\"'][^\"']*/m\\d+/[\"'][^>]*class=[\"'][^\"']*\\bop\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</a>"));
        if (TextUtils.isEmpty(latest)) latest = clean(first(infoHtml, "<a[^>]*class=[\"'][^\"']*\\bop\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</a>"));
        // tags: 类  别：热血/奇幻
        List<String> tags = new ArrayList<>();
        String tagText = clean(first(infoHtml, "类\\s*别[：:]?\\s*([^<]+)"));
        if (!TextUtils.isEmpty(tagText)) {
            for (String tag : tagText.split("[/／]")) {
                String t = clean(tag);
                if (!TextUtils.isEmpty(t)) tags.add(t);
            }
        }
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, author, tags);
        return new ComicModels.ComicDetail(summary, author, status, description, latest, new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetchGet(absolute(config.route("detail").replace("{comicId}", rawId)), config.referer);
        String block = elementContentById(html, "chapterlistload");
        List<ComicModels.Chapter> collected = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        List<String> groups = splitListGroups(block);
        for (int g = 0; g < groups.size(); g++) {
            Matcher matcher = CHAPTER_LINK_PATTERN.matcher(groups.get(g));
            while (matcher.find()) {
                String chapterId = matcher.group(1);
                if (TextUtils.isEmpty(chapterId) || !seen.add(chapterId)) continue;
                String title = clean(matcher.group(2));
                if (TextUtils.isEmpty(title)) title = "第" + chapterId + "话";
                String url = absolute("/m" + chapterId + "/");
                collected.add(new ComicModels.Chapter(chapterId, title, url, g, 0));
            }
        }
        // Keep formal chapters and bonus chapters in their site-defined groups, then sort within each group.
        Collections.sort(collected, new Comparator<ComicModels.Chapter>() {
            @Override
            public int compare(ComicModels.Chapter a, ComicModels.Chapter b) {
                int section = a.sectionSlot - b.sectionSlot;
                return section != 0 ? section : numeric(chapterIdLong(a.chapterId), chapterIdLong(b.chapterId));
            }
        });
        for (int i = 0; i < collected.size(); i++) {
            ComicModels.Chapter c = collected.get(i);
            collected.set(i, new ComicModels.Chapter(c.chapterId, c.title, c.url, c.sectionSlot, i));
        }
        return collected;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = absolute(chapterUrl);
        String html = fetchChapterGet(url, config.referer);
        String title = clean(first(html, "<title>([\\s\\S]*?)</title>"));
        if (title.contains(" - ")) title = title.substring(0, title.indexOf(" - ")).trim();
        if (TextUtils.isEmpty(title)) title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        if (isBlockedChapter(html)) throw new IOException("漫本章节已被站点屏蔽：" + title);
        String chapterId = rawChapterId(url);
        if (TextUtils.isEmpty(chapterId)) throw new IOException("漫本章节 ID 解析失败：" + url);
        List<String> images = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        int consecutiveEmpty = 0;
        boolean reachedEnd = false;
        for (int spreadPage = 1; spreadPage <= 1000; spreadPage++) {
            ImageData data = parseChapterImageData(fetchGet(imageshowUrl(chapterId, spreadPage), url));
            int before = seen.size();
            for (String image : data.images) {
                if (seen.add(image)) images.add(image);
            }
            if (data.isEnd) {
                reachedEnd = true;
                if (images.isEmpty()) throw new IOException("漫本图片数据为空：" + url);
                break;
            }
            if (seen.size() == before) {
                consecutiveEmpty++;
                if (consecutiveEmpty >= 2) throw new IOException("漫本图片循环无新增：" + url);
            } else {
                consecutiveEmpty = 0;
            }
        }
        if (!reachedEnd) throw new IOException("漫本图片数据未正常结束：" + url);
        if (images.isEmpty()) throw new IOException("漫本章节图片为空：" + url);
        return new ComicModels.ChapterPage(url, title, images, "");
    }

    @Override
    public boolean healthCheck() {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(absolute(config.route("categoryIndex"))).openConnection();
            connection.setRequestMethod("GET");
            connection.setConnectTimeout(5000);
            connection.setReadTimeout(8000);
            connection.setRequestProperty("User-Agent", UA);
            connection.setRequestProperty("Referer", config.referer);
            int code = connection.getResponseCode();
            if (code < 200 || code >= 400) return false;
            try (InputStream stream = connection.getInputStream()) {
                String body = new String(readAllBytes(stream), "UTF-8");
                return body.contains("mh-list") || body.contains("pagerdata");
            }
        } catch (IOException ignored) {
            return false;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    // ---- category ----

    private List<ComicModels.ComicSummary> fetchCategory(String region, String state, int page) throws IOException {
        Map<String, String> body = categoryBody(region, state, page);
        String url = absolute(config.route("category"));
        String json = fetchPost(url, body, config.referer);
        return parseCategoryJson(json);
    }

    private Map<String, String> categoryBody(String region, String state, int page) {
        Map<String, String> body = new LinkedHashMap<>();
        body.put("t", "2");
        body.put("pageindex", String.valueOf(Math.max(1, page)));
        body.put("sc", "1");
        body.put("tsort", TextUtils.isEmpty(config.filter("sort.latest")) ? "2" : config.filter("sort.latest"));
        body.put("tagid", "0");
        body.put("tst", "0");
        body.put("tarea", "0");
        body.put("tgroup", "0");
        body.put("tnm", "");
        String regionKey = TextUtils.isEmpty(region) || "all".equals(region) ? "全部" : region;
        applyFilterParam(body, config.filter("category." + regionKey));
        String stateKey = TextUtils.isEmpty(state) ? "all" : state;
        String stateValue = config.filter("state." + stateKey);
        if (!TextUtils.isEmpty(stateValue)) body.put("tst", stateValue);
        return body;
    }

    private void applyFilterParam(Map<String, String> body, String paramValue) {
        if (TextUtils.isEmpty(paramValue)) return;
        int colon = paramValue.indexOf(':');
        if (colon <= 0) return;
        String key = paramValue.substring(0, colon).trim();
        String value = paramValue.substring(colon + 1).trim();
        if (TextUtils.isEmpty(key) || TextUtils.isEmpty(value)) return;
        body.put(key, value);
    }

    private List<ComicModels.ComicSummary> parseCategoryJson(String json) throws IOException {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        if (TextUtils.isEmpty(json)) return result;
        JSONArray array;
        try {
            array = new JSONArray(json);
        } catch (JSONException e) {
            throw new IOException("漫本分类 JSON 非数组: " + snippet(json));
        }
        Set<String> seen = new LinkedHashSet<>();
        for (int i = 0; i < array.length(); i++) {
            JSONObject item = array.optJSONObject(i);
            if (item == null) continue;
            String rawId = rawComicId(item.optString("Url"));
            if (TextUtils.isEmpty(rawId) || !seen.add(rawId)) continue;
            String title = clean(item.optString("Title"));
            if (TextUtils.isEmpty(title)) continue;
            String cover = absolute(item.optString("BigPic"));
            String author = firstArrayItem(item, "Author");
            String latest = clean(item.optString("LastPartShowName"));
            String subtitle = !TextUtils.isEmpty(author) ? author : latest;
            result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, subtitle, stringArray(item, "TagList")));
        }
        return result;
    }

    // ---- search ----

    private List<ComicModels.ComicSummary> parseSearchCards(String html) {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        if (html == null) return result;
        Set<String> seen = new LinkedHashSet<>();
        Matcher item = Pattern.compile(
                "class=[\"'][^\"']*\\bitem\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)(?=class=[\"'][^\"']*\\b(?:item|pager)\\b[^\"']*[\"']|$)",
                Pattern.CASE_INSENSITIVE).matcher(html);
        while (item.find()) {
            String block = item.group(1);
            String slug = first(block, "/mh-([^/\"'\\?]+)/");
            if (TextUtils.isEmpty(slug) || !seen.add(slug)) continue;
            String title = clean(first(block, "class=[\"']title[\"'][^>]*>[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>"));
            if (TextUtils.isEmpty(title)) title = clean(first(block, "class=[\"']title[\"'][^>]*>([\\s\\S]*?)</div>"));
            if (TextUtils.isEmpty(title)) continue;
            String imgTag = firstRaw(block, "<img[^>]*\\bclass=[\"'][^\"']*cover[^\"']*[\"'][^>]*>");
            if (TextUtils.isEmpty(imgTag)) imgTag = firstRaw(block, "<img[^>]+>");
            String cover = absolute(imageUrlFromTag(imgTag));
            String tip = clean(first(block, "class=[\"']tip[\"'][^>]*>([\\s\\S]*?)</(?:div|p)>"));
            result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + slug, title, cover, tip, new ArrayList<String>()));
        }
        return result;
    }

    // ---- chapter images ----

    private boolean isBlockedChapter(String html) {
        if (html == null) return false;
        boolean blocked = html.contains("屏蔽") || html.contains("章节数据缺少");
        boolean hasReaderMarkup = html.contains("class=\"myview\"")
                || html.contains("class=\"pageItem\"")
                || html.contains("imageshow.ashx");
        return blocked && !hasReaderMarkup;
    }

    private ImageData parseChapterImageData(String script) throws IOException {
        if (script == null || !script.contains("chapterimage")) {
            throw new IOException("漫本图片数据格式异常：无 chapterimage " + snippet(script));
        }
        int start = script.indexOf('{');
        int end = script.lastIndexOf('}');
        if (start < 0 || end <= start) throw new IOException("漫本图片数据格式异常：" + snippet(script));
        JSONObject root;
        try {
            root = new JSONObject(script.substring(start, end + 1));
        } catch (JSONException e) {
            throw new IOException("漫本图片数据格式异常：" + snippet(script));
        }
        String imagePix = root.optString("ImagePix");
        JSONArray images = root.optJSONArray("Images");
        if (TextUtils.isEmpty(imagePix) || images == null || images.length() == 0) {
            throw new IOException("漫本图片数据格式异常：ImagePix/Images 缺失 " + snippet(script));
        }
        List<String> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (int i = 0; i < images.length(); i++) {
            String path = images.optString(i);
            if (TextUtils.isEmpty(path)) continue;
            String url = path.startsWith("http://") || path.startsWith("https://") ? path : imagePix + path;
            if (!url.startsWith("http://") && !url.startsWith("https://")) continue;
            if (!url.startsWith(imagePix)) continue;
            if (seen.add(url)) result.add(url);
        }
        return new ImageData(result, root.optBoolean("IsEnd", false));
    }

    private String imageshowUrl(String chapterId, int page) {
        return absolute(config.route("chapterImages")
                .replace("{chapterId}", chapterId)
                .replace("{page}", String.valueOf(page)));
    }

    // ---- network ----

    private String fetchGet(String url, String referer) throws IOException {
        return fetch(url, "GET", null, referer, 10000, 20000);
    }

    private String fetchChapterGet(String url, String referer) throws IOException {
        return fetch(url, "GET", null, referer, 10000, 30000);
    }

    private String fetchPost(String url, Map<String, String> body, String referer) throws IOException {
        return fetch(url, "POST", body, referer, 10000, 20000);
    }

    private String fetch(String url, String method, Map<String, String> body, String referer, int connectMs, int readMs) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setRequestMethod(method);
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(connectMs);
        connection.setReadTimeout(readMs);
        connection.setRequestProperty("User-Agent", UA);
        connection.setRequestProperty("Referer", TextUtils.isEmpty(referer) ? config.referer : referer);
        connection.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8");
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
        connection.setRequestProperty("Accept-Encoding", "gzip");
        if (body != null) {
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
            StringBuilder sb = new StringBuilder();
            boolean first = true;
            for (Map.Entry<String, String> entry : body.entrySet()) {
                if (!first) sb.append('&');
                sb.append(URLEncoder.encode(entry.getKey(), "UTF-8"))
                        .append('=')
                        .append(URLEncoder.encode(entry.getValue(), "UTF-8"));
                first = false;
            }
            byte[] payload = sb.toString().getBytes("UTF-8");
            connection.getOutputStream().write(payload);
            connection.getOutputStream().flush();
        }
        int code = connection.getResponseCode();
        if (code < 200 || code >= 300) {
            connection.disconnect();
            throw new IOException("漫本 HTTP " + code + ": " + url);
        }
        try (InputStream raw = connection.getInputStream();
             InputStream stream = "gzip".equalsIgnoreCase(connection.getContentEncoding()) ? new GZIPInputStream(raw) : raw) {
            byte[] bytes = readAllBytes(stream);
            String charset = charsetFrom(connection.getContentType());
            if (TextUtils.isEmpty(charset)) charset = "UTF-8";
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
        return matcher.find() ? matcher.group(1) : "";
    }

    // ---- helpers ----

    private List<String> splitListGroups(String block) {
        List<String> groups = new ArrayList<>();
        if (TextUtils.isEmpty(block)) return groups;
        Pattern p = Pattern.compile("<div[^>]*\\bclass=[\"'][^\"']*\\blist\\b[^\"']*[\"']", Pattern.CASE_INSENSITIVE);
        Matcher m = p.matcher(block);
        List<Integer> starts = new ArrayList<>();
        while (m.find()) starts.add(m.start());
        for (int i = 0; i < starts.size(); i++) {
            int s = starts.get(i);
            int e = (i + 1 < starts.size()) ? starts.get(i + 1) : block.length();
            groups.add(block.substring(s, e));
        }
        if (groups.isEmpty() && block.contains("/m")) groups.add(block);
        return groups;
    }

    private String elementContentById(String html, String idValue) {
        if (html == null || TextUtils.isEmpty(idValue)) return "";
        int idx = html.indexOf(idValue);
        if (idx < 0) return "";
        int tagClose = html.indexOf('>', idx);
        if (tagClose < 0) return "";
        return elementContentAt(html, tagClose);
    }

    private String elementContentByClass(String html, String className) {
        if (html == null || TextUtils.isEmpty(className)) return "";
        Matcher matcher = Pattern.compile(
                "<div[^>]*class=[\"'][^\"']*\\b" + Pattern.quote(className) + "\\b[^\"']*[\"'][^>]*>",
                Pattern.CASE_INSENSITIVE).matcher(html);
        if (!matcher.find()) return "";
        return elementContentAt(html, matcher.end() - 1);
    }

    private String elementContentAt(String html, int tagClose) {
        int depth = 1;
        int pos = tagClose + 1;
        while (pos < html.length() && depth > 0) {
            int open = html.indexOf("<div", pos);
            int close = html.indexOf("</div", pos);
            if (close < 0) return html.substring(tagClose + 1);
            if (open >= 0 && open < close) {
                depth++;
                pos = open + 4;
            } else {
                depth--;
                if (depth == 0) return html.substring(tagClose + 1, close);
                pos = close + 5;
            }
        }
        return html.substring(tagClose + 1);
    }

    private String rawComicId(String value) {
        if (value == null) return "";
        if (value.startsWith(PREFIX)) value = value.substring(PREFIX.length());
        Matcher m = Pattern.compile("/mh-([^/\"'\\?]+)/").matcher(value);
        if (m.find()) return m.group(1);
        return value.replaceAll("/+$", "").trim();
    }

    private String rawChapterId(String value) {
        if (value == null) return "";
        Matcher m = Pattern.compile("/m(\\d+)/?").matcher(value);
        return m.find() ? m.group(1) : "";
    }

    private long chapterIdLong(String value) {
        if (TextUtils.isEmpty(value)) return 0L;
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException ignored) {
            return 0L;
        }
    }

    private int numeric(long a, long b) {
        return a < b ? -1 : (a > b ? 1 : 0);
    }

    private String firstArrayItem(JSONObject item, String key) {
        JSONArray array = item.optJSONArray(key);
        if (array == null || array.length() == 0) return "";
        return clean(array.optString(0));
    }

    private List<String> stringArray(JSONObject item, String key) {
        List<String> values = new ArrayList<>();
        JSONArray array = item.optJSONArray(key);
        Set<String> seen = new LinkedHashSet<>();
        if (array != null) {
            for (int i = 0; i < array.length(); i++) {
                String tag = clean(array.optString(i));
                if (!TextUtils.isEmpty(tag) && seen.add(tag)) values.add(tag);
            }
        }
        return values;
    }

    private String meta(String html, String key) {
        Matcher matcher = META_PATTERN.matcher(html == null ? "" : html);
        while (matcher.find()) if (key.equals(matcher.group(1))) return matcher.group(2);
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
        return first(html, "\\b" + Pattern.quote(name) + "=[\"']([^\"']*)[\"']");
    }

    private String imageUrlFromTag(String tag) {
        String url = attr(tag, "data-src");
        if (TextUtils.isEmpty(url)) url = attr(tag, "data-original");
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

    private String cleanUrl(String value) {
        String url = value == null ? "" : value.replace("&amp;", "&").replace("\\/", "/").trim();
        int quote = url.indexOf('"');
        if (quote >= 0) url = url.substring(0, quote);
        int space = url.indexOf(' ');
        if (space > 0) url = url.substring(0, space);
        return url;
    }

    private String snippet(String value) {
        String text = value == null ? "" : value.replaceAll("\\s+", " ").trim();
        return text.length() > 500 ? text.substring(0, 500) : text;
    }

    private static final class ImageData {
        final List<String> images;
        final boolean isEnd;

        ImageData(List<String> images, boolean isEnd) {
            this.images = images;
            this.isEnd = isEnd;
        }
    }
}
