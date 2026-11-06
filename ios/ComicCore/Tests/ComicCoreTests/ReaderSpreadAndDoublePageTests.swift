import XCTest
@testable import ComicCore

final class ReaderSpreadAndDoublePageTests: XCTestCase {

    // MARK: - ReaderScalePolicy Tests

    private func g(_ mode: Int, _ iw: Int, _ ih: Int) -> ReaderScalePolicy.Geometry {
        ReaderScalePolicy.geometry(enabled: true, mode: mode, scroll: false,
                                   imageWidth: iw, imageHeight: ih,
                                   viewportWidth: 600, viewportHeight: 900)
    }

    func testCompletePageAndStretchRespectViewport() {
        let fitted = g(ReaderScalePolicy.FIT_SCREEN, 1200, 1200)
        XCTAssertEqual(fitted.width, 600, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 600, accuracy: 0.01)
        XCTAssertEqual(fitted.top, 150, accuracy: 0.01)

        let stretched = g(ReaderScalePolicy.STRETCH, 1200, 1200)
        XCTAssertEqual(stretched.width, 600, accuracy: 0.01)
        XCTAssertEqual(stretched.height, 900, accuracy: 0.01)
        XCTAssertNotEqual(stretched.scaleX, stretched.scaleY, accuracy: 0.01)
    }

    func testOverflowIsPreservedWithoutCroppingAndLongPagesStartAtTop() {
        let width = g(ReaderScalePolicy.FIT_WIDTH, 600, 4000)
        XCTAssertEqual(width.height, 4000, accuracy: 0.01)
        XCTAssertEqual(width.top, 0, accuracy: 0.01)

        let height = g(ReaderScalePolicy.FIT_HEIGHT, 2000, 500)
        XCTAssertEqual(height.width, 3600, accuracy: 0.01)
        XCTAssertEqual(height.left, -1500, accuracy: 0.01)

        let pixels = g(ReaderScalePolicy.ORIGINAL, 1200, 1400)
        XCTAssertEqual(pixels.scaleX, 1.0, accuracy: 0.001)
        XCTAssertEqual(pixels.scaleY, 1.0, accuracy: 0.001)
        XCTAssertEqual(pixels.top, 0, accuracy: 0.01)
    }

    func testSmartUsesBothAspectRatioAndAvailableHeight() {
        XCTAssertEqual(g(ReaderScalePolicy.SMART, 600, 3000).height, 3000, accuracy: 0.01)
        XCTAssertEqual(g(ReaderScalePolicy.SMART, 600, 1000).height, 900, accuracy: 0.01)

        let wide = ReaderScalePolicy.geometry(enabled: true, mode: 0, scroll: false,
                                              imageWidth: 600, imageHeight: 1500,
                                              viewportWidth: 600, viewportHeight: 2400)
        XCTAssertEqual(wide.height, 1500, accuracy: 0.01)
        XCTAssertEqual(wide.width, 600, accuracy: 0.01)
    }

    func testDisabledPreservesLegacyStripAndPagedBehavior() {
        XCTAssertEqual(ReaderScalePolicy.scrollHeight(enabled: false, mode: ReaderScalePolicy.STRETCH,
                                                      iw: 600, ih: 3000, vw: 600, vh: 900), 3000)
        XCTAssertEqual(ReaderScalePolicy.geometry(enabled: false, mode: ReaderScalePolicy.ORIGINAL, scroll: false,
                                                 imageWidth: 600, imageHeight: 3000,
                                                 viewportWidth: 600, viewportHeight: 900).height, 900, accuracy: 0.01)
        XCTAssertEqual(ReaderScalePolicy.scrollHeight(enabled: true, mode: ReaderScalePolicy.FIT_SCREEN,
                                                      iw: 600, ih: 3000, vw: 600, vh: 900), 900)
    }

