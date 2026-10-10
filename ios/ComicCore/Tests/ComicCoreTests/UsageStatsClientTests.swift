import XCTest
@testable import ComicCore

final class UsageStatsClientTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageStatsClientTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    func testDefaultStateIsEnabledAndGeneratesPayload() {
        let client = UsageStatsClient(directory: tempDirectory)
        XCTAssertTrue(client.isEnabled)
        XCTAssertTrue(client.isDecided)

        let payload = client.payload()
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?["appVersion"] as? String, "2.0.40")
        XCTAssertEqual(payload?["versionCode"] as? Int, 340)
        XCTAssertFalse((payload?["installId"] as? String ?? "").isEmpty)
    }

    func testDisablingUsageStatsReturnsNilPayload() {
        let client = UsageStatsClient(directory: tempDirectory)
        client.setEnabled(false)
        XCTAssertFalse(client.isEnabled)
        XCTAssertTrue(client.isDecided)
        XCTAssertNil(client.payload())

        // Reload fresh instance from disk
        let reloaded = UsageStatsClient(directory: tempDirectory)
        XCTAssertFalse(reloaded.isEnabled)
        XCTAssertNil(reloaded.payload())
    }

    func testBeijingDayFormatting() {
        // Date with known GMT time
        let date = Date(timeIntervalSince1970: 1700000000) // 2023-11-14 22:13:20 UTC -> 2023-11-15 06:13:20 Beijing
        let day = UsageStatsClient.beijingDay(date: date)
        XCTAssertEqual(day, "2023-11-15")
    }

    func testMarkDayReportedPersists() {
        let client = UsageStatsClient(directory: tempDirectory)
        client.markDayReported("2026-10-10")
        XCTAssertEqual(client.lastReportedDay, "2026-10-10")

        let reloaded = UsageStatsClient(directory: tempDirectory)
        XCTAssertEqual(reloaded.lastReportedDay, "2026-10-10")
    }
}
