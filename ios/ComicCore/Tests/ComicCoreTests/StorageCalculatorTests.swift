import XCTest
@testable import ComicCore

final class StorageCalculatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage_calc_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testEmptyDirectorySize() throws {
        let size = try StorageCalculator.directorySize(at: tempDir)
        XCTAssertEqual(size, 0)
    }

    func testDirectorySizeWithNestedFiles() throws {
        let file1 = tempDir.appendingPathComponent("file1.bin")
        let file2Subdir = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: file2Subdir, withIntermediateDirectories: true)
        let file2 = file2Subdir.appendingPathComponent("file2.bin")

        let data1 = Data(repeating: 0x41, count: 1024) // 1 KB
        let data2 = Data(repeating: 0x42, count: 2048) // 2 KB
        try data1.write(to: file1)
        try data2.write(to: file2)

        let size = try StorageCalculator.directorySize(at: tempDir)
        XCTAssertEqual(size, 3072)
    }

    func testFormatBytes() {
        XCTAssertEqual(StorageCalculator.formatBytes(512), "512 B")
        XCTAssertEqual(StorageCalculator.formatBytes(1024), "1.0 KB")
        XCTAssertEqual(StorageCalculator.formatBytes(1536), "1.5 KB")
        XCTAssertEqual(StorageCalculator.formatBytes(1024 * 1024 * 5), "5.0 MB")
        XCTAssertEqual(StorageCalculator.formatBytes(1024 * 1024 * 1024 * 3), "3.0 GB")
    }
}
