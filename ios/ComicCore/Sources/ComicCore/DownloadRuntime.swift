import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol DownloadImageFetcherProtocol: Sendable {
    func fetch(sourceId: String,
               url: String,
               referer: String,
               destination: URL,
               check: @escaping () throws -> Void) async throws -> (bytes: Int64, hash: String)
}

public protocol DownloadSourceResolverProtocol: Sendable {
    func resolveChapter(sourceId: String, url: String) async throws -> ChapterPage
    func resolveReferer(sourceId: String, chapterUrl: String) -> String
    func resolveImageUrl(sourceId: String, imageUrl: String, force: Bool) async throws -> String
    func fetchCover(sourceId: String, coverUrl: String, destination: URL, check: @escaping () throws -> Void) async throws
}

public extension DownloadSourceResolverProtocol {
    func resolveImageUrl(sourceId: String, imageUrl: String, force: Bool) async throws -> String {
        imageUrl
    }
}

public enum ImageValidator {
    public static func isValidImage(data: Data) -> Bool {
        if data.count < 4 { return false }
        if data.starts(with: [0xff, 0xd8, 0xff]) { return true } // JPEG
        if data.starts(with: [0x89, 0x50, 0x4e, 0x47]) { return true } // PNG
        if data.starts(with: "GIF87a".utf8) || data.starts(with: "GIF89a".utf8) { return true } // GIF
        if data.starts(with: "RIFF".utf8) && data.count >= 12 && data.dropFirst(8).starts(with: "WEBP".utf8) { return true } // WebP
        if data.starts(with: [0x42, 0x4d]) { return true } // BMP
        return false
    }

    public static func isTextOrHtml(data: Data) -> Bool {
        guard let text = String(data: data.prefix(256), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return text.hasPrefix("<!doctype") || text.hasPrefix("<html") || text.hasPrefix("<?xml") || text.hasPrefix("{") || text.hasPrefix("[")
    }
}

public final class DefaultDownloadImageFetcher: DownloadImageFetcherProtocol, @unchecked Sendable {
    public static let shared = DefaultDownloadImageFetcher()
    public static let maxPageBytes: Int64 = 128 * 1024 * 1024 // 128 MiB

    public init() {}

    public func fetch(sourceId: String,
                      url: String,
                      referer: String,
                      destination: URL,
                      check: @escaping () throws -> Void) async throws -> (bytes: Int64, hash: String) {
        try check()
        let cleanUrl = PublicSourceImages.strip(url)
        guard let requestUrl = URL(string: cleanUrl) else {
            throw DownloadError.corruptedData("无效的图片地址")
        }
        var request = URLRequest(url: requestUrl)
        request.timeoutInterval = 25
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let effectiveReferer = PublicSourceImages.referer(url, fallback: referer)
        if !effectiveReferer.isEmpty {
            request.setValue(effectiveReferer, forHTTPHeaderField: "Referer")
        }

        let destDir = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destDir.path) {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        }

        final class ImageStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
            let destination: URL
            let maxBytes: Int64
            let check: () throws -> Void

            private(set) var written: Int64 = 0
            private(set) var expectedLength: Int64 = -1
            private(set) var statusCode: Int = 0
            private(set) var streamError: Error?
            private var fileHandle: FileHandle?
            private var continuation: CheckedContinuation<Void, Error>?
            private let lock = NSLock()
            private var isResumed = false

            init(destination: URL, maxBytes: Int64, check: @escaping () throws -> Void) {
                self.destination = destination
                self.maxBytes = maxBytes
                self.check = check
            }

            func attachContinuation(_ cont: CheckedContinuation<Void, Error>) {
                self.continuation = cont
            }

            private func finish(error: Error?) {
                lock.lock()
                guard !isResumed else {
                    lock.unlock()
                    return
                }
                isResumed = true
                let cont = self.continuation
                self.continuation = nil
                lock.unlock()

                try? fileHandle?.close()
                fileHandle = nil

                if let error {
                    cont?.resume(throwing: error)
                } else {
                    cont?.resume(returning: ())
                }
            }

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                guard let http = response as? HTTPURLResponse else {
                    streamError = DownloadError.corruptedData("无效的服务器响应")
                    completionHandler(.cancel)
                    return
                }
                statusCode = http.statusCode
                if statusCode == 206 {
                    streamError = DownloadError.corruptedData("图片下载不接受部分响应")
                    completionHandler(.cancel)
                    return
                }
                if statusCode != 200 {
                    let retryHeader = http.allHeaderFields["Retry-After"] as? String
                    let retryDelay = (retryHeader.flatMap { Double($0) } ?? (statusCode == 429 ? 60 : 0)) * 1000
                    streamError = DownloadHTTPError(statusCode: statusCode, retryAfterMs: Int64(retryDelay))
                    completionHandler(.cancel)
                    return
                }

                if let type = (http.allHeaderFields.first { $0.key.description.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value as? String)?.lowercased() {
                    if type.contains("text/") || type.contains("json") {
                        streamError = DownloadError.corruptedData("服务器返回了网页，未下载图片")
                        completionHandler(.cancel)
                        return
                    }
                }

                if let cl = (http.allHeaderFields.first { $0.key.description.caseInsensitiveCompare("Content-Length") == .orderedSame }?.value as? String).flatMap({ Int64($0) }) {
                    expectedLength = cl
                    if cl > maxBytes {
                        streamError = DownloadError.corruptedData("单页超过 128MiB 限制")
                        completionHandler(.cancel)
                        return
                    }
                }

                do {
                    let empty = Data()
                    try empty.write(to: destination, options: .atomic)
                    fileHandle = try FileHandle(forWritingTo: destination)
                    written = 0
                    completionHandler(.allow)
                } catch {
                    streamError = error
                    completionHandler(.cancel)
                }
            }

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                do {
                    try check()
                } catch {
                    streamError = error
                    dataTask.cancel()
                    return
                }

