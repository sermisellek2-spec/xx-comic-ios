package com.xxcomic.reader;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Tracks local vs online reading sessions and evaluates bookshelf launch preference.
 * Uses completely local calculations, no network, no user tracking.
 */
public class ReadingHabitTracker {

    public interface TimeProvider {
        long elapsedRealtime();
        long currentTimeMillis();
    }

    public static final TimeProvider SYSTEM_TIME_PROVIDER = new TimeProvider() {
        @Override
        public long elapsedRealtime() {
            return android.os.SystemClock.elapsedRealtime();
        }

        @Override
        public long currentTimeMillis() {
            return System.currentTimeMillis();
        }
    };

    public interface OnHabitChangeListener {
        void onHabitUpdated(ReadingHabitTracker tracker);
    }

    public static final int PREF_NONE = 0;   // 学习中
    public static final int PREF_MY = 1;     // 我的书架
    public static final int PREF_LOCAL = 2;  // 本地书架

    public static final int LAUNCH_MODE_AUTO = 0;   // 自动跟随习惯
    public static final int LAUNCH_MODE_MY = 1;     // 我的书架
    public static final int LAUNCH_MODE_LOCAL = 2;  // 本地书架

    public static final long MIN_READING_TIME_MS = 60_000L;          // 60s reading required
    public static final long INACTIVITY_TIMEOUT_MS = 120_000L;        // 120s idle cutoff
    public static final long BACKGROUND_TIMEOUT_MS = 300_000L;        // 5 min background timeout
    public static final long SAMPLE_EXPIRY_MS = 30L * 24 * 60 * 60 * 1000L; // 30 days
    public static final int MAX_SAMPLES = 10;
    public static final int MIN_SAMPLES_TO_DECIDE = 5;

    public static final class Sample {
        public final long timestamp;
        public final boolean isLocal;

        public Sample(long timestamp, boolean isLocal) {
            this.timestamp = timestamp;
            this.isLocal = isLocal;
        }
    }

    public static final class Session {
        public final String comicId;
        public final boolean isLocal;
        public boolean isAutoFollowHabit;
        public boolean contentReadable;
        public boolean hasUserAction;
        public boolean isForeground = true;
        public boolean overlayVisible = false;
        public boolean voted = false;
        public long accumulatedReadingMs = 0L;
        public long lastActiveTime;
        public long lastTickTime;
        public long backgroundTime = 0L;

        public Session(String comicId, boolean isLocal, long now) {
            this.comicId = comicId;
            this.isLocal = isLocal;
            this.lastActiveTime = now;
            this.lastTickTime = now;
        }
    }

    private final TimeProvider timeProvider;
    private final List<Sample> samples = new ArrayList<>();
    private int launchMode = LAUNCH_MODE_AUTO;
    private int lastManualTab = 0; // 0: 我的书架, 1: 本地书架
    private int learnedPreference = PREF_NONE;
    private Session currentSession;
    private OnHabitChangeListener listener;

    public ReadingHabitTracker() {
        this(SYSTEM_TIME_PROVIDER);
    }

    public ReadingHabitTracker(TimeProvider timeProvider) {
        this.timeProvider = timeProvider != null ? timeProvider : SYSTEM_TIME_PROVIDER;
    }

    public void setListener(OnHabitChangeListener listener) {
        this.listener = listener;
    }

    public int getLaunchMode() {
        return launchMode;
    }

    public void setLaunchMode(int launchMode) {
        this.launchMode = launchMode;
        if (currentSession != null) {
            currentSession.isAutoFollowHabit = (launchMode == LAUNCH_MODE_AUTO);
        }
        if (listener != null) listener.onHabitUpdated(this);
    }

    public int getLastManualTab() {
        return lastManualTab;
    }

    public void setLastManualTab(int lastManualTab) {
        this.lastManualTab = lastManualTab == 1 ? 1 : 0;
        if (listener != null) listener.onHabitUpdated(this);
    }

    public int getLearnedPreference() {
        return learnedPreference;
    }

    public List<Sample> getSamples() {
        return Collections.unmodifiableList(samples);
    }

    public Session getCurrentSession() {
        return currentSession;
    }

    // --- Pure Evaluation Functions ---

