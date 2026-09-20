import XCTest
@testable import ComicCore

final class ContentFingerprintTests: XCTestCase {
    private var root: URL!
    private let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    private let abcHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    @discardableResult private func write(_ path: String, _ data: Data = Data("abc".utf8)) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func testStandardFileVectorsAndOriginalBytesRemainUnchanged() throws {
        let empty = try write("empty", Data()), abc = try write("abc")
        XCTAssertEqual(try ContentFingerprint.file(empty, maximumBytes: 0), emptyHash)
        XCTAssertEqual(try ContentFingerprint.file(abc, maximumBytes: 3), abcHash)
        let bytes = Data(repeating: 97, count: 768 * 1024 + 17)
        let large = try write("chunks", bytes)
        XCTAssertEqual(try ContentFingerprint.file(large), "f72ff80ee465c71bf9dceb28be42abe12cc10fdaa73cf0b6c7571d98edd3fe0a")
        XCTAssertEqual(try Data(contentsOf: large), bytes)
        XCTAssertEqual(try Data(contentsOf: abc), Data("abc".utf8))
    }

    func testFolderMatchesAndroidManifestInNaturalOrder() throws {
        try write("2.png"); try write("10.png", Data())
        let expected = "289a7e9d8b7639baa049ca4aed2c3fc55cf31ec0056560ea3459ff175cc325d3"
        XCTAssertEqual(try ContentFingerprint.folder(root, relativeImagePaths: ["10.png", "2.png"]), expected)
        XCTAssertEqual(try ContentFingerprint.folder(root, relativeImagePaths: ["2.png", "10.png"]), expected)
        XCTAssertEqual(try ContentFingerprint.folder(root, relativeImagePaths: []), emptyHash)
    }

    func testManifestPreservesWrapperSpacesAndOriginalUnicodeBytes() throws {
        let a = "包装 空间/卷2/é 2.png", b = "包装 空间/卷2/é 10.png"
        try write(a); try write(b, Data())
        XCTAssertEqual(try ContentFingerprint.folder(root, relativeImagePaths: [b, a]),
                       "870df7b0d9a97cadf1eda17ebe677317d7c773c3829a188397b64b14a9094730")
        try write("e\u{0301}.png")
        XCTAssertEqual(try ContentFingerprint.folder(root, relativeImagePaths: ["e\u{0301}.png"]),
                       "f4b5b1583b45cc231719975eedf5e7916ebe92d90a12ff61e7b82e31f226e5cf")
        try write("é.png")
        XCTAssertEqual(try ContentFingerprint.folder(root, relativeImagePaths: ["é.png"]),
                       "ffea95376fba9eed789dba14f1befa7bb58f49896153bfc09ed926ddb53d86ed")
    }

    func testRenameAndContentChangeAlterIdentity() throws {
        let original = try write("2.png")
        let first = try ContentFingerprint.folder(root, relativeImagePaths: ["2.png"])
        let renamed = root.appendingPathComponent("3.png")
        try FileManager.default.moveItem(at: original, to: renamed)
        let second = try ContentFingerprint.folder(root, relativeImagePaths: ["3.png"])
        XCTAssertNotEqual(first, second)
        try Data("abd".utf8).write(to: renamed)
        XCTAssertNotEqual(second, try ContentFingerprint.folder(root, relativeImagePaths: ["3.png"]))
    }

    func testFileRejectsInvalidURLDirectoryMissingAndLimits() throws {
        let file = try write("abc")
        XCTAssertThrowsError(try ContentFingerprint.file(file, maximumBytes: -1))
        XCTAssertThrowsError(try ContentFingerprint.file(file, maximumBytes: 2))
        XCTAssertThrowsError(try ContentFingerprint.file(root))
        XCTAssertThrowsError(try ContentFingerprint.file(root.appendingPathComponent("missing")))
        XCTAssertThrowsError(try ContentFingerprint.file(URL(string: "https://example.org/file")!))
    }

