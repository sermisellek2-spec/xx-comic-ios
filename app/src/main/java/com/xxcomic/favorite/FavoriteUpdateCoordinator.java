package com.xxcomic.favorite;

import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;

import com.xxcomic.source.ComicModels;
import com.xxcomic.source.ComicSource;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.atomic.AtomicInteger;

public final class FavoriteUpdateCoordinator {
    private static final String PREF_KEY = "favorite.update.states";
    private static final FavoriteUpdateCoordinator INSTANCE = new FavoriteUpdateCoordinator();

    public static FavoriteUpdateCoordinator getInstance() {
        return INSTANCE;
    }

    public interface SourceResolver {
        ComicSource resolveSource(String comicId);
        boolean isSourceAvailable(String comicId);
    }

    public interface BadgeChangeListener {
        void onBadgeChanged(String comicId, boolean visible);
    }

    private final Object lock = new Object();
    private boolean sessionStarted = false;
    private final Set<String> checkedInSession = Collections.synchronizedSet(new HashSet<>());
    private final Map<String, Integer> visitEpochs = new ConcurrentHashMap<>();
    private final Map<String, Integer> favoriteEpochs = new ConcurrentHashMap<>();
    private final Map<String, FavoriteUpdateState> states = new ConcurrentHashMap<>();

    private SharedPreferences sharedPreferences;
    private BadgeChangeListener badgeChangeListener;
    private final Handler mainHandler;

    // Bounded concurrency: max 2 total, max 1 per source
    private final ExecutorService executor = Executors.newFixedThreadPool(2, new ThreadFactory() {
        private final AtomicInteger index = new AtomicInteger(1);
        @Override
        public Thread newThread(Runnable r) {
            Thread t = new Thread(r, "favorite-update-worker-" + index.getAndIncrement());
            t.setPriority(Thread.NORM_PRIORITY - 1);
            return t;
        }
    });

    private final List<CheckTask> taskQueue = new ArrayList<>();
    private final Set<String> runningSources = new HashSet<>();
    private int runningCount = 0;

    private static final class CheckTask {
        final String comicId;
        final ComicSource client;
        final SourceResolver resolver;

        CheckTask(String comicId, ComicSource client, SourceResolver resolver) {
            this.comicId = comicId;
            this.client = client;
            this.resolver = resolver;
        }
    }

    private FavoriteUpdateCoordinator() {
        Handler handler = null;
        try {
            Looper looper = Looper.getMainLooper();
            if (looper != null) {
                handler = new Handler(looper);
            }
        } catch (Throwable ignored) {
        }
        this.mainHandler = handler;
    }

    public void init(SharedPreferences prefs) {
        synchronized (lock) {
            this.sharedPreferences = prefs;
            if (prefs != null) {
                restoreStates(prefs.getString(PREF_KEY, "{}"));
            }
        }
    }

    public void setBadgeChangeListener(BadgeChangeListener listener) {
        synchronized (lock) {
            this.badgeChangeListener = listener;
        }
    }

    public boolean shouldShowBadge(String comicId) {
        if (isEmpty(comicId)) return false;
        FavoriteUpdateState state = states.get(comicId);
        return state != null && state.pendingUpdate && checkedInSession.contains(comicId);
    }

    public void startStartupCheck(List<String> favoriteSnapshot, SourceResolver resolver,
                                  Map<String, ComicModels.ComicDetail> cachedDetails) {
        if (favoriteSnapshot == null || favoriteSnapshot.isEmpty() || resolver == null) {
            return;
        }
        synchronized (lock) {
            if (sessionStarted) {
                return;
            }
            sessionStarted = true;

            // Initialize baseline for existing cached details if state not present
            for (String comicId : favoriteSnapshot) {
                if (!states.containsKey(comicId) && cachedDetails != null) {
                    ComicModels.ComicDetail detail = cachedDetails.get(comicId);
                    if (detail != null && detail.chapters != null && !detail.chapters.isEmpty()) {
                        FavoriteRevision rev = FavoriteRevision.fromDetail(detail);
                        FavoriteUpdateState state = new FavoriteUpdateState(
                                detail.summary != null ? detail.summary.sourceId : "",
                                comicId, false, rev, rev);
                        states.put(comicId, state);
                    }
                }
            }
            persistStatesLocked();

            for (String comicId : favoriteSnapshot) {
                if (!resolver.isSourceAvailable(comicId)) {
                    continue;
                }
                ComicSource client = resolver.resolveSource(comicId);
                if (client == null) {
                    continue;
                }
                taskQueue.add(new CheckTask(comicId, client, resolver));
            }
            dispatchNextTasksLocked();
        }
    }

