import Foundation

/// The IDs used by source management, discovery, search, and configuration import/export.
public enum BuiltinSourceCatalog {
    public static let dedicatedIDs = [
        "mh160", "gmh", "mh18", "jmcomic", "mkzhan", "hiperdex", "manhuagui", "hanman18",
        "d5d6", "manben", "manhuazhan", "bbyin", "antbyw", "cuimh", "liumanhua", "copy4000",
        "manwa", "dingmanhua", "dongmanla", "xinmanhua", "zaimanhua", "guazi"
    ]
    public static var activeIDs: [String] {
        dedicatedIDs + PublicSourceRegistry.ids()
    }
    public static let retiredIDs = ["baozimh", "mhua5"]
}