                written += Int64(data.count)
                if written > maxBytes {
                    streamError = DownloadError.corruptedData("单页超过 128MiB 限制")
                    dataTask.cancel()
                    return
                }

                fileHandle?.write(data)
            }

            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let err = streamError ?? error {
                    finish(error: err)
                } else {
                    finish(error: nil)
                }
            }
        }

        let delegate = ImageStreamDelegate(destination: destination, maxBytes: Self.maxPageBytes, check: check)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.attachContinuation(continuation)
                    let task = session.dataTask(with: request)
                    task.resume()
                }
            } onCancel: {
                session.invalidateAndCancel()
            }

            try check()

            if delegate.written == 0 {
                throw DownloadError.corruptedData("图片文件为空")
            }
            if delegate.expectedLength >= 0 && delegate.written != delegate.expectedLength {
                throw DownloadError.corruptedData("图片传输不完整，请重试")
            }

            var rawData = try Data(contentsOf: destination)
            if !PublicSourceImages.sourceId(url).isEmpty || PublicSourceRegistry.contains(sourceId) {
                let decoded = try PublicSourceImages.decodeForSource(sourceId: sourceId, url: url, data: rawData)
                if decoded != rawData {
                    try decoded.write(to: destination, options: .atomic)
                    rawData = decoded
                }
            } else if sourceId == "xinmanhua" || XinmanhuaImageDecoder.usesImageHost(url) {
                let decoded = try XinmanhuaImageDecoder.decode(rawData)
                if decoded != rawData {
                    try decoded.write(to: destination, options: .atomic)
                    rawData = decoded
                }
            } else if sourceId == "manwa" || ManwaImageDecoder.usesImageHost(url) {
                let decoded = try ManwaImageDecoder.decode(rawData)
                if decoded != rawData {
                    try decoded.write(to: destination, options: .atomic)
                    rawData = decoded
                }
            }

            if ImageValidator.isTextOrHtml(data: rawData) {
                throw DownloadError.corruptedData("服务器返回了网页，未下载图片")
            }

            guard ImageValidator.isValidImage(data: rawData) else {
                throw DownloadError.corruptedData("图片格式不受支持或文件损坏")
            }

            let hash = DownloadModels.sha256Hex(rawData)
            return (bytes: Int64(rawData.count), hash: hash)

        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}


public struct DownloadHTTPError: LocalizedError, Equatable, Sendable {
    public let statusCode: Int
    public let retryAfterMs: Int64

    public var errorDescription: String? {
        "图片请求失败 HTTP \(statusCode)"
    }
}

public final class DownloadRuntime: @unchecked Sendable {
    public static let maxActiveWorkers = 2

    public let store: DownloadStore
    public let queue: DownloadCoordinator
    public let downloadsDirectory: URL
    public let storageLocations: DownloadStorageLocations?

    private let lock = NSLock()
    private var activeWorkers = Set<String>()
    private var deletingBookIDs = Set<String>()
    private var deletingTaskIDs = Set<String>()
    private var isInitialized = false

    public var isWifiOnly: Bool = true
    public var isNetworkConnected: Bool = true
    public var isWifiConnected: Bool = true

    public var imageFetcher: DownloadImageFetcherProtocol
    public var fileWorker: FileDownloadWorker
    public var sourceResolver: DownloadSourceResolverProtocol?
    public var fileSourceResolver: ((_ sourceId: String) -> FileSourceCapability?)?
    public var onTaskCompleted: ((DownloadTask) -> Void)?

    public init(store: DownloadStore,
                downloadsDirectory: URL,
                imageFetcher: DownloadImageFetcherProtocol = DefaultDownloadImageFetcher.shared,
                fileWorker: FileDownloadWorker = FileDownloadWorker(),
                sourceResolver: DownloadSourceResolverProtocol? = nil,
                fileSourceResolver: ((_ sourceId: String) -> FileSourceCapability?)? = nil,
                storageLocations: DownloadStorageLocations? = nil) {
        self.store = store
        self.queue = DownloadCoordinator(repository: store)
        self.downloadsDirectory = downloadsDirectory
        self.storageLocations = storageLocations
        self.imageFetcher = imageFetcher
        self.fileWorker = fileWorker
        self.sourceResolver = sourceResolver
        self.fileSourceResolver = fileSourceResolver

        if !FileManager.default.fileExists(atPath: downloadsDirectory.path) {
            try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        }

        // Recover interrupted tasks on startup
        queue.recover()
        isInitialized = true
        let recovered = store.list()
        Task.detached(priority: .utility) { [weak self] in self?.cleanResidualPartFiles(tasks: recovered) }
    }

