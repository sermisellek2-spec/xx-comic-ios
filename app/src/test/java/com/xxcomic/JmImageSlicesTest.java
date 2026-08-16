package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

public class JmImageSlicesTest {
    @Test
    public void sliceBoundsCoverSourceAndTargetWithoutOverlap() {
        int[][] bounds = MainActivity.jmSliceBounds(1499, 14);

        int expectedSourceBottom = 1499;
        int expectedTargetTop = 0;
        for (int[] bound : bounds) {
            assertEquals(expectedSourceBottom, bound[1]);
            assertEquals(expectedTargetTop, bound[2]);
            assertEquals(bound[1] - bound[0], bound[3] - bound[2]);
            expectedSourceBottom = bound[0];
            expectedTargetTop = bound[3];
        }
        assertEquals(0, expectedSourceBottom);
        assertEquals(1499, expectedTargetTop);
    }
}
