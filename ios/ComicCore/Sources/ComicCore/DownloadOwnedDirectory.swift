import Foundation

/// Refuse to recursively delete a book unless all entries belong to its tasks.
enum DownloadOwnedDirectory {
    static func validate(_ directory: URL, allowedDirectories: Set<String>, allowedFiles: Set<String>,
                         taskIDs: Set<String>, partPrefix: String? = nil, pageFilesAtRoot: Bool = false) throws {
        let manager = FileManager.default
        if let attributes = try? manager.attributesOfItem(atPath: directory.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw DownloadError.corruptedData("下载目录含外部链接，原文件已保留")
        }
        guard manager.fileExists(atPath: directory.path) else { return }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        let root = try directory.resourceValues(forKeys: keys)
        guard root.isDirectory == true, root.isSymbolicLink != true else { throw DownloadError.corruptedData("删除路径不是 App 拥有的目录，原文件已保留") }
        // Darwin's enumerator can return canonical file URLs even when the input
        // contains an OS directory alias (for example /var -> /private/var).
        // Compare path components inside that same canonical root; byte offsets
        // into a differently formed URL do not identify its relative children.
        let enumerationRoot = directory.resolvingSymlinksInPath().standardizedFileURL
        let rootComponents = enumerationRoot.pathComponents
        var enumerationError: Error?
        guard let entries = manager.enumerator(at: enumerationRoot, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, error in
            enumerationError = error; return false
        }) else { throw DownloadError.corruptedData("无法检查下载目录") }
        for case let file as URL in entries {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw DownloadError.corruptedData("下载目录含外部链接，原文件已保留") }
            let components = file.standardizedFileURL.pathComponents
            guard components.count > rootComponents.count, components.starts(with: rootComponents) else {
                throw DownloadError.corruptedData("下载目录检查超出归属范围，原文件已保留")
            }
            let relative = components.dropFirst(rootComponents.count).joined(separator: "/")
            if values.isDirectory == true {
                guard allowedDirectories.contains(relative) else { throw DownloadError.corruptedData("下载目录含未知文件夹，已保留") }
            } else {
                let parts = relative.split(separator: "/")
                let taskFile = parts.count == 2 && taskIDs.contains(String(parts[0])) &&
                    String(parts[1]).range(of: #"^(\d+\.img|\d+\.\d+\.part)$"#, options: .regularExpression) != nil
                let workPart = partPrefix.map {
                    relative.range(of: "^" + NSRegularExpression.escapedPattern(for: $0) + #"\.\d+\.part$"#, options: .regularExpression) != nil
                } ?? false
                let rootPage = pageFilesAtRoot && parts.count == 1 && relative.range(of: #"^(\d+\.img|\d+\.\d+\.part)$"#, options: .regularExpression) != nil
                guard values.isRegularFile == true, allowedFiles.contains(relative) || taskFile || workPart || rootPage else {
                    throw DownloadError.corruptedData("下载目录含未知文件，已保留")
                }
            }
        }
        if let enumerationError { throw enumerationError }
    }
}
