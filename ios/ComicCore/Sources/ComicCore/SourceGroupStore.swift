import Foundation

public enum SourceGroupError: LocalizedError, Equatable {
    case emptyName(String)
    case duplicateName(String)
    case builtinImmutable(String)
    case notFound(String)
    case storageFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName(let msg): return msg
        case .duplicateName(let msg): return msg
        case .builtinImmutable(let msg): return msg
        case .notFound(let msg): return msg
        case .storageFailed(let msg): return msg
        }
    }
}

public struct SourceGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public let isBuiltin: Bool
    public var sourceIds: [String]

    public init(id: String, name: String, isBuiltin: Bool, sourceIds: [String]) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isBuiltin = isBuiltin
        var seen = Set<String>()
        self.sourceIds = sourceIds.compactMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}

public final class SourceGroupStore: @unchecked Sendable {
    public static let allId = "builtin_source_all"
    public static let defaultGroupName = "全部"

    private struct JSONFile: Codable {
        var version: Int
        var selectedId: String?
        var legacyMigrated: Bool?
        var groups: [GroupJSON]
    }

    private struct GroupJSON: Codable {
        var id: String
        var name: String
        var sourceIds: [String]
    }

    private let lock = NSLock()
    private let primaryURL: URL
    private let backupURL: URL
    private let tempURL: URL

    private var _groups: [SourceGroup] = initialGroups()
    private var _selectedId: String = allId
    private var _recoveryMessage: String = ""
    private var _writable: Bool = true
    private var _legacyMigrated: Bool = false

    public init(directory: URL) {
        self.primaryURL = directory.appendingPathComponent("source_groups.json")
        self.backupURL = directory.appendingPathComponent("source_groups.json.bak")
        self.tempURL = directory.appendingPathComponent("source_groups.json.tmp")
        load()
    }

    public var groups: [SourceGroup] {
        lock.lock()
        defer { lock.unlock() }
        return _groups
    }

    public var currentGroup: SourceGroup {
        lock.lock()
        defer { lock.unlock() }
        return _groups.first { $0.id == _selectedId } ?? _groups[0]
    }

    public var selectedId: String {
        lock.lock()
        defer { lock.unlock() }
        return _selectedId
    }

    public var recoveryMessage: String {
        lock.lock()
        defer { lock.unlock() }
        return _recoveryMessage
    }

    @discardableResult
    public func create(name: String, sourceIds: [String] = []) throws -> SourceGroup {
        lock.lock()
        defer { lock.unlock() }
        let cleanName = try validNameLocked(name, ignoreId: nil)
        let group = SourceGroup(id: "source_" + UUID().uuidString.lowercased(),
                                name: cleanName,
                                isBuiltin: false,
                                sourceIds: sourceIds)
        var next = _groups
        next.append(group)
        try commitLocked(next: next, currentId: _selectedId)
        return group
    }

    public func rename(id: String, to rawName: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let old = try editableLocked(id)
        let cleanName = try validNameLocked(rawName, ignoreId: id)
        let replacement = SourceGroup(id: id, name: cleanName, isBuiltin: false, sourceIds: old.sourceIds)
        try replaceLocked(replacement)
    }

    public func setSources(id: String, sourceIds: [String]) throws {
        lock.lock()
        defer { lock.unlock() }
        let old = try editableLocked(id)
        let replacement = SourceGroup(id: id, name: old.name, isBuiltin: false, sourceIds: sourceIds)
        try replaceLocked(replacement)
    }

    public func delete(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let old = try editableLocked(id)
        var next = _groups
        next.removeAll { $0.id == old.id }
        let nextSelectedId = (id == _selectedId) ? Self.allId : _selectedId
        try commitLocked(next: next, currentId: nextSelectedId)
    }

    public func select(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard _groups.contains(where: { $0.id == id }) else {
            throw SourceGroupError.notFound("分组已不存在")
        }
        try commitLocked(next: _groups, currentId: id)
    }

    public func visibleSources<T>(_ enabled: [T], idExtractor: (T) -> String) -> [T] {
        lock.lock()
        let group = _groups.first { $0.id == _selectedId } ?? _groups[0]
        lock.unlock()

        if group.isBuiltin {
            return enabled
        }
        let idSet = Set(group.sourceIds)
        return enabled.filter { idSet.contains(idExtractor($0)) }
    }

