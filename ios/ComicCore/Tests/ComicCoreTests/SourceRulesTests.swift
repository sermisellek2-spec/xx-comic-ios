import XCTest
@testable import ComicCore

final class SourceRulesTests: XCTestCase {
    static let SCRIPT =
        "var source={latest:function(p){return {items:[{id:'book'+p,title:'作品'+p,cover:''}],hasMore:p<2};},search:function(q,p){return this.latest(p);},filters:function(){return [{key:'region',label:'分类',options:[{label:'全部',value:'all'}]}];},category:function(f,p){return this.latest(p);},detail:function(k){return {id:k,title:'作品',description:'说明'};},chapters:function(k){return [{id:'c1',title:'第1话',url:env.baseUrl+'/c1',order:0}];},chapter:function(u){return {title:'章节',images:[{url:env.baseUrl+'/1.jpg',referer:u}]};}};"

    static func json(id: String, version: Int, script: String = SCRIPT) -> [String: Any] {
        [
            "id": id,
            "name": "测试站源",
            "version": version,
            "engineApi": 1,
            "baseUrl": "https://site.example",
            "hosts": ["site.example", "*.cdn.example"],
            "script": script,
            "scriptSha256": RuleDefinition.sha(Data(script.utf8))
        ]
    }

    static func rule(id: String, version: Int, script: String = SCRIPT) throws -> RuleDefinition {
        try RuleDefinition(json: json(id: id, version: version, script: script))
    }

    static func client(_ r: RuleDefinition) -> ScriptComicSource {
        ScriptComicSource(rule: r, network: { _, _ in
            throw RuleError("测试禁止外网")
        })
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SourceRulesTests-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }

    // MARK: - RuleEngine Tests

    func testUnknownSourceHasFullContractAndStableIds() throws {
        let s = Self.client(try Self.rule(id: "brand_new_source", version: 1))
        try s.validate()

        let latest1 = try s.latest(page: 1)
        XCTAssertEqual("brand_new_source:book1", latest1.first?.comicId)
        XCTAssertTrue(s.hasMoreCategoryPage(latest1))

        let latest2 = try s.latest(page: 2)
        XCTAssertFalse(s.hasMoreCategoryPage(latest2))

        let searched = try s.search(keyword: "中文", page: 2)
        XCTAssertEqual("作品2", searched.first?.title)

        let filters = try s.filterGroups()
        XCTAssertEqual(1, filters.count)

        let categoryResult = try s.category(filters: ["region": "all"], page: 1)
        XCTAssertEqual(1, categoryResult.count)

        let detail = try s.detail(comicId: "brand_new_source:book1")
        XCTAssertEqual("brand_new_source:book1", detail.summary.comicId)

        let chapters = try s.chapters(comicId: "brand_new_source:book1")
        XCTAssertEqual("c1", chapters.first?.chapterId)

        let chapterPage = try s.chapter(url: "https://site.example/c1")
        let image = chapterPage.imageUrls.first ?? ""
        XCTAssertTrue(RuleImages.isRule(image))
        XCTAssertEqual("rule:brand_new_source:https://site.example/c1:0", RuleImages.cacheIdentity(image))

        XCTAssertThrowsError(try s.detail(comicId: "other:book1"))
        XCTAssertThrowsError(try s.chapter(url: "https://untrusted.example/c"))
    }

    func testInvalidHashEngineIdAndHostAreRejected() throws {
        var j = Self.json(id: "good", version: 1)
        j["scriptSha256"] = "0"
        XCTAssertThrowsError(try RuleDefinition(json: j))

        j["scriptSha256"] = RuleDefinition.sha(Data(Self.SCRIPT.utf8))
        j["engineApi"] = RuleDefinition.API + 1
        XCTAssertThrowsError(try RuleDefinition(json: j))

        j["engineApi"] = 1
        j["id"] = "../oops"
        XCTAssertThrowsError(try RuleDefinition(json: j))

        j["id"] = "baozimh"
        XCTAssertThrowsError(try RuleDefinition(json: j))

        j["id"] = "good"
        j["hosts"] = ["*"]
        XCTAssertThrowsError(try RuleDefinition(json: j))

        j["hosts"] = ["other.example"]
        XCTAssertThrowsError(try RuleDefinition(json: j))
    }

    func testRequiredMethodsValidatedWithoutNetwork() throws {
        XCTAssertThrowsError(try Self.client(Self.rule(id: "bad", version: 1, script: "var source={latest:function(){}};")).validate())
        XCTAssertThrowsError(try Self.client(Self.rule(id: "bad", version: 1, script: "xx.get('https://site.example');" + Self.SCRIPT)).validate())
    }

    func testNoJavaBridgeOrSharedGlobalState() throws {
        let code = Self.SCRIPT + "source.latest=function(){if(typeof java!=='undefined'||typeof Packages!=='undefined'||typeof getClass!=='undefined')throw Error('java exposed');return {items:[{id:'1',title:typeof leaked}],hasMore:false};};var leaked=1;"
        let s = Self.client(try Self.rule(id: "safe", version: 1, script: code))
        let res1 = try s.latest(page: 1)
        XCTAssertEqual("number", res1.first?.title)

        let clean = Self.client(try Self.rule(id: "clean", version: 1, script: Self.SCRIPT + "source.latest=function(){return {items:[{id:'1',title:typeof leaked}],hasMore:false};};"))
        let res2 = try clean.latest(page: 1)
        XCTAssertEqual("undefined", res2.first?.title)

        XCTAssertThrowsError(try Self.client(Self.rule(id: "safe", version: 2, script: Self.SCRIPT + "java.lang.System.exit(0);")).validate())
        XCTAssertThrowsError(try Self.client(Self.rule(id: "safe", version: 3, script: Self.SCRIPT + "__host.getClass();")).validate())
    }

