package com.xxcomic;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class ProtectedSourceUiTest {
    @Test
    public void vpnSourcesAreExplicit() {
        assertTrue(MainActivity.requiresVpn("mh18"));
        assertTrue(MainActivity.requiresVpn("jmcomic"));
        assertTrue(MainActivity.requiresVpn("hiperdex"));
        assertTrue(MainActivity.requiresVpn("hanman18"));
        assertTrue(MainActivity.requiresVpn("manhuagui"));
        assertFalse(MainActivity.requiresVpn("baozimh"));
    }

    @Test
    public void onlyCloudflareSourcesCanBeVerifiedManually() {
        assertTrue(MainActivity.supportsManualVerification("mh18"));
        assertTrue(MainActivity.supportsManualVerification("jmcomic"));
        assertFalse(MainActivity.supportsManualVerification("hiperdex"));
        assertFalse(MainActivity.supportsManualVerification("hanman18"));
        assertFalse(MainActivity.supportsManualVerification("manhuagui"));
    }
}
