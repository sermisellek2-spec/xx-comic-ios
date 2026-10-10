import Foundation
import ComicCore

private actor OverlapCounter {
    var active = 0
    var maximum = 0
    func enter() { active += 1; maximum = max(maximum, active) }
    func leave() { active -= 1 }
}

@main struct RecoveryProbe {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xxcomic-recovery-review-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let external = root.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data([1]).write(to: external.appendingPathComponent("01.jpg"))
        let localPath = root.appendingPathComponent("Local")
        let local = try LocalLibrary(directory: localPath)
        let result = try await local.importFolderCoordinated(title: "Probe", folder: external, isReadableImage: {_ in true})
        let volume = localPath.appendingPathComponent(result.book.id)
        let backup = localPath.appendingPathComponent(".backup-" + result.book.id + "-" + UUID().uuidString)
        // Recreate the on-disk interruption point after old -> backup, before new publish.
        try FileManager.default.moveItem(at: volume, to: backup)
        let restarted = try LocalLibrary(directory: localPath)
        try await restarted.recoverOrphans()
        let seriesAfterRecovery = try await restarted.series(id: result.series.id)!
        var oldVolumeReadable = true
        do { _ = try restarted.book(id: result.book.id) } catch { oldVolumeReadable = false }

        let gate = SingleWriterGate()
        let counter = OverlapCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    await gate.execute {
                        await counter.enter()
                        try? await Task.sleep(nanoseconds: 30_000_000)
                        await counter.leave()
                    }
                }
            }
        }
        let maximum = await counter.maximum
        let findings: [String: Any] = [
            "interruptedSyncRecovery": [
                "catalogStillReferencesOldVolume": seriesAfterRecovery.volumeIDs.contains(result.book.id),
                "oldVolumeReadableAfterRecovery": oldVolumeReadable,
                "backupStillExists": FileManager.default.fileExists(atPath: backup.path)
            ],
            "singleWriterGate": ["maximumSimultaneousBlocks": maximum]
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: findings, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
    }
}