    func testEndlessLoopIsInterrupted() throws {
        let loopClient = Self.client(try Self.rule(id: "loop", version: 1, script: Self.SCRIPT + "source.latest=function(){while(true){}};"))
        XCTAssertThrowsError(try loopClient.latest(page: 1))

        let healthyClient = Self.client(try Self.rule(id: "healthy", version: 1, script: Self.SCRIPT))
        XCTAssertEqual(1, try healthyClient.latest(page: 1).count)
    }

    func testHtmlAndPostGraphqlAndCryptoUseGenericHost() throws {
        let script = Self.SCRIPT + "source.latest=function(){var r=xx.request({url:env.baseUrl+'/graphql',method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({query:'{ comics { id } }'})});var t=xx.select('<a href=\"/中文\">中文</a>','a',env.baseUrl)[0];return {items:[{id:JSON.parse(r.body).id,title:t.text,cover:''}],hasMore:false};};"
        final class RequestBox: @unchecked Sendable {
            var items = [String]()
        }
        let requests = RequestBox()
        let r = try Self.rule(id: "graph", version: 1, script: script)
        let s = ScriptComicSource(rule: r) { _, m, args in
            try RuleScript.invoke(rule: r, method: m, args: args) { op, j in
                requests.items.append(j)
                guard let data = j.data(using: .utf8),
                      let req = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    throw RuleError("请求无效")
                }
                XCTAssertEqual("POST", req["method"] as? String)
                XCTAssertTrue(((req["body"] as? String) ?? "").contains("query"))
                return "{\"status\":200,\"body\":\"{\\\"id\\\":\\\"abc\\\"}\"}"
            }
        }

        let items = try s.latest(page: 1)
        XCTAssertEqual("中文", items.first?.title)
        XCTAssertEqual(1, requests.items.count)

