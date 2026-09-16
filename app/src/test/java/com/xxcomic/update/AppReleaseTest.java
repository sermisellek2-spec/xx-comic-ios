package com.xxcomic.update;

import org.json.JSONObject;
import org.junit.Test;

import java.io.IOException;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class AppReleaseTest {

    private static final String VALID_SHA256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    @Test
    public void testParseValidReleaseWithDefaultMode() throws Exception {
        JSONObject json = new JSONObject();
        json.put("versionName", "2.1.0");
        json.put("versionCode", 217);
        json.put("size", 1024000L);
        json.put("sha256", VALID_SHA256);

        AppRelease release = AppRelease.parse(json);
        assertEquals("2.1.0", release.versionName);
        assertEquals(217, release.versionCode);
        assertEquals(1024000L, release.size);
        assertEquals(VALID_SHA256, release.sha256);
        assertEquals(AppRelease.MODE_SOFT, release.updateMode);
        assertFalse(release.isPromptMode());
        assertEquals("", release.releaseNotes);
    }

    @Test
    public void testParsePromptMode() throws Exception {
        JSONObject json = new JSONObject();
        json.put("versionName", "2.1.0");
        json.put("versionCode", 217);
        json.put("size", 1024000L);
        json.put("sha256", VALID_SHA256);
        json.put("updateMode", "prompt");
        json.put("releaseNotes", "修复重要已知问题\n优化体验");

        AppRelease release = AppRelease.parse(json);
        assertEquals(AppRelease.MODE_PROMPT, release.updateMode);
        assertTrue(release.isPromptMode());
        assertEquals("修复重要已知问题\n优化体验", release.releaseNotes);
    }

    @Test
    public void testParseInvalidModeFallsBackToSoft() throws Exception {
        JSONObject json = new JSONObject();
        json.put("versionName", "2.1.0");
        json.put("versionCode", 217);
        json.put("size", 1024000L);
        json.put("sha256", VALID_SHA256);
        json.put("updateMode", "forced_unknown");

        AppRelease release = AppRelease.parse(json);
        assertEquals(AppRelease.MODE_SOFT, release.updateMode);
        assertFalse(release.isPromptMode());
    }

    @Test
    public void testLongReleaseNotesTruncation() {
        StringBuilder longNotes = new StringBuilder();
        for (int i = 0; i < 2500; i++) {
            longNotes.append("a");
        }
        AppRelease release = new AppRelease("2.1.0", 217, 1000L, VALID_SHA256, "soft", longNotes.toString());
        assertEquals(2000, release.releaseNotes.length());
    }

    @Test
    public void testVersionComparison() {
        AppRelease release = new AppRelease("2.1.0", 217, 1000L, VALID_SHA256, "soft", "");
        assertTrue(release.hasNewVersion(216));
        assertFalse(release.hasNewVersion(217));
        assertFalse(release.hasNewVersion(218));
    }

    @Test(expected = IOException.class)
    public void testParseNullObject() throws Exception {
        AppRelease.parse(null);
    }

    @Test(expected = IOException.class)
    public void testParseInvalidVersionName() throws Exception {
        JSONObject json = new JSONObject();
        json.put("versionName", "v2.1");
        json.put("versionCode", 217);
        json.put("size", 1000L);
        json.put("sha256", VALID_SHA256);
        AppRelease.parse(json);
    }

    @Test(expected = IOException.class)
    public void testParseInvalidVersionCode() throws Exception {
        JSONObject json = new JSONObject();
        json.put("versionName", "2.1.0");
        json.put("versionCode", 0);
        json.put("size", 1000L);
        json.put("sha256", VALID_SHA256);
        AppRelease.parse(json);
    }

    @Test(expected = IOException.class)
    public void testParseInvalidSha256() throws Exception {
        JSONObject json = new JSONObject();
        json.put("versionName", "2.1.0");
        json.put("versionCode", 217);
        json.put("size", 1000L);
        json.put("sha256", "not-a-valid-sha256");
        AppRelease.parse(json);
    }
}
