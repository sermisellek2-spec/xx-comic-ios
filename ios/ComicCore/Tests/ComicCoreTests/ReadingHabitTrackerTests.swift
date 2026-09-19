import XCTest
@testable import ComicCore

final class ReadingHabitTrackerTests: XCTestCase {
    private final class TestClock {
        var monotonic: TimeInterval = 1
        var wall: TimeInterval = 1_726_750_000

        func advance(_ seconds: TimeInterval) {
            monotonic += seconds
            wall += seconds
        }

        var clocks: ReadingHabitTracker.Clocks {
            .init(monotonic: { self.monotonic }, wall: { self.wall })
        }
    }

    private func tracker(_ clock: TestClock) -> ReadingHabitTracker {
        ReadingHabitTracker(clocks: clock.clocks)
    }

    func testPreferenceRequiresFiveRecentSamplesAndKeepsPreviousBelowThreshold() {
        let now: TimeInterval = 1_726_750_000
        let fourLocal = (0..<4).map { ReadingHabitTracker.Sample(timestamp: now - Double($0), isLocal: true) }
        XCTAssertEqual(ReadingHabitTracker.evaluatePreference(fourLocal, previous: .none, now: now), .none)

        let sixLocal = (0..<6).map { ReadingHabitTracker.Sample(timestamp: now - Double($0), isLocal: true) }
        let fourOnline = (6..<10).map { ReadingHabitTracker.Sample(timestamp: now - Double($0), isLocal: false) }
        XCTAssertEqual(ReadingHabitTracker.evaluatePreference(sixLocal + fourOnline, previous: .my, now: now), .my)
    }

    func testPreferenceUsesLatestTenWithinThirtyDaysAndSeventyPercentThreshold() {
        let now: TimeInterval = 1_726_750_000
        let recentLocal = (0..<7).map { ReadingHabitTracker.Sample(timestamp: now - Double($0), isLocal: true) }
        let recentOnline = (7..<10).map { ReadingHabitTracker.Sample(timestamp: now - Double($0), isLocal: false) }
        let olderOnline = (20..<25).map { ReadingHabitTracker.Sample(timestamp: now - Double($0), isLocal: false) }
        XCTAssertEqual(ReadingHabitTracker.evaluatePreference(recentLocal + recentOnline + olderOnline, previous: .my, now: now), .local)

        let expired = (0..<5).map { _ in ReadingHabitTracker.Sample(timestamp: now - 31 * 24 * 60 * 60, isLocal: true) }
        XCTAssertEqual(ReadingHabitTracker.evaluatePreference(expired, previous: .my, now: now), .my)
    }

    func testLaunchTabResolutionHonorsFixedModeLearnedPreferenceAndManualFallback() {
        XCTAssertEqual(ReadingHabitTracker.resolveLaunchTab(mode: .my, learned: .local, lastManualTab: 1), 0)
        XCTAssertEqual(ReadingHabitTracker.resolveLaunchTab(mode: .local, learned: .my, lastManualTab: 0), 1)
        XCTAssertEqual(ReadingHabitTracker.resolveLaunchTab(mode: .automatic, learned: .local, lastManualTab: 0), 1)
        XCTAssertEqual(ReadingHabitTracker.resolveLaunchTab(mode: .automatic, learned: .none, lastManualTab: 1), 1)
        XCTAssertEqual(ReadingHabitTracker.autoSubtitle(learned: .none, effectiveTab: 0), "学习中 · 启动显示我的书架")
    }

    func testReadableTimeAndUserActionAreBothRequiredAndSessionVotesOnce() {
        let clock = TestClock(), subject = tracker(clock)
        subject.enterReader(comicID: "local-1", isLocal: true)
        clock.advance(70); subject.tick()
        XCTAssertTrue(subject.samples.isEmpty)

        subject.contentBecameReadable()
        clock.advance(10); subject.userDidRead()
        clock.advance(49); subject.tick()
        XCTAssertTrue(subject.samples.isEmpty)
        clock.advance(1); subject.tick()
        XCTAssertEqual(subject.samples.map(\.isLocal), [true])

        clock.advance(70); subject.userDidRead(); subject.tick()
        XCTAssertEqual(subject.samples.count, 1)
    }

    func testUnreadableAndIdlePeriodsDoNotAccumulate() {
        let clock = TestClock(), subject = tracker(clock)
        subject.enterReader(comicID: "comic", isLocal: false)
        clock.advance(70); subject.userDidRead(); subject.tick()
        XCTAssertTrue(subject.samples.isEmpty)

        subject.contentBecameReadable(); subject.userDidRead()
        clock.advance(180); subject.tick()
        XCTAssertEqual(subject.currentSession?.accumulatedReadingTime, 120)
        clock.advance(30); subject.tick()
        XCTAssertEqual(subject.currentSession?.accumulatedReadingTime, 120)
    }

