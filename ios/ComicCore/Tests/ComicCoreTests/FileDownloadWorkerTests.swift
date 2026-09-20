import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ZIPFoundation
@testable import ComicCore

final class FileDownloadWorkerTests: XCTestCase {
    private var tempDir: URL!
    private var server: LocalTestHTTPServer!
    private var zipData: Data!
    private var partFile: URL!
    private var task: DownloadTask!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        partFile = tempDir.appendingPathComponent("book.part")
        task = DownloadTask(comicId: "comic", chapterId: "vol1", isFileTask: true, fileId: "vol1")

        let archiveURL = tempDir.appendingPathComponent("sample.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        let entryData = Data([1, 2, 3, 4, 5])
        try archive.addEntry(with: "1.png", type: .file, uncompressedSize: Int64(entryData.count), compressionMethod: .none,
                             provider: { position, count in entryData.subdata(in: Int(position)..<min(Int(position) + count, entryData.count)) })
        zipData = try Data(contentsOf: archiveURL)

        server = try LocalTestHTTPServer()
        server.start()
    }

    override func tearDownWithError() throws {
        server?.stop()
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func resource(path: String, bytes: Int64, hash: String? = nil, headers: [String: String] = [:]) -> FileResource {
        FileResource(fileId: "vol1", revision: "v1", title: "第一卷", order: 0,
                     expectedFormat: "zip", bytes: bytes, sha256: hash,
                     url: server.url(for: path), headers: headers, expiresAt: 0)
    }

    private struct MockFileSource: FileSourceCapability {
        let resources: [FileResource]
        let callCount = Counter()

        func listFiles(comicId: String) async throws -> [FileResource] {
            resources
        }

        func resolveFile(comicId: String, fileId: String) async throws -> FileResource {
            let index = min(callCount.increment(), resources.count - 1)
            return resources[index]
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var val: Int = 0
        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            let old = val
            val += 1
            return old
        }
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return val
        }
    }

    func testPreservesBytesAndUsesResolvedHeadersWithoutPersistingTokens() async throws {
        server.route("/file") { req in
            XCTAssertEqual(req.header("Authorization"), "Bearer sample")
            return LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/zip"],
                body: self.zipData
            )
        }

        let res = resource(path: "/file", bytes: Int64(zipData.count), hash: nil, headers: ["Authorization": "Bearer sample"])
        let source = MockFileSource(resources: [res])
        let worker = FileDownloadWorker()
        let result = try await worker.download(task: &task, source: source, part: partFile, check: {})

