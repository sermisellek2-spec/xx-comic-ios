package com.xxcomic.update;

import org.junit.Test;
import static org.junit.Assert.*;

public class UpdatePromptPolicyTest {
    @Test
    public void testIsIgnoredToday() {
        assertFalse(UpdatePromptPolicy.isIgnoredToday(null, "2026-09-19"));
        assertFalse(UpdatePromptPolicy.isIgnoredToday("", "2026-09-19"));
        assertFalse(UpdatePromptPolicy.isIgnoredToday("2026-09-18", "2026-09-19"));
        assertTrue(UpdatePromptPolicy.isIgnoredToday("2026-09-19", "2026-09-19"));
        assertFalse(UpdatePromptPolicy.isIgnoredToday("2026-09-19", null));
        assertFalse(UpdatePromptPolicy.isIgnoredToday(null, null));
    }
}
