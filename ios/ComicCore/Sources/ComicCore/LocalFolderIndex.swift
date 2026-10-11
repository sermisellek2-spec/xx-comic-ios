import Foundation

struct LocalFolderIndex {
    struct Group { let title: String; let indices: [Int] }
    let files: [URL]
    let relativePaths: [String]
    let groups: [Group]

    init(folder: URL, metadataOnly: Bool = false, isReadableImage: (URL) throws -> Bool) throws {
        var found: [(path: String, url: URL)] = []
        var entryCount = 0, totalBytes: Int64 = 0
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        func scan(_ directory: URL, prefix: String, depth: Int) throws {
            try Task.checkCancellation()
            guard depth <= 5 else { throw LocalLibraryError.folderTooDeep }
            let attributes = try directory.resourceValues(forKeys: keys)
            guard attributes.isDirectory == true, attributes.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) {
                try Task.checkCancellation()
                let lower = url.lastPathComponent.lowercased()
                if lower == "__macosx" || [".ds_store", "thumbs.db", ".nomedia", "desktop.ini"].contains(where: lower.hasSuffix) { continue }
                entryCount += 1
                guard entryCount <= 50_000 else { throw LocalLibraryError.folderTooLarge }
                let value = try url.resourceValues(forKeys: keys)
                guard value.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
                let relative = prefix + url.lastPathComponent
                if value.isDirectory == true { try scan(url, prefix: relative + "/", depth: depth + 1); continue }
                guard ["jpg", "jpeg", "png", "webp", "gif"].contains(url.pathExtension.lowercased()) else { continue }
                guard value.isRegularFile == true, let size = value.fileSize else { throw LocalLibraryError.invalidBook }
                guard size <= LocalLibrary.maximumImageBytes else { throw LocalLibraryError.imageTooLarge }
                totalBytes += Int64(size)
                guard totalBytes <= LocalLibrary.maximumImportBytes else { throw LocalLibraryError.folderTooLarge }
                if metadataOnly {
                    if size > 0 { found.append((relative, url)) }
                } else if try isReadableImage(url) { found.append((relative, url)) }
            }
        }
        try scan(folder, prefix: "", depth: 0)
        try Task.checkCancellation()
        guard !found.isEmpty else { throw LocalLibraryError.emptyImport }
        found.sort { NaturalPathOrder.less($0.path, $1.path) }
        files = found.map(\.url)
        relativePaths = found.map(\.path)
        groups = Self.groups(for: found.map(\.path))
    }

    static func groups(for sortedPaths: [String]) -> [Group] {
        var paths = sortedPaths.map { $0.split(separator: "/").map(String.init) }
        while let first = paths.first?.first, paths.allSatisfy({ $0.count > 1 && $0[0] == first }) {
            paths = paths.map { Array($0.dropFirst()) }
        }
        let root = paths.indices.filter { paths[$0].count == 1 }
        var byFolder: [String: [Int]] = [:]
        for index in paths.indices where paths[index].count > 1 { byFolder[paths[index][0], default: []].append(index) }
        if byFolder.isEmpty {
            return [Group(title: "正文", indices: root)]
        } else {
            return (root.isEmpty ? [] : [Group(title: "未分章", indices: root)]) + byFolder.keys.sorted(by: NaturalPathOrder.less).map { Group(title: $0, indices: byFolder[$0]!) }
        }
    }
}
