package com.xxcomic.reader;

import org.junit.Test;
import static org.junit.Assert.*;

public class ReaderSettingsSheetTest {

    @Test
    public void scrollModeMapsCorrectly() {
        assertEquals(ReaderSettingsSheet.MODE_SCROLL, ReaderSettingsSheet.toReadingMode(0, false));
        assertEquals(ReaderSettingsSheet.MODE_SCROLL, ReaderSettingsSheet.toReadingMode(0, true));
        assertEquals(0, ReaderSettingsSheet.toLayoutMode(ReaderSettingsSheet.MODE_SCROLL));
        assertFalse(ReaderSettingsSheet.toLeftHand(ReaderSettingsSheet.MODE_SCROLL));
    }

    @Test
    public void normalModeMapsCorrectly() {
        assertEquals(ReaderSettingsSheet.MODE_NORMAL, ReaderSettingsSheet.toReadingMode(1, false));
        assertEquals(1, ReaderSettingsSheet.toLayoutMode(ReaderSettingsSheet.MODE_NORMAL));
        assertFalse(ReaderSettingsSheet.toLeftHand(ReaderSettingsSheet.MODE_NORMAL));
    }

    @Test
    public void mangaModeMapsCorrectly() {
        assertEquals(ReaderSettingsSheet.MODE_MANGA, ReaderSettingsSheet.toReadingMode(1, true));
        assertEquals(1, ReaderSettingsSheet.toLayoutMode(ReaderSettingsSheet.MODE_MANGA));
        assertTrue(ReaderSettingsSheet.toLeftHand(ReaderSettingsSheet.MODE_MANGA));
    }

    @Test
    public void roundTripConversionPreservesReadingModes() {
        int[] modes = new int[]{
                ReaderSettingsSheet.MODE_SCROLL,
                ReaderSettingsSheet.MODE_NORMAL,
                ReaderSettingsSheet.MODE_MANGA
        };
        for (int mode : modes) {
            int layout = ReaderSettingsSheet.toLayoutMode(mode);
            boolean leftHand = ReaderSettingsSheet.toLeftHand(mode);
            int roundTrip = ReaderSettingsSheet.toReadingMode(layout, leftHand);
            assertEquals(mode, roundTrip);
        }
    }

    @Test
    public void chapterContinuityCrossesBoundariesCorrectly() {
        // At page 0, moving backward (-1) crosses chapter to previous
        assertTrue(ReaderNavigation.crossesChapter(0, 20, -1));
        assertFalse(ReaderNavigation.crossesChapter(0, 20, 1));

        // In middle of chapter, moving forward or backward does not cross
        assertFalse(ReaderNavigation.crossesChapter(10, 20, 1));
        assertFalse(ReaderNavigation.crossesChapter(10, 20, -1));

        // At last page, moving forward (1) crosses chapter to next
        assertTrue(ReaderNavigation.crossesChapter(19, 20, 1));
        assertFalse(ReaderNavigation.crossesChapter(19, 20, -1));

        // Swipe deltas: LTR (leftHand = false): swipe left (dx < 0) goes forward (1)
        assertEquals(1, ReaderNavigation.swipeDelta(-50f, false));
        assertEquals(-1, ReaderNavigation.swipeDelta(50f, false));

        // Swipe deltas: RTL (leftHand = true): swipe right (dx > 0) goes forward (1)
        assertEquals(1, ReaderNavigation.swipeDelta(50f, true));
        assertEquals(-1, ReaderNavigation.swipeDelta(-50f, true));
    }
}
