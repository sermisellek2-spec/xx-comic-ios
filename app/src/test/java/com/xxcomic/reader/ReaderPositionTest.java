package com.xxcomic.reader;

import org.junit.Test;
import static org.junit.Assert.*;

public class ReaderPositionTest {
    @Test public void oldProgressRestoresImageAndOffset() {
        ReaderPosition p = ReaderPosition.fromLegacy(3750, 8);
        assertEquals(3, p.imageIndex);
        assertEquals(0, p.offset, .0001);
        assertEquals(3750, p.legacyProgress(8));
        p = ReaderPosition.fromLegacy(4200, 8);
        assertEquals(3, p.imageIndex);
        assertEquals(.36, p.offset, .0001);
    }
    @Test public void shortenedChapterClampsImage() {
        assertEquals(2, new ReaderPosition(9, .5, false).indexFor(3));
        assertEquals(0, ReaderPosition.fromLegacy(5000, 0).imageIndex);
    }
    @Test public void completedChapterRestoresLastImage() {
        ReaderPosition p = ReaderPosition.fromLegacy(10000, 8);
        assertEquals(7, p.imageIndex);
        assertTrue(p.atEnd);
        assertEquals(10000, p.legacyProgress(8));
    }
    @Test public void invalidOffsetIsSafe() {
        assertEquals(0, new ReaderPosition(-1, Double.NaN, false).offset, 0);
        assertEquals(1, new ReaderPosition(0, 2, false).offset, 0);
    }
    @Test public void handDirectionDoesNotReverseLogicalPageOrder() {
        assertEquals(1, ReaderNavigation.tapDelta(true, true));
        assertEquals(1, ReaderNavigation.tapDelta(false, false));
        assertEquals(1, ReaderNavigation.swipeDelta(100, true));
        assertEquals(1, ReaderNavigation.swipeDelta(-100, false));
        assertEquals(-1, ReaderNavigation.swipeDelta(-100, true));
    }
    @Test public void chapterChangesOnlyBeyondBoundary() {
        assertFalse(ReaderNavigation.crossesChapter(0, 3, 1));
        assertFalse(ReaderNavigation.crossesChapter(2, 3, -1));
        assertTrue(ReaderNavigation.crossesChapter(2, 3, 1));
        assertTrue(ReaderNavigation.crossesChapter(0, 3, -1));
        assertFalse(ReaderNavigation.crossesChapter(0, 0, 1));
    }
}
