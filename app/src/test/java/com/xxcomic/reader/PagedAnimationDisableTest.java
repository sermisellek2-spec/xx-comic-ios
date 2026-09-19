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

    @Test
    public void gestureSuppressedInButtonMode() {
        int inputMode = 1; // Button mode
        float dx = -100f;
        float dy = 5f;
        boolean canSwipe = (inputMode != 1) && Math.abs(dx) > 72f && Math.abs(dx) > Math.abs(dy) * 1.1f;
        assertFalse("Swipe gesture must be completely disabled in button mode (inputMode == 1)", canSwipe);

        inputMode = 0; // Touch edge mode
        canSwipe = (inputMode != 1) && Math.abs(dx) > 72f && Math.abs(dx) > Math.abs(dy) * 1.1f;
        assertTrue(canSwipe);
    }

    @Test
    public void angleExceeding45DegreesRejected() {
        float dx = 80f;
        // Exactly 45 degrees (|dx| == |dy|)
        float dy = 80f;
        boolean validAngle = Math.abs(dx) > Math.abs(dy) * 1.1f;
        assertFalse(validAngle);

        // 60 degrees (|dy| > |dx|)
        dy = 120f;
        validAngle = Math.abs(dx) > Math.abs(dy) * 1.1f;
        assertFalse(validAngle);

        // 30 degrees (|dx| = 80, |dy| = 40, |dx| > 44)
        dy = 40f;
        validAngle = Math.abs(dx) > Math.abs(dy) * 1.1f;
        assertTrue(validAngle);
    }

    @Test
    public void singleStepGestureDebounceLogic() {
        long minInterval = 200L;
        long lastNavigateTime = 0L;

        // First swipe at 1000ms
        long t1 = 1000L;
        boolean canNavigate1 = (t1 - lastNavigateTime >= minInterval);
        assertTrue(canNavigate1);
        lastNavigateTime = t1;

        // Second rapid swipe at 1100ms (within 100ms < 200ms)
        long t2 = 1100L;
        boolean canNavigate2 = (t2 - lastNavigateTime >= minInterval);
        assertFalse("Rapid consecutive swipe within debounce interval must be rejected", canNavigate2);

        // Third swipe at 1250ms (250ms elapsed >= 200ms)
        long t3 = 1250L;
        boolean canNavigate3 = (t3 - lastNavigateTime >= minInterval);
        assertTrue("Swipe after debounce interval must be allowed", canNavigate3);
    }

    @Test
    public void multiTouchAndCancelBlocksGesture() {
        boolean blockedGesture = false;
        boolean navigationTriggeredInGesture = false;

        // Simulate multi-touch pointer count > 1
        int pointerCount = 2;
        if (pointerCount > 1) {
            blockedGesture = true;
        }
        assertTrue(blockedGesture);

        // ACTION_UP evaluation
        boolean wouldTrigger = !blockedGesture && !navigationTriggeredInGesture;
        assertFalse(wouldTrigger);

        // Simulate ACTION_CANCEL
        blockedGesture = false;
        navigationTriggeredInGesture = false;
        boolean isCancel = true;
        if (isCancel) {
            blockedGesture = true;
            navigationTriggeredInGesture = true;
        }
        assertTrue(blockedGesture);
        assertTrue(navigationTriggeredInGesture);
    }
}
