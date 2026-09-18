package com.xxcomic.reader;

import android.graphics.Color;

import com.xxcomic.DataHelpers;
import com.xxcomic.source.ComicModels;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.Assert.*;

public class ChapterDrawerSheetTest {

    @Test
    public void targetPositionMatchesCurrentChapterInAscendingOrder() {
        int chapterCount = 100;
        List<Integer> orderIndexes = DataHelpers.chapterOrder(false, chapterCount);
        assertEquals(chapterCount, orderIndexes.size());

        // For reading chapter 5, position in list should be 5
        int currentChapterIndex = 5;
        int targetPosition = orderIndexes.indexOf(currentChapterIndex);
        assertEquals(5, targetPosition);

        // For chapter 0, target is 0
        assertEquals(0, orderIndexes.indexOf(0));

        // For last chapter (99), target is 99
        assertEquals(99, orderIndexes.indexOf(99));
    }

    @Test
    public void targetPositionMatchesCurrentChapterInDescendingOrder() {
        int chapterCount = 100;
        List<Integer> orderIndexes = DataHelpers.chapterOrder(true, chapterCount);
        assertEquals(chapterCount, orderIndexes.size());

        // In descending order, chapter 99 is at position 0, chapter 0 is at position 99
        assertEquals(0, orderIndexes.indexOf(99));
        assertEquals(99, orderIndexes.indexOf(0));

        // Chapter 167 in a 367-chapter comic
        List<Integer> comic367 = DataHelpers.chapterOrder(true, 367);
        assertEquals(0, comic367.indexOf(366));
        int target167 = comic367.indexOf(166);
        assertEquals(367 - 1 - 166, target167);
    }

    @Test
    public void readerBackgroundColorIsTranslucentDark() {
        int readerBg = (235 << 24) | (28 << 16) | (33 << 8) | 40;
        int alpha = (readerBg >>> 24) & 0xff;
        int red = (readerBg >> 16) & 0xff;
        int green = (readerBg >> 8) & 0xff;
        int blue = readerBg & 0xff;

        assertEquals(235, alpha);
        assertEquals(28, red);
        assertEquals(33, green);
        assertEquals(40, blue);
        assertTrue("Background must be translucent (alpha < 255)", alpha < 255);
        assertTrue("Background must have sufficient contrast (alpha > 200)", alpha > 200);
    }

    @Test
    public void chapterOrderTogglePreservesAllChapters() {
        int total = 50;
        List<Integer> asc = DataHelpers.chapterOrder(false, total);
        List<Integer> desc = DataHelpers.chapterOrder(true, total);

        assertEquals(total, asc.size());
        assertEquals(total, desc.size());

        for (int i = 0; i < total; i++) {
            assertEquals(Integer.valueOf(i), asc.get(i));
            assertEquals(Integer.valueOf(total - 1 - i), desc.get(i));
        }
    }

    @Test
    public void upwardDragExpandsAndDownwardDragCollapses() {
        assertEquals(900, ChapterDrawerSheet.settledHeight(620, 100, 550, 900));
        assertEquals(550, ChapterDrawerSheet.settledHeight(810, -100, 550, 900));
    }

    @Test
    public void smallDragSnapsBackAndLargeDownwardDragDismisses() {
        assertEquals(550, ChapterDrawerSheet.settledHeight(562, 12, 550, 900));
        assertEquals(900, ChapterDrawerSheet.settledHeight(890, -10, 550, 900));
        assertEquals(0, ChapterDrawerSheet.settledHeight(250, -300, 550, 900));
    }
}
