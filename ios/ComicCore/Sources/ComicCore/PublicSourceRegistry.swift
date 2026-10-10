import Foundation

public struct PublicSourceProfile: Sendable {
    public let id: String
    public let name: String
    public let available: Bool
    public let base: String
    public let family: String
    public let detailPattern: String
    public let cards: String
    public let catalog: String
    public let reader: String
    public let search: String
    public let latest: String
    public let filters: [(label: String, path: String)]
    public let filterGroups: [SourceFilterGroup]?
    public let network: String
    public let notice: String
    public let sampleDetail: String
    public let sampleChapter: String
    public let decoder: String
    public let readerPagination: Bool
    public let reverseCatalog: Bool
    public let defaultEnabled: Bool
    public let authEndpoint: String
    public let auditIndex: Int
}

public enum PublicSourceRegistry {
    private static let loaded: (ids: [String], map: [String: PublicSourceProfile]) = loadProfiles()

    private static func loadProfiles() -> (ids: [String], map: [String: PublicSourceProfile]) {
        let url = Bundle.module.url(forResource: "public-sources", withExtension: "json")
            ?? Bundle.module.url(forResource: "public-sources", withExtension: "json", subdirectory: "Resources")
        guard let url,
              let data = try? Data(contentsOf: url),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            fatalError("Invalid public source profiles")
        }
        var orderedIds: [String] = []
        var map: [String: PublicSourceProfile] = [:]
        for item in array {
            guard (item["available"] as? Bool) == true,
                  let id = item["id"] as? String, !id.isEmpty else {
                continue
            }
            var parsedFilters: [(label: String, path: String)] = []
            if let fArr = item["filters"] as? [[String: Any]] {
                for f in fArr {
                    let label = (f["label"] as? String) ?? ""
                    let path = (f["path"] as? String) ?? ""
                    parsedFilters.append((label: label, path: path))
                }
            }
            var parsedGroups: [SourceFilterGroup]? = nil
            if let fgArr = item["filterGroups"] as? [[String: Any]] {
                var groups: [SourceFilterGroup] = []
                for g in fgArr {
                    guard let key = g["key"] as? String,
                          let label = g["label"] as? String,
                          let optArr = g["options"] as? [[String: Any]] else { continue }
                    let opts: [SourceFilterOption] = optArr.compactMap { o in
                        guard let oLabel = o["label"] as? String,
                              let oValue = o["value"] as? String else { return nil }
                        return SourceFilterOption(label: oLabel, value: oValue)
                    }
                    groups.append(SourceFilterGroup(key: key, label: label, options: opts))
                }
                parsedGroups = groups
            }
            let profile = PublicSourceProfile(
                id: id,
                name: (item["name"] as? String) ?? id,
                available: true,
                base: (item["base"] as? String) ?? "",
                family: (item["family"] as? String) ?? "",
                detailPattern: (item["detailPattern"] as? String) ?? "",
                cards: (item["cards"] as? String) ?? "",
                catalog: (item["catalog"] as? String) ?? "",
                reader: (item["reader"] as? String) ?? "",
                search: (item["search"] as? String) ?? "",
                latest: (item["latest"] as? String) ?? "",
                filters: parsedFilters,
                filterGroups: parsedGroups,
                network: (item["network"] as? String) ?? "",
                notice: (item["notice"] as? String) ?? "",
                sampleDetail: (item["sampleDetail"] as? String) ?? "",
                sampleChapter: (item["sampleChapter"] as? String) ?? "",
                decoder: (item["decoder"] as? String) ?? "",
                readerPagination: (item["readerPagination"] as? Bool) ?? false,
                reverseCatalog: (item["reverseCatalog"] as? Bool) ?? false,
                defaultEnabled: (item["defaultEnabled"] as? Bool) ?? true,
                authEndpoint: (item["authEndpoint"] as? String) ?? "",
                auditIndex: (item["auditIndex"] as? Int) ?? 1
            )
            orderedIds.append(id)
            map[id] = profile
        }
        return (orderedIds, map)
    }

    public static func profile(_ id: String) throws -> PublicSourceProfile {
        guard let p = loaded.map[id] else {
            throw NSError(domain: "PublicSourceRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown public source: \(id)"])
        }
        return p
    }

    public static func contains(_ id: String) -> Bool {
        loaded.map[id] != nil
    }

    public static func ids() -> [String] {
        loaded.ids
    }

    public static func networkHint(_ id: String) -> String {
        loaded.map[id]?.network ?? ""
    }

    public static func capabilityHint(_ id: String) -> String {
        loaded.map[id]?.notice ?? ""
    }

    public static func config(_ id: String) -> SourceConfigItem {
        guard let p = loaded.map[id], let host = URL(string: p.base)?.host else {
            preconditionFailure("Unknown public source: \(id)")
        }
        return SourceConfigItem(
            id: id,
            name: p.name,
            domain: host,
            baseUrl: p.base,
            referer: p.base + "/",
            latestPath: "",
            searchPath: "",
            categoryPath: "",
            detailPath: "",
            enabled: p.defaultEnabled,
            routes: [:],
            filters: [:]
        )
    }

    public static func defaults() -> [String: SourceConfigItem] {
        var result: [String: SourceConfigItem] = [:]
        for id in loaded.ids {
            result[id] = config(id)
        }
        return result
    }

    public static func orderedDefaults() -> [SourceConfigItem] {
        loaded.ids.map { config($0) }
    }

    public static func create(_ config: SourceConfigItem, transport: any HTTPTransport = URLSessionHTTPTransport()) -> PublicComicSource {
        PublicComicSource(config: config, transport: transport)
    }
}
