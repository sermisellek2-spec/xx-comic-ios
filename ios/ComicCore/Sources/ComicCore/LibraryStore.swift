import Foundation

public struct ReadingRecord: Codable, Equatable, Sendable {
    public let chapter: Chapter
    public let chapterIndex: Int
    public let position: ReaderPosition
    public let updatedAt: TimeInterval
}

public struct LibraryEntry: Codable, Equatable, Sendable {
    public var summary: ComicSummary
    public var favoriteAt: TimeInterval?
    public var reading: ReadingRecord?
    public var positions: [String: ReaderPosition]
    // Compatibility data only: preserved when old libraries are decoded and rewritten.
    public var textPositions: [String: TextLocator]?
    public var isFavorite: Bool { favoriteAt != nil }
    public var sortTime: TimeInterval { max(favoriteAt ?? 0, reading?.updatedAt ?? 0) }
}

/// Confine to the UI actor. Writes replace the snapshot atomically before memory changes.
public final class LibraryStore {
    public static let maxPositions = 600

    private struct Snapshot: Codable {
        var version = 1
        var entries: [String: LibraryEntry] = [:]
        var positionOrder: [String]? = nil
    }
    private let file: URL
    private let maxPositionsLimit: Int
    private var snapshot: Snapshot

    public init(directory: URL, maxPositions: Int = LibraryStore.maxPositions) throws {
        file = directory.appendingPathComponent("library.json")
        maxPositionsLimit = max(1, maxPositions)
        if FileManager.default.fileExists(atPath: file.path) {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
            guard snapshot.version == 1 else { throw LibraryError.unsupportedVersion }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            snapshot = Snapshot()
        }
    }

    public var favorites: [LibraryEntry] { sorted(snapshot.entries.values.filter(\.isFavorite)) }
    public var history: [LibraryEntry] {
        snapshot.entries.values.filter { $0.reading != nil }.sorted {
            if $0.reading!.updatedAt == $1.reading!.updatedAt { return Self.key($0.summary) < Self.key($1.summary) }
            return $0.reading!.updatedAt > $1.reading!.updatedAt
        }
    }

    public func entry(for comic: ComicSummary) -> LibraryEntry? { snapshot.entries[Self.key(comic)] }
    public func position(for comic: ComicSummary, chapterID: String) -> ReaderPosition? {
        entry(for: comic)?.positions[chapterID]
    }

    public func setFavorite(_ comic: ComicSummary, favorite: Bool, now: TimeInterval = Date().timeIntervalSince1970) throws {
        var entry = entry(for: comic) ?? LibraryEntry(summary: comic, positions: [:])
        entry.summary = comic
        entry.favoriteAt = favorite ? (entry.favoriteAt ?? now) : nil
        try persist(entry)
    }

    public func saveReading(_ comic: ComicSummary, chapter: Chapter, chapterIndex: Int,
                            position: ReaderPosition, now: TimeInterval = Date().timeIntervalSince1970) throws {
        let comicKey = Self.key(comic)
        var entry = entry(for: comic) ?? LibraryEntry(summary: comic, positions: [:])
        entry.summary = comic
        entry.reading = ReadingRecord(chapter: chapter, chapterIndex: max(0, chapterIndex), position: position, updatedAt: now)
        entry.positions[chapter.chapterId] = position

        var next = snapshot
        next.entries[comicKey] = entry
        let token = "\(comicKey)\n\(chapter.chapterId)"
        var order = next.positionOrder ?? Self.rebuildPositionOrder(entries: next.entries)
        order.removeAll { $0 == token }
        order.append(token)
        Self.prunePositions(entries: &next.entries, order: &order, limit: maxPositionsLimit)
        next.positionOrder = order
        let data = try JSONEncoder().encode(next)
        try data.write(to: file, options: .atomic)
        snapshot = next
    }

    public func deleteHistory(for comic: ComicSummary) throws {
        let k = Self.key(comic)
        guard var entry = snapshot.entries[k] else { return }
        entry.reading = nil
        entry.positions.removeAll()
        entry.textPositions?.removeAll()
        var next = snapshot
        if !entry.isFavorite {
            next.entries.removeValue(forKey: k)
        } else {
            next.entries[k] = entry
        }
        if var order = next.positionOrder {
            let prefix = k + "\n"
            order.removeAll { $0.hasPrefix(prefix) }
            next.positionOrder = order
        }
        let data = try JSONEncoder().encode(next)
        try data.write(to: file, options: .atomic)
        snapshot = next
    }

