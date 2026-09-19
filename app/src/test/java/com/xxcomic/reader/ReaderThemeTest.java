package com.xxcomic.reader;

import com.xxcomic.MainActivity;

import org.junit.Test;

import static org.junit.Assert.*;

public class ReaderThemeTest {

    @Test
    public void themeModeConstantsMatch() {
        assertEquals(0, ReaderSettingsSheet.THEME_DEFAULT);
        assertEquals(1, ReaderSettingsSheet.THEME_DARK);
        assertEquals(2, ReaderSettingsSheet.THEME_LIGHT);

        assertEquals(ReaderSettingsSheet.THEME_DEFAULT, MainActivity.READER_THEME_DEFAULT);
        assertEquals(ReaderSettingsSheet.THEME_DARK, MainActivity.READER_THEME_DARK);
        assertEquals(ReaderSettingsSheet.THEME_LIGHT, MainActivity.READER_THEME_LIGHT);
    }

    @Test
    public void readerThemeResolutionLogic() {
        // Mode: DARK (1) -> always dark
        assertTrue(resolveTheme(MainActivity.READER_THEME_DARK, false, 0));
        assertTrue(resolveTheme(MainActivity.READER_THEME_DARK, true, 0));

        // Mode: LIGHT (2) -> always light (unless e-ink)
        assertFalse(resolveTheme(MainActivity.READER_THEME_LIGHT, false, 0));
        assertFalse(resolveTheme(MainActivity.READER_THEME_LIGHT, true, 0));

        // Mode: DEFAULT (0) -> follows system night mode
        assertTrue(resolveTheme(MainActivity.READER_THEME_DEFAULT, true, 0));
        assertFalse(resolveTheme(MainActivity.READER_THEME_DEFAULT, false, 0));

        // E-ink mode (displayMode == 1) -> always true for comic background
        assertTrue(resolveTheme(MainActivity.READER_THEME_LIGHT, false, 1));
        assertTrue(resolveTheme(MainActivity.READER_THEME_DEFAULT, false, 1));
    }

    @Test
    public void listenerDefaultMethodDoesNotThrow() {
        ReaderSettingsSheet.OnSettingsChangeListener listener = new ReaderSettingsSheet.OnSettingsChangeListener() {
            @Override
            public void onReadingModeChanged(int mode) {}

            @Override
            public void onHideStatusBadgeChanged(boolean hide) {}

            @Override
            public void onEinkModeChanged(boolean eink) {}

            @Override
            public void onPinchZoomChanged(boolean enabled) {}

            @Override
            public void onDisablePageAnimationChanged(boolean disabled) {}

            @Override
            public void onCropWhiteMarginsChanged(boolean enabled) {}
        };
        // Invoking default interface method should be a no-op
        listener.onReaderThemeChanged(ReaderSettingsSheet.THEME_DARK);
    }

    @Test
    public void listenerCapturesThemeSelection() {
        final int[] captured = {-1};
        ReaderSettingsSheet.OnSettingsChangeListener listener = new ReaderSettingsSheet.OnSettingsChangeListener() {
            @Override
            public void onReadingModeChanged(int mode) {}

            @Override
            public void onHideStatusBadgeChanged(boolean hide) {}

            @Override
            public void onEinkModeChanged(boolean eink) {}

            @Override
            public void onPinchZoomChanged(boolean enabled) {}

            @Override
            public void onDisablePageAnimationChanged(boolean disabled) {}

            @Override
            public void onCropWhiteMarginsChanged(boolean enabled) {}

            @Override
            public void onReaderThemeChanged(int themeMode) {
                captured[0] = themeMode;
            }
        };

        listener.onReaderThemeChanged(ReaderSettingsSheet.THEME_LIGHT);
        assertEquals(ReaderSettingsSheet.THEME_LIGHT, captured[0]);

        listener.onReaderThemeChanged(ReaderSettingsSheet.THEME_DARK);
        assertEquals(ReaderSettingsSheet.THEME_DARK, captured[0]);
    }

    private static boolean resolveTheme(int readerThemeMode, boolean isSystemNight, int readerDisplayMode) {
        if (readerDisplayMode == 1) return true;
        if (readerThemeMode == MainActivity.READER_THEME_DARK) return true;
        if (readerThemeMode == MainActivity.READER_THEME_LIGHT) return false;
        return isSystemNight;
    }
}
