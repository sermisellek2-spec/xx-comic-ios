import Foundation

// Retains the production engine's class isolation and detached helper call.
@MainActor final class EnhancementActorProbe {
    nonisolated private static func enhanceNeural() throws -> Int { 1 }
    func enhance() async -> Int {
        do {
            return try await Task.detached(priority: .userInitiated) { () -> Int in
                return try Self.enhanceNeural()
            }.value
        } catch { return 0 }
    }
}
