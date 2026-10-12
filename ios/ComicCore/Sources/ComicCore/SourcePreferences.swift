import Foundation

public final class SourcePreferences {
    private let defaults: UserDefaults
    private let defaultIDs: [String]
    public init(defaults: UserDefaults, defaultIDs: [String]) {
        self.defaults = defaults
        self.defaultIDs = defaultIDs
    }
    public static func canonicalID(_ id: String) -> String {
        switch id {
        case "five_um": return "manhuazhan"
        case "copymanga": return "copy4000"
        default: return id
        }
    }

    public static func legacyAliases(for id: String) -> [String] {
        let canonical = canonicalID(id)
        switch canonical {
        case "manhuazhan": return ["five_um"]
        case "copy4000": return ["copymanga"]
        default: return []
        }
    }

    public var orderedIDs: [String] {
        let json = defaults.string(forKey: "source.order") ?? "[]"
        let values = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any] ?? []
        let mapped = values.compactMap { ($0 as? String).map(Self.canonicalID) }
        return SourceOrder.normalize(mapped, available: defaultIDs)
    }
    public var enabledIDs: [String] { orderedIDs.filter(isEnabled) }
    public func isEnabled(_ id: String) -> Bool {
        let canonical = Self.canonicalID(id)
        guard defaultIDs.contains(canonical) || defaultIDs.contains(id) else { return false }
        if let val = defaults.object(forKey: "source.\(canonical).enabled") as? Bool {
            return val
        }
        for alias in Self.legacyAliases(for: id) {
            if let legacyVal = defaults.object(forKey: "source.\(alias).enabled") as? Bool {
                defaults.set(legacyVal, forKey: "source.\(canonical).enabled")
                return legacyVal
            }
        }
        if canonical != id, let directVal = defaults.object(forKey: "source.\(id).enabled") as? Bool {
            defaults.set(directVal, forKey: "source.\(canonical).enabled")
            return directVal
        }
        return SourceConfigDefaults.defaultConfig(for: canonical)?.enabled ?? true
    }
    public func setEnabled(_ enabled: Bool, id: String) {
        let canonical = Self.canonicalID(id)
        guard defaultIDs.contains(canonical) || defaultIDs.contains(id) else { return }
        defaults.set(enabled, forKey: "source.\(canonical).enabled")
        for alias in Self.legacyAliases(for: id) {
            defaults.set(enabled, forKey: "source.\(alias).enabled")
        }
        if canonical != id {
            defaults.set(enabled, forKey: "source.\(id).enabled")
        }
    }
    public func setOrder(_ ids: [String]) {
        let mapped = ids.map(Self.canonicalID)
        // An array of strings always has a JSON representation.
        guard let data = try? JSONEncoder().encode(SourceOrder.normalize(mapped, available: defaultIDs)), let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: "source.order")
    }
    public func resetOrder() { setOrder(defaultIDs) }

    public func config(for sourceId: String) -> SourceConfigItem? {
        let canonical = Self.canonicalID(sourceId)
        if let data = defaults.data(forKey: "source.\(canonical).config"),
           let item = try? JSONDecoder().decode(SourceConfigItem.self, from: data) {
            return item
        }
        for alias in Self.legacyAliases(for: sourceId) {
            if let legacyData = defaults.data(forKey: "source.\(alias).config"),
               let item = try? JSONDecoder().decode(SourceConfigItem.self, from: legacyData) {
                return item
            }
        }
        if canonical != sourceId,
           let directData = defaults.data(forKey: "source.\(sourceId).config"),
           let item = try? JSONDecoder().decode(SourceConfigItem.self, from: directData) {
            return item
        }
        return SourceConfigDefaults.defaultConfig(for: canonical) ?? SourceConfigDefaults.defaultConfig(for: sourceId)
    }

    public func setConfig(_ item: SourceConfigItem, for sourceId: String) {
        let canonical = Self.canonicalID(sourceId)
        guard defaultIDs.contains(canonical) || defaultIDs.contains(sourceId) else { return }
        if let data = try? JSONEncoder().encode(item) {
            defaults.set(data, forKey: "source.\(canonical).config")
            for alias in Self.legacyAliases(for: sourceId) {
                defaults.set(data, forKey: "source.\(alias).config")
            }
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
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw SourceConfigError.invalidJSON }
        guard (json["schema"] as? String) == "xx-comic.sources" else { throw SourceConfigError.invalidSchema }
        struct Header: Decodable { let version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw SourceConfigError.invalidFields }
        guard header.version == nil || [1, 2].contains(header.version!) else { throw SourceConfigError.unsupportedVersion }
        if let sources = json["sources"], !(sources is [[String: Any]]) { throw SourceConfigError.invalidFields }
        if let order = json["sourceOrder"], !(order is [String]) { throw SourceConfigError.invalidFields }
        if let custom = json["custom"], !(custom is [[String: Any]]) { throw SourceConfigError.invalidFields }
        let sources = json["sources"] as? [[String: Any]] ?? []
        let order = json["sourceOrder"] as? [String] ?? []
        let custom = json["custom"] as? [[String: Any]] ?? []
        guard !sources.isEmpty || !order.isEmpty || !custom.isEmpty else { throw SourceConfigError.emptyPackage }

        // Prepare and validate the entire import before persisting any order, switch or endpoint.
        var prepared: [SourceConfigItem] = [], seen = Set<String>(), skipped: [String] = [], warnings: [String] = []
        for item in sources {
            guard let rawID = item["id"] as? String, !rawID.isEmpty else { throw SourceConfigError.invalidFields }
            let id = Self.canonicalID(rawID)
            guard defaultIDs.contains(id) || defaultIDs.contains(rawID) else {
                skipped.append(rawID); warnings.append("已跳过非当前站源：" + rawID); continue
            }
            guard seen.insert(id).inserted else { throw SourceConfigError.invalidFields }
            let fallback = (config(for: id) ?? SourceConfigItem(id: id, name: id)).withEnabled(isEnabled(id))
            let encoder = JSONEncoder()
            let baseData = try encoder.encode(fallback)
            var normalized = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
            let originalFields = normalized
            let supported = SourceConfigDefaults.defaultConfig(for: id) ?? fallback
            // These exported fields have no consumer in the current source
            // interface. Preserve unchanged compatibility values, but report
            // attempted overrides rather than pretending they affect requests.
            let unusedRoutes = Self.unconsumedRoutes(for: id)
            for key in ["name", "domain", "baseUrl", "referer", "latestPath", "searchPath", "categoryPath", "detailPath", "enabled"] {
                if let value = item[key] { normalized[key] = value }
            }
            normalized["id"] = id
            // Old flat paths must reach the same route consumers as v2 routes.
            // An explicit v2 route takes precedence over its legacy flat field.
            var legacyRoutes = normalized["routes"] as? [String: String] ?? [:]
            let explicitRoutes = item["routes"] as? [String: String] ?? [:]
            for (field, route) in [("latestPath", "latest"), ("searchPath", "search"), ("categoryPath", "category"), ("detailPath", "detail")] {
                if let path = item[field] as? String {
                    let routeAvailable = supported.routes?[route] != nil || !supported.route(route).isEmpty
                    if !routeAvailable || unusedRoutes.contains(route) {
                        if path != (originalFields[field] as? String) {
                            warnings.append("已跳过不支持的字段：" + id + "." + field + "（当前请求不消费该字段）")
                        }
                        normalized[field] = originalFields[field]
                    } else if explicitRoutes[route] == nil { legacyRoutes[route] = path }
                }
            }
            normalized["routes"] = legacyRoutes
            for key in ["routes", "filters"] {
                guard let overrides = item[key] else { continue }
                guard let mapping = overrides as? [String: String] else { throw SourceConfigError.invalidFields }
                let defaultsMapping = key == "routes" ? supported.routes : supported.filters
                let allowed = Set(defaultsMapping?.keys.map { $0 } ?? [])
                var merged = (normalized[key] as? [String: String]) ?? [:]
                for (field, value) in mapping {
                    guard allowed.contains(field) else {
                        warnings.append("已跳过不支持的字段：" + id + "." + key + "." + field); continue
                    }
                    let unusedFilter = key == "filters" && (id == "manhuagui" || (id == "d5d6" && (field.hasPrefix("category.") || field == "state.all")) || (id == "manben" && field == "sort.popular") || id == "hanman18")
                    if key == "routes" && unusedRoutes.contains(field) || unusedFilter {
                        if value != merged[field] {
                            warnings.append("已跳过不支持的字段：" + id + "." + key + "." + field + "（当前请求不消费该字段）")
                        }
                        continue
                    }
                    merged[field] = value
                }
                normalized[key] = merged
            }
            let normalizedData = try JSONSerialization.data(withJSONObject: normalized)
            guard let config = try? JSONDecoder().decode(SourceConfigItem.self, from: normalizedData) else { throw SourceConfigError.invalidFields }
            for address in [config.baseUrl, config.referer] where !address.isEmpty {
                guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw SourceConfigError.invalidFields }
            }
            prepared.append(config)
        }
        for (index, item) in custom.enumerated() {
            let id = item["id"] as? String ?? "自定义站源（第\(index + 1)项）"
            skipped.append(id)
            warnings.append("已跳过自定义站源：" + id + "（当前版本尚不支持自定义解析器）")
        }
        for config in prepared {
            setConfig(config, for: config.id)
            setEnabled(config.enabled, id: config.id)
        }
        if !order.isEmpty { setOrder(order) }
        let enabledCount = prepared.filter(\.enabled).count
        return SourceImportResult(totalSources: prepared.count, enabledCount: enabledCount, disabledCount: prepared.count - enabledCount,
                                  orderUpdated: !order.isEmpty, skippedSources: skipped, warnings: warnings)
    }

    // Retained Android export fields that do not reach the current request path.
    // Category helpers and directory-provided chapter URLs are the consumers.
    private static func unconsumedRoutes(for id: String) -> Set<String> {
        if PublicSourceRegistry.contains(id) { return ["latest", "search", "category", "detail", "chapter"] }
        switch id {
        case "gmh", "d5d6": return ["latest"]
        case "mh160", "mkzhan", "hiperdex": return ["chapter"]
        case "jmcomic": return ["category", "chapter"]
        case "mh18", "manhuagui", "manben": return ["latest", "chapter"]
        case "manhuazhan", "bbyin", "liumanhua": return ["latest", "category", "chapter"]
        case "cuimh": return ["latest", "search", "category", "chapter"]
        case "copy4000": return ["chapters", "chapter"]
        case "dongmanla", "hanman18": return ["category", "chapter"]
        default: return []
        }
    }
}
