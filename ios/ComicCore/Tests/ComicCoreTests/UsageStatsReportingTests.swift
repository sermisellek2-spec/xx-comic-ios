import XCTest
@testable import ComicCore

private actor StatisticsTransport: HTTPTransport {
    private(set) var bodies: [Data] = []
    var status = 200
    var hold = false
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse { throw HTTPTransportError.unsupportedMethod }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
        bodies.append(body)
        if hold {
            await withCheckedContinuation { release = $0; started?.resume(); started = nil }
        }
        return HTTPResponse(data: Data(), statusCode: status)
    }
    func setStatus(_ status: Int) { self.status = status }
    func holdResponse() { hold = true }
    func waitForStart() async { if release == nil { await withCheckedContinuation { started = $0 } } }
    func complete() { release?.resume(); release = nil }
}

final class UsageStatsReportingTests: XCTestCase {
    private let info = UsageStatsApplicationInfo(appVersion: "2.0.40", versionCode: 340, osVersion: "16.0", deviceModel: "Apple iPhone")
    private let date = Date(timeIntervalSince1970: 1700000000)
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRealIsolatedHTTPPostSucceedsAndRedirectIsNotFollowed() async throws {
        let server = try LocalTestHTTPServer()
        server.route("/collect") { _ in .init(statusCode: 200) }
        server.route("/redirect") { _ in .init(statusCode: 302, statusText: "Found", headers: ["Location": "/must-not-receive"]) }
        server.route("/must-not-receive") { _ in .init(statusCode: 200) }
        server.start(); defer { server.stop() }
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = UsageStatsClient(directory: folder, reportingURL: URL(string: server.url(for: "/collect"))!)
        let accepted = await client.reportIfNeeded(info: info, date: date, uptime: 1)
        XCTAssertTrue(accepted)
        let other = folder.appendingPathComponent("redirect-state")
        let redirectClient = UsageStatsClient(directory: other, reportingURL: URL(string: server.url(for: "/redirect"))!)
        let redirected = await redirectClient.reportIfNeeded(info: info, date: date, uptime: 1)
        XCTAssertFalse(redirected)
        let requests = server.recordedRequests()
        XCTAssertEqual(requests.map(\.path), ["/collect", "/redirect"])
        XCTAssertTrue(requests.allSatisfy { $0.method == "POST" })
        XCTAssertEqual(requests.first?.header("Content-Type"), "application/json; charset=UTF-8")
        XCTAssertEqual(redirectClient.lastReportedDay, "")
    }

    func testDailySuccessPersistsAcrossRestartWithExactlyOriginalFiveFields() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let transport = StatisticsTransport()
        let client = UsageStatsClient(directory: folder, transport: transport)
        let first = await client.reportIfNeeded(info: info, date: date, uptime: 1)
        XCTAssertTrue(first)
        let restored = UsageStatsClient(directory: folder, transport: transport)
        let duplicate = await restored.reportIfNeeded(info: info, date: date, uptime: 1000)
        XCTAssertFalse(duplicate)
        let next = await restored.reportIfNeeded(info: info, date: date.addingTimeInterval(86400), uptime: 1001)
        XCTAssertTrue(next)
        let bodies = await transport.bodies
        XCTAssertEqual(bodies.count, 2)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["installId", "appVersion", "versionCode", "osVersion", "deviceModel"])
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[1]) as? [String: Any])
        XCTAssertEqual(payload["installId"] as? String, second["installId"] as? String)
    }

    func testFailureDoesNotMarkDayAndRetriesOnlyOnLaterForegroundAfterCooldown() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let transport = StatisticsTransport(); await transport.setStatus(503)
        let client = UsageStatsClient(directory: folder, transport: transport)
        let failed = await client.reportIfNeeded(info: info, date: date, uptime: 1)
        XCTAssertFalse(failed); XCTAssertEqual(client.lastReportedDay, "")
        await transport.setStatus(200)
        let tooSoon = await client.reportIfNeeded(info: info, date: date, uptime: 2)
        XCTAssertFalse(tooSoon)
        let retry = await client.reportIfNeeded(info: info, date: date, uptime: 901)
        XCTAssertTrue(retry)
        let count = await transport.bodies.count; XCTAssertEqual(count, 2)
    }

    func testDisabledStatisticsNeverSendsAndReenableUsesSameSettingFile() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let transport = StatisticsTransport()
        let client = UsageStatsClient(directory: folder, transport: transport)
        try client.setEnabled(false)
        let skipped = await client.reportIfNeeded(info: info, date: date, uptime: 1)
        XCTAssertFalse(skipped)
        let count = await transport.bodies.count; XCTAssertEqual(count, 0)
        try client.setEnabled(true)
        let accepted = await client.reportIfNeeded(info: info, date: date, uptime: 1)
        XCTAssertTrue(accepted)
    }

    func testConcurrentForegroundAndDisablingDuringRequestDoNotCommitReport() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let transport = StatisticsTransport(); await transport.holdResponse()
        let client = UsageStatsClient(directory: folder, transport: transport)
        let first = Task { await client.reportIfNeeded(info: info, date: date, uptime: 1) }
        await transport.waitForStart()
        let duplicate = await client.reportIfNeeded(info: info, date: date, uptime: 2)
        XCTAssertFalse(duplicate)
        try client.setEnabled(false)
        await transport.complete()
        let accepted = await first.value
        XCTAssertFalse(accepted); XCTAssertEqual(client.lastReportedDay, "")
        XCTAssertFalse(UsageStatsClient(directory: folder).isEnabled)
        let count = await transport.bodies.count; XCTAssertEqual(count, 1)
    }

    func testCorruptSettingIsPreservedWithoutSilentEnableOrNetwork() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("usage-stats.json")
        let original = Data("broken user preference".utf8); try original.write(to: file)
        let transport = StatisticsTransport()
        let client = UsageStatsClient(directory: folder, transport: transport)
        XCTAssertFalse(client.isEnabled); XCTAssertNil(client.payload())
        XCTAssertThrowsError(try client.setEnabled(true))
        let accepted = await client.reportIfNeeded(info: info, date: date, uptime: 1)
        XCTAssertFalse(accepted); XCTAssertEqual(try Data(contentsOf: file), original)
        let count = await transport.bodies.count; XCTAssertEqual(count, 0)
    }
}
