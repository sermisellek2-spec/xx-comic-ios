package com.xxcomic.source;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Web API/HTML adapter. No page JavaScript is executed and no empty reader is cached as success. */
public class CopyMangaComicSource implements ComicSource {
    private static final int SEARCH_LIMIT = 12;
    private static final int CATEGORY_LIMIT = 50;
    private static final Pattern LINKS = Pattern.compile("<a\\b([^>]*)>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE);
    private static final String USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";
    private final SourceConfig config;

    public CopyMangaComicSource() { this(SourceConfig.copy4000(true)); }
    public CopyMangaComicSource(SourceConfig config) { this.config = config == null ? SourceConfig.copy4000(true) : config; }
    @Override public String id() { return config.id; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        if (keyword == null || keyword.trim().isEmpty()) return new ArrayList<>();
        String path = config.route("search").replace("{keyword}", encode(keyword.trim()))
                .replace("{offset}", offset(page, SEARCH_LIMIT)).replace("{limit}", String.valueOf(SEARCH_LIMIT));
        return parseSearch(fetch(absolute(path)));
    }

    @Override public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        return category(Collections.emptyMap(), page);
    }

    @Override public List<String> categories() throws IOException {
        List<String> result = new ArrayList<>();
        for (ComicModels.FilterGroup group : filterGroups()) if ("theme".equals(group.key)) {
            for (ComicModels.FilterOption option : group.options) if (!"all".equals(option.value)) result.add(option.label);
        }
        return result;
    }

