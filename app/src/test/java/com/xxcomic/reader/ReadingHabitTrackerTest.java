package com.xxcomic.reader;

import org.junit.Before;
import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.Assert.*;

public class ReadingHabitTrackerTest {

    private static class TestTimeProvider implements ReadingHabitTracker.TimeProvider {
        long elapsed = 1000L;
        long wallClock = 1726750000000L;

        @Override
        public long elapsedRealtime() {
            return elapsed;
        }

        @Override
        public long currentTimeMillis() {
            return wallClock;
        }

        void advance(long ms) {
            elapsed += ms;
            wallClock += ms;
        }
    }

    private TestTimeProvider time;
    private ReadingHabitTracker tracker;

    @Before
    public void setUp() {
        time = new TestTimeProvider();
        tracker = new ReadingHabitTracker(time);
    }

    // --- Pure Algorithm Tests ---

    @Test
    public void testFewerThanFiveSamplesDoesNotDecide() {
        List<ReadingHabitTracker.Sample> list = new ArrayList<>();
        list.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        list.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        list.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        list.add(new ReadingHabitTracker.Sample(time.wallClock, true));

        int result = ReadingHabitTracker.evaluatePreference(list, ReadingHabitTracker.PREF_NONE, time.wallClock);
        assertEquals(ReadingHabitTracker.PREF_NONE, result);
    }

    @Test
    public void testFourOutOfFiveLocalSwitchesToLocal() {
        List<ReadingHabitTracker.Sample> list = new ArrayList<>();
        list.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        list.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        list.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        list.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        list.add(new ReadingHabitTracker.Sample(time.wallClock, false)); // 4 local, 1 online (80% >= 70%)

        int result = ReadingHabitTracker.evaluatePreference(list, ReadingHabitTracker.PREF_NONE, time.wallClock);
        assertEquals(ReadingHabitTracker.PREF_LOCAL, result);
    }

    @Test
    public void testSixOutOfTenMaintainsPrevious() {
        List<ReadingHabitTracker.Sample> list = new ArrayList<>();
        for (int i = 0; i < 6; i++) list.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        for (int i = 0; i < 4; i++) list.add(new ReadingHabitTracker.Sample(time.wallClock, false)); // 60% < 70%

        int result = ReadingHabitTracker.evaluatePreference(list, ReadingHabitTracker.PREF_MY, time.wallClock);
        assertEquals(ReadingHabitTracker.PREF_MY, result);
    }

    @Test
    public void testSevenOutOfTenSwitches() {
        List<ReadingHabitTracker.Sample> localMajority = new ArrayList<>();
        for (int i = 0; i < 7; i++) localMajority.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        for (int i = 0; i < 3; i++) localMajority.add(new ReadingHabitTracker.Sample(time.wallClock, false));
        assertEquals(ReadingHabitTracker.PREF_LOCAL, ReadingHabitTracker.evaluatePreference(localMajority, ReadingHabitTracker.PREF_MY, time.wallClock));

        List<ReadingHabitTracker.Sample> onlineMajority = new ArrayList<>();
        for (int i = 0; i < 3; i++) onlineMajority.add(new ReadingHabitTracker.Sample(time.wallClock, true));
        for (int i = 0; i < 7; i++) onlineMajority.add(new ReadingHabitTracker.Sample(time.wallClock, false));
        assertEquals(ReadingHabitTracker.PREF_MY, ReadingHabitTracker.evaluatePreference(onlineMajority, ReadingHabitTracker.PREF_LOCAL, time.wallClock));
    }

    @Test
    public void testThirtyDaysExpiry() {
        List<ReadingHabitTracker.Sample> list = new ArrayList<>();
        long thirtyOneDaysAgo = time.wallClock - (31L * 24 * 60 * 60 * 1000L);
        for (int i = 0; i < 5; i++) {
            list.add(new ReadingHabitTracker.Sample(thirtyOneDaysAgo, true)); // expired
        }
        int result = ReadingHabitTracker.evaluatePreference(list, ReadingHabitTracker.PREF_NONE, time.wallClock);
        assertEquals(ReadingHabitTracker.PREF_NONE, result); // all expired, fewer than 5 valid
    }

