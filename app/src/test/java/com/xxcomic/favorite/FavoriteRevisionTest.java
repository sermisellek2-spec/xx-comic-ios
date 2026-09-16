package com.xxcomic.favorite;

import com.xxcomic.source.ComicModels;

import org.json.JSONObject;
import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

public class FavoriteRevisionTest {

    private static ComicModels.Chapter chapter(String title, String url) {
        return new ComicModels.Chapter("", title, url, 0, 0);
    }

    private static ComicModels.Chapter chapter(String id, String title, String url) {
        return new ComicModels.Chapter(id, title, url, 0, 0);
    }

    private static ComicModels.ComicSummary summary(String id) {
        return new ComicModels.ComicSummary("test_source", id, "Title", "", "", Collections.emptyList());
    }

    private static ComicModels.ComicDetail detail(String id, String latestChapter, List<ComicModels.Chapter> chapters) {
        return new ComicModels.ComicDetail(summary(id), "Author", "连载中", "Desc", latestChapter, chapters);
    }

    @Test
    public void testCanonicalChapterIdWithExplicitId() {
        ComicModels.Chapter c = chapter("chap_001", "第1话", "https://example.com/chapter/1");
        assertEquals("chap_001", FavoriteRevision.canonicalChapterId(c));
    }

    @Test
    public void testCanonicalChapterIdWithUrlNormalization() {
        ComicModels.Chapter c = chapter("第1话", "https://example.com/comic/123/chap-1?auth=xyz&section_slot=2#page3");
        assertEquals("/comic/123/chap-1?section_slot=2", FavoriteRevision.canonicalChapterId(c));
    }

    @Test
    public void testExtractChapterNumber() {
        assertEquals(Long.valueOf(105), FavoriteRevision.extractChapterNumber("第105话 决赛前夕"));
        assertEquals(Long.valueOf(12), FavoriteRevision.extractChapterNumber("Chapter 12"));
        assertEquals(null, FavoriteRevision.extractChapterNumber("特别篇 序章"));
    }

    @Test
    public void testHasNewChaptersDetectsAddedChapter() {
        ComicModels.Chapter c1 = chapter("第1话", "/c/1");
        ComicModels.Chapter c2 = chapter("第2话", "/c/2");
        ComicModels.Chapter c3 = chapter("第3话", "/c/3");

        FavoriteRevision baseline = FavoriteRevision.fromChapters("第2话", Arrays.asList(c1, c2));
        FavoriteRevision candidate = FavoriteRevision.fromChapters("第3话", Arrays.asList(c1, c2, c3));

        assertTrue(FavoriteRevision.hasNewChapters(baseline, candidate));
    }

    @Test
    public void testHasNewChaptersOrderIndependent() {
        ComicModels.Chapter c1 = chapter("第1话", "/c/1");
        ComicModels.Chapter c2 = chapter("第2话", "/c/2");

        FavoriteRevision baseline = FavoriteRevision.fromChapters("第2话", Arrays.asList(c1, c2));
        // Source inverted chapter order (newest first vs oldest first)
        FavoriteRevision candidate = FavoriteRevision.fromChapters("第2话", Arrays.asList(c2, c1));

        assertFalse(FavoriteRevision.hasNewChapters(baseline, candidate));
    }

    @Test
    public void testHasNewChaptersDeletedChaptersDoesNotTriggerUpdate() {
        ComicModels.Chapter c1 = chapter("第1话", "/c/1");
        ComicModels.Chapter c2 = chapter("第2话", "/c/2");

        FavoriteRevision baseline = FavoriteRevision.fromChapters("第2话", Arrays.asList(c1, c2));
        // One chapter removed by site
        FavoriteRevision candidate = FavoriteRevision.fromChapters("第1话", Collections.singletonList(c1));

        assertFalse(FavoriteRevision.hasNewChapters(baseline, candidate));
    }

    @Test
    public void testHasNewChaptersRenamedChapterWithSameUrlDoesNotTriggerUpdate() {
        ComicModels.Chapter c1 = chapter("第1话", "/c/1");
        ComicModels.Chapter c2 = chapter("第2话 原标题", "/c/2");
        FavoriteRevision baseline = FavoriteRevision.fromChapters("第2话 原标题", Arrays.asList(c1, c2));

        ComicModels.Chapter c2Renamed = chapter("第2话 新标题（修图版）", "/c/2");
        FavoriteRevision candidate = FavoriteRevision.fromChapters("第2话 新标题（修图版）", Arrays.asList(c1, c2Renamed));

        assertFalse(FavoriteRevision.hasNewChapters(baseline, candidate));
    }

    @Test
    public void testHasNewChaptersLatestChapterModeFallback() {
        ComicModels.ComicDetail d1 = detail("c1", "第10话", new ArrayList<>());
        ComicModels.ComicDetail d2 = detail("c1", "第11话", new ArrayList<>());
        ComicModels.ComicDetail dSame = detail("c1", "第10话", new ArrayList<>());

        FavoriteRevision rev1 = FavoriteRevision.fromDetail(d1);
        FavoriteRevision rev2 = FavoriteRevision.fromDetail(d2);
        FavoriteRevision revSame = FavoriteRevision.fromDetail(dSame);

        assertTrue(FavoriteRevision.hasNewChapters(rev1, rev2));
        assertFalse(FavoriteRevision.hasNewChapters(rev1, revSame));
        assertFalse(FavoriteRevision.hasNewChapters(rev2, rev1));
    }

    @Test
    public void testJsonSerializationRoundtrip() throws Exception {
        ComicModels.Chapter c1 = chapter("第1话", "/c/1");
        ComicModels.Chapter c2 = chapter("第2话", "/c/2");
        FavoriteRevision original = FavoriteRevision.fromChapters("第2话", Arrays.asList(c1, c2));

        JSONObject json = original.toJson();
        FavoriteRevision restored = FavoriteRevision.fromJson(json);

        assertNotNull(restored);
        assertEquals(original.formatVersion, restored.formatVersion);
        assertEquals(original.mode, restored.mode);
        assertEquals(original.chapterIds, restored.chapterIds);
        assertEquals(original.latestChapterId, restored.latestChapterId);
        assertEquals(original.latestChapterName, restored.latestChapterName);
        assertEquals(original.chapterNumber, restored.chapterNumber);
        assertEquals(original.chapterCount, restored.chapterCount);
    }
}
