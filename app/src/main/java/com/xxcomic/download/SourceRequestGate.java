package com.xxcomic.download;

import java.io.InterruptedIOException;
import java.util.HashMap;
import java.util.Map;

/** Keeps requests polite per source while allowing unrelated sources to progress. */
public final class SourceRequestGate {
    private static final long THROTTLE_BASE_MS = 1500L;

    private static final class State {
        long nextRequestAt;
        long cooldownUntil;
        int throttledResponses;
    }

    private final long intervalMs;
    private final long maxCooldownMs;
    private final Map<String, State> states = new HashMap<>();

    public SourceRequestGate(long intervalMs, long maxCooldownMs) {
        this.intervalMs = Math.max(0L, intervalMs);
        this.maxCooldownMs = Math.max(1L, maxCooldownMs);
    }

    public void before(String sourceId) throws InterruptedIOException {
        if (sourceId == null || sourceId.trim().isEmpty()) return;
        synchronized (states) {
            State state = states.computeIfAbsent(sourceId, ignored -> new State());
            while (true) {
                long waitMs = Math.max(state.nextRequestAt, state.cooldownUntil) - now();
                if (waitMs <= 0L) {
                    state.nextRequestAt = now() + intervalMs;
                    return;
                }
                try {
                    states.wait(Math.min(waitMs, 250L));
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    throw new InterruptedIOException("请求等待已取消");
                }
            }
        }
    }

    public void onSuccess(String sourceId) {
        if (sourceId == null || sourceId.trim().isEmpty()) return;
        synchronized (states) {
            State state = states.get(sourceId);
            if (state == null) return;
            if (state.cooldownUntil <= now()) state.throttledResponses = 0;
            states.notifyAll();
        }
    }

    public void onFailure(String sourceId, int status, long retryAfterMs) {
        if (sourceId == null || sourceId.trim().isEmpty() || (status != 429 && status != 503)) return;
        synchronized (states) {
            State state = states.computeIfAbsent(sourceId, ignored -> new State());
            state.throttledResponses = Math.min(8, state.throttledResponses + 1);
            long exponential = THROTTLE_BASE_MS << Math.min(6, state.throttledResponses - 1);
            long requested = retryAfterMs > 0L ? retryAfterMs : exponential;
            long delay = Math.min(maxCooldownMs, Math.max(1L, requested));
            state.cooldownUntil = Math.max(state.cooldownUntil, now() + delay);
            states.notifyAll();
        }
    }

    public long cooldownRemaining(String sourceId) {
        if (sourceId == null || sourceId.trim().isEmpty()) return 0L;
        synchronized (states) {
            State state = states.get(sourceId);
            if (state == null) return 0L;
            return Math.max(0L, Math.max(state.nextRequestAt, state.cooldownUntil) - now());
        }
    }

    private static long now() {
        return System.nanoTime() / 1_000_000L;
    }
}