    func testCorruptSettingsAndDimensionsRemainFinite() {
        XCTAssertEqual(ReaderScalePolicy.normalize(900), ReaderScalePolicy.SMART)
        let bad = ReaderScalePolicy.geometry(enabled: true, mode: -1, scroll: true,
                                             imageWidth: 0, imageHeight: 0,
                                             viewportWidth: 0, viewportHeight: 0)
        XCTAssertEqual(bad.width, 1.0, accuracy: 0.001)
        XCTAssertTrue(bad.scaleX.isFinite)
    }

    func testLabelsAndDescriptions() {
        for mode in 0..<ReaderScalePolicy.COUNT {
            XCTAssertFalse(ReaderScalePolicy.label(mode).isEmpty)
            XCTAssertFalse(ReaderScalePolicy.description(mode).isEmpty)
        }
    }

    // MARK: - DoublePageDetector Tests

    func testNanaPdfAspectIsRecognizedAgainstChapterBaseline() {
        let sample = DoublePageDetector.Sample(width: 595, height: 525)
        let decision = DoublePageDetector.decide(sample: sample, chapterMedian: sample.aspect, index: 5, count: 20)
        XCTAssertTrue(decision.split)
    }

    func testPortraitPageIsNotRecognizedAsDoublePage() {
        let decision = DoublePageDetector.decide(
            sample: DoublePageDetector.Sample(width: 850, height: 1300),
            chapterMedian: 1.133, index: 5, count: 20)
        XCTAssertFalse(decision.split)
    }

    func testVeryWideArtworkDoesNotPassTheConservativeScore() {
        let decision = DoublePageDetector.decide(
            sample: DoublePageDetector.Sample(width: 1600, height: 800),
            chapterMedian: 1.133, index: 5, count: 20)
        XCTAssertFalse(decision.split)
    }

    func testMissingLandscapeBaselineIsNotPositive() {
        let decision = DoublePageDetector.decide(
            sample: DoublePageDetector.Sample(width: 595, height: 525),
            chapterMedian: 0.9, index: 5, count: 20)
        XCTAssertFalse(decision.split)
    }

    func testLandscapeCoverAndBackMatterRemainSplittableInNanaChapter() {
        XCTAssertTrue(DoublePageDetector.decide(sample: DoublePageDetector.Sample(width: 595, height: 525),
                                                chapterMedian: 1.398, index: 0, count: 102).split)
        XCTAssertTrue(DoublePageDetector.decide(sample: DoublePageDetector.Sample(width: 595, height: 559),
                                                chapterMedian: 1.398, index: 101, count: 102).split)
    }

    func testMedianUsesOnlyValidPageDimensions() {
        let pages: [DoublePageDetector.Sample?] = [
            nil,
            DoublePageDetector.Sample(width: 595, height: 425),
            DoublePageDetector.Sample(width: 595, height: 426),
            DoublePageDetector.Sample(width: 0, height: 0)
        ]
        let expected = (595.0 / 425.0 + 595.0 / 426.0) / 2.0
        XCTAssertEqual(DoublePageDetector.median(pages), expected, accuracy: 1e-9)
        XCTAssertEqual(DoublePageDetector.median(nil), 0)
        XCTAssertEqual(DoublePageDetector.median([]), 0)
    }

    func testMeasureThresholds() {
        XCTAssertNil(DoublePageDetector.measure(width: 255, height: 200))
        XCTAssertNil(DoublePageDetector.measure(width: 300, height: 127))
        XCTAssertNotNil(DoublePageDetector.measure(width: 256, height: 128))
    }

    // MARK: - DoublePagePlan Tests

    private func pages() -> [String] { ["a", "b", "c"] }

