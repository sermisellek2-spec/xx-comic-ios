import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Coordinates and executes batch imports of files and folders into LocalLibrary.
/// Manages execution state through BatchImportSession, ensures security-scoped file access
/// and NSFileCoordinator locks, and appends multi-volume items to series.
public actor BatchImportWorker {

    public struct ProgressUpdate: Equatable, Sendable {
        public let taskId: String
        public let groupIndex: Int
        public let totalGroups: Int
        public let itemIndex: Int
        public let totalItemsInGroup: Int
        public let itemName: String
        public let state: BatchImportSession.State
        public let errorDescription: String?
        public let targetSeriesId: String?
    }

    public struct ResultSummary: Equatable, Sendable {
        public let taskId: String
        public let totalItems: Int
        public let succeededCount: Int
        public let skippedCount: Int
        public let failedCount: Int
        public let cancelled: Bool
        public let seriesIds: [String]
    }

    public typealias ImageProbe = @Sendable (URL) throws -> Bool
    public typealias PdfInspector = @Sendable (URL) throws -> PdfPublication
    public typealias PdfCoverRenderer = @Sendable (URL) throws -> Data?
    public typealias ProgressHandler = @Sendable (ProgressUpdate) -> Void

    public let library: LocalLibrary
    public let session: BatchImportSession
    private let isReadableImage: ImageProbe
    private let inspectPdf: PdfInspector?
    private let renderPdfCover: PdfCoverRenderer?

    private var activeTaskId: String?
    private var isCancelled: Bool = false
    private var isRunning = false

    public enum WorkerError: Error { case alreadyRunning }

    public init(library: LocalLibrary,
                session: BatchImportSession,
                isReadableImage: @escaping ImageProbe = defaultImageProbe,
                inspectPdf: PdfInspector? = nil,
                renderPdfCover: PdfCoverRenderer? = nil) {
        self.library = library
        self.session = session
        self.isReadableImage = isReadableImage
        self.inspectPdf = inspectPdf
        self.renderPdfCover = renderPdfCover
    }

    public static let defaultImageProbe: ImageProbe = { url in
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "webp", "gif", "bmp"].contains(ext)
    }

    public static func createBookmark(for url: URL) throws -> Data {
        #if canImport(Darwin)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return Data(url.path.utf8)
        #endif
    }

    public static func resolveBookmark(_ data: Data) throws -> URL {
        try resolveBookmarkWithState(data).url
    }

    static func resolveBookmarkWithState(_ data: Data) throws -> (url: URL, isStale: Bool) {
        #if canImport(Darwin)
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
        #else
        guard let path = String(data: data, encoding: .utf8), path.hasPrefix("/"), !path.contains("\0") else { throw LocalLibraryError.invalidBook }
        return (URL(fileURLWithPath: path), false)
        #endif
    }

    /// Plans candidates into groups, sets up session, and executes the batch.
    public func planAndExecute(candidates: [BatchImportCandidate],
                               urlMap: [String: URL],
                               progress: ProgressHandler? = nil) async throws -> ResultSummary {
        let groups = BatchImportPlanner.plan(candidates)
        return try await execute(groups: groups, urlMap: urlMap, progress: progress)
    }

    /// Executes specified planner groups.
    public func execute(groups: [BatchImportGroup],
                        urlMap: [String: URL],
                        progress: ProgressHandler? = nil) async throws -> ResultSummary {
        try beginRun()
        defer { endRun() }
        try Task.checkCancellation()
        let sessionGroups: [BatchImportSession.Group] = groups.map { group in
            let items = group.volumes.map { cand in
                BatchImportSession.Item(
                    uri: cand.fileId.isEmpty ? cand.fileName : cand.fileId,
                    name: cand.fileName,
                    format: cand.format.isEmpty ? (cand.fileName as NSString).pathExtension : cand.format,
                    selectionIndex: cand.selectionIndex
                )
            }
            return BatchImportSession.Group(
                key: group.key,
                title: group.title,
                targetBookId: "",
                requiresExistingBook: false,
                items: items
            )
        }

        let snapshot = try await session.create(groups: sessionGroups)
        self.activeTaskId = snapshot.taskId
        self.isCancelled = false
        return try await runImportLoop(taskId: snapshot.taskId, urlMap: urlMap, progress: progress)
    }

    /// Appends multiple files/folders to an existing series as new volumes.
    public func appendVolumes(urls: [URL],
                              toSeriesId seriesId: String,
                              seriesTitle: String,
                              progress: ProgressHandler? = nil) async throws -> ResultSummary {
        try beginRun()
        defer { endRun() }
        try Task.checkCancellation()
        guard let existingSeries = try await library.series(id: seriesId), existingSeries.status == "ready" else {
            throw LocalCatalogError.targetNotFound
        }

        var urlMap: [String: URL] = [:]
        let candidates = try urls.enumerated().map { idx, url in
            let path = url.path
            urlMap[path] = url
            return try BatchImportCandidate(
                sourceId: "local",
                remoteComicId: seriesId,
                seriesTitle: seriesTitle,
                fileName: url.lastPathComponent,
                fileId: path,
                format: url.pathExtension,
                selectionIndex: idx
            )
        }
        let ordered = BatchImportPlanner.orderVolumes(candidates)
        let items = ordered.map { cand in
            BatchImportSession.Item(
                uri: cand.fileId,
                name: cand.fileName,
                format: cand.format,
                selectionIndex: cand.selectionIndex
            )
        }
        let group = BatchImportSession.Group(
            key: "series:\(seriesId)",
            title: seriesTitle,
            targetBookId: seriesId,
            requiresExistingBook: true,
            items: items
        )
        let snapshot = try await session.create(groups: [group])
        self.activeTaskId = snapshot.taskId
        self.isCancelled = false
        return try await runImportLoop(taskId: snapshot.taskId, urlMap: urlMap, progress: progress)
    }

    /// Resumes or retries any unfinished/failed items in the active or loaded session.
    public func resumeSession(urlMap: [String: URL],
                              progress: ProgressHandler? = nil) async throws -> ResultSummary {
        try beginRun()
        defer { endRun() }
        try Task.checkCancellation()
        guard let current = await session.current() else {
            throw BatchImportSession.SessionError.invalidSnapshot
        }
        guard !current.cancelled else { throw BatchImportSession.SessionError.cancelled }
        try await session.retryFailed(taskID: current.taskId)
        self.activeTaskId = current.taskId
        self.isCancelled = false
        return try await runImportLoop(taskId: current.taskId, urlMap: urlMap, progress: progress)
    }

    /// Retries failed items in the current session.
    public func retryFailed(urlMap: [String: URL],
                            progress: ProgressHandler? = nil) async throws -> ResultSummary {
        try beginRun()
        defer { endRun() }
        try Task.checkCancellation()
        guard let current = await session.current() else {
            throw BatchImportSession.SessionError.invalidSnapshot
        }
        guard !current.cancelled else { throw BatchImportSession.SessionError.cancelled }
        try await session.retryFailed(taskID: current.taskId)
        self.activeTaskId = current.taskId
        self.isCancelled = false
        return try await runImportLoop(taskId: current.taskId, urlMap: urlMap, progress: progress)
    }

    /// Signals cancellation of the current active batch import.
    public func cancel() async throws {
        isCancelled = true
        if let taskId = activeTaskId {
            try await session.cancel(taskID: taskId)
        }
    }

    // MARK: - Internal Execution Loop

    private func runImportLoop(taskId: String,
                               urlMap: [String: URL],
                               progress: ProgressHandler?) async throws -> ResultSummary {
        guard let snapshot = await session.current(), snapshot.taskId == taskId else {
            throw BatchImportSession.SessionError.taskMismatch
        }

        var touchedSeriesIds: Set<String> = []

        for (groupIndex, group) in snapshot.groups.enumerated() {
            if isCancelled || Task.isCancelled { break }
            var currentTargetSeriesId: String? = group.targetBookId.isEmpty ? nil : group.targetBookId

            for (itemIndex, item) in group.items.enumerated() {
                if isCancelled || Task.isCancelled { break }

                // Check live state in session before processing
                let liveSnapshot = await session.current()
                if isCancelled || Task.isCancelled || liveSnapshot?.cancelled == true { isCancelled = true; break }
                if let liveItem = liveSnapshot?.groups[groupIndex].items[itemIndex],
                   liveItem.state == .completed || liveItem.state == .skipped {
                    continue
                }

                // Resolve URL
                guard let url = resolveURL(uri: item.uri, urlMap: urlMap) else {
                    let missingMsg = "无法定位待导入文件: \(item.name)"
                    try await session.fail(taskID: taskId, group: groupIndex, item: itemIndex, error: missingMsg)
                    progress?(ProgressUpdate(
                        taskId: taskId, groupIndex: groupIndex, totalGroups: snapshot.groups.count,
                        itemIndex: itemIndex, totalItemsInGroup: group.items.count, itemName: item.name,
                        state: .failed, errorDescription: missingMsg, targetSeriesId: currentTargetSeriesId
                    ))
                    continue
                }

                // Prepare and Publish
                do {
                    try Task.checkCancellation()
                    // Cancellation can arrive during this actor hop, after the
                    // live snapshot check. Treat it as the same user cancellation.
                    try await session.start(taskID: taskId, group: groupIndex, item: itemIndex)
                    progress?(ProgressUpdate(
                        taskId: taskId, groupIndex: groupIndex, totalGroups: snapshot.groups.count,
                        itemIndex: itemIndex, totalItemsInGroup: group.items.count, itemName: item.name,
                        state: .running, errorDescription: nil, targetSeriesId: currentTargetSeriesId
                    ))
                    if isCancelled || Task.isCancelled { throw CancellationError() }
                    let cleanedName = cleanItemTitle(item.name)
                    let prepared = try withSecurityScopeAndCoordination(for: url) { coordinatedURL in
                        try self.prepareItem(url: coordinatedURL, name: cleanedName, format: item.format)
                    }

                    if isCancelled || Task.isCancelled {
                        try library.discardPrepared(prepared)
                        try await session.cancel(taskID: taskId)
                        break
                    }

                    let (series, book) = try await library.publishImport(
                        prepared,
                        targetSeriesId: currentTargetSeriesId,
                        explicitTitle: group.title.isEmpty ? cleanedName : group.title
                    )

                    touchedSeriesIds.insert(series.id)
                    if currentTargetSeriesId == nil {
                        currentTargetSeriesId = series.id
                    }

                    try await session.complete(taskID: taskId, group: groupIndex, item: itemIndex, bookID: currentTargetSeriesId ?? book.id)
                    progress?(ProgressUpdate(
                        taskId: taskId, groupIndex: groupIndex, totalGroups: snapshot.groups.count,
                        itemIndex: itemIndex, totalItemsInGroup: group.items.count, itemName: item.name,
                        state: .completed, errorDescription: nil, targetSeriesId: currentTargetSeriesId
                    ))
                } catch is CancellationError {
                    try await session.cancel(taskID: taskId)
                    isCancelled = true
                    break
                } catch BatchImportSession.SessionError.cancelled {
                    isCancelled = true
                    break
                } catch {
                    let errDesc = error.localizedDescription
                    ErrorLogStore.shared.append(title: "批量导入失败: \(item.name)", error: error)
                    try await session.fail(taskID: taskId, group: groupIndex, item: itemIndex, error: errDesc)
                    progress?(ProgressUpdate(
                        taskId: taskId, groupIndex: groupIndex, totalGroups: snapshot.groups.count,
                        itemIndex: itemIndex, totalItemsInGroup: group.items.count, itemName: item.name,
                        state: .failed, errorDescription: errDesc, targetSeriesId: currentTargetSeriesId
                    ))
                }
            }
        }

        if isCancelled || Task.isCancelled { try await session.cancel(taskID: taskId); isCancelled = true }
        let finalSnapshot = await session.current() ?? snapshot
        var total = 0
        var succeeded = 0
        var skipped = 0
        var failed = 0
        for g in finalSnapshot.groups {
            for it in g.items {
                total += 1
                switch it.state {
                case .completed: succeeded += 1
                case .skipped: skipped += 1
                case .failed: failed += 1
                case .pending, .running: break
                }
            }
        }

        return ResultSummary(
            taskId: taskId,
            totalItems: total,
            succeededCount: succeeded,
            skippedCount: skipped,
            failedCount: failed,
            cancelled: finalSnapshot.cancelled || isCancelled,
            seriesIds: Array(touchedSeriesIds).sorted()
        )
    }

    // MARK: - Helpers

    private func beginRun() throws {
        guard !isRunning else { throw WorkerError.alreadyRunning }
        isRunning = true
    }

    private func endRun() {
        isRunning = false
        activeTaskId = nil
    }

    private func cleanItemTitle(_ name: String) -> String {
        var result = (name as NSString).deletingPathExtension
        if result.isEmpty { result = name }
        return SearchRules.trim(result)
    }

    private func resolveURL(uri: String, urlMap: [String: URL]) -> URL? {
        guard let mapped = urlMap[uri], mapped.isFileURL else { return nil }
        return mapped
    }

    private func prepareItem(url: URL, name: String, format: String) throws -> PreparedLocalImport {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return try library.prepareFolder(title: name, folder: url, isReadableImage: isReadableImage)
        }

        let ext = (url.pathExtension.isEmpty ? format : url.pathExtension).lowercased()
        switch ext {
        case "zip", "cbz":
            return try library.prepareArchive(title: name, archive: url, isReadableImage: isReadableImage)
        case "epub":
            return try library.prepareEpub(title: name, archive: url, isReadableImage: isReadableImage)
        case "pdf":
            guard let inspect = inspectPdf, let renderCover = renderPdfCover else {
                throw LocalLibraryError.invalidArchive
            }
            return try library.preparePdf(title: name, file: url, inspect: inspect, renderCover: renderCover)
        case "mobi", "azw", "azw3":
            guard let kindleFormat = LocalKindleFormat(rawValue: ext) else {
                throw LocalLibraryError.invalidArchive
            }
            return try library.prepareKindle(title: name, source: url, format: kindleFormat, isReadableImage: isReadableImage)
        case "jpg", "jpeg", "png", "webp", "gif", "bmp":
            return try library.prepareImages(title: name, files: [url])
        default:
            return try library.prepareArchive(title: name, archive: url, isReadableImage: isReadableImage)
        }
    }

    private func withSecurityScopeAndCoordination<T>(for url: URL, block: (URL) throws -> T) throws -> T {
        #if canImport(Darwin)
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var coordinatorError: NSError?
        var result: Result<T, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { coordinatedURL in
            do {
                let value = try block(coordinatedURL)
                result = .success(value)
            } catch {
                result = .failure(error)
            }
        }
        if let coordinatorError {
            throw coordinatorError
        }
        if let result {
            return try result.get()
        }
        throw LocalLibraryError.invalidBook
        #else
        return try block(url)
        #endif
    }
}
