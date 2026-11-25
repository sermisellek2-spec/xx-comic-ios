import Foundation
import XCTest
@testable import ComicCore
#if canImport(ImageIO) && canImport(CoreGraphics)
import ImageIO
import CoreGraphics
#endif

final class Parity2056CacheExportAndFixesTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir(_ prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func be32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }

    private func be64(_ value: UInt64) -> [UInt8] {
        [
            UInt8((value >> 56) & 0xff),
            UInt8((value >> 48) & 0xff),
            UInt8((value >> 40) & 0xff),
            UInt8((value >> 32) & 0xff),
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }

    private func makeBox(fourCC: String, payload: [UInt8], use64BitSize: Bool = false) -> Data {
        let cc = Array(fourCC.utf8)
        precondition(cc.count == 4)
        var out = Data()
        if use64BitSize {
            let total = UInt64(16 + payload.count)
            out.append(contentsOf: be32(1))
            out.append(contentsOf: cc)
            out.append(contentsOf: be64(total))
        } else {
            let total = UInt32(8 + payload.count)
            out.append(contentsOf: be32(total))
            out.append(contentsOf: cc)
        }
        out.append(contentsOf: payload)
        return out
    }

    private func makeSyntheticAvif(use64BitMdat: Bool = false, includeMeta: Bool = true, mdatPayloadCount: Int = 16) -> Data {
        var ftypPayload = Array("avif".utf8)
        ftypPayload.append(contentsOf: be32(0))
        ftypPayload.append(contentsOf: Array("mif1".utf8))
        ftypPayload.append(contentsOf: Array("avif".utf8))

        var data = makeBox(fourCC: "ftyp", payload: ftypPayload)
        if includeMeta {
            data.append(makeBox(fourCC: "meta", payload: [UInt8](repeating: 0, count: 12)))
        }
        data.append(makeBox(fourCC: "mdat", payload: [UInt8](repeating: 0xab, count: mdatPayloadCount), use64BitSize: use64BitMdat))
        return data
    }

    private static let minimalValidPng = Data([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
        0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
        0x42, 0x60, 0x82
    ])

    private static let minimalRuleScript = """
    var source = {
      latest: function(p){return [];},
      search: function(q,p){return [];},
      filters: function(){return [];},
      category: function(f,p){return [];},
      detail: function(id){return {title:'t',chapters:[]};},
      chapters: function(id){return [];},
      chapter: function(u){return {images:['https://a.example.com/1.jpg']};}
    };
    """

    // MARK: - 1. AvifImageHelper

    func testAvifHeaderAndContainerCompleteness() throws {
        let dir = try makeTempDir("AvifHelperTests")
        defer { try? FileManager.default.removeItem(at: dir) }

        let validAvif = makeSyntheticAvif()
        XCTAssertTrue(RuleImageData.isIsoBmffImageHeader(validAvif))
        XCTAssertTrue(AvifImageHelper.isAvifHeader(validAvif))
        XCTAssertTrue(AvifImageHelper.hasCompleteContainer(data: validAvif))

        let valid64 = makeSyntheticAvif(use64BitMdat: true)
        XCTAssertTrue(AvifImageHelper.hasCompleteContainer(data: valid64))

        let validFile = dir.appendingPathComponent("valid.avif")
        try validAvif.write(to: validFile)
        XCTAssertTrue(AvifImageHelper.isAvifFile(at: validFile))
        XCTAssertTrue(AvifImageHelper.hasCompleteContainer(at: validFile))

        let valid64File = dir.appendingPathComponent("valid64.avif")
        try valid64.write(to: valid64File)
        XCTAssertTrue(AvifImageHelper.hasCompleteContainer(at: valid64File))

        // Truncated mdat payload
        let truncated = validAvif.dropLast(3)
        let truncatedFile = dir.appendingPathComponent("truncated.avif")
        try Data(truncated).write(to: truncatedFile)
        XCTAssertTrue(AvifImageHelper.isAvifFile(at: truncatedFile))
        XCTAssertFalse(AvifImageHelper.hasCompleteContainer(at: truncatedFile))
        XCTAssertFalse(AvifImageHelper.hasCompleteContainer(data: Data(truncated)))

        // Missing meta/moov
        let noMeta = makeSyntheticAvif(includeMeta: false)
        let noMetaFile = dir.appendingPathComponent("nometa.avif")
        try noMeta.write(to: noMetaFile)
        XCTAssertFalse(AvifImageHelper.hasCompleteContainer(at: noMetaFile))

        // Empty mdat (payload length 0)
        let emptyMdat = makeSyntheticAvif(mdatPayloadCount: 0)
        let emptyMdatFile = dir.appendingPathComponent("emptymdat.avif")
        try emptyMdat.write(to: emptyMdatFile)
        XCTAssertFalse(AvifImageHelper.hasCompleteContainer(at: emptyMdatFile))

        // Unsized box (boxSize == 0) must be rejected
        var unsized = makeBox(fourCC: "ftyp", payload: Array("avif".utf8) + be32(0) + Array("mif1".utf8))
        unsized.append(makeBox(fourCC: "meta", payload: [UInt8](repeating: 0, count: 8)))
        unsized.append(contentsOf: be32(0))
        unsized.append(contentsOf: Array("mdat".utf8))
        unsized.append(contentsOf: [UInt8](repeating: 1, count: 16))
        let unsizedFile = dir.appendingPathComponent("unsized.avif")
        try unsized.write(to: unsizedFile)
        XCTAssertFalse(AvifImageHelper.hasCompleteContainer(at: unsizedFile))

        // Non-AVIF ISOBMFF brand (mp42)
        let mp4 = makeBox(fourCC: "ftyp", payload: Array("mp42".utf8) + be32(0) + Array("isom".utf8))
        XCTAssertFalse(RuleImageData.isIsoBmffImageHeader(mp4))
        XCTAssertFalse(AvifImageHelper.isAvifHeader(mp4))
    }

    // MARK: - 2. CoverBitmapDecoder

    func testCoverBitmapDecoderPlanningAndTransformSafety() throws {
        XCTAssertEqual(CoverBitmapDecoder.COVER_GRID_TARGET_WIDTH, 360)
        XCTAssertEqual(CoverBitmapDecoder.COVER_GRID_TARGET_HEIGHT, 480)
        XCTAssertEqual(CoverBitmapDecoder.COVER_HERO_TARGET_WIDTH, 720)
        XCTAssertEqual(CoverBitmapDecoder.COVER_HERO_TARGET_HEIGHT, 960)
        XCTAssertEqual(CoverBitmapDecoder.MAX_NON_TRANSFORM_DECODE_PIXELS, 16_000_000)

        XCTAssertEqual(CoverBitmapDecoder.calculateInSampleSize(rawWidth: 300, rawHeight: 400, reqWidth: 360, reqHeight: 480), 1)
        XCTAssertEqual(CoverBitmapDecoder.calculateInSampleSize(rawWidth: 1440, rawHeight: 1920, reqWidth: 360, reqHeight: 480), 4)
        XCTAssertEqual(CoverBitmapDecoder.calculateInSampleSize(rawWidth: 2880, rawHeight: 3840, reqWidth: 360, reqHeight: 480), 8)

        XCTAssertFalse(CoverBitmapDecoder.shouldDownscaleRestoredBitmap(width: 540, height: 720, reqWidth: 360, reqHeight: 480))
        XCTAssertTrue(CoverBitmapDecoder.shouldDownscaleRestoredBitmap(width: 541, height: 720, reqWidth: 360, reqHeight: 480))
        XCTAssertTrue(CoverBitmapDecoder.shouldDownscaleRestoredBitmap(width: 360, height: 721, reqWidth: 360, reqHeight: 480))

        let scaled = CoverBitmapDecoder.computeScaledDimensions(width: 1200, height: 2400, maxWidth: 360, maxHeight: 480)
        XCTAssertEqual(scaled.width, 240)
        XCTAssertEqual(scaled.height, 480)

        // Non-transform large image subsamples and caps below 16MP
        let nonTxPlan = CoverBitmapDecoder.planDecode(
            rawWidth: 8000,
            rawHeight: 8000,
            imageUrl: "https://example.com/cover.jpg",
            reqWidth: 360,
            reqHeight: 480
        )
        XCTAssertFalse(nonTxPlan.hasRuleTransform)
        XCTAssertGreaterThanOrEqual(nonTxPlan.inSampleSize, 2)
        XCTAssertLessThanOrEqual(Int64(nonTxPlan.targetWidth) * Int64(nonTxPlan.targetHeight), 16_000_000)

        // Transform-protected cover MUST decode at inSampleSize == 1 before pixel restore
        let rule = try RuleDefinition(json: [
            "id": "cover_tx_rule",
            "name": "Cover TX",
            "version": 1,
            "engineApi": 3,
            "baseUrl": "https://a.example.com",
            "hosts": ["a.example.com"],
            "script": Self.minimalRuleScript,
            "scriptSha256": RuleDefinition.sha(Data(Self.minimalRuleScript.utf8))
        ])
        let tagged = try RuleImages.tag(
            rule: rule,
            image: [
                "url": "https://a.example.com/cover.jpg",
                "transform": ["type": "reverseBands", "bands": 4]
            ],
            chapter: "c1",
            index: -1
        )
        let txPlan = CoverBitmapDecoder.planDecode(
            rawWidth: 1200,
            rawHeight: 1600,
            imageUrl: tagged,
            reqWidth: 360,
            reqHeight: 480
        )
        XCTAssertTrue(txPlan.hasRuleTransform)
        XCTAssertEqual(txPlan.ruleTransform, "bands:4")
        XCTAssertEqual(txPlan.inSampleSize, 1)
        XCTAssertTrue(txPlan.downscaleAfterRestore)
        XCTAssertEqual(txPlan.targetWidth, 360)
        XCTAssertEqual(txPlan.targetHeight, 480)
    }

    #if canImport(ImageIO) && canImport(CoreGraphics)
    func testCoverBitmapDecoderNativeRestoreAndDownscale() throws {
        // Build an 800x1000 image where top half is red and bottom half is blue, scrambled with bands:2 (reversed halves)
        let width = 800
        let height = 1000
        let rowBytes = width * 4
        var raw = Data(count: rowBytes * height)
        raw.withUnsafeMutableBytes { buf in
            let px = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                let isTop = y < height / 2
                for x in 0..<width {
                    let off = (y * width + x) * 4
                    // Scrambled: top is blue, bottom is red; bands:2 swaps top & bottom -> top red, bottom blue
                    px[off + 0] = isTop ? 0 : 255
                    px[off + 1] = 0
                    px[off + 2] = isTop ? 255 : 0
                    px[off + 3] = 255
                }
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: raw as CFData))
        let cgImage = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let pngOut = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(pngOut as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let decoded = try XCTUnwrap(CoverBitmapDecoder.decodeData(
            pngOut as Data,
            imageUrl: "https://a.example.com/c.png#xx-bands=2",
            reqWidth: 360,
            reqHeight: 480
        ))
        // Downscaled >1.5x from 800x1000 into 360x480 -> 360x450
        XCTAssertEqual(decoded.width, 360)
        XCTAssertEqual(decoded.height, 450)
    }
    #endif

    // MARK: - 3. CoverLoadCoordinator

    func testCoverLoadCoordinatorCandidatesSanitizeRetryAndCoalesce() {
        let urls = CoverLoadCoordinator<String>.buildCandidateUrls(
            primaryUrl: " https://a.com/1.jpg ",
            fallbackUrls: ["https://a.com/1.jpg", "", "https://b.com/2.jpg", "https://c.com/3.jpg", "https://d.com/4.jpg"]
        )
        XCTAssertEqual(urls, ["https://a.com/1.jpg", "https://b.com/2.jpg", "https://c.com/3.jpg"])

        XCTAssertEqual(CoverLoadCoordinator<String>.extractSafeHost("https://CDN.Example.COM:8443/a.jpg?tok=1#frag"), "cdn.example.com")
        XCTAssertEqual(CoverLoadCoordinator<String>.extractSafeHost("not a url"), "")
        XCTAssertEqual(CoverLoadCoordinator<String>.sanitizeUrlForLog("https://CDN.Example.COM:8443/path/c.jpg?token=abc#frag"), "https://cdn.example.com:8443/path/c.jpg")

        XCTAssertTrue(CoverLoadCoordinator<String>.isRetryableCoverError(nil, httpCode: 408))
        XCTAssertTrue(CoverLoadCoordinator<String>.isRetryableCoverError(nil, httpCode: 429))
        XCTAssertTrue(CoverLoadCoordinator<String>.isRetryableCoverError(nil, httpCode: 503))
        XCTAssertFalse(CoverLoadCoordinator<String>.isRetryableCoverError(nil, httpCode: 404))
        XCTAssertFalse(CoverLoadCoordinator<String>.isRetryableCoverError(CancellationError(), httpCode: 0))
        XCTAssertTrue(CoverLoadCoordinator<String>.isRetryableCoverError(URLError(.timedOut), httpCode: 0))
        XCTAssertFalse(CoverLoadCoordinator<String>.isRetryableCoverError(URLError(.serverCertificateUntrusted), httpCode: 0))

        let coord = CoverLoadCoordinator<String>()
        XCTAssertTrue(coord.shouldLogHostFailure(host: "A.Example.com", nowMillis: 1_000))
        XCTAssertFalse(coord.shouldLogHostFailure(host: "a.example.com", nowMillis: 300_000))
        XCTAssertTrue(coord.shouldLogHostFailure(host: "a.example.com", nowMillis: 601_000))

        // LRU eviction > 128 hosts
        for i in 1...130 {
            XCTAssertTrue(coord.shouldLogHostFailure(host: "host-\(i).example.com", nowMillis: 700_000 + Int64(i)))
        }
        // "a.example.com" was evicted (128 capacity), so it logs again immediately
        XCTAssertTrue(coord.shouldLogHostFailure(host: "a.example.com", nowMillis: 701_000))

        // InFlightCoalescer + generation epoch
        final class StringListBox: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [String?] = []
            func append(_ v: String?) { lock.lock(); storage.append(v); lock.unlock() }
            func snapshot() -> [String?] { lock.lock(); defer { lock.unlock() }; return storage }
        }
        let results = StringListBox()
        let epoch1 = coord.registerLeader(key: "cover-k1") { val, _, _ in results.append(val) }
        XCTAssertGreaterThanOrEqual(epoch1, 0)
        XCTAssertEqual(coord.registerLeader(key: "cover-k1") { val, _, _ in results.append(val) }, -1)
        XCTAssertTrue(coord.isInFlightEpoch(epoch1))
        coord.clearInFlight()
        XCTAssertFalse(coord.isInFlightEpoch(epoch1))
        // Stale epoch finish does NOT fire
        coord.finishForEpoch(key: "cover-k1", expectedEpoch: epoch1, value: "stale", error: nil, cancelled: false)
        XCTAssertTrue(results.snapshot().isEmpty)

        let epoch2 = coord.registerLeader(key: "cover-k1") { val, _, _ in results.append(val) }
        XCTAssertEqual(coord.registerLeader(key: "cover-k1") { val, _, _ in results.append(val) }, -1)
        coord.finishForEpoch(key: "cover-k1", expectedEpoch: epoch2, value: "fresh", error: nil, cancelled: false)
        XCTAssertEqual(results.snapshot(), ["fresh", "fresh"])
    }

    // MARK: - 4. ComicDiskCacheStore

    func testComicDiskCacheStoreSplitCorruptInvalidationAndRetainedClear() throws {
        let dir = try makeTempDir("ComicDiskCacheTests")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ComicDiskCacheStore(cacheDir: dir)
        let s1 = ComicSummary(sourceId: "srcA", comicId: "srcA:1", title: "Fav Comic", coverUrl: "https://a/1.jpg")
        let s2 = ComicSummary(sourceId: "srcB", comicId: "srcB:2", title: "Hist Comic", coverUrl: "https://b/2.jpg")
        let s3 = ComicSummary(sourceId: "srcC", comicId: "srcC:3", title: "Transient Comic", coverUrl: "https://c/3.jpg")

        let d1 = ComicDetail(
            summary: s1, author: "Auth", status: "连载", description: "Desc", latestChapter: "第2话",
            chapters: [Chapter(chapterId: "ch1", title: "第1话", url: "https://a/c1")]
        )
        let d2 = ComicDetail(
            summary: s2, author: "Auth2", status: "完结", description: "Desc2", latestChapter: "第1话",
            chapters: [Chapter(chapterId: "ch2", title: "第1话", url: "https://b/c2")]
        )
        let c1 = ChapterPage(chapterId: "https://a/c1", title: "第1话", nextPageUrl: "", imageUrls: ["https://a/p1.jpg"])
        let c2 = ChapterPage(chapterId: "https://b/c2", title: "第1话", nextPageUrl: "", imageUrls: ["https://b/p1.jpg"])

        try store.writeSnapshots(
            summaries: [s1, s2, s3],
            details: [
                ComicDiskCacheStore.CachedDetailEntry(detail: d1, sourceParserRevision: 3, sourceRuleVersion: 1),
                ComicDiskCacheStore.CachedDetailEntry(detail: d2, sourceParserRevision: 2, sourceRuleVersion: 1) // rev < 3 -> chapters cleared on read
            ],
            chapters: [c1, c2]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.summariesFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.detailsFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.chaptersFile.path))
        XCTAssertGreaterThan(store.totalBytes(), 0)

        let readDetails = store.readDetails()
        XCTAssertEqual(readDetails.first(where: { $0.summary.comicId == "srcA:1" })?.chapters.count, 1)
        XCTAssertEqual(readDetails.first(where: { $0.summary.comicId == "srcB:2" })?.chapters.count, 0)

        // Rule version invalidation clears chapters for srcA (v1 -> v2)
        XCTAssertTrue(store.invalidateDetailsAndChapters(forSourceIds: [], ruleVersions: ["srcA": 2]))
        XCTAssertEqual(store.readDetails().first(where: { $0.summary.comicId == "srcA:1" })?.chapters.count, 0)
        XCTAssertEqual(store.readChapters().map(\.chapterId), ["https://b/c2"])

        // Retained summaries for clear
        let retained = ComicDiskCacheStore.retainedSummaryIdsForCacheClear(
            favoriteIds: ["srcA:1"],
            lastViewedKeys: ["srcB:2"],
            progressKeys: []
        )
        XCTAssertEqual(retained, ["srcA:1", "srcB:2"])
        XCTAssertTrue(store.clear(retainingSummaryIds: retained))
        XCTAssertEqual(Set(store.readSummaries().map(\.comicId)), ["srcA:1", "srcB:2"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.detailsFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.chaptersFile.path))

        // Corrupt JSON triggers .corrupt-<ts> backup
        try Data("{corrupt json".utf8).write(to: store.summariesFile)
        let recoveredSummaries = store.readSummaries()
        XCTAssertTrue(recoveredSummaries.isEmpty)
        XCTAssertTrue(store.isSummariesCorrupted)
        let dirContents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertTrue(dirContents.contains { $0.lastPathComponent.hasPrefix("summaries_v1.json.corrupt-") })
    }

    // MARK: - 5. ImageDiskCacheTrimmer

    func testImageDiskCacheTrimmerHysteresisTouchThrottleAndTrackedBytes() throws {
        let dir = try makeTempDir("ImageTrimmerTests")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(ImageDiskCacheTrimmer.lowWaterMarkBytes(1000), 800)
        XCTAssertEqual(ImageDiskCacheTrimmer.lowWaterMarkBytes(Int64.max), (Int64.max / 5) * 4 + ((Int64.max % 5) * 4) / 5)
        XCTAssertFalse(ImageDiskCacheTrimmer.shouldTouchAccessTime(lastModifiedMs: 1_000, nowMs: 301_000))
        XCTAssertTrue(ImageDiskCacheTrimmer.shouldTouchAccessTime(lastModifiedMs: 1_000, nowMs: 301_001))

        let trimmer = ImageDiskCacheTrimmer(cacheDir: dir)
        XCTAssertEqual(trimmer.peekTrackedBytes(), -1)
        // recordWrite preserves -1 before initialization
        XCTAssertEqual(trimmer.recordWrite(deltaBytes: 500), -1)

        // Create 5 files of 100 bytes each with distinct modification times
        for i in 1...5 {
            let file = dir.appendingPathComponent("img-\(i).img")
            try Data(repeating: UInt8(i), count: 100).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(1000 + i * 10))],
                ofItemAtPath: file.path
            )
        }

        XCTAssertEqual(trimmer.getTrackedBytes(), 500)
        // Max 400 bytes -> lowWaterMark = 320 bytes -> must evict oldest two (200 bytes) leaving 300 bytes
        let remaining = trimmer.trimSync(maxBytes: 400)
        XCTAssertEqual(remaining, 300)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("img-1.img").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("img-2.img").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("img-3.img").path))
        XCTAssertEqual(trimmer.recordWrite(deltaBytes: 50), 350)
    }

    // MARK: - 6. DownloadImageExporter & DownloadNamingPolicy

    func testDownloadNamingPolicyAndExporterMagicFormatDecisions() throws {
        let suite = "ExporterPrefs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(DownloadImageExporter.loadPreferredFormat(defaults: defaults), .jpg)
        DownloadImageExporter.savePreferredFormat(.png, defaults: defaults)
        XCTAssertEqual(DownloadImageExporter.loadPreferredFormat(defaults: defaults), .png)

        // Windows reserved names & illegal chars
        XCTAssertEqual(DownloadNamingPolicy.sanitize("CON", fallback: "x"), "_CON")
        XCTAssertEqual(DownloadNamingPolicy.sanitize("LPT1.txt", fallback: "x"), "_LPT1.txt")
        XCTAssertEqual(DownloadNamingPolicy.sanitize("..", fallback: "x"), "_")
        XCTAssertEqual(DownloadNamingPolicy.sanitize("A/B:C*D?E", fallback: "x"), "A_B_C_D_E")

        var used = Set<String>()
        XCTAssertEqual(DownloadImageExporter.resolveUniqueChapterDirName(usedChapterDirNames: &used, baseChapterDirName: "001_Ch", chapterId: "c1"), "001_Ch")
        let dup = DownloadImageExporter.resolveUniqueChapterDirName(usedChapterDirNames: &used, baseChapterDirName: "001_Ch", chapterId: "c2")
        XCTAssertTrue(dup.hasPrefix("001_Ch_"))
        XCTAssertNotEqual(dup, "001_Ch")

        // Magic detection incl. AVIF
        XCTAssertEqual(DownloadImageExporter.detectImageFormat(Self.minimalValidPng).mimeType, "image/png")
        XCTAssertEqual(DownloadImageExporter.detectImageFormat(Data([0xff, 0xd8, 0xff, 0xe0])).mimeType, "image/jpeg")
        XCTAssertEqual(DownloadImageExporter.detectImageFormat(makeSyntheticAvif()).mimeType, "image/avif")

        // Effective output & passthrough rules
        XCTAssertEqual(DownloadImageExporter.effectiveOutputFormat(requested: .original, hasTransform: true), .png)
        XCTAssertEqual(DownloadImageExporter.effectiveOutputFormat(requested: .original, hasTransform: false), .original)

        let pngType = DownloadImageExporter.ImageType(extension: ".png", mimeType: "image/png")
        XCTAssertFalse(DownloadImageExporter.needsBitmapDecode(requested: .original, detected: pngType, hasTransform: false))
        XCTAssertFalse(DownloadImageExporter.needsBitmapDecode(requested: .png, detected: pngType, hasTransform: false))
        XCTAssertTrue(DownloadImageExporter.needsBitmapDecode(requested: .jpg, detected: pngType, hasTransform: false))
        XCTAssertTrue(DownloadImageExporter.needsBitmapDecode(requested: .original, detected: pngType, hasTransform: true))

        // WebP fallback when unencodable
        let fallback = DownloadImageExporter.resolveTranscodeFormat(requested: .webp, hasTransform: false, webpSupported: false)
        XCTAssertEqual(fallback.format, .png)
        XCTAssertNotNil(fallback.fallbackReason)
        let supported = DownloadImageExporter.resolveTranscodeFormat(requested: .webp, hasTransform: false, webpSupported: true)
        XCTAssertEqual(supported.format, .webp)
        XCTAssertNil(supported.fallbackReason)
    }

    #if canImport(ImageIO) && canImport(CoreGraphics)
    func testDownloadImageExporterRealExportPngAndJpgAlphaFlatten() async throws {
        let root = try makeTempDir("ExporterNativeTests")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try DownloadStore(directory: root)
        let downloadsDir = root.appendingPathComponent("downloads", isDirectory: true)
        let exportDir = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let runtime = DownloadRuntime(store: store, downloadsDirectory: downloadsDir)
        let bookId = try DownloadModels.bookId(source: "src", comic: "c1")
        let taskId = try DownloadModels.key("src", "c1", "ch1")
        let detail = ComicDetail(
            summary: ComicSummary(sourceId: "src", comicId: "c1", title: "Export Comic"),
            author: "", status: "", description: "", latestChapter: "第1话",
            chapters: [Chapter(chapterId: "ch1", title: "第1话", url: "https://a/1")]
        )
        store.saveSnapshot(detail)

        let chapterDir = downloadsDir.appendingPathComponent(bookId, isDirectory: true).appendingPathComponent(taskId, isDirectory: true)
        try FileManager.default.createDirectory(at: chapterDir, withIntermediateDirectories: true)
        let pageFile = chapterDir.appendingPathComponent("0.img")
        try Self.minimalValidPng.write(to: pageFile)
        let pageHash = DownloadModels.sha256Hex(Self.minimalValidPng)
        let page = DownloadPage(index: 0, url: "https://a/p0.png", path: "\(bookId)/\(taskId)/0.img", hash: pageHash, bytes: Int64(Self.minimalValidPng.count))
        store.savePage(task: taskId, page: page)
        store.save(task: DownloadTask(
            id: taskId, bookId: bookId, sourceId: "src", comicId: "c1", chapterId: "ch1",
            title: "第1话", url: "https://a/1", order: 0, totalPages: 1, donePages: 1,
            bytes: Int64(Self.minimalValidPng.count), state: .completed
        ))

        let resultJpg = try await DownloadImageExporter.export(
            runtime: runtime, bookId: bookId, chapterIds: nil, format: .jpg, destinationDirectory: exportDir
        )
        XCTAssertEqual(resultJpg.exportedChapters, 1)
        XCTAssertEqual(resultJpg.exportedPages, 1)
        XCTAssertEqual(resultJpg.skippedPages, 0)
        XCTAssertFalse(resultJpg.cancelled)

        let exportedJpg = exportDir
            .appendingPathComponent("Export Comic")
            .appendingPathComponent("001_第1话")
            .appendingPathComponent("001.jpg")
        let jpgBytes = try Data(contentsOf: exportedJpg)
        XCTAssertEqual(DownloadImageExporter.detectImageFormat(jpgBytes).mimeType, "image/jpeg")

        // Verify offline cache remained intact
        XCTAssertEqual(try Data(contentsOf: pageFile), Self.minimalValidPng)
    }
    #endif

    // MARK: - 7. FavoriteUpdateCoordinator

    func testFavoriteUpdateCoordinatorDebounceVisitEpochAndCheckedInSession() async throws {
        let suite = "FavCoord2056.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let coord = FavoriteUpdateCoordinator(defaults: defaults)
        let ch1 = Chapter(chapterId: "1", title: "第1话", url: "/1")
        let ch2 = Chapter(chapterId: "2", title: "第2话", url: "/2")
        let rev1 = FavoriteRevision.fromChapters(latestChapterName: "第1话", chapters: [ch1])
        let rev2 = FavoriteRevision.fromChapters(latestChapterName: "第2话", chapters: [ch1, ch2])

        // Acknowledge baseline, then reload fresh coordinator -> shouldShowBadge is false until checked in session
        coord.acknowledge(sourceId: "src", comicId: "c1", revision: rev1)
        coord.recordObserved(sourceId: "src", comicId: "c1", revision: rev2)
        XCTAssertTrue(coord.shouldShowBadge(sourceId: "src", comicId: "c1"))

        let reloaded = FavoriteUpdateCoordinator(defaults: defaults)
        XCTAssertTrue(reloaded.hasPendingUpdate(sourceId: "src", comicId: "c1"))
        XCTAssertFalse(reloaded.shouldShowBadge(sourceId: "src", comicId: "c1"))

        // visitEpoch guard discards stale in-flight check
        let startVisit = reloaded.visitEpoch(sourceId: "src", comicId: "c1")
        let startFav = reloaded.favoriteEpoch(sourceId: "src", comicId: "c1")
        reloaded.onUserEnterDetail(sourceId: "src", comicId: "c1")
        XCTAssertGreaterThan(reloaded.visitEpoch(sourceId: "src", comicId: "c1"), startVisit)

        let ch3 = Chapter(chapterId: "3", title: "第3话", url: "/3")
        let rev3 = FavoriteRevision.fromChapters(latestChapterName: "第3话", chapters: [ch1, ch2, ch3])
        reloaded.recordObserved(
            sourceId: "src",
            comicId: "c1",
            revision: rev3,
            startVisitEpoch: startVisit,
            startFavoriteEpoch: startFav,
            deferPersist: true
        )
        XCTAssertFalse(reloaded.shouldShowBadge(sourceId: "src", comicId: "c1"))
        reloaded.flushPendingPersist()

        // onDetailChaptersObserved updates baseline and clears badge
        let detail = ComicDetail(
            summary: ComicSummary(sourceId: "src", comicId: "c1", title: "T"),
            author: "", status: "", description: "", latestChapter: "第3话",
            chapters: [ch1, ch2, ch3]
        )
        reloaded.onDetailChaptersObserved(sourceId: "src", comicId: "c1", detail: detail)
        XCTAssertFalse(reloaded.hasPendingUpdate(sourceId: "src", comicId: "c1"))

        // Background priority propagation check during startStartupCheck
        final class PriorityProbeSource: ComicSource, @unchecked Sendable {
            let id = "probe_src"
            let name = "Probe"
            let referer = ""
            private let lock = NSLock()
            private var _sawBackground = false
            var sawBackground: Bool { lock.lock(); defer { lock.unlock() }; return _sawBackground }
            func latest(page: Int) async throws -> [ComicSummary] { [] }
            func search(keyword: String, page: Int) async throws -> [ComicSummary] { [] }
            func detail(comicId: String) async throws -> ComicDetail {
                lock.lock()
                _sawBackground = RuleCallPriority.currentIsBackground()
                lock.unlock()
                return ComicDetail(
                    summary: ComicSummary(sourceId: id, comicId: comicId, title: "T"),
                    author: "", status: "", description: "", latestChapter: "第1话",
                    chapters: [Chapter(chapterId: "1", title: "第1话", url: "/1")]
                )
            }
            func chapters(comicId: String) async throws -> [Chapter] { [] }
            func chapter(url: String) async throws -> ChapterPage { ChapterPage(chapterId: "1", title: "1", imageUrls: []) }
            func filterGroups() async throws -> [SourceFilterGroup] { [] }
            func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { [] }
        }

        let probe = PriorityProbeSource()
        let task = reloaded.startStartupCheck(
            favorites: [(sourceId: "probe_src", comicId: "c-bg")],
            sourceProvider: { _ in probe }
        )
        await task.value
        XCTAssertTrue(probe.sawBackground)
    }

    // MARK: - 8. Parity Fixes (Log, Stats, DoublePage, Pdf, Bookshelf, FavoriteRevision, DownloadRuntime)

    func testErrorLogSanitizerUsageStatsDoublePagePdfBookshelfAndFavoriteRevision() throws {
        // ErrorLogSanitizer
        let rawLog = "GET https://api.example.com/v1/page?token=abc&foo=bar failed; Authorization: Basic dXNlcjpwYXNz; Bearer jwt123; x-auth-token: secret99"
        let clean = ErrorLogSanitizer.sanitize(rawLog)
        XCTAssertTrue(clean.contains("https://api.example.com/v1/page?[redacted]"))
        XCTAssertFalse(clean.contains("foo=bar"))
        XCTAssertTrue(clean.contains("Basic [REDACTED]"))
        XCTAssertFalse(clean.contains("dXNlcjpwYXNz"))
        XCTAssertTrue(clean.contains("Bearer [REDACTED]"))
        XCTAssertFalse(clean.contains("jwt123"))
        XCTAssertTrue(clean.contains("x-auth-token: [REDACTED]"))
        XCTAssertFalse(clean.contains("secret99"))

        // UsageStatsClient endpoint
        XCTAssertEqual(UsageStatsClient.endpoint, "https://weifeng.cloud/telemetry/collect")

        // ReaderDoublePage NaN / < 1.05 returns sample.aspect
        let sample = DoublePageDetector.Sample(width: 800, height: 1000)
        let nanDecision = DoublePageDetector.decide(sample: sample, chapterMedian: .nan)
        XCTAssertFalse(nanDecision.split)
        XCTAssertEqual(nanDecision.aspect, sample.aspect, accuracy: 1e-9)
        let lowDecision = DoublePageDetector.decide(sample: sample, chapterMedian: 0.8)
        XCTAssertFalse(lowDecision.split)
        XCTAssertEqual(lowDecision.aspect, sample.aspect, accuracy: 1e-9)

        // PdfPublication downscales large pages and enforces 6MP budget
        let downscaled = try PdfPublication.renderSize(width: 4000, height: 6000, maximumDimension: 720)
        XCTAssertEqual(downscaled, PdfPublication.PageSize(width: 480, height: 720))
        let capped = try PdfPublication.renderSize(width: 4000, height: 4000, maximumDimension: 4000)
        XCTAssertLessThanOrEqual(capped.width * capped.height, 6_000_000)

        // BookshelfLayoutHelper & BookshelfReadingStatus
        XCTAssertEqual(BookshelfLayoutHelper.formatUnreadBadgeText(count: 0, hasUpdate: true), "新")
        XCTAssertEqual(BookshelfLayoutHelper.formatUnreadBadgeText(count: -1, hasUpdate: true), "新")
        XCTAssertEqual(BookshelfLayoutHelper.formatUnreadBadgeText(count: 0, hasUpdate: false), "")

        let comic = ComicSummary(sourceId: "src", comicId: "src:1", title: "T", latestChapter: "汇总最新")
        let detail = ComicDetail(
            summary: comic, author: "", status: "", description: "", latestChapter: "详情最新",
            chapters: [Chapter(chapterId: "1", title: "第1话", url: "/1")]
        )
        let rev = FavoriteRevision(chapterIds: (1...5).map(String.init), latestChapterName: "观测最新", chapterCount: 5)
        let statusPending = BookshelfReadingStatus(comic: comic, reading: nil, revision: rev, detail: detail, pendingUpdate: true)
        XCTAssertEqual(statusPending.unreadCount, 5)
        XCTAssertEqual(statusPending.latestChapter, "观测最新")

        // FavoriteRevision normalizeChapterUrl & extractChapterNumber
        XCTAssertEqual(
            FavoriteRevision.normalizeChapterUrl("https://host.com/c/1?token=secret&t=1700000000&b=2&a=1#frag"),
            "/c/1?a=1&b=2"
        )
        XCTAssertEqual(FavoriteRevision.extractChapterNumber("第１２話"), 12)
        XCTAssertEqual(FavoriteRevision.extractChapterNumber("2025年 新年特辑"), nil)
        XCTAssertEqual(FavoriteRevision.extractChapterNumber("15 - 标题"), 15)
    }

    func testDownloadRuntimeBlacklistHooksImageValidatorAvifAndKeepAliveFetcher() async throws {
        // ImageValidator AVIF + container end markers
        XCTAssertTrue(ImageValidator.isValidImage(data: makeSyntheticAvif()))
        XCTAssertFalse(ImageValidator.isValidImage(data: Data(makeSyntheticAvif().dropLast(4))))
        XCTAssertTrue(ImageValidator.isValidImage(data: Self.minimalValidPng))
        XCTAssertFalse(ImageValidator.isValidImage(data: Data(Self.minimalValidPng.prefix(33))))

        let dir = try makeTempDir("DownloadBlacklistTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try DownloadStore(directory: dir)
        let runtime = DownloadRuntime(store: store, downloadsDirectory: dir.appendingPathComponent("dl"))
        runtime.suspendForBackground()

        XCTAssertTrue(DownloadRuntime.isPausableState(.queued))
        XCTAssertTrue(DownloadRuntime.isPausableState(.downloading))
        XCTAssertTrue(DownloadRuntime.isPausableState(.waitingVerification))
        XCTAssertFalse(DownloadRuntime.isPausableState(.completed))

        let detail = ComicDetail(
            summary: ComicSummary(sourceId: "src", comicId: "c1", title: "進擊的巨人"),
            author: "", status: "", description: "", latestChapter: "",
            chapters: [Chapter(chapterId: "ch1", title: "第1话", url: "https://a/1")]
        )
        runtime.enqueue(detail: detail, selectedChapterIds: ["ch1"])
        let matched = runtime.findMatchingBookIdsByTitle("进击的巨人")
        XCTAssertEqual(matched.count, 1)
        XCTAssertTrue(runtime.hasPausableTasks(forBookIds: matched))
        let pausedIds = runtime.pauseTasks(forBookIds: matched)
        XCTAssertEqual(pausedIds.count, 1)
        XCTAssertEqual(store.get(id: pausedIds[0])?.state, .pausedUser)
        XCTAssertFalse(runtime.hasPausableTasks(forBookIds: matched))
        runtime.resumeTasks(taskIds: pausedIds)
        XCTAssertEqual(store.get(id: pausedIds[0])?.state, .queued)

        // DefaultDownloadImageFetcher shared Keep-Alive + image/avif Accept + RuleCallPriority
        let server = try LocalTestHTTPServer()
        server.route("/avif.img") { req in
            let accept = req.header("Accept") ?? ""
            XCTAssertTrue(accept.contains("image/avif"))
            return LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "image/avif"],
                body: self.makeSyntheticAvif()
            )
        }
        server.start()
        defer { server.stop() }

        let dest = dir.appendingPathComponent("fetched.avif")
        let res = try await DefaultDownloadImageFetcher.shared.fetch(
            sourceId: "src",
            url: server.url(for: "/avif.img"),
            referer: "https://src.example.com/",
            destination: dest,
            check: {}
        )
        XCTAssertEqual(res.bytes, Int64(makeSyntheticAvif().count))
    }
}
