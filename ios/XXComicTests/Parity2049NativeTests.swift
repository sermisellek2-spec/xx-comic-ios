import XCTest
import UIKit
import Darwin
import ComicCore
@testable import XXComic

private final class NativeLoopbackServer: @unchecked Sendable {
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
        let head = "HTTP/1.1 \(reply.status) OK\r\nContent-Type: \(reply.contentType)\r\nContent-Length: \(reply.body.count)\r\nConnection: close\r\n\r\n"
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
final class Parity2049NativeTests: XCTestCase {

    func testAll111RealV3BundleRulesParseValidateAndPreserveCapabilities() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundleURL = repoRoot.appendingPathComponent("rules/dist/xx-comic-all-sources.xxrules.json")
        let data = try Data(contentsOf: bundleURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let bundle = try RuleStore.parseCompatible(json: json)
        XCTAssertEqual(bundle.skipped, 0)
        XCTAssertEqual(bundle.rules.count, 111)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Validate111-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let catalog = RuleCatalog(directory: tempDir, debug: true)

        for rule in bundle.rules {
            XCTAssertTrue(rule.engineApi == 2 || rule.engineApi == 3, "Rule \(rule.id) must target engineApi 2..3")
            XCTAssertNoThrow(try catalog.validate(rule), "JavaScriptCore validation failed for \(rule.id)")
        }

        let byID = Dictionary(uniqueKeysWithValues: bundle.rules.map { ($0.id, $0) })
        XCTAssertEqual(byID["guoman8"]?.engineApi, 3)
        XCTAssertEqual(byID["guoman8"]?.minIntervalMs, 250)
        XCTAssertEqual(byID["guoman8"]?.allowsCleartext("img.guoman8.cc"), true)
        XCTAssertEqual(byID["ehentai"]?.engineApi, 3)
        XCTAssertEqual(byID["ehentai"]?.minIntervalMs, 350)
        XCTAssertGreaterThanOrEqual(byID["veryim"]?.version ?? 0, 4)
        XCTAssertNotNil(byID["acgn"])
        XCTAssertNotNil(byID["manwa"])
        XCTAssertNotNil(byID["xinmanhua"])
        XCTAssertNotNil(byID["jmcomic"])
        XCTAssertEqual(bundle.rules.filter(\.requiresVpn).count, 34)
    }

    func testRuleWebRendererExecutesDynamicDomWaitSelectorAndBlocksImages() async throws {
        final class HitCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func increment() {
                lock.lock()
                value += 1
                lock.unlock()
            }
            func get() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }
        let imageHits = HitCounter()

        let server = try NativeLoopbackServer { path in
            if path == "/blocked.png" {
                imageHits.increment()
                return .init(status: 200, contentType: "image/png", body: Data([0x89, 0x50, 0x4E, 0x47]))
            }
            let html = """
            <!doctype html><html><body>
            <img src="/blocked.png" />
            <script>
            setTimeout(function() {
              var el = document.createElement('div');
              el.id = 'ready-chapter';
              el.textContent = 'Rendered-2049';
              document.body.appendChild(el);
            }, 40);
            </script>
            </body></html>
            """
            return .init(status: 200, contentType: "text/html; charset=utf-8", body: Data(html.utf8))
        }
        defer { server.stop() }

        let pageURL = "http://127.0.0.1:\(server.port)/page"
        let script = """
        var source = {
          latest: function(p){return {items:[],hasMore:false};},
          filters: function(){return [];},
          category: function(f,p){return {items:[],hasMore:false};},
          detail: function(id){return {title:'t',chapters:[]};},
          chapters: function(id){return [];},
          chapter: function(u){return {images:['https://127.0.0.1/1.jpg']};},
          search: function(q,p){
            var r = xx.render('\(pageURL)', { waitSelector: '#ready-chapter', waitMs: 30, timeoutMs: 8000 });
            var nodes = xx.select(r.body, '#ready-chapter', r.url);
            var title = nodes.length ? nodes[0].text : 'missing';
            return { items: [{ id: '1', title: title, cover: '' }], hasMore: false };
          }
        };
        """

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Render2049-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let catalog = RuleCatalog(directory: tempDir, debug: true)

        let rule = try RuleDefinition(json: [
            "id": "render_dom_rule",
            "name": "Render DOM Rule",
            "version": 1,
            "engineApi": 3,
            "baseUrl": "https://127.0.0.1",
            "hosts": ["127.0.0.1"],
            "cleartextHosts": ["127.0.0.1"],
            "requires": ["render"],
            "script": script,
            "scriptSha256": RuleDefinition.sha(Data(script.utf8))
        ])
        _ = try catalog.store().install([rule], validator: { try catalog.validate($0) }, subscription: "")
        catalog.refresh()

        let source = try XCTUnwrap(catalog.source("render_dom_rule"))
        let results: [ComicSummary]
        do {
            results = try await source.search(keyword: "test", page: 1)
        } catch {
            XCTFail("render_dom_rule search threw: \((error as? LocalizedError)?.errorDescription ?? String(describing: error))")
            return
        }
        XCTAssertEqual(results.first?.title, "Rendered-2049")
        XCTAssertEqual(imageHits.get(), 0, "WKContentRuleList must block subresource image loads during xx.render")
    }

