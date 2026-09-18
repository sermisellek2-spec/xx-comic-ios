package com.xxcomic.reader;

/** Geometry shared by the strip and single-page readers, in viewport coordinates. */
public final class ZoomGeometry {
    private ZoomGeometry() {}

    public static float followFocus(float translation, float pivot, float previousFocus,
                                    float focus, float ratio) {
        return focus - pivot - ratio * (previousFocus - pivot - translation);
    }

    public static float correction(float start, float size, float viewport, float slop) {
        if (size <= viewport) {
            float center = (viewport - size) / 2f;
            return Math.max(center - slop, Math.min(center + slop, start)) - start;
        }
        if (start > slop) return slop - start;
        if (start + size < viewport - slop) return viewport - slop - start - size;
        return 0f;
    }
}
