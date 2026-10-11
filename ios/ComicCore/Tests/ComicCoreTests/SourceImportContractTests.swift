import XCTest
@testable import ComicCore

final class SourceImportContractTests: XCTestCase {
    private func withStore(_ body: (SourcePreferences) throws -> Void) rethrows {
        let suite = "SourceImportContractTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs))
    }

    func testMinimalV2ItemMergesDefaultsAndConsumesOverrides() throws {
        try withStore { store in
            store.setEnabled(false, id: "hiperdex")
            let result = try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"hiperdex","baseUrl":"https://fixture.invalid","routes":{"search":"/lookup?q={keyword}"}}]}"#)
            XCTAssertEqual(result.totalSources, 1)
            let config = try XCTUnwrap(store.config(for: "hiperdex"))
            XCTAssertEqual(config.baseUrl, "https://fixture.invalid")
            XCTAssertEqual(config.route("search"), "/lookup?q={keyword}")
            XCTAssertEqual(config.route("latest"), SourceConfigDefaults.hiperdex().route("latest"))
            XCTAssertEqual(config.filter("genre.webtoon"), "webtoon")
            XCTAssertFalse(store.isEnabled("hiperdex"))
        }
    }

    func testMalformedPackageDoesNotPartiallyChangeOrderSwitchesOrConfig() throws {
        try withStore { store in
            let originalOrder = store.orderedIDs, original = store.config(for: "hiperdex")
            XCTAssertThrowsError(try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sourceOrder":["hiperdex","gmh"],"sources":[{"id":"hiperdex","enabled":false,"baseUrl":"https://fixture.invalid"},{"id":"gmh","routes":{"search":17}}]}"#))
            XCTAssertEqual(store.orderedIDs, originalOrder)
            XCTAssertTrue(store.isEnabled("hiperdex"))
            XCTAssertEqual(store.config(for: "hiperdex"), original)
        }
    }

    func testUnknownAndCustomSourcesDoNotBecomeActiveSources() throws {
        try withStore { store in
            let result = try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"unknown"}],"custom":[{"id":"custom-fixture","name":"Custom"}]}"#)
            XCTAssertEqual(result.totalSources, 0)
            XCTAssertEqual(result.skippedSources, ["unknown", "custom-fixture"])
            XCTAssertFalse(result.warnings.isEmpty)
            XCTAssertEqual(store.orderedIDs.count, 51)
            XCTAssertFalse(store.isEnabled("unknown"))
        }
    }

    func testUnsupportedKeysAreReportedWithoutDroppingSupportedConfiguration() throws {
        try withStore { store in
            let result = try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"hiperdex","routes":{"search":"/lookup?q={keyword}","fictional":"/ignored"},"filters":{"fictional":"ignored"}}]}"#)
            XCTAssertEqual(result.totalSources, 1)
            XCTAssertTrue(result.warnings.contains { $0.contains("routes.fictional") })
            XCTAssertTrue(result.warnings.contains { $0.contains("filters.fictional") })
            XCTAssertNil(store.config(for: "hiperdex")?.routes?["fictional"])
            XCTAssertEqual(store.config(for: "hiperdex")?.route("search"), "/lookup?q={keyword}")
        }
    }

    func testFutureVersionIsRejectedBeforeMutation() throws {
        try withStore { store in
            XCTAssertThrowsError(try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":3,"sources":[{"id":"hiperdex","enabled":false}]}"#))
            XCTAssertTrue(store.isEnabled("hiperdex"))
        }
    }
}
