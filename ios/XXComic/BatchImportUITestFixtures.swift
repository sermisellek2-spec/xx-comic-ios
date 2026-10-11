#if DEBUG
import UIKit
import ComicCore

@MainActor
enum BatchImportUITestFixtures {
    private static var enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--batch-import-fixtures")
    }

    static func seed(library: LocalLibrary) throws {
        guard enabled else { return }
        let folder = library.directory.appendingPathComponent("UITestBatchSelections", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 1...2 {
            let file = folder.appendingPathComponent("恢复卷0\(index).png")
            guard !FileManager.default.fileExists(atPath: file.path) else { continue }
            let data = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48)).image { context in
                (index == 1 ? UIColor.systemBlue : UIColor.systemRed).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
            }.pngData()!
            try data.write(to: file, options: .atomic)
        }
        guard !ProcessInfo.processInfo.arguments.contains("--batch-new-import") else { return }
        let session = library.directory.appendingPathComponent("batch_import_session.json")
        guard !FileManager.default.fileExists(atPath: session.path) else { return }
        let items: [[String: Any]] = (1...2).map { index in
            ["uri": "/previous-selection/恢复卷0\(index).png", "name": "恢复卷0\(index).png",
             "format": "png", "selectionIndex": index - 1, "state": "pending", "error": ""]
        }
        let snapshot: [String: Any] = ["version": 1, "taskId": UUID().uuidString, "cancelled": false,
            "groups": [["key": "recovery-fixture", "title": "恢复验收漫画", "targetBookId": "", "requiresExistingBook": false, "items": items]]]
        try JSONSerialization.data(withJSONObject: snapshot, options: .sortedKeys).write(to: session, options: .atomic)
    }

    /// Replaces only the system file chooser in explicit Debug tests. The real
    /// picker delegate, recovery plan, session, worker and library remain in use.
    /// This is not evidence of Files permissions or external provider access.
    static func selectedURLs(library: LocalLibrary) -> [URL]? {
        guard enabled else { return nil }
        let count = ProcessInfo.processInfo.arguments.contains("--batch-select-one") ? 1 : 2
        return (1...count).map { library.directory.appendingPathComponent("UITestBatchSelections/恢复卷0\($0).png") }
    }
}
#endif
