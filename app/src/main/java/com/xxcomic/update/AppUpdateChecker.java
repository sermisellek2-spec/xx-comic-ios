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

    private static final class CheckRequest {
        final StartupCheckCallback startupCallback;
        final ManualCheckCallback manualCallback;

        CheckRequest(StartupCheckCallback startupCallback, ManualCheckCallback manualCallback) {
            this.startupCallback = startupCallback;
            this.manualCallback = manualCallback;
        }
    }

    private final Object lock = new Object();
    private boolean sessionStarted = false;
    private boolean sessionPromptDismissed = false;
    private AppRelease cachedRelease = null;
    private Future<?> inFlightFuture = null;
    private final List<CheckRequest> listeners = new ArrayList<>();

    private AppUpdateChecker() {
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
        synchronized (lock) {
            if (sessionStarted) {
                return false;
            }
            sessionStarted = true;
            CheckRequest req = new CheckRequest(callback, null);
            attachOrExecuteLocked(executor, metadataUrl, userAgent, req);
            return true;
        }
    }

    public void triggerManualCheck(ExecutorService executor, String metadataUrl,
                                  String userAgent, ManualCheckCallback callback) {
        synchronized (lock) {
            CheckRequest req = new CheckRequest(null, callback);
            attachOrExecuteLocked(executor, metadataUrl, userAgent, req);
        }
    }

    private void attachOrExecuteLocked(ExecutorService executor, String metadataUrl,
                                       String userAgent, CheckRequest request) {
        listeners.add(request);
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

            List<CheckRequest> targets;
            boolean hasManualListener = false;
            synchronized (lock) {
                cachedRelease = result;
                targets = new ArrayList<>(listeners);
                listeners.clear();
                inFlightFuture = null;
                for (CheckRequest req : targets) {
                    if (req.manualCallback != null) {
                        hasManualListener = true;
                        break;
                    }
                }
            }

            for (CheckRequest req : targets) {
                if (req.manualCallback != null) {
                    if (error != null) {
                        req.manualCallback.onManualCheckFailure(error);
                    } else {
                        req.manualCallback.onManualCheckSuccess(result);
                    }
                } else if (req.startupCallback != null) {
                    // If a manual check joined and took over result display, suppress startup callback
                    if (!hasManualListener) {
                        req.startupCallback.onStartupCheckFinished(error != null ? null : result);
                    }
                }
            }
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