    func testSplitCreatesTwoVirtualPagesAndKeepsSourceMapping() {
        var automatic = [Int: DoublePagePlan.Decision]()
        automatic[0] = DoublePagePlan.Decision(split: true, score: 0.8, aspect: 1.13)
        let plan = DoublePagePlan(chapterIdentity: "chapter", originals: pages(),
                                  enabled: true, rightFirst: false,
                                  manual: [:], automatic: automatic)

        XCTAssertEqual(plan.units.count, 4)
        XCTAssertEqual(plan.displayForSource(0), 0)
        XCTAssertEqual(plan.displayForSource(1), 2)
        XCTAssertEqual(plan.unit(0)?.source, 0)
        XCTAssertEqual(plan.unit(0)?.leftHalf, true)
        XCTAssertEqual(plan.unit(1)?.leftHalf, false)
        XCTAssertEqual(plan.unit(0)?.pageLabel(), "1左")
        XCTAssertEqual(plan.unit(1)?.pageLabel(), "1右")
    }

    func testRightFirstReversesOnlyTheVirtualOrder() {
        var automatic = [Int: DoublePagePlan.Decision]()
        automatic[0] = DoublePagePlan.Decision(split: true, score: 0.8, aspect: 1.13)
        let plan = DoublePagePlan(chapterIdentity: "chapter", originals: pages(),
                                  enabled: true, rightFirst: true,
                                  manual: [:], automatic: automatic)

        XCTAssertEqual(plan.unit(0)?.leftHalf, false)
        XCTAssertEqual(plan.unit(1)?.leftHalf, true)
        XCTAssertNotEqual(plan.displayKeys[0], plan.displayKeys[1])
    }

    func testManualRulesOverrideAutomaticDecisionAndCanReturnToAutomatic() {
        var automatic = [Int: DoublePagePlan.Decision]()
        automatic[0] = DoublePagePlan.Decision(split: true, score: 0.8, aspect: 1.13)
        var manual = [Int: Int]()
        manual[0] = -1
        let keptWhole = DoublePagePlan(chapterIdentity: "chapter", originals: pages(),
                                       enabled: true, rightFirst: false,
                                       manual: manual, automatic: automatic)
        XCTAssertEqual(keptWhole.units.count, 3)
        XCTAssertEqual(keptWhole.unit(0)?.split, false)

        manual[0] = 1
        let forcedSplit = DoublePagePlan(chapterIdentity: "chapter", originals: pages(),
                                         enabled: true, rightFirst: false,
                                         manual: manual, automatic: [:])
        XCTAssertEqual(forcedSplit.units.count, 4)
        XCTAssertEqual(forcedSplit.unit(0)?.split, true)
    }

    func testSwitchingDetectionAndOrderKeepsOriginalPageAndPhysicalHalf() {
        var manual = [Int: Int]()
        manual[0] = 1
        manual[1] = 1
        manual[2] = 1

        let leftFirst = SpreadPagePlan.fromDoublePagePlan(DoublePagePlan(
            chapterIdentity: "chapter", originals: pages(), enabled: true,
            rightFirst: false, manual: manual, automatic: [:]))
        let right = ReaderPosition(imageIndex: 1, offset: 0.3, atEnd: false)
        XCTAssertEqual(leftFirst.displayForPosition(right, focusX: 0.75), 3)

        let rightFirst = SpreadPagePlan.fromDoublePagePlan(DoublePagePlan(
            chapterIdentity: "chapter", originals: pages(), enabled: true,
            rightFirst: true, manual: manual, automatic: [:]))
        XCTAssertEqual(rightFirst.displayForPosition(right, focusX: 0.75), 2)

        let whole = SpreadPagePlan(chapterIdentity: "chapter", originals: pages(),
                                   enabled: false, manual: [:], automatic: [:])
        XCTAssertEqual(whole.displayForPosition(right, focusX: 0.75), 1)

        manual[0] = -1
        let changed = SpreadPagePlan.fromDoublePagePlan(DoublePagePlan(
            chapterIdentity: "chapter", originals: pages(), enabled: true,
            rightFirst: false, manual: manual, automatic: [:]))
        XCTAssertEqual(changed.displayForPosition(right, focusX: 0.75), 2)
    }