    private void dispatchNextTasksLocked() {
        if (taskQueue.isEmpty() || runningCount >= 2) {
            return;
        }
        Iterator<CheckTask> it = taskQueue.iterator();
        while (it.hasNext() && runningCount < 2) {
            CheckTask task = it.next();
            String sourceId = task.client.id();
            if (!runningSources.contains(sourceId)) {
                it.remove();
                runningSources.add(sourceId);
                runningCount++;
                executeTask(task);
            }
        }
    }

    private void executeTask(CheckTask task) {
        final String comicId = task.comicId;
        final ComicSource client = task.client;
        final int startVisitEpoch = getVisitEpoch(comicId);
        final int startFavoriteEpoch = getFavoriteEpoch(comicId);

        executor.submit(() -> {
            FavoriteRevision newRev = null;
            try {
                FavoriteUpdateState state = states.get(comicId);
                FavoriteRevision baseline = state != null ? state.acknowledgedRevision : null;
                newRev = FavoriteUpdateChecker.check(client, comicId, baseline);
            } catch (Exception ignored) {
            }

            boolean notifyVisible = false;
            synchronized (lock) {
                runningSources.remove(client.id());
                runningCount--;
                dispatchNextTasksLocked();

                // Discard if favorite was removed/re-added while task was in-flight
                if (getFavoriteEpoch(comicId) != startFavoriteEpoch) {
                    return;
                }

                if (newRev != null) {
                    FavoriteUpdateState state = states.get(comicId);
                    if (state == null) {
                        // First observation establishes baseline, do not light up star
                        state = new FavoriteUpdateState(client.id(), comicId, false, newRev, newRev);
                        states.put(comicId, state);
                        checkedInSession.add(comicId);
                        persistStatesLocked();
                    } else if (state.acknowledgedRevision == null) {
                        state.acknowledgedRevision = newRev;
                        state.observedRevision = newRev;
                        state.pendingUpdate = false;
                        checkedInSession.add(comicId);
                        persistStatesLocked();
                    } else {
                        boolean hasNew = FavoriteRevision.hasNewChapters(state.acknowledgedRevision, newRev);
                        int currentVisitEpoch = getVisitEpoch(comicId);
                        if (currentVisitEpoch > startVisitEpoch) {
                            // User opened detail while check was in flight: advance baseline silently, do not light up
                            state.acknowledgedRevision = newRev;
                            state.observedRevision = newRev;
                            state.pendingUpdate = false;
                            checkedInSession.add(comicId);
                            persistStatesLocked();
                        } else {
                            state.observedRevision = newRev;
                            state.pendingUpdate = hasNew;
                            checkedInSession.add(comicId);
                            persistStatesLocked();
                            if (hasNew) {
                                notifyVisible = true;
                            }
                        }
                    }
                }
            }

            if (notifyVisible) {
                postBadgeNotification(comicId, true);
            }
        });
    }

    public void onUserEnterDetail(String comicId) {
        if (isEmpty(comicId)) return;
        visitEpochs.compute(comicId, (k, v) -> v == null ? 1 : v + 1);
        synchronized (lock) {
            FavoriteUpdateState state = states.get(comicId);
            if (state != null) {
                state.pendingUpdate = false;
                if (state.observedRevision != null) {
                    state.acknowledgedRevision = state.observedRevision;
                }
                persistStatesLocked();
            }
        }
        postBadgeNotification(comicId, false);
    }