        let encoded = try RuleCrypto.convert(["type": "base64Encode", "data": "中文"])
        let decoded = try RuleCrypto.convert(["type": "base64Decode", "data": encoded])
        XCTAssertEqual("中文", decoded)
    }

    func testDuplicateBatchIdAndMissingPagesRejected() throws {
        let p = try RuleStore.pack([Self.rule(id: "one", version: 1), Self.rule(id: "one", version: 1)])
        XCTAssertThrowsError(try RuleStore.parse(json: p))

        let noImages = Self.client(try Self.rule(id: "one", version: 1, script: Self.SCRIPT + "source.chapter=function(){return {images:[]};};"))
        XCTAssertThrowsError(try noImages.chapter(url: "https://site.example/c"))

        let noItems = Self.client(try Self.rule(id: "one", version: 1, script: Self.SCRIPT + "source.latest=function(){return {items:[]};};"))
        XCTAssertThrowsError(try noItems.latest(page: 1))
    }

    func testInstallUpdateRollbackAndRestartKeepSourceIdentity() throws {
        let dir = makeTempDir()
        var store = try RuleStore(directory: dir)
        let first = try Self.rule(id: "fresh", version: 1, script: Self.SCRIPT)
        let second = try Self.rule(id: "fresh", version: 2, script: Self.SCRIPT + "\n//fix")

        _ = try store.install([first], validator: { r in try Self.client(r).validate() })
        XCTAssertEqual(1, store.entries().count)

        let previewMsg = try store.install([first], validator: { _ in })
        XCTAssertTrue(previewMsg.contains("不变 1"))

        try store.change(ids: ["fresh"], action: "disable")
        _ = try store.install([second], validator: { _ in })
        XCTAssertFalse(store.entries()[0].enabled)

        store = try RuleStore(directory: dir)
        XCTAssertEqual(second.hash, store.entries()[0].rule.hash)
        XCTAssertEqual(first.hash, store.entries()[0].previous)

        try store.change(ids: ["fresh"], action: "rollback")
        XCTAssertEqual(first.hash, store.entries()[0].rule.hash)
        XCTAssertEqual(second.hash, store.entries()[0].previous)
        XCTAssertEqual(first.hash, try store.version(first.hash).hash)
    }

    func testValidationFailureDoesNotPartiallyActivateBatch() throws {
        let store = try RuleStore(directory: makeTempDir())
        let old = try Self.rule(id: "old", version: 1)
        _ = try store.install([old], validator: { _ in })

        let batch = [try Self.rule(id: "new_one", version: 1), try Self.rule(id: "new_two", version: 1)]
        XCTAssertThrowsError(try store.install(batch, validator: { r in
            if r.id == "new_two" { throw RuleError("invalid") }
        }))

        XCTAssertEqual(["old"], store.entries().map { $0.rule.id })
        XCTAssertEqual(1, store.entries().count)
    }

    func testCorruptedPrimaryRecoversAndDoesNotOverwriteGoodBackup() throws {
        let dir = makeTempDir()
        var store = try RuleStore(directory: dir)
        let a = try Self.rule(id: "fresh", version: 1)
        let b = try Self.rule(id: "fresh", version: 2, script: Self.SCRIPT + "//v2")
        _ = try store.install([a], validator: { _ in })
        _ = try store.install([b], validator: { _ in })

        try "{}".write(to: dir.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
        store = try RuleStore(directory: dir)
        XCTAssertEqual(a.hash, store.entries()[0].rule.hash)
        XCTAssertFalse(store.recoveryMessage.isEmpty)

        try store.change(ids: ["fresh"], action: "disable")
        let backupFile = dir.appendingPathComponent("index.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFile.path))
        let bakLen = (try? Data(contentsOf: backupFile).count) ?? 0
        XCTAssertTrue(bakLen > 2)
    }

    func testBothCorruptSnapshotsLockWritesAndPreserveOriginals() throws {
        let dir = makeTempDir()
        try "bad-primary".write(to: dir.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
        try "bad-backup".write(to: dir.appendingPathComponent("index.bak"), atomically: true, encoding: .utf8)

        let store = try RuleStore(directory: dir)
        XCTAssertThrowsError(try store.install([Self.rule(id: "valid", version: 1)], validator: { _ in }))
        let content = try String(contentsOf: dir.appendingPathComponent("index.json"), encoding: .utf8)
        XCTAssertEqual("bad-primary", content)
    }

    func testBatchDeleteRemovesEntriesAndImportRestoresRuleData() throws {
        let dir = makeTempDir()
        let store = try RuleStore(directory: dir)
        let rules = [try Self.rule(id: "first", version: 1), try Self.rule(id: "second", version: 1)]
        _ = try store.install(rules, validator: { _ in })
        try store.change(ids: ["first", "second", "gmh"], action: "delete")

        XCTAssertTrue(store.entries().isEmpty)
        XCTAssertTrue(store.hidden().contains("gmh"))
        XCTAssertTrue(store.hidden().contains("first"))

        let restored = try RuleStore(directory: dir)
        XCTAssertTrue(restored.entries().isEmpty)
        _ = try restored.install(rules, validator: { _ in })
        XCTAssertEqual(2, restored.entries().count)
        XCTAssertFalse(restored.hidden().contains("first"))
        XCTAssertFalse(restored.hidden().contains("second"))
        XCTAssertTrue(restored.hidden().contains("gmh"))

        let pack = try RuleStore.pack(rules)
        let parsed = try RuleStore.parse(json: pack)
        XCTAssertEqual(rules[1].hash, parsed[1].hash)
        XCTAssertEqual(rules[0].hash, try store.version(rules[0].hash).hash)
    }

    func testDowngradeAndSameVersionDifferentContentCannotReplace() throws {
        let store = try RuleStore(directory: makeTempDir())
        let r = try Self.rule(id: "one", version: 2)
        _ = try store.install([r], validator: { _ in })

        XCTAssertThrowsError(try store.install([Self.rule(id: "one", version: 1)], validator: { _ in }))
        XCTAssertThrowsError(try store.install([Self.rule(id: "one", version: 2, script: Self.SCRIPT + "//changed")], validator: { _ in }))
        XCTAssertEqual(r.hash, store.entries()[0].rule.hash)
    }

    func testSubscriptionsAreIdempotentAndIndependentFromSources() throws {
        let store = try RuleStore(directory: makeTempDir())
        _ = try store.install([Self.rule(id: "one", version: 1)], validator: { _ in })
        try store.repository("https://rules.example/index.json", add: true)
        try store.repository("https://rules.example/index.json", add: true)
        XCTAssertEqual(1, store.repositories().count)

        try store.repository("https://rules.example/index.json", add: false)
        XCTAssertTrue(store.repositories().isEmpty)
        XCTAssertEqual(1, store.entries().count)

        XCTAssertThrowsError(try store.repository("http://insecure.example/index", add: true))
    }

    func testWildcardHostsAreBoundedAndHeadersRejectCredentialsInjection() throws {
        let r = try Self.rule(id: "one", version: 1)
        XCTAssertTrue(r.allows("img.cdn.example"))
        XCTAssertFalse(r.allows("cdn.example.evil"))
        XCTAssertFalse(r.allows("evilsite.example"))

        let http = RuleHttp(rule: r, debug: true)
        XCTAssertThrowsError(try http.checkUrl("https://evil.example/"))
        XCTAssertThrowsError(try http.checkUrl("file:///etc/passwd"))
        XCTAssertThrowsError(try RuleHttp.checkHeader("X-Test", "okay\r\nAuthorization: oops"))
        XCTAssertThrowsError(try RuleHttp.checkHeader("Cookie", "secret"))
    }

    func testRefreshCapabilityAndDecodeDescriptorsValidated() throws {
        var definition = Self.json(id: "signed", version: 1, script: Self.SCRIPT)
        definition["imageRefresh"] = true
        let noHook = try RuleDefinition(json: definition)
        XCTAssertThrowsError(try Self.client(noHook).validate())

        let script = Self.SCRIPT + "source.image=function(d,force){d.url=env.baseUrl+(force?'/fresh.jpg':'/old.jpg');return d;};"
        definition = Self.json(id: "signed", version: 1, script: script)
        definition["imageRefresh"] = true
        let source = Self.client(try RuleDefinition(json: definition))
        try source.validate()

        let imgResult = try source.image(["url": "https://site.example/old.jpg"], force: true)
        XCTAssertTrue(((imgResult["url"] as? String) ?? "").hasSuffix("/fresh.jpg"))

        let r = try Self.rule(id: "one", version: 1)
        XCTAssertThrowsError(try RuleImages.tag(rule: r, image: ["url": "https://evil.example/a.jpg"], chapter: "c", index: 0))
        XCTAssertThrowsError(try RuleImages.tag(rule: r, image: ["url": "https://site.example/a.jpg", "decode": ["type": "unknown"]], chapter: "c", index: 0))
    }

    func testRepositoryResolvesRelativePackagesAndRejectsWrongHashes() throws {
        let packed = try RuleStore.pack([Self.rule(id: "remote", version: 1)])
        let packData = try JSONSerialization.data(withJSONObject: packed, options: [])
        let body = String(decoding: packData, as: UTF8.self)

        let index: [String: Any] = [
            "schema": "xx-comic.rule-repository",
            "version": 1,
            "packages": [
                [
                    "url": "site.json",
                    "sha256": RuleDefinition.sha(packData)
                ]
            ]
        ]

        let parsed = try RuleRepository.read(root: index, origin: "https://rules.example/repo/index.json") { url in
            XCTAssertEqual("https://rules.example/repo/site.json", url)
            return body
        }
        XCTAssertEqual("remote", parsed[0].id)

        XCTAssertThrowsError(try RuleRepository.read(root: index, origin: "https://rules.example/repo/index.json", fetcher: { _ in body + " " }))
    }

    func testInstallBundleRestoresNativeVisibilityAndKeepsDisabledStateAtomically() throws {
        let store = try RuleStore(directory: makeTempDir())
        try store.change(ids: ["gmh", "one"], action: "delete")
        let r = try Self.rule(id: "one", version: 1)

        _ = try store.install([r], validator: { _ in }, restoreNative: ["gmh"], subscription: "https://rules.example/index.json", states: ["one": false])
        XCTAssertFalse(store.hidden().contains("gmh"))
        XCTAssertFalse(store.hidden().contains("one"))
        XCTAssertFalse(store.entries()[0].enabled)
        XCTAssertEqual(1, store.repositories().count)

        XCTAssertThrowsError(try store.install([Self.rule(id: "two", version: 1)], validator: { _ in throw RuleError("bad script") }, restoreNative: ["another"], subscription: "https://other.example/index.json", states: [:]))
        XCTAssertEqual(1, store.entries().count)
        XCTAssertEqual(1, store.repositories().count)
    }

    func testBase64WorksForAllByteValuesAndUrlAlphabet() throws {
        var all = [UInt8]()
        for n in 0...256 { all.append(UInt8(n & 0xFF)) }
        for len in 0...all.count {
            let part = Data(all.prefix(len))
            let standard = RuleBase64.encode(part, false)
            XCTAssertEqual(part.base64EncodedString(), standard)
            XCTAssertEqual(part, try RuleBase64.decode(standard))

            let url = RuleBase64.encode(part, true)
            XCTAssertEqual(part, try RuleBase64.decode(url))
            XCTAssertFalse(url.contains("="))
        }
    }

    func testImportedTextCannotFloodMainThreadViews() throws {
        let hugeTitle = Self.client(try Self.rule(id: "huge", version: 1, script: Self.SCRIPT + "source.latest=function(){return {items:[{id:'a',title:new Array(10000).join('A')}],hasMore:false};};"))
        XCTAssertThrowsError(try hugeTitle.latest(page: 1))

        let hugeDetail = Self.client(try Self.rule(id: "huge", version: 1, script: Self.SCRIPT + "source.detail=function(k){return {id:k,title:'ok',description:new Array(50000).join('A')};};"))
        XCTAssertThrowsError(try hugeDetail.detail(comicId: "huge:a"))

        let hugeChapters = Self.client(try Self.rule(id: "huge", version: 1, script: Self.SCRIPT + "source.chapters=function(){return [{id:'c',url:env.baseUrl+'/c',title:new Array(50000).join('A')}];};"))
        XCTAssertThrowsError(try hugeChapters.chapters(comicId: "huge:a"))

        let hugeUrl = "https://site.example/" + String(repeating: "a", count: 9000)
        XCTAssertThrowsError(try RuleDefinition.validateHttp(hugeUrl))

        let r = try Self.rule(id: "huge", version: 1)
        let hugeExtra = String(repeating: "a", count: 20000)
        XCTAssertThrowsError(try RuleImages.tag(rule: r, image: ["url": "https://site.example/1.png", "extra": hugeExtra], chapter: "c", index: 0))
    }

    func testJsonEscapingDoesNotMakeSavedRuleUnreadable() throws {
        let comment = String(repeating: "\u{0001}", count: 270000)
        let r = try Self.rule(id: "escaped", version: 1, script: Self.SCRIPT + "\n//" + comment)
        let store = try RuleStore(directory: makeTempDir())
        _ = try store.install([r], validator: { x in try Self.client(x).validate() })
        XCTAssertEqual(r.hash, try store.version(r.hash).hash)

        var invalid = Self.json(id: "host", version: 1)
        invalid["hosts"] = [String(repeating: "a", count: 300) + ".example"]
        XCTAssertThrowsError(try RuleDefinition(json: invalid))
    }

    // MARK: - RuleBundle Tests

    func testOldApiIdentityAndNewCapabilityDeclarationsRemainDistinct() throws {
        let legacyJson = Self.json(id: "legacy", version: 2)
        let old = try RuleDefinition(json: legacyJson)
        XCTAssertEqual(1, old.engineApi)
        XCTAssertEqual(old.hash, try RuleDefinition(json: old.toDictionary()).hash)

        var currentJson = legacyJson
        currentJson["engineApi"] = 2
        currentJson["supportsSearch"] = false
        let current = try RuleDefinition(json: currentJson)
        XCTAssertNotEqual(old.hash, current.hash)
        XCTAssertFalse(Self.client(current).supportsSearch)
        XCTAssertFalse(try RuleDefinition(json: current.toDictionary()).supportsSearch)
    }

    func testPrefixedCipherAndMetadataImagesUseGenericDescriptions() throws {
        var image = [UInt8](repeating: 0, count: 100)
        image[0] = 137
        image[1] = UInt8(ascii: "P")
        image[2] = UInt8(ascii: "N")
        image[3] = UInt8(ascii: "G")

        let iv = [UInt8](repeating: 0, count: 16)
        let key = Array("0123456789abcdef".utf8)
        let encrypted = try SourceAES.encrypt(Data(image), key: Data(key), iv: Data(iv))

        var bytes = Data(iv)
        bytes.append(encrypted)

        let format: [String: Any] = [
            "type": "aesCbc",
            "key": RuleBase64.encode(Data(key), false),
            "ivPrefix": true,
            "passIfPlain": true
        ]
        var rJson = Self.json(id: "new_image", version: 1)
        rJson["engineApi"] = 2
        let r = try RuleDefinition(json: rJson)
        try RuleImageData.validate(rule: r, descriptor: format)

        let decodedEnc = try RuleImageData.decode(descriptor: format, data: bytes)
        XCTAssertEqual(Data(image), decodedEnc)

        let decodedPlain = try RuleImageData.decode(descriptor: format, data: Data(image))
        XCTAssertEqual(Data(image), decodedPlain)

        let header = Data("metadata-marker".utf8)
        var prefixBytes = header
        prefixBytes.append(Data(repeating: 0, count: 80 - header.count))
        prefixBytes.append(Data(image))

        let prefix: [String: Any] = [
            "type": "prefix",
            "bytes": 80,
            "magic": RuleBase64.encode(header, false)
        ]
        try RuleImageData.validate(rule: r, descriptor: prefix)
        let decodedPrefix = try RuleImageData.decode(descriptor: prefix, data: prefixBytes)
        XCTAssertEqual(Data(image), decodedPrefix)
    }

    func testAnonymousCookiesCannotCrossRuleOrHostBoundaries() throws {
        var aJson = Self.json(id: "cookies_one", version: 1)
        aJson["engineApi"] = 2
        let a = try RuleDefinition(json: aJson)

        var bJson = Self.json(id: "cookies_two", version: 1)
        bJson["engineApi"] = 2
        let b = try RuleDefinition(json: bJson)

        RuleSessions.receive(rule: a, url: "https://site.example/", fresh: ["csrf": "test-only"])
        XCTAssertEqual("test-only", RuleSessions.get(rule: a, url: "https://site.example/a")["csrf"])
        XCTAssertTrue(RuleSessions.get(rule: b, url: "https://site.example/").isEmpty)
        XCTAssertTrue(RuleSessions.get(rule: a, url: "https://other.cdn.example/").isEmpty)

        var a2Json = Self.json(id: "cookies_one", version: 2)
        a2Json["engineApi"] = 2
        let a2 = try RuleDefinition(json: a2Json)
        XCTAssertTrue(RuleSessions.get(rule: a2, url: "https://site.example/").isEmpty)
    }

    // MARK: - RuleSubscriptionUpdate Tests

    func testFirstInstallRecordsOnlyDefaultAddress() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        try s.ensureDefaultRepository()
        XCTAssertTrue(s.entries().isEmpty)
        XCTAssertTrue(s.hidden().isEmpty)
        XCTAssertEqual([RuleRepository.DEFAULT_URL], s.repositories())

        let reopened = try RuleStore(directory: dir)
        try reopened.ensureDefaultRepository()
        XCTAssertTrue(reopened.entries().isEmpty)
        XCTAssertEqual(s.repositories(), reopened.repositories())
    }

    func testRemovedDefaultIsNotAddedAgainOnRestart() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        try s.ensureDefaultRepository()
        try s.repository(RuleRepository.DEFAULT_URL, add: false)

        let reopened = try RuleStore(directory: dir)
        try reopened.ensureDefaultRepository()
        XCTAssertTrue(reopened.repositories().isEmpty)
    }

    func testUpgradePreservesRulesRepositoriesAndSwitches() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        _ = try s.install([Self.rule(id: "disabled", version: 3), Self.rule(id: "removed", version: 2)], validator: { _ in })
        try s.change(ids: ["disabled"], action: "disable")
        try s.change(ids: ["removed"], action: "delete")
        try s.repository("https://custom.example/index.json", add: true)

        let upgraded = try RuleStore(directory: dir)
        try upgraded.ensureDefaultRepository()
        XCTAssertEqual(1, upgraded.entries().count)
        XCTAssertFalse(upgraded.entries().first(where: { $0.rule.id == "disabled" })?.enabled ?? true)
        XCTAssertTrue(upgraded.hidden().contains("removed"))
        XCTAssertEqual(["https://custom.example/index.json", RuleRepository.DEFAULT_URL], upgraded.repositories())
    }

    func testOldRemovedEntriesDisappearWithoutLosingNativeFallbackMask() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        _ = try s.install([Self.rule(id: "legacy", version: 1)], validator: { _ in })

        let indexPath = dir.appendingPathComponent("index.json")
        let data = try Data(contentsOf: indexPath)
        var root = (try JSONSerialization.jsonObject(with: data)) as! [String: Any]
        var entries = root["entries"] as! [[String: Any]]
        entries[0]["removed"] = true
        root["entries"] = entries
        root["hidden"] = ["legacy"]
        let rewritten = try JSONSerialization.data(withJSONObject: root, options: [])
        try rewritten.write(to: indexPath)

        let reopened = try RuleStore(directory: dir)
        XCTAssertTrue(reopened.entries().isEmpty)
        XCTAssertTrue(reopened.hidden().contains("legacy"))

        _ = try reopened.install([Self.rule(id: "legacy", version: 1)], validator: { _ in })
        let reopenedAgain = try RuleStore(directory: dir)
        XCTAssertEqual(1, reopenedAgain.entries().count)
        XCTAssertFalse(reopenedAgain.hidden().contains("legacy"))
    }

    func testMigrationDoesNotEvictAnyOfSixteenCustomSubscriptions() throws {
        let s = try RuleStore(directory: makeTempDir())
        for n in 0..<16 {
            try s.repository("https://custom.example/\(n).json", add: true)
        }
        let before = s.repositories()
        try s.ensureDefaultRepository()
        XCTAssertEqual(before, s.repositories())
    }

    func testCorruptIndexIsPreservedAndMigrationCannotOverwriteIt() throws {
        let dir = makeTempDir()
        let f = dir.appendingPathComponent("index.json")
        try "broken".write(to: f, atomically: true, encoding: .utf8)
        let s = try RuleStore(directory: dir)
        XCTAssertThrowsError(try s.ensureDefaultRepository())
        let content = try String(contentsOf: f, encoding: .utf8)
        XCTAssertEqual("broken", content)
    }

    func testBackupRecoveryKeepsEntriesWhenDefaultIsAdded() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        _ = try s.install([Self.rule(id: "kept", version: 1)], validator: { _ in })
        try s.repository("https://custom.example/index.json", add: true)

        try "broken".write(to: dir.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
        let recovered = try RuleStore(directory: dir)
        try recovered.ensureDefaultRepository()
        XCTAssertEqual("kept", recovered.entries()[0].rule.id)
        XCTAssertEqual(1, try RuleStore(directory: dir).entries().count)
    }

    func testRefreshPreservesDisabledSourceAndCanReinstallDeletedSource() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        _ = try s.install([Self.rule(id: "off", version: 1), Self.rule(id: "gone", version: 5), Self.rule(id: "local_only", version: 2)], validator: { _ in })
        try s.change(ids: ["off"], action: "disable")
        try s.change(ids: ["gone"], action: "delete")

        let old = s.entries().first(where: { $0.rule.id == "off" })!.rule.hash
        let message = try s.updateSubscriptions([Self.rule(id: "off", version: 2), Self.rule(id: "gone", version: 1), Self.rule(id: "new", version: 1)])
        XCTAssertTrue(message.contains("新增 2"))
        XCTAssertFalse(s.entries().first(where: { $0.rule.id == "off" })!.enabled)
        XCTAssertEqual(old, s.entries().first(where: { $0.rule.id == "off" })!.previous)
        XCTAssertEqual(old, try s.version(old).hash)
        XCTAssertEqual(1, s.entries().first(where: { $0.rule.id == "gone" })!.rule.version)
        XCTAssertFalse(s.hidden().contains("gone"))
        XCTAssertTrue(s.entries().first(where: { $0.rule.id == "new" })!.enabled)

        let ids = try RuleStore(directory: dir).entries().map { $0.rule.id }
        XCTAssertEqual(["off", "local_only", "gone", "new"], ids)
    }

    func testUnchangedRefreshDoesNotRewriteIndexOrLoseRollback() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        _ = try s.install([Self.rule(id: "aa", version: 1)], validator: { _ in })
        _ = try s.install([Self.rule(id: "aa", version: 2)], validator: { _ in })
        let before = try Data(contentsOf: dir.appendingPathComponent("index.json"))
        let previous = s.entries().first(where: { $0.rule.id == "aa" })!.previous

        let msg = try s.updateSubscriptions([Self.rule(id: "aa", version: 2)])
        XCTAssertTrue(msg.contains("不变 1"))
        let after = try Data(contentsOf: dir.appendingPathComponent("index.json"))
        XCTAssertEqual(before, after)
        XCTAssertEqual(previous, s.entries().first(where: { $0.rule.id == "aa" })!.previous)
    }

    func testLowerVersionRejectsWholeBatch() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        _ = try s.install([Self.rule(id: "old", version: 5)], validator: { _ in })
        XCTAssertThrowsError(try s.updateSubscriptions([Self.rule(id: "new", version: 1), Self.rule(id: "old", version: 4)]))
        XCTAssertEqual(1, s.entries().count)
    }

    func testSameVersionChangedContentRejectsWholeBatch() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        _ = try s.install([Self.rule(id: "aa", version: 1)], validator: { _ in })
        let changed = try Self.rule(id: "aa", version: 1, script: Self.SCRIPT + "\n//changed")
        XCTAssertThrowsError(try s.updateSubscriptions([changed]))
    }

    func testOldAppMetadataLossCanBeRepairedWithoutChangingTheScript() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        let old = try Self.rule(id: "vpn_site", version: 5)
        _ = try s.install([old], validator: { _ in })

        var markedJson = old.toDictionary()
        markedJson["requiresVpn"] = true
        let marked = try RuleDefinition(json: markedJson)
        XCTAssertEqual(old.hash, marked.coreHash)
        XCTAssertNotEqual(old.hash, marked.hash)

        let msg = try s.updateSubscriptions([marked])
        XCTAssertTrue(msg.contains("更新 1"))

        let updated = try RuleStore(directory: dir).entries().first(where: { $0.rule.id == "vpn_site" })!
        XCTAssertTrue(updated.rule.requiresVpn)
        XCTAssertEqual(old.hash, updated.previous)
        XCTAssertEqual(old.scriptSha256, updated.rule.scriptSha256)
    }

    func testDuplicateIdsCannotPartiallyActivate() throws {
        let dir = makeTempDir()
        let s = try RuleStore(directory: dir)
        try s.ensureDefaultRepository()
        XCTAssertThrowsError(try s.updateSubscriptions([Self.rule(id: "aa", version: 1), Self.rule(id: "aa", version: 1)]))
    }

    private final class MockRepo {
        var bodies = [String: String]()
        var urls = [String]()

        func add(url: String, rules: [RuleDefinition]) throws {
            let packed = try RuleStore.pack(rules)
            let packData = try JSONSerialization.data(withJSONObject: packed, options: [])
            let packStr = String(decoding: packData, as: UTF8.self)

            let index: [String: Any] = [
                "schema": "xx-comic.rule-repository",
                "version": 1,
                "packages": [
                    [
                        "url": "pack.json",
                        "sha256": RuleDefinition.sha(packData)
                    ]
                ]
            ]
            let indexData = try JSONSerialization.data(withJSONObject: index, options: [])
            bodies[url] = String(decoding: indexData, as: UTF8.self)

            let resolvedUrl = URL(string: "pack.json", relativeTo: URL(string: url))!.absoluteString
            bodies[resolvedUrl] = packStr
            urls.append(url)
        }

        func fetch(_ url: String) throws -> String {
            guard let b = bodies[url] else { throw RuleError("网络失败") }
            return b
        }
    }

    func testAllRepositoriesMergeIdenticalIdsAndValidateOnce() throws {
        let repo = MockRepo()
        try repo.add(url: "https://one.example/index.json", rules: [Self.rule(id: "aa", version: 1)])
        try repo.add(url: "https://two.example/index.json", rules: [Self.rule(id: "aa", version: 1), Self.rule(id: "bb", version: 1)])

        var checked = [String]()
        let rules = try RuleSubscriptionUpdate.prepare(urls: repo.urls, validator: { r in checked.append(r.id) }, fetcher: repo.fetch)
        XCTAssertEqual(["aa", "bb"], checked)
        XCTAssertEqual(2, rules.count)
    }

    func testConflictingRepositoriesDoNotUseLastWriterWins() throws {
        let repo = MockRepo()
        try repo.add(url: "https://one.example/index.json", rules: [Self.rule(id: "aa", version: 1)])
        try repo.add(url: "https://two.example/index.json", rules: [Self.rule(id: "aa", version: 2)])
        XCTAssertThrowsError(try RuleSubscriptionUpdate.prepare(urls: repo.urls, validator: { _ in }, fetcher: repo.fetch))
    }

    func testCorruptPackageFailsBeforeScriptValidation() throws {
        let repo = MockRepo()
        try repo.add(url: "https://one.example/index.json", rules: [Self.rule(id: "aa", version: 1)])
        repo.bodies["https://one.example/pack.json"] = "{}"
        XCTAssertThrowsError(try RuleSubscriptionUpdate.prepare(urls: repo.urls, validator: { _ in
            XCTFail("哈希失败不能执行脚本")
        }, fetcher: repo.fetch))
    }

    func testOneUnavailableRepositoryPreventsCommitOfAnyOther() throws {
        let repo = MockRepo()
        try repo.add(url: "https://one.example/index.json", rules: [Self.rule(id: "aa", version: 1)])
        repo.urls.append("https://down.example/index.json")

        let s = try RuleStore(directory: makeTempDir())
        try s.ensureDefaultRepository()
        XCTAssertThrowsError(try s.updateSubscriptions(RuleSubscriptionUpdate.prepare(urls: repo.urls, validator: { _ in }, fetcher: repo.fetch)))
        XCTAssertTrue(s.entries().isEmpty)
    }

    func testInvalidScriptPreventsAnyActivation() throws {
        let repo = MockRepo()
        try repo.add(url: "https://one.example/index.json", rules: [Self.rule(id: "aa", version: 1)])
        let s = try RuleStore(directory: makeTempDir())
        XCTAssertThrowsError(try s.updateSubscriptions(RuleSubscriptionUpdate.prepare(urls: repo.urls, validator: { _ in
            throw RuleError("契约错误")
        }, fetcher: repo.fetch)))
        XCTAssertTrue(s.entries().isEmpty)
    }

    func testEmptySubscriptionsAndInsecureAddressAreExplicitErrors() throws {
        XCTAssertThrowsError(try RuleSubscriptionUpdate.prepare(urls: [], validator: { _ in }, fetcher: { _ in "" }))
        XCTAssertThrowsError(try RuleSubscriptionUpdate.prepare(urls: ["http://bad.example/index.json"], validator: { _ in }, fetcher: { _ in "" }))
    }

    // MARK: - RuleMigration Tests

    func testDependentFilterChoicesUseCachedMetadataAndKeepNativeValues() throws {
        let script = """
        var source = {
            latest: function(p) { return { items: [], hasMore: false }; },
            search: function(q, p) { return { items: [], hasMore: false }; },
            category: function(f, p) { return this.latest(p); },
            detail: function(k) { return { id: k, title: '作品' }; },
            chapters: function(k) { return []; },
            chapter: function(u) { return { title: '章节', images: [] }; },
            filters: function() {
                return [
                    {key: 'type', label: '频道', options: [
                        {label: '全部', value: 'all'},
                        {label: '女生', value: 'girl'},
                        {label: '男生', value: 'boy'}
                    ]},
                    {key: 'tag', label: '题材', dependsOn: 'type', allValue: 'all', options: [
                        {label: '全部', value: 'all'},
                        {label: '恋爱', value: 'girl:17', parent: 'girl', selectedLabel: '恋爱'},
                        {label: '热血', value: 'boy:1', parent: 'boy', selectedLabel: '热血'}
                    ]}
                ];
            }
        };
        """
        var rJson = Self.json(id: "comic51", version: 1, script: script)
        rJson["engineApi"] = 2
        let r = try RuleDefinition(json: rJson)
        let s = ScriptComicSource(rule: r, network: { _, _ in
            throw RuleError("筛选配置不应访问网站")
        })

        let all = try s.filterGroups()
        let selected = s.filterGroupsForSelection(["type": "girl"])

        let allTags = all.first(where: { $0.key == "tag" })!
        let tags = selected.first(where: { $0.key == "tag" })!

        XCTAssertTrue(allTags.options.count > tags.options.count)
        XCTAssertEqual("all", tags.options[0].value)
        XCTAssertEqual("girl:17", tags.options[1].value)
        XCTAssertEqual("恋爱", tags.options[1].label)
        XCTAssertTrue(tags.options.allSatisfy { $0.value == "all" || $0.value.hasPrefix("girl:") })
        XCTAssertEqual(["tag"], s.dependentFilterKeys("type"))
    }

    func testFirstNativeMigrationKeepsDisabledStateAndLaterRuleUpdatesKeepTheirOwnState() throws {
        var rJson = Self.json(id: "mh160", version: 1)
        rJson["replacesNative"] = true
        let r = try RuleDefinition(json: rJson)

        var nativeItems = [String: [String: Any]]()
        nativeItems[r.id] = ["enabled": false]

        let initialStates = RuleImportStates.initial(rules: [r], installed: [], nativeItems: nativeItems)
        XCTAssertEqual(false, initialStates[r.id])

        let installed = RuleStore.Entry(rule: r, previous: "", enabled: true, removed: false)
        let laterStates = RuleImportStates.initial(rules: [r], installed: [installed], nativeItems: nativeItems)
        XCTAssertTrue(laterStates.isEmpty)

        let removedEntry = RuleStore.Entry(rule: r, previous: "", enabled: true, removed: true)
        let reimportStates = RuleImportStates.initial(rules: [r], installed: [removedEntry], nativeItems: nativeItems)
        XCTAssertEqual(false, reimportStates[r.id])
    }

    func testGenericTransformsAndBudgetsPreserveBoundaries() throws {
        let b0 = try RuleBitmapTransform.bounds(height: 10, count: 3)[0]
        XCTAssertEqual([6, 10, 0, 4], b0)
        let b2 = try RuleBitmapTransform.bounds(height: 10, count: 3)[2]
        XCTAssertEqual([0, 3, 7, 10], b2)

        var j = Self.json(id: "quota", version: 1)
        j["engineApi"] = 2
        j["requestLimit"] = 513
        XCTAssertThrowsError(try RuleDefinition(json: j))

        j["requestLimit"] = 40
        j["timeoutSeconds"] = 241
        XCTAssertThrowsError(try RuleDefinition(json: j))

        j["timeoutSeconds"] = 90
        j["engineApi"] = 1
        j["browserSession"] = true
        XCTAssertThrowsError(try RuleDefinition(json: j))

        var jmJson = Self.json(id: "jmcomic", version: 1)
        jmJson["browserSession"] = true
        jmJson["engineApi"] = 2
        let jmRule = try RuleDefinition(json: jmJson)
        XCTAssertTrue(jmRule.browserSession)
        XCTAssertEqual(jmRule.hash, try RuleDefinition(json: jmRule.toDictionary()).hash)

        let d: [String: Any] = [
            "url": jmRule.baseUrl + "/image.jpg",
            "transform": ["type": "reverseBands", "bands": 10]
        ]
        let tagged = try RuleImages.tag(rule: jmRule, image: d, chapter: jmRule.baseUrl + "/photo/123", index: 0)
        XCTAssertEqual("bands:10", try RuleImages.transformation(tagged))

        var badD = d
        badD["transform"] = ["type": "reverseBands", "bands": 101]
        XCTAssertThrowsError(try RuleImages.tag(rule: jmRule, image: badD, chapter: jmRule.baseUrl + "/photo/123", index: 0))
    }

    func testIntegerOverflowAndTextConversionsMatchWireProtocols() throws {
        let a: Int64 = 3917647857211, b: Int64 = 104729
        let mulResult = try RuleCrypto.convert([
            "type": "int64",
            "op": "mul",
            "a": String(a),
            "b": String(b)
        ])
        XCTAssertEqual(String(a &* b), mulResult)

        let pinyinResult = try RuleCrypto.convert(["type": "pinyin", "data": "美丽新世界"])
        XCTAssertEqual("meilixinshijie", pinyinResult)

        let urlEncodeResult = try RuleCrypto.convert([
            "type": "urlEncode",
            "charset": "GBK",
            "data": "漫画 A"
        ])
        XCTAssertEqual("%C2%FE%BB%AD+A", urlEncodeResult)

        XCTAssertThrowsError(try RuleCrypto.convert([
            "type": "int64",
            "op": "mod",
            "a": "1",
            "b": "0"
        ]))
    }

    final class MockBrowserSession: RuleBrowserSession {
        let response: String
        init(response: String) { self.response = response }
        func fetch(_ url: String) throws -> String { response }
    }

    func testBrowserTransportIsDeclaredAndCannotReadAnotherOrigin() throws {
        var rJson = Self.json(id: "mh18", version: 1)
        rJson["browserSession"] = true
        rJson["engineApi"] = 2
        let r = try RuleDefinition(json: rJson)

        let session = MockBrowserSession(response: "public fixture")
        try RuleWebSessions.attach(r.baseUrl, session)
        defer {
            try? RuleWebSessions.detach(r.baseUrl, session)
        }

        let fetched = try RuleWebSessions.fetch(rule: r, url: r.baseUrl + "/manga")
        XCTAssertEqual("public fixture", fetched)

        XCTAssertThrowsError(try RuleWebSessions.fetch(rule: r, url: "https://unrelated.example/manga"))

        let gmhRule = try Self.rule(id: "gmh", version: 1)
        XCTAssertThrowsError(try RuleWebSessions.fetch(rule: gmhRule, url: r.baseUrl + "/manga"))
    }

    func testMissingRuleSourcePlaceholderBehavior() async throws {
        let missing = MissingRuleSource(id: "removed_src")
        XCTAssertEqual("removed_src", missing.id)
        XCTAssertEqual("未安装站源", missing.name)
        XCTAssertFalse(missing.supportsSearch)
        let healthy = await missing.healthCheck()
        XCTAssertFalse(healthy)

        do {
            _ = try await missing.latest(page: 1)
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("此站源已移除"))
        }

        do {
            _ = try await missing.search(keyword: "test", page: 1)
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("此站源已移除"))
        }

        do {
            _ = try await missing.detail(comicId: "removed_src:123")
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("此站源已移除"))
        }

        do {
            _ = try await missing.chapters(comicId: "removed_src:123")
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("此站源已移除"))
        }

        do {
            _ = try await missing.chapter(url: "https://site.example/c1")
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("此站源已移除"))
        }

        do {
            _ = try await missing.filterGroups()
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("此站源已移除"))
        }

        do {
            _ = try await missing.category(filters: [:], page: 1)
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("此站源已移除"))
        }
    }
}
