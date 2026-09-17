package com.xxcomic.ebook;

import org.junit.Assert;
import org.junit.Test;

public class TextLocatorTest {

    @Test
    public void serializesAndDeserializesCorrectly() {
        TextLocator locator = new TextLocator("book_test_1", 2, 5, "OEBPS/chapter2.xhtml", "section_1", 0.45f, 120);
        String json = locator.toJson();

        TextLocator restored = TextLocator.fromJson(json);
        Assert.assertNotNull(restored);
        Assert.assertEquals("book_test_1", restored.bookId);
        Assert.assertEquals(2, restored.chapterIndex);
        Assert.assertEquals(5, restored.spineIndex);
        Assert.assertEquals("OEBPS/chapter2.xhtml", restored.resourceHref);
        Assert.assertEquals("section_1", restored.anchorId);
        Assert.assertEquals(0.45f, restored.scrollPercentage, 0.001f);
        Assert.assertEquals(120, restored.charOffset);
    }

    @Test
    public void clampsPercentagesAndHandlesNullsGracefully() {
        TextLocator locator = new TextLocator(null, -1, -5, null, null, 1.8f, -10);
        Assert.assertEquals("", locator.bookId);
        Assert.assertEquals(0, locator.chapterIndex);
        Assert.assertEquals(0, locator.spineIndex);
        Assert.assertEquals("", locator.resourceHref);
        Assert.assertEquals("", locator.anchorId);
        Assert.assertEquals(1.0f, locator.scrollPercentage, 0.001f);
        Assert.assertEquals(0, locator.charOffset);

        TextLocator negativeScroll = locator.withScrollPercentage(-0.5f);
        Assert.assertEquals(0.0f, negativeScroll.scrollPercentage, 0.001f);

        Assert.assertNull(TextLocator.fromJson(null));
        Assert.assertNull(TextLocator.fromJson("   "));
        Assert.assertNull(TextLocator.fromJson("invalid_json"));
    }
}
