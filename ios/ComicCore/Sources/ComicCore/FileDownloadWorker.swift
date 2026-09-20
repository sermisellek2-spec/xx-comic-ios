import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ZIPFoundation

public final class FileDownloadWorker: @unchecked Sendable {
    public typealias Check = @Sendable () throws -> Void
    public typealias ProgressListener = @Sendable (_ bytes: Int64, _ total: Int64) -> Void

    public struct Result: Equatable, Sendable {
        public let bytes: Int64
        public let hash: String
        public let detectedFormat: String

        public init(bytes: Int64, hash: String, detectedFormat: String) {
            self.bytes = bytes
            self.hash = hash
            self.detectedFormat = detectedFormat
        }
    }

    public static let maxBytes: Int64 = 20 * 1024 * 1024 * 1024 // 20GB
    public static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    public init() {}

    public func download(task: inout DownloadTask,
                         source: FileSourceCapability?,
                         part: URL,
                         check: @escaping Check,
                         progress: ProgressListener? = nil) async throws -> Result {
        try check()
        guard let source else {
            throw DownloadError.corruptedData("站源不支持文件下载")
        }
        var resource = try await resolve(task: &task, source: source)
        let validator = URL(fileURLWithPath: part.path + ".etag")

        do {
            for refresh in 0..<2 {
                let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                if resource.isExpired(now: nowMs) {
                    if task.refreshCount >= 1 {
                        throw DownloadError.corruptedData("文件链接已过期，请稍后重试")
                    }
                    task.refreshCount = 1
                    resource = try await resolve(task: &task, source: source)
                    if resource.isExpired(now: Int64(Date().timeIntervalSince1970 * 1000)) {
                        throw DownloadError.corruptedData("文件链接已过期，请稍后重试")
                    }
                }

                do {
                    return try await transfer(resource: resource, part: part, validator: validator, check: check, progress: progress)
                } catch let httpErr as DownloadHTTPError {
                    if (httpErr.statusCode != 401 && httpErr.statusCode != 403) || task.refreshCount >= 1 || refresh == 1 {
                        throw httpErr
                    }
                    task.refreshCount = 1
                    resource = try await resolve(task: &task, source: source)
                }
            }
            throw DownloadError.corruptedData("文件链接未生效，请重试")
        } catch {
            if !Self.isCancellation(error) {
                try? FileManager.default.removeItem(at: part)
                try? FileManager.default.removeItem(at: validator)
            }
            throw error
        }
    }

    private func resolve(task: inout DownloadTask, source: FileSourceCapability) async throws -> FileResource {
        guard let fileId = task.fileId, !fileId.isEmpty else {
            throw DownloadError.corruptedData("缺少文件标识")
        }
        let r = try await source.resolveFile(comicId: task.comicId, fileId: fileId)
        guard r.fileId == task.fileId else {
            throw DownloadError.corruptedData("文件身份发生变化，请重新选择")
        }
        task.revision = r.revision
        task.sha256 = r.sha256
        task.expectedBytes = r.bytes
        task.expectedFormat = r.expectedFormat
        task.expiresAt = r.expiresAt
        return r
    }

