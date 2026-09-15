package com.xxcomic.reader;

/** Logical order never depends on handedness; only physical gestures do. */
public final class ReaderNavigation {
    private ReaderNavigation() { }
    public static int tapDelta(boolean leftSide, boolean leftHand) {
        return leftSide == leftHand ? 1 : -1;
    }
    public static int swipeDelta(float dx, boolean leftHand) {
        return (dx > 0) == leftHand ? 1 : -1;
    }
    public static boolean crossesChapter(int index, int count, int delta) {
        return count > 0 && (index + delta < 0 || index + delta >= count);
    }
}
