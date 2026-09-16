package com.xxcomic.source;

import org.junit.Test;
import java.lang.reflect.Method;
import static org.junit.Assert.*;

public class GmhComicSourceTest {
    @Test public void chapterLinesMatchCurrentWebsiteDefaultRoute() throws Exception {
        Method method = GmhComicSource.class.getDeclaredMethod("hostForLine", int.class);
        method.setAccessible(true);
        assertEquals("https://c-nd2-1.6wm.top", method.invoke(new GmhComicSource(), 2));
        assertEquals("https://c-nd3-1.6wm.top", method.invoke(new GmhComicSource(), 1));
    }

    @Test public void cachedLegacyUrlsKeepImagePathAndQueryOnCurrentRoute() {
        assertEquals("https://c-nd2-1.6wm.top/scomic/a/4.webp?x=%2F&n=1",
                GmhComicSource.migrateImageUrl("https://f40-1-4.g-mh.online/scomic/a/4.webp?x=%2F&n=1"));
        assertEquals("https://c-nd3-1.6wm.top/a.webp",
                GmhComicSource.migrateImageUrl("https://t40-1-4.g-mh.online/a.webp"));
        for (String url : new String[]{"https://f40-1-4.g-mh.online.evil/a.webp",
                "https://other.example/a.webp", "https://c-nd2-1.6wm.top/a.webp"}) {
            assertEquals(url, GmhComicSource.migrateImageUrl(url));
        }
    }
}
