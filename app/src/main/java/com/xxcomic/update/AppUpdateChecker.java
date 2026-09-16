package com.xxcomic.update;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Future;

public final class AppUpdateChecker {
    private static final AppUpdateChecker INSTANCE = new AppUpdateChecker();

    public static AppUpdateChecker getInstance() {
        return INSTANCE;
    }

    public interface StartupCheckCallback {
        void onStartupCheckFinished(AppRelease release);
    }

    public interface ManualCheckCallback {
        void onManualCheckSuccess(AppRelease release);
        void onManualCheckFailure(Exception error);
    }

    private final Object lock = new Object();
    private boolean sessionStarted = false;
    private boolean startupCompleted = false;
    private boolean sessionPromptDismissed = false;
    private StartupCheckCallback startupCallback;
    private AppRelease cachedRelease = null;
    private Future<?> inFlightFuture = null;
    private final List<ManualCheckCallback> manualListeners = new ArrayList<>();

    AppUpdateChecker() {
    }

    public boolean isSessionPromptDismissed() {
        synchronized (lock) {
            return sessionPromptDismissed;
        }
    }

    public void markSessionPromptDismissed() {
        synchronized (lock) {
            sessionPromptDismissed = true;
        }
    }

    public AppRelease getCachedRelease() {
        synchronized (lock) {
            return cachedRelease;
        }
    }

    public boolean triggerStartupCheck(ExecutorService executor, String metadataUrl,
                                       String userAgent, int currentVersionCode,
                                       StartupCheckCallback callback) {
        AppRelease replay = null;
        boolean deliverReplay = false;
        synchronized (lock) {
            // Each Activity subscribes to the process-owned result without starting a new request.
            startupCallback = callback;
            if (sessionStarted) {
                deliverReplay = startupCompleted && !sessionPromptDismissed;
                replay = cachedRelease;
            } else {
                sessionStarted = true;
                executeIfNeededLocked(executor, metadataUrl, userAgent);
                return true;
            }
        }
        if (deliverReplay && callback != null) callback.onStartupCheckFinished(replay);
        return false;
    }

    public void detachStartupCallback(StartupCheckCallback callback) {
        synchronized (lock) {
            if (startupCallback == callback) startupCallback = null;
        }
    }

    public void triggerManualCheck(ExecutorService executor, String metadataUrl,
                                  String userAgent, ManualCheckCallback callback) {
        synchronized (lock) {
            // Manual presentation supersedes any pending automatic prompt for this session.
            sessionPromptDismissed = true;
            manualListeners.add(callback);
            executeIfNeededLocked(executor, metadataUrl, userAgent);
        }
    }

    private void executeIfNeededLocked(ExecutorService executor, String metadataUrl, String userAgent) {
        if (inFlightFuture != null && !inFlightFuture.isDone() && !inFlightFuture.isCancelled()) {
            // Already checking, join the running request
            return;
        }
        inFlightFuture = executor.submit(() -> {
            AppRelease result = null;
            Exception error = null;
            try {
                result = fetchAppRelease(metadataUrl, userAgent);
            } catch (Exception e) {
                error = e;
            }

            List<ManualCheckCallback> targets;
            StartupCheckCallback startupTarget;
            synchronized (lock) {
                cachedRelease = result;
                startupCompleted = sessionStarted;
                targets = new ArrayList<>(manualListeners);
                manualListeners.clear();
                inFlightFuture = null;
                startupTarget = sessionPromptDismissed ? null : startupCallback;
            }

            for (ManualCheckCallback target : targets) {
                if (error != null) target.onManualCheckFailure(error);
                else target.onManualCheckSuccess(result);
            }
            if (startupTarget != null) startupTarget.onStartupCheckFinished(result);
        });
    }

    public static AppRelease fetchAppRelease(String metadataUrl, String userAgent) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(metadataUrl).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(15000);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("User-Agent", userAgent);
        try {
            int code = connection.getResponseCode();
            if (code < 200 || code >= 300) throw new IOException("HTTP " + code);
            JSONObject object;
            try (InputStream stream = connection.getInputStream()) {
                object = new JSONObject(new String(readAllBytes(stream), "UTF-8"));
            }
            return AppRelease.parse(object);
        } finally {
            connection.disconnect();
        }
    }

    private static byte[] readAllBytes(InputStream stream) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        byte[] chunk = new byte[8192];
        int read;
        while ((read = stream.read(chunk)) != -1) {
            buffer.write(chunk, 0, read);
        }
        return buffer.toByteArray();
    }
}
