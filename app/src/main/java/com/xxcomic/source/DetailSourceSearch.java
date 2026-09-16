package com.xxcomic.source;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.FutureTask;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/** One short-lived title cache; independent of discovery search and detail loading. */
public final class DetailSourceSearch implements AutoCloseable {
    public interface Listener {
        void onResults(List<ComicModels.ComicSummary> items, boolean loading);
    }

    private final Executor callbackExecutor;
    private final ExecutorService workers = Executors.newFixedThreadPool(3);
    private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor();
    private final long timeoutMs;
    private final Map<String, ComicModels.ComicSummary> matches = new LinkedHashMap<>();
    private final Map<String, Job> jobs = new LinkedHashMap<>();
    private final Set<String> completed = new HashSet<>();
    private List<String> sourceIds = new ArrayList<>();
    private String title = "";
    private String initialSource = "";
    private long cacheStarted;
    private int revision;
    private Listener listener;
    private boolean closed;

    public DetailSourceSearch(Executor callbackExecutor) { this(callbackExecutor, 10000); }

    DetailSourceSearch(Executor callbackExecutor, long timeoutMs) {
        this.callbackExecutor = callbackExecutor;
        this.timeoutMs = timeoutMs;
    }

    public synchronized void start(ComicModels.ComicSummary current, List<ComicSource> sources, Listener listener) {
        if (closed) return;
        String query = current.title == null ? "" : current.title.trim();
        List<String> ids = new ArrayList<>();
        for (ComicSource source : sources) if (source.supportsSearch()) ids.add(source.id());
        if (!title.equals(query) || !sourceIds.equals(ids)
                || System.nanoTime() - cacheStarted > TimeUnit.MINUTES.toNanos(5)) {
            detach();
            matches.clear();
            completed.clear();
            title = query;
            sourceIds = ids;
            initialSource = current.sourceId;
            cacheStarted = System.nanoTime();
        }
        this.listener = listener;
        matches.put(current.sourceId, current);
        completed.add(current.sourceId);
        if (!query.isEmpty()) {
            for (ComicSource source : sources) {
                String id = source.id();
                if (!source.supportsSearch() || completed.contains(id) || jobs.containsKey(id)) continue;
                Job job = new Job();
                jobs.put(id, job);
                job.work = new FutureTask<>(() -> {
                    synchronized (DetailSourceSearch.this) {
                        if (jobs.get(id) != job) return null;
                        // Start the timeout when the request runs, not while waiting in the queue.
                        job.timeout = timer.schedule(() -> finish(id, job, null), timeoutMs, TimeUnit.MILLISECONDS);
                    }
                    ComicModels.ComicSummary match = null;
                    try {
                        match = SourceSwitchMatcher.firstExactMatch(query, source.search(query, 1), id);
                    } catch (Exception ignored) {
                        // Failed/verification-required sources do not interrupt the detail screen.
                    }
                    finish(id, job, match);
                    return null;
                });
                workers.execute(job.work);
            }
        }
        publish();
    }

    private synchronized void finish(String id, Job job, ComicModels.ComicSummary match) {
        if (jobs.get(id) != job) return;
        jobs.remove(id);
        completed.add(id);
        if (job.timeout != null) job.timeout.cancel(false);
        if (job.work != null) job.work.cancel(true);
        if (match != null) matches.put(id, match);
        publish();
    }

    private void publish() {
        if (listener == null) return;
        List<ComicModels.ComicSummary> result = new ArrayList<>();
        if (matches.containsKey(initialSource)) result.add(matches.get(initialSource));
        for (String id : sourceIds) {
            if (!id.equals(initialSource) && matches.containsKey(id)) result.add(matches.get(id));
        }
        Listener target = listener;
        boolean loading = !jobs.isEmpty();
        int token = ++revision;
        callbackExecutor.execute(() -> {
            synchronized (DetailSourceSearch.this) {
                if (listener == target && token == revision) target.onResults(result, loading);
            }
        });
    }

    public synchronized void detach() {
        listener = null;
        revision++;
        for (Job job : jobs.values()) {
            if (job.timeout != null) job.timeout.cancel(false);
            if (job.work != null) job.work.cancel(true);
        }
        jobs.clear();
    }

    @Override public synchronized void close() {
        detach();
        closed = true;
        workers.shutdownNow();
        timer.shutdownNow();
    }

    private static final class Job {
        FutureTask<Void> work;
        Future<?> timeout;
    }
}
