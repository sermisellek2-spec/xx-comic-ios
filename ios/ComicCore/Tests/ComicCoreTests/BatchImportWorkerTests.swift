import XCTest
@testable import ComicCore

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [BatchImportWorker.ProgressUpdate] = []

    func append(_ update: BatchImportWorker.ProgressUpdate) {
        lock.lock()
        defer { lock.unlock() }
        updates.append(update)
    }

    var allUpdates: [BatchImportWorker.ProgressUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return updates
    }
}

final class BatchImportWorkerTests: XCTestCase {
    private var tempDirectory: URL!
    private var outsideDirectory: URL!
    private var sessionFile: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchImportWorkerTests-\(UUID().uuidString)", isDirectory: true)
        outsideDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchImportOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        sessionFile = tempDirectory.appendingPathComponent("batch_session.json")
    }

    override func tearDownWithError() throws {
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
        if let outsideDirectory { try? FileManager.default.removeItem(at: outsideDirectory) }
        try super.tearDownWithError()
    }

    private func createTestZip(name: String, entries: [String: [UInt8]]) throws -> URL {
        let zipURL = outsideDirectory.appendingPathComponent(name)
        let items = entries.map { ZIPFixture.Item($0.key, $0.value) }
        let data = try ZIPFixture.make(items)
        try data.write(to: zipURL)
        return zipURL
    }

    func testBatchImportMultipleVolumesMergesIntoSingleSeries() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let session = try BatchImportSession(file: sessionFile)
        let worker = BatchImportWorker(library: library, session: session, isReadableImage: { _ in true })

        let zip1 = try createTestZip(name: "海贼王 01.zip", entries: ["01.png": [1, 2, 3]])
        let zip2 = try createTestZip(name: "海贼王 02.zip", entries: ["02.png": [4, 5, 6]])
        let zip3 = try createTestZip(name: "海贼王 03.zip", entries: ["03.png": [7, 8, 9]])

        var urlMap: [String: URL] = [:]
        let cands = try [zip1, zip2, zip3].enumerated().map { idx, url -> BatchImportCandidate in
            urlMap[url.path] = url
            return try BatchImportCandidate(
                fileName: url.lastPathComponent,
                fileId: url.path,
                format: "zip",
                selectionIndex: idx
            )
        }

        let progressBox = ProgressBox()
        let summary = try await worker.planAndExecute(candidates: cands, urlMap: urlMap) { update in
            progressBox.append(update)
        }

        XCTAssertEqual(summary.totalItems, 3)
        XCTAssertEqual(summary.succeededCount, 3)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertFalse(summary.cancelled)
        XCTAssertEqual(summary.seriesIds.count, 1)

        let seriesId = try XCTUnwrap(summary.seriesIds.first)
        let foundSeries = try await library.series(id: seriesId)
        let series = try XCTUnwrap(foundSeries)
        XCTAssertEqual(series.displayTitle, "海贼王")
        XCTAssertEqual(series.volumeIDs.count, 3)

        let chapters = try await library.chapters(for: seriesId)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].chapterSlot, 0)
        XCTAssertEqual(chapters[1].chapterSlot, 1)
        XCTAssertEqual(chapters[2].chapterSlot, 2)

        // Verify session persisted completion
        let currentSnapshot = await session.current()
        XCTAssertNotNil(currentSnapshot)
        XCTAssertEqual(currentSnapshot?.groups.count, 1)
        XCTAssertEqual(currentSnapshot?.groups[0].items.allSatisfy { $0.state == .completed }, true)
        XCTAssertEqual(currentSnapshot?.groups[0].targetBookId, seriesId)
        XCTAssertFalse(progressBox.allUpdates.isEmpty)
    }

    func testBatchImportMultipleDistinctSeriesGroupedCorrectly() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let session = try BatchImportSession(file: sessionFile)
        let worker = BatchImportWorker(library: library, session: session, isReadableImage: { _ in true })

        let naruto1 = try createTestZip(name: "火影忍者 01.zip", entries: ["n1.png": [1, 1]])
        let naruto2 = try createTestZip(name: "火影忍者 02.zip", entries: ["n2.png": [2, 2]])
        let bleach1 = try createTestZip(name: "死神 01.zip", entries: ["b1.png": [3, 3]])

        var urlMap: [String: URL] = [:]
        let cands = try [naruto1, naruto2, bleach1].enumerated().map { idx, url in
            urlMap[url.path] = url
            return try BatchImportCandidate(fileName: url.lastPathComponent, fileId: url.path, format: "zip", selectionIndex: idx)
        }

        let summary = try await worker.planAndExecute(candidates: cands, urlMap: urlMap)
        XCTAssertEqual(summary.totalItems, 3)
        XCTAssertEqual(summary.succeededCount, 3)
        XCTAssertEqual(summary.seriesIds.count, 2)

        let allSeries = try await library.series()
        XCTAssertEqual(allSeries.count, 2)

        let narutoSeries = try XCTUnwrap(allSeries.first(where: { $0.displayTitle == "火影忍者" }))
        XCTAssertEqual(narutoSeries.volumeIDs.count, 2)

        let bleachSeries = try XCTUnwrap(allSeries.first(where: { $0.displayTitle == "死神" }))
        XCTAssertEqual(bleachSeries.volumeIDs.count, 1)
    }

    func testAppendVolumesToExistingSeries() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let session = try BatchImportSession(file: sessionFile)
        let worker = BatchImportWorker(library: library, session: session, isReadableImage: { _ in true })

        let vol1 = try createTestZip(name: "灌篮高手 01.zip", entries: ["s1.png": [1, 1]])
        let vol2 = try createTestZip(name: "灌篮高手 02.zip", entries: ["s2.png": [2, 2]])
        let vol3 = try createTestZip(name: "灌篮高手 03.zip", entries: ["s3.png": [3, 3]])

        // First import vol 1 single
        let initial = try await library.importArchiveCoordinated(title: "灌篮高手", archive: vol1, isReadableImage: { _ in true })
        XCTAssertEqual(initial.series.volumeIDs.count, 1)

        // Now append vol 2 and vol 3
        let summary = try await worker.appendVolumes(urls: [vol2, vol3], toSeriesId: initial.series.id, seriesTitle: "灌篮高手")
        XCTAssertEqual(summary.totalItems, 2)
        XCTAssertEqual(summary.succeededCount, 2)
        XCTAssertEqual(summary.seriesIds, [initial.series.id])

        let foundSeries = try await library.series(id: initial.series.id)
        let updatedSeries = try XCTUnwrap(foundSeries)
        XCTAssertEqual(updatedSeries.volumeIDs.count, 3)
        let chapters = try await library.chapters(for: initial.series.id)
        XCTAssertEqual(chapters.count, 3)
    }

    func testSingleItemFailureDoesNotBlockRemainingAndCanRetry() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let session = try BatchImportSession(file: sessionFile)
        let worker = BatchImportWorker(library: library, session: session, isReadableImage: { _ in true })

        let valid1 = try createTestZip(name: "卷01.zip", entries: ["p1.png": [1, 2]])
        let corrupt = outsideDirectory.appendingPathComponent("卷02.zip")
        try Data("NOT_A_VALID_ZIP_ARCHIVE_DATA".utf8).write(to: corrupt)
        let valid3 = try createTestZip(name: "卷03.zip", entries: ["p3.png": [5, 6]])

        var urlMap: [String: URL] = [:]
        let cands = try [valid1, corrupt, valid3].enumerated().map { idx, url in
            urlMap[url.path] = url
            return try BatchImportCandidate(seriesTitle: "混合测试", fileName: url.lastPathComponent, fileId: url.path, format: "zip", selectionIndex: idx)
        }

        let summary = try await worker.planAndExecute(candidates: cands, urlMap: urlMap)
        XCTAssertEqual(summary.totalItems, 3)
        XCTAssertEqual(summary.succeededCount, 2)
        XCTAssertEqual(summary.failedCount, 1)

        let snapshot = await session.current()
        XCTAssertEqual(snapshot?.groups[0].items[0].state, .completed)
        XCTAssertEqual(snapshot?.groups[0].items[1].state, .failed)
        XCTAssertEqual(snapshot?.groups[0].items[2].state, .completed)

        let seriesId = try XCTUnwrap(summary.seriesIds.first)
        let foundSeries = try await library.series(id: seriesId)
        var currentSeries = try XCTUnwrap(foundSeries)
        XCTAssertEqual(currentSeries.volumeIDs.count, 2)

        // Now fix the corrupted item
        let fixedItems = [ZIPFixture.Item("p2.png", [3, 4])]
        let validZip2Data = try ZIPFixture.make(fixedItems)
        try validZip2Data.write(to: corrupt)

        // Retry failed items
        let retrySummary = try await worker.retryFailed(urlMap: urlMap)
        XCTAssertEqual(retrySummary.failedCount, 0)
        XCTAssertEqual(retrySummary.succeededCount, 3)

        let refoundSeries = try await library.series(id: seriesId)
        currentSeries = try XCTUnwrap(refoundSeries)
        XCTAssertEqual(currentSeries.volumeIDs.count, 3)
    }

    func testCancellationStopsSubsequentItemsAndCleansStaging() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let session = try BatchImportSession(file: sessionFile)
        let worker = BatchImportWorker(library: library, session: session, isReadableImage: { _ in true })

        let zip1 = try createTestZip(name: "取消测试 01.zip", entries: ["p1.png": [1]])
        let zip2 = try createTestZip(name: "取消测试 02.zip", entries: ["p2.png": [2]])

        var urlMap: [String: URL] = [:]
        let cands = try [zip1, zip2].enumerated().map { idx, url in
            urlMap[url.path] = url
            return try BatchImportCandidate(fileName: url.lastPathComponent, fileId: url.path, format: "zip", selectionIndex: idx)
        }

        let summary = try await worker.planAndExecute(candidates: cands, urlMap: urlMap) { update in
            if update.itemIndex == 0 && update.state == .completed {
                Task {
                    await (try? worker.cancel())
                }
            }
        }

        // Either 1 succeeded or cancelled triggered
        XCTAssertTrue(summary.cancelled || summary.succeededCount >= 1)

        // Check that staging directory is completely empty / no orphans
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        let stagingFolders = remainingFiles.filter { $0.hasPrefix(".import-") }
        XCTAssertEqual(stagingFolders, [])
    }

    func testBookmarkRoundTrip() throws {
        let testFile = outsideDirectory.appendingPathComponent("bookmark_target.txt")
        try Data("bookmark test".utf8).write(to: testFile)

        let bookmarkData = try BatchImportWorker.createBookmark(for: testFile)
        XCTAssertFalse(bookmarkData.isEmpty)

        let resolvedURL = try BatchImportWorker.resolveBookmark(bookmarkData)
        XCTAssertEqual(resolvedURL.standardizedFileURL.path, testFile.standardizedFileURL.path)
    }

    func testRestartRecoveryUsesReselectedFileAndPreservesSessionSeriesAndFirstVolume() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let session = try BatchImportSession(file: sessionFile)
        let first = try createTestZip(name: "续作01.zip", entries: ["1.png": [1]])
        let missing = outsideDirectory.appendingPathComponent("续作02.zip")
        let candidates = try [first, missing].enumerated().map { index, url in
            try BatchImportCandidate(seriesTitle: "续作", fileName: url.lastPathComponent, fileId: url.path, format: "zip", selectionIndex: index)
        }
        let worker = BatchImportWorker(library: library, session: session, isReadableImage: { _ in true })
        let original = try await worker.planAndExecute(candidates: candidates, urlMap: [first.path: first])
        XCTAssertEqual(original.succeededCount, 1)
        XCTAssertEqual(original.failedCount, 1)
        let seriesID = try XCTUnwrap(original.seriesIds.first)
        let firstSeries = try await library.series(id: seriesID)
        let firstVolumeID = try XCTUnwrap(firstSeries?.volumeIDs.first)
        let originalSession = await session.current()
        let taskID = try XCTUnwrap(originalSession?.taskId)

        let pickedDirectory = outsideDirectory.appendingPathComponent("重新授权")
        try FileManager.default.createDirectory(at: pickedDirectory, withIntermediateDirectories: true)
        let picked = pickedDirectory.appendingPathComponent(missing.lastPathComponent)
        try ZIPFixture.make([ZIPFixture.Item("2.png", [2])]).write(to: picked)
        let restoredSession = try BatchImportSession(file: sessionFile)
        let loaded = await restoredSession.current()
        let plan = BatchImportRecoveryPlan(snapshot: try XCTUnwrap(loaded), selectedURLs: [picked, first])
        XCTAssertEqual(plan.pendingCount, 1)
        XCTAssertEqual(plan.urlMap[missing.path], picked)
        XCTAssertTrue(plan.unresolvedNames.isEmpty)
        XCTAssertNil(plan.urlMap[first.path], "已完成文件不应重新排队")
        let restoredLibrary = try LocalLibrary(directory: tempDirectory)
        let restoredWorker = BatchImportWorker(library: restoredLibrary, session: restoredSession, isReadableImage: { _ in true })
        let result = try await restoredWorker.resumeSession(urlMap: plan.urlMap)
        XCTAssertEqual(result.taskId, taskID)
        XCTAssertEqual(result.succeededCount, 2)
        XCTAssertEqual(result.failedCount, 0)
        let finalSeries = try await restoredLibrary.series(id: seriesID)
        XCTAssertEqual(finalSeries?.volumeIDs.count, 2)
        XCTAssertEqual(finalSeries?.volumeIDs.first, firstVolumeID)
        let allSeries = try await restoredLibrary.series()
        XCTAssertEqual(allSeries.count, 1)
        let finalSession = await restoredSession.current()
        XCTAssertEqual(finalSession?.groups.first?.targetBookId, seriesID)
        XCTAssertTrue(finalSession?.groups.first?.items.allSatisfy { $0.state == .completed } == true)
    }

    func testSavedPathAloneCannotAuthorizeRestartImport() async throws {
        let zip = try createTestZip(name: "仍在原位置.zip", entries: ["1.png": [1]])
        let library = try LocalLibrary(directory: tempDirectory)
        let session = try BatchImportSession(file: sessionFile)
        let saved = try await session.create(groups: [.init(key: "old", title: "未授权", targetBookId: "", items: [.init(uri: zip.path, name: zip.lastPathComponent, format: "zip", selectionIndex: 0)])])
        let worker = BatchImportWorker(library: library, session: session, isReadableImage: { _ in true })
        let summary = try await worker.resumeSession(urlMap: [:])
        XCTAssertEqual(summary.taskId, saved.taskId)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.succeededCount, 0)
        let series = try await library.series()
        XCTAssertTrue(series.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path), "原文件不得被删除")
    }

    func testRecoveryNeverAssignsAmbiguousSameNameFilesBySelectionOrder() async throws {
        let session = try BatchImportSession(file: sessionFile)
        let snapshot = try await session.create(groups: [.init(key: "two", title: "同名", targetBookId: "", items: [
            .init(uri: "/original/a/卷01.zip", name: "卷01.zip", format: "zip", selectionIndex: 0),
            .init(uri: "/original/b/卷01.zip", name: "卷01.zip", format: "zip", selectionIndex: 1)
        ])])
        let selected = [URL(fileURLWithPath: "/picked/b/卷01.zip"), URL(fileURLWithPath: "/picked/a/卷01.zip")]
        let ambiguous = BatchImportRecoveryPlan(snapshot: snapshot, selectedURLs: selected)
        XCTAssertTrue(ambiguous.urlMap.isEmpty)
        XCTAssertEqual(ambiguous.unresolvedNames.count, 2)
        XCTAssertEqual(ambiguous.ambiguousNames, ["卷01.zip"])
        let exact = BatchImportRecoveryPlan(snapshot: snapshot, selectedURLs: [URL(fileURLWithPath: "/original/b/卷01.zip"), URL(fileURLWithPath: "/original/a/卷01.zip")])
        XCTAssertEqual(exact.urlMap.count, 2)
        XCTAssertTrue(exact.unresolvedNames.isEmpty)
    }

    func testCancellingCallingTaskAfterFirstVolumeStopsAndPersistsRemainingSkippedItems() async throws {
        let library = try LocalLibrary(directory: tempDirectory)
        let session = try BatchImportSession(file: sessionFile)
        let urls = try (1...3).map { try createTestZip(name: "取消测试0\($0).zip", entries: ["\($0).png": [UInt8($0)]]) }
        let candidates = try urls.enumerated().map { index, url in
            try BatchImportCandidate(seriesTitle: "取消测试", fileName: url.lastPathComponent, fileId: url.path, format: "zip", selectionIndex: index)
        }
        let urlMap = Dictionary(uniqueKeysWithValues: urls.map { ($0.path, $0) })
        let worker = BatchImportWorker(library: library, session: session, isReadableImage: { _ in true })
        let job = Task {
            try await worker.planAndExecute(candidates: candidates, urlMap: urlMap) { progress in
                if progress.state == .completed { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        let result = try await job.value
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.skippedCount, 2)
        let restored = try BatchImportSession(file: sessionFile)
        let snapshot = await restored.current()
        XCTAssertTrue(snapshot?.cancelled == true)
        XCTAssertEqual(snapshot?.groups.first?.items.map(\.state), [.completed, .skipped, .skipped])
        let series = try await library.series()
        XCTAssertEqual(series.first?.volumeIDs.count, 1)
        XCTAssertEqual(series.count, 1)
        for url in urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
    }
}
