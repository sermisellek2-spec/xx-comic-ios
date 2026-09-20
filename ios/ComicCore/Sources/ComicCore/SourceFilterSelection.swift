public enum SourceFilterSelection {
    public static func select(sourceID: String, key: String, value: String,
                              groupKeys: [String], in selection: inout [String: String]) {
        selection[key] = value
        if value != "all" && ["mh160", "gmh", "mh18", "jmcomic"].contains(sourceID) {
            for otherKey in groupKeys where otherKey != key {
                selection[otherKey] = "all"
            }
        }
    }
}
