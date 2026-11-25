import Foundation

/// Persistent LRU store mapping canonical comic IDs to resolved member-specific raw IDs.
public final class FailoverRouteStore: @unchecked Sendable {
    public static let defaultMaxEntries = 2048
    private static let persistVersion = 1
    private static let maxLoadBytes = 4 * 1024 * 1024

    private final class EntryNode {
        let key: String
        var members: [String: String]
        var memberOrder: [String]
        var prev: EntryNode?
        var next: EntryNode?

        init(key: String, members: [String: String], memberOrder: [String]) {
            self.key = key
            self.members = members
            self.memberOrder = memberOrder
        }
    }

    private let lock = NSLock()
    private let fileURL: URL?
    private let maxEntries: Int
    private var map: [String: EntryNode] = [:]
    private var reverse: [String: String] = [:]
    private var head: EntryNode?
    private var tail: EntryNode?

    public init(fileURL: URL? = nil, maxEntries: Int = defaultMaxEntries) {
        self.fileURL = fileURL
        self.maxEntries = max(16, maxEntries)
        load()
    }

    public func findMemberRawId(_ comicId: String?, memberId: String?) -> String? {
        guard let comicId, !comicId.isEmpty, let memberId, !memberId.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let node = map[comicId] else { return nil }
        touch(node)
        return node.members[memberId]
    }

    public func findCanonicalComicId(memberId: String?, memberRawId: String?) -> String? {
        guard let memberId, !memberId.isEmpty, let memberRawId, !memberRawId.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return reverse[Self.reverseKey(memberId: memberId, memberRawId: memberRawId)]
    }

    public func saveRoute(comicId: String?, memberId: String?, memberRawId: String?) {
        guard let comicId, !comicId.isEmpty,
              let memberId, !memberId.isEmpty,
              let memberRawId, !memberRawId.isEmpty else {
            return
        }
        lock.lock()
        defer { lock.unlock() }

        if let node = map[comicId] {
            touch(node)
            if node.members[memberId] == memberRawId {
                reverse[Self.reverseKey(memberId: memberId, memberRawId: memberRawId)] = comicId
                return
            }
            if let oldRaw = node.members[memberId], oldRaw != memberRawId {
                let oldKey = Self.reverseKey(memberId: memberId, memberRawId: oldRaw)
                if reverse[oldKey] == comicId {
                    reverse.removeValue(forKey: oldKey)
                }
            } else if node.members[memberId] == nil {
                node.memberOrder.append(memberId)
            }
            node.members[memberId] = memberRawId
        } else {
            let node = EntryNode(key: comicId, members: [memberId: memberRawId], memberOrder: [memberId])
            insertAtTail(node)
            map[comicId] = node
            evictIfNeeded()
        }

        reverse[Self.reverseKey(memberId: memberId, memberRawId: memberRawId)] = comicId
        persistQuietlyLocked()
    }

    public func routesFor(_ comicId: String?) -> [String: String] {
        guard let comicId, !comicId.isEmpty else { return [:] }
        lock.lock()
        defer { lock.unlock() }
        guard let node = map[comicId] else { return [:] }
        touch(node)
        return node.members
    }

    public func size() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return map.count
    }

    public var count: Int { size() }

    private func touch(_ node: EntryNode) {
        guard tail !== node else { return }
        unlink(node)
        insertAtTail(node)
    }

    private func insertAtTail(_ node: EntryNode) {
        node.prev = tail
        node.next = nil
        if let tail {
            tail.next = node
        } else {
            head = node
        }
        tail = node
    }

    private func unlink(_ node: EntryNode) {
        let prev = node.prev
        let next = node.next
        if let prev {
            prev.next = next
        } else {
            head = next
        }
        if let next {
            next.prev = prev
        } else {
            tail = prev
        }
        node.prev = nil
        node.next = nil
    }

    private func evictIfNeeded() {
        while map.count > maxEntries, let eldest = head {
            unlink(eldest)
            map.removeValue(forKey: eldest.key)
            removeReverseEntries(comicId: eldest.key, byMember: eldest.members)
        }
    }

    private func removeReverseEntries(comicId: String, byMember: [String: String]) {
        for (memberId, memberRawId) in byMember {
            let key = Self.reverseKey(memberId: memberId, memberRawId: memberRawId)
            if reverse[key] == comicId {
                reverse.removeValue(forKey: key)
            }
        }
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attrs[.size] as? NSNumber, fileSize.intValue > Self.maxLoadBytes {
                return
            }
            let data = try Data(contentsOf: fileURL)
            guard data.count <= Self.maxLoadBytes,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["version"] as? Int) == Self.persistVersion,
                  let routesObj = root["routes"] as? [String: Any] else {
                return
            }
            for (comicId, rawMembers) in routesObj {
                guard !comicId.isEmpty, let membersDict = rawMembers as? [String: Any] else { continue }
                var loadedMembers = [String: String]()
                var loadedOrder = [String]()
                for (memberId, rawVal) in membersDict {
                    guard !memberId.isEmpty, let memberRawId = rawVal as? String, !memberRawId.isEmpty else {
                        continue
                    }
                    loadedMembers[memberId] = memberRawId
                    loadedOrder.append(memberId)
                    reverse[Self.reverseKey(memberId: memberId, memberRawId: memberRawId)] = comicId
                }
                if !loadedMembers.isEmpty {
                    let node = EntryNode(key: comicId, members: loadedMembers, memberOrder: loadedOrder)
                    insertAtTail(node)
                    map[comicId] = node
                    evictIfNeeded()
                }
            }
        } catch {
            // Corrupt route cache must never break source initialization.
        }
    }

    private func persistQuietlyLocked() {
        guard let fileURL else { return }
        var rows = [String: [String: String]]()
        var current = head
        while let node = current {
            rows[node.key] = node.members
            current = node.next
        }
        let root: [String: Any] = [
            "version": Self.persistVersion,
            "routes": rows
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: []) else { return }
        try? AtomicFileOps.writeAtomically(data, to: fileURL)
    }

    private static func reverseKey(memberId: String, memberRawId: String) -> String {
        "\(memberId)\0\(memberRawId)"
    }
}
