package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

public class ProtectedSourceSessionIsolationTest {
    @Test
    public void protectedSourcesUseIndependentChrome124Sessions() {
        String mh18Agent = Mh18WebViewSession.fixedUserAgent();
        String jmcomicAgent = JmComicWebViewSession.fixedUserAgent();

        assertFalse(Mh18WebViewSession.class.isAssignableFrom(JmComicWebViewSession.class));
        assertFalse(JmComicWebViewSession.class.isAssignableFrom(Mh18WebViewSession.class));
        assertEquals(mh18Agent, jmcomicAgent);
    }
}