    private func transfer(resource: FileResource,
                          part: URL,
                          validator: URL,
                          check: @escaping Check,
                          progress: ProgressListener?) async throws -> Result {
        var saved = ""
        if FileManager.default.fileExists(atPath: validator.path),
           let content = try? String(contentsOf: validator, encoding: .utf8) {
            saved = content
        }
        let identity = resource.revision + "\n" + (resource.sha256 ?? "null") + "\n"
        let etag = saved.hasPrefix(identity) ? String(saved.dropFirst(identity.count)) : ""

        var offset: Int64 = 0
        if FileManager.default.fileExists(atPath: part.path),
           etag.hasPrefix("\""),
           let attr = try? FileManager.default.attributesOfItem(atPath: part.path),
           let size = (attr[.size] as? NSNumber)?.int64Value,
           size > 0 {
            offset = size
        }

        guard var url = URL(string: resource.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.user == nil else {
            throw DownloadError.corruptedData("文件地址协议不支持")
        }

        var headers = resource.headers

        for _ in 0...5 {
            try check()

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            for (k, v) in headers {
                if k.contains("\n") || v.contains("\n") || k.contains("\r") || v.contains("\r") {
                    throw DownloadError.corruptedData("站源请求信息无效")
                }
                let lower = k.lowercased()
                if ["host", "content-length", "range", "if-range", "accept-encoding"].contains(lower) {
                    continue
                }
                request.setValue(v, forHTTPHeaderField: k)
            }
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

            if offset > 0 {
                request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
                request.setValue(etag, forHTTPHeaderField: "If-Range")
            }

            let transferResult = try await executeSingleRequest(request: request,
                                                                partURL: part,
                                                                offset: offset,
                                                                maxBytes: Self.maxBytes,
                                                                check: check,
                                                                progress: progress)

            let status = transferResult.statusCode

            // Handle redirects
            if [301, 302, 303, 307, 308].contains(status) {
                guard let location = transferResult.headers.first(where: { $0.key.caseInsensitiveCompare("Location") == .orderedSame })?.value,
                      let next = URL(string: location, relativeTo: url)?.absoluteURL else {
                    throw DownloadError.corruptedData("文件跳转地址缺失")
                }
                if url.scheme?.lowercased() == "https" && next.scheme?.lowercased() != "https" {
                    throw DownloadError.corruptedData("文件链接不允许降级为明文连接")
                }
                if !sameOrigin(url, next) {
                    headers.removeAll()
                }
                url = next
                continue
            }

            // Handle 416 Range Not Satisfiable
            if status == 416 && offset > 0 {
                offset = 0
                try? FileManager.default.removeItem(at: part)
                try? FileManager.default.removeItem(at: validator)
                continue
            }

            if status != 200 && status != 206 {
                let delay = status == 429 ? 60000 : 0
                throw DownloadHTTPError(statusCode: status, retryAfterMs: Int64(delay))
            }

            let contentType = transferResult.headers.first(where: { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame })?.value
            if let contentType, contentType.lowercased().contains("text/html") {
                throw DownloadError.corruptedData("站源返回了网页，未获取到文件")
            }

            let contentLengthHeader = transferResult.headers.first(where: { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame })?.value
            let length: Int64 = contentLengthHeader.flatMap { Int64($0) } ?? -1
            var total = length

            let responseEtag = transferResult.headers.first(where: { $0.key.caseInsensitiveCompare("ETag") == .orderedSame })?.value

            if status == 206 {
                guard let contentRange = transferResult.headers.first(where: { $0.key.caseInsensitiveCompare("Content-Range") == .orderedSame })?.value,
                      let regex = try? NSRegularExpression(pattern: #"bytes (\d+)-(\d+)/(\d+)"#),
                      let match = regex.firstMatch(in: contentRange, range: NSRange(contentRange.startIndex..., in: contentRange)),
                      match.numberOfRanges == 4,
                      let r1 = Range(match.range(at: 1), in: contentRange),
                      let r2 = Range(match.range(at: 2), in: contentRange),
                      let r3 = Range(match.range(at: 3), in: contentRange),
                      let first = Int64(contentRange[r1]),
                      let last = Int64(contentRange[r2]),
                      let rangeTotal = Int64(contentRange[r3]) else {
                    throw DownloadError.corruptedData("文件续传响应无效")
                }
                total = rangeTotal
                if offset <= 0 || etag != responseEtag {
                    throw DownloadError.corruptedData("文件续传响应无效")
                }
                if first != offset || last < first || last != total - 1 || (length >= 0 && length != last - first + 1) {
                    throw DownloadError.corruptedData("文件续传范围不符")
                }
            } else {
                offset = 0
            }

            if total > Self.maxBytes || resource.bytes > Self.maxBytes {
                throw DownloadError.corruptedData("文件超过容量上限")
            }
            if resource.bytes >= 0 && total >= 0 && resource.bytes != total {
                throw DownloadError.corruptedData("文件长度与站源描述不符")
            }

            let parentDir = part.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            if let responseEtag, responseEtag.hasPrefix("\"") {
                try? (identity + responseEtag).write(to: validator, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: validator)
            }

            let written = transferResult.bytesWritten
            try check()

            if written == 0 || (total >= 0 && written != total) || (resource.bytes >= 0 && written != resource.bytes) {
                throw DownloadError.corruptedData("文件传输不完整")
            }

            let hash = try Self.calculateSha256(part, check: check)
            if let expectedHash = resource.sha256, hash.caseInsensitiveCompare(expectedHash) != .orderedSame {
                throw DownloadError.corruptedData("文件校验失败")
            }

            guard let format = Self.detectFormat(file: part, hint: resource.expectedFormat) else {
                throw DownloadError.corruptedData("文件格式不支持或内容损坏")
            }

            try? FileManager.default.removeItem(at: validator)
            return Result(bytes: written, hash: hash, detectedFormat: format)
        }

        throw DownloadError.corruptedData("文件跳转次数过多")
    }

    private struct SingleRequestResult {
        let statusCode: Int
        let headers: [String: String]
        let bytesWritten: Int64
    }

    private func executeSingleRequest(request: URLRequest,
                                      partURL: URL,
                                      offset: Int64,
                                      maxBytes: Int64,
                                      check: @escaping Check,
                                      progress: ProgressListener?) async throws -> SingleRequestResult {
        try check()

        final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
            let partURL: URL
            let offset: Int64
            let maxBytes: Int64
            let check: Check
            let progress: ProgressListener?

            private(set) var statusCode: Int = 0
            private(set) var headers: [String: String] = [:]
            private(set) var written: Int64 = 0
            private(set) var streamError: Error?
            private var fileHandle: FileHandle?
            private var totalExpected: Int64 = -1
            private var continuation: CheckedContinuation<SingleRequestResult, Error>?
            private let lock = NSLock()
            private var isResumed = false

            init(partURL: URL, offset: Int64, maxBytes: Int64, check: @escaping Check, progress: ProgressListener?) {
                self.partURL = partURL
                self.offset = offset
                self.maxBytes = maxBytes
                self.check = check
                self.progress = progress
                self.written = offset
            }

            func attachContinuation(_ continuation: CheckedContinuation<SingleRequestResult, Error>) {
                self.continuation = continuation
            }

            private func finish(result: Swift.Result<SingleRequestResult, Error>) {
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

                switch result {
                case .success(let res):
                    cont?.resume(returning: res)
                case .failure(let err):
                    cont?.resume(throwing: err)
                }
            }

            // Stop auto-redirect
            func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
                headers = response.allHeaderFields.reduce(into: [:]) { res, entry in
                    if let k = entry.key as? String { res[k] = String(describing: entry.value) }
                }
                statusCode = response.statusCode
                completionHandler(nil)
            }

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                guard let http = response as? HTTPURLResponse else {
                    streamError = DownloadError.corruptedData("无效的服务器响应")
                    completionHandler(.cancel)
                    return
                }
                statusCode = http.statusCode
                headers = http.allHeaderFields.reduce(into: [:]) { res, entry in
                    if let k = entry.key as? String { res[k] = String(describing: entry.value) }
                }

                // If redirect, 416, or error, cancel and finish
                if [301, 302, 303, 307, 308, 416].contains(statusCode) || (statusCode != 200 && statusCode != 206) {
                    completionHandler(.cancel)
                    return
                }

                let effectiveOffset: Int64 = (statusCode == 206) ? offset : 0
                if let cl = headers.first(where: { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame })?.value {
                    totalExpected = (Int64(cl) ?? -1) + effectiveOffset
                }

                do {
                    if effectiveOffset == 0 {
                        let empty = Data()
                        try empty.write(to: partURL, options: .atomic)
                        fileHandle = try FileHandle(forWritingTo: partURL)
                        written = 0
                    } else {
                        fileHandle = try FileHandle(forWritingTo: partURL)
                        try fileHandle?.seekToEnd()
                        written = effectiveOffset
                    }
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
                    streamError = DownloadError.corruptedData("文件超过容量上限")
                    dataTask.cancel()
                    return
                }

                fileHandle?.write(data)
                progress?(written, totalExpected)
            }

            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let err = streamError ?? error {
                    // Check if redirect or 416 cancelled the task intentionally
                    if [301, 302, 303, 307, 308, 416].contains(statusCode) {
                        finish(result: .success(SingleRequestResult(statusCode: statusCode, headers: headers, bytesWritten: written)))
                        return
                    }
                    if statusCode != 0 && statusCode != 200 && statusCode != 206 {
                        finish(result: .success(SingleRequestResult(statusCode: statusCode, headers: headers, bytesWritten: written)))
                        return
                    }
                    finish(result: .failure(err))
                } else {
                    finish(result: .success(SingleRequestResult(statusCode: statusCode, headers: headers, bytesWritten: written)))
                }
            }
        }

        let delegate = StreamDelegate(partURL: partURL, offset: offset, maxBytes: maxBytes, check: check, progress: progress)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.attachContinuation(continuation)
                let task = session.dataTask(with: request)
                task.resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        guard let sA = a.scheme?.lowercased(), let sB = b.scheme?.lowercased(), sA == sB else { return false }
        guard let hA = a.host?.lowercased(), let hB = b.host?.lowercased(), hA == hB else { return false }
        let pA = (a.port == nil || a.port == -1) ? (sA == "https" ? 443 : 80) : a.port!
        let pB = (b.port == nil || b.port == -1) ? (sB == "https" ? 443 : 80) : b.port!
        return pA == pB
    }

    public static func calculateSha256(_ file: URL, check: Check = {}) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            throw DownloadError.corruptedData("无法读取文件计算哈希")
        }
        defer { try? handle.close() }

        var hasher = StreamingSHA256()
        while true {
            try check()
            guard let chunk = try? handle.read(upToCount: 65536), !chunk.isEmpty else {
                break
            }
            hasher.update(chunk)
        }
        return hasher.finalizeHex()
    }

    public static func detectFormat(file: URL, hint: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 68), head.count >= 4 else { return nil }

        if head.count >= 5, let s = String(data: head.prefix(5), encoding: .ascii), s == "%PDF-" {
            return "pdf"
        }
        if head.count >= 68 {
            let magic = head.subdata(in: 60..<68)
            if let s = String(data: magic, encoding: .ascii), s == "BOOKMOBI" || s == "TEXtREAd" {
                return "mobi"
            }
        }
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            do {
                let archive = try Archive(url: file, accessMode: .read)
                if archive["META-INF/container.xml"] != nil {
                    return "epub"
                }
                return hint.lowercased() == "cbz" ? "cbz" : "zip"
            } catch {
                return hint.lowercased() == "cbz" ? "cbz" : "zip"
            }
        }
        return nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let dlErr = error as? DownloadError, dlErr == .taskCancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && (ns.code == NSURLErrorCancelled || ns.code == NSURLErrorTimedOut) {
            return true
        }
        return false
    }
}

/// Helper for chunk-by-chunk SHA-256 calculation
public struct StreamingSHA256 {
    private var data = Data()

    public init() {}

    public mutating func update(_ chunk: Data) {
        data.append(chunk)
    }

    public func finalizeHex() -> String {
        DownloadModels.sha256Hex(data)
    }
}
