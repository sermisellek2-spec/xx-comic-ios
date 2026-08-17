package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

public class ProtectedSourceSessionIsolationTest {
    @Test
    public void protectedSourcesUseIndependentNativeWebViewSessions() {
        String nativeAgent = "Mozilla/5.0 Chrome/139.0.0.0 Mobile";

        assertFalse(Mh18WebViewSession.class.isAssignableFrom(JmComicWebViewSession.class));
        assertFalse(JmComicWebViewSession.class.isAssignableFrom(Mh18WebViewSession.class));
        assertEquals(nativeAgent, Mh18WebViewSession.selectedUserAgent(nativeAgent));
        assertEquals(nativeAgent, JmComicWebViewSession.selectedUserAgent(nativeAgent));
    }
}