    @Test
    public void testLatestTenSamplesTruncation() {
        List<ReadingHabitTracker.Sample> list = new ArrayList<>();
        // 10 recent local samples
        for (int i = 0; i < 10; i++) {
            list.add(new ReadingHabitTracker.Sample(time.wallClock - i * 1000L, true));
        }
        // 5 older online samples
        for (int i = 0; i < 5; i++) {
            list.add(new ReadingHabitTracker.Sample(time.wallClock - (20 + i) * 1000L, false));
        }
        // Only latest 10 (which are all local) should count
        int result = ReadingHabitTracker.evaluatePreference(list, ReadingHabitTracker.PREF_NONE, time.wallClock);
        assertEquals(ReadingHabitTracker.PREF_LOCAL, result);
    }

    @Test
    public void testResolveLaunchTabPriority() {
        // Manual fixed modes always win
        assertEquals(0, ReadingHabitTracker.resolveLaunchTab(ReadingHabitTracker.LAUNCH_MODE_MY, ReadingHabitTracker.PREF_LOCAL, 1));
        assertEquals(1, ReadingHabitTracker.resolveLaunchTab(ReadingHabitTracker.LAUNCH_MODE_LOCAL, ReadingHabitTracker.PREF_MY, 0));

        // Auto mode follows learned preference
        assertEquals(1, ReadingHabitTracker.resolveLaunchTab(ReadingHabitTracker.LAUNCH_MODE_AUTO, ReadingHabitTracker.PREF_LOCAL, 0));
        assertEquals(0, ReadingHabitTracker.resolveLaunchTab(ReadingHabitTracker.LAUNCH_MODE_AUTO, ReadingHabitTracker.PREF_MY, 1));

        // Auto mode when learning follows last manual tab (or default 0)
        assertEquals(1, ReadingHabitTracker.resolveLaunchTab(ReadingHabitTracker.LAUNCH_MODE_AUTO, ReadingHabitTracker.PREF_NONE, 1));
        assertEquals(0, ReadingHabitTracker.resolveLaunchTab(ReadingHabitTracker.LAUNCH_MODE_AUTO, ReadingHabitTracker.PREF_NONE, 0));
    }

    // --- Session Lifecycle Tests ---

    @Test
    public void testStayWithoutInteractionDoesNotVote() {
        tracker.onEnterReader("comic_1", true);
        tracker.onContentReadable();
        time.advance(70_000L); // 70s passed, but no user action
        tracker.tick();

        assertTrue(tracker.getSamples().isEmpty());
    }

    @Test
    public void testUnreadableDoesNotAccumulateTime() {
        tracker.onEnterReader("comic_1", true);
        // onContentReadable not called (e.g. loading or error)
        time.advance(70_000L);
        tracker.onUserAction();
        tracker.tick();

        assertTrue(tracker.getSamples().isEmpty());
    }

    @Test
    public void testFiftyNineSecondsDoesNotVote() {
        tracker.onEnterReader("comic_1", true);
        tracker.onContentReadable();
        time.advance(10_000L);
        tracker.onUserAction();
        time.advance(49_000L); // total 59s
        tracker.tick();

        assertTrue(tracker.getSamples().isEmpty());
    }

    @Test
    public void testSixtySecondsWithInteractionVotesOnce() {
        final boolean[] updated = {false};
        tracker.setListener(t -> updated[0] = true);

        tracker.onEnterReader("comic_1", true);
        tracker.onContentReadable();
        time.advance(10_000L);
        tracker.onUserAction();
        time.advance(51_000L); // total 61s
        tracker.tick();

        assertEquals(1, tracker.getSamples().size());
        assertTrue(tracker.getSamples().get(0).isLocal);
        assertTrue(updated[0]);

        // Staying longer in the same session does not vote a second time
        updated[0] = false;
        time.advance(60_000L);
        tracker.onUserAction();
        tracker.tick();
        assertEquals(1, tracker.getSamples().size());
        assertFalse(updated[0]);
    }

