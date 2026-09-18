package com.xxcomic.local;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Plans a batch without opening or decoding the file contents. */
public final class BatchImportPlanner {
    private static final Pattern EXTENSION = Pattern.compile("(?i)\\.[a-z0-9]{1,8}$");
    private static final Pattern VOLUME = Pattern.compile(
            "(?i)(?:第\\s*(\\d+)\\s*[卷册集话章]|(?:vol(?:ume)?|v)\\.?\\s*(\\d+)|(?:^|[\\s_\\-()\\[\\]])(\\d{1,4})(?=\\D*$))");

    private BatchImportPlanner() {}

    public static List<BatchImportModels.ImportGroup> plan(List<BatchImportModels.FileCandidate> candidates) {
        if (candidates == null || candidates.isEmpty()) return Collections.emptyList();
        Map<String, MutableGroup> grouped = new LinkedHashMap<>();
        for (BatchImportModels.FileCandidate candidate : candidates) {
            if (candidate == null) continue;
            String key = groupKey(candidate);
            MutableGroup group = grouped.get(key);
            if (group == null) {
                String title = candidate.seriesTitle.isEmpty()
                        ? normalizeTitle(candidate.fileName) : candidate.seriesTitle;
                group = new MutableGroup(key, title, candidate.sourceId.isEmpty() || candidate.remoteComicId.isEmpty());
                grouped.put(key, group);
            }
            if (!containsFingerprint(group.files, candidate)) group.files.add(candidate);
        }

        List<BatchImportModels.ImportGroup> result = new ArrayList<>();
        for (MutableGroup group : grouped.values()) {
            Collections.sort(group.files, VOLUME_ORDER);
            result.add(new BatchImportModels.ImportGroup(group.key, group.title,
                    group.requiresConfirmation, group.files));
        }
        return Collections.unmodifiableList(result);
    }

    public static String normalizeTitle(String fileName) {
        String value = fileName == null ? "" : fileName.trim();
        value = EXTENSION.matcher(value).replaceFirst("");
        value = value.replace('\u3000', ' ').trim();
        value = value.replaceFirst("(?i)[\\s_\\-()\\[\\]]*(?:第\\s*\\d+\\s*[卷册集话章]|(?:vol(?:ume)?|v)\\.?\\s*\\d+|\\d{1,4})\\s*$", "");
        value = value.replaceAll("[\\s_\\-]+$", "").replaceAll("\\s+", " ").trim();
        return value.isEmpty() ? "未命名漫画" : value;
    }

    public static int volumeNumber(String fileName) {
        String value = fileName == null ? "" : fileName;
        Matcher matcher = VOLUME.matcher(value);
        int result = -1;
        while (matcher.find()) {
            String number = matcher.group(1) != null ? matcher.group(1)
                    : matcher.group(2) != null ? matcher.group(2) : matcher.group(3);
            try { result = Integer.parseInt(number); } catch (Exception ignored) {}
        }
        return result;
    }

    private static String groupKey(BatchImportModels.FileCandidate candidate) {
        if (!candidate.sourceId.isEmpty() && !candidate.remoteComicId.isEmpty()) {
            return "remote:" + candidate.sourceId + ":" + candidate.remoteComicId;
        }
        String title = candidate.seriesTitle.isEmpty()
                ? normalizeTitle(candidate.fileName) : candidate.seriesTitle;
        return "local:" + title.toLowerCase(Locale.ROOT);
    }

    private static boolean containsFingerprint(List<BatchImportModels.FileCandidate> files,
                                               BatchImportModels.FileCandidate candidate) {
        if (candidate.fingerprint.isEmpty()) return false;
        for (BatchImportModels.FileCandidate existing : files) {
            if (candidate.fingerprint.equalsIgnoreCase(existing.fingerprint)) return true;
        }
        return false;
    }

    private static final Comparator<BatchImportModels.FileCandidate> VOLUME_ORDER =
            new Comparator<BatchImportModels.FileCandidate>() {
                @Override public int compare(BatchImportModels.FileCandidate a,
                                              BatchImportModels.FileCandidate b) {
                    if (a.sourceOrder != null && b.sourceOrder != null && !a.sourceOrder.equals(b.sourceOrder)) {
                        return Integer.compare(a.sourceOrder, b.sourceOrder);
                    }
                    if (a.sourceOrder != null && b.sourceOrder == null) return -1;
                    if (a.sourceOrder == null && b.sourceOrder != null) return 1;
                    int av = volumeNumber(a.fileName), bv = volumeNumber(b.fileName);
                    if (av >= 0 && bv >= 0 && av != bv) return Integer.compare(av, bv);
                    if (av >= 0 && bv < 0) return -1;
                    if (av < 0 && bv >= 0) return 1;
                    int byName = new NaturalPathOrder().compare(a.fileName, b.fileName);
                    return byName != 0 ? byName : Integer.compare(a.selectionIndex, b.selectionIndex);
                }
            };

    private static final class MutableGroup {
        final String key;
        final String title;
        final boolean requiresConfirmation;
        final List<BatchImportModels.FileCandidate> files = new ArrayList<>();

        MutableGroup(String key, String title, boolean requiresConfirmation) {
            this.key = key;
            this.title = title;
            this.requiresConfirmation = requiresConfirmation;
        }
    }
}
