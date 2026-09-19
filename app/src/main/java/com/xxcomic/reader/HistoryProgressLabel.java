package com.xxcomic.reader;

import java.util.List;

/**
 * Pure display formatting rules for reading history chapter progress labels.
 */
public final class HistoryProgressLabel {
    private HistoryProgressLabel() {}

    public static String label(int savedIndex, List<String> chapterTitles) {
        if (savedIndex < 0) {
            return "有阅读记录";
        }
        if (chapterTitles == null || chapterTitles.isEmpty()) {
            return "上次看到 第 " + (savedIndex + 1) + " 章";
        }
        if (savedIndex < chapterTitles.size()) {
            String title = chapterTitles.get(savedIndex);
            if (title == null || title.trim().isEmpty()) {
                return "上次看到 第 " + (savedIndex + 1) + " 章";
            }
            return "上次看到 · " + title.trim();
        }
        return "目录已更新 · 点击继续";
    }
}