    @Test
    public void testOverlayPausesAccumulation() {
        tracker.onEnterReader("comic_1", true);
        tracker.onContentReadable();
        tracker.onUserAction();
        time.advance(30_000L); // 30s
        tracker.tick();

        tracker.onOverlayVisibilityChanged(true); // menu/drawer opened
        time.advance(60_000L); // 60s in drawer
        tracker.tick();
        assertTrue(tracker.getSamples().isEmpty()); // paused, not counted

        tracker.onOverlayVisibilityChanged(false); // drawer closed
        time.advance(31_000L); // 30s + 31s = 61s reading time
        tracker.tick();

        assertEquals(1, tracker.getSamples().size());
    }

    @Test
    public void testBriefBackgroundResumesSameSession() {
        tracker.onEnterReader("comic_1", true);
        tracker.onContentReadable();
        tracker.onUserAction();
        time.advance(40_000L); // 40s
        tracker.tick();

        tracker.onAppBackground();
        time.advance(120_000L); // 2 minutes background (<= 5 min)
        tracker.onAppForeground();

        time.advance(21_000L); // +21s -> total 61s
        tracker.tick();

        assertEquals(1, tracker.getSamples().size());
    }

    @Test
    public void testMoreThanFiveMinutesBackgroundStartsNewSession() {
        tracker.onEnterReader("comic_1", true);
        tracker.onContentReadable();
        tracker.onUserAction();
        time.advance(40_000L); // 40s
        tracker.tick();

        tracker.onAppBackground();
        time.advance(360_000L); // 6 minutes in background (> 5 min)
        tracker.onAppForeground();

        // Previous session discarded without vote; new session requires 60s
        time.advance(30_000L);
        tracker.tick();
        assertTrue(tracker.getSamples().isEmpty());

        time.advance(35_000L); // total 65s in new session
        tracker.onUserAction();
        tracker.tick();
        assertEquals(1, tracker.getSamples().size());
    }

    @Test
    public void testManualFixedModeDoesNotAddSamples() {
        tracker.setLaunchMode(ReadingHabitTracker.LAUNCH_MODE_MY); // fixed manual mode

        tracker.onEnterReader("comic_1", true);
        tracker.onContentReadable();
        tracker.onUserAction();
        time.advance(70_000L);
        tracker.tick();

        assertTrue(tracker.getSamples().isEmpty()); // no samples added in fixed mode
    }

    @Test
    public void testResetHabitClearsSamplesAndLearnedPreference() {
        // Record 5 samples
        for (int i = 0; i < 5; i++) {
            tracker.onEnterReader("comic_" + i, true);
            tracker.onContentReadable();
            tracker.onUserAction();
            time.advance(65_000L);
            tracker.tick();
            tracker.onExitReader();
        }
        assertEquals(5, tracker.getSamples().size());
        assertEquals(ReadingHabitTracker.PREF_LOCAL, tracker.getLearnedPreference());

        tracker.setLastManualTab(1);
        tracker.resetHabit();

        assertTrue(tracker.getSamples().isEmpty());
        assertEquals(ReadingHabitTracker.PREF_NONE, tracker.getLearnedPreference());
        assertEquals(1, tracker.getLastManualTab()); // preserved manual choice
    }

    @Test
    public void testSerializationAndRestoration() {
        for (int i = 0; i < 3; i++) {
            tracker.onEnterReader("comic_" + i, i % 2 == 0);
            tracker.onContentReadable();
            tracker.onUserAction();
            time.advance(65_000L);
            tracker.tick();
            tracker.onExitReader();
        }
        String json = tracker.serializeSamples();
        assertNotNull(json);

        ReadingHabitTracker restored = new ReadingHabitTracker(time);
        restored.restoreState(ReadingHabitTracker.LAUNCH_MODE_AUTO, 1, ReadingHabitTracker.PREF_NONE, json);

        assertEquals(3, restored.getSamples().size());
        assertEquals(1, restored.getLastManualTab());
        assertEquals(ReadingHabitTracker.LAUNCH_MODE_AUTO, restored.getLaunchMode());
    }
}