    func testHalfViewportRoundTripsThroughOriginalCoordinates() {
        var manual = [Int: Int]()
        manual[1] = 1
        let plan = SpreadPagePlan.fromDoublePagePlan(DoublePagePlan(
            chapterIdentity: "chapter", originals: pages(), enabled: true,
            rightFirst: false, manual: manual, automatic: [:]))

        for index in [1, 2] {
            guard let unit = plan.unit(index) else {
                XCTFail("Missing unit at \(index)")
                return
            }
            for x in [0.1, 0.5, 0.9] {
                let sourceX = unit.sourceX(x: x, leftFraction: 0.5)
                XCTAssertEqual(x, unit.unitX(source: 1, x: sourceX, leftFraction: 0.5), accuracy: 1e-9)
                let pos = ReaderPosition(imageIndex: 1, offset: 0, atEnd: false)
                XCTAssertEqual(index, plan.displayForPosition(pos, focusX: sourceX))
            }
        }
    }

    func testDisabledSplitReturnsExactOriginalSequenceEvenWithManualRules() {
        var manual = [Int: Int]()
        manual[0] = 1
        let plan = DoublePagePlan(chapterIdentity: "chapter", originals: pages(),
                                  enabled: false, rightFirst: true,
                                  manual: manual, automatic: [:])
        XCTAssertEqual(pages(), plan.displayKeys)
        XCTAssertEqual(plan.unit(0)?.split, false)
    }

    func testPreviousChapterAndLegacyCompletedPositionEnterAtItsLastHalf() {
        var manual = [Int: Int]()
        manual[2] = 1
        for rightFirst in [false, true] {
            let plan = SpreadPagePlan.fromDoublePagePlan(DoublePagePlan(
                chapterIdentity: "chapter", originals: pages(), enabled: true,
                rightFirst: rightFirst, manual: manual, automatic: [:]))
            XCTAssertEqual(3, plan.displayForPosition(ReaderPosition(imageIndex: 2, offset: 0, atEnd: true)))
        }
    }

    func testUnitForKey() {
        var automatic = [Int: DoublePagePlan.Decision]()
        automatic[0] = DoublePagePlan.Decision(split: true, score: 0.8, aspect: 1.13)
        let plan = DoublePagePlan(chapterIdentity: "chapter", originals: pages(),
                                  enabled: true, rightFirst: false,
                                  manual: [:], automatic: automatic)
        XCTAssertNotNil(plan.unitForKey(plan.displayKeys[0]))
        XCTAssertNil(plan.unitForKey("nonexistent"))
        XCTAssertNil(plan.unitForKey(nil))
    }

    // MARK: - DoublePageStateStore Tests

    func testDoublePageStateStoreOperations() throws {
        let suite = "DoublePageStateStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DoublePageStateStore(defaults: defaults)
        let book = "comic_123"
        let revision = "rev_abc"

        XCTAssertFalse(store.enabled(book))
        store.setEnabled(book, enabled: true)
        XCTAssertTrue(store.enabled(book))

        XCTAssertFalse(store.rightFirst(book))
        store.setRightFirst(book, rightFirst: true)
        XCTAssertTrue(store.rightFirst(book))

        // Manual rules
        XCTAssertEqual(try store.manual(book: book, revision: revision), [:])
        try store.setManual(book: book, revision: revision, index: 2, mode: 1)
        try store.setManual(book: book, revision: revision, index: 4, mode: -1)
        XCTAssertEqual(try store.manual(book: book, revision: revision), [2: 1, 4: -1])

        // Remove rule
        try store.setManual(book: book, revision: revision, index: 2, mode: nil)
        XCTAssertEqual(try store.manual(book: book, revision: revision), [4: -1])

        // Invalid manual input
        XCTAssertThrowsError(try store.setManual(book: book, revision: revision, index: -1, mode: 1))
        XCTAssertThrowsError(try store.setManual(book: book, revision: revision, index: 0, mode: 0))

        // Automatic decisions
        XCTAssertFalse(store.complete(book: book, revision: revision))
        let decisions: [Int: DoublePagePlan.Decision] = [
            1: DoublePagePlan.Decision(split: true, score: 0.85, aspect: 1.3),
            3: DoublePagePlan.Decision(split: false, score: 0.2, aspect: 0.9)
        ]
        store.saveAutomatic(book: book, revision: revision, decisions: decisions, complete: true)
        XCTAssertTrue(store.complete(book: book, revision: revision))

        let loaded = store.automatic(book: book, revision: revision)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[1]?.split, true)
        XCTAssertEqual(loaded[1]?.score ?? 0, 0.85, accuracy: 1e-4)
        XCTAssertEqual(loaded[3]?.split, false)

