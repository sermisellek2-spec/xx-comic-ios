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
}
