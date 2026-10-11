import XCTest
@testable import ComicCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class LocalOwnershipRecoveryTests: XCTestCase {
    private var root: URL!
    private var external: URL!
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6VEAAAAASUVORK5CYII=")!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OwnedRecovery-" + UUID().uuidString)
        external = FileManager.default.temporaryDirectory.appendingPathComponent("RecoveryInput-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try png.write(to: external.appendingPathComponent("page.png"))
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: external)
    }
    private func prepare(_ library: LocalLibrary) throws -> PreparedLocalImport {
        try library.prepareImages(title: "恢复测试", files: [external.appendingPathComponent("page.png")])
    }
    private func abandoned(in library: LocalLibrary) throws -> URL {
        let prepared = try prepare(library)
        return prepared.staging // Only the URL escapes: the live journal lock is released.
    }

    func testUnknownPrefixedAndUUIDDirectoriesAreNeverOrphansByNameAlone() async throws {
        let library = try LocalLibrary(directory: root)
        _ = try await library.publishImport(prepare(library))
        let unknown = [".import-" + UUID().uuidString, UUID().uuidString, ".import-not-a-transaction"]
        for name in unknown {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try png.write(to: folder.appendingPathComponent("book.json"))
        }
        try await library.recoverOrphans()
        try await library.recoverOrphans()
        for name in unknown { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name).appendingPathComponent("book.json")), png) }
        XCTAssertEqual(try Data(contentsOf: external.appendingPathComponent("page.png")), png)
    }

    func testRecoveryDoesNotRemoveActiveImportFromAnotherLibraryInstance() async throws {
        let library = try LocalLibrary(directory: root), prepared = try prepare(library)
        let restarted = try LocalLibrary(directory: root)
        try await restarted.recoverOrphans()
        XCTAssertEqual(try Data(contentsOf: prepared.staging.appendingPathComponent("0.png")), png)
        let book = try library.publishPrepared(prepared)
        XCTAssertEqual(try restarted.book(id: book.id), book)
    }

    func testPartialPreparationWithDurableOwnershipIsCleanedOnRestart() async throws {
        let library = try LocalLibrary(directory: root)
        let staging: URL
        do {
            let partial = try LocalImportDirectory(root: root, owner: library.importOwner)
            staging = partial.staging
            try partial.write(png.prefix(8), name: "0.png")
            XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent("book.json").path))
        }
        try await LocalLibrary(directory: root).recoverOrphans()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try Data(contentsOf: external.appendingPathComponent("page.png")), png)
    }

    func testUncommittedFirstVolumeRecoversEvenBeforeCatalogExists() async throws {
        let library = try LocalLibrary(directory: root)
        let pendingID: String
        do { let prepared = try prepare(library); pendingID = try library.publishPrepared(prepared, pendingCatalog: true).id }
        let exists = await library.catalogStore.existsOnDisk()
        XCTAssertFalse(exists)
        try await LocalLibrary(directory: root).recoverOrphans()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(pendingID).path))
    }

    func testCommittedCatalogAndLegacyVolumesSurvivePendingJournalRecovery() async throws {
        let library = try LocalLibrary(directory: root)
        let book: LocalBook
        do {
            let prepared = try prepare(library)
            book = try library.publishPrepared(prepared, pendingCatalog: true)
            let series = LocalSeriesRecord(id: UUID().uuidString, originalTitle: book.title, userTitle: nil,
                volumeIDs: [book.id], createdAt: book.createdAt, updatedAt: book.createdAt, status: "ready")
            try await library.catalogStore.commitNewSeries(series)
        }
        let legacy = try library.importImages(title: "旧单卷", files: [external.appendingPathComponent("page.png")])
        let restarted = try LocalLibrary(directory: root)
        try await restarted.recoverOrphans()
        XCTAssertEqual(try restarted.book(id: book.id), book)
        XCTAssertEqual(try restarted.book(id: legacy.id), legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(book.id).appendingPathComponent(LocalImportJournal.name).path))
    }

    func testUnknownContentsReportRecoveryFailureBeforeDeletingKnownFiles() async throws {
        let library = try LocalLibrary(directory: root), staging = try abandoned(in: library)
        let unknown = staging.appendingPathComponent("keep.txt")
        try Data("user data".utf8).write(to: unknown)
        do { try await LocalLibrary(directory: root).recoverOrphans(); XCTFail("未知文件不能假成功") }
        catch { XCTAssertEqual(error.localizedDescription, LocalLibraryError.recoveryIncomplete.localizedDescription) }
        XCTAssertEqual(try Data(contentsOf: unknown), Data("user data".utf8))
        XCTAssertEqual(try Data(contentsOf: staging.appendingPathComponent("0.png")), png)
        try FileManager.default.removeItem(at: unknown)
        try await LocalLibrary(directory: root).recoverOrphans()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testCopiedDirectoryJournalAndReplacedPageCannotAuthorizeCleanup() async throws {
        let library = try LocalLibrary(directory: root), staging = try abandoned(in: library)
        let copy = root.appendingPathComponent(".import-" + UUID().uuidString)
        try FileManager.default.copyItem(at: staging, to: copy)
        let parked = external.appendingPathComponent("original.png")
        try FileManager.default.moveItem(at: staging.appendingPathComponent("0.png"), to: parked)
        try Data("replacement".utf8).write(to: staging.appendingPathComponent("0.png"))
        do { try await LocalLibrary(directory: root).recoverOrphans(); XCTFail("替换文件必须阻止清理") } catch {}
        XCTAssertEqual(try Data(contentsOf: staging.appendingPathComponent("0.png")), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: copy.appendingPathComponent("0.png")), png)
        XCTAssertEqual(try Data(contentsOf: parked), png)
    }

    func testSymlinkAndMalformedJournalDoNotAuthorizeOutsideAccess() async throws {
        let library = try LocalLibrary(directory: root), staging = try abandoned(in: library)
        let marker = staging.appendingPathComponent(LocalImportJournal.name)
        try FileManager.default.removeItem(at: marker)
        try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: external.appendingPathComponent("page.png"))
        let unknown = root.appendingPathComponent(".import-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: false)
        try Data("{}\n".utf8).write(to: unknown.appendingPathComponent(LocalImportJournal.name))
        try await LocalLibrary(directory: root).recoverOrphans()
        XCTAssertEqual(try Data(contentsOf: staging.appendingPathComponent("0.png")), png)
        XCTAssertEqual(try Data(contentsOf: external.appendingPathComponent("page.png")), png)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    }

    func testWholeSeriesUnknownFilePreflightKeepsEveryVolumeReadyAndReadable() async throws {
        let library = try LocalLibrary(directory: root)
        let first = try await library.publishImport(prepare(library))
        let second = try await library.publishImport(prepare(library), targetSeriesId: first.series.id)
        let unknown = root.appendingPathComponent(second.book.id).appendingPathComponent("keep.txt")
        try png.write(to: unknown)
        do { try await library.deleteSeries(id: first.series.id); XCTFail("未知文件必须拒删整本") } catch {}
        let series = try await library.series(id: first.series.id)
        XCTAssertEqual(series?.status, "ready")
        XCTAssertEqual(series?.volumeIDs, [first.book.id, second.book.id])
        XCTAssertEqual(try library.book(id: first.book.id), first.book)
        XCTAssertEqual(try library.book(id: second.book.id), second.book)
        XCTAssertEqual(try Data(contentsOf: unknown), png)
        try FileManager.default.removeItem(at: unknown)
        try await library.deleteSeries(id: first.series.id)
        let deleted = try await library.series(id: first.series.id)
        XCTAssertNil(deleted)
    }

    private func leaveDeletionJournal(book: LocalBook) throws {
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard rootFD >= 0 else { throw LocalLibraryError.invalidBook }
        defer { close(rootFD) }
        let folderFD = openat(rootFD, book.id, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard folderFD >= 0 else { throw LocalLibraryError.invalidBook }
        defer { close(folderFD) }
        let journal = try LocalImportJournal(rootFD: rootFD, folderFD: folderFD, token: book.id)
        for name in book.pages + ["book.json"] {
            var info = stat()
            guard fstatat(folderFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw LocalLibraryError.invalidBook }
            try journal.record(name: name, identity: [UInt64(info.st_dev), UInt64(info.st_ino)])
        }
        try journal.willDelete(targetID: book.id)
        // Crash after some unlink calls, before removal of the journal/directory/catalog.
        XCTAssertEqual(unlinkat(folderFD, "book.json", 0), 0)
        XCTAssertEqual(unlinkat(folderFD, book.pages[0], 0), 0)
    }

    func testInterruptedDeletionRestoresTombstoneAndCompletesOnRestart() async throws {
        let library = try LocalLibrary(directory: root)
        let imported = try await library.importFolderCoordinated(title: "旧书", folder: external, isReadableImage: { _ in true })
        _ = try await library.renameSeries(id: imported.series.id, newTitle: "保留书名")
        let fingerprint = try XCTUnwrap(imported.book.fingerprint)
        let tombstone = LocalDeletedFingerprintRecord(fingerprint: fingerprint, seriesId: imported.series.id,
            volumeId: imported.book.id, userTitle: "保留书名", deletedAt: Date().timeIntervalSince1970)
        try await library.catalogStore.markSeriesDeleting(seriesId: imported.series.id, newTombstones: [tombstone])
        try leaveDeletionJournal(book: imported.book)
        let restarted = try LocalLibrary(directory: root)
        try await restarted.recoverOrphans()
        let deleted = try await restarted.series(id: imported.series.id)
        XCTAssertNil(deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(imported.book.id).path))
        let restored = try await restarted.importFolderCoordinated(title: "重导", folder: external, isReadableImage: { _ in true })
        XCTAssertEqual(restored.series.id, imported.series.id)
        XCTAssertEqual(restored.book.id, imported.book.id)
        XCTAssertEqual(restored.series.displayTitle, "保留书名")
        XCTAssertEqual(try Data(contentsOf: external.appendingPathComponent("page.png")), png)
    }
}
