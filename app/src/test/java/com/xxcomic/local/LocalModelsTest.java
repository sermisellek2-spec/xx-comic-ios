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
}
