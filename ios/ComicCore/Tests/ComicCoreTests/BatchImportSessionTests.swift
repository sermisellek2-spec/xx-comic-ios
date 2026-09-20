import XCTest
@testable import ComicCore

final class BatchImportSessionTests: XCTestCase {
    private func file() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("session.json")
    }

    private func groups() -> [BatchImportSession.Group] {
        [0, 1, 2].map { group in
            .init(key: "g\(group)", title: "系列", targetBookId: "old", items: (0..<2).map {
                .init(uri: "opaque:\(group)/\($0)", name: "卷\($0)", format: "epub", selectionIndex: $0)
            })
        }
    }

    private func rejects(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected error", file: file, line: line) } catch {}
    }

    func testFinishedItemsNeverRestartAndFailedItemsDoNotBlockOtherGroups() async throws {
        let file = try file()
        let store = try BatchImportSession(file: file)
        let created = try await store.create(groups: groups())
        let id = created.taskId
        try await store.complete(taskID: id, group: 0, item: 0, bookID: "new")
        try await store.skip(taskID: id, group: 0, item: 1)
        try await store.fail(taskID: id, group: 1, item: 0, error: " 权限已失效 ")
        try await store.complete(taskID: id, group: 1, item: 1, bookID: "")
        try await store.start(taskID: id, group: 2, item: 0)
        let pending = await store.pendingGroupIndices()
        XCTAssertEqual(pending, [2])
        let reopened = try BatchImportSession(file: file)
        let loaded = await reopened.current()
        XCTAssertEqual(loaded?.groups[1].items[0].state, .failed)
        XCTAssertEqual(loaded?.groups[1].items[0].error, " 权限已失效 ")
        XCTAssertEqual(loaded?.groups[1].targetBookId, "old")
        let before = try Data(contentsOf: file)
        for index in 0..<2 {
            try await store.start(taskID: id, group: 0, item: index)
            try await store.complete(taskID: id, group: 0, item: index, bookID: "late")
            try await store.fail(taskID: id, group: 0, item: index, error: "late")
            try await store.skip(taskID: id, group: 0, item: index)
        }
        try await store.start(taskID: id, group: 1, item: 0)
        XCTAssertEqual(try Data(contentsOf: file), before)
        try await store.retryFailed(taskID: id)
        let retried = await store.current()
        XCTAssertEqual(retried?.groups[0].items.map(\.state), [.completed, .skipped])
        XCTAssertEqual(retried?.groups[0].targetBookId, "new")
        XCTAssertEqual(retried?.groups[1].items.map(\.state), [.pending, .completed])
        XCTAssertEqual(retried?.groups[1].items[0].error, "")
        XCTAssertEqual(retried?.groups[2].items.map(\.state), [.pending, .pending])
        let retryPending = await store.pendingGroupIndices()
        XCTAssertEqual(retryPending, [1, 2])
        let retryDisk = try BatchImportSession(file: file)
        let retrySaved = await retryDisk.current()
        XCTAssertEqual(retrySaved, retried)
    }

    func testCancelSkipsAllUnfinishedAndLateCallbacksCannotReviveOrTouchSource() async throws {
        let file = try file()
        let source = file.deletingLastPathComponent().appendingPathComponent("source.epub")
        let original = Data([0, 255, 42, 1])
        try original.write(to: source)
        let store = try BatchImportSession(file: file)
        var input = groups()
        input.append(.init(key: "source", title: "源文件", targetBookId: "", items: [
            .init(uri: source.absoluteString, name: "source.epub", format: "epub", selectionIndex: 6)]))
        let created = try await store.create(groups: input)
        let id = created.taskId
        try await store.complete(taskID: id, group: 0, item: 0, bookID: "book")
        try await store.skip(taskID: id, group: 0, item: 1)
        try await store.fail(taskID: id, group: 1, item: 0, error: "failure")
        try await store.start(taskID: id, group: 1, item: 1)
        try await store.cancel(taskID: id)
        let cancelled = await store.current()
        XCTAssertEqual(cancelled?.cancelled, true)
        XCTAssertEqual(cancelled?.groups[0].items.map(\.state), [.completed, .skipped])
        XCTAssertEqual(cancelled?.groups[1].items.map(\.state), [.skipped, .skipped])
        XCTAssertEqual(cancelled?.groups[2].items.map(\.state), [.skipped, .skipped])
        XCTAssertEqual(cancelled?.groups[1].items[0].error, "")
        let bytes = try Data(contentsOf: file)
        await rejects { try await store.start(taskID: id, group: 1, item: 0) }
        try await store.complete(taskID: id, group: 1, item: 0, bookID: "late")
        try await store.fail(taskID: id, group: 1, item: 0, error: "late")
        try await store.skip(taskID: id, group: 0, item: 0)
        try await store.setTargetBookID(taskID: id, group: 0, bookID: "late")
        try await store.retryFailed(taskID: id)
        try await store.cancel(taskID: id)
        let pending = await store.pendingGroupIndices()
        XCTAssertEqual(pending, [])
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let reopened = try BatchImportSession(file: file)
        let restored = await reopened.current()
        XCTAssertEqual(restored, cancelled)
        let replacement = try await store.create(groups: groups())
        XCTAssertNotEqual(replacement.taskId, id)
    }

    func testActiveAndFailedBatchCannotBeReplacedButFinishedBatchCan() async throws {
        let file = try file()
        let store = try BatchImportSession(file: file)
        let created = try await store.create(groups: [groups()[0]])
        await rejects { _ = try await store.create(groups: self.groups()) }
        try await store.fail(taskID: created.taskId, group: 0, item: 0, error: "failed")
        try await store.skip(taskID: created.taskId, group: 0, item: 1)
        await rejects { _ = try await store.create(groups: self.groups()) }
        try await store.complete(taskID: created.taskId, group: 0, item: 0, bookID: "book")
        let replacement = try await store.create(groups: groups())
        XCTAssertNotEqual(replacement.taskId, created.taskId)
        let bytes = try Data(contentsOf: file)
        let old = created.taskId
        await rejects { try await store.start(taskID: old, group: 0, item: 0) }
        await rejects { try await store.complete(taskID: old, group: 0, item: 0, bookID: "late") }
        await rejects { try await store.fail(taskID: old, group: 0, item: 0, error: "late") }
        await rejects { try await store.skip(taskID: old, group: 0, item: 0) }
        await rejects { try await store.setTargetBookID(taskID: old, group: 0, bookID: "late") }
        await rejects { try await store.retryFailed(taskID: old) }
        await rejects { try await store.cancel(taskID: old) }
        let after = await store.current()
        XCTAssertEqual(after, replacement)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testInvalidIndicesAndMissingTaskThrowWithoutMutation() async throws {
        let file = try file()
        let store = try BatchImportSession(file: file)
        await rejects { try await store.cancel(taskID: UUID().uuidString) }
        let created = try await store.create(groups: groups())
        let bytes = try Data(contentsOf: file)
        for (group, item) in [(-1, 0), (3, 0), (0, -1), (0, 2), (Int.max, Int.max)] {
            await rejects { try await store.start(taskID: created.taskId, group: group, item: item) }
            await rejects { try await store.complete(taskID: created.taskId, group: group, item: item, bookID: "bad") }
            await rejects { try await store.fail(taskID: created.taskId, group: group, item: item, error: "bad") }
            await rejects { try await store.skip(taskID: created.taskId, group: group, item: item) }
        }
        await rejects { try await store.setTargetBookID(taskID: created.taskId, group: -1, bookID: "bad") }
        let after = await store.current()
        XCTAssertEqual(after, created)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    private func fixture() -> String {
        """
        {"version":1,"taskId":"00000000-0000-0000-0000-000000000001","groups":[{"key":"k","title":"t","targetBookId":"existing","items":[{"uri":"opaque","name":"n","format":"epub","selectionIndex":4,"state":"pending","error":""}]}],"cancelled":false}
        """
    }

    func testLegacyMissingRequiresExistingBookDefaultsFalse() async throws {
        let file = try file()
        try Data(fixture().utf8).write(to: file)
        let store = try BatchImportSession(file: file)
        let snapshot = await store.current()
        XCTAssertEqual(snapshot?.groups[0].requiresExistingBook, false)
        XCTAssertEqual(snapshot?.groups[0].targetBookId, "existing")
    }

    func testCorruptUnsupportedInvalidAndNonUTF8FilesArePreserved() throws {
        let file = try file()
        let valid = fixture()
        let invalid = ["{broken", valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
            valid.replacingOccurrences(of: "00000000-0000-0000-0000-000000000001", with: "bad-id"),
            valid.replacingOccurrences(of: "pending", with: "unknown"),
            valid.replacingOccurrences(of: "\"error\":\"\"", with: "\"error\":null"),
            valid.replacingOccurrences(of: "\"items\":[", with: "\"missing\":[")]
        for bytes in invalid.map({ Data($0.utf8) }) + [Data([0xff, 0xfe, 0x7b, 0x00])] {
            try bytes.write(to: file)
            XCTAssertThrowsError(try BatchImportSession(file: file))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testUTF16AndUTF32WithoutBOMAreRejectedAsNonUTF8JSON() throws {
        let file = try file()
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            let bytes = try XCTUnwrap(fixture().data(using: encoding))
            try bytes.write(to: file)
            XCTAssertThrowsError(try BatchImportSession(file: file))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testFailedFirstCreateAndReplacementKeepPreviousSnapshot() async throws {
        let file = try file()
        let failWrite: @Sendable (Data, URL) throws -> Void = { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let empty = try BatchImportSession(file: file, write: failWrite)
        await rejects { _ = try await empty.create(groups: self.groups()) }
        let absent = await empty.current()
        XCTAssertNil(absent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let setup = try BatchImportSession(file: file)
        let created = try await setup.create(groups: groups())
        try await setup.cancel(taskID: created.taskId)
        let bytes = try Data(contentsOf: file)
        let store = try BatchImportSession(file: file, write: failWrite)
        let before = await store.current()
        await rejects { _ = try await store.create(groups: self.groups()) }
        let after = await store.current()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testDirectoriesSymlinksAndNonDirectoryParentsAreNotEmptySessions() throws {
        let file = try file()
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertThrowsError(try BatchImportSession(file: file))
        try FileManager.default.removeItem(at: file)
        let target = file.deletingLastPathComponent().appendingPathComponent("target.json")
        let bytes = Data(fixture().utf8)
        try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertThrowsError(try BatchImportSession(file: file))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        try FileManager.default.removeItem(at: target)
        XCTAssertThrowsError(try BatchImportSession(file: file))
        try FileManager.default.removeItem(at: file)
        try bytes.write(to: file)
        XCTAssertThrowsError(try BatchImportSession(file: file.appendingPathComponent("nested.json")))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testExact16MiBReadLimitAndOneByteOverPreserveFile() async throws {
        let file = try file()
        let limit = 16 * 1024 * 1024
        var bytes = Data(fixture().utf8)
        bytes.append(Data(repeating: 32, count: limit - bytes.count))
        try bytes.write(to: file)
        let store = try BatchImportSession(file: file)
        let snapshot = await store.current()
        XCTAssertNotNil(snapshot)
        bytes.append(32)
        try bytes.write(to: file)
        XCTAssertThrowsError(try BatchImportSession(file: file))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testExact16MiBSaveLimitRollsBackOversizedMutationAndCreate() async throws {
        let file = try file()
        let store = try BatchImportSession(file: file)
        let created = try await store.create(groups: [.init(key: "k", title: "t", targetBookId: "", items: [])])
        let initialSize = try Data(contentsOf: file).count
        let target = String(repeating: "a", count: 16 * 1024 * 1024 - initialSize)
        try await store.setTargetBookID(taskID: created.taskId, group: 0, bookID: target)
        let bytes = try Data(contentsOf: file)
        XCTAssertEqual(bytes.count, 16 * 1024 * 1024)
        let before = await store.current()
        await rejects { try await store.setTargetBookID(taskID: created.taskId, group: 0, bookID: target + "a") }
        await rejects { _ = try await store.create(groups: [.init(key: "k", title: "t", targetBookId: target + "a", items: [])]) }
        let after = await store.current()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let reopened = try BatchImportSession(file: file)
        let restored = await reopened.current()
        XCTAssertEqual(restored, before)
    }

    func testWriteFailurePreservesDurableBytesAndAllMemoryFields() async throws {
        let file = try file()
        let setup = try BatchImportSession(file: file)
        let created = try await setup.create(groups: groups())
        try await setup.fail(taskID: created.taskId, group: 0, item: 0, error: "original error")
        let bytes = try Data(contentsOf: file)
        let store = try BatchImportSession(file: file, write: { _, url in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: [NSFilePathErrorKey: url.path])
        })
        let before = await store.current()
        await rejects { try await store.complete(taskID: created.taskId, group: 0, item: 0, bookID: "new") }
        await rejects { try await store.fail(taskID: created.taskId, group: 0, item: 0, error: "new error") }
        await rejects { try await store.skip(taskID: created.taskId, group: 0, item: 0) }
        await rejects { try await store.start(taskID: created.taskId, group: 1, item: 0) }
        await rejects { try await store.setTargetBookID(taskID: created.taskId, group: 0, bookID: "new") }
        await rejects { try await store.retryFailed(taskID: created.taskId) }
        await rejects { try await store.cancel(taskID: created.taskId) }
        let after = await store.current()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let reopened = try BatchImportSession(file: file)
        let restored = await reopened.current()
        XCTAssertEqual(restored, before)
    }

    func testRealDirectoryBlockingAtomicWritePreservesMemoryAndFailurePath() async throws {
        let file = try file()
        let store = try BatchImportSession(file: file)
        let created = try await store.create(groups: groups())
        let previous = file.deletingLastPathComponent().appendingPathComponent("previous.json")
        try FileManager.default.moveItem(at: file, to: previous)
        let bytes = try Data(contentsOf: previous)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let blocker = file.appendingPathComponent("blocker")
        try Data([42]).write(to: blocker)
        await rejects { try await store.complete(taskID: created.taskId, group: 0, item: 0, bookID: "new") }
        await rejects { try await store.cancel(taskID: created.taskId) }
        let after = await store.current()
        XCTAssertEqual(after, created)
        XCTAssertEqual(try Data(contentsOf: previous), bytes)
        XCTAssertEqual(try Data(contentsOf: blocker), Data([42]))
        XCTAssertThrowsError(try BatchImportSession(file: file))
    }

    func testRestartResetsRunningOnlyInMemoryAndPreservesMetadata() async throws {
        let file = try file()
        let store = try BatchImportSession(file: file)
        let empty = await store.current()
        XCTAssertNil(empty)
        let created = try await store.create(groups: [.init(key: " series ", title: " 系列 ", targetBookId: "existing",
            requiresExistingBook: true, items: [.init(uri: " file:///external/one.epub ", name: " 卷一.epub ", format: " epub ", selectionIndex: 4)])])
        try await store.start(taskID: created.taskId, group: 0, item: 0)
        let bytes = try Data(contentsOf: file)
        let reopened = try BatchImportSession(file: file)
        let restored = await reopened.current()
        let saved = try XCTUnwrap(restored)
        XCTAssertEqual(saved.taskId, created.taskId)
        XCTAssertEqual(saved.version, 1)
        XCTAssertNotNil(UUID(uuidString: saved.taskId))
        XCTAssertEqual(saved.groups[0].key, " series ")
        XCTAssertEqual(saved.groups[0].title, " 系列 ")
        XCTAssertTrue(saved.groups[0].requiresExistingBook)
        XCTAssertEqual(saved.groups[0].targetBookId, "existing")
        XCTAssertEqual(saved.groups[0].items[0].uri, " file:///external/one.epub ")
        XCTAssertEqual(saved.groups[0].items[0].name, " 卷一.epub ")
        XCTAssertEqual(saved.groups[0].items[0].format, " epub ")
        XCTAssertEqual(saved.groups[0].items[0].selectionIndex, 4)
        XCTAssertEqual(saved.groups[0].items[0].state, .pending)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let disk = try JSONDecoder().decode(BatchImportSession.Snapshot.self, from: bytes)
        XCTAssertEqual(disk.groups[0].items[0].state, .running)
        try await reopened.setTargetBookID(taskID: saved.taskId, group: 0, bookID: " new ")
        let persisted = try JSONDecoder().decode(BatchImportSession.Snapshot.self, from: Data(contentsOf: file))
        XCTAssertEqual(persisted.groups[0].items[0].state, .pending)
        XCTAssertEqual(persisted.groups[0].targetBookId, " new ")
    }
}
