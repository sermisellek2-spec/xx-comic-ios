import Foundation
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
        let cleanUrl = url.components(separatedBy: "#")[0]
        guard let requestUrl = URL(string: cleanUrl) else {
            throw DownloadError.corruptedData("无效的图片地址")
        }
        var request = URLRequest(url: requestUrl)
        request.timeoutInterval = 25
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
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
            if sourceId == "xinmanhua" || XinmanhuaImageDecoder.usesImageHost(url) {
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

    private let lock = NSLock()
    private var activeWorkers = Set<String>()
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
                fileSourceResolver: ((_ sourceId: String) -> FileSourceCapability?)? = nil) {
        self.store = store
        self.queue = DownloadCoordinator(repository: store)
        self.downloadsDirectory = downloadsDirectory
        self.imageFetcher = imageFetcher
        self.fileWorker = fileWorker
        self.sourceResolver = sourceResolver
        self.fileSourceResolver = fileSourceResolver

        if !FileManager.default.fileExists(atPath: downloadsDirectory.path) {
            try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        }

        // Recover interrupted tasks on startup
        queue.recover()
        cleanResidualPartFiles()
        isInitialized = true
    }

    private func cleanResidualPartFiles() {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: downloadsDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return
        }
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "part" {
                try? manager.removeItem(at: fileURL)
            }
        }
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
        store.saveSnapshot(detail)
        queue.enqueueFiles(source: detail.summary.sourceId,
                           comic: detail.summary.comicId,
                           files: files,
                           selected: selected)
        kickLocked()
    }

    public func enqueue(detail: ComicDetail, selectedChapterIds: [String]) {
        lock.lock()
        defer { lock.unlock() }
        store.saveSnapshot(detail)
        queue.enqueue(source: detail.summary.sourceId,
                      comic: detail.summary.comicId,
                      chapters: detail.chapters,
                      selected: selectedChapterIds)
        kickLocked()
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

    public func cancel(id: String) {
        lock.lock()
        queue.cancel(id: id)
        guard let task = store.get(id: id) else {
            lock.unlock()
            return
        }
        lock.unlock()

        deleteTaskFiles(task: task)
        store.remove(task: id)
    }

    public func deleteChapter(id: String) {
        lock.lock()
        guard var task = store.get(id: id) else {
            lock.unlock()
            return
        }
        task.generation = DownloadCoordinator.nextGeneration()
        task.state = .deleting
        store.save(task: task)
        lock.unlock()

        deleteTaskFiles(task: task)
        store.remove(task: id)
    }

    public func deleteBook(bookId: String) {
        lock.lock()
        let tasks = store.list().filter { $0.bookId == bookId }
        for var t in tasks {
            t.generation = DownloadCoordinator.nextGeneration()
            t.state = .deleting
            store.save(task: t)
        }
        lock.unlock()

        let bookDir = downloadsDirectory.appendingPathComponent(bookId, isDirectory: true)
        try? FileManager.default.removeItem(at: bookDir)

        for t in tasks {
            store.remove(task: t.id)
        }
    }

    private func deleteTaskFiles(task: DownloadTask) {
        let taskDir = downloadsDirectory
            .appendingPathComponent(task.bookId, isDirectory: true)
            .appendingPathComponent(task.id, isDirectory: true)
        try? FileManager.default.removeItem(at: taskDir)
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
        do {
            try checkLease(task)
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

            let taskDir = downloadsDirectory
                .appendingPathComponent(task.bookId, isDirectory: true)
                .appendingPathComponent(task.id, isDirectory: true)

            if !FileManager.default.fileExists(atPath: taskDir.path) {
                try FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
            }

            for (i, rawUrl) in uniqueUrls.enumerated() {
                try checkLease(task)
                let targetFile = taskDir.appendingPathComponent("\(i).img")
                let existingPage = savedPages[i]

                let pageToUse: DownloadPage
                if let existing = existingPage,
                   DownloadModels.sameImage(existing.url, rawUrl),
                   isValidPage(existing, targetFile: targetFile) {
                    pageToUse = existing
                } else {
                    let partFile = taskDir.appendingPathComponent("\(i).\(task.generation).part")
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

                    try checkLease(task)
                    if FileManager.default.fileExists(atPath: targetFile.path) {
                        try? FileManager.default.removeItem(at: targetFile)
                    }
                    try FileManager.default.moveItem(at: partFile, to: targetFile)

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
                let coverTarget = downloadsDirectory
                    .appendingPathComponent(task.bookId, isDirectory: true)
                    .appendingPathComponent("cover.img")
                if !FileManager.default.fileExists(atPath: coverTarget.path) {
                    try? await resolver.fetchCover(sourceId: task.sourceId,
                                                   coverUrl: snapshot.summary.coverUrl,
                                                   destination: coverTarget,
                                                   check: { [weak self] in
                        guard let self else { throw DownloadError.taskCancelled }
                        try self.checkLease(task)
                    })
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
            guard let fileSource = fileSourceResolver?(task.sourceId) else {
                throw DownloadError.corruptedData("站源不支持文件下载")
            }

            let workDir = downloadsDirectory.appendingPathComponent("work_\(task.id)", isDirectory: true)
            if !FileManager.default.fileExists(atPath: workDir.path) {
                try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            }
            let partFile = workDir.appendingPathComponent("\(task.chapterId).\(task.generation).part")

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

            let bookDir = downloadsDirectory.appendingPathComponent(task.bookId, isDirectory: true)
            if !FileManager.default.fileExists(atPath: bookDir.path) {
                try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
            }
            let targetFile = bookDir.appendingPathComponent("\(task.chapterId).\(result.detectedFormat)")

            if FileManager.default.fileExists(atPath: targetFile.path) {
                try? FileManager.default.removeItem(at: targetFile)
            }
            try FileManager.default.moveItem(at: partFile, to: targetFile)
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

    private func isValidPage(_ page: DownloadPage, targetFile: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: targetFile.path) else { return false }
        guard let attr = try? FileManager.default.attributesOfItem(atPath: targetFile.path),
              let size = (attr[FileAttributeKey.size] as? NSNumber)?.int64Value,
              size == page.bytes else { return false }
        guard let data = try? Data(contentsOf: targetFile) else { return false }
        return DownloadModels.sha256Hex(data) == page.hash
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
            queue.failed(lease: task,
                         now: Int64(Date().timeIntervalSince1970 * 1000),
                         error: error.localizedDescription,
                         retryAfter: 0)
        }
    }

    // MARK: - Offline Reading

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
            let fileURL = downloadsDirectory.appendingPathComponent(page.path)
            guard isValidPage(page, targetFile: fileURL) else {
                throw DownloadError.corruptedData("下载文件缺失或损坏，请到下载中心重新下载本章")
            }
            urls.append(fileURL.absoluteString)
        }
        return ChapterPage(chapterId: chapter.chapterId, title: chapter.title, nextPageUrl: "", imageUrls: urls)
    }
}
