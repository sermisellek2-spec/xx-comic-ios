import Foundation

public enum BookshelfScope: String, Codable, CaseIterable, Sendable {
    case online
    case local

    public var key: String { rawValue }

    public static func fromKey(_ key: String) -> BookshelfScope {
        if key.lowercased() == "local" { return .local }
        return .online
    }
}

public struct BookshelfGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let scope: BookshelfScope
    public var name: String
    public let isBuiltin: Bool
    public var orderIndex: Int
    public let createdAt: Int64
    public var updatedAt: Int64

    public init(id: String, scope: BookshelfScope, name: String, isBuiltin: Bool,
                orderIndex: Int, createdAt: Int64, updatedAt: Int64) {
        self.id = id
        self.scope = scope
        self.name = name
        self.isBuiltin = isBuiltin
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func withName(_ newName: String) -> BookshelfGroup {
        BookshelfGroup(id: id, scope: scope, name: newName, isBuiltin: isBuiltin,
                       orderIndex: orderIndex, createdAt: createdAt,
                       updatedAt: Int64(Date().timeIntervalSince1970 * 1000))
    }

    public func withOrderIndex(_ newOrderIndex: Int) -> BookshelfGroup {
        BookshelfGroup(id: id, scope: scope, name: name, isBuiltin: isBuiltin,
                       orderIndex: newOrderIndex, createdAt: createdAt, updatedAt: updatedAt)
    }
}

public struct BookshelfGroupDeletionSnapshot: Codable, Sendable {
    public let group: BookshelfGroup
    public let memberIds: [String]
    public let orderIndex: Int
    public let deletedAt: Int64