        store.retry(book: book, revision: revision)
        XCTAssertFalse(store.complete(book: book, revision: revision))

        // Clear manual
        store.clearManual(book: book)
        XCTAssertEqual(try store.manual(book: book, revision: revision), [:])
    }

    // MARK: - SpreadPagePlan Tests

    private func spreadPages() -> [String] { ["a", "b", "c", "d", "e", "f"] }

    func testOriginalsRemainReachableExactlyOnceAndSeekUsesOriginalIndices() {
        var automatic = [Int: SpreadPagePlan.Decision]()
        automatic[1] = SpreadPagePlan.Decision(firstOnLeft: true, score: 0.9)
        let plan = SpreadPagePlan(chapterIdentity: "chapter", originals: spreadPages(),
                                  enabled: true, manual: [:], automatic: automatic)
        XCTAssertEqual(spreadPages(), plan.originals)
        XCTAssertEqual(plan.units.count, 5)
        XCTAssertEqual(plan.displayForSource(1), 1)
        XCTAssertEqual(plan.displayForSource(2), 1)
        XCTAssertEqual(plan.displayForSource(3), 2)

        var covered = [Int]()
        for u in plan.units {
            for i in u.first...u.last {
                covered.append(i)
            }
        }
        XCTAssertEqual([0, 1, 2, 3, 4, 5], covered)
        XCTAssertEqual(plan.units[1].pageLabel(), "2–3")
    }

    func testDisabledFeatureRestoresOriginalPagesWithoutChangingRules() {
        var manual = [Int: Int]()
        manual[2] = -1
        let plan = SpreadPagePlan(chapterIdentity: "chapter", originals: spreadPages(),
                                  enabled: false, manual: manual, automatic: [:])
        XCTAssertEqual(spreadPages(), plan.displayKeys)
        XCTAssertEqual(manual[2], -1)
    }

    func testSplitVetoesAutomaticNeighborsAndManualOrderWins() {
        var manual = [Int: Int]()
        manual[2] = 0
        manual[4] = -1
        var automatic = [Int: SpreadPagePlan.Decision]()
        automatic[1] = SpreadPagePlan.Decision(firstOnLeft: true, score: 0.9)
        automatic[2] = SpreadPagePlan.Decision(firstOnLeft: true, score: 0.9)
        automatic[3] = SpreadPagePlan.Decision(firstOnLeft: true, score: 0.9)
        automatic[4] = SpreadPagePlan.Decision(firstOnLeft: true, score: 0.9)

        let plan = SpreadPagePlan(chapterIdentity: "chapter", originals: spreadPages(),
                                  enabled: true, manual: manual, automatic: automatic)
        XCTAssertEqual(plan.units.count, 5)
        XCTAssertFalse(plan.unit(1)?.isSpread ?? true)
        XCTAssertFalse(plan.unit(2)?.isSpread ?? true)
        XCTAssertTrue(plan.unit(4)?.isSpread ?? false)
        XCTAssertFalse(plan.unit(4)?.firstOnLeft ?? true)
    }

    func testAmbiguousOverlappingPairsRemainSingles() {
        var automatic = [Int: SpreadPagePlan.Decision]()
        automatic[1] = SpreadPagePlan.Decision(firstOnLeft: true, score: 0.9)
        automatic[2] = SpreadPagePlan.Decision(firstOnLeft: true, score: 0.86)
        let plan = SpreadPagePlan(chapterIdentity: "chapter", originals: spreadPages(),
                                  enabled: true, manual: [:], automatic: automatic)
        XCTAssertEqual(plan.units.count, 6)
    }

    func testViewportMappingRoundTripsUnequalWidthAndReverseOrder() {
        var manual = [Int: Int]()
        manual[1] = -1
        guard let unit = SpreadPagePlan(chapterIdentity: "chapter", originals: spreadPages(),
                                        enabled: true, manual: manual, automatic: [:]).unit(1) else {
            XCTFail("Missing unit at 1")
            return
        }
        for source in [1, 2] {
            for x in [0.1, 0.4, 0.9] {
                let joint = unit.unitX(source: source, x: x, leftFraction: 0.47)
                XCTAssertEqual(source, unit.sourceAt(x: joint, leftFraction: 0.47))
                XCTAssertEqual(x, unit.sourceX(x: joint, leftFraction: 0.47), accuracy: 1e-9)
            }
        }
    }

    func testContentRevisionAndSpatialOrderSeparateCompositeCacheKeys() {
        var a = [Int: Int]()
        var b = [Int: Int]()
        a[1] = 1
        b[1] = -1
        let x = SpreadPagePlan(chapterIdentity: "chapter", originals: spreadPages(),
                               enabled: true, manual: a, automatic: [:])
        let y = SpreadPagePlan(chapterIdentity: "chapter", originals: spreadPages(),
                               enabled: true, manual: b, automatic: [:])
        XCTAssertNotEqual(x.unit(1)?.key, y.unit(1)?.key)
        XCTAssertNotEqual(x.revision,
                          SpreadPagePlan(chapterIdentity: "changed", originals: spreadPages(),
                                         enabled: true, manual: a, automatic: [:]).revision)
    }

    // MARK: - SpreadStateStore Tests

    func testSpreadStateStoreOperations() throws {
        let suite = "SpreadStateStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SpreadStateStore(defaults: defaults)
        let book = "comic_456"
        let revision = "rev_def"

        XCTAssertFalse(store.enabled(book))
        store.setEnabled(book, enabled: true)
        XCTAssertTrue(store.enabled(book))

        // Manual rules
        XCTAssertEqual(try store.manual(book: book, revision: revision), [:])
        try store.setManual(book: book, revision: revision, index: 1, direction: 1)
        XCTAssertEqual(try store.manual(book: book, revision: revision), [1: 1])

        // Neighbor blocking: cannot join adjacent index while page 1 has a pair
        XCTAssertThrowsError(try store.setManual(book: book, revision: revision, index: 2, direction: 1))
        XCTAssertThrowsError(try store.setManual(book: book, revision: revision, index: 0, direction: 1))

        // Clear rule
        try store.setManual(book: book, revision: revision, index: 1, direction: nil)
        XCTAssertEqual(try store.manual(book: book, revision: revision), [:])

        // Automatic decisions
        XCTAssertFalse(store.complete(book: book, revision: revision))
        let decisions: [Int: SpreadPagePlan.Decision] = [
            2: SpreadPagePlan.Decision(firstOnLeft: true, score: 0.92)
        ]
        store.saveAutomatic(book: book, revision: revision, decisions: decisions, complete: true)
        XCTAssertTrue(store.complete(book: book, revision: revision))

        let loaded = store.automatic(book: book, revision: revision)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[2]?.firstOnLeft, true)
        XCTAssertEqual(loaded[2]?.score ?? 0, 0.92, accuracy: 1e-4)

        store.retry(book: book, revision: revision)
        XCTAssertFalse(store.complete(book: book, revision: revision))

        // Clear manual
        try store.setManual(book: book, revision: revision, index: 3, direction: -1)
        store.clearManual(book: book)
        XCTAssertEqual(try store.manual(book: book, revision: revision), [:])
    }

    // MARK: - SpreadDetector Tests (Synthetic Fixtures)

    private struct SyntheticPixels: SpreadDetectorPixels {
        let width: Int
        let height: Int
        let generator: (Int, Int) -> UInt32

        func argb(x: Int, y: Int) -> UInt32 {
            generator(x, y)
        }
    }

    func testSyntheticMatchingSpreadFindsSpatialOrder() {
        let w = 600
        let h = 900

        // Seam wave across Y: provides strong local variance (> 20) across all 8 regions
        func seamWave(y: Int) -> UInt32 {
            let wave = sin(Double(y) * 0.15) * 80.0 + cos(Double(y) * 0.05) * 30.0 + 128.0
            let grey = UInt32(max(0, min(255, Int(wave))))
            return 0xff000000 | (grey << 16) | (grey << 8) | grey
        }

        // Page 1: right edge (x >= 550) has seamWave; rest is dark (grey = 16)
        let page1Pixels = SyntheticPixels(width: w, height: h) { x, y in
            if x >= 550 {
                return seamWave(y: y)
            }
            return 0xff101010
        }

        // Page 2: left edge (x <= 50) has identical seamWave; rest is light (grey = 224)
        let page2Pixels = SyntheticPixels(width: w, height: h) { x, y in
            if x <= 50 {
                return seamWave(y: y)
            }
            return 0xffe0e0e0
        }

        guard let page1 = SpreadDetector.Sample.read(page1Pixels),
              let page2 = SpreadDetector.Sample.read(page2Pixels) else {
            XCTFail("Failed to read synthetic samples")
            return
        }

        // Forward detect: page 1 right matches page 2 left
        let forward = SpreadDetector.detect(page1, page2)
        XCTAssertTrue(forward.merge, "forward score=\(forward.forward.score) matches=\(forward.forward.matchingRegions)")
        XCTAssertTrue(forward.firstOnLeft)

        // Reverse detect: page 2 on left, page 1 on right -> should detect reverse orientation
        let reversed = SpreadDetector.detect(page2, page1)
        XCTAssertTrue(reversed.merge)
        XCTAssertFalse(reversed.firstOnLeft)
    }

    func testMissingAndDuplicatePagesAreNeverPositive() {
        let blankPixels = SyntheticPixels(width: 600, height: 900) { _, _ in 0xffffffff }
        guard let page = SpreadDetector.Sample.read(blankPixels) else {
            XCTFail("Failed to read sample")
            return
        }

        XCTAssertFalse(SpreadDetector.detect(nil, page).merge)
        XCTAssertFalse(SpreadDetector.detect(page, nil).merge)
        XCTAssertFalse(SpreadDetector.detect(page, page).merge)
    }

    func testBlankPagesAreNotPositive() {
        let blank = SyntheticPixels(width: 850, height: 1300) { _, _ in 0xffffffff }
        guard let sample = SpreadDetector.Sample.read(blank) else {
            XCTFail("Failed to read blank sample")
            return
        }
        XCTAssertFalse(SpreadDetector.detect(sample, sample).merge)
    }

    func testSmallPagesReturnNilSample() {
        let small = SyntheticPixels(width: 20, height: 20) { _, _ in 0xffffffff }
        XCTAssertNil(SpreadDetector.Sample.read(small))
    }

    func testAspectMismatchBlocksDetection() {
        let portrait1 = SyntheticPixels(width: 600, height: 900) { _, _ in 0xff101010 } // aspect 0.667
        let portrait2 = SyntheticPixels(width: 400, height: 900) { _, _ in 0xff202020 } // aspect 0.444 (diff 0.22 > 0.18)
        guard let p1 = SpreadDetector.Sample.read(portrait1),
              let p2 = SpreadDetector.Sample.read(portrait2) else {
            XCTFail("Failed to read samples")
            return
        }
        XCTAssertFalse(SpreadDetector.detect(p1, p2).merge)
    }
}
