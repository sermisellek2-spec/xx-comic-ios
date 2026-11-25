import XCTest
import UIKit
import ImageIO
import Darwin
import ComicCore
@testable import XXComic

private final class Parity2056LoopbackServer: @unchecked Sendable {
    struct Reply {
        let status: Int
        let contentType: String
        let body: Data
    }

    private let serverFd: Int32
    let port: UInt16
    private let lock = NSLock()
    private var running = true
    private let handler: @Sendable (String) -> Reply

    init(handler: @escaping @Sendable (String) -> Reply) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw URLError(.cannotOpenFile) }
        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw URLError(.cannotConnectToHost)
        }

        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assigned) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len)
            }
        }
        self.serverFd = fd
        self.port = UInt16(bigEndian: assigned.sin_port)
        self.handler = handler

        Thread.detachNewThread { [weak self] in
            guard let self else { return }
            while true {
                self.lock.lock()
                let active = self.running
                self.lock.unlock()
                if !active { break }
                let client = accept(self.serverFd, nil, nil)
                if client < 0 { break }
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.serve(client)
                }
            }
        }
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
        close(serverFd)
    }

    deinit { stop() }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var noSigPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(client, &buf, buf.count)
        guard n > 0 else { return }
        let reqText = String(decoding: buf.prefix(n), as: UTF8.self)
        let firstLine = reqText.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        let rawPath = parts.count >= 2 ? String(parts[1]) : "/"
        let path = rawPath.components(separatedBy: "?")[0]

        let reply = handler(path)
        let statusText = reply.status == 200 ? "OK" : "Error"
        let head = "HTTP/1.1 \(reply.status) \(statusText)\r\nContent-Type: \(reply.contentType)\r\nContent-Length: \(reply.body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(reply.body)
        out.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                _ = write(client, base, out.count)
            }
        }
    }
}

@MainActor
final class Parity2056NativeTests: XCTestCase {

