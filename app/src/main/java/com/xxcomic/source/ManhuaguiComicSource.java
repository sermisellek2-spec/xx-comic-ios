package com.xxcomic.source;

import android.os.Build;
import android.text.Html;
import android.text.TextUtils;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;

public class ManhuaguiComicSource implements ComicSource {
    private static final String SOURCE_ID = "manhuagui";
    private static final String PREFIX = SOURCE_ID + ":";
    private static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36";
    private static final Pattern BCOVER_BLOCK_PATTERN = Pattern.compile(
            "<a\\b(?=[^>]*\\bclass=[\"'][^\"']*\\bbcover\\b)[^>]*>[\\s\\S]*?</a>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern IMG_TAG_PATTERN = Pattern.compile(
            "<img\\b[^>]*>",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern CHAPTER_PATTERN = Pattern.compile(
            "<a[^>]*href=[\"'](/comic/\\d+/\\d+\\.html)[\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE);
    private static final Pattern META_PATTERN = Pattern.compile(
            "<meta[^>]+(?:property|name)=[\"']([^\"']+)[\"'][^>]+content=[\"']([^\"']*)[\"']", Pattern.CASE_INSENSITIVE);
    private final SourceConfig config;

    public ManhuaguiComicSource() {
        this(SourceConfig.manhuagui(true));
    }

    public ManhuaguiComicSource(SourceConfig config) {
        this.config = config == null ? SourceConfig.manhuagui(true) : config;
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
        return parseCards(fetch(absolute(config.route("search").replace("{keyword}", encoded))));
    }

    @Override
    public List<String> categories() {
        return new ArrayList<>(Arrays.asList("全部", "日本", "内地", "韩国", "港台", "欧美", "其它"));
    }

    @Override
    public List<ComicModels.FilterGroup> filterGroups() throws IOException {
        String html = fetch(absolute(config.route("category").replaceAll("\\{[^}]*\\}", "").replaceAll("/+$", "")));
        List<ComicModels.FilterGroup> groups = new ArrayList<>();
        String[][] definitions = {
                {"area", "region", "地区"}, {"genre", "genre", "剧情"}, {"age", "audience", "受众"},
                {"year", "year", "年份"}, {"letter", "letter", "字母"}, {"status", "state", "状态"}
        };
        for (String[] definition : definitions) {
            String block = first(html, "<div[^>]*class=[\"'][^\"']*\\bfilter\\b[^\"']*\\b" + definition[0] + "\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>");
            LinkedHashMap<String, String> values = new LinkedHashMap<>();
            Matcher links = Pattern.compile("<a[^>]+href=[\"']([^\"']*/list(?:/[^\"']*)?)[\"'][^>]*>([\\s\\S]*?)</a>", Pattern.CASE_INSENSITIVE).matcher(block);
            while (links.find()) {
                String label = clean(links.group(2));
                String path = decode(links.group(1));
                Matcher slug = Pattern.compile("/list/([^/]+)/?", Pattern.CASE_INSENSITIVE).matcher(path);
                String value = slug.find() ? slug.group(1) : "all";
                if (!TextUtils.isEmpty(label) && !"全部".equals(label)) values.put(label, value);
            }
            if (!values.isEmpty()) groups.add(SourceFilters.group(definition[1], definition[2], values));
        }
        if (groups.isEmpty()) throw new IOException(config.name + " 分类解析失败");
        return groups;
    }

    @Override
    public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException {
        return parseCards(fetch(categoryUrl(region, state, page)));
    }

    @Override
    public List<ComicModels.ComicSummary> category(Map<String, String> filters, int page) throws IOException {
        StringBuilder segment = new StringBuilder();
        for (String key : new String[]{"region", "genre", "audience", "year", "letter", "state"}) {
            String value = SourceFilters.value(filters, key, "all");
            if (!"all".equals(value)) {
                if (segment.length() > 0) segment.append('-');
                segment.append(value);
            }
        }
        String base = config.route("category").replaceAll("\\{[^}]*\\}", "").replaceAll("/+$", "");
        StringBuilder path = new StringBuilder(base);
        if (segment.length() > 0) path.append('/').append(segment);
        if (page > 1) path.append("/index_p").append(page).append(".html");
        return parseCards(fetch(absolute(path.toString())));
    }

    @Override
    public ComicModels.ComicDetail detail(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId).replaceAll("/+$", "")));
        String title = clean(first(html, "<h1[^>]*>([\\s\\S]*?)</h1>"));
        String cover = absoluteImage(cleanUrl(meta(html, "og:image")));
        if (TextUtils.isEmpty(cover)) {
            cover = absoluteImage(imageUrlFromTag(firstRaw(html, "<a[^>]+class=[\"'][^\"']*bcover[^\"']*[\"'][\\s\\S]*?<img[^>]+>")));
        }
        if (TextUtils.isEmpty(cover)) {
            cover = absoluteImage(imageUrlFromTag(firstRaw(html, "<div[^>]+class=[\"'][^\"']*(?:cover|thumb|book)[^\"']*[\"'][\\s\\S]*?<img\\b[^>]*>")));
        }
        if (TextUtils.isEmpty(cover)) {
            cover = "https://cf.mhgui.com/cpic/b/" + rawId + ".jpg";
        }
        String author = clean(first(html, "漫画作者[：:]?</strong>\\s*<a[^>]*>([\\s\\S]*?)</a>"));
        String status = clean(first(html, "漫画状态[：:]?</strong>\\s*<span[^>]*>([\\s\\S]*?)</span>"));
        String description = clean(first(html, "<div[^>]+id=[\"']intro-cut[\"'][^>]*>([\\s\\S]*?)</div>"));
        String latest = clean(first(html, "更新至\\s*\\[\\s*<a[^>]*>([\\s\\S]*?)</a>"));
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, "", new ArrayList<String>());
        return new ComicModels.ComicDetail(summary, author, status, description, latest, new ArrayList<ComicModels.Chapter>());
    }

    @Override
    public List<ComicModels.Chapter> chapters(String comicId) throws IOException {
        String rawId = rawComicId(comicId);
        String html = fetch(absolute(config.route("detail").replace("{comicId}", rawId).replaceAll("/+$", "")));
        List<ComicModels.Chapter> chapters = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Matcher a = CHAPTER_PATTERN.matcher(html);
        int index = 0;
        while (a.find()) {
            String href = a.group(1);
            if (!rawId.equals(rawComicId(href))) continue;
            if (!seen.add(href)) continue;
            String title = clean(attr(a.group(0), "title"));
            if (TextUtils.isEmpty(title)) title = clean(a.group(2));
            int chapterSlot = numericChapterId(href, index);
            chapters.add(new ComicModels.Chapter(rawChapterId(href), title, absolute(href), 0, chapterSlot));
            index++;
        }
        Collections.sort(chapters, new Comparator<ComicModels.Chapter>() {
            @Override
            public int compare(ComicModels.Chapter a, ComicModels.Chapter b) {
                return a.chapterSlot - b.chapterSlot;
            }
        });
        return chapters;
    }

    @Override
    public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException {
        String url = absolute(chapterUrl);
        String html = fetch(url, 15000, 30000);
        String title = clean(first(html, "<h2[^>]*>([\\s\\S]*?)</h2>"));
        String config = extractImgData(html);
        if (TextUtils.isEmpty(config)) throw new IOException(chapterConfigMissingMessage(url, html));
        List<String> images = buildImageUrls(config);
        if (images.isEmpty()) throw new IOException("Manhuagui chapter image list empty: " + url);
        return new ComicModels.ChapterPage(url, title, images, "");
    }

    // Chapter pages pack the image config with a dean-edwards packer; decode it to
    // SMH.imgData({"bid":..,"path":"/ps3/..","files":[..],"sl":{"e":..,"m":..}}).preInit()
    // then build https://eu2.hamreus.com + encodedPath + file + ?e=&m=.
    private static final String IMG_HOST = "https://eu2.hamreus.com";
    private static final String[] IMG_DATA_MARKERS = new String[] {
            "SMH.imgData",
            "SMH[\"imgData\"]",
            "SMH['imgData']"
    };
    private static final Pattern PACKER_ARGS_PATTERN = Pattern.compile(
            "\\(\\s*([\"'])((?:\\\\.|(?!\\1)[\\s\\S])*)\\1\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*([\"'])((?:\\\\.|(?!\\5)[\\s\\S])*)\\5\\s*(?:\\.\\s*split|\\[[^\\]]*\\])\\s*\\(\\s*([\"'])((?:\\\\.|(?!\\7)[\\s\\S])*)\\7\\s*\\)");

    private String extractImgData(String html) {
        return extractImgData(html, 0);
    }

    private String extractImgData(String html, int depth) {
        if (html == null) return "";
        if (depth > 4) return "";
        for (PackerArgs args : packerArgs(html)) {
            String config = extractImgData(unpackPacker(args), depth + 1);
            if (!TextUtils.isEmpty(config)) return config;
        }
        return validImgDataFromScript(html);
    }

    private List<PackerArgs> packerArgs(String html) {
        List<PackerArgs> result = new ArrayList<>();
        int search = 0;
        while (search < html.length()) {
            int fn = html.indexOf("function(p,a,c,k,e,d)", search);
            if (fn < 0) break;
            int brace = html.indexOf('{', fn);
            int end = matchingBrace(html, brace);
            int open = end > 0 ? html.indexOf('(', end + 1) : -1;
            PackerArgs args = open > 0 ? parsePackerInvocation(html, open) : null;
            if (args != null) result.add(args);
            search = Math.max(fn + 1, open + 1);
        }
        if (result.isEmpty()) {
            Matcher m = PACKER_ARGS_PATTERN.matcher(html);
            while (m.find()) result.add(new PackerArgs(unescapeJs(m.group(2)), Integer.parseInt(m.group(3)), Integer.parseInt(m.group(4)), unescapeJs(m.group(6)), unescapeJs(m.group(8))));
        }
        return result;
    }

    private PackerArgs parsePackerInvocation(String text, int open) {
        int pos = skipSpaces(text, open + 1);
        JsString payload = readJsString(text, pos);
        if (payload == null) return null;
        pos = skipComma(text, payload.next);
        IntRead radix = readInt(text, pos);
        if (radix == null) return null;
        pos = skipComma(text, radix.next);
        IntRead count = readInt(text, pos);
        if (count == null) return null;
        pos = skipComma(text, count.next);
        JsString dict = readJsString(text, pos);
        if (dict == null) return null;
        int dictEnd = findTopLevelComma(text, dict.next);
        if (dictEnd < 0) return null;
        String sep = "|";
        String tail = text.substring(dict.next, dictEnd);
        Matcher split = Pattern.compile("split\\s*\\(\\s*([\"'])((?:\\\\.|(?!\\1)[\\s\\S])*)\\1\\s*\\)").matcher(tail);
        if (split.find()) sep = unescapeJs(split.group(2));
        return new PackerArgs(payload.value, radix.value, count.value, dict.value, sep);
    }

    private String unpackPacker(PackerArgs args) {
        String[] dict = splitPackerDict(args.dict, args.sep, args.count);
        final String[] replacements = new String[Math.max(args.count, dict.length)];
        for (int i = replacements.length - 1; i >= 0; i--) {
            if (i < dict.length && !dict[i].isEmpty()) {
                replacements[i] = dict[i];
            }
        }
        Matcher tokens = Pattern.compile("[0-9A-Za-z]+").matcher(args.payload);
        StringBuffer out = new StringBuffer();
        while (tokens.find()) {
            int index = decodeToken(tokens.group(), args.radix);
            String replacement = index >= 0 && index < replacements.length ? replacements[index] : null;
            tokens.appendReplacement(out, Matcher.quoteReplacement(replacement == null ? tokens.group() : replacement));
        }
        tokens.appendTail(out);
        return out.toString();
    }

    private String[] splitPackerDict(String dictText, String sepText, int expectedCount) {
        String safeDict = dictText == null ? "" : dictText;
        String[] best = new String[] { safeDict };
        String[] candidates = new String[] { sepText, "|", "," };
        String decoded = decompressBase64Dict(safeDict);
        String[] dictCandidates = TextUtils.isEmpty(decoded) ? new String[] { safeDict } : new String[] { safeDict, decoded };
        for (String dict : dictCandidates) {
            for (String sep : candidates) {
                if (TextUtils.isEmpty(sep)) continue;
                String[] parts = dict.split(Pattern.quote(sep), -1);
                if (parts.length > best.length) best = parts;
                if (parts.length >= expectedCount) return parts;
            }
        }
        return best;
    }

    private String decompressBase64Dict(String value) {
        if (TextUtils.isEmpty(value) || !value.matches("[A-Za-z0-9+/]+=*")) return "";
        final String chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        return decompressLzString(value.length(), 32, new LzReader() {
            @Override public int valueAt(int index) {
                return index >= 0 && index < value.length() ? chars.indexOf(value.charAt(index)) : 0;
            }
        });
    }

    private String decompressLzString(int length, int resetValue, LzReader reader) {
        List<String> dictionary = new ArrayList<>();
        dictionary.add("0");
        dictionary.add("1");
        dictionary.add("2");
        int enlargeIn = 4;
        int dictSize = 4;
        int numBits = 3;
        LzData data = new LzData(reader.valueAt(0), resetValue, 1);
        int bits = readLzBits(data, resetValue, reader, 2);
        String c;
        if (bits == 0) {
            c = String.valueOf((char) readLzBits(data, resetValue, reader, 8));
        } else if (bits == 1) {
            c = String.valueOf((char) readLzBits(data, resetValue, reader, 16));
        } else {
            return "";
        }
        dictionary.add(c);
        String w = c;
        StringBuilder result = new StringBuilder(c);
        while (true) {
            if (data.index > length) return "";
            int code = readLzBits(data, resetValue, reader, numBits);
            if (code == 0) {
                dictionary.add(String.valueOf((char) readLzBits(data, resetValue, reader, 8)));
                code = dictSize++;
                enlargeIn--;
            } else if (code == 1) {
                dictionary.add(String.valueOf((char) readLzBits(data, resetValue, reader, 16)));
                code = dictSize++;
                enlargeIn--;
            } else if (code == 2) {
                return result.toString();
            }
            if (enlargeIn == 0) {
                enlargeIn = 1 << numBits;
                numBits++;
            }
            String entry;
            if (code >= 0 && code < dictionary.size() && dictionary.get(code) != null) {
                entry = dictionary.get(code);
            } else if (code == dictSize) {
                entry = w + w.charAt(0);
            } else {
                return "";
            }
            result.append(entry);
            dictionary.add(w + entry.charAt(0));
            dictSize++;
            enlargeIn--;
            w = entry;
            if (enlargeIn == 0) {
                enlargeIn = 1 << numBits;
                numBits++;
            }
        }
    }

    private int readLzBits(LzData data, int resetValue, LzReader reader, int count) {
        int bits = 0;
        int power = 1;
        int maxPower = 1 << count;
        while (power != maxPower) {
            int resb = data.value & data.position;
            data.position >>= 1;
            if (data.position == 0) {
                data.position = resetValue;
                data.value = reader.valueAt(data.index++);
            }
            if (resb > 0) bits |= power;
            power <<= 1;
        }
        return bits;
    }

    private interface LzReader {
        int valueAt(int index);
    }

    private static class LzData {
        int value;
        int position;
        int index;

        LzData(int value, int position, int index) {
            this.value = value;
            this.position = position;
            this.index = index;
        }
    }

    private int skipSpaces(String text, int pos) {
        while (pos < text.length() && Character.isWhitespace(text.charAt(pos))) pos++;
        return pos;
    }

    private int skipComma(String text, int pos) {
        pos = skipSpaces(text, pos);
        if (pos < text.length() && text.charAt(pos) == ',') pos++;
        return skipSpaces(text, pos);
    }

    private JsString readJsString(String text, int pos) {
        pos = skipSpaces(text, pos);
        if (pos >= text.length()) return null;
        char quote = text.charAt(pos);
        if (quote != '\'' && quote != '"') return null;
        StringBuilder raw = new StringBuilder();
        boolean escaping = false;
        for (int i = pos + 1; i < text.length(); i++) {
            char ch = text.charAt(i);
            if (escaping) {
                raw.append('\\').append(ch);
                escaping = false;
            } else if (ch == '\\') {
                escaping = true;
            } else if (ch == quote) {
                return new JsString(unescapeJs(raw.toString()), i + 1);
            } else {
                raw.append(ch);
            }
        }
        return null;
    }

    private IntRead readInt(String text, int pos) {
        pos = skipSpaces(text, pos);
        int start = pos;
        while (pos < text.length() && Character.isDigit(text.charAt(pos))) pos++;
        if (pos == start) return null;
        return new IntRead(Integer.parseInt(text.substring(start, pos)), pos);
    }

    private int findTopLevelComma(String text, int pos) {
        int paren = 0;
        boolean inString = false;
        boolean escaping = false;
        char quote = 0;
        for (int i = pos; i < text.length(); i++) {
            char ch = text.charAt(i);
            if (inString) {
                if (escaping) escaping = false;
                else if (ch == '\\') escaping = true;
                else if (ch == quote) inString = false;
                continue;
            }
            if (ch == '\'' || ch == '"') {
                inString = true;
                quote = ch;
            } else if (ch == '(') {
                paren++;
            } else if (ch == ')') {
                if (paren == 0) return i;
                paren--;
            } else if (ch == ',' && paren == 0) {
                return i;
            }
        }
        return -1;
    }

    private static class PackerArgs {
        final String payload;
        final int radix;
        final int count;
        final String dict;
        final String sep;

        PackerArgs(String payload, int radix, int count, String dict, String sep) {
            this.payload = payload;
            this.radix = radix;
            this.count = count;
            this.dict = dict;
            this.sep = sep;
        }
    }

    private static class JsString {
        final String value;
        final int next;

        JsString(String value, int next) {
            this.value = value;
            this.next = next;
        }
    }

    private static class IntRead {
        final int value;
        final int next;

        IntRead(int value, int next) {
            this.value = value;
            this.next = next;
        }
    }

    private String validImgDataFromScript(String script) {
        if (TextUtils.isEmpty(script)) return "";
        int searchFrom = 0;
        while (searchFrom < script.length()) {
            MarkerMatch marker = nextImgDataMarker(script, searchFrom);
            if (marker.index < 0) break;
            String config = configJsonAt(script, marker.index, marker.text);
            if (isValidImgData(config)) return config;
            String normalized = normalizeLooseJsonObject(config);
            if (!config.equals(normalized) && isValidImgData(normalized)) return normalized;
            searchFrom = marker.index + marker.text.length();
        }
        int objectSearch = 0;
        while (objectSearch < script.length()) {
            int start = script.indexOf('{', objectSearch);
            if (start < 0) return "";
            int end = matchingBrace(script, start);
            String candidate = start >= 0 && end > start ? script.substring(start, end + 1) : "";
            String canonical = canonicalImgData(candidate);
            if (isValidImgData(canonical)) return canonical;
            objectSearch = start + 1;
        }
        return "";
    }

    private MarkerMatch nextImgDataMarker(String script, int searchFrom) {
        MarkerMatch match = new MarkerMatch(-1, "");
        for (String marker : IMG_DATA_MARKERS) {
            int index = script.indexOf(marker, searchFrom);
            if (index >= 0 && (match.index < 0 || index < match.index)) {
                match = new MarkerMatch(index, marker);
            }
        }
        return match;
    }

    private String configJsonAt(String script, int marker, String markerText) {
        int openParen = script.indexOf('(', marker + markerText.length());
        int start = openParen >= 0 ? script.indexOf('{', openParen) : -1;
        int end = matchingBrace(script, start);
        if (start < 0 || end <= start) return "";
        return script.substring(start, end + 1);
    }

    private static class MarkerMatch {
        final int index;
        final String text;

        MarkerMatch(int index, String text) {
            this.index = index;
            this.text = text;
        }
    }

    private int matchingBrace(String text, int start) {
        if (TextUtils.isEmpty(text) || start < 0 || start >= text.length() || text.charAt(start) != '{') return -1;
        int depth = 0;
        boolean inString = false;
        boolean escaping = false;
        char quote = 0;
        for (int i = start; i < text.length(); i++) {
            char ch = text.charAt(i);
            if (inString) {
                if (escaping) {
                    escaping = false;
                } else if (ch == '\\') {
                    escaping = true;
                } else if (ch == quote) {
                    inString = false;
                }
                continue;
            }
            if (ch == '"' || ch == '\'') {
                inString = true;
                quote = ch;
            } else if (ch == '{') {
                depth++;
            } else if (ch == '}') {
                depth--;
                if (depth == 0) return i;
            }
        }
        return -1;
    }

    private boolean isValidImgData(String value) {
        if (TextUtils.isEmpty(value)) return false;
        try {
            JSONObject root = new JSONObject(value);
            return !TextUtils.isEmpty(root.optString("path"))
                    && root.optJSONArray("files") != null
                    && root.optJSONObject("sl") != null;
        } catch (JSONException ignored) {
            return false;
        }
    }

    private String canonicalImgData(String value) {
        if (TextUtils.isEmpty(value)) return "";
        try {
            JSONObject root = new JSONObject(normalizeLooseJsonObject(value));
            JSONArray files = root.optJSONArray("files");
            String path = root.optString("path");
            JSONObject sl = root.optJSONObject("sl");
            JSONArray names = root.names();
            for (int i = 0; names != null && i < names.length(); i++) {
                String key = names.optString(i);
                Object item = root.opt(key);
                if (files == null && item instanceof JSONArray && looksLikeFiles((JSONArray) item)) {
                    files = (JSONArray) item;
                } else if (TextUtils.isEmpty(path) && item instanceof String && looksLikePath((String) item)) {
                    path = (String) item;
                } else if (sl == null && item instanceof JSONObject) {
                    JSONObject object = (JSONObject) item;
                    if (object.has("e") || object.has("m")) sl = object;
                }
            }
            if (TextUtils.isEmpty(path) || files == null) return "";
            JSONObject canonical = new JSONObject();
            canonical.put("path", path);
            canonical.put("files", files);
            canonical.put("sl", sl == null ? new JSONObject() : sl);
            return canonical.toString();
        } catch (JSONException ignored) {
            return "";
        }
    }

    private boolean looksLikeFiles(JSONArray array) {
        if (array.length() == 0) return false;
        for (int i = 0; i < array.length(); i++) {
            String value = array.optString(i);
            if (!looksLikeImageFile(value)) return false;
        }
        return true;
    }

    private boolean looksLikePath(String value) {
        if (TextUtils.isEmpty(value) || !value.contains("/")) return false;
        return true;
    }

    private boolean looksLikeImageFile(String value) {
        if (TextUtils.isEmpty(value)) return false;
        return value.matches("(?i).+\\.(jpe?g|png|webp|gif|bmp)(\\?.*)?$");
    }

    private String normalizeLooseJsonObject(String value) {
        if (TextUtils.isEmpty(value)) return "";
        return value
                .replaceAll("([\\{,]\\s*)([A-Za-z_$][A-Za-z0-9_$]*)(\\s*:)", "$1\"$2\"$3")
                .replaceAll("(:\\s*)([A-Za-z_$][A-Za-z0-9_$]*|[0-9]+[A-Za-z_$][A-Za-z0-9_$]*)(\\s*[,}])", "$1\"$2\"$3");
    }

    private String base62(int c, int a) {
        if (c < a) {
            return (c > 35) ? String.valueOf((char) (c + 29)) : Integer.toString(c, 36);
        }
        return base62(c / a, a) + base62(c % a, a);
    }

    private String unescapeJs(String s) {
        if (s == null) return "";
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (ch == '\\' && i + 1 < s.length()) {
                char n = s.charAt(i + 1);
                if (n == '\'') { out.append('\''); i++; }
                else if (n == '"') { out.append('"'); i++; }
                else if (n == '\\') { out.append('\\'); i++; }
                else if (n == '/') { out.append('/'); i++; }
                else if (n == 'n') { out.append('\n'); i++; }
                else if (n == 'r') { out.append('\r'); i++; }
                else if (n == 't') { out.append('\t'); i++; }
                else if (n == 'b') { out.append('\b'); i++; }
                else if (n == 'f') { out.append('\f'); i++; }
                else if (n == 'x' && i + 3 < s.length()) {
                    try { out.append((char) Integer.parseInt(s.substring(i + 2, i + 4), 16)); i += 3; }
                    catch (Exception e) { out.append(n); }
                } else if (n == 'u' && i + 5 < s.length()) {
                    try { out.append((char) Integer.parseInt(s.substring(i + 2, i + 6), 16)); i += 5; }
                    catch (Exception e) { out.append(n); }
                } else { out.append(n); i++; }
            } else {
                out.append(ch);
            }
        }
        return out.toString();
    }

    private List<String> buildImageUrls(String configJson) throws IOException {
        List<String> images = new ArrayList<>();
        try {
            JSONObject root = new JSONObject(configJson);
            String path = root.optString("path");
            JSONObject sl = root.optJSONObject("sl");
            String e = sl == null ? "" : sl.optString("e");
            String m = sl == null ? "" : sl.optString("m");
            JSONArray files = root.optJSONArray("files");
            if (files == null || TextUtils.isEmpty(path)) return images;
            Set<String> seen = new LinkedHashSet<>();
            String encodedPath = encodePath(path);
            for (int i = 0; i < files.length(); i++) {
                String file = files.optString(i);
                if (TextUtils.isEmpty(file)) continue;
                String imageUrl = IMG_HOST + encodedPath + file + "?e=" + e + "&m=" + m;
                if (seen.add(imageUrl)) images.add(imageUrl);
            }
        } catch (JSONException error) {
            throw new IOException("Manhuagui config parse failed", error);
        }
        return images;
    }

    private String encodePath(String path) {
        StringBuilder sb = new StringBuilder();
        sb.append('/');
        for (String seg : path.replaceAll("^/+", "").replaceAll("/+$", "").split("/")) {
            if (TextUtils.isEmpty(seg)) continue;
            try {
                sb.append(URLEncoder.encode(seg, "UTF-8").replace("+", "%20"));
            } catch (Exception e) {
                sb.append(seg);
            }
            sb.append('/');
        }
        return sb.toString();
    }

    private String chapterConfigMissingMessage(String url, String html) {
        String body = html == null ? "" : html;
        String snippet = body.replaceAll("\\s+", " ").trim();
        if (snippet.length() > 500) snippet = snippet.substring(0, 500);
        List<PackerArgs> packers = packerArgs(body);
        int packerMatches = 0;
        String unpackedSnippet = "";
        String packerDebug = "";
        for (PackerArgs packer : packers) {
            packerMatches++;
            if (TextUtils.isEmpty(unpackedSnippet)) {
                unpackedSnippet = debugImgDataSnippet(unpackPacker(packer));
                packerDebug = debugPacker(packer);
            }
        }
        return "Manhuagui chapter config not found: " + url
                + "; len=" + body.length()
                + "; hasSMH=" + body.contains("SMH")
                + "; hasPacker=" + body.contains("function(p,a,c,k,e,d)")
                + "; packerMatches=" + packerMatches
                + "; packerDebug=" + packerDebug
                + "; unpackedSnippet=" + unpackedSnippet
                + "; snippet=" + snippet;
    }

    private String debugPacker(PackerArgs args) {
        try {
            int radix = args.radix;
            int count = args.count;
            String[] dict = splitPackerDict(args.dict, args.sep, count);
            StringBuilder out = new StringBuilder();
            out.append("radix=").append(radix)
                    .append(",count=").append(count)
                    .append(",sep=").append(cleanForDebug(args.sep))
                    .append(",dictRawLen=").append(args.dict == null ? 0 : args.dict.length())
                    .append(",dictLen=").append(dict.length)
                    .append(",dictSnippet=").append(cleanForDebug(args.dict));
            String[] tokens = new String[] {"3b", "1I", "1f", "1e", "1b", "1a", "18", "1g", "1h", "1c", "2a", "5", "1", "3", "16", "14", "13", "28", "27", "26"};
            for (String token : tokens) {
                int index = decodeToken(token, radix);
                out.append(",").append(token).append("@").append(index).append("=");
                if (index >= 0 && index < dict.length && !TextUtils.isEmpty(dict[index])) {
                    out.append(cleanForDebug(dict[index]));
                } else {
                    out.append("<empty>");
                }
            }
            return out.toString();
        } catch (Exception error) {
            return error.getClass().getSimpleName() + ":" + cleanForDebug(error.getMessage());
        }
    }

    private int decodeToken(String token, int radix) {
        if (TextUtils.isEmpty(token) || radix <= 1) return -1;
        int value = 0;
        for (int i = 0; i < token.length(); i++) {
            char ch = token.charAt(i);
            int digit;
            if (ch >= '0' && ch <= '9') digit = ch - '0';
            else if (ch >= 'a' && ch <= 'z') digit = ch - 'a' + 10;
            else if (ch >= 'A' && ch <= 'Z') digit = ch - 29;
            else return -1;
            if (digit < 0 || digit >= radix) return -1;
            value = value * radix + digit;
        }
        return value;
    }

    private String cleanForDebug(String value) {
        String text = value == null ? "" : value.replaceAll("\\s+", " ").trim();
        if (text.length() > 80) text = text.substring(0, 80);
        return text.replace(",", "，").replace(";", "；");
    }

    private String debugImgDataSnippet(String script) {
        String text = script == null ? "" : script.replaceAll("\\s+", " ").trim();
        int at = text.indexOf("imgData");
        if (at < 0) at = text.indexOf("SMH");
        if (at < 0) at = 0;
        int start = Math.max(0, at - 120);
        int end = Math.min(text.length(), at + 900);
        return text.substring(start, end);
    }

    @Override
    public boolean healthCheck() {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(config.baseUrl + "/list/").openConnection();
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

    private List<ComicModels.ComicSummary> parseCards(String html) throws IOException {
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        if (html == null) return result;
        Set<String> seen = new LinkedHashSet<>();
        Matcher matcher = BCOVER_BLOCK_PATTERN.matcher(html);
        while (matcher.find()) {
            String block = matcher.group(0);
            String href = attr(block, "href");
            String imageTag = firstRaw(block, "<img\\b[^>]*>");
            String title = clean(attr(block, "title"));
            if (TextUtils.isEmpty(title)) title = clean(attr(imageTag, "alt"));
            String cover = absoluteImage(imageUrlFromTag(imageTag));
            String rawId = rawComicId(href);
            if (TextUtils.isEmpty(rawId) || TextUtils.isEmpty(title) || !seen.add(rawId)) continue;
            result.add(new ComicModels.ComicSummary(SOURCE_ID, PREFIX + rawId, title, cover, "", new ArrayList<String>()));
        }
        if (result.isEmpty()) {
            throw new IOException("manhuagui parseCards empty; len=" + html.length()
                    + " hasBcover=" + html.contains("bcover")
                    + " snippet=" + html.substring(0, Math.min(600, html.length())));
        }
        return result;
    }

    private String categoryUrl(String region, String state, int page) {
        String segment = "";
        if (!TextUtils.isEmpty(region) && !"all".equals(region)) {
            segment = config.filter("region." + region);
        } else if (!TextUtils.isEmpty(state) && !"all".equals(state)) {
            segment = config.filter("state." + state);
        }
        String pagePath = page <= 1 ? "" : "index_p" + page + ".html";
        // manhuagui 404s on trailing-slash directory URLs; build /list[/segment][/pagePath] without one.
        // Strip any {placeholders} (a stale persisted config may still carry the old template) + trailing slash.
        String base = config.route("category").replaceAll("\\{[^}]*\\}", "").replaceAll("/+$", "");
        StringBuilder path = new StringBuilder(base);
        if (!TextUtils.isEmpty(segment)) path.append("/").append(segment);
        if (!TextUtils.isEmpty(pagePath)) path.append("/").append(pagePath);
        return absolute(path.toString());
    }

    private String fetch(String url) throws IOException {
        return fetch(url, 0, 10000, 15000);
    }

    private String fetch(String url, int connectTimeoutMs, int readTimeoutMs) throws IOException {
        return fetch(url, 0, connectTimeoutMs, readTimeoutMs);
    }

    private String fetch(String url, int redirects, int connectTimeoutMs, int readTimeoutMs) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(connectTimeoutMs);
        connection.setReadTimeout(readTimeoutMs);
        connection.setRequestProperty("User-Agent", UA);
        connection.setRequestProperty("Referer", config.referer);
        connection.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7");
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
        connection.setRequestProperty("Accept-Encoding", "gzip");
        // SEEMH anti-bot 404s requests missing browser-navigation fingerprint headers.
        connection.setRequestProperty("Upgrade-Insecure-Requests", "1");
        connection.setRequestProperty("Sec-Fetch-Dest", "document");
        connection.setRequestProperty("Sec-Fetch-Mode", "navigate");
        connection.setRequestProperty("Sec-Fetch-Site", "none");
        connection.setRequestProperty("Sec-Fetch-User", "?1");
        connection.setRequestProperty("sec-ch-ua", "\"Not;A=Brand\";v=\"8\", \"Chromium\";v=\"150\", \"Google Chrome\";v=\"150\"");
        connection.setRequestProperty("sec-ch-ua-mobile", "?0");
        connection.setRequestProperty("sec-ch-ua-platform", "\"Windows\"");
        int code = connection.getResponseCode();
        if (code >= 300 && code < 400 && redirects < 5) {
            String location = connection.getHeaderField("Location");
            connection.disconnect();
            if (!TextUtils.isEmpty(location)) return fetch(normalizeRedirectUrl(location), redirects + 1, connectTimeoutMs, readTimeoutMs);
        }
        try (InputStream raw = connection.getInputStream();
             InputStream stream = "gzip".equalsIgnoreCase(connection.getContentEncoding()) ? new GZIPInputStream(raw) : raw) {
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
        return first(html, "\\b" + name + "=[\"']([^\"']*)[\"']");
    }

    private String imageUrlFromTag(String tag) {
        String url = attr(tag, "data-src");
        if (TextUtils.isEmpty(url)) url = attr(tag, "data-original");
        if (TextUtils.isEmpty(url)) url = attr(tag, "src");
        return cleanUrl(url);
    }

    private String rawComicId(String value) {
        String raw = decode(value);
        if (raw.startsWith(PREFIX)) raw = raw.substring(PREFIX.length());
        Matcher m = Pattern.compile("/comic/(\\d+)/?").matcher(raw);
        if (m.find()) return m.group(1);
        m = Pattern.compile("(\\d+)").matcher(raw);
        return m.find() ? m.group(1) : raw.trim();
    }

    private String rawChapterId(String href) {
        Matcher m = Pattern.compile("/comic/\\d+/(\\d+)\\.html").matcher(decode(href));
        return m.find() ? m.group(1) : "";
    }

    private int numericChapterId(String href, int fallback) {
        String raw = rawChapterId(href);
        try {
            return TextUtils.isEmpty(raw) ? fallback : Integer.parseInt(raw);
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    private String absoluteImage(String url) {
        if (TextUtils.isEmpty(url)) return "";
        if (url.startsWith("//")) return "https:" + url;
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        return absolute(url);
    }

    private String absolute(String url) {
        if (TextUtils.isEmpty(url)) return "";
        if (url.startsWith("http://") || url.startsWith("https://")) return url;
        if (url.startsWith("//")) return "https:" + url;
        if (url.startsWith("/")) return config.baseUrl + url;
        return config.baseUrl + "/" + url;
    }

    private String normalizeRedirectUrl(String url) {
        String target = absolute(url);
        if (target.startsWith("http://" + config.domain)) {
            return "https://" + target.substring("http://".length());
        }
        return target;
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
