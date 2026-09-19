import XCTest
@testable import ComicCore

final class SourceAESTests: XCTestCase {
    func testAndroidCuimhFixtureDecryptsUnchangedPublicPayload() throws {
        let payload = Data(base64Encoded: "MDEyMzQ1Njc4OWFiY2RlZutEhySNBDxh7+9pX7lLguDwdPqtjE0tJLVG7+xCkHDt8wNN7cqhoHcwG3tUWN0IQwe7JEqUHI+AXvzwvUk6n4EgljPPb5F5MAJn2Knj9EpWbv2K8oHdIjj7c8x5IkNvnFDCV2qy8rDuJUDhSUFw4lU=")!
        let plaintext = try SourceAES.decrypt(Data(payload.dropFirst(16)), key: Data("9S8$vJnU2ANeSRoF".utf8), iv: Data(payload.prefix(16)))
        XCTAssertEqual(String(data: plaintext, encoding: .utf8), #"{"host":"www.cuimh.com","source_id":"12","images":["https://img.example/1.webp","/static/2.webp"]}"#)
    }

    func test192And256BitKeysDecodeFixedPaddedVectors() throws {
        // Independently generated OpenSSL vectors; plaintext is five ASCII bytes.
        for (length, encoded) in [(24, "LnXKD5lDlD3a02rVyEbOPg=="), (32, "EaRnlaOkqJgWnAaLoHN7OA==")] {
            let plaintext = try SourceAES.decrypt(Data(base64Encoded: encoded)!, key: Data((0..<length).map(UInt8.init)), iv: Data((0..<16).map(UInt8.init)))
            XCTAssertEqual(plaintext, Data("comic".utf8))
        }
    }

    func testInvalidLengthsAndPaddingAreRejected() {
        let key = Data(repeating: 0, count: 16), iv = Data(repeating: 0, count: 16)
        for length in [0, 15, 17] {
            XCTAssertThrowsError(try SourceAES.decrypt(Data(repeating: 0, count: length), key: key, iv: iv))
        }
        XCTAssertThrowsError(try SourceAES.decrypt(Data(repeating: 0, count: 16), key: Data(repeating: 0, count: 17), iv: iv))
        XCTAssertThrowsError(try SourceAES.decrypt(Data(repeating: 0, count: 16), key: key, iv: Data(repeating: 0, count: 15)))
        // AES-CBC decryption of this all-zero block with zero key/IV has invalid PKCS7 padding.
        XCTAssertThrowsError(try SourceAES.decrypt(Data(repeating: 0, count: 16), key: key, iv: iv))
    }

    func testPreCancelledDecodeDoesNotReturnData() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SourceAES.decrypt(Data(base64Encoded: "EaRnlaOkqJgWnAaLoHN7OA==")!, key: Data((0..<32).map(UInt8.init)), iv: Data((0..<16).map(UInt8.init)))
        }
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
