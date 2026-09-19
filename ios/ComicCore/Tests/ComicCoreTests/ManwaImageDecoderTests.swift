import XCTest
@testable import ComicCore

final class ManwaImageDecoderTests: XCTestCase {
    // The Android regression fixture was generated independently with .NET AES-CBC.
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9AAAAABJRU5ErkJggg==")!
    private let encrypted = Data(base64Encoded: "AAECAwQFBgcICQoLDA0OD54Tk4Nv+8l3Uh1THnnKXglPAH8cC/Tv25bOvDH6oRQArf7/DrKbyeVJ4noUr0XJwZLp/D3rGO6sUAtVnQsw81HqEsIN/dDPOSp+6DzeooBM")!

    func testEncryptedImageRestoresOriginalBytesAndPlainImagePassesThrough() throws {
        XCTAssertEqual(try ManwaImageDecoder.decode(encrypted), png)
        XCTAssertEqual(try ManwaImageDecoder.decode(png), png)
        for prefix in [[UInt8](arrayLiteral: 0xff, 0xd8, 0xff), Array("GIF89a".utf8), Array("RIFF0000WEBP".utf8)] {
            let image = Data(prefix + Array(repeating: 0, count: 16))
            XCTAssertEqual(try ManwaImageDecoder.decode(image), image)
        }
    }

    func testTruncatedHTMLAndWrongKeysAreRejected() {
        for input in [Data(repeating: 0, count: 5), Data(encrypted.dropLast()), Data("<html><body>Access denied</body></html>".utf8)] {
            XCTAssertThrowsError(try ManwaImageDecoder.decode(input))
        }
        XCTAssertThrowsError(try ManwaImageDecoder.decode(encrypted, publicKey: "invalid"))
        XCTAssertThrowsError(try ManwaImageDecoder.decode(encrypted, publicKey: "01234567890123456789012345678901"))
    }

    func testHostMatchingDoesNotCaptureLookalikesOtherSourcesOrLocalFiles() {
        for url in ["https://tu.mwzu.cc/a.jpg", "https://tu.mhttu.cc/a.jpg", "https://mwtuwu.cc/a.jpg", "https://MANWACE.CC/a.jpg"] {
            XCTAssertTrue(ManwaImageDecoder.usesImageHost(url))
        }
        for url in ["https://mwtuwu.cc.example.com/a.jpg", "https://other.test/a?host=mwtuwu.cc", "file:///tmp/manwace.cc/a.jpg", "not a URL"] {
            XCTAssertFalse(ManwaImageDecoder.usesImageHost(url))
        }
    }
}
