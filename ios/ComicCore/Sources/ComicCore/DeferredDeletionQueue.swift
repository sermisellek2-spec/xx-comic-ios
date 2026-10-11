import Foundation

public enum LocalDeletionTarget: Hashable, Sendable {
    case localSeries(String)
    case downloadBook(String)
}

/// Owns the undo window independently of the presenting page. A process exit
/// during the window leaves the copies intact, as in Android's pending UI state.
public actor DeferredDeletionQueue {
    private struct Pending {
        let token: UUID
        let task: Task<Void, Never>
    }
    private var waiting: [LocalDeletionTarget: Pending] = [:]
    private var committing = Set<LocalDeletionTarget>()
    private let delay: UInt64
    private let operation: @Sendable (LocalDeletionTarget) async throws -> Void
    private let onChange: @Sendable (Set<LocalDeletionTarget>, Set<LocalDeletionTarget>) -> Void
    private let onResult: @Sendable (LocalDeletionTarget, Result<Void, Error>) -> Void

    public init(delayNanoseconds: UInt64 = 3_500_000_000,
                operation: @escaping @Sendable (LocalDeletionTarget) async throws -> Void,
                onChange: @escaping @Sendable (Set<LocalDeletionTarget>, Set<LocalDeletionTarget>) -> Void = { _, _ in },
                onResult: @escaping @Sendable (LocalDeletionTarget, Result<Void, Error>) -> Void = { _, _ in }) {
        delay = delayNanoseconds; self.operation = operation; self.onChange = onChange; self.onResult = onResult
    }

    public func schedule(_ targets: [LocalDeletionTarget]) {
        for target in targets where !committing.contains(target) {
            waiting[target]?.task.cancel()
            let token = UUID(), duration = delay
            let task = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: duration) } catch { return }
                await self?.commit(target, token: token)
            }
            waiting[target] = Pending(token: token, task: task)
        }
        changed()
    }

    @discardableResult
    public func undo(_ targets: [LocalDeletionTarget]) -> Set<LocalDeletionTarget> {
        var restored = Set<LocalDeletionTarget>()
        for target in targets {
            if let pending = waiting.removeValue(forKey: target) { pending.task.cancel(); restored.insert(target) }
        }
        changed(); return restored
    }
    public var hiddenTargets: Set<LocalDeletionTarget> { Set(waiting.keys).union(committing) }
    private func changed() { onChange(Set(waiting.keys), committing) }
    private func commit(_ target: LocalDeletionTarget, token: UUID) async {
        guard waiting[target]?.token == token else { return }
        waiting.removeValue(forKey: target); committing.insert(target); changed()
        let result: Result<Void, Error>
        do { try await operation(target); result = .success(()) } catch { result = .failure(error) }
        committing.remove(target); changed(); onResult(target, result)
    }
}
