package com.xxcomic;

import org.junit.Test;
import static org.junit.Assert.assertEquals;

public class SourceSwitchSheetTest {
    @Test public void upwardDragExpandsAndDownwardDragCollapses() {
        assertEquals(900, SourceSwitchSheet.settledHeight(620, 100, 550, 900));
        assertEquals(550, SourceSwitchSheet.settledHeight(810, -100, 550, 900));
    }
    @Test public void smallDragSnapsBackAndLargeDownwardDragDismisses() {
        assertEquals(550, SourceSwitchSheet.settledHeight(562, 12, 550, 900));
        assertEquals(900, SourceSwitchSheet.settledHeight(890, -10, 550, 900));
        assertEquals(0, SourceSwitchSheet.settledHeight(250, -300, 550, 900));
    }
}
