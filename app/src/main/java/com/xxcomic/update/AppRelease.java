package com.xxcomic.update;

import org.json.JSONObject;

import java.io.IOException;
import java.util.Locale;

public final class AppRelease {
    public static final String MODE_SOFT = "soft";
    public static final String MODE_PROMPT = "prompt";
    private static final int MAX_NOTES_LENGTH = 2000;

    public final String versionName;
    public final int versionCode;
    public final long size;
    public final String sha256;
    public final String updateMode;
    public final String releaseNotes;

    public AppRelease(String versionName, int versionCode, long size, String sha256,
                      String updateMode, String releaseNotes) {
        this.versionName = versionName == null ? "" : versionName;
        this.versionCode = versionCode;
        this.size = size;
        this.sha256 = sha256 == null ? "" : sha256.toLowerCase(Locale.US);
        this.updateMode = normalizeMode(updateMode);
        this.releaseNotes = normalizeNotes(releaseNotes);
    }

    public static AppRelease parse(JSONObject object) throws IOException {
        if (object == null) {
            throw new IOException("更新元数据为空");
        }
        String versionName = object.optString("versionName", "");
        int versionCode = object.optInt("versionCode", 0);
        long size = object.optLong("size", 0L);
        String sha256 = object.optString("sha256", "").toLowerCase(Locale.US);
        if (!versionName.matches("[0-9]+(?:\\.[0-9]+){2}")
                || versionCode < 1
                || size < 1L
                || !sha256.matches("[0-9a-f]{64}")) {
            throw new IOException("更新元数据无效");
        }
        String updateMode = object.optString("updateMode", MODE_SOFT);
        String releaseNotes = object.optString("releaseNotes", "");
        return new AppRelease(versionName, versionCode, size, sha256, updateMode, releaseNotes);
    }

    public boolean hasNewVersion(int currentVersionCode) {
        return versionCode > currentVersionCode;
    }

    public boolean isPromptMode() {
        return MODE_PROMPT.equals(updateMode);
    }

    private static String normalizeMode(String mode) {
        if (mode == null) return MODE_SOFT;
        String trimmed = mode.trim().toLowerCase(Locale.US);
        return MODE_PROMPT.equals(trimmed) ? MODE_PROMPT : MODE_SOFT;
    }

    private static String normalizeNotes(String notes) {
        if (notes == null) return "";
        String trimmed = notes.trim();
        if (trimmed.length() > MAX_NOTES_LENGTH) {
            return trimmed.substring(0, MAX_NOTES_LENGTH);
        }
        return trimmed;
    }
}
