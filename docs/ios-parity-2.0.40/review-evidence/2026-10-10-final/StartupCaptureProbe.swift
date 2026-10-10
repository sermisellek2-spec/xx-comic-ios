import Foundation

struct RecoveryLibraryProbe {
    func recoverOrphans() async throws {}
}

// Fixed: all properties initialized before Task invocation; captures local value lib without capturing self.
@MainActor final class StartupCaptureProbe {
    let localLibrary: RecoveryLibraryProbe
    let networkMonitor: Int
    init() {
        localLibrary = RecoveryLibraryProbe()
        networkMonitor = 1
        let lib = localLibrary
        Task {
            try? await lib.recoverOrphans()
        }
    }
}
