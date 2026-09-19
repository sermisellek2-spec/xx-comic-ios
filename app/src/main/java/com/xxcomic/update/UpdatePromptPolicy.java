package com.xxcomic.update;

public final class UpdatePromptPolicy {
    private UpdatePromptPolicy() {
    }

    public static boolean isIgnoredToday(String savedDate, String todayDate) {
        if (savedDate == null || todayDate == null) return false;
        return !savedDate.isEmpty() && savedDate.equals(todayDate);
    }
}