    private func makeSolidPNG(width: Int, height: Int, color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.pngData())
    }

    func testBundle162RulesAnd16RetiredSourcesValidateInJavaScriptCore() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundleURL = repoRoot.appendingPathComponent("rules/dist/xx-comic-all-sources.xxrules.json")
        let indexURL = repoRoot.appendingPathComponent("rules/dist/index.json")

        let bundleJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: bundleURL)) as? [String: Any])
        let bundle = try RuleStore.parseCompatible(json: bundleJSON)
        XCTAssertEqual(bundle.skipped, 0)
        XCTAssertEqual(bundle.rules.count, 162)
        XCTAssertEqual(bundle.rules.filter(\.requiresVpn).count, 61)
        XCTAssertEqual(bundle.rules.filter { !$0.fallbackOf.isEmpty }.count, 22)
        XCTAssertEqual(bundle.rules.filter { $0.engineApi == 3 }.count, 162)

        let indexJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: indexURL)) as? [String: Any])
        let retired = try XCTUnwrap(indexJSON["retiredSources"] as? [[String: Any]])
        XCTAssertEqual(retired.count, 16)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Validate162-2056-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let catalog = RuleCatalog(directory: tempDir, debug: true)

        var exclusiveFilterGroupCount = 0
        for rule in bundle.rules {
            XCTAssertNoThrow(try catalog.validate(rule), "JavaScriptCore validation failed for \(rule.id)")
            if rule.script.contains("exclusiveGroup") {
                exclusiveFilterGroupCount += 1
            }
        }
        XCTAssertEqual(exclusiveFilterGroupCount, 159)
    }

    func testFailoverChainViaRuleCatalogSwitchesToBackupOnPrimaryFailure() async throws {
        let server = try Parity2056LoopbackServer { path in
            if path == "/primary/latest" {
                return .init(status: 503, contentType: "text/plain; charset=utf-8", body: Data("down".utf8))
            }
            if path == "/backup/latest" {
                let payload = #"{"items":[{"id":"b-1","title":"备份命中漫画","cover":""}],"hasMore":false}"#
                return .init(status: 200, contentType: "application/json; charset=utf-8", body: Data(payload.utf8))
            }
            return .init(status: 404, contentType: "text/plain", body: Data())
        }
        defer { server.stop() }

        let primaryScript = """
        var source = {
          latest: function(p){ return xx.get('http://127.0.0.1:\(server.port)/primary/latest'); },
          search: function(q,p){ return {items:[],hasMore:false}; },
          filters: function(){ return []; },
          category: function(f,p){ return {items:[],hasMore:false}; },
          detail: function(id){ return {title:'t',chapters:[]}; },
          chapters: function(id){ return []; },
          chapter: function(u){ return {images:[]}; }
        };
        """
        let backupScript = """
        var source = {
          latest: function(p){
            var r = xx.get('http://127.0.0.1:\(server.port)/backup/latest');
            return JSON.parse(r.body);
          },
          search: function(q,p){ return {items:[],hasMore:false}; },
          filters: function(){ return []; },
          category: function(f,p){ return {items:[],hasMore:false}; },
          detail: function(id){ return {title:'t',chapters:[]}; },
          chapters: function(id){ return []; },
          chapter: function(u){ return {images:[]}; }
        };
        """

        let primary = try RuleDefinition(json: [
            "id": "failover_primary_2056",
            "name": "主线测试源",
            "version": 1,
            "engineApi": 3,
            "baseUrl": "http://127.0.0.1:\(server.port)",
            "hosts": ["127.0.0.1"],
            "cleartextHosts": ["127.0.0.1"],
            "script": primaryScript,
            "scriptSha256": RuleDefinition.sha(Data(primaryScript.utf8))
        ])
        let backup = try RuleDefinition(json: [
            "id": "failover_backup_2056",
            "name": "备线测试源",
            "version": 1,
            "engineApi": 3,
            "fallbackOf": "failover_primary_2056",
            "baseUrl": "http://127.0.0.1:\(server.port)",
            "hosts": ["127.0.0.1"],
            "cleartextHosts": ["127.0.0.1"],
            "script": backupScript,
            "scriptSha256": RuleDefinition.sha(Data(backupScript.utf8))
        ])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FailoverCatalog-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let catalog = RuleCatalog(directory: tempDir, debug: true)
        _ = try catalog.store().install([primary, backup], validator: { try catalog.validate($0) }, subscription: "")
        catalog.refresh()

        XCTAssertFalse(catalog.visibleEntries().contains { $0.rule.id == "failover_backup_2056" })
        let composite = try XCTUnwrap(catalog.comicSource("failover_primary_2056") as? FailoverComicSource)
        XCTAssertTrue(composite.hasBackups)

        let items = try await composite.latest(page: 1)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "备份命中漫画")
        XCTAssertEqual(items.first?.sourceId, "failover_primary_2056")
    }

    func testCoverBitmapDecoderAndAvifHeaderDetection() throws {
        let png = try makeSolidPNG(width: 24, height: 32, color: .systemTeal)
        let decoded = try XCTUnwrap(CoverBitmapDecoder.decodeData(png, imageUrl: "https://fixture.invalid/c.png", reqWidth: 16, reqHeight: 24))
        XCTAssertGreaterThan(decoded.width, 0)
        XCTAssertGreaterThan(decoded.height, 0)

        var avifHeader = Data([0x00, 0x00, 0x00, 0x18])
        avifHeader.append(Data("ftypavif".utf8))
        avifHeader.append(Data(repeating: 0, count: 16))
        XCTAssertTrue(AvifImageHelper.isAvifHeader(avifHeader))
        XCTAssertFalse(AvifImageHelper.isAvifHeader(png))
    }

    func testDownloadImageExporterAllFormatsAndWebPFallbackPreserveOfflineFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Export2056-" + UUID().uuidString, isDirectory: true)
        let outRoot = FileManager.default.temporaryDirectory.appendingPathComponent("ExportOut2056-" + UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outRoot)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try DownloadStore(file: root.appendingPathComponent("downloads.json"))
        let runtime = DownloadRuntime(store: store, downloadsDirectory: root)
        let bookID = try DownloadModels.bookId(source: "fixture", comic: "export-comic")
        let taskID = try DownloadModels.key("fixture", "export-comic", "ch-1")
        let chapterDir = root.appendingPathComponent(bookID).appendingPathComponent(taskID)
        try FileManager.default.createDirectory(at: chapterDir, withIntermediateDirectories: true)

        let png = try makeSolidPNG(width: 16, height: 24, color: .systemOrange)
        let pageFile = chapterDir.appendingPathComponent("0.img")
        try png.write(to: pageFile)

        let comic = ComicSummary(sourceId: "fixture", comicId: "export-comic", title: "导出测试漫画")
        let chapter = Chapter(chapterId: "ch-1", title: "第1话", url: "https://fixture.invalid/ch-1")
        let detail = ComicDetail(summary: comic, author: "测试", status: "连载", description: "", latestChapter: "第1话", chapters: [chapter])
        store.saveSnapshot(detail)
        store.replacePages(task: taskID, pages: [
            DownloadPage(index: 0, url: "https://fixture.invalid/0.png", path: "\(bookID)/\(taskID)/0.img", hash: DownloadModels.sha256Hex(png), bytes: Int64(png.count))
        ])
        try store.saveConfirmedTask(DownloadTask(id: taskID, bookId: bookID, sourceId: "fixture", comicId: "export-comic", chapterId: "ch-1", title: "第1话", url: chapter.url, totalPages: 1, donePages: 1, state: .completed))

        let jpgOut = outRoot.appendingPathComponent("jpg", isDirectory: true)
        let jpgRes = try await DownloadImageExporter.export(runtime: runtime, bookId: bookID, chapterIds: [chapter.chapterId], format: .jpg, destinationDirectory: jpgOut)
        XCTAssertEqual(jpgRes.exportedPages, 1)
        let jpgFiles = try FileManager.default.subpathsOfDirectory(atPath: jpgOut.path).filter { $0.hasSuffix(".jpg") }
        XCTAssertEqual(jpgFiles.count, 1)

        let webpOut = outRoot.appendingPathComponent("webp", isDirectory: true)
        let webpRes = try await DownloadImageExporter.export(runtime: runtime, bookId: bookID, chapterIds: [chapter.chapterId], format: .webp, destinationDirectory: webpOut)
        XCTAssertEqual(webpRes.exportedPages, 1)
        let allWebpOutFiles = try FileManager.default.subpathsOfDirectory(atPath: webpOut.path).filter { !$0.isEmpty }
        if !DownloadImageExporter.isWebPEncodeSupported() {
            XCTAssertFalse(webpRes.fallbackReason.isEmpty, "WebP encode fallback reason must be surfaced when WebP encoder is unavailable")
            XCTAssertTrue(allWebpOutFiles.contains { $0.hasSuffix(".png") }, "Lossless fallback must write real .png files")
            XCTAssertFalse(allWebpOutFiles.contains { $0.hasSuffix(".webp") }, "Must never mislabel PNG data with a .webp extension")
        }

        XCTAssertEqual(try Data(contentsOf: pageFile), png, "Export must never alter or delete original downloaded files")
    }

    func testAppEnvironmentBlacklistAndDiskCacheClearPreserveLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Env2056-" + UUID().uuidString, isDirectory: true)
        let suite = "Env2056." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }

        let comic = ComicSummary(sourceId: "mh160", comicId: "c-2056", title: "黑名单与缓存验收")
        let detail = ComicDetail(summary: comic, author: "作者", status: "连载", description: "简介", latestChapter: "第1话", chapters: [
            Chapter(chapterId: "ch-1", title: "第1话", url: "https://fixture.invalid/ch-1")
        ])

        do {
            let env = try AppEnvironment(defaults: defaults, storageDirectory: root)
            defer { env.cancelFolderSynchronization() }
            try env.usageStats.setEnabled(false)

            try env.setFavorite(comic, favorite: true)
            XCTAssertEqual(env.visibleFavorites().count, 1)

            let added = env.addToBlacklist(title: comic.title, sourceId: comic.sourceId, sourceName: "漫画160", comicId: comic.comicId, coverUrl: "", pauseDownloads: false)
            XCTAssertNotNil(added)
            XCTAssertEqual(env.visibleFavorites().count, 0)

            XCTAssertTrue(env.restoreFromBlacklist(normalizedTitle: ComicTitleNormalizer.normalize(comic.title)))
            XCTAssertEqual(env.visibleFavorites().count, 1)

            try env.diskCacheStore.writeSnapshots(summaries: [comic], details: [ComicDiskCacheStore.CachedDetailEntry(detail: detail, sourceRuleVersion: nil)], chapters: [])
        }

        let reloaded = try AppEnvironment(defaults: defaults, storageDirectory: root)
        defer { reloaded.cancelFolderSynchronization() }
        try reloaded.usageStats.setEnabled(false)

        XCTAssertEqual(reloaded.cachedSummary(sourceId: comic.sourceId, comicId: comic.comicId)?.title, comic.title)
        XCTAssertEqual(reloaded.cachedDetail(sourceId: comic.sourceId, comicId: comic.comicId)?.author, "作者")

        _ = try await reloaded.clearCaches()
        XCTAssertNil(reloaded.cachedSummary(sourceId: comic.sourceId, comicId: comic.comicId))
        XCTAssertTrue(reloaded.diskCacheStore.readSummaries().isEmpty)
        XCTAssertEqual(reloaded.visibleFavorites().count, 1, "Cache clear must preserve library favorites")
    }

    func testTextReaderNormalizeZipPathBlocksTraversal() throws {
        XCTAssertEqual(try TextReaderViewController.normalizeZipPath("OEBPS/Text/../Images/cover.png?v=1#top"), "OEBPS/Images/cover.png")
        XCTAssertEqual(try TextReaderViewController.normalizeZipPath("/OPS/chapter1.xhtml"), "OPS/chapter1.xhtml")
        XCTAssertThrowsError(try TextReaderViewController.normalizeZipPath("../etc/passwd"))
        XCTAssertThrowsError(try TextReaderViewController.normalizeZipPath("OEBPS/../../secret.txt"))
        XCTAssertThrowsError(try TextReaderViewController.normalizeZipPath("C:/windows/system.ini"))
        XCTAssertThrowsError(try TextReaderViewController.normalizeZipPath("bad\0path.xhtml"))
    }
}