    public static int evaluatePreference(List<Sample> allSamples, int previousLearned, long currentTime) {
        if (allSamples == null || allSamples.isEmpty()) {
            return previousLearned;
        }
        List<Sample> valid = new ArrayList<>();
        long cutoff = currentTime - SAMPLE_EXPIRY_MS;
        for (Sample s : allSamples) {
            if (s != null && s.timestamp >= cutoff) {
                valid.add(s);
            }
        }
        Collections.sort(valid, (a, b) -> Long.compare(b.timestamp, a.timestamp));
        if (valid.size() > MAX_SAMPLES) {
            valid = new ArrayList<>(valid.subList(0, MAX_SAMPLES));
        }
        if (valid.size() < MIN_SAMPLES_TO_DECIDE) {
            return previousLearned;
        }
        int localCount = 0;
        for (Sample s : valid) {
            if (s.isLocal) localCount++;
        }
        int total = valid.size();
        int onlineCount = total - localCount;
        if (localCount * 10 >= total * 7) {
            return PREF_LOCAL;
        }
        if (onlineCount * 10 >= total * 7) {
            return PREF_MY;
        }
        return previousLearned;
    }

    public static int resolveLaunchTab(int launchMode, int learnedPreference, int lastManualTab) {
        if (launchMode == LAUNCH_MODE_MY) {
            return 0;
        }
        if (launchMode == LAUNCH_MODE_LOCAL) {
            return 1;
        }
        if (learnedPreference == PREF_LOCAL) {
            return 1;
        }
        if (learnedPreference == PREF_MY) {
            return 0;
        }
        return lastManualTab == 1 ? 1 : 0;
    }

    public static String getAutoSubtitle(int learnedPreference, int effectiveTab) {
        if (learnedPreference == PREF_LOCAL) {
            return "当前偏好：本地书架";
        }
        if (learnedPreference == PREF_MY) {
            return "当前偏好：我的书架";
        }
        return "学习中 · 启动显示" + (effectiveTab == 1 ? "本地书架" : "我的书架");
    }

    public int resolveCurrentLaunchTab() {
        return resolveLaunchTab(launchMode, learnedPreference, lastManualTab);
    }

    public String getCurrentAutoSubtitle() {
        return getAutoSubtitle(learnedPreference, resolveCurrentLaunchTab());
    }

    // --- Session Lifecycle Events ---

    public void onEnterReader(String comicId, boolean isLocal) {
        long now = timeProvider.elapsedRealtime();
        if (currentSession != null) {
            if (currentSession.comicId != null && currentSession.comicId.equals(comicId)) {
                if (currentSession.backgroundTime > 0 && now - currentSession.backgroundTime > BACKGROUND_TIMEOUT_MS) {
                    currentSession = new Session(comicId, isLocal, now);
                } else {
                    if (currentSession.backgroundTime > 0) {
                        currentSession.lastActiveTime += (now - currentSession.backgroundTime);
                    }
                    currentSession.isForeground = true;
                    currentSession.backgroundTime = 0;
                    currentSession.lastTickTime = now;
                    currentSession.isAutoFollowHabit = (launchMode == LAUNCH_MODE_AUTO);
                    return;
                }
            } else {
                flushSessionTime();
                currentSession = new Session(comicId, isLocal, now);
            }
        } else {
            currentSession = new Session(comicId, isLocal, now);
        }
        currentSession.isAutoFollowHabit = (launchMode == LAUNCH_MODE_AUTO);
    }

    public void onContentReadable() {
        if (currentSession == null) return;
        long now = timeProvider.elapsedRealtime();
        if (!currentSession.contentReadable) {
            currentSession.contentReadable = true;
            currentSession.lastActiveTime = now;
            currentSession.lastTickTime = now;
        }
        checkVote();
    }

    public void onUserAction() {
        if (currentSession == null) return;
        long now = timeProvider.elapsedRealtime();
        flushSessionTime();
        currentSession.hasUserAction = true;
        currentSession.lastActiveTime = now;
        currentSession.lastTickTime = now;
        checkVote();
    }

    public void onOverlayVisibilityChanged(boolean overlayVisible) {
        if (currentSession == null) return;
        long now = timeProvider.elapsedRealtime();
        flushSessionTime();
        if (!overlayVisible && currentSession.overlayVisible) {
            currentSession.lastActiveTime += (now - currentSession.lastTickTime);
        }
        currentSession.overlayVisible = overlayVisible;
        currentSession.lastTickTime = now;
        checkVote();
    }

