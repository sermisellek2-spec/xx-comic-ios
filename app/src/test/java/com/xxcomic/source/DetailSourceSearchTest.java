package com.xxcomic.source;

import org.junit.After;
import org.junit.Test;
import java.lang.reflect.Proxy;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.Assert.*;

public class DetailSourceSearchTest {
    private final DetailSourceSearch search = new DetailSourceSearch(Runnable::run, 1000);
    @After public void close() { search.close(); }

    private ComicModels.ComicSummary comic(String source, String title) {
        return new ComicModels.ComicSummary(source, source + ":1", title, "", "", null);
    }
    private interface Request { List<ComicModels.ComicSummary> run(String query, int page) throws Exception; }
    private ComicSource source(String id, Request request) {
        return (ComicSource) Proxy.newProxyInstance(getClass().getClassLoader(), new Class[]{ComicSource.class}, (p, m, a) -> {
            if (m.getName().equals("id")) return id;
            if (m.getName().equals("supportsSearch")) return true;
            if (m.getName().equals("search")) return request.run((String)a[0], (int)a[1]);
            throw new AssertionError("Unexpected network operation: " + m.getName());
        });
    }
    private List<ComicModels.ComicSummary> completed(BlockingQueue<List<ComicModels.ComicSummary>> queue) throws Exception {
        List<ComicModels.ComicSummary> result = queue.poll(3, TimeUnit.SECONDS);
        assertNotNull("Search must finish without waiting indefinitely", result);
        return result;
    }

    @Test public void searchesFirstPageOnceAndReusesMatchesWhenSwitching() throws Exception {
        AtomicInteger calls = new AtomicInteger();
        ComicSource other = source("b", (query, page) -> {
            assertEquals("漫画", query); assertEquals(1, page); calls.incrementAndGet();
            return Arrays.asList(comic("b", "漫画外传"), comic("b", "漫画"));
        });
        BlockingQueue<List<ComicModels.ComicSummary>> queue = new LinkedBlockingQueue<>();
        DetailSourceSearch.Listener listener = (items, loading) -> { if (!loading) queue.add(items); };
        search.start(comic("a", "漫画"), Collections.singletonList(other), listener);
        List<ComicModels.ComicSummary> results = completed(queue);
        assertEquals(2, results.size()); assertEquals("b:1", results.get(1).comicId);
        search.start(results.get(1), Collections.singletonList(other), listener);
        assertEquals(2, completed(queue).size()); assertEquals(1, calls.get());
        search.detach();
        search.start(comic("a", "漫画"), Collections.singletonList(other), listener);
        assertEquals(2, completed(queue).size()); assertEquals(1, calls.get());
    }

    @Test public void showsFastResultWhileAnotherSourceIsStillRunningAndTimesOutSilently() throws Exception {
        CountDownLatch release = new CountDownLatch(1);
        BlockingQueue<Integer> partial = new LinkedBlockingQueue<>();
        BlockingQueue<List<ComicModels.ComicSummary>> done = new LinkedBlockingQueue<>();
        ComicSource slow = source("slow", (q, p) -> { release.await(); return Collections.emptyList(); });
        ComicSource fast = source("fast", (q, p) -> Collections.singletonList(comic("fast", q)));
        ComicSource failed = source("failed", (q, p) -> { throw new VerificationRequiredException("verify"); });
        search.start(comic("a", "漫画"), Arrays.asList(slow, fast, failed), (items, loading) -> {
            if (loading && items.size() == 2) partial.add(items.size());
            if (!loading) done.add(items);
        });
        assertEquals(Integer.valueOf(2), partial.poll(2, TimeUnit.SECONDS));
        assertEquals(2, completed(done).size());
        release.countDown();
    }

    @Test public void lateResultsCannotReplaceNewTitleOrNotifyAfterLeaving() throws Exception {
        CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1), returned = new CountDownLatch(1);
        ComicSource blocked = source("b", (q, p) -> {
            if (q.equals("旧书")) {
                entered.countDown();
                boolean waiting = true;
                while (waiting) { try { release.await(); waiting = false; } catch (InterruptedException ignored) { } }
                returned.countDown();
            }
            return Collections.singletonList(comic("b", q));
        });
        AtomicInteger oldCallbacks = new AtomicInteger();
        search.start(comic("a", "旧书"), Collections.singletonList(blocked), (i, l) -> oldCallbacks.incrementAndGet());
        assertTrue(entered.await(2, TimeUnit.SECONDS));
        search.detach();
        int before = oldCallbacks.get();
        BlockingQueue<List<ComicModels.ComicSummary>> done = new LinkedBlockingQueue<>();
        search.start(comic("a", "新书"), Collections.singletonList(blocked), (i, l) -> { if (!l) done.add(i); });
        assertEquals("新书", completed(done).get(1).title);
        release.countDown(); assertTrue(returned.await(2, TimeUnit.SECONDS));
        assertEquals(before, oldCallbacks.get());
    }

    @Test public void currentSourceIsNotSearchedAndUnfinishedSearchSurvivesDetailRefresh() throws Exception {
        AtomicInteger calls = new AtomicInteger();
        CountDownLatch started = new CountDownLatch(1), release = new CountDownLatch(1);
        ComicSource current = source("a", (q, p) -> { throw new AssertionError("Current source must not be searched"); });
        ComicSource other = source("b", (q, p) -> {
            calls.incrementAndGet(); started.countDown(); release.await();
            return Collections.singletonList(comic("b", q));
        });
        List<ComicSource> sources = Arrays.asList(current, other);
        search.start(comic("a", "漫画"), sources, (i, l) -> { });
        assertTrue(started.await(2, TimeUnit.SECONDS));
        BlockingQueue<List<ComicModels.ComicSummary>> done = new LinkedBlockingQueue<>();
        search.start(comic("a", "漫画"), sources, (i, l) -> { if (!l) done.add(i); });
        release.countDown();
        assertEquals(2, completed(done).size()); assertEquals(1, calls.get());
    }

    @Test public void callbacksAlreadyQueuedBeforeLeavingAreDiscarded() {
        BlockingQueue<Runnable> ui = new LinkedBlockingQueue<>();
        AtomicInteger calls = new AtomicInteger();
        try (DetailSourceSearch queued = new DetailSourceSearch(ui::add)) {
            queued.start(comic("a", "漫画"), Collections.emptyList(), (i, l) -> calls.incrementAndGet());
            queued.detach();
            Runnable callback;
            while ((callback = ui.poll()) != null) callback.run();
            assertEquals(0, calls.get());
        }
    }
}
