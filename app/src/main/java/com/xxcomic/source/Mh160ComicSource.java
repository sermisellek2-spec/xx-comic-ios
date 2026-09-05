package com.xxcomic.source;

import android.util.Base64;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** HTML adapter for 漫画160 (mh160mh.com). */
public final class Mh160ComicSource implements ComicSource {
    private static final String ID = "mh160";
    private static final String PREFIX = ID + ":";
    private static final String BASE = "https://www.mh160mh.com";
    private static final String IMAGE_BASE = "http://auto.mangafiles.com:88";
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
    private static final Pattern LINK = Pattern.compile("<a[^>]+href=[\\\"']([^\\\"']+)[\\\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE);
    private final SourceConfig config;

    public Mh160ComicSource() { this(SourceConfig.mh160(true)); }
    public Mh160ComicSource(SourceConfig config) { this.config = config == null ? SourceConfig.mh160(true) : config; }
    @Override public String id() { return config.id; }
    @Override public String name() { return config.name; }
    @Override public String domain() { return config.domain; }

    @Override public List<ComicModels.ComicSummary> latest(int page) throws IOException {
        String path = "/kanmanhua/all/" + (page > 1 ? page + ".html" : "");
        return parseCards(fetch(absolute(path)));
    }

    @Override public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
        String q = URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
        String path = config.route("search").replace("{keyword}", q)
                .replace("{pageQuery}", page > 1 ? "&page=" + page : "");
        return parseCards(fetch(absolute(path)));
    }

    @Override public List<String> categories() throws IOException {
        List<String> values = new ArrayList<>();
        for (ComicModels.FilterGroup group : filterGroups()) {
            for (ComicModels.FilterOption option : group.options) {
                if (!"all".equals(option.value) && !values.contains(option.label)) values.add(option.label);
            }
        }
        return values;
    }

