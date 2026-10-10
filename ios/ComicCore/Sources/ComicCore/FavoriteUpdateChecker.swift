import Foundation

/// Checks online favorites for new chapter updates and coordinates red-dot badges.
public final class FavoriteUpdateChecker: @unchecked Sendable {
    public typealias SourceProvider = @Sendable (String) -> (any ComicSource)?

    private let library: LibraryStore
    private let coordinator: FavoriteUpdateCoordinator
    private let sourceProvider: SourceProvider
    private let lock = NSLock()
    private var checkTask: Task<Void, Never>?

    public init(
        library: LibraryStore,
        coordinator: FavoriteUpdateCoordinator,
        sourceProvider: @escaping SourceProvider
    ) {
        self.library = library
        self.coordinator = coordinator
        self.sourceProvider = sourceProvider
    }

    /// Checks all online favorites for new chapter updates.
    /// Returns a dictionary of "sourceId:comicId" -> hasPendingUpdate.
    @discardableResult
    public func checkAllFavorites() async -> [String: Bool] {
        let favorites = library.favorites.filter { $0.summary.sourceId != "local" }
        var results: [String: Bool] = [:]

        for entry in favorites {
            if Task.isCancelled { break }
            let comic = entry.summary
            guard let source = sourceProvider(comic.sourceId) else { continue }
            do {
                let detail = try await source.detail(comicId: comic.comicId)
                let revision = FavoriteRevision.fromChapters(
                    latestChapterName: detail.latestChapter,
                    chapters: detail.chapters
                )
                coordinator.recordObserved(
                    sourceId: comic.sourceId,
                    comicId: comic.comicId,
                    revision: revision
                )
                let hasUpdate = coordinator.hasPendingUpdate(
                    sourceId: comic.sourceId,
                    comicId: comic.comicId
                )
                results["\(comic.sourceId):\(comic.comicId)"] = hasUpdate
            } catch {
                // Network errors or offline skips gracefully without corrupting baseline
                continue
            }
        }

        return results
    }

    /// Initiates a background check task for all online favorites.
    public func startAutoCheck() {
        lock.lock()
        defer { lock.unlock() }
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            _ = await self?.checkAllFavorites()
        }
    }

    /// Cancels any active update check.
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        checkTask?.cancel()
        checkTask = nil
    }
}
