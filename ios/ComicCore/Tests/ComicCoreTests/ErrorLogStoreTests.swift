import XCTest
@testable import ComicCore

final class ErrorLogStoreTests: XCTestCase {
    private var tempFile: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("error_logs_test_\(UUID().uuidString).txt")
    }

    override func tearDownWithError() throws {
        if let tempFile = tempFile {
            try? FileManager.default.removeItem(at: tempFile)
        }
        try super.tearDownWithError()
    }

    func testEmptyStore() {
        let store = ErrorLogStore(userDefaults: nil, fileURL: tempFile)
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.entries().isEmpty)
        XCTAssertEqual(store.allText(), "")
    }

    func testAppendAndParseEntries() {
        let store = ErrorLogStore(userDefaults: nil, fileURL: tempFile)

        enum SampleError: LocalizedError {
            case networkTimeout
            var errorDescription: String? { "请求连接超时" }
        }

        store.append(title: "站源请求失败", error: SampleError.networkTimeout)
        XCTAssertEqual(store.count, 1)

        let firstBatch = store.entries()
        XCTAssertEqual(firstBatch.count, 1)
        XCTAssertEqual(firstBatch[0].title, "站源请求失败")
        XCTAssertTrue(firstBatch[0].message.contains("SampleError: 请求连接超时"))
        XCTAssertFalse(firstBatch[0].timestamp.isEmpty)

        // 追加第二条，最新一条应该排在最前面
        store.append(title: "章节图片解码失败", error: nil, detail: "损坏的 PNG 签名")
        XCTAssertEqual(store.count, 2)

        let secondBatch = store.entries()
        XCTAssertEqual(secondBatch.count, 2)
        XCTAssertEqual(secondBatch[0].title, "章节图片解码失败")
        XCTAssertEqual(secondBatch[0].message, "损坏的 PNG 签名")
        XCTAssertEqual(secondBatch[1].title, "站源请求失败")
    }

    func testClear() {
        let store = ErrorLogStore(userDefaults: nil, fileURL: tempFile)
        store.append(title: "错误一", error: nil, detail: "详情一")
        store.append(title: "错误二", error: nil, detail: "详情二")
        XCTAssertEqual(store.count, 2)

        store.clear()
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.entries().isEmpty)
        XCTAssertEqual(store.allText(), "")
    }

    func testMaxCharactersTruncation() {
        let store = ErrorLogStore(userDefaults: nil, fileURL: tempFile)
        let largePayload = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ", count: 5000) // 130,000 字符
        store.append(title: "超大崩溃日志", error: nil, detail: largePayload)

        let text = store.allText()
        XCTAssertLessThanOrEqual(text.count, ErrorLogStore.maxCharacters)
    }

    func testSanitizationOnAppend() {
        let store = ErrorLogStore(userDefaults: nil, fileURL: tempFile)
        store.append(
            title: "请求失败: https://api.example.com/v1/page?token=secret123&auth=my_password",
            error: nil,
            detail: "Header: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\nCookie: session_id=xyz789;"
        )

        let text = store.allText()
        XCTAssertFalse(text.contains("secret123"))
        XCTAssertFalse(text.contains("my_password"))
        XCTAssertFalse(text.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"))
        XCTAssertFalse(text.contains("xyz789"))
        XCTAssertTrue(text.contains("[REDACTED]"))
        XCTAssertTrue(text.contains("Bearer [REDACTED]"))
        XCTAssertTrue(text.contains("Cookie: [REDACTED]"))
    }
}