    func testFolderRejectsUnsafeDuplicateAndExcessPaths() throws {
        try write("2.png")
        for path in ["", "/2.png", "../2.png", "a/../2.png", "./2.png", "a//2.png", "a/", "a\\2.png", "a\0.png"] {
            XCTAssertThrowsError(try ContentFingerprint.folder(root, relativeImagePaths: [path]), path)
        }
        XCTAssertThrowsError(try ContentFingerprint.folder(root, relativeImagePaths: ["2.png", "2.png"]))
        XCTAssertThrowsError(try ContentFingerprint.folder(root, relativeImagePaths: (0...50_000).map { "\($0).png" }))
        XCTAssertThrowsError(try ContentFingerprint.folder(URL(string: "https://example.org/")!, relativeImagePaths: []))
        XCTAssertThrowsError(try ContentFingerprint.folder(root.appendingPathComponent("2.png"), relativeImagePaths: []))
        XCTAssertThrowsError(try ContentFingerprint.folder(root, relativeImagePaths: ["missing.png"]))
    }

    func testRejectsRootIntermediateAndFileSymbolicLinks() throws {
        let file = try write("real/2.png")
        let fileLink = root.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: file)
        XCTAssertThrowsError(try ContentFingerprint.file(fileLink))
        XCTAssertThrowsError(try ContentFingerprint.folder(root, relativeImagePaths: ["link.png"]))
        let folderLink = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: folderLink, withDestinationURL: file.deletingLastPathComponent())
        XCTAssertThrowsError(try ContentFingerprint.folder(root, relativeImagePaths: ["linked/2.png"]))
        XCTAssertThrowsError(try ContentFingerprint.folder(folderLink, relativeImagePaths: []))
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createSymbolicLink(at: outside, withDestinationURL: root.deletingLastPathComponent())
        XCTAssertThrowsError(try ContentFingerprint.folder(root, relativeImagePaths: ["outside/anything.png"]))
    }

    func testFolderRejectsImageOver128MiBBeforeReading() throws {
        let file = try write("huge.png", Data())
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 128 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try ContentFingerprint.folder(root, relativeImagePaths: ["huge.png"]))
    }

    func testPreCancelledFileAndFolderThrowCancellation() async throws {
        let file = try write("abc"), directory = root!
        for folder in [false, true] {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try folder ? ContentFingerprint.folder(directory, relativeImagePaths: []) : ContentFingerprint.file(file)
            }
            do { _ = try await task.value; XCTFail("Cancelled hashing succeeded") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
    }

    func testRunningCancellationStopsRealChunkPipeline() async throws {
        let file = try write("chunks", Data(repeating: 97, count: 768 * 1024 + 17))
        let task = Task {
            var reads = 0
            return try ContentFingerprint.file(file, maximumBytes: 1_048_576) { handle, count in
                reads += 1
                XCTAssertLessThanOrEqual(count, 256 * 1024)
                let data = try handle.read(upToCount: count)
                if reads == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                return data
            }
        }
        do { _ = try await task.value; XCTFail("Cancelled hashing succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testReadErrorPropagatesWithoutPublishingDigest() throws {
        let file = try write("abc")
        var readError: NSError?
        // Close the real input descriptor, so FileHandle itself produces the read error.
        XCTAssertThrowsError(try ContentFingerprint.file(file, maximumBytes: 3) { handle, count in
            try handle.close()
            do { return try handle.read(upToCount: count) }
            catch { readError = error as NSError; throw error }
        }) {
            XCTAssertNotNil(readError)
            XCTAssertEqual(($0 as NSError).domain, readError?.domain)
            XCTAssertEqual(($0 as NSError).code, readError?.code)
        }
    }

    func testTruncationAndGrowthDuringReadCannotReturnMixedIdentity() throws {
        for truncate in [true, false] {
            let file = try write("changing", Data(repeating: 97, count: 512 * 1024))
            var reads = 0
            XCTAssertThrowsError(try ContentFingerprint.file(file, maximumBytes: 512 * 1024) { handle, count in
                let data = try handle.read(upToCount: count)
                reads += 1
                if reads == 1 {
                    let writer = try FileHandle(forWritingTo: file)
                    defer { try? writer.close() }
                    if truncate { try writer.truncate(atOffset: 256 * 1024) }
                    else { try writer.seekToEnd(); try writer.write(contentsOf: Data([98])) }
                }
                return data
            })
        }
    }
}
