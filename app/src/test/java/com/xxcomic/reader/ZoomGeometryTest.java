package com.xxcomic.reader;

import org.junit.Test;
import static org.junit.Assert.assertEquals;

public class ZoomGeometryTest {
    @Test public void movingPinchKeepsContentUnderFingers() {
        // Content at 400 was at focus 450 with pivot 500, scale 1 and translation 50.
        // Doubling scale while moving focus to 480 requires translation 180.
        assertEquals(180f, ZoomGeometry.followFocus(50, 500, 450, 480, 2), .001f);
    }

    @Test public void reversePinchRestoresOriginalTransform() {
        float moved = ZoomGeometry.followFocus(50, 500, 450, 480, 2);
        assertEquals(50f, ZoomGeometry.followFocus(moved, 500, 480, 450, .5f), .001f);
    }

    @Test public void stationaryFocusDoesNotDriftAndPanUsesFullDistance() {
        assertEquals(-100f, ZoomGeometry.followFocus(0, 0, 100, 100, 2), .001f);
        assertEquals(80f, ZoomGeometry.followFocus(50, 500, 450, 480, 1), .001f);
    }

    @Test public void smallImageCanFollowFingersUntilRelease() {
        assertEquals(0f, ZoomGeometry.correction(140, 800, 1000, 200), .001f);
        assertEquals(-40f, ZoomGeometry.correction(140, 800, 1000, 0), .001f);
    }

    @Test public void largeImageBoundsAllowSlopThenSettleWithoutBlankEdges() {
        assertEquals(0f, ZoomGeometry.correction(80, 1500, 1000, 200), .001f);
        assertEquals(-80f, ZoomGeometry.correction(80, 1500, 1000, 0), .001f);
        assertEquals(100f, ZoomGeometry.correction(-600, 1500, 1000, 0), .001f);
        assertEquals(0f, ZoomGeometry.correction(-200, 1500, 1000, 0), .001f);
    }
}
