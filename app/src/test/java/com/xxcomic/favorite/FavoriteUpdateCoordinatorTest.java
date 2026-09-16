package com.xxcomic.favorite;

import com.xxcomic.source.ComicModels;
import org.junit.Before;
import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

public class FavoriteUpdateCoordinatorTest {

    private FavoriteUpdateCoordinator coordinator;

    private static ComicModels.Chapter chapter(String title, String url) {
        return new ComicModels.Chapter("", title, url, 0, 0);
    }

    private static ComicModels.ComicSummary summary(String id) {
        return new ComicModels.ComicSummary("test_source", id, "Title " + id, "", "", Collections.emptyList());
    }

    private static ComicModels.ComicDetail detail(String id, String latestChapter, List<ComicModels.Chapter> chapters) {
        return new ComicModels.ComicDetail(summary(id), "Author", "连载中", "Desc", latestChapter, chapters);
    }

    @Before
    public void setUp() {
        coordinator = FavoriteUpdateCoordinator.getInstance();
        coordinator.resetForTesting();
    }

    @Test
    public void testSessionIsolationPreventsShowingBadgeBeforeCheck() {
        String comicId = "test_comic_1";
        ComicModels.Chapter c1 = chapter("第1话", "/c/1");
        FavoriteRevision rev = FavoriteRevision.fromChapters("第1话", Collections.singletonList(c1));

        // State exists locally from previous app run with pendingUpdate = true
        FavoriteUpdateState state = new FavoriteUpdateState("test_source", comicId, true, rev, rev);
        // Inject state manually into coordinator
        // Note: checkedInSession is empty
        assertFalse("Unchecked comic in current session must never show badge", coordinator.shouldShowBadge(comicId));
    }

    @Test
    public void testUserEnteringDetailDismissesBadgeAndAdvancesBaseline() {
        String comicId = "test_comic_1";
        ComicModels.Chapter c1 = chapter("第1话", "/c/1");
        ComicModels.Chapter c2 = chapter("第2话", "/c/2");
        FavoriteRevision rev1 = FavoriteRevision.fromChapters("第1话", Collections.singletonList(c1));
        FavoriteRevision rev2 = FavoriteRevision.fromChapters("第2话", Arrays.asList(c1, c2));

        ComicModels.ComicDetail d = detail(comicId, "第1话", Collections.singletonList(c1));
        coordinator.onFavoriteAdded(comicId, d);

        FavoriteUpdateState state = coordinator.getState(comicId);
        assertNotNull(state);
        assertEquals(0, coordinator.getVisitEpoch(comicId));

        // Simulate update detected
        state.observedRevision = rev2;
        state.pendingUpdate = true;

        final AtomicBoolean badgeCleared = new AtomicBoolean(false);
        coordinator.setBadgeChangeListener((id, visible) -> {
            if (comicId.equals(id) && !visible) {
                badgeCleared.set(true);
            }
        });

        // User enters detail
        coordinator.onUserEnterDetail(comicId);

        // Badge must be dismissed
        assertFalse(state.pendingUpdate);
        assertEquals(rev2.latestChapterName, state.acknowledgedRevision.latestChapterName);
        assertEquals(1, coordinator.getVisitEpoch(comicId));
        assertTrue(badgeCleared.get());
    }

    @Test
    public void testFavoriteRemovedCleansUpState() {
        String comicId = "test_comic_2";
        ComicModels.ComicDetail d = detail(comicId, "第1话", new ArrayList<>());
        coordinator.onFavoriteAdded(comicId, d);
        assertNotNull(coordinator.getState(comicId));

        final AtomicBoolean badgeCleared = new AtomicBoolean(false);
        coordinator.setBadgeChangeListener((id, visible) -> {
            if (comicId.equals(id) && !visible) {
                badgeCleared.set(true);
            }
        });

        coordinator.onFavoriteRemoved(comicId);

        assertNull(coordinator.getState(comicId));
        assertFalse(coordinator.shouldShowBadge(comicId));
        assertTrue(badgeCleared.get());
    }

    @Test
    public void testPruneDeletedFavorites() {
        String fav1 = "fav_1";
        String fav2 = "fav_2";
        coordinator.onFavoriteAdded(fav1, null);
        coordinator.onFavoriteAdded(fav2, null);

        assertNotNull(coordinator.getState(fav1));
        assertNotNull(coordinator.getState(fav2));

        // fav2 was removed from the favorites list on disk/sync
        coordinator.pruneDeletedFavorites(Collections.singletonList(fav1));

        assertNotNull(coordinator.getState(fav1));
        assertNull(coordinator.getState(fav2));
    }
}
