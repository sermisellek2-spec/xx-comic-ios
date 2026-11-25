import Foundation

public enum SourceFilterSelection {
    public static let allTag = "全部"

    public static func select(sourceID: String, key: String, value: String,
                              groupKeys: [String], in selection: inout [String: String]) {
        selection[key] = value
        if value != "all" && ["mh160", "gmh", "mh18", "jmcomic"].contains(sourceID) {
            for otherKey in groupKeys where otherKey != key {
                selection[otherKey] = "all"
            }
        }
    }

    public static func isDefaultOptionLabel(_ option: SourceFilterOption?) -> Bool {
        guard let label = option?.label.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else {
            return false
        }
        switch label {
        case allTag, "默认", "不限",
             "全部题材", "全部地区", "全部状态", "全部分类",
             "默认排序", "全部排序", "综合排序",
             "更新时间", "最新更新", "最近更新", "按更新", "更新", "最新":
            return true
        default:
            return label.lowercased() == "all"
        }
    }

    public static func isDefaultFilterOption(
        group: SourceFilterGroup?,
        option: SourceFilterOption?
    ) -> Bool {
        guard let option else { return true }
        if option.value.isEmpty || option.value.lowercased() == "all" {
            return true
        }
        if let first = group?.options.first,
           option.value == first.value,
           isDefaultOptionLabel(first) {
            return true
        }
        return false
    }

    public static func hasAnyExclusiveGroup(_ groups: [SourceFilterGroup]) -> Bool {
        groups.contains { !$0.options.isEmpty && !$0.exclusiveGroup.isEmpty }
    }

    public static func isPartialMutexFilterSchema(_ groups: [SourceFilterGroup]) -> Bool {
        var validCount = 0
        var exclusiveCount = 0
        var exclusiveNames = Set<String>()
        for g in groups where !g.options.isEmpty {
            validCount += 1
            if !g.exclusiveGroup.isEmpty {
                exclusiveCount += 1
                exclusiveNames.insert(g.exclusiveGroup)
            }
        }
        return exclusiveCount > 0 && !(exclusiveCount == validCount && exclusiveNames.count == 1)
    }

    public static func filterMutexNote(_ groups: [SourceFilterGroup]) -> String? {
        var validCount = 0
        var exclusiveCount = 0
        var exclusiveNames = Set<String>()
        for g in groups where !g.options.isEmpty {
            validCount += 1
            if !g.exclusiveGroup.isEmpty {
                exclusiveCount += 1
                exclusiveNames.insert(g.exclusiveGroup)
            }
        }
        if exclusiveCount == 0 { return nil }
        if exclusiveCount == validCount && exclusiveNames.count == 1 {
            return "原站仅支持单条件筛选，切换分类会重置其他互斥项"
        }
        return "部分筛选条件受原站限制互斥，标注以外条件可叠加组合"
    }

    public static func resetFilterGroupToDefault(
        _ group: SourceFilterGroup,
        selectedFilters: inout [String: String],
        selectedFilterLabels: inout [String: String],
        defaultLabel: String = allTag
    ) {
        guard !group.key.isEmpty else { return }
        let fallbackLabel = defaultLabel.isEmpty ? allTag : defaultLabel
        if !group.options.isEmpty {
            if let allOpt = group.options.first(where: { $0.value.lowercased() == "all" }) {
                selectedFilters[group.key] = allOpt.value
                selectedFilterLabels[group.key] = allOpt.label.isEmpty ? fallbackLabel : allOpt.label
                return
            }
            let first = group.options[0]
            selectedFilters[group.key] = first.value
            selectedFilterLabels[group.key] = first.label.isEmpty ? fallbackLabel : first.label
            return
        }
        selectedFilters[group.key] = "all"
        selectedFilterLabels[group.key] = fallbackLabel
    }

    public static func resetFilterGroupToDefault(
        _ group: SourceFilterGroup,
        selectedFilters: inout [String: String]
    ) {
        var ignoredLabels: [String: String] = [:]
        resetFilterGroupToDefault(group, selectedFilters: &selectedFilters, selectedFilterLabels: &ignoredLabels)
    }

    @discardableResult
    public static func applyExclusiveFilterReset(
        groups: [SourceFilterGroup],
        selectedGroup: SourceFilterGroup,
        selectedOption: SourceFilterOption,
        selectedFilters: inout [String: String],
        selectedFilterLabels: inout [String: String],
        defaultLabel: String = allTag
    ) -> [String] {
        guard !selectedGroup.exclusiveGroup.isEmpty,
              !isDefaultFilterOption(group: selectedGroup, option: selectedOption) else {
            return []
        }
        var resetKeys: [String] = []
        for other in groups {
            guard !other.key.isEmpty, other.key != selectedGroup.key else { continue }
            if selectedGroup.exclusiveGroup == other.exclusiveGroup {
                resetFilterGroupToDefault(
                    other,
                    selectedFilters: &selectedFilters,
                    selectedFilterLabels: &selectedFilterLabels,
                    defaultLabel: defaultLabel
                )
                resetKeys.append(other.key)
            }
        }
        return resetKeys
    }

    @discardableResult
    public static func applyExclusiveFilterReset(
        groups: [SourceFilterGroup],
        selectedGroup: SourceFilterGroup,
        selectedOption: SourceFilterOption,
        selectedFilters: inout [String: String]
    ) -> [String] {
        var ignoredLabels: [String: String] = [:]
        return applyExclusiveFilterReset(
            groups: groups,
            selectedGroup: selectedGroup,
            selectedOption: selectedOption,
            selectedFilters: &selectedFilters,
            selectedFilterLabels: &ignoredLabels
        )
    }

    /// Full Android 2.0.54-2.0.56 selection logic supporting `exclusiveGroup` mutex groups
    /// while preserving legacy fallback for built-in non-rule sources (`mh160/gmh/mh18/jmcomic`).
    @discardableResult
    public static func select(
        sourceID: String,
        isRuleSource: Bool = false,
        groups: [SourceFilterGroup],
        selectedGroup: SourceFilterGroup,
        selectedOption: SourceFilterOption,
        in selection: inout [String: String],
        labels: inout [String: String],
        defaultLabel: String = allTag
    ) -> [String] {
        selection[selectedGroup.key] = selectedOption.value
        labels[selectedGroup.key] = selectedOption.label

        let resetExclusiveKeys = applyExclusiveFilterReset(
            groups: groups,
            selectedGroup: selectedGroup,
            selectedOption: selectedOption,
            selectedFilters: &selection,
            selectedFilterLabels: &labels,
            defaultLabel: defaultLabel
        )
        if !resetExclusiveKeys.isEmpty {
            return resetExclusiveKeys
        }

        if !isRuleSource,
           !hasAnyExclusiveGroup(groups),
           !isDefaultFilterOption(group: selectedGroup, option: selectedOption),
           ["mh160", "gmh", "mh18", "jmcomic"].contains(sourceID) {
            var legacyResetKeys: [String] = []
            for other in groups where other.key != selectedGroup.key {
                resetFilterGroupToDefault(
                    other,
                    selectedFilters: &selection,
                    selectedFilterLabels: &labels,
                    defaultLabel: defaultLabel
                )
                legacyResetKeys.append(other.key)
            }
            return legacyResetKeys
        }
        return []
    }
}
