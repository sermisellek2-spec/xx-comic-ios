package com.xxcomic.download;

import org.junit.Test;

import java.io.InterruptedIOException;

import static org.junit.Assert.assertTrue;

public class SourceRequestGateTest {
    @Test public void sameSourceRequestsAreSpaced() throws Exception {
        SourceRequestGate gate = new SourceRequestGate(40, 1000);
        gate.before("source");
        long started = System.nanoTime();
        gate.before("source");
        long elapsedMs = (System.nanoTime() - started) / 1_000_000L;
        assertTrue("second request should wait for the source interval", elapsedMs >= 25);
    }

    @Test public void differentSourcesDoNotShareTheInterval() throws Exception {
        SourceRequestGate gate = new SourceRequestGate(1000, 1000);
        gate.before("source-a");
        long started = System.nanoTime();
        gate.before("source-b");
        long elapsedMs = (System.nanoTime() - started) / 1_000_000L;
        assertTrue("different source should not wait", elapsedMs < 250);
    }

    @Test public void throttledStatusCreatesBoundedCooldown() throws Exception {
        SourceRequestGate gate = new SourceRequestGate(1, 1000);
        gate.onFailure("source", 503, 0);
        assertTrue(gate.cooldownRemaining("source") > 0);
        assertTrue(gate.cooldownRemaining("source") <= 1000);
    }

    @Test public void retryAfterTakesPrecedenceAndIsCapped() {
        SourceRequestGate gate = new SourceRequestGate(1, 500);
        gate.onFailure("source", 429, 5000);
        assertTrue(gate.cooldownRemaining("source") <= 500);
        assertTrue(gate.cooldownRemaining("source") >= 350);
    }

    @Test public void inFlightSuccessDoesNotCancelAConcurrentThrottle() {
        SourceRequestGate gate = new SourceRequestGate(1, 1000);
        gate.onFailure("source", 503, 500);
        gate.onSuccess("source");
        assertTrue(gate.cooldownRemaining("source") > 0);
    }

    @Test(expected = InterruptedIOException.class)
    public void interruptedWaitStopsPromptly() throws Exception {
        SourceRequestGate gate = new SourceRequestGate(1, 1000);
        gate.onFailure("source", 503, 1000);
        Thread.currentThread().interrupt();
        try {
            gate.before("source");
        } finally {
            Thread.interrupted();
        }
    }
}
