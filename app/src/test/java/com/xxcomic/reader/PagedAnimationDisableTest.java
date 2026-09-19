package com.xxcomic.reader;

import org.junit.Test;
import static org.junit.Assert.*;

public class PagedAnimationDisableTest {

    @Test
    public void listenerDefaultMethodsDoNotThrow() {
        ReaderSettingsSheet.OnSettingsChangeListener listener = new ReaderSettingsSheet.OnSettingsChangeListener() {
            @Override public void onReadingModeChanged(int mode) {}
            @Override public void onHideStatusBadgeChanged(boolean hide) {}
            @Override public void onEinkModeChanged(boolean eink) {}
            @Override public void onPinchZoomChanged(boolean enabled) {}
        };
        // Should execute default implementations without exception
        listener.onDisablePageAnimationChanged(true);
        listener.onDisablePageAnimationChanged(false);
        listener.onCropWhiteMarginsChanged(true);
        listener.onCropWhiteMarginsChanged(false);
    }

    @Test
    public void listenerCapturesDisablePageAnimationChanges() {
        final boolean[] captured = new boolean[]{false};
        ReaderSettingsSheet.OnSettingsChangeListener listener = new ReaderSettingsSheet.OnSettingsChangeListener() {
            @Override public void onReadingModeChanged(int mode) {}
            @Override public void onHideStatusBadgeChanged(boolean hide) {}
            @Override public void onEinkModeChanged(boolean eink) {}
            @Override public void onPinchZoomChanged(boolean enabled) {}
            @Override public void onDisablePageAnimationChanged(boolean disabled) {
                captured[0] = disabled;
            }
        };

        listener.onDisablePageAnimationChanged(true);
        assertTrue(captured[0]);

        listener.onDisablePageAnimationChanged(false);
        assertFalse(captured[0]);
    }

    @Test
    public void swipeGestureEvaluationConditions() {
        float density = 2.0f; // 2.0 density for dp calculation: dp(36) = 72px
        float minSwipePx = 36f * density;

        // Valid swipe left (LTR): dx = -80px, dy = 10px, duration = 300ms
        float dx = -80f;
        float dy = 10f;
        long duration = 300L;
        boolean isHorizontal = Math.abs(dx) > minSwipePx && Math.abs(dx) > Math.abs(dy) * 1.1f && duration < 1000L;
        assertTrue(isHorizontal);
        assertEquals(1, ReaderNavigation.swipeDelta(dx, false));

        // Swipe right (LTR): dx = 80px, dy = 10px, duration = 300ms
        dx = 80f;
        isHorizontal = Math.abs(dx) > minSwipePx && Math.abs(dx) > Math.abs(dy) * 1.1f && duration < 1000L;
        assertTrue(isHorizontal);
        assertEquals(-1, ReaderNavigation.swipeDelta(dx, false));

        // Diagonal/vertical scroll: dx = 80px, dy = 80px -> should NOT be recognized as page swipe
        dy = 80f;
        isHorizontal = Math.abs(dx) > minSwipePx && Math.abs(dx) > Math.abs(dy) * 1.1f && duration < 1000L;
        assertFalse(isHorizontal);

        // Distance too short: dx = 50px (< 72px)
        dx = 50f;
        dy = 0f;
        isHorizontal = Math.abs(dx) > minSwipePx && Math.abs(dx) > Math.abs(dy) * 1.1f && duration < 1000L;
        assertFalse(isHorizontal);

        // Slow drag exceeding 1 second
        dx = -100f;
        duration = 1200L;
        isHorizontal = Math.abs(dx) > minSwipePx && Math.abs(dx) > Math.abs(dy) * 1.1f && duration < 1000L;
        assertFalse(isHorizontal);
    }

    @Test
    public void swipeNavigationBoundaryDistinction() {
        int pageCount = 15;

        // In animation-disabled mode, intra-chapter swipe delta (+1) should navigate within chapter
        int currentPage = 5;
        int delta = 1;
        assertFalse(ReaderNavigation.crossesChapter(currentPage, pageCount, delta));
        assertEquals(6, currentPage + delta);

        // Backward intra-chapter swipe delta (-1)
        delta = -1;
        assertFalse(ReaderNavigation.crossesChapter(currentPage, pageCount, delta));
        assertEquals(4, currentPage + delta);

        // At end of chapter (page 14 of 15), forward swipe crosses boundary to next chapter
        currentPage = 14;
        delta = 1;
        assertTrue(ReaderNavigation.crossesChapter(currentPage, pageCount, delta));

        // At start of chapter (page 0), backward swipe crosses boundary to previous chapter
        currentPage = 0;
        delta = -1;
        assertTrue(ReaderNavigation.crossesChapter(currentPage, pageCount, delta));
    }

    @Test
    public void rtlMangaSwipeDirections() {
        // In RTL Manga mode:
        // Swiping right (dx > 0) turns to NEXT page (forward, delta = 1)
        assertEquals(1, ReaderNavigation.swipeDelta(80f, true));

        // Swiping left (dx < 0) turns to PREVIOUS page (backward, delta = -1)
        assertEquals(-1, ReaderNavigation.swipeDelta(-80f, true));
    }
}
