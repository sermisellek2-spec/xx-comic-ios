package com.xxcomic;

import com.xxcomic.source.ComicModels;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class SearchPagingTest {
    @Test
    public void appendPageKeepsOnlyNewComicIds() {
        List<ComicModels.ComicSummary> existing = Collections.singletonList(comic("jmcomic:1"));
        List<ComicModels.ComicSummary> page = Arrays.asList(comic("jmcomic:1"), comic("jmcomic:2"));

        List<ComicModels.ComicSummary> additions = MainActivity.newSearchItems(existing, page);

        assertEquals(1, additions.size());
        assertEquals("jmcomic:2", additions.get(0).comicId);
    }

    @Test
    public void repeatedPageHasNoAdditionsAndEndsPaging() {
        List<ComicModels.ComicSummary> existing = Collections.singletonList(comic("jmcomic:1"));

        assertTrue(MainActivity.newSearchItems(existing, existing).isEmpty());
    }

    @Test
    public void pagingRequiresActualDownwardUserScroll() {
        assertFalse(MainActivity.shouldLoadNextSearchPage(0, 0, 600, 500, 120));
        assertFalse(MainActivity.shouldLoadNextSearchPage(300, 300, 600, 850, 120));
        assertTrue(MainActivity.shouldLoadNextSearchPage(301, 300, 600, 850, 120));
    }

    @Test
    public void protectedSourcesUseBrowserSessionTimeoutDuringGlobalSearch() {
        assertEquals(185L, MainActivity.globalSearchTimeoutSeconds("mh18"));
        assertEquals(185L, MainActivity.globalSearchTimeoutSeconds("jmcomic"));
        assertEquals(10L, MainActivity.globalSearchTimeoutSeconds("baozi"));
    }

    private static ComicModels.ComicSummary comic(String id) {
        return new ComicModels.ComicSummary("jmcomic", id, id, "", "", Collections.emptyList());
    }
}