    public func clearHistory() throws {
        var nextEntries = snapshot.entries
        for (k, var entry) in nextEntries {
            entry.reading = nil
            entry.positions.removeAll()
            entry.textPositions?.removeAll()
            if !entry.isFavorite {
                nextEntries.removeValue(forKey: k)
            } else {
                nextEntries[k] = entry
            }
        }
        var next = snapshot
        next.entries = nextEntries
        if next.positionOrder != nil {
            next.positionOrder = []
        }
        let data = try JSONEncoder().encode(next)
        try data.write(to: file, options: .atomic)
        snapshot = next
    }

    public func restoreEntries(_ updates: [(ComicSummary, LibraryEntry?)]) throws {
        var next = snapshot
        for (comic, restored) in updates {
            let k = Self.key(comic)
            if let restored {
                next.entries[k] = restored
            } else {
                next.entries.removeValue(forKey: k)
            }
        }
        if next.positionOrder != nil {
            var order = Self.rebuildPositionOrder(entries: next.entries)
            Self.prunePositions(entries: &next.entries, order: &order, limit: maxPositionsLimit)
            next.positionOrder = order
        }
        let data = try JSONEncoder().encode(next)
        try data.write(to: file, options: .atomic)
        snapshot = next
    }

    public func replaceSource(original: ComicSummary, target: ComicSummary, matchingChapter: Chapter? = nil, matchingChapterIndex: Int = 0, now: TimeInterval = Date().timeIntervalSince1970) throws {
        let oldKey = Self.key(original)
        let newKey = Self.key(target)
        let oldEntry = snapshot.entries[oldKey]

        var targetEntry = snapshot.entries[newKey] ?? LibraryEntry(summary: target, positions: [:])
        targetEntry.summary = target
        if let oldEntry {
            if oldEntry.isFavorite {
                targetEntry.favoriteAt = targetEntry.favoriteAt ?? oldEntry.favoriteAt ?? now
            }
            if let oldReading = oldEntry.reading {
                if let matchingChapter {
                    targetEntry.reading = ReadingRecord(
                        chapter: matchingChapter,
                        chapterIndex: max(0, matchingChapterIndex),
                        position: oldReading.position,
                        updatedAt: oldReading.updatedAt
                    )
                    targetEntry.positions[matchingChapter.chapterId] = oldReading.position
                } else {
                    targetEntry.reading = oldReading
                }
            }
        }

        var next = snapshot
        next.entries.removeValue(forKey: oldKey)
        next.entries[newKey] = targetEntry
        let data = try JSONEncoder().encode(next)
        try data.write(to: file, options: .atomic)
        snapshot = next
    }

    private func persist(_ entry: LibraryEntry) throws {
        var next = snapshot
        next.entries[Self.key(entry.summary)] = entry
        let data = try JSONEncoder().encode(next)
        try data.write(to: file, options: .atomic)
        snapshot = next
    }

    private func sorted(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.sorted { $0.sortTime == $1.sortTime ? Self.key($0.summary) < Self.key($1.summary) : $0.sortTime > $1.sortTime }
    }

    private static func rebuildPositionOrder(entries: [String: LibraryEntry]) -> [String] {
        let orderedComics = entries.sorted { a, b in
            let ta = a.value.reading?.updatedAt ?? a.value.favoriteAt ?? 0
            let tb = b.value.reading?.updatedAt ?? b.value.favoriteAt ?? 0
            return ta == tb ? a.key < b.key : ta < tb
        }
        var result: [String] = []
        for (comicKey, entry) in orderedComics {
            let activeId = entry.reading?.chapter.chapterId
            for chapterId in entry.positions.keys.sorted() where chapterId != activeId {
                result.append("\(comicKey)\n\(chapterId)")
            }
            if let activeId, entry.positions[activeId] != nil {
                result.append("\(comicKey)\n\(activeId)")
            }
        }
        return result
    }

    private static func prunePositions(entries: inout [String: LibraryEntry], order: inout [String], limit: Int) {
        var total = entries.values.reduce(0) { $0 + $1.positions.count }
        guard total > limit else { return }
        var idx = 0
        while total > limit && idx < order.count {
            let token = order[idx]
            guard let nl = token.firstIndex(of: "\n") else {
                order.remove(at: idx)
                continue
            }
            let comicKey = String(token[..<nl])
            let chapterId = String(token[token.index(after: nl)...])
            guard var entry = entries[comicKey], entry.positions[chapterId] != nil else {
                order.remove(at: idx)
                continue
            }
            if entry.reading?.chapter.chapterId == chapterId {
                idx += 1
                continue
            }
            entry.positions.removeValue(forKey: chapterId)
            entries[comicKey] = entry
            order.remove(at: idx)
            total -= 1
        }
    }

    private static func key(_ comic: ComicSummary) -> String {
        "\(comic.sourceId.utf8.count):\(comic.sourceId)\(comic.comicId)"
    }
}

public enum LibraryError: LocalizedError, Equatable {
    case unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "书架数据版本暂不支持，已保留原文件。"
        }
    }
}