    @Override public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        List<ComicModels.FilterGroup> groups = parseFilterGroups(fetch(absolute("/kanmanhua/all/")));
        if (groups.isEmpty()) throw new IOException(config.name + "分类解析失败");
        return groups;
    }

    @Override public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        Map<String, String> filters = new LinkedHashMap<>();
        if (state != null && !state.isEmpty()) filters.put("state", state);
        if (region != null && !region.isEmpty()) filters.put("region", region);
        return category(filters, page);
    }

    @Override public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        return parseCards(fetch(absolute(buildCategoryPath(filters, page))));
    }

    @Override public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String raw = rawComicId(comicId);
        String html = fetch(absolute("/kanmanhua/" + raw + "/"));
        ComicModels.ComicDetail parsed = parseDetail(raw, html);
        return new ComicModels.ComicDetail(parsed.summary, parsed.author, parsed.status,
                parsed.description, parsed.latestChapter, parseChapters(html, raw));
    }

    @Override public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String raw = rawComicId(comicId);
        List<ComicModels.Chapter> result = parseChapters(fetch(absolute("/kanmanhua/" + raw + "/")), raw);
        if (result.isEmpty()) throw new IOException(config.name + "目录解析失败");
        return result;
    }

    @Override public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = absolute(chapterUrl);
        String html = fetch(url);
        List<String> images = resolveChapterImages(html);
        if (images.isEmpty()) throw new IOException(config.name + "章节解析失败：缺少正文图片");
        String id = chapterIdFromUrl(url);
        String title = clean(first(html, "<title[^>]*>([\\s\\S]*?)</title>"));
        return new ComicModels.ChapterPage(id, title.isEmpty() ? id : title, images, "");
    }

    @Override public boolean healthCheck() {
        try { return fetch(absolute("/kanmanhua/all/")).contains("kanmanhua"); }
        catch (IOException ignored) { return false; }
    }

    static List<ComicModels.ComicSummary> parseCards(String html) {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        String list = first(html, "<ul[^>]*class=[\\\"'][^\\\"']*mh-search-list[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</ul>");
        if (list.isEmpty()) list = value(html);
        Matcher matcher = Pattern.compile("<li[^>]*>[\\s\\S]*?</li>", Pattern.CASE_INSENSITIVE).matcher(list);
        while (matcher.find()) {
            String card = matcher.group();
            String href = first(card, "<a[^>]+href=[\\\"']([^\\\"']*?/kanmanhua/[^\\\"']+)[\\\"']");
            String raw = rawComicIdStatic(href);
            if (raw.isEmpty() || !seen.add(raw)) continue;
            String imageTag = firstRaw(card, "<img[^>]*>");
            String title = clean(first(card, "<h[1-6][^>]*>\\s*<a[^>]*>([\\s\\S]*?)</a>"));
            if (title.isEmpty()) title = clean(first(card, "<a[^>]*title=[\\\"']([^\\\"']+)[\\\"']"));
            if (title.isEmpty()) title = clean(attr(imageTag, "alt"));
            if (title.isEmpty()) continue;
            String cover = imageUrl(imageTag);
            String tagBlock = first(card, "class=[\\\"'][^\\\"']*mh-works-tags[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</p>");
            List<String> tags = linkTexts(tagBlock);
            String subtitle = clean(first(card, "class=[\\\"'][^\\\"']*mh-works-author[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</p>"));
            subtitle = subtitle.replaceFirst("^状态[：:]\\s*", "");
            if (subtitle.isEmpty()) subtitle = clean(first(card, "class=[\\\"'][^\\\"']*cover-list-updata[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</p>"));
            result.add(new ComicModels.ComicSummary(ID, PREFIX + raw, title, absoluteImage(cover),
                    subtitle, tags));
        }
        return result;
    }

    static List<ComicModels.FilterGroup> parseFilterGroups(String html) {
        List<ComicModels.FilterGroup> result = new ArrayList<>();
        Matcher blocks = Pattern.compile("<div[^>]*class=[\\\"'][^\\\"']*mh-tags[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</div>\\s*</div>?", Pattern.CASE_INSENSITIVE).matcher(value(html));
        while (blocks.find()) {
            String block = blocks.group(1);
            String label = clean(first(block, "<h[1-6][^>]*>([\\s\\S]*?)</h[1-6]>"));
            if (label.isEmpty()) label = clean(first(block, "class=[\\\"'][^\\\"']*mh-tags-lx[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)<"));
            String key = keyFor(label);
            if (key.isEmpty()) continue;
            LinkedHashMap<String, String> options = new LinkedHashMap<>();
            options.put("全部", "all");
            Matcher links = LINK.matcher(block);
            while (links.find()) {
                String text = clean(links.group(2));
                String path = filterPath(links.group(1));
                if (!text.isEmpty() && !"全部".equals(text) && !options.containsKey(text)) options.put(text, path);
            }
            List<ComicModels.FilterOption> parsed = new ArrayList<>();
            for (Map.Entry<String, String> e : options.entrySet()) parsed.add(new ComicModels.FilterOption(e.getKey(), e.getValue()));
            result.add(new ComicModels.FilterGroup(key, "进度".equals(label) ? "状态" : label, parsed));
        }
        return result;
    }

    static String buildCategoryPath(Map<String, String> filters, int page) {
        StringBuilder path = new StringBuilder("/kanmanhua");
        if (filters != null) {
            for (String key : new String[]{"state", "subject", "region", "version", "audience", "special", "color", "quality", "letter"}) {
                String value = filters.get(key);
                if (value != null && !value.isEmpty() && !"all".equals(value)) {
                    path.append('/').append(value.startsWith("/") ? value.substring(1) : value);
                    break;
                }
            }
        }
        if (path.length() == 10) path.append("/all");
        path.append('/');
        if (page > 1) path.append(page).append(".html");
        return path.toString();
    }

    static ComicModels.ComicDetail parseDetail(String rawId, String html) throws IOException {
        String title = clean(first(html, "<div[^>]*class=[\\\"'][^\\\"']*mh-date-info-name[^\\\"']*[\\\"'][^>]*>[\\s\\S]*?<h[1-6][^>]*>([\\s\\S]*?)</h[1-6]>"));
        if (title.isEmpty()) title = clean(first(html, "<title[^>]*>([\\s\\S]*?)</title>"));
        if (title.isEmpty()) throw new IOException("漫画160详情解析失败：缺少标题");
        String coverBlock = firstRaw(html, "<div[^>]*class=[\\\"'][^\\\"']*mh-date-bgpic[^\\\"']*[\\\"'][^>]*>[\\s\\S]*?</div>");
        if (coverBlock.isEmpty()) coverBlock = firstRaw(html, "<div[^>]*class=[\\\"'][^\\\"']*mh-cover[^\\\"']*[\\\"'][^>]*>[\\s\\S]*?</div>");
        String cover = absoluteImage(imageUrl(firstRaw(coverBlock, "<img[^>]*>")));
        String author = labelled(html, "作者");
        String status = labelled(html, "状态");
        String desc = clean(first(html, "class=[\\\"'][^\\\"']*(?:work-introd|works-info-intro)[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</div>"));
        String labels = first(html, "class=[\\\"'][^\\\"']*mh-label[^\\\"']*[\\\"'][^>]*>([\\s\\S]*?)</div>");
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(ID, PREFIX + rawId, title, cover, author, linkTexts(labels));
        return new ComicModels.ComicDetail(summary, author, status, desc, "", new ArrayList<ComicModels.Chapter>());
    }

    static List<ComicModels.Chapter> parseChapters(String html, String comicId) {
        List<ComicModels.Chapter> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        String block = elementContentByClass(html, "cy_plist");
        Matcher matcher = Pattern.compile("<a[^>]+href=[\\\"']([^\\\"']+)[\\\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE).matcher(block);
        int index = 0;
        while (matcher.find()) {
            String href = decode(matcher.group(1));
            if (!href.matches("(?i)(?:https?://[^/]+)?/kanmanhua/" + Pattern.quote(comicId) + "/[^/]+\\.html(?:[?#].*)?")) continue;
            String url = absoluteDefault(href);
            if (!seen.add(url)) continue;
            String title = clean(matcher.group(2));
            if (!title.isEmpty()) result.add(new ComicModels.Chapter(chapterIdFromUrl(url), title, url, 0, index++));
        }
        if (result.isEmpty()) {
            Matcher direct = Pattern.compile("href=[\\\"']([^\\\"']*/kanmanhua/" + Pattern.quote(comicId) + "/[^\\\"']+\\.html)[\\\"']", Pattern.CASE_INSENSITIVE).matcher(value(html));
            if (direct.find()) { String url = absoluteDefault(direct.group(1)); result.add(new ComicModels.Chapter(chapterIdFromUrl(url), "在线阅读", url, 0, 0)); }
        }
        java.util.Collections.reverse(result);
        return result;
    }

    static List<String> parseChapterImages(String html) {
        List<String> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher var = Pattern.compile("qTcms_S_m_murl_e\\s*=\\s*[\\\"']([^\\\"']+)[\\\"']", Pattern.CASE_INSENSITIVE).matcher(value(html));
        if (!var.find()) return result;
        String encoded = decode(var.group(1));
        try {
            String payload = new String(decodeBase64(encoded), StandardCharsets.UTF_8);
            for (String part : payload.split("\\$qingtiandy\\$")) {
                String path = part.trim();
                if (path.isEmpty() || path.contains("recommend") || path.contains("tuijian")) continue;
                String image = path.startsWith("http") ? path : IMAGE_BASE + (path.startsWith("/") ? path : "/" + path);
                if (seen.add(image)) result.add(image);
            }
        } catch (IllegalArgumentException ignored) { }
        return result;
    }

    private static byte[] decodeBase64(String encoded) {
        try {
            byte[] decoded = Base64.decode(encoded, Base64.DEFAULT);
            if (decoded != null) return decoded;
        } catch (RuntimeException ignored) {
            // android.jar throws in local JVM tests; Android devices use the branch above.
        }
        try {
            Object decoder = Class.forName("java.util.Base64").getMethod("getDecoder").invoke(null);
            return (byte[]) decoder.getClass().getMethod("decode", String.class).invoke(decoder, encoded);
        } catch (ReflectiveOperationException error) {
            throw new IllegalArgumentException(error);
        }
    }

    static List<String> resolveChapterImages(String html) {
        List<String> images = parseChapterImages(html);
        String pageId = first(html, "qTcms_S_p_id\\s*=\\s*[\\\"'](\\d+)[\\\"']");
        String host = parseLong(pageId) > 542724L ? "https://xwdf.tgmhfc.uk" : "https://mhpic6.tgmhfc.uk";
        // The legacy host embedded in page scripts no longer resolves.
        for (int i = 0; i < images.size(); i++) {
            images.set(i, images.get(i).replace("http://auto.mangafiles.com:88", host));
        }
        return images;
    }

    private static long parseLong(String value) {
        try { return Long.parseLong(value); }
        catch (NumberFormatException ignored) { return Long.MAX_VALUE; }
    }

    private String fetch(String url) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setInstanceFollowRedirects(true); c.setConnectTimeout(10000); c.setReadTimeout(20000);
        c.setRequestProperty("User-Agent", UA); c.setRequestProperty("Referer", config.referer);
        try (InputStream in = c.getInputStream()) { ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] b = new byte[8192]; int n; while ((n = in.read(b)) != -1) out.write(b, 0, n); return out.toString(StandardCharsets.UTF_8.name()); }
        finally { c.disconnect(); }
    }
    private String absolute(String value) { String v = decode(value); if (v.startsWith("http://") || v.startsWith("https://")) return v; if (v.startsWith("//")) return "https:" + v; return BASE + (v.startsWith("/") ? v : "/" + v); }
    private static String absoluteDefault(String value) { String v = decode(value); if (v.startsWith("http://") || v.startsWith("https://")) return v; if (v.startsWith("//")) return "https:" + v; return BASE + (v.startsWith("/") ? v : "/" + v); }
    private static String absoluteImage(String value) { if (empty(value)) return ""; String v = decode(value).replaceAll("(@![^/?]+)+$", ""); if (v.startsWith("http://") || v.startsWith("https://")) return v; if (v.startsWith("//")) return "https:" + v; return BASE + (v.startsWith("/") ? v : "/" + v); }
    private String rawComicId(String value) { return rawComicIdStatic(value != null && value.startsWith(PREFIX) ? value.substring(PREFIX.length()) : value); }
    private static String rawComicIdStatic(String value) { if (empty(value)) return ""; String v = decode(value); int q = v.indexOf('?'); if (q >= 0) v = v.substring(0, q); while (v.endsWith("/")) v = v.substring(0, v.length() - 1); int i = v.lastIndexOf('/'); return (i >= 0 ? v.substring(i + 1) : v).replace(".html", "").trim(); }
    private static String chapterIdFromUrl(String value) { String v = value == null ? "" : value; Matcher m = Pattern.compile("/([^/]+)\\.html(?:[?#].*)?/?$").matcher(v); return m.find() ? m.group(1) : v; }
    private static String filterPath(String href) { String v = decode(href); int i = v.indexOf("/kanmanhua/"); if (i >= 0) v = v.substring(i + 11); v = v.replaceAll("/+$", ""); int q = v.indexOf('?'); if (q >= 0) v = v.substring(0, q); return v.isEmpty() || "all".equals(v) ? "all" : "/" + v; }
    private static String keyFor(String label) { if (label.contains("进度")) return "state"; if (label.contains("题材")) return "subject"; if (label.contains("地区")) return "region"; if (label.contains("版本")) return "version"; if (label.contains("读者")) return "audience"; if (label.contains("特殊")) return "special"; if (label.contains("颜色")) return "color"; if (label.contains("品质")) return "quality"; if (label.contains("字母")) return "letter"; return ""; }
    private static String labelled(String html, String label) { String v = clean(first(html, "<(?:p|span|li)[^>]*>([\\s\\S]*?" + Pattern.quote(label) + "[：:]?[\\s\\S]*?)</(?:p|span|li)>")); return v.replaceFirst("^.*?" + Pattern.quote(label) + "[：:]?\\s*", "").trim(); }
    private static List<String> linkTexts(String html) { List<String> r = new ArrayList<>(); Matcher m = Pattern.compile("<a[^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE).matcher(value(html)); while (m.find()) { String t = clean(m.group(1)); if (!t.isEmpty() && t.length() < 12 && !r.contains(t)) r.add(t); } return r; }
    private static String elementContentByClass(String html, String cls) { Matcher o = Pattern.compile("<([a-z0-9]+)[^>]*class=[\\\"'][^\\\"']*\\b" + Pattern.quote(cls) + "\\b[^\\\"']*[\\\"'][^>]*>", Pattern.CASE_INSENSITIVE).matcher(value(html)); if (!o.find()) return ""; String tag = o.group(1); Matcher t = Pattern.compile("</?" + tag + "\\b[^>]*>", Pattern.CASE_INSENSITIVE).matcher(html); t.region(o.end(), html.length()); int d = 1; while (t.find()) { if (t.group().startsWith("</")) d--; else if (!t.group().endsWith("/>") && !t.group().matches("(?i)<(?:img|br|input|meta|link)\\b[^>]*>")) d++; if (d == 0) return html.substring(o.end(), t.start()); } return html.substring(o.end()); }
    private static String imageUrl(String tag) { String v = attr(tag, "data-original"); if (empty(v)) v = attr(tag, "data-src"); if (empty(v)) v = attr(tag, "src"); return v; }
    private static String attr(String tag, String name) { return first(tag, "\\b" + Pattern.quote(name) + "=[\\\"']([^\\\"']*)[\\\"']"); }
    private static String firstRaw(String html, String regex) { Matcher m = Pattern.compile(regex, Pattern.CASE_INSENSITIVE).matcher(value(html)); return m.find() ? m.group() : ""; }
    private static String first(String html, String regex) { Matcher m = Pattern.compile(regex, Pattern.CASE_INSENSITIVE).matcher(value(html)); return m.find() ? m.group(1) : ""; }
    private static String clean(String v) { return decode(v).replaceAll("<[^>]+>", " ").replaceAll("\\s+", " ").trim(); }
    private static String decode(String v) { return value(v).replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'").replace("&nbsp;", " "); }
    private static String value(String v) { return v == null ? "" : v; }
    private static boolean empty(String v) { return v == null || v.trim().isEmpty(); }
}
