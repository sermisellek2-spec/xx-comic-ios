import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ComicCore

final class LocalTestHTTPServerTests: XCTestCase {
    func testServerServesResponseAndRecordsRequest() throws {
        let server = try LocalTestHTTPServer()
        server.route("/hello") { req in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "text/plain", "X-Custom": "test-value"],
                body: Data("world".utf8)
            )
        }
        server.start()
        defer { server.stop() }

        guard let url = URL(string: server.url(for: "/hello")) else {
            XCTFail("Invalid URL")
            return
        }

        var req = URLRequest(url: url)
        req.setValue("CustomAgent/1.0", forHTTPHeaderField: "User-Agent")

        let exp = expectation(description: "request finished")
        var responseData: Data?
        var httpResponse: HTTPURLResponse?

        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            responseData = data
            httpResponse = resp as? HTTPURLResponse
            exp.fulfill()
        }
        task.resume()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(responseData, Data("world".utf8))
        XCTAssertEqual(httpResponse?.allHeaderFields["X-Custom"] as? String, "test-value")

        let requests = server.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.path, "/hello")
        XCTAssertEqual(requests.first?.header("User-Agent"), "CustomAgent/1.0")
    }

    func testDataDelegateReceivesStreamingData() throws {
        let server = try LocalTestHTTPServer()
        let payload = Data(repeating: 0x42, count: 1024)
        server.route("/stream") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/octet-stream"],
                body: payload
            )
        }
        server.start()
        defer { server.stop() }

        final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
            var received = Data()
            var statusCode = 0
            var completed = false
            let exp: XCTestExpectation

            init(exp: XCTestExpectation) {
                self.exp = exp
            }

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                if let http = response as? HTTPURLResponse {
                    self.statusCode = http.statusCode
                }
                completionHandler(.allow)
            }

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                received.append(data)
            }

            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                completed = true
                exp.fulfill()
            }
        }

        let exp = expectation(description: "streaming done")
        let delegate = Delegate(exp: exp)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: server.url(for: "/stream"))!)
        task.resume()

        waitForExpectations(timeout: 5)
        XCTAssertEqual(delegate.statusCode, 200)
        XCTAssertEqual(delegate.received, payload)
        XCTAssertTrue(delegate.completed)
    }
}

