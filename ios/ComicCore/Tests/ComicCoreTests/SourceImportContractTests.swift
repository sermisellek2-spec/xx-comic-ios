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

    func testFlatLegacyPathsReachRoutesAndExplicitV2RoutesTakePrecedence() throws {
        try withStore { store in
            _ = try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":1,"sources":[{"id":"hiperdex","searchPath":"/legacy?q={keyword}","detailPath":"/legacy/{comicId}"}]}"#)
            XCTAssertEqual(store.config(for: "hiperdex")?.route("search"), "/legacy?q={keyword}")
            XCTAssertEqual(store.config(for: "hiperdex")?.route("detail"), "/legacy/{comicId}")
            _ = try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"hiperdex","searchPath":"/old","routes":{"search":"/v2?q={keyword}"}}]}"#)
            XCTAssertEqual(store.config(for: "hiperdex")?.route("search"), "/v2?q={keyword}")
        }
    }

    func testUnconsumedCompatibilityOverridesAreReportedAndDoNotReplaceStoredValues() throws {
        try withStore { store in
            let result = try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"manhuagui","latestPath":"/unused-flat","routes":{"latest":"/unused","chapter":"/unused/{chapterId}","search":"/supported?q={keyword}"},"filters":{"region.jp":"unused"}},{"id":"d5d6","latestPath":"/unused","routes":{"latest":"/unused"},"filters":{"category.jp":"unused","state.all":"9","state.pub":"8"}}]}"#)
            XCTAssertEqual(result.totalSources, 2)
            for field in ["manhuagui.routes.latest", "manhuagui.routes.chapter", "manhuagui.filters.region.jp", "d5d6.latestPath", "d5d6.routes.latest", "d5d6.filters.category.jp", "d5d6.filters.state.all"] {
                XCTAssertTrue(result.warnings.contains { $0.contains(field) }, field)
            }
            XCTAssertEqual(store.config(for: "manhuagui")?.route("latest"), SourceConfigDefaults.manhuagui().route("latest"))
            XCTAssertEqual(store.config(for: "manhuagui")?.route("search"), "/supported?q={keyword}")
            XCTAssertEqual(store.config(for: "manhuagui")?.filter("region.jp"), "japan")
            XCTAssertEqual(store.config(for: "d5d6")?.filter("state.pub"), "8")
        }
    }

    func testPublicSourceFlatPathsAreReportedAndCannotCreateUnconsumedRoutes() throws {
        try withStore { store in
            let id = try XCTUnwrap(PublicSourceRegistry.ids().first)
            let original = try XCTUnwrap(store.config(for: id))
            let item: [String: Any] = ["id": id, "name": "已改名称", "baseUrl": "https://fixture.invalid",
                                       "latestPath": "/unused-latest", "searchPath": "/unused-search",
                                       "categoryPath": "/unused-category", "detailPath": "/unused-detail"]
            let data = try JSONSerialization.data(withJSONObject: ["schema": "xx-comic.sources", "version": 2, "sources": [item]])
            let result = try store.importConfig(jsonString: String(decoding: data, as: UTF8.self))
            let current = try XCTUnwrap(store.config(for: id))
            for field in ["latestPath", "searchPath", "categoryPath", "detailPath"] {
                XCTAssertTrue(result.warnings.contains { $0.contains(id + "." + field) }, field)
            }
            XCTAssertEqual(current.routes, original.routes)
            XCTAssertEqual(current.latestPath, original.latestPath)
            XCTAssertEqual(current.searchPath, original.searchPath)
            XCTAssertEqual(current.categoryPath, original.categoryPath)
            XCTAssertEqual(current.detailPath, original.detailPath)
            XCTAssertEqual(current.name, "已改名称")
            XCTAssertEqual(current.baseUrl, "https://fixture.invalid")
        }
    }

    func testCurrentCatalogExportRoundTripDoesNotAddPhantomRoutesOrWarnings() throws {
        try withStore { store in
            let sources = BuiltinSourceCatalog.activeIDs.map { id -> (id: String, name: String, domain: String, referer: String) in
                let config = store.config(for: id)!
                return (id, config.name, config.domain, config.referer)
            }
            let original = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, store.config(for: $0.id)!) })
            let result = try store.importConfig(jsonString: store.exportConfig(sources: sources))
            XCTAssertEqual(result.totalSources, 51)
            XCTAssertEqual(result.enabledCount, 50)
            XCTAssertEqual(result.warnings, [])
            for source in sources {
                XCTAssertEqual(store.config(for: source.id)?.routes, original[source.id]?.routes, source.id)
            }
        }
    }

    func testUnconsumedFilterChangesReportSkipAndKeepSupportedManbenSort() throws {
        try withStore { store in
            let result = try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"manben","filters":{"sort.popular":"unused","sort.latest":"7"}},{"id":"hanman18","filters":{"category.all":"unused"}}]}"#)
            XCTAssertTrue(result.warnings.contains { $0.contains("manben.filters.sort.popular") })
            XCTAssertTrue(result.warnings.contains { $0.contains("hanman18.filters.category.all") })
            XCTAssertEqual(store.config(for: "manben")?.filter("sort.popular"), "4")
            XCTAssertEqual(store.config(for: "manben")?.filter("sort.latest"), "7")
            XCTAssertEqual(store.config(for: "hanman18")?.filter("category.all"), "")
        }
    }

    func testUnconsumedMkzhanAndXinmanhuaFiltersReportSkipWithoutDiscardingSupportedFields() throws {
        try withStore { store in
            let mkzhan = store.config(for: "mkzhan")!
            let xinmanhua = store.config(for: "xinmanhua")!
            let result = try store.importConfig(jsonString: #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"mkzhan","enabled":false,"routes":{"search":"/imported-search?keyword={keyword}"},"filters":{"filter.serial":"finish=9","filter.free":"is_free=9"}},{"id":"xinmanhua","filters":{"genre.治愈":"unused","order.popular":"9"}}]}"#)
            for field in ["mkzhan.filters.filter.serial", "mkzhan.filters.filter.free", "xinmanhua.filters.genre.治愈", "xinmanhua.filters.order.popular"] {
                XCTAssertTrue(result.warnings.contains { $0.contains(field) }, field)
            }
            XCTAssertEqual(result.totalSources, 2)
            XCTAssertEqual(store.config(for: "mkzhan")?.filters, mkzhan.filters)
            XCTAssertEqual(store.config(for: "xinmanhua")?.filters, xinmanhua.filters)
            XCTAssertFalse(store.isEnabled("mkzhan"))
            XCTAssertEqual(store.config(for: "mkzhan")?.route("search"), "/imported-search?keyword={keyword}")
        }
    }

    func testAuditedUnconsumedRoutesReportOverridesAndPreserveValues() throws {
        try withStore { store in
            let fields: [String: [String]] = [
                "gmh": ["latest"], "mh160": ["chapter"], "mh18": ["latest", "chapter"],
                "mkzhan": ["chapter"], "manben": ["latest", "chapter"],
                "manhuazhan": ["latest", "category", "chapter"], "bbyin": ["latest", "category", "chapter"],
                "cuimh": ["latest", "search", "category", "chapter"], "liumanhua": ["latest", "category", "chapter"],
                "copy4000": ["chapters", "chapter"], "dongmanla": ["category", "chapter"],
                "jmcomic": ["chapter"], "hanman18": ["category", "chapter"]
            ]
            let items: [[String: Any]] = fields.keys.sorted().map { id in
                ["id": id, "routes": Dictionary(uniqueKeysWithValues: fields[id]!.map { ($0, "/unused-" + $0) })]
            }
            let original = Dictionary(uniqueKeysWithValues: fields.keys.map { ($0, store.config(for: $0)!) })
            let data = try JSONSerialization.data(withJSONObject: ["schema": "xx-comic.sources", "version": 2, "sources": items])
            let result = try store.importConfig(jsonString: String(decoding: data, as: UTF8.self))
            for (id, keys) in fields {
                for key in keys {
                    XCTAssertTrue(result.warnings.contains { $0.contains(id + ".routes." + key) }, id + "." + key)
                    XCTAssertEqual(store.config(for: id)?.route(key), original[id]?.route(key), id + "." + key)
                }
            }
            XCTAssertEqual(result.totalSources, fields.count)
            XCTAssertEqual(store.orderedIDs.count, 51)
        }
    }
}
