import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class LocalTestHTTPServer: @unchecked Sendable {
    public struct Request {
        public let method: String
        public let path: String
        public let headers: [String: String]

        public func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    public struct Response {
        public var statusCode: Int
        public var statusText: String
        public var headers: [String: String]
        public var body: Data

        public init(statusCode: Int = 200,
                    statusText: String = "OK",
                    headers: [String: String] = [:],
                    body: Data = Data()) {
            self.statusCode = statusCode
            self.statusText = statusText
            self.headers = headers
            self.body = body
        }
    }

    public typealias Handler = @Sendable (Request) -> Response

    private let serverFd: Int32
    public let port: UInt16
    private let lock = NSLock()
    private var routes: [String: Handler] = [:]
    private var rawRequests: [Request] = []
    private var isRunning = true
    private var workerThread: Thread?

    public init() throws {
        #if canImport(Darwin)
        let streamType = SOCK_STREAM
        #else
        let streamType = Int32(SOCK_STREAM.rawValue)
        #endif
        let fd = socket(AF_INET, streamType, 0)
        guard fd >= 0 else {
            throw NSError(domain: "LocalTestHTTPServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "socket() failed: \(errno)"])
        }
        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(fd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw NSError(domain: "LocalTestHTTPServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "bind() failed: \(errno)"])
        }

        guard listen(fd, 16) == 0 else {
            close(fd)
            throw NSError(domain: "LocalTestHTTPServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "listen() failed: \(errno)"])
        }

        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assignedAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                getsockname(fd, saPtr, &addrLen)
            }
        }
        self.serverFd = fd
        self.port = UInt16(bigEndian: assignedAddr.sin_port)
    }

    public var baseURLString: String {
        "http://127.0.0.1:\(port)"
    }

    public func url(for path: String) -> String {
        baseURLString + (path.hasPrefix("/") ? path : "/" + path)
    }

    public func route(_ path: String, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        routes[path] = handler
    }

    public func recordedRequests() -> [Request] {
        lock.lock()
        defer { lock.unlock() }
        return rawRequests
    }

    public func start() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            while true {
                self.lock.lock()
                let running = self.isRunning
                self.lock.unlock()
                if !running { break }

                let clientFd = accept(self.serverFd, nil, nil)
                if clientFd < 0 {
                    break
                }

                self.handleClient(clientFd)
            }
        }
        self.workerThread = thread
        thread.start()
    }

    public func stop() {
        lock.lock()
        isRunning = false
        lock.unlock()
        close(serverFd)
        workerThread?.cancel()
    }

    deinit {
        stop()
    }

    private func handleClient(_ clientFd: Int32) {
        defer { close(clientFd) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        var receivedData = Data()
        var headerEndRange: Range<Data.Index>? = nil

        while true {
            let bytesRead = read(clientFd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            receivedData.append(buffer, count: bytesRead)
            if let range = receivedData.range(of: Data("\r\n\r\n".utf8)) {
                headerEndRange = range
                break
            }
        }

        guard let headerRange = headerEndRange,
              let headerString = String(data: receivedData.subdata(in: 0..<headerRange.lowerBound), encoding: .utf8) else {
            return
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return }

        let method = String(requestParts[0])
        let fullPath = String(requestParts[1])
        let path = fullPath.components(separatedBy: "?")[0]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let request = Request(method: method, path: fullPath, headers: headers)
        lock.lock()
        rawRequests.append(request)
        let handler = routes[path] ?? routes["*"]
        lock.unlock()

        let response = handler?(request) ?? Response(statusCode: 404, statusText: "Not Found", headers: [:], body: Data("Not Found".utf8))

        var headerBytes = "HTTP/1.1 \(response.statusCode) \(response.statusText)\r\nConnection: close\r\n"
        var finalHeaders = response.headers
        if finalHeaders["Content-Length"] == nil && finalHeaders["Transfer-Encoding"] == nil {
            finalHeaders["Content-Length"] = "\(response.body.count)"
        }
        for (k, v) in finalHeaders {
            headerBytes += "\(k): \(v)\r\n"
        }
        headerBytes += "\r\n"

        if let headData = headerBytes.data(using: .utf8) {
            headData.withUnsafeBytes { rawPtr in
                if let ptr = rawPtr.baseAddress {
                    _ = write(clientFd, ptr, headData.count)
                }
            }
        }

        if !response.body.isEmpty {
            response.body.withUnsafeBytes { rawPtr in
                if let ptr = rawPtr.baseAddress {
                    _ = write(clientFd, ptr, response.body.count)
                }
            }
        }
    }
}
