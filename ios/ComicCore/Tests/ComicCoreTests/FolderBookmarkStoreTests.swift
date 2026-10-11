import XCTest
@testable import ComicCore

private final class FolderWriteControl: @unchecked Sendable {
    private let lock = NSLock()
    private var blocked = false
    func blockWrites() { lock.lock(); blocked = true; lock.unlock() }
    func write(_ data: Data, to url: URL) throws {
        lock.lock(); let shouldFail = blocked; lock.unlock()
        if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }
}

final class FolderBookmarkStoreTests: XCTestCase {
    func testFailedNewBookmarkDoesNotPublishMemoryOrOverwriteDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let control = FolderWriteControl()
        let store = try FolderBookmarkStore(directory: root, write: { try control.write($0, to: $1) })
        control.blockWrites()
        let record = SyncedFolderRecord(folderName: "外部漫画", bookmarkData: Data([1, 2]), seriesId: "stable-series")
        XCTAssertThrowsError(try store.save(record: record))
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertTrue(try FolderBookmarkStore(directory: root).list().isEmpty)
    }

    func testFailedUpdateAndUnlinkPreserveOriginalBookmarkAcrossRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let control = FolderWriteControl()
        let store = try FolderBookmarkStore(directory: root, write: { try control.write($0, to: $1) })
        let original = SyncedFolderRecord(folderName: "原文件夹", bookmarkData: Data([7, 8]), seriesId: "stable-series")
        try store.save(record: original)
        let file = root.appendingPathComponent("synced_folders.json")
        let before = try Data(contentsOf: file)
        control.blockWrites()
        var changed = original
        changed.bookmarkData = Data([9]); changed.status = .permissionRevoked
        XCTAssertThrowsError(try store.save(record: changed))
        XCTAssertEqual(store.record(id: original.id), original)
        XCTAssertThrowsError(try store.remove(id: original.id))
        XCTAssertEqual(store.record(id: original.id), original)
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try FolderBookmarkStore(directory: root).record(id: original.id), original)
    }
}
