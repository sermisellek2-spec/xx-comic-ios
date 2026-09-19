package com.xxcomic.reader;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.Assert.assertEquals;

public class HistoryProgressLabelTest {

    @Test
    public void testOutOfBoundsChapterIndexShowsUpdatedDirectory() {
        assertEquals("目录已更新 · 点击继续", HistoryProgressLabel.label(256, Arrays.asList("全卷")));
        assertEquals("目录已更新 · 点击继续", HistoryProgressLabel.label(1, Arrays.asList("第1话")));
        assertEquals("目录已更新 · 点击继续", HistoryProgressLabel.label(5, Arrays.asList("第1话", "第2话")));
    }

    @Test
    public void testValidIndexShowsChapterTitle() {
        assertEquals("上次看到 · 全卷", HistoryProgressLabel.label(0, Arrays.asList("全卷")));
        assertEquals("上次看到 · 第1话", HistoryProgressLabel.label(0, Arrays.asList("第1话", "第2话")));
        assertEquals("上次看到 · 第2话", HistoryProgressLabel.label(1, Arrays.asList("第1话", "第2话")));
    }

    @Test
    public void testNegativeIndexShowsGenericRecord() {
        assertEquals("有阅读记录", HistoryProgressLabel.label(-1, null));
        assertEquals("有阅读记录", HistoryProgressLabel.label(-1, Collections.emptyList()));
        assertEquals("有阅读记录", HistoryProgressLabel.label(-1, Arrays.asList("全卷")));
    }

    @Test
    public void testMissingOrEmptyDirectoryShowsChapterNumber() {
        assertEquals("上次看到 第 1 章", HistoryProgressLabel.label(0, null));
        assertEquals("上次看到 第 1 章", HistoryProgressLabel.label(0, Collections.emptyList()));
        assertEquals("上次看到 第 3 章", HistoryProgressLabel.label(2, null));
        assertEquals("上次看到 第 10 章", HistoryProgressLabel.label(9, Collections.emptyList()));
    }

    @Test
    public void testEmptyOrWhitespaceTitleFallsBackToChapterNumber() {
        assertEquals("上次看到 第 1 章", HistoryProgressLabel.label(0, Arrays.asList("")));
        assertEquals("上次看到 第 1 章", HistoryProgressLabel.label(0, Arrays.asList("   ")));
        assertEquals("上次看到 第 2 章", HistoryProgressLabel.label(1, Arrays.asList("第1话", null)));
    }
}
