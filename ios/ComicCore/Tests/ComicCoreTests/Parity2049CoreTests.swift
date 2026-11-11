import XCTest
import Foundation
@testable import ComicCore

final class Parity2049CoreTests: XCTestCase {

    private let minimalScript = """
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

    func testRuleDefinitionV3CapabilitiesCleartextAndHashIdentity() throws {
        XCTAssertEqual(RuleDefinition.API, 3)

        let v2Json: [String: Any] = [
            "id": "demo_v2",
            "name": "Demo V2",
            "version": 1,
            "engineApi": 2,
            "baseUrl": "https://a.example.com",
            "hosts": ["a.example.com", "www.aymry.com"],
            "script": minimalScript,
            "scriptSha256": RuleDefinition.sha(Data(minimalScript.utf8))
        ]
        let v2Rule = try RuleDefinition(json: v2Json)
        XCTAssertTrue(v2Rule.allowsCleartext("www.aymry.com"), "Engine API <= 2 keeps legacy cleartext allowlist")
        XCTAssertFalse(v2Rule.allowsCleartext("a.example.com"))

        let v3Json: [String: Any] = [
            "id": "demo_v3",
            "name": "Demo V3",
            "version": 2,
            "engineApi": 3,
            "baseUrl": "https://a.example.com",
            "hosts": ["a.example.com", "www.aymry.com", "*.cdn.example.com", "cdn.example.com"],
            "cleartextHosts": ["*.cdn.example.com", "cdn.example.com"],
            "requires": ["render", "cryptoV3"],
            "minIntervalMs": 250,
            "script": minimalScript,
            "scriptSha256": RuleDefinition.sha(Data(minimalScript.utf8))
        ]
        let v3Rule = try RuleDefinition(json: v3Json)
        XCTAssertFalse(v3Rule.allowsCleartext("www.aymry.com"), "Engine API 3 must not inherit legacy cleartext hosts")
        XCTAssertTrue(v3Rule.allowsCleartext("sub.cdn.example.com"))
        XCTAssertTrue(v3Rule.allowsCleartext("cdn.example.com"))
        XCTAssertFalse(v3Rule.allowsCleartext("a.example.com"))
        XCTAssertTrue(v3Rule.requiresCapability("render"))
        XCTAssertTrue(v3Rule.requiresCapability("cryptoV3"))
        XCTAssertFalse(v3Rule.requiresCapability("unknown"))
        XCTAssertEqual(v3Rule.minIntervalMs, 250)

        let roundTrip = try RuleDefinition(json: v3Rule.toDictionary())
        XCTAssertEqual(roundTrip.hash, v3Rule.hash)
        XCTAssertEqual(roundTrip.coreHash, v3Rule.coreHash)

        // Unlisted cleartextHost must fail validation
        var badCleartext = v3Json
        badCleartext["cleartextHosts"] = ["evil.other.com"]
        XCTAssertThrowsError(try RuleDefinition(json: badCleartext))

        // Unsupported future API 4 throws UnsupportedRuleError only AFTER integrity check
        var validApi4 = v3Json
        validApi4["id"] = "future_v4"
        validApi4["engineApi"] = 4
        XCTAssertThrowsError(try RuleDefinition(json: validApi4)) { error in
            XCTAssertTrue(error is UnsupportedRuleError, "Expected UnsupportedRuleError, got \(error)")
        }

        var tamperedApi4 = validApi4
        tamperedApi4["scriptSha256"] = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try RuleDefinition(json: tamperedApi4)) { error in
            XCTAssertFalse(error is UnsupportedRuleError, "Tampered script must fail integrity before UnsupportedRuleError")
        }

        // Compatible bundle parser skips valid API 4 while keeping API 3
        let bundleJson: [String: Any] = [
            "schema": "xx-comic.rules",
            "version": 1,
            "sources": [v3Json, validApi4]
        ]
        let compatible = try RuleStore.parseCompatible(json: bundleJson)
        XCTAssertEqual(compatible.rules.map(\.id), ["demo_v3"])
        XCTAssertEqual(compatible.skipped, 1)
    }

    func testDefaultRepositoryMigrationV2ToV3IsIdempotentAndRespectsUserRemoval() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RuleRepoV3-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(RuleRepository.LEGACY_DEFAULT_URL, "https://weifeng.cloud/rules/index.json")
        XCTAssertEqual(RuleRepository.DEFAULT_URL, "https://weifeng.cloud/rules/v3/index.json")

        let store = try RuleStore(directory: dir)
        try store.repository(RuleRepository.LEGACY_DEFAULT_URL, add: true)
        try store.repository("https://custom.example.com/rules/index.json", add: true)

        try store.ensureDefaultRepository()
        XCTAssertEqual(
            store.repositories(),
            ["https://weifeng.cloud/rules/v3/index.json", "https://custom.example.com/rules/index.json"]
        )

        // Removing the default v3 repository must not re-add it on next launch
        try store.repository(RuleRepository.DEFAULT_URL, add: false)
        let reopened = try RuleStore(directory: dir)
        try reopened.ensureDefaultRepository()
        XCTAssertEqual(reopened.repositories(), ["https://custom.example.com/rules/index.json"])
    }

    func testRuleCryptoV3Primitives() throws {
        // RFC 4231 Test Case 2: HMAC-SHA256("Jefe", "what do ya want for nothing?")
        let hmacHex = try RuleCrypto.convert([
            "type": "hmacSha256",
            "key": "Jefe",
            "keyEncoding": "utf8",
            "data": "what do ya want for nothing?",
            "dataEncoding": "utf8",
            "outputEncoding": "hex"
        ])
        XCTAssertEqual(hmacHex, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")

        // hexEncode / hexDecode
        let hexEncoded = try RuleCrypto.convert(["type": "hexEncode", "data": "XXComic", "dataEncoding": "utf8"])
        XCTAssertEqual(hexEncoded, "5858436f6d6963")
        let hexDecoded = try RuleCrypto.convert(["type": "hexDecode", "data": hexEncoded, "outputEncoding": "utf8"])
        XCTAssertEqual(hexDecoded, "XXComic")

        // AES-CTR encrypt & decrypt round-trip with ivPrefix
        let keyHex = "000102030405060708090a0b0c0d0e0f"
        let ivHex = "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"
        let ctrCipherB64 = try RuleCrypto.convert([
            "type": "aesCtrEncrypt",
            "key": keyHex,
            "keyEncoding": "hex",
            "iv": ivHex,
            "ivEncoding": "hex",
            "data": "Hello Rule Engine v3 CTR!",
            "dataEncoding": "utf8",
            "outputEncoding": "base64"
        ])
        let ivBytes = try RuleCrypto.parseBinary(ivHex, encoding: "hex")
        let ctBytes = try RuleBase64.decode(ctrCipherB64)
        var prefixed = Data()
        prefixed.append(ivBytes)
        prefixed.append(ctBytes)
        let ctrPlain = try RuleCrypto.convert([
            "type": "aesCtrDecrypt",
            "key": keyHex,
            "keyEncoding": "hex",
            "ivPrefix": true,
            "data": RuleBase64.encode(prefixed, false),
            "dataEncoding": "base64",
            "outputEncoding": "utf8"
        ])
        XCTAssertEqual(ctrPlain, "Hello Rule Engine v3 CTR!")

        // AES-ECB & AES-CBC round-trip
        let ecbB64 = try RuleCrypto.convert([
            "type": "aesEcbEncrypt",
            "key": keyHex,
            "keyEncoding": "hex",
            "data": "ECB-Payload-2049",
            "dataEncoding": "utf8"
        ])
        let ecbPlain = try RuleCrypto.convert([
            "type": "aesEcbDecrypt",
            "key": keyHex,
            "keyEncoding": "hex",
            "data": ecbB64,
            "dataEncoding": "base64",
            "outputEncoding": "utf8"
        ])
        XCTAssertEqual(ecbPlain, "ECB-Payload-2049")

        // xorBytes & int64 sub
        let xoredHex = try RuleCrypto.convert([
            "type": "xorBytes",
            "key": "ff00",
            "keyEncoding": "hex",
            "data": "0f0f0f0f",
            "dataEncoding": "hex",
            "outputEncoding": "hex"
        ])
        XCTAssertEqual(xoredHex, "f00ff00f")

        let subVal = try RuleCrypto.convert(["type": "int64", "op": "sub", "a": "1000000000000", "b": "250000000000"])
        XCTAssertEqual(subVal, "750000000000")
    }

    func testRuleImageDataMultiStepPipelineAndBitmapTransforms() throws {
        // Synthetic PNG header + payload
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let key = Data((0..<16).map { UInt8($0 + 1) })
        let iv = Data((0..<16).map { UInt8(0xA0 + $0) })

        // Encrypt reverse of decode steps: first AES-CTR, then XOR with 0x5A after 2-byte skip, then wrap as data URI base64
        let ctrEncrypted = try SourceAES.ctrCrypt(pngBytes, key: key, iv: iv)
        var xorEncrypted = ctrEncrypted
        for i in 2..<xorEncrypted.count {
            xorEncrypted[i] ^= 0x5A
        }
        let dataUriPayload = Data(("data:image/png;base64," + xorEncrypted.base64EncodedString()).utf8)

        let steps: [[String: Any]] = [
            ["type": "base64"],
            ["type": "xor", "key": "5a", "keyEncoding": "hex", "skipBytes": 2],
            [
                "type": "aesCtr",
                "key": key.base64EncodedString(),
                "keyEncoding": "base64",
                "iv": iv.base64EncodedString(),
                "ivEncoding": "base64"
            ]
        ]
        let decoded = try RuleImageData.decode(spec: steps, data: dataUriPayload)
        XCTAssertEqual(decoded, pngBytes)

        // Prefix strip without magic
        var prefixedPng = Data([0xDE, 0xAD, 0xBE])
        prefixedPng.append(pngBytes)
        let unprefixed = try RuleImageData.decode(spec: ["type": "prefix", "bytes": 3], data: prefixedPng)
        XCTAssertEqual(unprefixed, pngBytes)

        // RuleBitmapTransform tiles with 90-degree rotation on 4x4 grid (2x2 tiles of 2x2 each) + 1px remainder
        let v3Rule = try RuleDefinition(json: [
            "id": "tx_v3",
            "name": "TX V3",
            "version": 1,
            "engineApi": 3,
            "baseUrl": "https://a.example.com",
            "hosts": ["a.example.com"],
            "script": minimalScript,
            "scriptSha256": RuleDefinition.sha(Data(minimalScript.utf8))
        ])
        let txSpec = try RuleBitmapTransform.validateAndSerialize(
            rule: v3Rule,
            transform: [
                "type": "tiles",
                "cols": 2,
                "rows": 2,
                "order": [3, 2, 1, 0],
                "rotations": [90, 0, 180, 270]
            ]
        )
        XCTAssertTrue(RuleBitmapTransform.isSupported(txSpec))
        let ops = RuleBitmapTransform.plan(width: 5, height: 5, transform: txSpec)
        // 4 tile ops + right remainder + bottom remainder = 6 ops
        XCTAssertEqual(ops.count, 6)

        // Non-square 90/270-degree tile rotations clamp to 0 while preserving 180 and tile permutation
        let nonSquareOps = RuleBitmapTransform.plan(width: 6, height: 4, transform: txSpec)
        XCTAssertEqual(nonSquareOps.map(\.rotation), [0, 0, 180, 0])

        // DownloadModels.imageIdentity preserves #xx-tx= fragment for offline unscramble
        let tagged = try RuleImages.tag(
            rule: v3Rule,
            image: [
                "url": "https://a.example.com/p1.jpg",
                "transform": ["type": "stripes", "axis": "vertical", "order": [1, 0]]
            ],
            chapter: "https://a.example.com/c1",
            index: 0
        )
        let identity = DownloadModels.imageIdentity(tagged)
        XCTAssertTrue(identity.contains("#xx-tx="), "Expected #xx-tx= fragment in \(identity)")
    }

    func testRuleHttpLoopbackPostBase64PacingAndFastCancellation() throws {
        let server = try LocalTestHTTPServer()
        defer { server.stop() }

        server.route("/echo") { req in
            XCTAssertEqual(req.method, "POST")
            return LocalTestHTTPServer.Response(
                statusCode: 200,
                headers: ["Content-Type": "application/octet-stream"],
                body: Data(req.body.reversed())
            )
        }
        server.route("/slow") { _ in
            Thread.sleep(forTimeInterval: 3.0)
            return LocalTestHTTPServer.Response(statusCode: 200, body: Data("late".utf8))
        }
        server.start()

        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
        let rule = try RuleDefinition(json: [
            "id": "loop_v3_\(suffix)",
            "name": "Loopback Rule",
            "version": 1,
            "engineApi": 3,
            "baseUrl": "https://127.0.0.1",
            "hosts": ["127.0.0.1"],
            "cleartextHosts": ["127.0.0.1"],
            "minIntervalMs": 120,
            "script": minimalScript,
            "scriptSha256": RuleDefinition.sha(Data(minimalScript.utf8))
        ])

        let token1 = RuleCancelToken()
        let http = RuleHttp(rule: rule, debug: true, cancelToken: token1, timeoutMillis: 5000)
        let rawPayload = Data([0x00, 0x11, 0x22, 0xFF, 0xFE])
        let t0 = Date()
        let resp1 = try http.request([
            "url": server.url(for: "/echo"),
            "method": "POST",
            "body": rawPayload.base64EncodedString(),
            "bodyEncoding": "base64",
            "responseType": "base64"
        ])
        let resp2 = try http.request([
            "url": server.url(for: "/echo"),
            "method": "POST",
            "body": rawPayload.base64EncodedString(),
            "bodyEncoding": "base64",
            "responseType": "base64"
        ])
        let elapsedMs = Date().timeIntervalSince(t0) * 1000
        XCTAssertGreaterThanOrEqual(elapsedMs, 100, "minIntervalMs=120 must pace consecutive requests")
        let decodedResp = try XCTUnwrap(Data(base64Encoded: resp1["body"] as? String ?? ""))
        XCTAssertEqual(decodedResp, Data(rawPayload.reversed()))
        XCTAssertEqual(resp2["status"] as? Int, 200)

        // Cancellation must abort in-flight /slow socket well before 3.0s
        let cancelToken = RuleCancelToken()
        let slowHttp = RuleHttp(rule: rule, debug: true, cancelToken: cancelToken, timeoutMillis: 5000)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(120)) {
            cancelToken.cancel()
        }
        let cancelStart = Date()
        XCTAssertThrowsError(try slowHttp.request(["url": server.url(for: "/slow")])) { error in
            XCTAssertTrue(error is RuleCancelledError, "Expected RuleCancelledError, got \(error)")
        }
        let cancelElapsed = Date().timeIntervalSince(cancelStart)
        XCTAssertLessThan(cancelElapsed, 1.0, "RuleCancelToken must abort URLSessionDataTask immediately")
    }

    func testGlobalSearchDispatchPolicyPrioritizesFastDirectSources() {
        let policy = GlobalSearchDispatchPolicy()
        policy.recordSuccess(sourceID: "fast_direct", elapsedMs: 180)
        policy.recordSuccess(sourceID: "slow_direct", elapsedMs: 3600)
        policy.recordFailure(sourceID: "flaky_timeout", timedOut: true)

        let input = ["flaky_timeout", "vpn_source", "unseen_direct", "slow_direct", "fast_direct"]
        let sorted = policy.sortForDispatch(input) { id in id == "vpn_source" }
        XCTAssertEqual(sorted, ["fast_direct", "unseen_direct", "slow_direct", "vpn_source", "flaky_timeout"])
    }
}
