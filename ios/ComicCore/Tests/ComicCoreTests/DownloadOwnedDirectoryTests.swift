import XCTest
@testable import ComicCore

final class DownloadOwnedDirectoryTests: XCTestCase {
    func testDirectoryURLFormsIdentifyTheSameOwnedChildrenAndKeepUnknownFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let book = root.appendingPathComponent("作品 é", isDirectory: true)
        let chapter = book.appendingPathComponent("章节 ü", isDirectory: true)
        try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true)
        try Data("owned image".utf8).write(to: chapter.appendingPathComponent("0.img"))
        try Data("owned cover".utf8).write(to: book.appendingPathComponent("cover.img"))
        let forms = [book, URL(fileURLWithPath: book.path, isDirectory: false), book.resolvingSymlinksInPath().standardizedFileURL]
        for directory in forms {
            try DownloadOwnedDirectory.validate(directory, allowedDirectories: [chapter.lastPathComponent],
                allowedFiles: ["cover.img"], taskIDs: [chapter.lastPathComponent])
        }
        let original = chapter.appendingPathComponent("original.txt")
        try Data("keep".utf8).write(to: original)
        for directory in forms {
            XCTAssertThrowsError(try DownloadOwnedDirectory.validate(directory, allowedDirectories: [chapter.lastPathComponent],
                allowedFiles: ["cover.img"], taskIDs: [chapter.lastPathComponent]))
        }
        XCTAssertEqual(try Data(contentsOf: original), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: chapter.appendingPathComponent("0.img")), Data("owned image".utf8))
    }
}
