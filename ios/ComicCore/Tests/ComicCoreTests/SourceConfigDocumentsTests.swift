import XCTest
@testable import ComicCore

final class SourceConfigDocumentsTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func store() -> (SourcePreferences, UserDefaults, String) {
        let name = "SourceConfigDocumentsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        return (SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs), defaults, name)
    }
    private func package(_ store: SourcePreferences) -> SourceExportPackage {
        store.exportPackage(sources: BuiltinSourceCatalog.activeIDs.map { id in (id, SourceConfigDefaults.defaultConfig(for: id)?.name ?? id, "", "") })
    }

    func testRealJSONFileRoundTripRetainsAll51SourcesAnd50EnabledAfterReload() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (source, sourceDefaults, sourceName) = store(), (target, defaults, name) = store()
        defer { sourceDefaults.removePersistentDomain(forName: sourceName); defaults.removePersistentDomain(forName: name) }
        let original = root.appendingPathComponent("original.cbz"); try Data([1, 2, 3]).write(to: original)
        source.setOrder(Array(BuiltinSourceCatalog.activeIDs.reversed()))
        let worker = SourceConfigDocuments(temporaryRoot: root.appendingPathComponent("exports"))
        let exported = try await worker.prepareExport(package(source))
        XCTAssertEqual(exported.url.lastPathComponent, "xx-comic-sources.json")
        let json = try JSONDecoder().decode(SourceExportPackage.self, from: Data(contentsOf: exported.url))
        XCTAssertEqual(json.schema, "xx-comic.sources"); XCTAssertEqual(json.version, 2)
        XCTAssertEqual(json.sources.count, 51); XCTAssertEqual(json.sources.filter(\.enabled).count, 50)
        let prepared = try await worker.prepareImport(from: exported.url, snapshot: target.importSnapshot())
        XCTAssertEqual(target.orderedIDs, BuiltinSourceCatalog.activeIDs, "Preparing a file must not save preferences")
        let result = try target.applyImport(prepared)
        XCTAssertEqual(result.totalSources, 51); XCTAssertTrue(result.warnings.isEmpty)
        let reloaded = SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs)
        XCTAssertEqual(reloaded.orderedIDs, Array(BuiltinSourceCatalog.activeIDs.reversed()))
        XCTAssertEqual(reloaded.enabledIDs.count, 50); XCTAssertFalse(reloaded.isEnabled("duya"))
        XCTAssertEqual(try Data(contentsOf: original), Data([1, 2, 3]))
        try await worker.discardExport(exported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.url.path))
        XCTAssertEqual(try Data(contentsOf: original), Data([1, 2, 3]))
    }

    func testInvalidFileDoesNotApplyValidFirstItemAndCanRetryWithAValidFile() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (target, defaults, name) = store(); defer { defaults.removePersistentDomain(forName: name) }
        let file = root.appendingPathComponent("config.json"), before = target.importSnapshot()
        let worker = SourceConfigDocuments(temporaryRoot: root.appendingPathComponent("exports"))
        try Data(#"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"gmh","enabled":false},{"id":"manben","enabled":"invalid"}]}"#.utf8).write(to: file)
        do { _ = try await worker.prepareImport(from: file, snapshot: before); XCTFail("Malformed second item must reject the whole file") }
        catch { XCTAssertEqual(error as? SourceConfigError, .invalidFields) }
        XCTAssertEqual(target.importSnapshot(), before)
        try Data(#"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"gmh","enabled":false}]}"#.utf8).write(to: file)
        let prepared = try await worker.prepareImport(from: file, snapshot: before)
        _ = try target.applyImport(prepared); XCTAssertFalse(target.isEnabled("gmh"))
    }

    func testUnsupportedFieldsReportPartialImportThroughARealFile() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (target, defaults, name) = store(); defer { defaults.removePersistentDomain(forName: name) }
        let file = root.appendingPathComponent("partial.json")
        try Data(#"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"gmh","enabled":false,"routes":{"fictional":"/ignored"}},{"id":"baozimh"}],"custom":[{"id":"custom-test"}]}"#.utf8).write(to: file)
        let worker = SourceConfigDocuments()
        let prepared = try await worker.prepareImport(from: file, snapshot: target.importSnapshot())
        let result = try target.applyImport(prepared)
        XCTAssertEqual(result.totalSources, 1); XCTAssertEqual(result.skippedSources, ["baozimh", "custom-test"])
        XCTAssertTrue(result.warnings.contains { $0.contains("gmh.routes.fictional") })
        XCTAssertEqual(target.orderedIDs.count, 51); XCTAssertNil(target.config(for: "gmh")?.routes?["fictional"])
    }

    func testCancelledFileReadCannotWritePreferences() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (target, defaults, name) = store(); defer { defaults.removePersistentDomain(forName: name) }
        let file = root.appendingPathComponent("config.json")
        try Data(#"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"gmh","enabled":false}]}"#.utf8).write(to: file)
        let before = target.importSnapshot()
        let coordinate = FileAccessCoordinator { url, _, body in
            withUnsafeCurrentTask { $0?.cancel() }
            try body(url)
        }
        let worker = SourceConfigDocuments(coordinator: coordinate)
        let task = Task { try await worker.prepareImport(from: file, snapshot: before) }
        do { _ = try await task.value; XCTFail("Cancel before reading must stop preparation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(target.importSnapshot(), before)
    }

    func testPreparedImportCannotOverwriteConfigurationChangedDuringFileRead() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (target, defaults, name) = store(); defer { defaults.removePersistentDomain(forName: name) }
        let file = root.appendingPathComponent("config.json")
        try Data(#"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"gmh","enabled":false}]}"#.utf8).write(to: file)
        let worker = SourceConfigDocuments()
        let prepared = try await worker.prepareImport(from: file, snapshot: target.importSnapshot())
        target.setEnabled(true, id: "duya")
        XCTAssertThrowsError(try target.applyImport(prepared)) { XCTAssertEqual($0 as? SourceConfigError, .configurationChanged) }
        XCTAssertTrue(target.isEnabled("gmh")); XCTAssertTrue(target.isEnabled("duya"))
    }

    func testUnreadableNonUTF8OversizedAndDirectoryInputsAreRejected() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (target, defaults, name) = store(); defer { defaults.removePersistentDomain(forName: name) }
        let worker = SourceConfigDocuments(), snapshot = target.importSnapshot()
        let invalid = root.appendingPathComponent("invalid.json"); try Data([0xff, 0xfe, 0xfd]).write(to: invalid)
        let large = root.appendingPathComponent("large.json")
        try Data(repeating: 32, count: Int(SourceConfigDocuments.maximumBytes) + 1).write(to: large)
        let cases: [(URL, SourceConfigDocumentError)] = [(root, .invalidFile), (invalid, .invalidUTF8), (large, .tooLarge), (root.appendingPathComponent("missing.json"), .readFailed)]
        for (url, expected) in cases {
            do { _ = try await worker.prepareImport(from: url, snapshot: snapshot); XCTFail("Reject " + url.lastPathComponent) }
            catch { XCTAssertEqual(error as? SourceConfigDocumentError, expected) }
        }
        XCTAssertEqual(target.importSnapshot(), snapshot)
    }

    func testExportCleanupPreservesUnknownFilesAndRejectsReplacedFileAndLinks() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (target, defaults, name) = store(); defer { defaults.removePersistentDomain(forName: name) }
        let worker = SourceConfigDocuments(temporaryRoot: root.appendingPathComponent("exports"))
        let first = try await worker.prepareExport(package(target))
        let unknown = first.url.deletingLastPathComponent().appendingPathComponent("unknown.txt")
        try Data([5, 6]).write(to: unknown); try await worker.discardExport(first)
        XCTAssertEqual(try Data(contentsOf: unknown), Data([5, 6]))
        let second = try await worker.prepareExport(package(target))
        try Data([7, 8]).write(to: second.url)
        do { try await worker.discardExport(second); XCTFail("A replaced file is not owned") }
        catch { XCTAssertEqual(error as? SourceConfigDocumentError, .unsafeExport) }
        XCTAssertEqual(try Data(contentsOf: second.url), Data([7, 8]))
        let third = try await worker.prepareExport(package(target))
        try FileManager.default.removeItem(at: third.url)
        try FileManager.default.createSymbolicLink(at: third.url, withDestinationURL: unknown)
        do { try await worker.discardExport(third); XCTFail("A symlink must be preserved") }
        catch { XCTAssertEqual(error as? SourceConfigDocumentError, .unsafeExport) }
        XCTAssertEqual(try Data(contentsOf: unknown), Data([5, 6]))
    }
}
