package com.xxcomic.source;

import java.util.List;

public final class SourceSwitchMatcher {
    private SourceSwitchMatcher() { }

    public static ComicModels.ComicSummary firstExactMatch(
            String title, List<ComicModels.ComicSummary> results, String sourceId) {
        if (title == null || title.trim().isEmpty() || results == null) return null;
        String expected = title.trim();
        for (ComicModels.ComicSummary item : results) {
            if (item != null && sourceId.equals(item.sourceId) && item.title != null
                    && item.comicId != null && !item.comicId.isEmpty()
                    && expected.equals(item.title.trim())) return item;
        }
        return null;
    }
}