    // MARK: - Private Helpers

    private static func initialGroups() -> [SourceGroup] {
        [SourceGroup(id: allId, name: defaultGroupName, isBuiltin: true, sourceIds: [])]
    }

    private func editableLocked(_ id: String) throws -> SourceGroup {
        guard let group = _groups.first(where: { $0.id == id }) else {
            throw SourceGroupError.notFound("分组已不存在")
        }
        if group.isBuiltin {
            throw SourceGroupError.builtinImmutable("全部分组不可修改")
        }
        return group
    }

    private func validNameLocked(_ raw: String, ignoreId: String?) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw SourceGroupError.emptyName("分组名称不能为空")
        }
        for g in _groups {
            if g.id != ignoreId && g.name.caseInsensitiveCompare(trimmed) == .orderedSame {
                throw SourceGroupError.duplicateName("分组名称已存在")
            }
        }
        return trimmed
    }

    private func replaceLocked(_ replacement: SourceGroup) throws {
        var next = _groups
        guard let index = next.firstIndex(where: { $0.id == replacement.id }) else {
            throw SourceGroupError.notFound("分组已不存在")
        }
        next[index] = replacement
        try commitLocked(next: next, currentId: _selectedId)
    }

    private func load() {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        if fm.fileExists(atPath: primaryURL.path) {
            do {
                try decodeLocked(from: primaryURL)
                return
            } catch {
                let corruptPath = primaryURL.path + ".corrupt." + String(Int(Date().timeIntervalSince1970 * 1000))
                try? fm.copyItem(atPath: primaryURL.path, toPath: corruptPath)
                _recoveryMessage = "分组文件损坏，原文件已备份"
            }
        }

        if fm.fileExists(atPath: backupURL.path) {
            do {
                try decodeLocked(from: backupURL)
                try? fm.removeItem(at: primaryURL)
                try? fm.copyItem(at: backupURL, to: primaryURL)
                _recoveryMessage = "分组文件已从备份恢复，请检查当前分组"
            } catch {
                _groups = Self.initialGroups()
                _selectedId = Self.allId
                _writable = false
                _recoveryMessage = "分组与备份无法读取，原数据已保留；请修复文件后重启"
            }
        }
    }

    private func decodeLocked(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let root = try JSONDecoder().decode(JSONFile.self, from: data)
        guard root.version == 1 else {
            throw SourceGroupError.storageFailed("未知分组版本: \(root.version)")
        }

        var loaded = Self.initialGroups()
        var ids = Set<String>([Self.allId])
        var names = Set<String>([Self.defaultGroupName.lowercased()])

        for entry in root.groups {
            let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if id == Self.allId { continue }
            guard !id.isEmpty, !name.isEmpty, ids.insert(id).inserted, names.insert(name.lowercased()).inserted else {
                throw SourceGroupError.storageFailed("无效分组项: \(id)")
            }
            loaded.append(SourceGroup(id: id, name: name, isBuiltin: false, sourceIds: entry.sourceIds))
        }

        _groups = loaded
        let current = root.selectedId ?? Self.allId
        _selectedId = ids.contains(current) ? current : Self.allId
        _legacyMigrated = root.legacyMigrated ?? false
    }

    private func commitLocked(next: [SourceGroup], currentId: String) throws {
        guard _writable else {
            throw SourceGroupError.storageFailed(_recoveryMessage.isEmpty ? "分组存储为只读模式" : _recoveryMessage)
        }

        let fm = FileManager.default
        let dir = primaryURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let nonBuiltin = next.filter { !$0.isBuiltin }.map { GroupJSON(id: $0.id, name: $0.name, sourceIds: $0.sourceIds) }
        let root = JSONFile(version: 1, selectedId: currentId, legacyMigrated: _legacyMigrated, groups: nonBuiltin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(root)

        try data.write(to: tempURL, options: .atomic)

        if fm.fileExists(atPath: primaryURL.path) {
            _ = try? fm.removeItem(at: backupURL)
            try fm.moveItem(at: primaryURL, to: backupURL)
        }
        try fm.moveItem(at: tempURL, to: primaryURL)

        _groups = next
        _selectedId = currentId
    }
}