    public void onAppBackground() {
        if (currentSession == null) return;
        long now = timeProvider.elapsedRealtime();
        flushSessionTime();
        currentSession.isForeground = false;
        currentSession.backgroundTime = now;
        currentSession.lastTickTime = now;
    }

    public void onAppForeground() {
        if (currentSession == null) return;
        long now = timeProvider.elapsedRealtime();
        if (currentSession.backgroundTime > 0 && now - currentSession.backgroundTime > BACKGROUND_TIMEOUT_MS) {
            currentSession = new Session(currentSession.comicId, currentSession.isLocal, now);
            currentSession.isForeground = true;
            currentSession.contentReadable = true;
            currentSession.isAutoFollowHabit = (launchMode == LAUNCH_MODE_AUTO);
            currentSession.lastActiveTime = now;
            currentSession.lastTickTime = now;
        } else {
            if (currentSession.backgroundTime > 0) {
                currentSession.lastActiveTime += (now - currentSession.backgroundTime);
            }
            currentSession.isForeground = true;
            currentSession.backgroundTime = 0;
            currentSession.lastTickTime = now;
        }
    }

    public void onExitReader() {
        flushSessionTime();
        currentSession = null;
    }

    public void tick() {
        flushSessionTime();
        checkVote();
    }

    private void flushSessionTime() {
        if (currentSession == null) return;
        long now = timeProvider.elapsedRealtime();
        if (!currentSession.contentReadable || !currentSession.isForeground || currentSession.overlayVisible) {
            currentSession.lastTickTime = now;
            return;
        }
        long elapsedSinceLastTick = now - currentSession.lastTickTime;
        currentSession.lastTickTime = now;
        if (elapsedSinceLastTick <= 0) return;

        long activeDeadline = currentSession.lastActiveTime + INACTIVITY_TIMEOUT_MS;
        long periodStart = now - elapsedSinceLastTick;
        long periodEnd = now;

        long effectiveEnd = Math.min(periodEnd, activeDeadline);
        if (effectiveEnd > periodStart) {
            long accum = effectiveEnd - periodStart;
            if (accum > 0) {
                currentSession.accumulatedReadingMs += accum;
            }
        }
    }

    private void checkVote() {
        if (currentSession == null || currentSession.voted) return;
        if (!currentSession.isAutoFollowHabit) return;
        if (!currentSession.hasUserAction) return;
        if (currentSession.accumulatedReadingMs < MIN_READING_TIME_MS) return;

        currentSession.voted = true;
        samples.add(new Sample(timeProvider.currentTimeMillis(), currentSession.isLocal));
        learnedPreference = evaluatePreference(samples, learnedPreference, timeProvider.currentTimeMillis());
        if (listener != null) {
            listener.onHabitUpdated(this);
        }
    }

    public void resetHabit() {
        samples.clear();
        learnedPreference = PREF_NONE;
        if (currentSession != null) {
            currentSession.voted = false;
        }
        if (listener != null) {
            listener.onHabitUpdated(this);
        }
    }

    // --- JSON Serialization for Persistence ---

    public String serializeSamples() {
        JSONArray arr = new JSONArray();
        for (Sample s : samples) {
            if (s == null) continue;
            try {
                JSONObject obj = new JSONObject();
                obj.put("t", s.timestamp);
                obj.put("l", s.isLocal);
                arr.put(obj);
            } catch (Exception ignored) {}
        }
        return arr.toString();
    }

    public void restoreState(int launchMode, int lastManualTab, int learnedPreference, String samplesJson) {
        this.launchMode = launchMode;
        this.lastManualTab = lastManualTab == 1 ? 1 : 0;
        this.learnedPreference = learnedPreference;
        samples.clear();
        if (samplesJson != null && !samplesJson.trim().isEmpty()) {
            try {
                JSONArray arr = new JSONArray(samplesJson);
                for (int i = 0; i < arr.length(); i++) {
                    JSONObject obj = arr.getJSONObject(i);
                    long t = obj.optLong("t", 0L);
                    boolean l = obj.optBoolean("l", false);
                    if (t > 0) {
                        samples.add(new Sample(t, l));
                    }
                }
            } catch (Exception ignored) {}
        }
        this.learnedPreference = evaluatePreference(samples, this.learnedPreference, timeProvider.currentTimeMillis());
    }
}