    func testRemoteImageViewRestoresScrambledCoverAndAutoRefreshesBrokenImageNode() async throws {
        // Build a 40x40 scrambled PNG where order [3, 2, 1, 0] puts yellow at top-left (raw) and red at bottom-right (raw).
        // After tiles [3, 2, 1, 0] restoration, top-left must be red and bottom-right must be yellow!
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let scrambledImage = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: fmt).image { ctx in
            // Raw tile 0 (top-left): yellow (belongs at dst tile 3)
            UIColor(red: 1, green: 1, blue: 0, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            // Raw tile 1 (top-right): blue (belongs at dst tile 2)
            UIColor(red: 0, green: 0, blue: 1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
            // Raw tile 2 (bottom-left): green (belongs at dst tile 1)
            UIColor(red: 0, green: 1, blue: 0, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 20, width: 20, height: 20))
            // Raw tile 3 (bottom-right): red (belongs at dst tile 0)
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            ctx.fill(CGRect(x: 20, y: 20, width: 20, height: 20))
        }
        let scrambledPng = try XCTUnwrap(scrambledImage.pngData())

        let server = try NativeLoopbackServer { path in
            if path == "/broken.png" {
                // Broken CDN node returning HTTP 200 text/html anti-hotlink page
                return .init(status: 200, contentType: "text/html; charset=utf-8", body: Data("<html>hotlink blocked</html>".utf8))
            }
            return .init(status: 200, contentType: "image/png", body: scrambledPng)
        }
        defer { server.stop() }

        let brokenURL = "http://127.0.0.1:\(server.port)/broken.png"
        let goodURL = "http://127.0.0.1:\(server.port)/good.png"
        let script = """
        var source = {
          latest: function(p){return [];},
          search: function(q,p){return [];},
          filters: function(){return [];},
          category: function(f,p){return [];},
          detail: function(id){return {title:'t',chapters:[]};},
          chapters: function(id){return [];},
          chapter: function(u){return {images:['\(goodURL)']};},
          image: function(desc, force){
            return {
              url: force ? '\(goodURL)' : '\(brokenURL)',
              transform: { type: 'tiles', cols: 2, rows: 2, order: [3, 2, 1, 0] }
            };
          }
        };
        """

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CoverRefresh2049-" + UUID().uuidString, isDirectory: true)
        let suite = "CoverRefresh2049." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let environment = try AppEnvironment(defaults: defaults, storageDirectory: root, forceFreshInstall: true)
        defer {
            environment.cancelFolderSynchronization()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try environment.usageStats.setEnabled(false)

        let rule = try RuleDefinition(json: [
            "id": "cover_refresh_rule",
            "name": "Cover Refresh Rule",
            "version": 1,
            "engineApi": 3,
            "baseUrl": "https://127.0.0.1",
            "hosts": ["127.0.0.1"],
            "cleartextHosts": ["127.0.0.1"],
            "imageRefresh": true,
            "script": script,
            "scriptSha256": RuleDefinition.sha(Data(script.utf8))
        ])
        _ = try environment.ruleCatalog.store().updateSubscriptions([rule])
        environment.reloadSources()
        RemoteImageView.clearMemoryCache()

        let taggedCover = try RuleImages.tag(
            rule: rule,
            image: [
                "url": brokenURL,
                "transform": ["type": "tiles", "cols": 2, "rows": 2, "order": [3, 2, 1, 0]]
            ],
            chapter: "",
            index: -1
        )

        // reader: false exercises cover loading AND HTTP 200 text/html auto-refresh (force: true)
        let decoded = try await RemoteImageView.fetchDecodedImage(url: taggedCover, referer: "", reader: false)
        let cg = try XCTUnwrap(decoded.cgImage)
        XCTAssertEqual(cg.width, 40)
        XCTAssertEqual(cg.height, 40)

        var rgba = [UInt8](repeating: 0, count: 40 * 40 * 4)
        let ctx = try XCTUnwrap(CGContext(
            data: &rgba,
            width: 40,
            height: 40,
            bitsPerComponent: 8,
            bytesPerRow: 40 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 40, height: 40))

        let topLeftIdx = (5 * 40 + 5) * 4
        XCTAssertGreaterThan(rgba[topLeftIdx], 200, "Restored top-left R should be red")
        XCTAssertLessThan(rgba[topLeftIdx + 1], 40, "Restored top-left G should be ~0")

        let bottomRightIdx = (35 * 40 + 35) * 4
        XCTAssertGreaterThan(rgba[bottomRightIdx], 200, "Restored bottom-right R should be yellow")
        XCTAssertGreaterThan(rgba[bottomRightIdx + 1], 200, "Restored bottom-right G should be yellow")
        XCTAssertLessThan(rgba[bottomRightIdx + 2], 40, "Restored bottom-right B should be ~0")
    }

    func testForegroundDetailBusyTokenIsIdempotentAndNotifiesIdleObservers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DetailBusy2049-" + UUID().uuidString, isDirectory: true)
        let suite = "DetailBusy2049." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let environment = try AppEnvironment(defaults: defaults, storageDirectory: root, forceFreshInstall: true)
        defer {
            environment.cancelFolderSynchronization()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try environment.usageStats.setEnabled(false)

        var idleCallbacks = 0
        let obs = environment.observeForegroundDetailIdle { idleCallbacks += 1 }
        defer { environment.removeForegroundDetailIdleObserver(obs) }

        XCTAssertFalse(environment.isForegroundDetailBusy)
        let t1 = environment.beginForegroundDetailLoad()
        let t2 = environment.beginForegroundDetailLoad()
        XCTAssertTrue(environment.isForegroundDetailBusy)

        environment.endForegroundDetailLoad(t1)
        environment.endForegroundDetailLoad(t1) // idempotent duplicate release
        XCTAssertTrue(environment.isForegroundDetailBusy)
        XCTAssertEqual(idleCallbacks, 0)

        environment.endForegroundDetailLoad(t2)
        XCTAssertFalse(environment.isForegroundDetailBusy)
        XCTAssertEqual(idleCallbacks, 1)
    }
}
