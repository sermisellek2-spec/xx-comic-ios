package com.xxcomic.download;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Inclusive, one-based selection against the chapter order currently shown to the user. */
public final class ChapterRangeSelection {
    private ChapterRangeSelection() { }

    public static <T> List<T> select(List<T> visible, int start, int end) {
        if (visible == null || visible.isEmpty() || start <= 0 || end <= 0) {
            return Collections.emptyList();
        }
        int low = Math.max(1, Math.min(start, end));
        int high = Math.min(visible.size(), Math.max(start, end));
        if (low > high) return Collections.emptyList();
        return new ArrayList<>(visible.subList(low - 1, high));
    }
}
