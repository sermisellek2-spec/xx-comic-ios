package com.xxcomic.download;

import com.xxcomic.source.ComicModels;
import java.util.*;
import org.junit.Test;
import static org.junit.Assert.*;

public class DownloadCoordinatorTest {
    static final class Memory implements DownloadCoordinator.Repository {
        final Map<String, DownloadModels.Task> data = new LinkedHashMap<>();
        public List<DownloadModels.Task> list() { return new ArrayList<>(data.values()); }
        public DownloadModels.Task get(String id) { return data.get(id); }
        public void save(DownloadModels.Task task) { data.put(task.id, task); }
    }
    private ComicModels.Chapter chapter(String id) { return new ComicModels.Chapter(id, id, "https://sample/" + id, 0, 0); }

    @Test public void duplicateEnqueueAndReversedDisplayKeepTheSameTask() {
        Memory db = new Memory(); DownloadCoordinator queue = new DownloadCoordinator(db);
        queue.enqueue("source", "comic", Arrays.asList(chapter("a"), chapter("b")), Arrays.asList("a", "b"));
        queue.enqueue("source", "comic", Arrays.asList(chapter("b"), chapter("a")), Arrays.asList("b", "a"));
        assertEquals(2, db.list().size());
        assertEquals("a", queue.claim(0, true, true, true).chapterId);
    }
    @Test public void userPauseWinsOverNetworkRecoveryAndInvalidatesLateCompletion() {
        Memory db = new Memory(); DownloadCoordinator queue = new DownloadCoordinator(db);
        queue.enqueue("s", "c", Arrays.asList(chapter("a")), Arrays.asList("a"));
        DownloadModels.Task lease = queue.claim(0, true, true, true); assertNotNull(lease);
        queue.pause(lease.id);
        assertFalse(queue.complete(lease));
        assertNull(queue.claim(10000, true, true, true));
        queue.resume(lease.id);
        assertNotNull(queue.claim(10000, true, true, true));
    }
    @Test public void cancellationRejectsLatePageAndCompletion() {
        Memory db = new Memory(); DownloadCoordinator queue = new DownloadCoordinator(db);
        queue.enqueue("s", "c", Arrays.asList(chapter("a")), Arrays.asList("a"));
        DownloadModels.Task lease = queue.claim(0, true, true, true); assertNotNull(lease);
        queue.cancel(lease.id);
        assertFalse(queue.isCurrent(lease));
        assertFalse(queue.complete(lease));
        assertEquals(DownloadModels.State.CANCELLED, db.get(lease.id).state);
    }
    @Test public void verificationWaitDoesNotBlockAnotherSource() {
        Memory db = new Memory(); DownloadCoordinator queue = new DownloadCoordinator(db);
        queue.enqueue("blocked", "c", Arrays.asList(chapter("a"), chapter("b")), Arrays.asList("a", "b"));
        queue.enqueue("other", "d", Arrays.asList(chapter("a")), Arrays.asList("a"));
        DownloadModels.Task first = queue.claim(0, true, true, true); assertNotNull(first);
        queue.waitForVerification(first);
        assertEquals("other", queue.claim(0, true, true, true).sourceId);
    }
    @Test public void threeAutomaticRetriesThenManualRetryRequired() {
        Memory db = new Memory(); DownloadCoordinator queue = new DownloadCoordinator(db);
        queue.enqueue("s", "c", Arrays.asList(chapter("a")), Arrays.asList("a"));
        long now=0;
        for (long delay : new long[]{2000, 5000, 15000}) {
            DownloadModels.Task lease=queue.claim(now, true, true, true); assertNotNull(lease);
            queue.failed(lease, now, "network", 0);
            assertNull(queue.claim(now+delay-1, true, true, true));
            now+=delay;
        }
        DownloadModels.Task last=queue.claim(now, true, true, true);
        queue.failed(last, now, "network", 0);
        assertNull(queue.claim(Long.MAX_VALUE, true, true, true));
        assertEquals(DownloadModels.State.FAILED, db.get(last.id).state);
    }
    @Test public void recoveryPreservesManualPauseAndCompletedAndRequeuesInterruptedWork() {
        Memory db = new Memory(); DownloadCoordinator queue = new DownloadCoordinator(db);
        queue.enqueue("s", "c", Arrays.asList(chapter("a"), chapter("b"), chapter("c")), Arrays.asList("a", "b", "c"));
        DownloadModels.Task a=queue.claim(0,true,true,true); assertNotNull(a); queue.complete(a);
        DownloadModels.Task b=queue.claim(0,true,true,true); queue.pause(b.id);
        DownloadModels.Task c=queue.claim(0,true,true,true);
        new DownloadCoordinator(db).recover();
        assertEquals(DownloadModels.State.COMPLETED,db.get(a.id).state);
        assertEquals(DownloadModels.State.PAUSED_USER,db.get(b.id).state);
        assertFalse(queue.isCurrent(c));
        assertEquals("c",queue.claim(0,true,true,true).chapterId);
    }
    @Test public void wifiOnlyWaitsUntilUnmeteredWifiOrExplicitPreferenceChange() {
        Memory db=new Memory(); DownloadCoordinator queue=new DownloadCoordinator(db);
        queue.enqueue("s","c",Arrays.asList(chapter("a")),Arrays.asList("a"));
        assertNull(queue.claim(0,true,false,true));
        assertNotNull(queue.claim(0,true,false,false));
    }
    @Test public void retryAfterCoolsDownTheSourceButNotOtherSources() {
        Memory db=new Memory(); DownloadCoordinator queue=new DownloadCoordinator(db);
        queue.enqueue("s","c",Arrays.asList(chapter("a"),chapter("b")),Arrays.asList("a","b"));
        queue.enqueue("other","c",Arrays.asList(chapter("a")),Arrays.asList("a"));
        queue.failed(queue.claim(0,true,true,true),0,"HTTP 429",60000);
        assertEquals("other",queue.claim(10000,true,true,true).sourceId);
    }

