package com.xxcomic.source;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;

/** Public web API used by manwace.cc. No login or paid chapter access is provided. */
public class ManwaComicSource implements ComicSource {
    private static final String ID = "manwa";
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final String[] TAGS = {"热血", "玄幻", "恋爱", "冒险", "古风", "都市", "穿越", "奇幻", "搞笑", "少男", "战斗", "重生", "逆袭", "爆笑", "少年", "后宫", "系统", "BL", "韩漫", "完整版", "19r", "台版"};
    private static final String[] TAG_SLUGS = {"hotblooded", "xuanhuan", "romance", "adventure", "historical", "urban", "transmigration", "fantasy", "comedy", "shounen", "action", "rebirth", "counterattack", "hilarious", "youth", "harem", "system", "bl", "manhwa", "fullversion", "19plus", "taiwanver"};
    private final SourceConfig config;

    public ManwaComicSource() { this(SourceConfig.manwa(true)); }
    public ManwaComicSource(SourceConfig config) { this.config = config == null ? SourceConfig.manwa(true) : config; }
    @Override public String id() { return ID; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return category(Collections.emptyMap(), page);
    }

    @Override public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        if (keyword == null || keyword.trim().isEmpty()) return new ArrayList<>();
        String path = config.route("search").replace("{page}", String.valueOf(Math.max(1, page)))
                .replace("{keyword}", URLEncoder.encode(keyword.trim(), "UTF-8"));
        return parseCards(request(absolute(path), null, config.referer));
    }

    @Override public List<String> categories() {
        List<String> tags = new ArrayList<>();
        tags.add("全部");
        tags.addAll(Arrays.asList(TAGS));
        return tags;
    }

    @Override public List<ComicModels.FilterGroup> filterGroups() {
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        groups.add(SourceFilters.group("level", "范围", "普通", "all", "全部", "0", "VIP無码", "2"));
        groups.add(SourceFilters.group("type", "类型", "全部", "all", "一般向", "1", "BL向", "2", "TL向", "3", "GL向", "5", "禁漫", "4"));
        List<ComicModels.FilterOption> tags = new ArrayList<>();
        tags.add(new ComicModels.FilterOption("全部", "all"));
        for (String tag : TAGS) tags.add(new ComicModels.FilterOption(tag, tag));
        groups.add(new ComicModels.FilterGroup("tag", "题材", tags));
        groups.add(SourceFilters.group("region", "地区", "全部", "all", "韩国", "2", "日漫", "3", "国漫", "4", "台漫", "5", "其他", "6", "未分类", "1"));
        groups.add(SourceFilters.group("state", "状态", "全部", "all", "连载中", "0", "已完结", "1"));
        groups.add(SourceFilters.group("day", "星期", "全部", "all", "周一", "1", "周二", "2", "周三", "3", "周四", "4", "周五", "5", "周六", "6", "周日", "7"));
        groups.add(SourceFilters.group("sort", "排序", "更新", "all", "新作", "1", "热门", "3"));
        return groups;
    }

    @Override public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        Map<String, String> filters = new LinkedHashMap<>();
        filters.put("region", region);
        filters.put("state", state);
        return category(filters, page);
    }

    @Override public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        String tag = value(filters, "tag", "");
        String suffix = "";
        if (!tag.isEmpty()) {
            int index = Arrays.asList(TAGS).indexOf(tag);
            if (index < 0) throw new IOException("漫蛙题材不支持，请重新选择");
            suffix = "/" + TAG_SLUGS[index];
        }
        // The website selects genres from the URL; comic.tag alone is ignored.
        return parseCards(request(absolute(config.route("category") + suffix), categoryBody(filters, page), absolute("/cate" + suffix)));
    }

    static JSONObject categoryBody(Map<String, String> filters, int page) throws IOException {
        try {
            JSONObject comic = new JSONObject().put("level", number(filters, "level", 1))
                    .put("typeId", number(filters, "type", 0)).put("areaId", number(filters, "region", 0))
                    .put("status", number(filters, "state", -1)).put("day", number(filters, "day", 0))
                    .put("tag", value(filters, "tag", ""));
            return new JSONObject().put("category", "comic").put("sort", number(filters, "sort", 0))
                    .put("page", new JSONObject().put("page", Math.max(1, page)).put("pageSize", 36))
                    .put("comic", comic)
                    .put("video", new JSONObject("{\"year\":0,\"typeId\":0,\"typeId1\":0,\"area\":\"\",\"lang\":\"\",\"status\":-1,\"day\":0,\"level\":0}"))
                    .put("novel", new JSONObject("{\"status\":-1,\"day\":0,\"sortId\":0,\"level\":0}"));
        } catch (JSONException e) { throw new IOException("漫蛙分类参数错误", e); }
    }

    List<ComicModels.ComicSummary> parseCards(String response) throws IOException {
        JSONArray rows = array(data(response), "list");
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.optJSONObject(i);
            if (row == null) throw new IOException("漫蛙列表条目格式错误");
            String rawId = first(row.optString("url"), "(?:^|/)comic/(\\d+)(?:[/?#]|$)");
            if (rawId.isEmpty()) rawId = row.optString("id");
            if (!rawId.matches("\\d+") || !seen.add(rawId)) continue;
            String title = text(row.optString("title"));
            if (title.isEmpty()) continue;
            String cover = row.optString("cover");
            if (cover.isEmpty()) cover = row.optString("pic");
            result.add(new ComicModels.ComicSummary(ID, ID + ":" + rawId, title, absolute(cover),
                    text(row.optString("author")), tags(row.optString("tags"))));
        }
        if (rows.length() > 0 && result.isEmpty()) throw new IOException("漫蛙列表解析失败");
        return result;
    }

    @Override public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawId(comicId);
        String html = request(absolute(config.route("detail").replace("{comicId}", rawId)), null, config.referer);
        return parseDetail(rawId, html);
    }

    ComicModels.ComicDetail parseDetail(String comicId, String html) throws IOException {
        String title = text(elementById(html, "page-title"));
        if (title.isEmpty()) throw new IOException("漫蛙详情解析失败，站点可能暂不可用");
        String coverTag = first(html, "(<img\\b[^>]*class=[\"'][^\"']*\\bcomic-cover\\b[^\"']*[\"'][^>]*>)");
        String cover = attribute(coverTag, "data-src");
        if (cover.isEmpty()) cover = attribute(coverTag, "data-original-cover");
        if (cover.isEmpty()) cover = attribute(coverTag, "src");
        String author = text(elementById(html, "author-container")).replaceAll("\\s*，\\s*", "，");
        List<String> tags = new ArrayList<>();
        Matcher links = Pattern.compile("<a\\b[^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE).matcher(elementById(html, "tagsContainer"));
        while (links.find()) { String tag = text(links.group(1)); if (!tag.isEmpty()) tags.add(tag); }
        String description = text(first(html, "<p\\b[^>]*class=[\"'][^\"']*\\bcomic-desc\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</p>"));
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(ID, ID + ":" + comicId, title, absolute(cover), author, tags);
        return new ComicModels.ComicDetail(summary, author, text(elementById(html, "status")), description,
                text(elementById(html, "newch")), new ArrayList<>());
    }

    @Override public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawId(comicId);
        JSONObject response = data(request(absolute(config.route("chapters").replace("{comicId}", rawId)), null, detailUrl(rawId)));
        JSONArray rows = array(response, "list");
        List<JSONObject> ordered = new ArrayList<>();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.optJSONObject(i);
            if (row == null || !row.optString("id").matches("\\d+") || row.optLong("id") <= 0)
                throw new IOException("漫蛙目录条目格式错误");
            ordered.add(row);
        }
        // sortId includes fractional bonus chapters; numeric title/ID sorting loses that order.
        Collections.sort(ordered, new Comparator<JSONObject>() {
            @Override public int compare(JSONObject a, JSONObject b) {
                return Double.compare(a.optDouble("sortId", 0), b.optDouble("sortId", 0));
            }
        });
        List<ComicModels.Chapter> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (JSONObject row : ordered) {
            String id = row.optString("id");
            if (!seen.add(id)) continue;
            result.add(new ComicModels.Chapter(id, text(row.optString("title")), detailUrl(rawId) + "/" + id, 0, result.size()));
        }
        return result;
    }

    @Override public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String path = new URL(absolute(chapterUrl)).getPath();
        Matcher ids = Pattern.compile("^/comic/(\\d+)/(\\d+)/?$").matcher(path);
        if (!ids.matches()) throw new IOException("漫蛙章节链接格式错误");
        String comicId = ids.group(1), chapterId = ids.group(2);
        String referer = detailUrl(comicId) + "/" + chapterId;
        JSONObject info = data(request(absolute(config.route("chapterInfo").replace("{chapterId}", chapterId)), null, referer));
        JSONObject current = info.optJSONObject("current");
        if (current == null || !comicId.equals(current.optString("comicId")) || !chapterId.equals(current.optString("id")))
            throw new IOException("漫蛙章节信息不匹配");
        List<String> images = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        int expectedTotal = -1, expectedPages = -1;
        for (int page = 1; page <= 500; page++) {
            if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException("漫蛙章节请求已取消");
            String route = config.route("images").replace("{chapterId}", chapterId).replace("{page}", String.valueOf(page))
                    .replace("{imageSource}", URLEncoder.encode(config.route("imageSource"), "UTF-8"));
            JSONObject payload = data(request(absolute(route), null, referer));
            JSONArray rows = array(payload, "images");
            JSONObject pagination = payload.optJSONObject("pagination");
            if (pagination == null) throw new IOException("漫蛙图片分页信息缺失");
            int total = pagination.optInt("total", -1), pages = pagination.optInt("total_pages", -1);
            if (total <= 0 || pages <= 0 || pages > 500 || pagination.optInt("current_page", -1) != page)
                throw new IOException("漫蛙章节暂无可读取图片或分页信息无效");
            if (page == 1) { expectedTotal = total; expectedPages = pages; }
            if (expectedTotal != total || expectedPages != pages) throw new IOException("漫蛙章节图片正在变化，请重试");
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = rows.optJSONObject(i);
                String image = row == null ? "" : absolute(row.optString("url"));
                if (image.isEmpty() || !seen.add(image)) throw new IOException("漫蛙图片缺失或分页重复");
                images.add(image);
            }
            if (rows.length() == 0) throw new IOException("漫蛙图片分页为空");
            if (page == pages) {
                if (images.size() != total) throw new IOException("漫蛙章节图片不完整，请重试");
                return new ComicModels.ChapterPage(referer, text(current.optString("title")), images, "");
            }
        }
        throw new IOException("漫蛙图片分页过多");
    }

    @Override public boolean healthCheck() {
        try { return !latest(1).isEmpty(); } catch (IOException e) { return false; }
    }

    protected String request(String url, JSONObject body, String referer) throws IOException {
        if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException("漫蛙请求已取消");
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        try {
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(25000);
            connection.setRequestProperty("User-Agent", UA);
            connection.setRequestProperty("Referer", referer);
            connection.setRequestProperty("Accept", "application/json,text/html;q=0.9,*/*;q=0.8");
            connection.setRequestProperty("Accept-Encoding", "gzip");
            if (body != null) {
                connection.setRequestMethod("POST");
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
                connection.setRequestProperty("Origin", config.baseUrl);
                // Type filtering uses a request-local cookie, including 0 to reset to all.
                JSONObject comic = body.optJSONObject("comic");
                if (comic != null) connection.setRequestProperty("Cookie", "typeId=" + comic.optInt("typeId", 0));
                byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
                connection.setFixedLengthStreamingMode(bytes.length);
                try (OutputStream output = connection.getOutputStream()) { output.write(bytes); }
            }
            int status = connection.getResponseCode();
            if (status == 401 || status == 403) throw new IOException("漫蛙访问受限，可能需要登录或会员权限");
            if (status < 200 || status >= 300) throw new IOException("漫蛙 HTTP " + status);
            try (InputStream raw = connection.getInputStream();
                 InputStream input = "gzip".equalsIgnoreCase(connection.getContentEncoding()) ? new GZIPInputStream(raw) : raw;
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException("漫蛙请求已取消");
                    output.write(buffer, 0, count);
                    if (output.size() > 16 * 1024 * 1024) throw new IOException("漫蛙响应过大");
                }
                return output.toString("UTF-8");
            }
        } finally { connection.disconnect(); }
    }

    private static JSONObject data(String response) throws IOException {
        try {
            JSONObject root = new JSONObject(response);
            int code = root.optInt("code", -1);
            if (code == 401 || code == 403) throw new IOException("漫蛙访问受限，可能需要登录或会员权限");
            if (code != 200) throw new IOException("漫蛙接口请求失败（" + code + "）");
            return root.getJSONObject("data");
        } catch (JSONException e) { throw new IOException("漫蛙接口响应格式错误", e); }
    }

    private static JSONArray array(JSONObject object, String key) throws IOException {
        JSONArray array = object.optJSONArray(key);
        if (array == null) throw new IOException("漫蛙接口缺少 " + key);
        return array;
    }

    private String detailUrl(String comicId) throws IOException { return absolute(config.route("detail").replace("{comicId}", comicId)); }

    private String absolute(String value) throws IOException {
        if (value == null || value.trim().isEmpty()) return "";
        URL url = new URL(new URL(config.baseUrl + "/"), decodeEntities(value.trim()));
        if (!"https".equals(url.getProtocol()) && !"http".equals(url.getProtocol())) throw new IOException("漫蛙链接协议无效");
        return url.toExternalForm();
    }

    private static String rawId(String id) throws IOException {
        String raw = id == null ? "" : id.startsWith(ID + ":") ? id.substring(ID.length() + 1) : id;
        if (!raw.matches("\\d+")) throw new IOException("漫蛙漫画 ID 无效");
        return raw;
    }

    private static String value(Map<String, String> filters, String key, String fallback) {
        String value = filters == null ? null : filters.get(key);
        return value == null || value.isEmpty() || "all".equals(value) ? fallback : value;
    }

    private static int number(Map<String, String> filters, String key, int fallback) {
        try { return Integer.parseInt(value(filters, key, String.valueOf(fallback))); }
        catch (NumberFormatException e) { return fallback; }
    }

    private static List<String> tags(String value) {
        List<String> tags = new ArrayList<>();
        for (String part : text(value).split("[,，/|]")) if (!part.trim().isEmpty()) tags.add(part.trim());
        return tags;
    }

    private static String elementById(String html, String id) {
        Matcher opening = Pattern.compile("<([a-z][a-z0-9]*)\\b[^>]*\\bid=[\"']" + Pattern.quote(id) + "[\"'][^>]*>", Pattern.CASE_INSENSITIVE).matcher(html);
        if (!opening.find()) return "";
        int end = html.toLowerCase(Locale.ROOT).indexOf("</" + opening.group(1).toLowerCase(Locale.ROOT) + ">", opening.end());
        return end < 0 ? "" : html.substring(opening.end(), end);
    }

    private static String first(String input, String regex) {
        Matcher match = Pattern.compile(regex, Pattern.CASE_INSENSITIVE).matcher(input == null ? "" : input);
        return match.find() ? match.group(1) : "";
    }

    private static String attribute(String tag, String key) { return decodeEntities(first(tag, "(?:^|\\s)" + Pattern.quote(key) + "=[\"']([^\"']*)[\"']")); }
    private static String text(String html) { return decodeEntities(html == null ? "" : html.replaceAll("<[^>]*>", " ")).replaceAll("\\s+", " ").trim(); }

    private static String decodeEntities(String value) {
        Matcher matcher = Pattern.compile("&#(x[0-9a-f]+|[0-9]+);?", Pattern.CASE_INSENSITIVE).matcher(value);
        StringBuffer output = new StringBuffer();
        while (matcher.find()) {
            String number = matcher.group(1);
            String replacement = matcher.group();
            try {
                int code = Integer.parseInt(number.toLowerCase(Locale.ROOT).startsWith("x") ? number.substring(1) : number,
                        number.toLowerCase(Locale.ROOT).startsWith("x") ? 16 : 10);
                if (Character.isValidCodePoint(code)) replacement = new String(Character.toChars(code));
            } catch (IllegalArgumentException ignored) { }
            matcher.appendReplacement(output, Matcher.quoteReplacement(replacement));
        }
        matcher.appendTail(output);
        return output.toString().replace("&nbsp;", " ").replace("&quot;", "\"").replace("&apos;", "'")
                .replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&");
    }
}
