package com.xxcomic.local;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class LocalContentResolverTest {
    @Test
    public void testSchemeAndUrlParsing() {
        String pageUrl = LocalContentResolver.buildPageUrl("page_123");
        assertEquals("local://page/page_123", pageUrl);
        assertTrue(LocalContentResolver.isLocalUrl(pageUrl));
        assertTrue(LocalContentResolver.isLocalPageUrl(pageUrl));
        assertFalse(LocalContentResolver.isLocalCoverUrl(pageUrl));
        assertEquals("page_123", LocalContentResolver.extractId(pageUrl, LocalContentResolver.PREFIX_PAGE));

        String coverUrl = LocalContentResolver.buildCoverUrl("book_456");
        assertEquals("local://cover/book_456", coverUrl);
        assertTrue(LocalContentResolver.isLocalUrl(coverUrl));
        assertTrue(LocalContentResolver.isLocalCoverUrl(coverUrl));
        assertFalse(LocalContentResolver.isLocalPageUrl(coverUrl));
        assertEquals("book_456", LocalContentResolver.extractId(coverUrl, LocalContentResolver.PREFIX_COVER));

        String chapterUrl = LocalContentResolver.buildChapterUrl("chap_789");
        assertEquals("local://chapter/chap_789", chapterUrl);
        assertTrue(LocalContentResolver.isLocalUrl(chapterUrl));
        assertTrue(LocalContentResolver.isLocalChapterUrl(chapterUrl));
        assertEquals("chap_789", LocalContentResolver.extractId(chapterUrl, LocalContentResolver.PREFIX_CHAPTER));

        assertFalse(LocalContentResolver.isLocalUrl("https://example.com/image.jpg"));
        assertFalse(LocalContentResolver.isLocalUrl(null));
        assertFalse(LocalContentResolver.isLocalUrl(""));
    }
}