    func testOverlayPausesReadingTime() {
        let clock = TestClock(), subject = tracker(clock)
        subject.enterReader(comicID: "comic", isLocal: true)
        subject.contentBecameReadable(); subject.userDidRead()
        clock.advance(30); subject.tick()
        subject.overlayVisibilityChanged(isVisible: true)
        clock.advance(60); subject.tick()
        XCTAssertTrue(subject.samples.isEmpty)
        subject.overlayVisibilityChanged(isVisible: false)
        clock.advance(31); subject.tick()
        XCTAssertEqual(subject.samples.count, 1)
    }

    func testBriefBackgroundContinuesButLongBackgroundStartsFreshSession() {
        let clock = TestClock(), subject = tracker(clock)
        subject.enterReader(comicID: "comic", isLocal: true)
        subject.contentBecameReadable(); subject.userDidRead()
        clock.advance(40); subject.tick()
        subject.appDidEnterBackground(); clock.advance(300); subject.appWillEnterForeground()
        clock.advance(21); subject.tick()
        XCTAssertEqual(subject.samples.count, 1)

        subject.exitReader()
        subject.enterReader(comicID: "other", isLocal: false)
        subject.contentBecameReadable(); subject.userDidRead()
        clock.advance(40); subject.tick()
        subject.appDidEnterBackground(); clock.advance(360); subject.appWillEnterForeground()
        clock.advance(30); subject.tick()
        XCTAssertEqual(subject.samples.count, 1)
        clock.advance(35); subject.userDidRead(); subject.tick()
        XCTAssertEqual(subject.samples.map(\.isLocal), [true, false])
    }

    func testSameBookReentryKeepsSessionButChangingBookStartsAnotherVote() {
        let clock = TestClock(), subject = tracker(clock)
        subject.enterReader(comicID: "same", isLocal: true)
        subject.contentBecameReadable(); subject.userDidRead()
        clock.advance(61); subject.tick()
        subject.enterReader(comicID: "same", isLocal: true)
        clock.advance(61); subject.userDidRead(); subject.tick()
        XCTAssertEqual(subject.samples.count, 1)

        subject.enterReader(comicID: "different", isLocal: false)
        subject.contentBecameReadable(); subject.userDidRead()
        clock.advance(61); subject.tick()
        XCTAssertEqual(subject.samples.map(\.isLocal), [true, false])
    }

    func testFixedModeDoesNotLearnAndResetPreservesManualTab() {
        let clock = TestClock(), subject = tracker(clock)
        subject.launchMode = .my
        subject.enterReader(comicID: "comic", isLocal: true)
        subject.contentBecameReadable(); subject.userDidRead()
        clock.advance(70); subject.tick()
        XCTAssertTrue(subject.samples.isEmpty)

        subject.launchMode = .automatic
        for index in 0..<5 {
            subject.enterReader(comicID: "local-\(index)", isLocal: true)
            subject.contentBecameReadable(); subject.userDidRead()
            clock.advance(61); subject.tick(); subject.exitReader()
        }
        XCTAssertEqual(subject.learnedPreference, .local)
        subject.lastManualTab = 1
        subject.resetHabit()
        XCTAssertTrue(subject.samples.isEmpty)
        XCTAssertEqual(subject.learnedPreference, .none)
        XCTAssertEqual(subject.lastManualTab, 1)
    }

    func testStateRoundTripsThroughUserDefaults() throws {
        let suite = "ReadingHabitTrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock(), subject = tracker(clock)
        subject.lastManualTab = 1
        subject.enterReader(comicID: "comic", isLocal: true)
        subject.contentBecameReadable(); subject.userDidRead()
        clock.advance(61); subject.tick()
        subject.save(to: defaults)

        let restored = tracker(clock)
        restored.restore(from: defaults)
        XCTAssertEqual(restored.launchMode, .automatic)
        XCTAssertEqual(restored.lastManualTab, 1)
        XCTAssertEqual(restored.samples.map(\.isLocal), [true])
    }

    func testRestoringPersistedStateDoesNotPublishPartialChanges() throws {
        let suite = "ReadingHabitTrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "habit.lastManualBookshelfTab")
        let clock = TestClock(), subject = tracker(clock)
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.restore(from: defaults)

        XCTAssertEqual(subject.lastManualTab, 1)
        XCTAssertEqual(changes, 0)
    }
}