    public init(group: BookshelfGroup, memberIds: Set<String>, orderIndex: Int) {
        self.group = group
        self.memberIds = Array(memberIds)
        self.orderIndex = orderIndex
        self.deletedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

public final class BookshelfGroupStore: @unchecked Sendable {
    public static let builtinOnlineAllId = "builtin_online_all"
    public static let builtinLocalAllId = "builtin_local_all"
    public static let defaultGroupName = "全部"

    private struct Snapshot: Codable {
        var version: Int = 1
        var migrated: Bool = false
        var groups: [BookshelfGroup] = []
        var onlineMembers: [String: [String]] = [:]
        var localMembers: [String: [String]] = [:]
    }

    private let lock = NSLock()
    private let file: URL
    private var groupsById: [String: BookshelfGroup] = [:]
    private var onlineMembers: [String: Set<String>] = [:]
    private var localMembers: [String: Set<String>] = [:]
    private var isMigratedState: Bool = false

    public init(file: URL) {
        self.file = file
        lock.lock()
        defer { lock.unlock() }
        loadLocked()
        ensureBuiltinGroupsLocked()
        saveLocked()
    }

    private func loadLocked() {
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        isMigratedState = snapshot.migrated
        for g in snapshot.groups {
            groupsById[g.id] = g
        }
        for (k, v) in snapshot.onlineMembers {
            onlineMembers[k] = Set(v)
        }
        for (k, v) in snapshot.localMembers {
            localMembers[k] = Set(v)
        }
    }

    private func ensureBuiltinGroupsLocked() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if groupsById[Self.builtinOnlineAllId] == nil {
            let g = BookshelfGroup(id: Self.builtinOnlineAllId, scope: .online, name: Self.defaultGroupName,
                                   isBuiltin: true, orderIndex: 0, createdAt: now, updatedAt: now)
            groupsById[Self.builtinOnlineAllId] = g
            if onlineMembers[Self.builtinOnlineAllId] == nil {
                onlineMembers[Self.builtinOnlineAllId] = []
            }
        }
        if groupsById[Self.builtinLocalAllId] == nil {
            let g = BookshelfGroup(id: Self.builtinLocalAllId, scope: .local, name: Self.defaultGroupName,
                                   isBuiltin: true, orderIndex: 0, createdAt: now, updatedAt: now)
            groupsById[Self.builtinLocalAllId] = g
            if localMembers[Self.builtinLocalAllId] == nil {
                localMembers[Self.builtinLocalAllId] = []
            }
        }
    }

    private func saveLocked() {
        var snapshot = Snapshot()
        snapshot.migrated = isMigratedState
        snapshot.groups = Array(groupsById.values)
        for (k, v) in onlineMembers {
            snapshot.onlineMembers[k] = Array(v)
        }
        for (k, v) in localMembers {
            snapshot.localMembers[k] = Array(v)
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            let dir = file.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    public var isMigrated: Bool {
        lock.lock(); defer { lock.unlock() }
        return isMigratedState
    }

    public func migrateLegacyDataIfNeeded(legacyOnlineFavorites: [String]?, legacyLocalBookIds: [String]?) {
        lock.lock(); defer { lock.unlock() }
        if isMigratedState { return }
        ensureBuiltinGroupsLocked()

        if let legacyOnline = legacyOnlineFavorites {
            var all = onlineMembers[Self.builtinOnlineAllId] ?? []
            for id in legacyOnline {
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { all.insert(trimmed) }
            }
            onlineMembers[Self.builtinOnlineAllId] = all
        }

        if let legacyLocal = legacyLocalBookIds {
            var all = localMembers[Self.builtinLocalAllId] ?? []
            for id in legacyLocal {
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { all.insert(trimmed) }
            }
            localMembers[Self.builtinLocalAllId] = all
        }

        isMigratedState = true
        saveLocked()
    }

    public func getGroups(scope: BookshelfScope) -> [BookshelfGroup] {
        lock.lock(); defer { lock.unlock() }
        var list = groupsById.values.filter { $0.scope == scope }
        list.sort { a, b in
            if a.isBuiltin != b.isBuiltin { return a.isBuiltin && !b.isBuiltin }
            if a.orderIndex != b.orderIndex { return a.orderIndex < b.orderIndex }
            return a.createdAt < b.createdAt
        }
        return list
    }

    public func getGroup(id: String) -> BookshelfGroup? {
        lock.lock(); defer { lock.unlock() }
        return groupsById[id]
    }

    public func getBuiltinGroup(scope: BookshelfScope) -> BookshelfGroup? {
        let id = scope == .online ? Self.builtinOnlineAllId : Self.builtinLocalAllId
        return getGroup(id: id)
    }

    public func createGroup(scope: BookshelfScope, rawName: String) throws -> BookshelfGroup {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BookshelfGroupError.emptyName }

        lock.lock(); defer { lock.unlock() }
        if groupsById.values.contains(where: { $0.scope == scope && $0.name == name }) {
            throw BookshelfGroupError.duplicateName
        }

        var maxOrder = 0
        for g in groupsById.values where g.scope == scope {
            maxOrder = max(maxOrder, g.orderIndex)
        }

        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let id = "group_\(scope.key)_\(hex)"
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let group = BookshelfGroup(id: id, scope: scope, name: name, isBuiltin: false,
                                   orderIndex: maxOrder + 1, createdAt: now, updatedAt: now)
        groupsById[id] = group
        if scope == .online {
            onlineMembers[id] = []
        } else {
            localMembers[id] = []
        }
        saveLocked()
        return group
    }

    public func renameGroup(id: String, rawNewName: String) throws -> BookshelfGroup {
        let name = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BookshelfGroupError.emptyName }

        lock.lock(); defer { lock.unlock() }
        guard let existing = groupsById[id] else { throw BookshelfGroupError.groupNotFound }
        guard !existing.isBuiltin else { throw BookshelfGroupError.cannotModifyBuiltin }
        if existing.name == name { return existing }

        if groupsById.values.contains(where: { $0.scope == existing.scope && $0.id != id && $0.name == name }) {
            throw BookshelfGroupError.duplicateName
        }

        let updated = existing.withName(name)
        groupsById[id] = updated
        saveLocked()
        return updated
    }

    public func deleteGroup(id: String) throws -> BookshelfGroupDeletionSnapshot {
        lock.lock(); defer { lock.unlock() }
        guard let group = groupsById[id] else { throw BookshelfGroupError.groupNotFound }
        guard !group.isBuiltin else { throw BookshelfGroupError.cannotModifyBuiltin }

        let members: Set<String>
        if group.scope == .online {
            members = onlineMembers.removeValue(forKey: id) ?? []
        } else {
            members = localMembers.removeValue(forKey: id) ?? []
        }
        groupsById.removeValue(forKey: id)

        let snapshot = BookshelfGroupDeletionSnapshot(group: group, memberIds: members, orderIndex: group.orderIndex)
        saveLocked()
        return snapshot
    }

    public func restoreGroup(snapshot: BookshelfGroupDeletionSnapshot) -> BookshelfGroup {
        let group = snapshot.group
        guard !group.isBuiltin else { return group }

        lock.lock(); defer { lock.unlock() }
        var name = group.name
        var counter = 1
        while groupsById.values.contains(where: { $0.scope == group.scope && $0.name == name }) {
            counter += 1
            name = "\(group.name) (\(counter))"
        }

        let restored = BookshelfGroup(id: group.id, scope: group.scope, name: name, isBuiltin: false,
                                      orderIndex: snapshot.orderIndex, createdAt: group.createdAt,
                                      updatedAt: Int64(Date().timeIntervalSince1970 * 1000))
        groupsById[restored.id] = restored

        let builtinId = (restored.scope == .online) ? Self.builtinOnlineAllId : Self.builtinLocalAllId
        if restored.scope == .online {
            onlineMembers[restored.id] = Set(snapshot.memberIds)
            for m in snapshot.memberIds { onlineMembers[builtinId, default: []].insert(m) }
        } else {
            localMembers[restored.id] = Set(snapshot.memberIds)
            for m in snapshot.memberIds { localMembers[builtinId, default: []].insert(m) }
        }
        saveLocked()
        return restored
    }

    public func reorderGroups(scope: BookshelfScope, orderedCustomGroupIds: [String]) {
        lock.lock(); defer { lock.unlock() }
        for (index, id) in orderedCustomGroupIds.enumerated() {
            if var g = groupsById[id], g.scope == scope, !g.isBuiltin {
                g.orderIndex = index + 1
                groupsById[id] = g
            }
        }
        saveLocked()
    }

    public func getMembers(groupId: String) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        guard let group = groupsById[groupId] else { return [] }
        return (group.scope == .online) ? (onlineMembers[groupId] ?? []) : (localMembers[groupId] ?? [])
    }