    private func cleanResidualPartFiles(tasks: [DownloadTask]) {
        let manager = FileManager.default
        // Never recursively scan the downloads root or delete arbitrary user .part files.
        guard (try? validateDirectoryIfPresent(downloadsDirectory)) != nil,
              let entries = try? manager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            for task in tasks where entry.lastPathComponent.hasPrefix("stage_" + task.id + "_") {
                let generation = String(entry.lastPathComponent.dropFirst(("stage_" + task.id + "_").count))
                guard let value = Int64(generation), value != task.generation else { continue }
                try? removeStagingDirectory(entry)
            }
        }
    }

    private func stagingDirectory(_ task: DownloadTask) throws -> URL {
        guard task.id == (try DownloadModels.key(task.sourceId, task.comicId, task.chapterId)) else { throw DownloadError.invalidIdentity }
        try validateDirectoryIfPresent(downloadsDirectory)
        let directory = downloadsDirectory.appendingPathComponent("stage_" + task.id + "_" + String(task.generation), isDirectory: true)
        try validateDirectoryIfPresent(directory)
        if !FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) }
        return directory
    }
    private func removeStagingDirectory(_ directory: URL) throws {
        try validateDirectoryIfPresent(downloadsDirectory)
        try validateDirectoryIfPresent(directory)
        guard directory.deletingLastPathComponent().standardizedFileURL == downloadsDirectory.standardizedFileURL,
              directory.lastPathComponent.range(of: #"^stage_[a-f0-9]{64}_\d+$"#, options: .regularExpression) != nil else { throw DownloadError.invalidIdentity }
        if !FileManager.default.fileExists(atPath: directory.path) { return }
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for entry in entries {
            guard entry.lastPathComponent == "cover.part" || entry.lastPathComponent.range(of: #"^\d+\.part$"#, options: .regularExpression) != nil else { throw DownloadLocationError.unsafePath }
            try validateRegularFileIfPresent(entry)
        }
        try FileManager.default.removeItem(at: directory)
    }

    public func updateNetworkStatus(isConnected: Bool, isWifi: Bool) {
        lock.lock()
        let prevAllowed = isNetworkConnected && (!isWifiOnly || isWifiConnected)
        self.isNetworkConnected = isConnected
        self.isWifiConnected = isWifi
        let nowAllowed = isConnected && (!isWifiOnly || isWifi)
        lock.unlock()

        if !nowAllowed {
            lock.lock()
            for t in store.list() {
                if DownloadModels.active(t.state) || t.state == .queued {
                    queue.waitForNetwork(t)
                }
            }
            lock.unlock()
        } else if !prevAllowed && nowAllowed {
            lock.lock()
            queue.recoverNetwork()
            kickLocked()
            lock.unlock()
        }
    }

    public func enqueueFiles(detail: ComicDetail, files: [FileResource], selected: [String]) {
        lock.lock()
        defer { lock.unlock() }
        let available = selected.filter { id in
            guard let book = try? DownloadModels.fileBookId(source: detail.summary.sourceId, comic: detail.summary.comicId, file: id) else { return false }
            guard let task = try? DownloadModels.fileTaskId(source: detail.summary.sourceId, comic: detail.summary.comicId, file: id) else { return false }
            return !deletingBookIDs.contains(book) && !deletingTaskIDs.contains(task)
        }
        store.saveSnapshot(detail)
        queue.enqueueFiles(source: detail.summary.sourceId,
                           comic: detail.summary.comicId,
                           files: files,
                           selected: available)
        kickLocked()
    }

    public func enqueue(detail: ComicDetail, selectedChapterIds: [String]) {
        try? enqueuePrepared(detail: detail, selectedChapterIds: selectedChapterIds)
    }
    private func enqueuePrepared(detail: ComicDetail, selectedChapterIds: [String]) throws {
        lock.lock()
        defer { lock.unlock() }
        let book = try DownloadModels.bookId(source: detail.summary.sourceId, comic: detail.summary.comicId)
        let selectedTasks = try selectedChapterIds.map { try DownloadModels.key(detail.summary.sourceId, detail.summary.comicId, $0) }
        guard !deletingBookIDs.contains(book), !selectedTasks.contains(where: deletingTaskIDs.contains) else { throw DownloadError.corruptedData("正在删除此下载，请完成后重试") }
        store.saveSnapshot(detail)
        queue.enqueue(source: detail.summary.sourceId,
                      comic: detail.summary.comicId,
                      chapters: detail.chapters,
                      selected: selectedChapterIds)
        kickLocked()
    }

    /// Prepare persistent ownership and permission on a worker before showing enqueue success.
    public func enqueueWithLocation(detail: ComicDetail, selectedChapterIds: [String]) async throws {
        let requestedLocation = storageLocations?.selectedID
        let worker = Task.detached(priority: .utility) { [self] in
            try Task.checkCancellation()
            if let storageLocations {
                for chapter in detail.chapters where selectedChapterIds.contains(chapter.chapterId) {
                    let task = DownloadTask(id: try DownloadModels.key(detail.summary.sourceId, detail.summary.comicId, chapter.chapterId),
                        bookId: try DownloadModels.bookId(source: detail.summary.sourceId, comic: detail.summary.comicId),
                        sourceId: detail.summary.sourceId, comicId: detail.summary.comicId, chapterId: chapter.chapterId, title: chapter.title)
                    try storageLocations.prepare(task, comicTitle: detail.summary.title, locationID: requestedLocation)
                }
            }
            try Task.checkCancellation()
        }
        try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        try enqueuePrepared(detail: detail, selectedChapterIds: selectedChapterIds)
    }
    public func bookDirectory(bookID: String) throws -> URL {
        if let storageLocations { return try storageLocations.bookDirectory(bookID: bookID) }
        guard !bookID.isEmpty, !bookID.contains("/"), !bookID.contains("\\"), bookID != ".", bookID != ".." else { throw DownloadError.invalidIdentity }
        try validateDirectoryIfPresent(downloadsDirectory)
        let book = downloadsDirectory.appendingPathComponent(bookID, isDirectory: true)
        try validateDirectoryIfPresent(book)
        return book
    }
    private func validateDirectoryIfPresent(_ directory: URL) throws {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: directory.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return }
        let type = attributes[.type] as? FileAttributeType
        guard type == .typeDirectory else { throw DownloadLocationError.unsafePath }
    }
    private func validateRegularFileIfPresent(_ file: URL) throws {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: file.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw DownloadLocationError.unsafePath }
    }
    private func chapterDirectory(_ task: DownloadTask, create: Bool = false) throws -> URL {
        if let storageLocations { return try storageLocations.chapterDirectory(task, create: create) }
        let chapter = try bookDirectory(bookID: task.bookId).appendingPathComponent(task.id, isDirectory: true)
        try validateDirectoryIfPresent(chapter)
        return chapter
    }
    private func pageURL(_ page: DownloadPage, task: DownloadTask) throws -> URL {
        if let storageLocations { return try storageLocations.pageURL(page, task: task) }
        guard page.path == "\(task.bookId)/\(task.id)/\(page.index).img", page.index >= 0 else { throw DownloadError.invalidIdentity }
        return try chapterDirectory(task).appendingPathComponent("\(page.index).img")
    }

    private func withBookDirectory<T>(_ bookID: String, access: FileAccessCoordinator.Access, body: (URL) throws -> T) throws -> T {
        if let storageLocations { return try storageLocations.withBookDirectory(bookID: bookID, access: access, body: body) }
        let book = try bookDirectory(bookID: bookID)
        return try FileAccessCoordinator.system.coordinate(book, access: access) { coordinated in
            guard coordinated.standardizedFileURL == book.standardizedFileURL else { throw DownloadError.invalidIdentity }
            try validateDirectoryIfPresent(downloadsDirectory); try validateDirectoryIfPresent(coordinated)
            return try body(coordinated)
        }
    }
    private func chapterDirectory(_ task: DownloadTask, in book: URL, create: Bool = false) throws -> URL {
        if let storageLocations { return try storageLocations.chapterDirectory(task, in: book, create: create) }
        guard !task.id.isEmpty, !task.id.contains("/"), !task.id.contains("\\"), task.id != ".", task.id != ".." else { throw DownloadError.invalidIdentity }
        let chapter = book.appendingPathComponent(task.id, isDirectory: true)
        try validateDirectoryIfPresent(chapter)
        if create, !FileManager.default.fileExists(atPath: chapter.path) { try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true) }
        return chapter
    }

    private func publish(_ staged: URL, to target: URL, task: DownloadTask) throws {
        try checkLease(task)
        try validateRegularFileIfPresent(staged); try validateRegularFileIfPresent(target)
        // Copy to the provider's volume, then atomically publish without first unlinking the old page.
        let publicationName = task.isFileTask ? ".xxcomic-publish-" + task.id
            : target.lastPathComponent == "cover.img" ? ".xxcomic-cover-" + task.id + ".part"
            : target.deletingPathExtension().lastPathComponent + "." + String(task.generation) + ".part"
        let publication = target.deletingLastPathComponent().appendingPathComponent(publicationName)
        try validateRegularFileIfPresent(publication)
        if FileManager.default.fileExists(atPath: publication.path) { try FileManager.default.removeItem(at: publication) }
        try FileManager.default.copyItem(at: staged, to: publication)
        do {
            try checkLease(task); try validateRegularFileIfPresent(target)
            try Self.renameReplacing(publication, target)
        } catch { try? FileManager.default.removeItem(at: publication); throw error }
        try FileManager.default.removeItem(at: staged)
    }
    private static func renameReplacing(_ source: URL, _ destination: URL) throws {
        // POSIX rename is atomic on one volume and preserves the old target if publication fails.
        let status = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in rename(from!, to!) }
        }
        if status != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    public func kick() {
        lock.lock()
        defer { lock.unlock() }
        kickLocked()
    }

    private func kickLocked() {
        guard isInitialized else { return }
        while activeWorkers.count < Self.maxActiveWorkers {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            guard let task = queue.claim(now: nowMs,
                                         connected: isNetworkConnected,
                                         wifi: isWifiConnected,
                                         wifiOnly: isWifiOnly,
                                         maxActive: Self.maxActiveWorkers,
                                         maxPerSource: Self.maxActiveWorkers) else {
                return
            }
            activeWorkers.insert(task.id)

            Task.detached { [weak self, task] in
                guard let self else { return }
                defer {
                    self.lock.lock()
                    self.activeWorkers.remove(task.id)
                    self.kickLocked()
                    self.lock.unlock()
                }
                await self.downloadTask(task)
            }
        }
    }

    public func pauseAll() {
        lock.lock()
        defer { lock.unlock() }
        for t in store.list() {
            if DownloadModels.active(t.state) || t.state == .queued || t.state == .waitingNetwork {
                queue.pause(id: t.id)
            }
        }
    }

    public func resumeAll() {
        lock.lock()
        defer { lock.unlock() }
        for t in store.list() {
            if t.state == .pausedUser {
                queue.resume(id: t.id)
            }
        }
        kickLocked()
    }

    public func cancel(id: String) async throws { try await deleteChapter(id: id) }
    /// Android's completed-chapter action deletes the owned copy and requeues the
    /// same identity. Online favorites and reading positions belong to another store.
    public func redownloadChapter(id: String) async throws {
        guard let original = store.get(id: id), original.state == .completed else { throw DownloadError.corruptedData("此章节尚未完成，请使用继续或重试") }
        try await deleteChapter(id: id)
        try requeueCompleted(original)
    }
    private func requeueCompleted(_ original: DownloadTask) throws {
        lock.lock(); defer { lock.unlock() }
        guard !deletingBookIDs.contains(original.bookId), !deletingTaskIDs.contains(original.id) else { throw DownloadError.corruptedData("正在删除下载书籍，请稍后重新下载") }
        if store.get(id: original.id) == nil {
            var retry = original
            retry.state = .queued; retry.generation = DownloadCoordinator.nextGeneration()
            retry.failures = 0; retry.donePages = 0; retry.totalPages = 0; retry.bytes = 0
            retry.error = ""; retry.nextAttempt = 0
            try store.saveConfirmedTask(retry)
        }
        kickLocked()
    }
    private func beginChapterDeletion(_ id: String) throws -> DownloadTask {
        lock.lock(); defer { lock.unlock() }
        guard let original = store.get(id: id), !deletingTaskIDs.contains(id), !deletingBookIDs.contains(original.bookId) else { throw DownloadError.corruptedData("任务不存在或正在删除") }
        let expectedBook = original.isFileTask ? try DownloadModels.fileBookId(source: original.sourceId, comic: original.comicId, file: original.fileId ?? original.chapterId) : try DownloadModels.bookId(source: original.sourceId, comic: original.comicId)
        let expectedTask = original.isFileTask ? try DownloadModels.fileTaskId(source: original.sourceId, comic: original.comicId, file: original.fileId ?? original.chapterId) : try DownloadModels.key(original.sourceId, original.comicId, original.chapterId)
        guard original.bookId == expectedBook, original.id == expectedTask else { throw DownloadError.invalidIdentity }
        var invalidated = original; invalidated.generation = DownloadCoordinator.nextGeneration(); invalidated.state = .deleting
        deletingTaskIDs.insert(id); store.save(task: invalidated)
        return original
    }
    private func endChapterDeletion(_ original: DownloadTask, success: Bool, changedFiles: Bool) {
        lock.lock(); defer { lock.unlock() }; deletingTaskIDs.remove(original.id)
        guard !success else { return }
        var restored = original; restored.generation = DownloadCoordinator.nextGeneration()
        if changedFiles { restored.state = .failed; restored.error = "删除未完成，请重试" }
        else if DownloadModels.active(restored.state) || restored.state == .queued || restored.state == .waitingNetwork { restored.state = .pausedUser }
        store.save(task: restored)
    }
    public func deleteChapter(id: String) async throws {
        try Task.checkCancellation()
        let original = try beginChapterDeletion(id)
        var success = false, changedFiles = false
        defer { endChapterDeletion(original, success: success, changedFiles: changedFiles) }
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while bookHasActiveWorkers([original]) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw DownloadError.corruptedData("下载尚未停止，请稍后重试") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let work = downloadsDirectory.appendingPathComponent("work_" + original.id, isDirectory: true)
        if original.isFileTask {
            try validateDirectoryIfPresent(downloadsDirectory)
            try DownloadOwnedDirectory.validate(work, allowedDirectories: [], allowedFiles: [], taskIDs: [], partPrefix: original.chapterId)
        }
        try withBookDirectory(original.bookId, access: original.isFileTask ? .delete : .write) { book in
            let directory = original.isFileTask ? book : try chapterDirectory(original, in: book)
            if original.isFileTask {
                try DownloadOwnedDirectory.validate(directory, allowedDirectories: [], allowedFiles: Set([original.chapterId + "." + original.expectedFormat,
                    ".xxcomic-publish-" + original.id, "cover.img"]).union(storageLocations?.hasOwnershipMarker(bookID: original.bookId) == true ? [DownloadStorageLocations.ownershipFile] : []), taskIDs: [])
            } else {
                try DownloadOwnedDirectory.validate(directory, allowedDirectories: [], allowedFiles: [], taskIDs: [], pageFilesAtRoot: true)
            }
            try Task.checkCancellation(); changedFiles = true
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        }
        if original.isFileTask, FileManager.default.fileExists(atPath: work.path) { try FileManager.default.removeItem(at: work) }
        try store.removeConfirmedTask(id)
        if original.isFileTask { try storageLocations?.removeMapping(bookID: original.bookId) }
        success = true
    }

    private func beginBookDeletion(_ bookId: String) throws -> [DownloadTask] {
        lock.lock()
        defer { lock.unlock() }
        guard !deletingBookIDs.contains(bookId) else { throw DownloadError.corruptedData("正在删除此下载书籍") }
        let tasks = store.list().filter { $0.bookId == bookId }
        guard !tasks.isEmpty else { throw DownloadError.invalidIdentity }
        guard !tasks.contains(where: { deletingTaskIDs.contains($0.id) }) else { throw DownloadError.corruptedData("章节正在删除，请稍后重试") }
        for task in tasks {
            let expected = task.isFileTask
                ? try DownloadModels.fileBookId(source: task.sourceId, comic: task.comicId, file: task.fileId ?? task.chapterId)
                : try DownloadModels.bookId(source: task.sourceId, comic: task.comicId)
            let taskID = task.isFileTask
                ? try DownloadModels.fileTaskId(source: task.sourceId, comic: task.comicId, file: task.fileId ?? task.chapterId)
                : try DownloadModels.key(task.sourceId, task.comicId, task.chapterId)
            guard bookId == expected, task.id == taskID else { throw DownloadError.invalidIdentity }
        }
        deletingBookIDs.insert(bookId)
        for var t in tasks {
            t.generation = DownloadCoordinator.nextGeneration()
            t.state = .deleting
            store.save(task: t)
        }
        return tasks
    }
    private func bookHasActiveWorkers(_ tasks: [DownloadTask]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return tasks.contains { activeWorkers.contains($0.id) }
    }
    private func endBookDeletion(_ bookId: String, failedTasks: [DownloadTask]?, changedFiles: Bool) {
        lock.lock(); defer { lock.unlock() }
        deletingBookIDs.remove(bookId)
        for var task in failedTasks ?? [] {
            task.generation = DownloadCoordinator.nextGeneration()
            if changedFiles { task.state = .failed; task.error = "删除未完成，请重试" }
            else if DownloadModels.active(task.state) || task.state == .queued || task.state == .waitingNetwork { task.state = .pausedUser }
            store.save(task: task)
        }
    }
    public func deleteBook(bookId: String) async throws {
        try Task.checkCancellation()
        let tasks = try beginBookDeletion(bookId)
        var success = false, changedFiles = false
        defer { endBookDeletion(bookId, failedTasks: success ? nil : tasks, changedFiles: changedFiles) }
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while bookHasActiveWorkers(tasks) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw DownloadError.corruptedData("下载任务尚未停止，请稍后重试删除") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let root = downloadsDirectory.standardizedFileURL
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw DownloadError.invalidIdentity }
        let taskIDs = Set(tasks.map { storageLocations?.chapterName($0) ?? $0.id })
        let knownPages = try tasks.flatMap { task in try store.pages(task: task.id).map { page in
            guard page.path == "\(task.bookId)/\(task.id)/\(page.index).img", page.index >= 0 else { throw DownloadError.invalidIdentity }
            return (storageLocations?.chapterName(task) ?? task.id) + "/\(page.index).img"
        } }
        let fileNames = tasks.filter(\.isFileTask).flatMap { [$0.chapterId + "." + $0.expectedFormat, ".xxcomic-publish-" + $0.id] }
        let known = Set(knownPages + fileNames + tasks.map { ".xxcomic-cover-" + $0.id + ".part" } + ["cover.img"] + (storageLocations?.hasOwnershipMarker(bookID: bookId) == true ? [DownloadStorageLocations.ownershipFile] : []))
        let work = tasks.filter(\.isFileTask).map { (root.appendingPathComponent("work_" + $0.id, isDirectory: true), $0.chapterId) }
        for (directory, prefix) in work { try DownloadOwnedDirectory.validate(directory, allowedDirectories: [], allowedFiles: [], taskIDs: [], partPrefix: prefix) }
        try withBookDirectory(bookId, access: .delete) { bookDir in
            try DownloadOwnedDirectory.validate(bookDir, allowedDirectories: taskIDs, allowedFiles: known, taskIDs: taskIDs)
            try Task.checkCancellation()
            // Once deletion starts, finish the database transaction before observing cancellation.
            changedFiles = true
            if FileManager.default.fileExists(atPath: bookDir.path) { try FileManager.default.removeItem(at: bookDir) }
        }
        for (directory, _) in work where FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try store.removeBook(bookId)
        try storageLocations?.removeMapping(bookID: bookId)
        success = true
    }

    private func checkLease(_ task: DownloadTask) throws {
        guard queue.isCurrent(task) else {
            throw DownloadError.taskCancelled
        }
        if !isNetworkConnected || (isWifiOnly && !isWifiConnected) {
            queue.waitForNetwork(task)
            throw DownloadError.corruptedData("等待网络连接")
        }
    }

    private func downloadTask(_ task: DownloadTask) async {
        if task.isFileTask {
            await downloadFileTask(task)
            return
        }
        var staging: URL?
        defer { if let staging { try? removeStagingDirectory(staging) } }
        do {
            try checkLease(task)
            try storageLocations?.prepare(task, comicTitle: store.snapshot(id: task.bookId)?.summary.title ?? task.comicId)
            guard let resolver = sourceResolver else {
                throw DownloadError.corruptedData("站源解析器未配置")
            }

            let chapter = try await resolver.resolveChapter(sourceId: task.sourceId, url: task.url)
            try checkLease(task)

            let rawUrls = chapter.imageUrls
            var seen = Set<String>()
            var uniqueUrls: [String] = []
            for u in rawUrls {
                if seen.insert(u).inserted {
                    uniqueUrls.append(u)
                }
            }
            guard !uniqueUrls.isEmpty else {
                throw DownloadError.invalidChapter
            }

            let savedPages = Dictionary(uniqueKeysWithValues: store.pages(task: task.id).map { ($0.index, $0) })
            var completedPages: [DownloadPage] = []
            var totalBytes: Int64 = 0

            try withBookDirectory(task.bookId, access: .write) { book in
                try checkLease(task)
                _ = try chapterDirectory(task, in: book, create: true)
            }
            let stagingDirectory = try stagingDirectory(task)
            staging = stagingDirectory

            for (i, rawUrl) in uniqueUrls.enumerated() {
                try checkLease(task)
                let existingPage = savedPages[i]

                let pageToUse: DownloadPage
                if let existing = existingPage,
                   DownloadModels.sameImage(existing.url, rawUrl),
                   try isValidPage(existing, task: task) {
                    pageToUse = existing
                } else {
                    let partFile = stagingDirectory.appendingPathComponent("\(i).part")
                    try validateRegularFileIfPresent(partFile)
                    let referer = resolver.resolveReferer(sourceId: task.sourceId, chapterUrl: task.url)

                    var fetchResult: (bytes: Int64, hash: String)?
                    let canRefresh = task.sourceId == "zaimanhua" || rawUrl.contains("#xx-")
                    for attempt in 0..<(canRefresh ? 2 : 1) {
                        try checkLease(task)
                        let resolvedUrl = try await resolver.resolveImageUrl(sourceId: task.sourceId, imageUrl: rawUrl, force: attempt > 0)
                        do {
                            fetchResult = try await imageFetcher.fetch(
                                sourceId: task.sourceId,
                                url: resolvedUrl,
                                referer: referer,
                                destination: partFile,
                                check: { [weak self] in
                                    guard let self else { throw DownloadError.taskCancelled }
                                    try self.checkLease(task)
                                }
                            )
                            break
                        } catch let httpError as DownloadHTTPError {
                            if !canRefresh || attempt > 0 || (httpError.statusCode != 403 && httpError.statusCode != 410) {
                                throw httpError
                            }
                        }
                    }
                    guard let fetchResult else {
                        throw DownloadError.corruptedData("图片地址刷新失败")
                    }

                    try withBookDirectory(task.bookId, access: .write) { book in
                        let target = try chapterDirectory(task, in: book).appendingPathComponent("\(i).img")
                        try publish(partFile, to: target, task: task)
                    }

                    let newPage = DownloadPage(index: i,
                                               url: DownloadModels.imageIdentity(rawUrl),
                                               path: "\(task.bookId)/\(task.id)/\(i).img",
                                               hash: fetchResult.hash,
                                               bytes: fetchResult.bytes)
                    store.savePage(task: task.id, page: newPage)
                    pageToUse = newPage
                }

                completedPages.append(pageToUse)
                totalBytes += pageToUse.bytes
                queue.update(lease: task, state: .downloading, done: i + 1, total: uniqueUrls.count, bytes: totalBytes)
            }

            try checkLease(task)
            queue.update(lease: task, state: .verifying, done: uniqueUrls.count, total: uniqueUrls.count, bytes: totalBytes)

            // Download cover if snapshot is available
            if let snapshot = store.snapshot(id: task.bookId), !snapshot.summary.coverUrl.isEmpty {
                let needsCover = try withBookDirectory(task.bookId, access: .read) { book in
                    let cover = book.appendingPathComponent("cover.img")
                    try validateRegularFileIfPresent(cover)
                    return !FileManager.default.fileExists(atPath: cover.path)
                }
                if needsCover {
                    let stagedCover = stagingDirectory.appendingPathComponent("cover.part")
                    try validateRegularFileIfPresent(stagedCover)
                    var coverFetched = false
                    do {
                        try await resolver.fetchCover(sourceId: task.sourceId,
                                                   coverUrl: snapshot.summary.coverUrl,
                                                   destination: stagedCover,
                                                   check: { [weak self] in
                        guard let self else { throw DownloadError.taskCancelled }
                        try self.checkLease(task)
                        })
                        coverFetched = true
                    } catch { /* The chapter remains usable when its optional cover fails. */ }
                    if coverFetched, FileManager.default.fileExists(atPath: stagedCover.path) {
                        try withBookDirectory(task.bookId, access: .write) { book in
                            let cover = book.appendingPathComponent("cover.img")
                            try validateRegularFileIfPresent(cover)
                            if !FileManager.default.fileExists(atPath: cover.path) { try publish(stagedCover, to: cover, task: task) }
                        }
                    }
                }
            }

            try checkLease(task)
            store.replacePages(task: task.id, pages: completedPages)
            queue.complete(lease: task)
            onTaskCompleted?(task)

        } catch {
            handleDownloadError(error, task: task)
        }
    }

    private func downloadFileTask(_ task: DownloadTask) async {
        var mutableTask = task
        do {
            try checkLease(task)
            guard !task.chapterId.isEmpty, !task.chapterId.contains("/"), !task.chapterId.contains("\\"), task.chapterId != ".", task.chapterId != ".." else { throw DownloadError.invalidIdentity }
            try storageLocations?.prepare(task, comicTitle: store.snapshot(id: task.bookId)?.summary.title ?? task.comicId)
            guard let fileSource = fileSourceResolver?(task.sourceId) else {
                throw DownloadError.corruptedData("站源不支持文件下载")
            }

            let workDir = downloadsDirectory.appendingPathComponent("work_\(task.id)", isDirectory: true)
            try validateDirectoryIfPresent(downloadsDirectory); try validateDirectoryIfPresent(workDir)
            if !FileManager.default.fileExists(atPath: workDir.path) {
                try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            }
            let partFile = workDir.appendingPathComponent("\(task.chapterId).\(task.generation).part")
            try validateRegularFileIfPresent(partFile)

            let result = try await fileWorker.download(
                task: &mutableTask,
                source: fileSource,
                part: partFile,
                check: { [weak self] in
                    guard let self else { throw DownloadError.taskCancelled }
                    try self.checkLease(task)
                },
                progress: { [weak self] bytes, total in
                    guard let self else { return }
                    self.queue.update(lease: task, state: .downloading, done: 0, total: 1, bytes: bytes)
                }
            )

            try checkLease(task)
            queue.update(lease: task, state: .verifying, done: 0, total: 1, bytes: result.bytes)

            try withBookDirectory(task.bookId, access: .write) { bookDir in
                if !FileManager.default.fileExists(atPath: bookDir.path) { try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true) }
                try publish(partFile, to: bookDir.appendingPathComponent("\(task.chapterId).\(result.detectedFormat)"), task: task)
            }
            try? FileManager.default.removeItem(at: workDir)

            try checkLease(task)
            var saved = store.get(id: task.id) ?? task
            saved.revision = mutableTask.revision
            saved.sha256 = mutableTask.sha256
            saved.expectedBytes = mutableTask.expectedBytes
            saved.bytes = result.bytes
            saved.donePages = 1
            saved.totalPages = 1
            saved.expectedFormat = result.detectedFormat
            store.save(task: saved)

            queue.complete(lease: task)
            onTaskCompleted?(saved)

        } catch {
            handleDownloadError(error, task: task)
        }
    }

    private func readPage(_ page: DownloadPage, task: DownloadTask, maximumBytes: Int64) throws -> Data {
        guard page.path == "\(task.bookId)/\(task.id)/\(page.index).img", page.index >= 0 else { throw DownloadError.invalidIdentity }
        return try withBookDirectory(task.bookId, access: .read) { book in
            let target = try chapterDirectory(task, in: book).appendingPathComponent("\(page.index).img")
            let bytes = try FileAccessCoordinator.readRegularFile(target, maximumBytes: maximumBytes)
            guard bytes.count == page.bytes, DownloadModels.sha256Hex(bytes) == page.hash else { throw DownloadError.corruptedData("下载图片损坏，请到下载中心重试本章") }
            return bytes
        }
    }
    private func isValidPage(_ page: DownloadPage, task: DownloadTask) throws -> Bool {
        do { _ = try readPage(page, task: task, maximumBytes: DefaultDownloadImageFetcher.maxPageBytes); return true }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return false }
        catch let error as DownloadError {
            if case .corruptedData = error { return false }
            throw error
        }
    }

    private func handleDownloadError(_ error: Error, task: DownloadTask) {
        if let dlErr = error as? DownloadError, dlErr == .taskCancelled {
            // Cancelled, do nothing
            return
        }
        ErrorLogStore.shared.append(title: "下载失败: \(task.comicId) - \(task.title)", error: error)
        if let httpErr = error as? DownloadHTTPError {
            if httpErr.statusCode == 403 || httpErr.statusCode == 401 {
                lock.lock()
                if queue.isCurrent(task) {
                    queue.pause(id: task.id)
                    var t = store.get(id: task.id) ?? task
                    t.error = "图片拒绝访问，请检查站源权限后重试"
                    store.save(task: t)
                }
                lock.unlock()
                return
            }
            queue.failed(lease: task,
                         now: Int64(Date().timeIntervalSince1970 * 1000),
                         error: error.localizedDescription,
                         retryAfter: httpErr.retryAfterMs)
        } else {
            let fileError = error as NSError
            let needsFileAction = error is DownloadLocationError ||
                (fileError.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError, NSFileWriteOutOfSpaceError].contains(fileError.code)) ||
                (fileError.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM), Int(EROFS), Int(ENOSPC)].contains(fileError.code))
            queue.failed(lease: task,
                         now: Int64(Date().timeIntervalSince1970 * 1000),
                         error: error.localizedDescription,
                         retryAfter: 0,
                         retryAutomatically: !needsFileAction)
        }
    }

    // MARK: - Offline Reading

    /// The image view receives file URLs, but access is restricted to recorded,
    /// completed download pages; a caller cannot use this to read user originals.
    public func offlineImageData(at url: URL, maximumBytes: Int64 = Int64(LocalLibrary.maximumImageBytes)) throws -> Data {
        guard url.isFileURL else { throw DownloadError.invalidIdentity }
        var permissionError: Error?
        for task in store.list() where !task.isFileTask && task.state == .completed {
            let relative: String?
            if let storageLocations {
                do { relative = try storageLocations.relativePath(of: url, bookID: task.bookId) }
                catch { permissionError = error; continue }
            } else {
                let prefix = downloadsDirectory.appendingPathComponent(task.bookId).standardizedFileURL.path + "/"
                let path = url.standardizedFileURL.path
                relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
            }
            guard let relative else { continue }
            let chapterName = storageLocations?.chapterName(task) ?? task.id
            guard let page = store.pages(task: task.id).first(where: { relative == chapterName + "/\($0.index).img" }) else { continue }
            return try readPage(page, task: task, maximumBytes: maximumBytes)
        }
        if let permissionError { throw permissionError }
        throw DownloadError.corruptedData("这张图片不属于已完成的下载，请到下载中心检查本章")
    }

    public func localChapter(detail: ComicDetail, chapterIndex: Int) throws -> ChapterPage? {
        guard detail.chapters.indices.contains(chapterIndex) else { return nil }
        let chapter = detail.chapters[chapterIndex]
        guard let taskId = try? DownloadModels.key(detail.summary.sourceId, detail.summary.comicId, chapter.chapterId) else {
            return nil
        }
        guard let task = store.get(id: taskId), task.state == .completed else {
            return nil
        }
        let pages = store.pages(task: taskId)
        guard pages.count == task.totalPages else {
            throw DownloadError.corruptedData("下载文件损坏，请到下载中心重试本章")
        }
        var urls: [String] = []
        for page in pages {
            try Task.checkCancellation()
            let fileURL = try pageURL(page, task: task)
            guard try isValidPage(page, task: task) else {
                throw DownloadError.corruptedData("下载文件缺失或损坏，请到下载中心重新下载本章")
            }
            urls.append(fileURL.absoluteString)
        }
        return ChapterPage(chapterId: chapter.chapterId, title: chapter.title, nextPageUrl: "", imageUrls: urls)
    }
}
