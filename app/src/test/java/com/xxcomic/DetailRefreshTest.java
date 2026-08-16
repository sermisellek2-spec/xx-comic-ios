package com.xxcomic;

import com.xxcomic.source.ComicModels;

import org.junit.Test;

import java.util.Collections;

import static org.junit.Assert.assertEquals;

public class DetailRefreshTest {
    @Test
    public void metadataRefreshKeepsAlreadyLoadedChapters() {
        ComicModels.Chapter chapter = new ComicModels.Chapter("1", "第1话", "/chapter/1", 0, 0);
        ComicModels.ComicDetail cached = detail("旧标题", Collections.singletonList(chapter));
        ComicModels.ComicDetail fresh = detail("新标题", Collections.emptyList());

        ComicModels.ComicDetail merged = MainActivity.mergeRefreshedDetail(cached, fresh);

        assertEquals("新标题", merged.summary.title);
        assertEquals(1, merged.chapters.size());
        assertEquals("1", merged.chapters.get(0).chapterId);
    }

    private static ComicModels.ComicDetail detail(String title,
                                                   java.util.List<ComicModels.Chapter> chapters) {
        ComicModels.ComicSummary summary = new ComicModels.ComicSummary(
                "jmcomic", "jmcomic:1", title, "", "", Collections.emptyList());
        return new ComicModels.ComicDetail(summary, "作者", "连载中", "简介", "", chapters);
    }
}
