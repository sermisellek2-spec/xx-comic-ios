package com.xxcomic.source;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

public class SourceSwitchMatcherTest {
    @Test
    public void rejectsEmptyInvalidAndCaseDifferentTitles() {
        ComicModels.ComicSummary wrongCase = new ComicModels.ComicSummary(
                "gmh", "1", "comic", "", "", null);
        ComicModels.ComicSummary missingId = new ComicModels.ComicSummary(
                "gmh", "", "Comic", "", "", null);
        assertNull(SourceSwitchMatcher.firstExactMatch("Comic",
                Arrays.asList(null, wrongCase, missingId), "gmh"));
        assertNull(SourceSwitchMatcher.firstExactMatch(" ", Collections.emptyList(), "gmh"));
        assertNull(SourceSwitchMatcher.firstExactMatch("Comic", null, "gmh"));
    }

    @Test
    public void returnsFirstStrictTitleMatchForRequestedSource() {
        ComicModels.ComicSummary first = new ComicModels.ComicSummary(
                "baozi", "1", "我独自升级", "", "", Collections.emptyList());
        ComicModels.ComicSummary exact = new ComicModels.ComicSummary(
                "gmh", "2", "  我独自升级 ", "", "", Collections.emptyList());
        ComicModels.ComicSummary later = new ComicModels.ComicSummary(
                "gmh", "3", "我独自升级", "", "", Collections.emptyList());

        assertEquals("2", SourceSwitchMatcher.firstExactMatch(
                "我独自升级", Arrays.asList(first, exact, later), "gmh").comicId);
    }

    @Test
    public void doesNotUsePartialOrDifferentSourceMatch() {
        ComicModels.ComicSummary partial = new ComicModels.ComicSummary(
                "gmh", "1", "我独自升级：外传", "", "", Collections.emptyList());
        ComicModels.ComicSummary other = new ComicModels.ComicSummary(
                "baozi", "2", "我独自升级", "", "", Collections.emptyList());

        assertNull(SourceSwitchMatcher.firstExactMatch(
                "我独自升级", Arrays.asList(partial, other), "gmh"));
    }
}