    @Override public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        return parseFilterGroups(fetch(absolute(config.route("categoryIndex"))));
    }

    @Override public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        Map<String, String> filters = new LinkedHashMap<>();
        if ("jp".equals(region)) region = "0";
        if ("kr".equals(region)) region = "1";
        if ("en".equals(region)) region = "2";
        if ("serial".equals(state)) state = "0";
        if ("pub".equals(state)) state = "1";
        filters.put("region", region);
        filters.put("status", state);
        return category(filters, page);
    }

    @Override public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        return parseCards(fetch(absolute(categoryPath(filters, page))));
    }

    String categoryPath(Map<String, String> filters, int page) throws IOException {
        String ordering = selected(filters, "ordering");
        if (ordering.isEmpty()) ordering = "-datetime_updated";
        if (!ordering.matches("-?(datetime_updated|popular)")) throw new IOException("拷贝漫画排序参数无效");
        StringBuilder query = new StringBuilder();
        for (String key : new String[]{"theme", "region", "status"}) {
            String value = selected(filters, key);
            if (value.isEmpty()) continue;
            if (!"theme".equals(key) && !value.matches("[012]")) throw new IOException("拷贝漫画筛选参数无效：" + key);
            query.append('&').append(key).append('=').append(encode(value));
        }
        return config.route("category").replace("{offset}", offset(page, CATEGORY_LIMIT))
                .replace("{limit}", String.valueOf(CATEGORY_LIMIT)).replace("{ordering}", ordering).replace("{filters}", query);
    }

    @Override public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawId(comicId);
        return parseDetail(rawId, fetch(absolute(config.route("detail").replace("{comicId}", encode(rawId)))));
    }

    @Override public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawId(comicId);
        JSONObject detail = apiResults(fetchApi(apiUrl("apiDetail").replace("{comicId}", encode(rawId))));
        checkComic(detail, rawId);
        JSONObject groups = detail.optJSONObject("groups");
        if (groups == null) throw new IOException("拷贝漫画目录缺少分组");
        List<ComicModels.Chapter> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Iterator<String> keys = groups.keys();
        int section = 0;
        while (keys.hasNext()) {
            String groupKey = keys.next();
            JSONObject group = groups.optJSONObject(groupKey);
            if (group == null) throw new IOException("拷贝漫画目录分组格式错误");
            String groupId = string(group, "path_word");
            if (groupId.isEmpty()) groupId = groupKey;
            int offset = 0;
            boolean complete = false;
            for (int page = 0; page < 1000; page++) {
                String url = apiUrl("apiChapters").replace("{comicId}", encode(rawId))
                        .replace("{group}", encode(groupId)).replace("{offset}", String.valueOf(offset));
                JSONObject data = apiResults(fetchApi(url));
                JSONArray list = data.optJSONArray("list");
                int total = data.optInt("total", -1);
                if (list == null || total < 0 || data.optInt("offset", -1) != offset)
                    throw new IOException("拷贝漫画目录分页响应错误");
                if (list.length() == 0) {
                    if (offset < total) throw new IOException("拷贝漫画目录未完整返回，请重试");
                    complete = true;
                    break;
                }
                int before = result.size();
                for (int i = 0; i < list.length(); i++) {
                    JSONObject item = list.optJSONObject(i);
                    if (item == null || !rawId.equals(string(item, "comic_path_word"))
                            || !groupId.equals(string(item, "group_path_word")))
                        throw new IOException("拷贝漫画目录与漫画或分组不匹配");
                    String chapterId = string(item, "uuid"), title = string(item, "name");
                    if (chapterId.isEmpty() || title.isEmpty()) throw new IOException("拷贝漫画目录项缺少标识或标题");
                    if (seen.add(chapterId)) result.add(new ComicModels.Chapter(chapterId, title,
                            absolute("/comic/" + encode(rawId) + "/chapter/" + encode(chapterId)), section, offset + i));
                }
                if (result.size() == before) throw new IOException("拷贝漫画目录重复返回同一页，请重试");
                offset += list.length();
                if (offset >= total) { complete = true; break; }
            }
            if (!complete) throw new IOException("拷贝漫画目录页数超出限制");
            section++;
        }
        if (result.isEmpty()) throw new IOException("拷贝漫画返回空目录，请稍后重试或检查站点访问状态");
        return result;
    }

    @Override public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        // Rebase saved links when the configured source domain changes.
        Matcher match = Pattern.compile("/comic/([^/?#]+)/chapter/([^/?#]+)(?:[?#].*)?$").matcher(chapterUrl == null ? "" : chapterUrl);
        if (!match.find()) throw new IOException("拷贝漫画章节地址无效");
        String rawId, chapterId;
        try {
            rawId = rawId(URLDecoder.decode(match.group(1), "UTF-8"));
            chapterId = URLDecoder.decode(match.group(2), "UTF-8");
        } catch (IllegalArgumentException e) { throw new IOException("拷贝漫画章节地址编码错误", e); }
        String url = absolute("/comic/" + encode(rawId) + "/chapter/" + encode(chapterId));
        String response = fetchApi(apiUrl("apiChapter").replace("{comicId}", encode(rawId)).replace("{chapterId}", encode(chapterId)));
        return parseApiReader(url, rawId, chapterId, response);
    }

    ComicModels.ChapterPage parseApiReader(String url, String rawId, String chapterId, String response) throws IOException {
        JSONObject data = apiResults(response);
        checkComic(data, rawId);
        JSONObject chapter = data.optJSONObject("chapter");
        if (chapter == null || !chapterId.equals(string(chapter, "uuid")) || !rawId.equals(string(chapter, "comic_path_word")))
            throw new IOException("拷贝漫画阅读数据与章节不匹配");
        JSONArray contents = chapter.optJSONArray("contents");
        if (contents == null || contents.length() == 0 || chapter.optInt("size", -1) != contents.length())
            throw new IOException("拷贝漫画章节图片未完整返回，请重试");
        List<String> images = new ArrayList<>();
        for (int i = 0; i < contents.length(); i++) {
            JSONObject item = contents.optJSONObject(i);
            String image = item == null ? "" : string(item, "url");
            if (!image.startsWith("https://") && !image.startsWith("http://")) throw new IOException("拷贝漫画图片地址无效");
            images.add(image);
        }
        return new ComicModels.ChapterPage(url, string(chapter, "name"), images, "");
    }

    private String apiUrl(String route) throws IOException {
        String base = config.route("apiBaseUrl");
        if (base.isEmpty()) base = SourceConfig.copy4000(true).route("apiBaseUrl");
        String path = config.route(route);
        if (path.isEmpty()) path = SourceConfig.copy4000(true).route(route);
        if (path.startsWith("https://") || path.startsWith("http://")) return path;
        if (!base.startsWith("https://") && !base.startsWith("http://")) throw new IOException("拷贝漫画 API 地址无效");
        return base.replaceAll("/+$", "") + path;
    }

    private static JSONObject apiResults(String response) throws IOException {
        JSONObject data = success(response).optJSONObject("results");
        if (data == null) throw new IOException("拷贝漫画接口未返回有效数据，请重试");
        if (data.optBoolean("is_lock", false)) throw new IOException("拷贝漫画当前内容不可访问");
        return data;
    }

    private static void checkComic(JSONObject data, String rawId) throws IOException {
        JSONObject comic = data.optJSONObject("comic");
        if (comic == null || !rawId.equals(string(comic, "path_word"))) throw new IOException("拷贝漫画响应与漫画标识不匹配");
    }

    @Override public boolean healthCheck() {
        try { return !latest(1).isEmpty(); } catch (IOException e) { return false; }
    }

    List<ComicModels.ComicSummary> parseSearch(String response) throws IOException {
        JSONObject json = success(response).optJSONObject("results");
        JSONArray list = json == null ? null : json.optJSONArray("list");
        if (list == null) throw new IOException("拷贝漫画搜索响应缺少列表");
        return summaries(list);
    }

    List<ComicModels.ComicSummary> parseCards(String html) throws IOException {
        String tag = openingByClass(html, "exemptComic-box");
        String list = attribute(tag, "list");
        if (list.isEmpty()) throw new IOException("拷贝漫画分类响应缺少列表数据");
        Object value = CopyMangaLiteral.parse(list);
        if (!(value instanceof JSONArray)) throw new IOException("拷贝漫画分类列表格式错误");
        return summaries((JSONArray) value);
    }

    private List<ComicModels.ComicSummary> summaries(JSONArray array) throws IOException {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (int i = 0; i < array.length(); i++) {
            JSONObject item = array.optJSONObject(i);
            if (item == null) throw new IOException("拷贝漫画列表项格式错误");
            String slug = string(item, "path_word"), title = string(item, "name");
            if (slug.isEmpty() || title.isEmpty()) throw new IOException("拷贝漫画列表缺少漫画标识或标题");
            if (!seen.add(slug)) continue;
            List<String> authors = names(item.optJSONArray("author"));
            result.add(new ComicModels.ComicSummary(id(), id() + ":" + slug, title,
                    absolute(string(item, "cover")), join(authors), names(item.optJSONArray("theme"))));
        }
        return result;
    }

    List<ComicModels.FilterGroup> parseFilterGroups(String html) throws IOException {
        LinkedHashMap<String, String> themes = new LinkedHashMap<>();
        Matcher links = LINKS.matcher(html);
        while (links.find()) {
            String href = attribute(links.group(1), "href");
            String path = href.replaceFirst("^https?://[^/]+", "");
            if (!path.startsWith("/comics?")) continue;
            String value = queryValue(href, "theme");
            String label = clean(links.group(2)).replaceFirst("\\s*\\(\\d+\\)\\s*$", "");
            if (!value.isEmpty() && !label.isEmpty() && !themes.containsKey(value)) themes.put(value, label);
        }
        if (themes.isEmpty()) throw new IOException("拷贝漫画分类字典不可用，请重试");
        List<ComicModels.FilterGroup> result = new ArrayList<>();
        result.add(group("ordering", "排序", "最近更新", "-datetime_updated", "较早更新", "datetime_updated", "热门优先", "-popular", "热度升序", "popular"));
        List<ComicModels.FilterOption> options = new ArrayList<>();
        options.add(new ComicModels.FilterOption("全部", "all"));
        for (Map.Entry<String, String> entry : themes.entrySet()) options.add(new ComicModels.FilterOption(entry.getValue(), entry.getKey()));
        result.add(new ComicModels.FilterGroup("theme", "题材", options));
        result.add(group("region", "地区", "全部", "all", "日漫", "0", "韩漫", "1", "美漫", "2"));
        result.add(group("status", "状态", "全部", "all", "连载中", "0", "已完结", "1", "短篇", "2"));
        return result;
    }

    ComicModels.ComicDetail parseDetail(String rawId, String html) throws IOException {
        String info = contentByClass(html, "comicParticulars-title-right");
        String title = clean(first(info, "<h6\\b[^>]*>([\\s\\S]*?)</h6>"));
        if (title.isEmpty()) throw new IOException("拷贝漫画详情不可用：缺少标题");
        String image = first(contentByClass(html, "comicParticulars-left-img"), "(<img\\b[^>]*>)");
        String cover = attribute(image, "data-src");
        if (cover.isEmpty()) cover = attribute(image, "src");
        List<String> authors = new ArrayList<>(), themes = new ArrayList<>();
        Matcher links = LINKS.matcher(info);
        while (links.find()) {
            String href = attribute(links.group(1), "href"), label = clean(links.group(2));
            if (href.contains("/author/")) authors.add(label);
            if (href.contains("theme=")) themes.add(label.replaceFirst("^#", ""));
        }
        String state = labelled(info, "狀態");
        String pageTitle = clean(first(html, "<title\\b[^>]*>([\\s\\S]*?)</title>"));
        String latest = first(pageTitle, "[-－](第[^-－]*?[話话卷回章])(?=[-－])");
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(id(), id() + ":" + rawId, title, absolute(cover), state, themes);
        return new ComicModels.ComicDetail(summary, join(authors), state,
                clean(contentByClass(html, "intro")), latest, new ArrayList<>());
    }

    List<ComicModels.Chapter> parseChapters(String rawId, String plain) throws IOException {
        try {
            JSONObject json = new JSONObject(plain);
            JSONObject build = json.optJSONObject("build");
            if (build == null || !rawId.equals(string(build, "path_word"))) throw new IOException("拷贝漫画目录与漫画标识不匹配");
            JSONObject groups = json.getJSONObject("groups");
            List<ComicModels.Chapter> result = new ArrayList<>();
            Set<String> seen = new LinkedHashSet<>();
            Iterator<String> keys = groups.keys();
            int section = 0;
            while (keys.hasNext()) {
                JSONObject group = groups.getJSONObject(keys.next());
                JSONArray chapters = group.getJSONArray("chapters");
                for (int i = 0; i < chapters.length(); i++) {
                    JSONObject item = chapters.getJSONObject(i);
                    String chapterId = string(item, "id"), title = string(item, "name");
                    if (chapterId.isEmpty() || title.isEmpty()) throw new IOException("拷贝漫画目录项缺少标识或标题");
                    if (!seen.add(chapterId)) continue;
                    String url = absolute("/comic/" + encode(rawId) + "/chapter/" + encode(chapterId));
                    result.add(new ComicModels.Chapter(chapterId, title, url, section, i));
                }
                section++;
            }
            if (result.isEmpty()) throw new IOException("拷贝漫画返回空目录，请稍后重试或检查站点访问状态");
            return result;
        } catch (JSONException e) { throw new IOException("拷贝漫画目录数据格式错误", e); }
    }

    ComicModels.ChapterPage parseReader(String url, String html) throws IOException {
        String payload = variable(html, "contentKey");
        if (payload.isEmpty()) throw new IOException("拷贝漫画未返回阅读数据，请稍后重试或检查站点访问状态");
        String plain = decrypt(payload, variable(html, "cct"));
        try {
            JSONArray array = new JSONArray(plain);
            List<String> images = new ArrayList<>();
            for (int i = 0; i < array.length(); i++) {
                String image = string(array.getJSONObject(i), "url");
                if (!image.startsWith("https://") && !image.startsWith("http://")) throw new IOException("拷贝漫画图片地址无效");
                images.add(image);
            }
            if (images.isEmpty()) throw new IOException("拷贝漫画章节没有返回图片，请重试");
            return new ComicModels.ChapterPage(url, clean(contentByClass(html, "header")), images, "");
        } catch (JSONException e) { throw new IOException("拷贝漫画阅读数据格式错误", e); }
    }

    static String decrypt(String payload, String key) throws IOException {
        if (payload == null || payload.length() <= 16) throw new IOException("拷贝漫画加密数据为空");
        byte[] keyBytes = key.getBytes(StandardCharsets.UTF_8);
        byte[] iv = payload.substring(0, 16).getBytes(StandardCharsets.UTF_8);
        String hex = payload.substring(16);
        if ((keyBytes.length != 16 && keyBytes.length != 24 && keyBytes.length != 32) || iv.length != 16
                || hex.length() % 32 != 0 || !hex.matches("[0-9a-fA-F]+")) throw new IOException("拷贝漫画密钥或密文格式错误");
        byte[] bytes = new byte[hex.length() / 2];
        for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) Integer.parseInt(hex.substring(i * 2, i * 2 + 2), 16);
        try {
            Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(keyBytes, "AES"), new IvParameterSpec(iv));
            return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(cipher.doFinal(bytes))).toString();
        } catch (GeneralSecurityException | CharacterCodingException e) { throw new IOException("拷贝漫画数据解密失败，请刷新页面后重试", e); }
    }

    /** Single bounded request, without the webpage's dnts header (which returned empty directories). */
    protected String fetch(String url) throws IOException {
        return request(url, false);
    }

    protected String fetchApi(String url) throws IOException {
        return request(url, true);
    }

    private String request(String url, boolean api) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(20000);
        connection.setRequestProperty("User-Agent", api ? "COPY/3.0.9" : USER_AGENT);
        // Java's default Accept prefers HTML, making the search API return its browsable UI.
        connection.setRequestProperty("Accept", api ? "application/json" : "application/json, text/html;q=0.9, */*;q=0.8");
        if (api) {
            connection.setRequestProperty("platform", "3");
            connection.setRequestProperty("version", "3.0.9");
            connection.setRequestProperty("region", "1");
            connection.setRequestProperty("webp", "1");
        }
        connection.setRequestProperty("Referer", config.referer);
        try {
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) throw new IOException("拷贝漫画请求失败：HTTP " + status);
            try (InputStream stream = connection.getInputStream(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = stream.read(buffer)) != -1) {
                    if (out.size() + read > 16 * 1024 * 1024) throw new IOException("拷贝漫画响应过大");
                    out.write(buffer, 0, read);
                }
                return new String(out.toByteArray(), StandardCharsets.UTF_8);
            }
        } finally { connection.disconnect(); }
    }

    private static JSONObject success(String response) throws IOException {
        try {
            JSONObject json = new JSONObject(response);
            if (json.optInt("code", -1) != 200) throw new IOException("拷贝漫画接口返回错误：" + json.optInt("code", -1));
            return json;
        } catch (JSONException e) { throw new IOException("拷贝漫画接口未返回有效 JSON", e); }
    }

    public static boolean usesImageHost(String url) {
        try {
            String host = new URL(url).getHost().toLowerCase(java.util.Locale.ROOT);
            return "mangafunb.fun".equals(host) || host.endsWith(".mangafunb.fun");
        } catch (Exception ignored) { return false; }
    }

    private String rawId(String value) throws IOException {
        if (value == null) throw new IOException("拷贝漫画标识为空");
        if (value.startsWith(id() + ":")) value = value.substring(id().length() + 1);
        if (value.isEmpty() || value.matches(".*[/?#].*")) throw new IOException("拷贝漫画标识无效");
        return value;
    }

    private String absolute(String value) {
        if (value.isEmpty()) return "";
        if (value.startsWith("http://") || value.startsWith("https://")) return value;
        if (value.startsWith("//")) return "https:" + value;
        return config.baseUrl + (value.startsWith("/") ? value : "/" + value);
    }

    private static String offset(int page, int limit) throws IOException {
        if (page < 1) throw new IOException("拷贝漫画页码必须大于零");
        return String.valueOf(((long) page - 1) * limit);
    }

    private static String encode(String value) throws IOException { return URLEncoder.encode(value, "UTF-8").replace("+", "%20"); }
    private static String selected(Map<String, String> filters, String key) {
        String value = filters == null ? null : filters.get(key);
        return value == null || "all".equals(value) ? "" : value;
    }
    private static String string(JSONObject obj, String key) { return obj.isNull(key) ? "" : obj.optString(key, ""); }
    private static List<String> names(JSONArray array) {
        List<String> names = new ArrayList<>();
        if (array != null) for (int i = 0; i < array.length(); i++) {
            JSONObject item = array.optJSONObject(i);
            if (item != null && !string(item, "name").isEmpty()) names.add(string(item, "name"));
        }
        return names;
    }
    private static String join(List<String> values) {
        StringBuilder out = new StringBuilder();
        for (String value : values) { if (out.length() > 0) out.append(" / "); out.append(value); }
        return out.toString();
    }
    private static ComicModels.FilterGroup group(String key, String label, String... pairs) {
        List<ComicModels.FilterOption> options = new ArrayList<>();
        for (int i = 0; i < pairs.length; i += 2) options.add(new ComicModels.FilterOption(pairs[i], pairs[i + 1]));
        return new ComicModels.FilterGroup(key, label, options);
    }
    private static String queryValue(String href, String key) throws IOException {
        int start = href.indexOf('?');
        if (start < 0) return "";
        for (String part : href.substring(start + 1).split("&")) {
            String[] pair = part.split("=", 2);
            if (pair.length == 2 && pair[0].equals(key)) {
                try { return URLDecoder.decode(pair[1], "UTF-8"); }
                catch (IllegalArgumentException e) { throw new IOException("拷贝漫画分类链接编码错误", e); }
            }
        }
        return "";
    }
    private static String variable(String html, String name) throws IOException {
        Matcher assignment = Pattern.compile("\\b(?:var|let|const)\\s+" + Pattern.quote(name) + "\\s*=\\s*").matcher(html);
        if (!assignment.find() || assignment.end() >= html.length()) return "";
        int start = assignment.end();
        char quote = html.charAt(start);
        if (quote != '\'' && quote != '"') throw new IOException("拷贝漫画阅读参数格式错误");
        // Payloads can be very long: scan once rather than using a recursive regex.
        for (int i = start + 1; i < html.length(); i++) {
            char c = html.charAt(i);
            if (c == '\\') { i++; continue; }
            if (c == quote) return (String) CopyMangaLiteral.parse(html.substring(start, i + 1));
        }
        throw new IOException("拷贝漫画阅读参数不完整");
    }
    private static String labelled(String html, String label) {
        Matcher li = Pattern.compile("<li\\b[^>]*>([\\s\\S]*?)</li>", Pattern.CASE_INSENSITIVE).matcher(html);
        while (li.find()) {
            String value = clean(li.group(1));
            if (value.startsWith(label + "：") || value.startsWith(label + ":")) return value.substring(label.length() + 1).trim();
        }
        return "";
    }
    static String attribute(String tag, String name) {
        return entities(first(tag, "(?:^|\\s)" + Pattern.quote(name) + "\\s*=\\s*[\"]([^\"]*)[\"]|(?:^|\\s)" + Pattern.quote(name) + "\\s*=\\s*[']([^']*)[']"));
    }
    private static String openingByClass(String html, String cls) {
        Matcher tags = Pattern.compile("<[a-z][a-z0-9]*\\b[^>]*>", Pattern.CASE_INSENSITIVE).matcher(html);
        while (tags.find()) {
            for (String token : attribute(tags.group(), "class").split("\\s+")) {
                if (cls.equals(token)) return tags.group();
            }
        }
        return "";
    }
    private static String contentByClass(String html, String cls) {
        String opening = openingByClass(html, cls);
        if (opening.isEmpty()) return "";
        String tag = first(opening, "^<([a-z0-9]+)");
        int start = html.indexOf(opening) + opening.length();
        Matcher tags = Pattern.compile("</?" + Pattern.quote(tag) + "\\b[^>]*>", Pattern.CASE_INSENSITIVE).matcher(html);
        tags.region(start, html.length());
        int depth = 1;
        while (tags.find()) {
            if (tags.group().startsWith("</")) depth--; else if (!tags.group().endsWith("/>")) depth++;
            if (depth == 0) return html.substring(start, tags.start());
        }
        return "";
    }
    private static String first(String text, String regex) {
        Matcher matcher = Pattern.compile(regex, Pattern.CASE_INSENSITIVE).matcher(text == null ? "" : text);
        if (!matcher.find()) return "";
        for (int i = 1; i <= matcher.groupCount(); i++) if (matcher.group(i) != null) return matcher.group(i);
        return "";
    }
    private static String clean(String html) { return entities(html.replaceAll("<[^>]*>", " ")).replaceAll("\\s+", " ").trim(); }
    private static String entities(String text) {
        Matcher matcher = Pattern.compile("&(#x[0-9a-fA-F]+|#[0-9]+|amp|quot|apos|lt|gt|nbsp);", Pattern.CASE_INSENSITIVE).matcher(text);
        StringBuffer out = new StringBuffer();
        while (matcher.find()) {
            String name = matcher.group(1), replacement = matcher.group();
            if (name.startsWith("#")) {
                try {
                    int number = name.matches("(?i)#x.*") ? Integer.parseInt(name.substring(2), 16) : Integer.parseInt(name.substring(1));
                    if (Character.isValidCodePoint(number)) replacement = new String(Character.toChars(number));
                } catch (IllegalArgumentException ignored) { }
            } else {
                switch (name.toLowerCase(java.util.Locale.ROOT)) {
                    case "amp": replacement = "&"; break; case "quot": replacement = "\""; break;
                    case "apos": replacement = "'"; break; case "lt": replacement = "<"; break;
                    case "gt": replacement = ">"; break; case "nbsp": replacement = " "; break;
                }
            }
            matcher.appendReplacement(out, Matcher.quoteReplacement(replacement));
        }
        matcher.appendTail(out);
        return out.toString();
    }
}
