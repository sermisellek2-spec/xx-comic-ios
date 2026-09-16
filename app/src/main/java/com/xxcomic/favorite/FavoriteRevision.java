package com.xxcomic.favorite;

import com.xxcomic.source.ComicModels;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class FavoriteRevision {
    public static final int FORMAT_VERSION = 1;
    public static final String MODE_CHAPTER_SET = "CHAPTER_SET";
    public static final String MODE_LATEST_CHAPTER = "LATEST_CHAPTER";

    public final int formatVersion;
    public final String mode;
    public final Set<String> chapterIds;
    public final String latestChapterId;
    public final String latestChapterName;
    public final Long chapterNumber;
    public final int chapterCount;
    public final long timestamp;

    public FavoriteRevision(int formatVersion, String mode, Set<String> chapterIds,
                            String latestChapterId, String latestChapterName,
                            Long chapterNumber, int chapterCount, long timestamp) {
        this.formatVersion = formatVersion;
        this.mode = mode == null ? MODE_CHAPTER_SET : mode;
        this.chapterIds = chapterIds == null ? Collections.emptySet() : Collections.unmodifiableSet(new LinkedHashSet<>(chapterIds));
        this.latestChapterId = latestChapterId == null ? "" : latestChapterId;
        this.latestChapterName = latestChapterName == null ? "" : latestChapterName;
        this.chapterNumber = chapterNumber;
        this.chapterCount = chapterCount;
        this.timestamp = timestamp;
    }

    public static FavoriteRevision fromChapters(String latestChapterName, List<ComicModels.Chapter> chapters) {
        if (chapters == null || chapters.isEmpty()) {
            Long number = extractChapterNumber(latestChapterName);
            return new FavoriteRevision(FORMAT_VERSION, MODE_LATEST_CHAPTER,
                    Collections.emptySet(), "", latestChapterName, number, 0, System.currentTimeMillis());
        }
        Set<String> ids = new LinkedHashSet<>();
        String lastId = "";
        String lastName = "";
        Long maxNumber = null;
        for (ComicModels.Chapter c : chapters) {
            String id = canonicalChapterId(c);
            if (!isEmpty(id)) {
                ids.add(id);
                lastId = id;
            }
            lastName = c.title;
            Long num = extractChapterNumber(c.title);
            if (num != null) {
                if (maxNumber == null || num > maxNumber) {
                    maxNumber = num;
                }
            }
        }
        String resolvedName = isEmpty(latestChapterName) ? lastName : latestChapterName;
        if (maxNumber == null) {
            maxNumber = extractChapterNumber(resolvedName);
        }
        return new FavoriteRevision(FORMAT_VERSION, MODE_CHAPTER_SET, ids,
                lastId, resolvedName, maxNumber, ids.size(), System.currentTimeMillis());
    }

    public static FavoriteRevision fromDetail(ComicModels.ComicDetail detail) {
        if (detail == null) {
            return null;
        }
        if (detail.chapters != null && !detail.chapters.isEmpty()) {
            return fromChapters(detail.latestChapter, detail.chapters);
        }
        String latestName = detail.latestChapter != null ? detail.latestChapter : "";
        Long number = extractChapterNumber(latestName);
        return new FavoriteRevision(FORMAT_VERSION, MODE_LATEST_CHAPTER,
                Collections.emptySet(), "", latestName, number, 0, System.currentTimeMillis());
    }

    public static boolean hasNewChapters(FavoriteRevision baseline, FavoriteRevision candidate) {
        if (baseline == null || candidate == null) {
            return false;
        }
        // Candidate has a full chapter set
        if (MODE_CHAPTER_SET.equals(candidate.mode)) {
            if (MODE_CHAPTER_SET.equals(baseline.mode)) {
                if (baseline.chapterIds.isEmpty()) {
                    return false;
                }
                Set<String> newIds = new HashSet<>(candidate.chapterIds);
                newIds.removeAll(baseline.chapterIds);
                return !newIds.isEmpty();
            } else if (MODE_LATEST_CHAPTER.equals(baseline.mode)) {
                if (baseline.chapterNumber != null && candidate.chapterNumber != null) {
                    return candidate.chapterNumber > baseline.chapterNumber;
                }
                return false;
            }
        }
        // Candidate only has latest chapter string/number
        if (MODE_LATEST_CHAPTER.equals(candidate.mode)) {
            if (baseline.chapterNumber != null && candidate.chapterNumber != null) {
                return candidate.chapterNumber > baseline.chapterNumber;
            }
            return false;
        }
        return false;
    }

    public static String canonicalChapterId(ComicModels.Chapter chapter) {
        if (chapter == null) return "";
        if (!isEmpty(chapter.chapterId)) {
            return chapter.chapterId.trim();
        }
        return normalizeChapterUrl(chapter.url);
    }

    public static String normalizeChapterUrl(String url) {
        if (url == null) return "";
        String cleaned = url.trim();
        int hashIdx = cleaned.indexOf('#');
        if (hashIdx >= 0) cleaned = cleaned.substring(0, hashIdx);
        int queryIdx = cleaned.indexOf('?');
        if (queryIdx >= 0) {
            String base = cleaned.substring(0, queryIdx);
            String query = cleaned.substring(queryIdx + 1);
            List<String> preserved = new ArrayList<>();
            for (String param : query.split("&")) {
                if (param.startsWith("section_slot=") || param.startsWith("chapter_slot=")) {
                    preserved.add(param);
                }
            }
            cleaned = preserved.isEmpty() ? base : base + "?" + join("&", preserved);
        }
        if (cleaned.startsWith("http://") || cleaned.startsWith("https://")) {
            int slashIdx = cleaned.indexOf('/', cleaned.indexOf("://") + 3);
            if (slashIdx >= 0) cleaned = cleaned.substring(slashIdx);
        }
        return cleaned;
    }

    public static Long extractChapterNumber(String title) {
        if (title == null) return null;
        Matcher m = Pattern.compile("(\\d+)").matcher(title);
        if (m.find()) {
            try {
                return Long.parseLong(m.group(1));
            } catch (NumberFormatException ignored) {
            }
        }
        return null;
    }

    public JSONObject toJson() throws JSONException {
        JSONObject object = new JSONObject();
        object.put("formatVersion", formatVersion);
        object.put("mode", mode);
        JSONArray array = new JSONArray();
        for (String id : chapterIds) {
            array.put(id);
        }
        object.put("chapterIds", array);
        object.put("latestChapterId", latestChapterId);
        object.put("latestChapterName", latestChapterName);
        if (chapterNumber != null) {
            object.put("chapterNumber", chapterNumber.longValue());
        }
        object.put("chapterCount", chapterCount);
        object.put("timestamp", timestamp);
        return object;
    }

    public static FavoriteRevision fromJson(JSONObject object) {
        if (object == null) return null;
        int version = object.optInt("formatVersion", FORMAT_VERSION);
        String mode = object.optString("mode", MODE_CHAPTER_SET);
        Set<String> ids = new LinkedHashSet<>();
        JSONArray array = object.optJSONArray("chapterIds");
        if (array != null) {
            for (int i = 0; i < array.length(); i++) {
                String id = array.optString(i, "");
                if (!isEmpty(id)) ids.add(id);
            }
        }
        String latestChapterId = object.optString("latestChapterId", "");
        String latestChapterName = object.optString("latestChapterName", "");
        Long chapterNumber = object.has("chapterNumber") ? object.optLong("chapterNumber") : null;
        int count = object.optInt("chapterCount", ids.size());
        long timestamp = object.optLong("timestamp", 0L);
        return new FavoriteRevision(version, mode, ids, latestChapterId, latestChapterName, chapterNumber, count, timestamp);
    }

    private static boolean isEmpty(String str) {
        return str == null || str.isEmpty();
    }

    private static String join(CharSequence delimiter, Iterable<? extends CharSequence> elements) {
        StringBuilder sb = new StringBuilder();
        boolean first = true;
        for (CharSequence element : elements) {
            if (first) {
                first = false;
            } else {
                sb.append(delimiter);
            }
            sb.append(element);
        }
        return sb.toString();
    }
}
