package com.xxcomic.local;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

public class LocalModelsTest {
    @Test
    public void testBookDisplayTitleFallback() {
        LocalModels.Book book1 = new LocalModels.Book(
                "id1", "fp1", "Original Title", null,
                LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, "prog1",
                "rel/path", null, 1000L, 1, 10, LocalModels.STATUS_READY, 0L, 0L
        );
        assertEquals("Original Title", book1.getDisplayTitle());

        LocalModels.Book book2 = book1.withUserTitle("Custom User Title");
        assertEquals("Custom User Title", book2.getDisplayTitle());

        LocalModels.Book book3 = new LocalModels.Book(
                "id3", "fp3", "", "  ",
                LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, "prog3",
                "rel/path", null, 1000L, 1, 10, LocalModels.STATUS_READY, 0L, 0L
        );
        assertEquals("未命名漫画", book3.getDisplayTitle());
    }

    @Test
    public void testChapterAndPageConstruction() {
        LocalModels.Chapter ch = new LocalModels.Chapter("ch1", "b1", 0, "第 1 话", "folder/ch1", 20);
        assertEquals("ch1", ch.id);
        assertEquals("b1", ch.bookId);
        assertEquals(0, ch.orderIndex);
        assertEquals("第 1 话", ch.title);
        assertEquals(20, ch.pageCount);

        LocalModels.Page page = new LocalModels.Page("p1", "b1", "ch1", 0, "folder/ch1/01.jpg", 1000, 1500, null, "image/jpeg");
        assertEquals("p1", page.id);
        assertEquals("b1", page.bookId);
        assertEquals("ch1", page.chapterId);
        assertEquals(0, page.orderIndex);
        assertEquals("image/jpeg", page.mimeType);
    }

    @Test
    public void testRecentlyUsedSortingComparator() {
        LocalModels.Book bookA = new LocalModels.Book("a", "fp_a", "Book A", null,
                LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, "prog_a",
                "/storage/a.zip", null, 100, 1, 10, LocalModels.STATUS_READY, 1000L, 1000L);
        LocalModels.Book bookB = new LocalModels.Book("b", "fp_b", "Book B", null,
                LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, "prog_b",
                "/storage/b.zip", null, 100, 1, 10, LocalModels.STATUS_READY, 2000L, 2000L);
        LocalModels.Book bookC = new LocalModels.Book("c", "fp_c", "Book C", null,
                LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, "prog_c",
                "/storage/c.zip", null, 100, 1, 10, LocalModels.STATUS_READY, 500L, 500L);

        java.util.Map<String, Long> lastViewed = new java.util.HashMap<>();
        // Book C was read at timestamp 5000 (most recent!)
        lastViewed.put("prog_c", 5000L);
        // Book A was read at timestamp 1500
        lastViewed.put("prog_a", 1500L);
        // Book B has no read history, so its time is createdAt = 2000

        java.util.List<LocalModels.Book> list = new java.util.ArrayList<>(java.util.Arrays.asList(bookA, bookB, bookC));
        java.util.Collections.sort(list, (left, right) -> {
            long leftReadTime = 0L;
            if (left.progressKey != null && lastViewed.containsKey(left.progressKey)) {
                leftReadTime = Math.max(leftReadTime, lastViewed.get(left.progressKey));
            }
            long rightReadTime = 0L;
            if (right.progressKey != null && lastViewed.containsKey(right.progressKey)) {
                rightReadTime = Math.max(rightReadTime, lastViewed.get(right.progressKey));
            }
            long leftTime = Math.max(left.createdAt, leftReadTime);
            long rightTime = Math.max(right.createdAt, rightReadTime);
            if (leftTime != rightTime) {
                return Long.compare(rightTime, leftTime);
            }
            return Long.compare(right.createdAt, left.createdAt);
        });

        // Expected order: Book C (5000) -> Book B (2000) -> Book A (1500)
        assertEquals("c", list.get(0).id);
        assertEquals("b", list.get(1).id);
        assertEquals("a", list.get(2).id);
    }
}
