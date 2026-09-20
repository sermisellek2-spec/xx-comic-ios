#if canImport(ImageIO)
import XCTest
@testable import ComicCore

final class LocalImageProbeTests: XCTestCase {
    func testOnlyDecodableImagesAreAccepted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Shared with Android's independently recorded image fixture.
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9AAAAABJRU5ErkJggg=="))
        let file = root.appendingPathComponent("image.png")
        try png.write(to: file)
        XCTAssertTrue(try LocalImageProbe.isReadable(file))
        // IHDR still advertises dimensions, but no image pixels remain.
        try Data(png.prefix(33)).write(to: file)
        XCTAssertFalse(try LocalImageProbe.isReadable(file))
        try Data("<html>not an image</html>".utf8).write(to: file)
        XCTAssertFalse(try LocalImageProbe.isReadable(file))
        let link = root.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try LocalImageProbe.isReadable(link))
    }

    func testOversizedFileAndCancellationFailBeforeDecoding() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 128 * 1024 * 1024 + 1)
        try handle.close()
        XCTAssertThrowsError(try LocalImageProbe.isReadable(file)) { error in
            guard case LocalLibraryError.imageTooLarge = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try LocalImageProbe.isReadable(file)
        }
        do { _ = try await task.value; XCTFail("Cancelled probe must throw") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
#endif
