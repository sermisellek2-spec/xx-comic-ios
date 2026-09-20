import Foundation

public final class SourcePreferences {
    private let defaults: UserDefaults
    private let defaultIDs: [String]
    public init(defaults: UserDefaults, defaultIDs: [String]) {
        self.defaults = defaults
        self.defaultIDs = defaultIDs
    }
    public var orderedIDs: [String] {
        let json = defaults.string(forKey: "source.order") ?? "[]"
        let values = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any] ?? []
        return SourceOrder.normalize(values.compactMap { $0 as? String }, available: defaultIDs)
    }
    public var enabledIDs: [String] { orderedIDs.filter(isEnabled) }
    public func isEnabled(_ id: String) -> Bool {
        defaultIDs.contains(id) && ((defaults.object(forKey: "source.\(id).enabled") as? Bool) ?? true)
    }
    public func setEnabled(_ enabled: Bool, id: String) {
        guard defaultIDs.contains(id) else { return }
        defaults.set(enabled, forKey: "source.\(id).enabled")
    }
    public func setOrder(_ ids: [String]) {
        // An array of strings always has a JSON representation.
        guard let data = try? JSONEncoder().encode(SourceOrder.normalize(ids, available: defaultIDs)), let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: "source.order")
    }
    public func resetOrder() { setOrder(defaultIDs) }

    public func config(for sourceId: String) -> SourceConfigItem? {
        if let data = defaults.data(forKey: "source.\(sourceId).config"),
           let item = try? JSONDecoder().decode(SourceConfigItem.self, from: data) {
            return item
        }
        return SourceConfigDefaults.defaultConfig(for: sourceId)
    }

    public func setConfig(_ item: SourceConfigItem, for sourceId: String) {
        guard defaultIDs.contains(sourceId) else { return }
        if let data = try? JSONEncoder().encode(item) {
            defaults.set(data, forKey: "source.\(sourceId).config")
        }
    }

    public func exportConfig(sources: [(id: String, name: String, domain: String, referer: String)]) -> String {
        let order = orderedIDs
        let items = sources.map { s -> SourceConfigItem in
            let existing = config(for: s.id)
            let base = s.referer.hasSuffix("/") ? String(s.referer.dropLast()) : s.referer
            return SourceConfigItem(
                id: s.id,
                name: s.name,
                domain: (existing?.domain.isEmpty == false) ? existing!.domain : s.domain,
                baseUrl: (existing?.baseUrl.isEmpty == false) ? existing!.baseUrl : base,
                referer: (existing?.referer.isEmpty == false) ? existing!.referer : s.referer,
                latestPath: existing?.latestPath ?? "",
                searchPath: existing?.searchPath ?? "",
                categoryPath: existing?.categoryPath ?? "",
                detailPath: existing?.detailPath ?? "",
                enabled: isEnabled(s.id),
                routes: existing?.routes,
                filters: existing?.filters
            )
        }
        let package = SourceExportPackage(
            schema: "xx-comic.sources",
            version: 2,
            exportedAt: Int64(Date().timeIntervalSince1970 * 1000),
            sourceOrder: order,
            sources: items,
            custom: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(package), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }

    public func importConfig(jsonString: String) throws -> SourceImportResult {
        guard let data = jsonString.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SourceConfigError.invalidJSON
        }
        guard (json["schema"] as? String) == "xx-comic.sources" else {
            throw SourceConfigError.invalidSchema
        }
        let sourcesArray = json["sources"] as? [[String: Any]] ?? []
        let sourceOrderArray = json["sourceOrder"] as? [String] ?? []
        if sourcesArray.isEmpty && sourceOrderArray.isEmpty {
            throw SourceConfigError.emptyPackage
        }

        var orderUpdated = false
        if !sourceOrderArray.isEmpty {
            setOrder(sourceOrderArray)
            orderUpdated = true
        }

        var enabledCount = 0
        var disabledCount = 0
        var total = 0
        for item in sourcesArray {
            guard let id = item["id"] as? String, defaultIDs.contains(id) else { continue }
            total += 1
            let enabled = item["enabled"] as? Bool ?? true
            setEnabled(enabled, id: id)
            if enabled {
                enabledCount += 1
            } else {
                disabledCount += 1
            }

            if let itemData = try? JSONSerialization.data(withJSONObject: item),
               let configItem = try? JSONDecoder().decode(SourceConfigItem.self, from: itemData) {
                setConfig(configItem, for: id)
            }
        }

        return SourceImportResult(
            totalSources: total,
            enabledCount: enabledCount,
            disabledCount: disabledCount,
            orderUpdated: orderUpdated
        )
    }
}
