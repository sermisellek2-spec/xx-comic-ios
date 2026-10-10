import Foundation
import ComicCore

@main struct RecoverySafetyProbe {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xxcomic-recovery-safety-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var results: [String: Any] = [:]

        // All destructive fault injection stays inside this probe's unique temporary root.
        let malformedContainer = root.appendingPathComponent("MalformedIDCase")
        let malformedLocal = malformedContainer.appendingPathComponent("Local")
        let malformedLibrary = try LocalLibrary(directory: malformedLocal)
        let malformedExternal = malformedContainer.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: malformedExternal, withIntermediateDirectories: true)
        let externalOriginal = malformedExternal.appendingPathComponent("01.jpg")
        try Data([1, 2, 3]).write(to: externalOriginal)
        let existingImport = try await malformedLibrary.importFolderCoordinated(title: "Existing Book", folder: malformedExternal, isReadableImage: {_ in true})
        _ = try malformedLibrary.book(id: existingImport.book.id)
        let sentinel = malformedContainer.appendingPathComponent("sibling-sentinel.txt")
        try Data("preserve sibling".utf8).write(to: sentinel)
        let malformedBackup = malformedLocal.appendingPathComponent(".backup-..-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: malformedBackup, withIntermediateDirectories: true)
        try Data("unknown backup".utf8).write(to: malformedBackup.appendingPathComponent("unknown.txt"))
        let unsafeTarget = malformedLocal.appendingPathComponent("..").resolvingSymlinksInPath().standardizedFileURL
        let containedTargetPath = (unsafeTarget.path as NSString).standardizingPath
        let expectedContainerPath = (malformedContainer.resolvingSymlinksInPath().path as NSString).standardizingPath
        let resolvedRootPath = (root.resolvingSymlinksInPath().path as NSString).standardizingPath
        guard containedTargetPath == expectedContainerPath,
              containedTargetPath.hasPrefix(resolvedRootPath + "/") else {
            print("Probe containment check failed: \(containedTargetPath) / \(expectedContainerPath) / \(resolvedRootPath)")
            return
        }
        var malformedError: String? = nil
        do { try await malformedLibrary.recoverOrphans() }
        catch { malformedError = error.localizedDescription }
        var previousOwnedBookReadable = true
        do { _ = try malformedLibrary.book(id: existingImport.book.id) }
        catch { previousOwnedBookReadable = false }
        results["malformedBackupID"] = [
            "siblingSentinelPreserved": FileManager.default.fileExists(atPath: sentinel.path),
            "libraryRootPreserved": FileManager.default.fileExists(atPath: malformedLocal.path),
            "previousOwnedBookReadable": previousOwnedBookReadable,
            "externalOriginalPreserved": FileManager.default.fileExists(atPath: externalOriginal.path),
            "recoveryError": malformedError ?? "none"
        ]

        let pageContainer = root.appendingPathComponent("MissingPageCase")
        let external = pageContainer.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: external.appendingPathComponent("01.jpg"))
        let localDir = pageContainer.appendingPathComponent("Local")
        let library = try LocalLibrary(directory: localDir)
        let imported = try await library.importFolderCoordinated(title: "Probe", folder: external, isReadableImage: {_ in true})
        let volume = localDir.appendingPathComponent(imported.book.id)
        let backup = localDir.appendingPathComponent(".backup-" + imported.book.id + "-" + UUID().uuidString)
        try FileManager.default.copyItem(at: volume, to: backup)
        let page = try library.pageURLs(for: imported.book)[0]
        guard (page.deletingLastPathComponent().path as NSString).standardizingPath == (volume.path as NSString).standardizingPath else {
            fatalError("Probe page containment check failed")
        }
        try FileManager.default.removeItem(at: page)
        var metadataValidationPassed = true
        do { _ = try library.book(id: imported.book.id) } catch { metadataValidationPassed = false }
        try await library.recoverOrphans()
        let recovered = try library.book(id: imported.book.id)
        let recoveredPage = try library.pageURLs(for: recovered)[0]
        var pageReadableAfterRecovery = true
        do { _ = try Data(contentsOf: recoveredPage) } catch { pageReadableAfterRecovery = false }
        results["missingTargetPage"] = [
            "metadataValidationPassedBeforeRecovery": metadataValidationPassed,
            "pageReadableAfterRecovery": pageReadableAfterRecovery,
            "goodBackupStillExists": FileManager.default.fileExists(atPath: backup.path)
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
    }
}
