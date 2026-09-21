import Foundation
import ZIPFoundation
import ComicCore
import UIKit

/// Real EPUB archives, enabled only in the existing isolated UI test launch path.
@MainActor
enum EpubUITestFixtures {
    static var sessionID: String? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return nil }
        return UUID(uuidString: ProcessInfo.processInfo.environment["XXCOMIC_UI_TEST_SESSION"] ?? "")?.uuidString
    }

    static func seed(library: LocalLibrary) throws {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--epub-fixtures"),
              library.directory.deletingLastPathComponent().lastPathComponent == "XXComic-UITests" else { return }
        if ProcessInfo.processInfo.arguments.contains("--kindle-fixtures") {
            try seedKindleImports(library: library)
            return
        }
        let existing = Set(try library.books().map(\.title))
        for kind in ["文字", "图文", "图片", "隔离", "跨书", "超限", "无锚点", "编码空锚点"] {
            let title = "EPUB 验收·" + kind
            guard !existing.contains(title) else { continue }
            let archiveURL = library.directory.appendingPathComponent(".fixture-\(UUID().uuidString).epub")
            defer { try? FileManager.default.removeItem(at: archiveURL) }
            let long = (1...100).map { "<p id='p\($0)'>这是验证滚动和位置恢复的真实正文，第 \($0) 段。每一节都应完整可达，图文内容保持原序。</p>" }.joined()
            let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
                UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }.pngData()!
            var files: [String: Data] = [
                "META-INF/container.xml": Data("<container><rootfile full-path='OPS/book.opf'/></container>".utf8),
                "OPS/nav.xhtml": Data("<html><nav><ol><li><a href='a.xhtml'>第一章</a></li><li><a href='c.xhtml'>第二章</a></li></ol></nav></html>".utf8),
                "OPS/a.xhtml": Data(("<html><body><h1 id='first'>正文甲</h1><a href='https://example.com/epub-test'>外部测试链接</a><a href='c.xhtml#second'>跳到第二章</a>" + long + "</body></html>").utf8),
                "OPS/b.xhtml": Data("<html><body><h1>第一章第二节</h1><p>不能遗漏的第二正文。</p></body></html>".utf8),
                "OPS/c.xhtml": Data(("<html><body><h1 id='second'>第二章正文</h1>" + long + "</body></html>").utf8)
            ]
            var manifest = "<item id='a' href='a.xhtml' media-type='application/xhtml+xml'/><item id='b' href='b.xhtml' media-type='application/xhtml+xml'/><item id='c' href='c.xhtml' media-type='application/xhtml+xml'/><item id='nav' href='nav.xhtml' media-type='application/xhtml+xml' properties='nav'/>"
            var spine = "<itemref idref='a'/><itemref idref='b'/><itemref idref='c'/>"
            if kind == "图片" || kind == "图文" || kind == "隔离" {
                files["OPS/image.png"] = image
                manifest += "<item id='image' href='image.png' media-type='image/png'/>"
                if kind == "图片" { spine = "<itemref idref='image'/>" }
                if kind == "图文" { spine = "<itemref idref='a'/><itemref idref='b'/><itemref idref='image'/><itemref idref='c'/>" }
            }
            if kind == "隔离" {
                // Script/event effects and CSS resource loading are observable through the WK accessibility tree.
                files["OPS/a.xhtml"] = Data("""
                <html><head><link rel='stylesheet' href='local.css'></head><body>
                <h1>隔离正文</h1><p id='script-status'>脚本未执行</p><p id='event-status'>事件未执行</p>
                <p class='same-book'>本书 CSS 未加载</p><p>本书资源隔离验收</p>
                <a href='https://example.com/epub-test'>外部测试链接</a><a href='javascript:document.body.textContent="JS链接执行"'>不安全链接</a>
                <script>document.getElementById('script-status').textContent='脚本已执行'</script>
                <img src='image.png' onload="document.getElementById('event-status').textContent='事件已执行'"><img src='image.png'>
                <link rel='stylesheet' href='https://example.com/blocked.css'>
                <iframe src='c.xhtml'></iframe><form action='https://example.com'><input type='submit' value='不安全表单'></form>
                </body></html>
                """.utf8)
                files["OPS/local.css"] = Data(".same-book{display:none}".utf8)
                files["OPS/foreign.css"] = Data("body{display:none!important}".utf8)
            }
            if kind == "跨书" {
                guard let foreign = try library.books().first(where: { $0.title == "EPUB 验收·隔离" }) else { throw LocalLibraryError.invalidBook }
                let url = try EpubReaderResource.url(bookID: foreign.id, path: "OPS/foreign.css")
                files["OPS/a.xhtml"] = Data("<html><head><link rel='stylesheet' href='\(url.absoluteString)'></head><body><h1>跨书样式未执行</h1></body></html>".utf8)
            }
            if kind == "超限" { files["OPS/a.xhtml"] = Data(("<html><body>" + String(repeating: "x", count: 8 * 1024 * 1024) + "</body></html>").utf8) }
            if kind == "无锚点" {
                let paragraphs = (1...100).map { "<p>没有 ID 的长篇正文，第 \($0) 段，必须使用百分比恢复阅读位置。</p>" }.joined()
                files["OPS/a.xhtml"] = Data(("<html><body><h1>无锚点正文</h1>" + paragraphs + "</body></html>").utf8)
            }
            if kind == "编码空锚点" {
                let padding = String(repeating: "<p>用于验证链接真正滚动到目标的正文段落。</p>", count: 40)
                // %2520 targets a literal "%20" ID suffix, not a space. Targets sit well below the top.
                files["OPS/a.xhtml"] = Data(("""
                <html><body><h1>编码链接起点</h1>
                <a href='#%E4%B8%AD%E6%96%87%20%E7%9B%AE%E6%A0%87'>同页中文空格</a>
                <a href='#literal%2520'>同页字面百分号</a>
                <a href='c.xhtml#%E7%AC%AC%E4%BA%8C%E7%AB%A0%20%E7%9B%AE%E6%A0%87'>跨章中文空格</a>
                <a href='c.xhtml#literal%2520'>跨章字面百分号</a>
                """ + padding + "<a id='中文 目标'></a><h2>同页中文目标已到达</h2>" + padding + "<div id='literal%20'></div><h2>同页百分号目标已到达</h2>" + padding + "</body></html>").utf8)
                files["OPS/c.xhtml"] = Data(("<html><body><h1>编码链接第二章</h1>" + padding + "<a id='第二章 目标'></a><h2>跨章中文目标已到达</h2>" + padding + "<div id='literal%20'></div><h2>跨章百分号目标已到达</h2>" + padding + "</body></html>").utf8)
            }
            files["OPS/book.opf"] = Data(("<package xmlns:dc='http://purl.org/dc/elements/1.1/'><metadata><dc:title>\(title)</dc:title><dc:creator>验收作者</dc:creator></metadata><manifest>" + manifest + "</manifest><spine>" + spine + "</spine></package>").utf8)
            do {
                let archive = try Archive(url: archiveURL, accessMode: .create)
                for (path, data) in files {
                    try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, count in
                        data.subdata(in: Int(position)..<min(Int(position) + count, data.count))
                    }
                }
            }
            _ = try library.importEpub(title: title, archive: archiveURL, isReadableImage: LocalImageProbe.isReadable)
        }
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
}