    @Test public void boundedClaimsAllowTwoTasksButRejectTheThird() {
        Memory db = new Memory(); DownloadCoordinator queue = new DownloadCoordinator(db);
        queue.enqueue("source", "comic", Arrays.asList(chapter("a"), chapter("b"), chapter("c")), Arrays.asList("a", "b", "c"));
        assertNotNull(queue.claim(0, true, true, true, 2, 2));
        assertNotNull(queue.claim(0, true, true, true, 2, 2));
        assertNull(queue.claim(0, true, true, true, 2, 2));
    }

    @Test public void sourceLimitDoesNotBlockAnotherSource() {
        Memory db = new Memory(); DownloadCoordinator queue = new DownloadCoordinator(db);
        queue.enqueue("source", "comic", Arrays.asList(chapter("a"), chapter("b"), chapter("c")), Arrays.asList("a", "b", "c"));
        queue.enqueue("other", "comic", Arrays.asList(chapter("d")), Arrays.asList("d"));
        assertNotNull(queue.claim(0, true, true, true, 3, 2));
        assertNotNull(queue.claim(0, true, true, true, 3, 2));
        assertEquals("other", queue.claim(0, true, true, true, 3, 2).sourceId);
    }
    @Test public void deletingAndRecreatingIdentityCannotReviveAnOldWorker() {
        Memory db=new Memory(); DownloadCoordinator queue=new DownloadCoordinator(db);
        queue.enqueue("s","c",Arrays.asList(chapter("a")),Arrays.asList("a"));
        DownloadModels.Task old=queue.claim(0,true,true,true);
        queue.cancel(old.id);db.data.remove(old.id);
        queue.enqueue("s","c",Arrays.asList(chapter("a")),Arrays.asList("a"));
        assertNotNull(queue.claim(0,true,true,true));
        assertFalse(queue.complete(old));
    }
}
