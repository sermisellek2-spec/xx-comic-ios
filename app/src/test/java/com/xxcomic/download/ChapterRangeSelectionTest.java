package com.xxcomic.download;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class ChapterRangeSelectionTest {
    @Test public void selectsInclusiveOneBasedRange() {
        assertEquals(Arrays.asList("c2", "c3", "c4"),
                ChapterRangeSelection.select(Arrays.asList("c1", "c2", "c3", "c4", "c5"), 2, 4));
    }

    @Test public void normalizesReverseAndClampsBounds() {
        assertEquals(Arrays.asList("c2", "c3"),
                ChapterRangeSelection.select(Arrays.asList("c1", "c2", "c3"), 9, 2));
    }

    @Test public void emptyListOrZeroRangeReturnsEmpty() {
        assertTrue(ChapterRangeSelection.select(Collections.<String>emptyList(), 1, 2).isEmpty());
        assertTrue(ChapterRangeSelection.select(Arrays.asList("c1"), 0, 0).isEmpty());
    }
}
