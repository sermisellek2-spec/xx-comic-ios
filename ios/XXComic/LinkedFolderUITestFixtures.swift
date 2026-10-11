#if DEBUG
import UIKit
import ComicCore

@MainActor
enum LinkedFolderUITestFixtures {
    static var enabled: Bool {
        let flags = ProcessInfo.processInfo.arguments
        return flags.contains("--ui-testing") && flags.contains("--linked-folder-fixture")
    }
    private static func directory(library: LocalLibrary, moved: Bool = false) -> URL {
        library.directory.deletingLastPathComponent().appendingPathComponent(moved ? "UITestLinkedMoved" : "UITestLinkedSelections", isDirectory: true)
    }
    static func seed(environment: AppEnvironment) async throws {
        guard enabled else { return }
        let folder = directory(library: environment.localLibrary)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            for index in 1...2 {
                let bytes = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48), format: format).image {
                    (index == 1 ? UIColor.systemBlue : UIColor.systemRed).setFill()
                    $0.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
                }.pngData()!
                try bytes.write(to: folder.appendingPathComponent("0\(index).png"))
            }
        }
        let record = try await environment.folderSyncCoordinator.linkFolder(url: folder, title: "直读验收漫画")
        environment.bookshelfGroupStore.addToScope(scope: .local, comicId: record.seriesId)
        if ProcessInfo.processInfo.arguments.contains("--linked-folder-moved") {
            let moved = directory(library: environment.localLibrary, moved: true)
            if !FileManager.default.fileExists(atPath: moved.path) { try FileManager.default.moveItem(at: folder, to: moved) }
            _ = await environment.folderSyncCoordinator.sync(id: record.id)
        }
        environment.notifyLibraryChanged()
    }

    /// Replaces only the system chooser for a moved-folder UI scenario. Reading,
    /// bookmarks, indexing, persistence and the production picker delegate are real.
    /// An app-owned fixture is not evidence of an external Files provider grant.
    static func reauthorizationSelection(library: LocalLibrary) -> URL? {
        guard enabled, ProcessInfo.processInfo.arguments.contains("--linked-folder-reauthorize-selection") else { return nil }
        return directory(library: library, moved: true)
    }
}
#endif
