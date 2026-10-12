import Foundation
import ZIPFoundation
import ComicCore
import UIKit

/// Real comic files and rejected text inputs in the isolated Debug UI-test sandbox.
@MainActor
enum EpubUITestFixtures {
    static var sessionID: String? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return nil }
        return UUID(uuidString: ProcessInfo.processInfo.environment["XXCOMIC_UI_TEST_SESSION"] ?? "")?.uuidString
        #else
        return nil
        #endif
    }

    #if DEBUG
    static func seed(library: LocalLibrary) throws {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--epub-fixtures"),
              library.directory.deletingLastPathComponent().lastPathComponent == "XXComic-UITests" else { return }
        if ProcessInfo.processInfo.arguments.contains("--batch-import-fixtures") {
            try BatchImportUITestFixtures.seed(library: library); return
        }
        if ProcessInfo.processInfo.arguments.contains("--kindle-fixtures") {
            try seedKindleImports(library: library); return
        }
        let folder = library.directory.appendingPathComponent(".epub-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = Set(try library.books().map(\.title))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }.pngData()!
        for kind in ["图片", "文字", "图文", "单图带文字", "旧文字"] {
            let title = "EPUB 验收·" + kind, url = folder.appendingPathComponent(title + ".epub")
            if !FileManager.default.fileExists(atPath: url.path) {
                var files: [String: Data] = ["META-INF/container.xml": Data("<container><rootfile full-path='OPS/book.opf'/></container>".utf8),
                    "OPS/nav.xhtml": Data("<html><nav><ol><li><a href='a.xhtml'>第一章</a></li><li><a href='b.xhtml'>第二章</a></li></ol></nav></html>".utf8),
                    "OPS/image.png": image]
                let picture = kind == "图片"
                files["OPS/a.xhtml"] = Data((picture ? "<html><body><img src='image.png'/></body></html>" : "<html><body><p>纯文字正文</p>" + (kind == "单图带文字" ? "<img src='image.png'/>" : "") + "</body></html>").utf8)
                files["OPS/b.xhtml"] = Data((picture || kind == "图文" ? "<html><body><img src='image.png'/></body></html>" : "<html><body><p>第二章文字</p></body></html>").utf8)
                files["OPS/book.opf"] = Data(("<package><metadata/><manifest><item id='a' href='a.xhtml' media-type='application/xhtml+xml'/><item id='b' href='b.xhtml' media-type='application/xhtml+xml'/><item id='image' href='image.png' media-type='image/png'/><item id='nav' href='nav.xhtml' media-type='application/xhtml+xml' properties='nav'/></manifest><spine><itemref idref='a'/><itemref idref='b'/></spine></package>").utf8)
                let archive = try Archive(url: url, accessMode: .create)
                for (path, bytes) in files {
                    try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count), compressionMethod: .deflate) { position, count in
                        bytes.subdata(in: Int(position)..<min(Int(position) + count, bytes.count))
                    }
                }
            }
            guard !existing.contains(title) else { continue }
            if kind == "图片" { _ = try library.importEpub(title: title, archive: url, isReadableImage: LocalImageProbe.isReadable) }
            if kind == "旧文字" {
                // A genuine old book.json remains loadable. It is never newly imported as text.
                let publication = try EpubParser.parse(archive: url), id = UUID().uuidString
                let pages = publication.spine.indices.map { "spine-\($0)" }
                let chapters = try publication.chapterRanges().enumerated().map { index, range in
                    LocalBookChapter(id: id + "_ch_\(index)", title: range.title, pages: Array(pages[range.startIndex..<range.endIndex]))
                }
                let book = LocalBook(id: id, title: title, createdAt: 1, pages: pages, chapters: chapters, epub: publication)
                let owned = library.directory.appendingPathComponent(id)
                try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
                try FileManager.default.copyItem(at: url, to: owned.appendingPathComponent("content.epub"))
                try JSONEncoder().encode(book).write(to: owned.appendingPathComponent("book.json"))
            }
        }
    }

    static func epubImports(library: LocalLibrary) -> [(String, URL)] {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--epub-fixtures"),
              !ProcessInfo.processInfo.arguments.contains("--kindle-fixtures"), !ProcessInfo.processInfo.arguments.contains("--batch-import-fixtures"),
              library.directory.deletingLastPathComponent().lastPathComponent == "XXComic-UITests" else { return [] }
        return ["文字", "图文", "单图带文字"].map { ("验收 EPUB·" + $0, library.directory.appendingPathComponent(".epub-fixtures").appendingPathComponent("EPUB 验收·" + $0 + ".epub")) }
    }

    static func kindleImports(library: LocalLibrary) -> [(String, URL)] {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--epub-fixtures"), ProcessInfo.processInfo.arguments.contains("--kindle-fixtures"),
              library.directory.deletingLastPathComponent().lastPathComponent == "XXComic-UITests" else { return [] }
        return [("小说", "mobi"), ("漫画", "azw"), ("图文", "mobi"), ("KF8", "azw3"), ("DRM", "mobi")].map { kind, ext in
            ("验收 Kindle·" + kind, library.directory.appendingPathComponent(".kindle-fixtures").appendingPathComponent("Kindle 验收·\(kind).\(ext)"))
        }
    }

    private static func seedKindleImports(library: LocalLibrary) throws {
        let folder = library.directory.appendingPathComponent(".kindle-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }.pngData()!
        let long = (1...100).map { "<p id='p\($0)'>Kindle 长篇正文，第 \($0) 段，用于验证实际阅读与位置恢复。</p>" }.joined()
        for (name, url) in kindleImports(library: library) {
            let comic = name.hasSuffix("漫画"), mixed = name.hasSuffix("图文")
            let body = comic ? "<img recindex='1'/>" : "<h1>第一章</h1>" + long + (mixed ? "<img recindex='1'/><img recindex='2'/>" : "") + "<mbp:pagebreak/><h1>第二章</h1><p>Kindle 第二章正文</p>" + long
            let text = Data(body.utf8), images = comic ? [image, image, image] : (mixed ? [image, image] : [])
            func put(_ bytes: inout Data, _ offset: Int, _ value: UInt32) {
                bytes.replaceSubrange(offset..<offset + 4, with: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
            }
            var header = Data(repeating: 0, count: 256)
            header[1] = 1; header[9] = 1; header[13] = name.hasSuffix("DRM") ? 2 : 0
            put(&header, 4, UInt32(text.count)); header.replaceSubrange(16..<20, with: Data("MOBI".utf8))
            put(&header, 20, 232); put(&header, 24, 2); put(&header, 28, 65001); put(&header, 36, name.hasSuffix("KF8") ? 8 : 6)
            put(&header, 108, images.isEmpty ? .max : 2); put(&header, 168, .max); put(&header, 172, .max)
            let records = [header, text] + images
            var bytes = Data(repeating: 0, count: 78 + records.count * 8)
            bytes.replaceSubrange(0..<4, with: Data("Book".utf8)); bytes.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8)); bytes[77] = UInt8(records.count)
            var offset = bytes.count
            for (index, record) in records.enumerated() { put(&bytes, 78 + index * 8, UInt32(offset)); offset += record.count }
            for record in records { bytes += record }
            try bytes.write(to: url, options: .atomic)
        }
    }

    #endif
}
