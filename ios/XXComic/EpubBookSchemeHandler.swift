import WebKit
import ComicCore

/// A handler belongs to exactly one document. WebKit callbacks and budget accounting stay on main.
@MainActor
final class EpubBookSchemeHandler: NSObject, WKURLSchemeHandler {
    private struct Request {
        let task: WKURLSchemeTask
        let url: URL
        let path: String
    }
    private let library: LocalLibrary
    private let book: LocalBook
    private let documentURL: URL
    private let document: Data
    private var pending: [Request] = []
    private var active: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var activeAllowance = 0
    private var stoppedTasks = Set<ObjectIdentifier>()
    private var requestCount = 0
    private var bytes = 0
    private var stopped = false
    var onFailure: ((Error) -> Void)?

    init(library: LocalLibrary, book: LocalBook, documentURL: URL, document: Data) {
        self.library = library; self.book = book; self.documentURL = documentURL; self.document = document
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard !stopped else { return }
        stoppedTasks.remove(ObjectIdentifier(urlSchemeTask))
        do {
            guard let url = urlSchemeTask.request.url else { throw LocalLibraryError.invalidBook }
            let path = try EpubReaderResource.path(from: url, bookID: book.id)
            requestCount += 1
            guard requestCount <= 1024 else { throw EpubError.limitExceeded("单篇正文超过 1024 个资源请求") }
            if url == documentURL {
                try deliver(document, mime: "text/html", to: urlSchemeTask, url: url)
            } else {
                pending.append(Request(task: urlSchemeTask, url: url, path: path)); drain()
            }
        } catch { urlSchemeTask.didFailWithError(error); onFailure?(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        stoppedTasks.insert(id)
        pending.removeAll { ObjectIdentifier($0.task) == id }
        if let worker = active[id], !worker.isCancelled {
            // The archive API cannot report partial decompression after cancellation.
            // Charge its reserved ceiling, so repeated cancelled requests cannot bypass the document budget.
            bytes += activeAllowance; worker.cancel()
        }
        drain()
    }
    func cancel() {
        stopped = true; pending.removeAll()
        active.values.forEach { $0.cancel() }; active.removeAll()
        onFailure = nil
    }
    private func deliver(_ data: Data, mime: String, to task: WKURLSchemeTask, url: URL) throws {
        let id = ObjectIdentifier(task)
        guard !stopped, !stoppedTasks.contains(id) else { return }
        guard data.count <= 256 * 1024 * 1024 - bytes else { throw EpubError.limitExceeded("单篇正文资源累计超过 256 MiB") }
        bytes += data.count
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text/") ? "utf-8" : nil))
        guard !stopped, !stoppedTasks.contains(id) else { return }
        task.didReceive(data)
        guard !stopped, !stoppedTasks.contains(id) else { return }
        task.didFinish()
    }
    private func drain() {
        // Serialize archive reads so the remaining total budget is exact before decompression.
        // This stays below the two-worker ceiling without rejecting a valid resource due to reservations.
        while !stopped, active.isEmpty, !pending.isEmpty {
            let allowance = min(128 * 1024 * 1024, 256 * 1024 * 1024 - bytes)
            guard allowance > 0 else {
                if active.isEmpty {
                    let error = EpubError.limitExceeded("单篇正文资源累计超过 256 MiB")
                    let request = pending.removeFirst(); request.task.didFailWithError(error); onFailure?(error)
                }
                return
            }
            let request = pending.removeFirst(), library = library, book = book
            let id = ObjectIdentifier(request.task)
            let path = request.path
            activeAllowance = allowance
            let worker = Task.detached(priority: .userInitiated) {
                try library.epubResource(bookID: book.id, path: path, maximumBytes: allowance)
            }
            active[id] = Task { [weak self] in
                let result: Result<Data, Error>
                do { result = .success(try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }) }
                catch { result = .failure(error) }
                guard let self else { return }
                defer { self.active.removeValue(forKey: id); self.drain() }
                guard !Task.isCancelled, !self.stopped, self.active[id] != nil else { return }
                do {
                    let data = try result.get()
                    self.activeAllowance = 0
                    let mime = EpubReaderResource.mimeType(path: request.path, publication: book.epub!)
                    try self.deliver(data, mime: mime, to: request.task, url: request.url)
                } catch { request.task.didFailWithError(error); self.onFailure?(error) }
            }
        }
    }
}