        XCTAssertEqual(result.bytes, Int64(zipData.count))
        XCTAssertEqual(result.detectedFormat, "zip")
        let written = try Data(contentsOf: partFile)
        XCTAssertEqual(written, zipData)
        XCTAssertTrue(task.url.isEmpty)
    }

    func testSupportsUnknownLengthAndDetectsEpubFromContent() async throws {
        let epubURL = tempDir.appendingPathComponent("sample.epub")
        let archive = try Archive(url: epubURL, accessMode: .create)
        let containerData = Data("sample container".utf8)
        try archive.addEntry(with: "META-INF/container.xml", type: .file, uncompressedSize: Int64(containerData.count), compressionMethod: .none,
                             provider: { pos, count in containerData.subdata(in: Int(pos)..<min(Int(pos) + count, containerData.count)) })
        let epubData = try Data(contentsOf: epubURL)

        server.route("/epub") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/epub+zip"],
                body: epubData
            )
        }

        let res = resource(path: "/epub", bytes: -1, hash: nil)
        let source = MockFileSource(resources: [res])
        let worker = FileDownloadWorker()
        let result = try await worker.download(task: &task, source: source, part: partFile, check: {})

        XCTAssertEqual(result.detectedFormat, "epub")
        let written = try Data(contentsOf: partFile)
        XCTAssertEqual(written, epubData)
    }

    func testRejectsHtmlTruncationChecksumAndUnsolicitedPartial() async throws {
        server.route("/html") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "text/html"],
                body: Data("<html>error</html>".utf8)
            )
        }
        server.route("/partial") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 206,
                headers: [
                    "Content-Type": "application/zip",
                    "Content-Range": "bytes 0-\(self.zipData.count - 1)/\(self.zipData.count)"
                ],
                body: self.zipData
            )
        }
        server.route("/hash") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/zip"],
                body: self.zipData
            )
        }

        let worker = FileDownloadWorker()

        // HTML rejection
        do {
            let res = resource(path: "/html", bytes: -1)
            _ = try await worker.download(task: &task, source: MockFileSource(resources: [res]), part: partFile, check: {})
            XCTFail("Should reject HTML")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: partFile.path))
        }

        // Unsolicited 206 rejection (no Range requested)
        do {
            let res = resource(path: "/partial", bytes: -1)
            _ = try await worker.download(task: &task, source: MockFileSource(resources: [res]), part: partFile, check: {})
            XCTFail("Should reject unsolicited 206")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: partFile.path))
        }

        // Bad hash rejection
        do {
            let res = resource(path: "/hash", bytes: -1, hash: "bad-hash-value")
            _ = try await worker.download(task: &task, source: MockFileSource(resources: [res]), part: partFile, check: {})
            XCTFail("Should reject bad hash")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: partFile.path))
        }
    }

    private func seedPartial(length: Int) throws {
        let partialData = zipData.subdata(in: 0..<length)
        try partialData.write(to: partFile, options: .atomic)
        let validatorURL = URL(fileURLWithPath: partFile.path + ".etag")
        try "v1\nnull\n\"same\"".write(to: validatorURL, atomically: true, encoding: .utf8)
    }

    func testResumesOnlyValidRangeWithSameStrongEtag() async throws {
        try seedPartial(length: 3)
        server.route("/resume") { req in
            XCTAssertEqual(req.header("Range"), "bytes=3-")
            XCTAssertEqual(req.header("If-Range"), "\"same\"")
            let slice = self.zipData.subdata(in: 3..<self.zipData.count)
            return LocalTestHTTPServer.Response(
                statusCode: 206,
                headers: [
                    "ETag": "\"same\"",
                    "Content-Range": "bytes 3-\(self.zipData.count - 1)/\(self.zipData.count)"
                ],
                body: slice
            )
        }

        let res = resource(path: "/resume", bytes: Int64(zipData.count))
        let source = MockFileSource(resources: [res])
        let worker = FileDownloadWorker()
        let result = try await worker.download(task: &task, source: source, part: partFile, check: {})

        XCTAssertEqual(result.bytes, Int64(zipData.count))
        let written = try Data(contentsOf: partFile)
        XCTAssertEqual(written, zipData)
    }

    func testRangeIgnoredByServerRestartsFile() async throws {
        try seedPartial(length: 3)
        server.route("/restart") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/zip"],
                body: self.zipData
            )
        }

        let res = resource(path: "/restart", bytes: -1)
        let source = MockFileSource(resources: [res])
        let worker = FileDownloadWorker()
        let result = try await worker.download(task: &task, source: source, part: partFile, check: {})

        XCTAssertEqual(result.bytes, Int64(zipData.count))
        let written = try Data(contentsOf: partFile)
        XCTAssertEqual(written, zipData)
    }

    func testRejectsWrongRangeAndEtag() async throws {
        server.route("/wrong_range") { _ in
            let slice = self.zipData.subdata(in: 3..<self.zipData.count)
            return LocalTestHTTPServer.Response(
                statusCode: 206,
                headers: [
                    "ETag": "\"same\"",
                    "Content-Range": "bytes 2-\(self.zipData.count - 1)/\(self.zipData.count)"
                ],
                body: slice
            )
        }
        server.route("/changed_etag") { _ in
            let slice = self.zipData.subdata(in: 3..<self.zipData.count)
            return LocalTestHTTPServer.Response(
                statusCode: 206,
                headers: [
                    "ETag": "\"changed\"",
                    "Content-Range": "bytes 3-\(self.zipData.count - 1)/\(self.zipData.count)"
                ],
                body: slice
            )
        }

        let worker = FileDownloadWorker()

        try seedPartial(length: 3)
        do {
            let res = resource(path: "/wrong_range", bytes: -1)
            _ = try await worker.download(task: &task, source: MockFileSource(resources: [res]), part: partFile, check: {})
            XCTFail("Should reject wrong range")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: partFile.path))
        }

        try seedPartial(length: 3)
        do {
            let res = resource(path: "/changed_etag", bytes: -1)
            _ = try await worker.download(task: &task, source: MockFileSource(resources: [res]), part: partFile, check: {})
            XCTFail("Should reject changed etag")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: partFile.path))
        }
    }

    func testStripsAllSourceHeadersOnCrossOriginRedirect() async throws {
        let other = try LocalTestHTTPServer()
        other.start()
        defer { other.stop() }

        let visited = Counter()
        other.route("/file") { req in
            XCTAssertNil(req.header("Authorization"))
            XCTAssertNil(req.header("X-Custom-Key"))
            _ = visited.increment()
            return LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/zip"],
                body: self.zipData
            )
        }

        server.route("/redirect") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 302,
                headers: ["Location": other.url(for: "/file")],
                body: Data()
            )
        }

        let res = resource(path: "/redirect", bytes: -1, headers: ["Authorization": "secret", "X-Custom-Key": "secret"])
        let source = MockFileSource(resources: [res])
        let worker = FileDownloadWorker()
        _ = try await worker.download(task: &task, source: source, part: partFile, check: {})

        XCTAssertEqual(visited.count, 1)
        let written = try Data(contentsOf: partFile)
        XCTAssertEqual(written, zipData)
    }

    func testRefreshesExpiredAccessOnceAndRejectsRepeated403() async throws {
        let count = Counter()
        server.route("/expired") { _ in
            _ = count.increment()
            return LocalTestHTTPServer.Response(statusCode: 403, body: Data())
        }
        server.route("/valid") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/zip"],
                body: self.zipData
            )
        }

        let expired = resource(path: "/expired", bytes: -1)
        let valid = resource(path: "/valid", bytes: -1)
        let source = MockFileSource(resources: [expired, valid])
        let worker = FileDownloadWorker()
        _ = try await worker.download(task: &task, source: source, part: partFile, check: {})

        XCTAssertEqual(count.count, 1)
        let written = try Data(contentsOf: partFile)
        XCTAssertEqual(written, zipData)

        // Repeated 403 fails
        task.refreshCount = 0
        let expiredOnlySource = MockFileSource(resources: [expired])
        do {
            _ = try await worker.download(task: &task, source: expiredOnlySource, part: partFile, check: {})
            XCTFail("Should fail on repeated 403")
        } catch {
            XCTAssertEqual(count.count, 3) // 1 initial + 2 in repeated test
        }
    }

    func testNewRevisionDiscardsPartialBytes() async throws {
        try seedPartial(length: 3)
        server.route("/new_rev") { req in
            XCTAssertNil(req.header("Range"))
            return LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/zip"],
                body: self.zipData
            )
        }

        let res = FileResource(fileId: "vol1", revision: "v2", title: "第一卷", order: 0,
                               expectedFormat: "zip", bytes: Int64(zipData.count), sha256: nil,
                               url: server.url(for: "/new_rev"), headers: [:], expiresAt: 0)
        let source = MockFileSource(resources: [res])
        let worker = FileDownloadWorker()
        _ = try await worker.download(task: &task, source: source, part: partFile, check: {})

        let written = try Data(contentsOf: partFile)
        XCTAssertEqual(written, zipData)
    }

    func testPauseStopsTransferAndRetainsOnlyValidatedResumeState() async throws {
        server.route("/pause") { _ in
            LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: [
                    "ETag": "\"same\"",
                    "Content-Type": "application/zip"
                ],
                body: self.zipData
            )
        }

        let res = resource(path: "/pause", bytes: -1)
        let source = MockFileSource(resources: [res])
        let worker = FileDownloadWorker()

        do {
            _ = try await worker.download(task: &task, source: source, part: partFile, check: {
                if FileManager.default.fileExists(atPath: self.partFile.path),
                   let attr = try? FileManager.default.attributesOfItem(atPath: self.partFile.path),
                   (attr[.size] as? NSNumber)?.intValue ?? 0 > 0 {
                    throw DownloadError.taskCancelled
                }
            })
            XCTFail("Should have cancelled")
        } catch {
            let validatorURL = URL(fileURLWithPath: partFile.path + ".etag")
            XCTAssertTrue(FileManager.default.fileExists(atPath: validatorURL.path))
        }
    }

    func testPreviousCompletedFileProtectedOnFailure() async throws {
        let completedFile = tempDir.appendingPathComponent("book.zip")
        let originalContent = Data([99, 99, 99])
        try originalContent.write(to: completedFile)

        server.route("/fail") { _ in
            LocalTestHTTPServer.Response(statusCode: 500, body: Data("error".utf8))
        }

        let res = resource(path: "/fail", bytes: -1)
        let source = MockFileSource(resources: [res])
        let worker = FileDownloadWorker()

        do {
            _ = try await worker.download(task: &task, source: source, part: partFile, check: {})
            XCTFail("Expected failure")
        } catch {
            // Completed target file remains untouched
            let existing = try Data(contentsOf: completedFile)
            XCTAssertEqual(existing, originalContent)
            // Part file was cleaned up on failure
            XCTAssertFalse(FileManager.default.fileExists(atPath: partFile.path))
        }
    }
}