    public void onFavoriteAdded(String comicId, ComicModels.ComicDetail detail) {
        if (isEmpty(comicId)) return;
        favoriteEpochs.compute(comicId, (k, v) -> v == null ? 1 : v + 1);
        synchronized (lock) {
            FavoriteRevision rev = detail != null ? FavoriteRevision.fromDetail(detail) : null;
            String sourceId = detail != null && detail.summary != null ? detail.summary.sourceId : "";
            FavoriteUpdateState state = new FavoriteUpdateState(sourceId, comicId, false, rev, rev);
            states.put(comicId, state);
            persistStatesLocked();
        }
    }

    public void onFavoriteRemoved(String comicId) {
        if (isEmpty(comicId)) return;
        favoriteEpochs.compute(comicId, (k, v) -> v == null ? 1 : v + 1);
        synchronized (lock) {
            states.remove(comicId);
            checkedInSession.remove(comicId);
            persistStatesLocked();
        }
        postBadgeNotification(comicId, false);
    }

    public void pruneDeletedFavorites(List<String> currentFavorites) {
        if (currentFavorites == null) return;
        synchronized (lock) {
            Set<String> favSet = new HashSet<>(currentFavorites);
            boolean changed = false;
            Iterator<Map.Entry<String, FavoriteUpdateState>> it = states.entrySet().iterator();
            while (it.hasNext()) {
                Map.Entry<String, FavoriteUpdateState> entry = it.next();
                if (!favSet.contains(entry.getKey())) {
                    it.remove();
                    checkedInSession.remove(entry.getKey());
                    changed = true;
                }
            }
            if (changed) {
                persistStatesLocked();
            }
        }
    }

    public int getVisitEpoch(String comicId) {
        Integer val = visitEpochs.get(comicId);
        return val == null ? 0 : val;
    }

    public int getFavoriteEpoch(String comicId) {
        Integer val = favoriteEpochs.get(comicId);
        return val == null ? 0 : val;
    }

    public FavoriteUpdateState getState(String comicId) {
        return states.get(comicId);
    }

    private void postBadgeNotification(String comicId, boolean visible) {
        Runnable task = () -> {
            BadgeChangeListener listener;
            synchronized (lock) {
                listener = badgeChangeListener;
            }
            if (listener != null) {
                listener.onBadgeChanged(comicId, visible);
            }
        };
        if (mainHandler != null) {
            mainHandler.post(task);
        } else {
            task.run();
        }
    }

    private void restoreStates(String json) {
        if (isEmpty(json)) return;
        try {
            JSONObject obj = new JSONObject(json);
            Iterator<String> keys = obj.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                JSONObject item = obj.optJSONObject(key);
                if (item != null) {
                    FavoriteUpdateState state = FavoriteUpdateState.fromJson(item);
                    if (state != null) {
                        states.put(key, state);
                    }
                }
            }
        } catch (JSONException ignored) {
        }
    }

    private void persistStatesLocked() {
        if (sharedPreferences == null) return;
        try {
            JSONObject obj = new JSONObject();
            for (Map.Entry<String, FavoriteUpdateState> entry : states.entrySet()) {
                obj.put(entry.getKey(), entry.getValue().toJson());
            }
            sharedPreferences.edit().putString(PREF_KEY, obj.toString()).apply();
        } catch (JSONException ignored) {
        }
    }

    void resetForTesting() {
        synchronized (lock) {
            sessionStarted = false;
            checkedInSession.clear();
            visitEpochs.clear();
            favoriteEpochs.clear();
            states.clear();
            taskQueue.clear();
            runningSources.clear();
            runningCount = 0;
            badgeChangeListener = null;
            sharedPreferences = null;
        }
    }

    private static boolean isEmpty(String str) {
        return str == null || str.isEmpty();
    }
}
