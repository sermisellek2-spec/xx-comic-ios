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

    /// Checks a single comic against source and optional baseline revision, matching Android's FavoriteUpdateChecker.java.
    public static func check(
        source: any ComicSource,
        comicId: String,
        baseline: FavoriteRevision?
    ) async -> FavoriteRevision? {
        guard !comicId.isEmpty else { return nil }
        do {
            let detail = try await source.detail(comicId: comicId)
            // If detail already contains full chapters, use them
            if !detail.chapters.isEmpty {
                return FavoriteRevision.fromChapters(
                    latestChapterName: detail.latestChapter,
                    chapters: detail.chapters
                )
            }

            // If baseline relied on CHAPTER_SET or detail has no reliable chapter evidence,
            // call chapters() to obtain reliable chapter IDs
            let needChapters = baseline != nil && baseline?.mode == FavoriteRevision.modeChapterSet
            let latestChapterEmpty = detail.latestChapter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if needChapters || latestChapterEmpty {
                do {
                    let chapters = try await source.chapters(comicId: comicId)
                    if !chapters.isEmpty {
                        return FavoriteRevision.fromChapters(
                            latestChapterName: detail.latestChapter,
                            chapters: chapters
                        )
                    }
                } catch {
                    // chapters() failed, fall back to detail if it has comparable info
                }
            }

            // Fall back to detail snapshot
            if !latestChapterEmpty {
                return FavoriteRevision.fromDetail(detail)
            }
            return nil
        } catch {
            // All errors (network, timeout, Cloudflare verification, retired source) are captured silently
            return nil
        }
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
            let baseline = coordinator.state(sourceId: comic.sourceId, comicId: comic.comicId)?.acknowledgedRevision
            guard let revision = await Self.check(
                source: source,
                comicId: comic.comicId,
                baseline: baseline
            ) else {
                continue
            }
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