    public func getGroupsForComic(scope: BookshelfScope, comicId: String) -> [BookshelfGroup] {
        lock.lock(); defer { lock.unlock() }
        let map = (scope == .online) ? onlineMembers : localMembers
        var result: [BookshelfGroup] = []
        for g in groupsById.values where g.scope == scope {
            if let set = map[g.id], set.contains(comicId) {
                result.append(g)
            }
        }
        result.sort { a, b in
            if a.isBuiltin != b.isBuiltin { return a.isBuiltin && !b.isBuiltin }
            return a.orderIndex < b.orderIndex
        }
        return result
    }

    public func containsComic(groupId: String, comicId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let group = groupsById[groupId] else { return false }
        let map = (group.scope == .online) ? onlineMembers : localMembers
        return map[groupId]?.contains(comicId) ?? false
    }

    public func addToScope(scope: BookshelfScope, comicId: String) {
        let clean = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let builtinId = (scope == .online) ? Self.builtinOnlineAllId : Self.builtinLocalAllId
        if scope == .online {
            if onlineMembers[builtinId, default: []].insert(clean).inserted { saveLocked() }
        } else {
            if localMembers[builtinId, default: []].insert(clean).inserted { saveLocked() }
        }
    }

    public func addToGroup(groupId: String, comicId: String) {
        let clean = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard let group = groupsById[groupId] else { return }
        let builtinId = (group.scope == .online) ? Self.builtinOnlineAllId : Self.builtinLocalAllId

        var changed = false
        if group.scope == .online {
            changed = onlineMembers[groupId, default: []].insert(clean).inserted || changed
            changed = onlineMembers[builtinId, default: []].insert(clean).inserted || changed
        } else {
            changed = localMembers[groupId, default: []].insert(clean).inserted || changed
            changed = localMembers[builtinId, default: []].insert(clean).inserted || changed
        }
        if changed { saveLocked() }
    }

    public func removeFromGroup(groupId: String, comicId: String) {
        let clean = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard let group = groupsById[groupId] else { return }

        if group.isBuiltin {
            removeComicFromAllGroupsLocked(scope: group.scope, comicId: clean)
        } else {
            if group.scope == .online {
                if onlineMembers[groupId]?.remove(clean) != nil { saveLocked() }
            } else {
                if localMembers[groupId]?.remove(clean) != nil { saveLocked() }
            }
        }
    }

    public func removeComicFromAllGroups(scope: BookshelfScope, comicId: String) {
        let clean = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        removeComicFromAllGroupsLocked(scope: scope, comicId: clean)
    }

    private func removeComicFromAllGroupsLocked(scope: BookshelfScope, comicId: String) {
        var changed = false
        if scope == .online {
            for key in onlineMembers.keys {
                if onlineMembers[key]?.remove(comicId) != nil { changed = true }
            }
        } else {
            for key in localMembers.keys {
                if localMembers[key]?.remove(comicId) != nil { changed = true }
            }
        }
        if changed { saveLocked() }
    }

    public func updateComicGroups(scope: BookshelfScope, comicId: String, targetGroupIds: Set<String>) {
        let clean = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }

        let builtinId = (scope == .online) ? Self.builtinOnlineAllId : Self.builtinLocalAllId
        var changed = false

        if scope == .online {
            changed = onlineMembers[builtinId, default: []].insert(clean).inserted || changed
            for g in groupsById.values where g.scope == scope && !g.isBuiltin {
                if targetGroupIds.contains(g.id) {
                    changed = onlineMembers[g.id, default: []].insert(clean).inserted || changed
                } else {
                    if onlineMembers[g.id]?.remove(clean) != nil { changed = true }
                }
            }
        } else {
            changed = localMembers[builtinId, default: []].insert(clean).inserted || changed
            for g in groupsById.values where g.scope == scope && !g.isBuiltin {
                if targetGroupIds.contains(g.id) {
                    changed = localMembers[g.id, default: []].insert(clean).inserted || changed
                } else {
                    if localMembers[g.id]?.remove(clean) != nil { changed = true }
                }
            }
        }
        if changed { saveLocked() }
    }
}

public enum BookshelfGroupError: LocalizedError {
    case emptyName
    case duplicateName
    case groupNotFound
    case cannotModifyBuiltin

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "分组名称不能为空"
        case .duplicateName: return "已存在同名分组"
        case .groupNotFound: return "未找到该分组"
        case .cannotModifyBuiltin: return "内置“全部”分组不可修改或删除"
        }
    }
}
