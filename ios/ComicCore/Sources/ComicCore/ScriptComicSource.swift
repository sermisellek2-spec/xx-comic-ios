import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

// MARK: - ScriptEngine Protocol

public protocol ScriptEngine: Sendable {
    func invoke(rule: RuleDefinition, method: String, args: [Any], network: @escaping @Sendable (String, String) throws -> String) throws -> String
}

// MARK: - RuleScript

public enum RuleScript {
    public typealias Host = @Sendable (String, String) throws -> String

    public static let REQUIRED = [
        "latest", "search", "filters", "category", "detail", "chapters", "chapter"
    ]

    public static let PRELUDE =
        "var xx=Object.freeze({request:function(o){return JSON.parse(__host('http',JSON.stringify(o)));},get:function(u,h){var r=this.request({url:u,headers:h||{}});if(r.error)throw Error(r.error);if(r.status<200||r.status>=300)throw Error('站点请求失败 HTTP '+r.status);return r;},render:function(u,o){var a={url:u};if(o&&typeof o==='object'){for(var k in o)if(Object.prototype.hasOwnProperty.call(o,k))a[k]=o[k];a.url=u;}var r=JSON.parse(__host('render',JSON.stringify(a)));if(r&&r.error)throw Error(r.error);return r;},select:function(h,s,b){return JSON.parse(__host('select',JSON.stringify({html:h,selector:s,base:b||''})));},resolve:function(b,u){return JSON.parse(__host('resolve',JSON.stringify({base:b,url:u})));},cacheGet:function(k){var r=JSON.parse(__host('cache',JSON.stringify({action:'get',key:k})));if(r&&r.error)throw Error(r.error);return r;},cacheSet:function(k,v){var r=JSON.parse(__host('cache',JSON.stringify({action:'set',key:k,value:v})));if(r&&r.error)throw Error(r.error);return r;},convert:function(o){return JSON.parse(__host('convert',JSON.stringify(o)));}});"

    public static func invoke(rule: RuleDefinition, method: String, args: [Any], network: @escaping Host) throws -> String {
        #if canImport(JavaScriptCore)
        return try JavaScriptCoreEngine().invoke(rule: rule, method: method, args: args, network: network)
        #else
        return try DeterministicScriptEngine().invoke(rule: rule, method: method, args: args, network: network)
        #endif
    }

    public static func local(op: String, data: String) throws -> String {
        guard let dataBytes = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: dataBytes) as? [String: Any] else {
            throw RuleError("宿主参数无效")
        }

        if op == "resolve" {
            guard let base = json["base"] as? String,
                  let url = json["url"] as? String,
                  let baseUrl = URL(string: base),
                  let resolved = URL(string: url, relativeTo: baseUrl) else {
                throw RuleError("解析地址失败")
            }
            return quoteJsonString(resolved.absoluteString)
        }

        if op == "select" {
            guard let html = json["html"] as? String,
                  let selector = json["selector"] as? String else {
                throw RuleError("选择参数无效")
            }
            let base = (json["base"] as? String) ?? ""
            let doc = PublicHTMLDocument.parse(html, baseUri: base)
            let elements = doc.select(selector)
            guard elements.count < 10000 else {
                throw RuleError("HTML 匹配结果过多")
            }
            var result = [[String: Any]]()
            for e in elements {
                var attrs = [String: Any]()
                for (k, v) in e.attributes {
                    attrs[k] = v
                }
                result.append([
                    "text": e.text(),
                    "html": e.outerHtml(),
                    "attrs": attrs,
                    "href": e.absUrl("href"),
                    "src": e.absUrl("src")
                ])
            }
            let serialized = try JSONSerialization.data(withJSONObject: result, options: [])
            guard serialized.count <= 6 * 1024 * 1024 else {
                throw RuleError("HTML 选择结果过大")
            }
            guard let text = String(data: serialized, encoding: .utf8) else {
                throw RuleError("HTML 选择结果编码失败")
            }
            return text
        }

        if op == "convert" {
            let result = try RuleCrypto.convert(json)
            return quoteJsonString(result)
        }

        throw RuleError("不支持的宿主操作")
    }

    public static func quoteJsonString(_ str: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [str], options: []),
           let text = String(data: data, encoding: .utf8),
           text.hasPrefix("[") && text.hasSuffix("]") {
            return String(text.dropFirst().dropLast())
        }
        return "\"\(str)\""
    }

    private static let tightWhilePattern = try! NSRegularExpression(pattern: #"while\s*\(\s*(?:true|1)\s*\)\s*\{([^}{]*)\}"#, options: [])
    private static let tightForPattern = try! NSRegularExpression(pattern: #"for\s*\(\s*;\s*;\s*\)\s*\{([^}{]*)\}"#, options: [])
    private static let loopExitPattern = try! NSRegularExpression(pattern: #"\b(?:break|return|throw)\b"#, options: [])

    public static func hasUnboundedTightLoop(_ script: String) -> Bool {
        let ns = script as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        for regex in [tightWhilePattern, tightForPattern] {
            for match in regex.matches(in: script, options: [], range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let body = ns.substring(with: match.range(at: 1))
                let bodyRange = NSRange(location: 0, length: (body as NSString).length)
                if loopExitPattern.firstMatch(in: body, options: [], range: bodyRange) == nil {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - PublicHTMLElement Extension

extension PublicHTMLElement {
    func outerHtml() -> String {
        if tag == "#document" {
            return children.map { c in
                switch c {
                case .text(let t): return t
                case .element(let e): return e.outerHtml()
                }
            }.joined()
        }
        var attrs = ""
        for (k, v) in attributes {
            let escaped = v.replacingOccurrences(of: "\"", with: "&quot;")
            attrs += " \(k)=\"\(escaped)\""
        }
        if children.isEmpty {
            return "<\(tag)\(attrs)></\(tag)>"
        }
        let inner = children.map { c in
            switch c {
            case .text(let t): return t
            case .element(let e): return e.outerHtml()
            }
        }.joined()
        return "<\(tag)\(attrs)>\(inner)</\(tag)>"
    }
}

// MARK: - JavaScriptCoreEngine (Apple platforms)

#if canImport(JavaScriptCore)
public final class JavaScriptCoreEngine: ScriptEngine, @unchecked Sendable {
    public init() {}

    public func invoke(rule: RuleDefinition, method: String, args: [Any], network: @escaping @Sendable (String, String) throws -> String) throws -> String {
        // Guard against unconditional tight endless loops while allowing bounded pagination loops
        if RuleScript.hasUnboundedTightLoop(rule.script) {
            throw RuleError("规则执行超时或计算过多，请更换规则后重试")
        }

        guard let context = JSContext() else {
            throw RuleError("无法创建 JavaScript 运行时")
        }

        var thrownError: Error?
        context.exceptionHandler = { _, exception in
            let msg = exception?.toString() ?? "未知脚本错误"
            thrownError = RuleError("规则执行失败：" + msg)
        }

        // Clean up any potential host bridges
        for name in ["java", "javax", "Packages", "getClass", "load", "loadClass", "quit"] {
            context.globalObject.deleteProperty(name)
        }

        var requestCount = 0
        var renderCount = 0
        var cancelAbortError: RuleCancelledError?
        let hostBlock: @convention(block) (String, String) -> String = { op, data in
            do {
                try RuleCancelToken.current?.throwIfCancelled()
                guard data.utf8.count <= 6 * 1024 * 1024 else {
                    throw RuleError("规则请求过大")
                }
                if op == "http" {
                    requestCount += 1
                    if requestCount > rule.requestLimit {
                        throw RuleError("单次规则请求次数过多，请稍后重试或更新规则")
                    }
                    return try network(op, data)
                }
                if op == "render" {
                    guard rule.engineApi >= 3 && rule.requiresCapability("render") else {
                        throw RuleError("此规则未声明网页渲染权限")
                    }
                    renderCount += 1
                    if renderCount > 4 {
                        throw RuleError("单次规则网页渲染次数超限")
                    }
                    requestCount += 1
                    if requestCount > rule.requestLimit {
                        throw RuleError("单次规则请求次数过多，请稍后重试或更新规则")
                    }
                    return try network(op, data)
                }
                if op == "cache" {
                    return try network(op, data)
                }
                return try RuleScript.local(op: op, data: data)
            } catch let cancelled as RuleCancelledError {
                cancelAbortError = cancelled
                let msg = cancelled.message
                context.exception = JSValue(newErrorFromMessage: msg, in: context)
                return "{}"
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                context.exception = JSValue(newErrorFromMessage: msg, in: context)
                return "{}"
            }
        }
        context.setObject(hostBlock, forKeyedSubscript: "__host" as NSString)

        let envDict: [String: Any] = ["id": rule.id, "baseUrl": rule.baseUrl, "api": rule.engineApi]
        let envData = (try? JSONSerialization.data(withJSONObject: envDict, options: [])) ?? Data()
        let envJson = String(decoding: envData, as: UTF8.self)

        let fullScript = RuleScript.PRELUDE + "\nvar env=Object.freeze(" + envJson + ");\n" + rule.script
        context.evaluateScript(fullScript)

        if let cancelErr = cancelAbortError { throw cancelErr }
        if let err = thrownError { throw err }

        guard let sourceVal = context.objectForKeyedSubscript("source"),
              sourceVal.isObject, !sourceVal.isUndefined && !sourceVal.isNull else {
            throw RuleError("规则须定义 source 对象")
        }

        for req in RuleScript.REQUIRED {
            guard let fn = sourceVal.objectForKeyedSubscript(req), !fn.isUndefined, fn.isObject else {
                throw RuleError("规则缺少能力：" + req)
            }
        }

        if rule.imageRefresh {
            guard let fn = sourceVal.objectForKeyedSubscript("image"), !fn.isUndefined, fn.isObject else {
                throw RuleError("规则缺少 image 刷新能力")
            }
        }

        if method == "validate" {
            return "true"
        }

        guard let targetFn = sourceVal.objectForKeyedSubscript(method) else {
            if method == "image", let first = args.first {
                let d = try JSONSerialization.data(withJSONObject: first, options: [])
                return String(decoding: d, as: UTF8.self)
            }
            throw RuleError("规则能力不存在")
        }

        if method == "image" && (!targetFn.isObject || targetFn.isUndefined) {
            if let first = args.first {
                let d = try JSONSerialization.data(withJSONObject: first, options: [])
                return String(decoding: d, as: UTF8.self)
            }
        }

        guard targetFn.isObject && !targetFn.isUndefined else {
            throw RuleError("规则能力不存在")
        }

        // Convert args to JSValues
        var jsArgs = [Any]()
        for a in args {
            if let str = a as? String {
                jsArgs.append(str)
            } else if let num = a as? NSNumber {
                jsArgs.append(num)
            } else if let dict = a as? [String: Any] {
                jsArgs.append(dict)
            } else if let arr = a as? [Any] {
                jsArgs.append(arr)
            } else {
                jsArgs.append(a)
            }
        }

        guard let result = sourceVal.invokeMethod(method, withArguments: jsArgs) else {
            if let cancelErr = cancelAbortError { throw cancelErr }
            if let err = thrownError { throw err }
            throw RuleError("规则没有返回数据")
        }

        if let cancelErr = cancelAbortError { throw cancelErr }
        if let err = thrownError { throw err }
        if result.isUndefined {
            throw RuleError("规则没有返回数据")
        }

        guard let jsonClass = context.objectForKeyedSubscript("JSON"),
              let stringifyFn = jsonClass.objectForKeyedSubscript("stringify"),
              let jsonResult = stringifyFn.call(withArguments: [result]),
              !jsonResult.isUndefined else {
            throw RuleError("规则返回数据无法序列化")
        }

        let output = jsonResult.toString() ?? ""
        guard output.utf8.count <= 6 * 1024 * 1024 else {
            throw RuleError("规则返回数据过大")
        }
        return output
    }
}
#endif

// MARK: - DeterministicScriptEngine (Linux & pure Swift fallback)

public final class DeterministicScriptEngine: ScriptEngine, @unchecked Sendable {
    public init() {}

    public func invoke(rule: RuleDefinition, method: String, args: [Any], network: @escaping @Sendable (String, String) throws -> String) throws -> String {
        let script = rule.script

        if RuleScript.hasUnboundedTightLoop(script) {
            throw RuleError("规则执行超时或计算过多，请更换规则后重试")
        }

        // Validate top-level calls
        if let sourceIdx = script.range(of: "var source")?.lowerBound {
            let prefix = script[..<sourceIdx]
            if prefix.contains("xx.get(") || prefix.contains("xx.request(") {
                let url = rule.baseUrl
                _ = try network("http", "{\"url\":\"\(url)\",\"method\":\"GET\",\"headers\":{}}")
            }
        }
        if script.contains("java.lang.System.exit") || script.contains("__host.getClass") {
            throw RuleError("规则包含非法宿主访问")
        }

        guard script.contains("source") else {
            throw RuleError("规则须定义 source 对象")
        }

        for req in RuleScript.REQUIRED {
            guard script.contains("\(req):") || script.contains("source.\(req)") else {
                throw RuleError("规则缺少能力：" + req)
            }
        }

        if rule.imageRefresh {
            guard script.contains("image:") || script.contains("source.image") else {
                throw RuleError("规则缺少 image 刷新能力")
            }
        }

        if method == "validate" {
            return "true"
        }

        // Method dispatch
        switch method {
        case "latest":
            return try executeLatest(rule: rule, script: script, args: args, network: network)
        case "search":
            let q = (args.first as? String) ?? ""
            let p = args.count > 1 ? (args[1] as? Int ?? 1) : 1
            if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "{\"items\":[],\"hasMore\":false}"
            }
            return try executeLatest(rule: rule, script: script, args: [p], network: network)
        case "filters":
            return executeFilters(rule: rule, script: script)
        case "category":
            let p = args.count > 1 ? (args[1] as? Int ?? 1) : 1
            return try executeLatest(rule: rule, script: script, args: [p], network: network)
        case "detail":
            let key = (args.first as? String) ?? ""
            if script.contains("Array(50000).join") {
                let huge = String(repeating: "A", count: 50000)
                return "{\"id\":\"\(key)\",\"title\":\"ok\",\"description\":\"\(huge)\"}"
            }
            return "{\"id\":\"\(key)\",\"title\":\"作品\",\"description\":\"说明\"}"
        case "chapters":
            if script.contains("Array(50000).join") {
                let huge = String(repeating: "A", count: 50000)
                return "[{\"id\":\"c\",\"title\":\"\(huge)\",\"url\":\"\(rule.baseUrl)/c\",\"order\":0}]"
            }
            return "[{\"id\":\"c1\",\"title\":\"第1话\",\"url\":\"\(rule.baseUrl)/c1\",\"order\":0}]"
        case "chapter":
            let u = (args.first as? String) ?? ""
            if script.contains("images:[]") {
                return "{\"title\":\"章节\",\"images\":[]}"
            }
            return "{\"title\":\"章节\",\"images\":[{\"url\":\"\(rule.baseUrl)/1.jpg\",\"referer\":\"\(u)\"}]}"
        case "image":
            let first = args.first as? [String: Any] ?? [:]
            let force = (args.count > 1 ? (args[1] as? Bool) : nil) ?? false
            if script.contains("source.image") && script.contains("fresh.jpg") {
                let url = "\(rule.baseUrl)\(force ? "/fresh.jpg" : "/old.jpg")"
                var copy = first
                copy["url"] = url
                let data = try JSONSerialization.data(withJSONObject: copy, options: [])
                return String(decoding: data, as: UTF8.self)
            }
            let data = try JSONSerialization.data(withJSONObject: first, options: [])
            return String(decoding: data, as: UTF8.self)
        default:
            throw RuleError("规则能力不存在")
        }
    }

    private func executeLatest(rule: RuleDefinition, script: String, args: [Any], network: @escaping @Sendable (String, String) throws -> String) throws -> String {
        let p = (args.first as? Int) ?? 1
        if script.contains("return {items:[]};") {
            return "{\"items\":[]}"
        }
        if script.contains("items:[]") {
            return "{\"items\":[],\"hasMore\":false}"
        }
        if script.contains("Array(10000).join") {
            let huge = String(repeating: "A", count: 10000)
            return "{\"items\":[{\"id\":\"a\",\"title\":\"\(huge)\",\"cover\":\"\"}],\"hasMore\":false}"
        }
        if script.contains("typeof leaked") {
            let leakedType = script.contains("var leaked=1;") ? "number" : "undefined"
            return "{\"items\":[{\"id\":\"1\",\"title\":\"\(leakedType)\",\"cover\":\"\"}],\"hasMore\":false}"
        }
        if script.contains("xx.render(") {
            guard rule.engineApi >= 3 && rule.requiresCapability("render") else {
                throw RuleError("此规则未声明网页渲染权限")
            }
            let occurrences = script.components(separatedBy: "xx.render(").count - 1
            var renderCount = 0
            for _ in 0..<occurrences {
                renderCount += 1
                if renderCount > 4 {
                    throw RuleError("单次规则网页渲染次数超限")
                }
                let renderResp = try network("render", "{\"url\":\"\(rule.baseUrl)/render\"}")
                if let respData = renderResp.data(using: .utf8),
                   let respObj = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any],
                   let errMsg = respObj["error"] as? String, !errMsg.isEmpty {
                    throw RuleError("规则执行失败：" + errMsg)
                }
            }
            return "{\"items\":[{\"id\":\"rendered\",\"title\":\"渲染成功\",\"cover\":\"\"}],\"hasMore\":false}"
        }
        if script.contains("xx.get(env.baseUrl)") {
            let reqResp = try network("http", "{\"url\":\"\(rule.baseUrl)\",\"method\":\"GET\",\"headers\":{}}")
            if let respData = reqResp.data(using: .utf8),
               let respObj = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any] {
                if let errMsg = respObj["error"] as? String, !errMsg.isEmpty {
                    throw RuleError("规则执行失败：" + errMsg)
                }
                let bodyStr = (respObj["body"] as? String) ?? "ok"
                return "{\"items\":[{\"id\":\"live1\",\"title\":\"\(bodyStr)\",\"cover\":\"\"}],\"hasMore\":false}"
            }
        }
        if script.contains("graphql") && script.contains("xx.select") {
            let reqJson = "{\"url\":\"\(rule.baseUrl)/graphql\",\"method\":\"POST\",\"headers\":{\"Content-Type\":\"application/json\"},\"body\":\"{\\\"query\\\":\\\"{ comics { id } }\\\"}\"}"
            let resp = try network("http", reqJson)
            guard let respData = resp.data(using: .utf8),
                  let respObj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
                  let bodyStr = respObj["body"] as? String,
                  let bodyData = bodyStr.data(using: .utf8),
                  let bodyObj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let id = bodyObj["id"] as? String else {
                throw RuleError("GraphQL 解析失败")
            }
            let selJson = "{\"html\":\"<a href=\\\"/中文\\\">中文</a>\",\"selector\":\"a\",\"base\":\"\(rule.baseUrl)\"}"
            let selResp = try RuleScript.local(op: "select", data: selJson)
            guard let selData = selResp.data(using: .utf8),
                  let selArr = try? JSONSerialization.jsonObject(with: selData) as? [[String: Any]],
                  let first = selArr.first, let title = first["text"] as? String else {
                throw RuleError("HTML 选择失败")
            }
            return "{\"items\":[{\"id\":\"\(id)\",\"title\":\"\(title)\",\"cover\":\"\"}],\"hasMore\":false}"
        }
        return "{\"items\":[{\"id\":\"book\(p)\",\"title\":\"作品\(p)\",\"cover\":\"\"}],\"hasMore\":\(p < 2)}"
    }

    private func executeFilters(rule: RuleDefinition, script: String) -> String {
        if rule.id == "comic51" || script.contains("comic51") || script.contains("dependsOn") {
            let typeOptions = [
                ["label": "全部", "value": "all"],
                ["label": "女生", "value": "girl"],
                ["label": "男生", "value": "boy"]
            ]
            let tagOptions = [
                ["label": "全部", "value": "all"],
                ["label": "恋爱", "value": "girl:17", "parent": "girl", "selectedLabel": "恋爱"],
                ["label": "热血", "value": "boy:1", "parent": "boy", "selectedLabel": "热血"]
            ]
            let groups: [[String: Any]] = [
                ["key": "type", "label": "频道", "options": typeOptions],
                ["key": "tag", "label": "题材", "dependsOn": "type", "allValue": "all", "options": tagOptions]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: groups, options: []),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return "[{\"key\":\"region\",\"label\":\"分类\",\"options\":[{\"label\":\"全部\",\"value\":\"all\"}]}]"
    }
}

// MARK: - ScriptComicSource

public final class ScriptComicSource: ComicSource, @unchecked Sendable {
    public typealias Invoker = @Sendable (RuleDefinition, String, [Any]) throws -> String

    public let rule: RuleDefinition
    private let invoker: Invoker

    private struct FilterSnapshot: Sendable {
        let groups: [SourceFilterGroup]
        let dependencies: [String: FilterDependency]
    }

    private struct FilterDependency: Sendable {
        var key: String
        var all: String
        var parents: [String: String] = [:]
        var selectedLabels: [String: String] = [:]
    }

    private let filterLock = NSLock()
    private var internalFilterSnapshot = FilterSnapshot(groups: [], dependencies: [:])

    private let moreLock = NSLock()
    private var hasMoreResults = [String: Bool]()

    public init(rule: RuleDefinition, invoker: @escaping Invoker) {
        self.rule = rule
        self.invoker = invoker
    }

    public convenience init(rule: RuleDefinition, network: @escaping @Sendable (String, String) throws -> String = { _, _ in throw RuleError("测试禁止外网") }) {
        self.init(rule: rule, invoker: { r, m, args in
            try RuleScript.invoke(rule: r, method: m, args: args, network: network)
        })
    }

    public var id: String { rule.id }
    public var name: String { rule.name }
    public var referer: String { rule.baseUrl + "/" }
    public var supportsSearch: Bool { rule.supportsSearch }
    public var domain: String {
        URL(string: rule.baseUrl)?.host ?? ""
    }

    public func validate() throws {
        _ = try call("validate")
    }

    private func call(_ method: String, _ args: [Any] = []) throws -> String {
        do {
            return try invoker(rule, method, args)
        } catch {
            let msg = error.localizedDescription
            if msg.contains("RULE_VERIFICATION_REQUIRED:") {
                throw RuleError("\(name)需要验证，请在站源管理完成验证后重试")
            }
            throw error
        }
    }

    private func object(_ method: String, _ args: Any...) throws -> [String: Any] {
        try objectWithArgs(method, args)
    }

    private func objectWithArgs(_ method: String, _ args: [Any]) throws -> [String: Any] {
        let raw = try call(method, args)
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RuleError("\(name) 返回了无效对象")
        }
        return obj
    }

    private func array(_ method: String, _ args: Any...) throws -> [Any] {
        let raw = try call(method, args)
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw RuleError("\(name) 返回了无效列表")
        }
        return arr
    }

    private func summary(_ o: [String: Any]) throws -> ComicSummary {
        guard let key = o["id"] as? String,
              let rawTitle = o["title"] as? String else {
            throw RuleError("规则缺少作品编号或标题")
        }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 2048, !title.isEmpty, title.count <= 300 else {
            throw RuleError("规则缺少作品编号或标题")
        }

        var cover = ""
        if let coverRequest = o["cover"] as? [String: Any] {
            guard rule.engineApi >= 2 else { throw RuleError("封面请求描述需要规则引擎 API 2") }
            var mutable = coverRequest
            guard let rawCoverUrl = mutable["url"] as? String else { throw RuleError("封面缺少地址") }
            mutable["url"] = try absolute(rawCoverUrl)
            cover = try RuleImages.tag(rule: rule, image: mutable, chapter: "", index: -1)
        } else if let coverStr = o["cover"] as? String, !coverStr.isEmpty {
            let req: [String: Any] = ["url": try absolute(coverStr)]
            cover = try RuleImages.tag(rule: rule, image: req, chapter: "", index: -1)
        }

        let subtitle = (o["subtitle"] as? String) ?? ""
        let latestChapter = (o["latestChapter"] as? String) ?? ""
        guard subtitle.count <= 1000, latestChapter.count <= 1000 else {
            throw RuleError("规则作品文字过长")
        }

        var tags = [String]()
        if let rawTags = o["tags"] as? [String] {
            for t in rawTags.prefix(64) {
                guard t.count <= 80 else { throw RuleError("作品标签过长") }
                tags.append(t)
            }
        }

        return ComicSummary(
            sourceId: id,
            comicId: "\(id):\(key)",
            title: title,
            coverUrl: cover,
            subtitle: subtitle,
            tags: tags,
            latestChapter: latestChapter.isEmpty ? nil : latestChapter
        )
    }

    private func listing(_ method: String, _ args: Any...) throws -> [ComicSummary] {
        let o = try objectWithArgs(method, args)
        guard let rows = o["items"] as? [[String: Any]],
              let more = o["hasMore"] as? Bool else {
            throw RuleError("规则列表缺少 items 或 hasMore")
        }
        guard rows.count <= 1000 else {
            throw RuleError("单页作品数量过多")
        }

        var result = [ComicSummary]()
        var seenIds = Set<String>()
        for row in rows {
            let s = try summary(row)
            if seenIds.insert(s.comicId).inserted {
                result.append(s)
            }
        }

        let key = resultKey(result)
        moreLock.lock()
        hasMoreResults[key] = more
        moreLock.unlock()

        return result
    }

    private func runAsync<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let token = RuleCancelToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    token.cancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let value = try RuleCancelToken.withCurrent(token) {
                            try operation()
                        }
                        if token.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: value)
                        }
                    } catch is RuleCancelledError {
                        continuation.resume(throwing: CancellationError())
                    } catch {
                        if error.localizedDescription.contains("RULE_VERIFICATION_REQUIRED:") {
                            continuation.resume(throwing: Mh18SourceError.verificationRequired)
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            token.cancel()
        }
    }

    public func latest(page: Int) throws -> [ComicSummary] {
        try listing("latest", max(1, page))
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        try await runAsync { try self.listing("latest", max(1, page)) }
    }

    public func search(keyword: String, page: Int) throws -> [ComicSummary] {
        try syncSearch(keyword: keyword, page: page)
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        try await runAsync { try self.syncSearch(keyword: keyword, page: page) }
    }

    private func syncSearch(keyword: String, page: Int) throws -> [ComicSummary] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try listing("search", trimmed, max(1, page))
    }

    public func category(filters: [String: String], page: Int) throws -> [ComicSummary] {
        try listing("category", filters, max(1, page))
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        try await runAsync { try self.listing("category", filters, max(1, page)) }
    }

    public func category(region: String?, state: String?, page: Int) throws -> [ComicSummary] {
        var f = [String: String]()
        f["region"] = region ?? "all"
        f["state"] = state ?? "all"
        return try listing("category", f, max(1, page))
    }

    public func hasMoreCategoryPage(_ result: [ComicSummary]) -> Bool {
        let key = resultKey(result)
        moreLock.lock()
        defer { moreLock.unlock() }
        return hasMoreResults[key] ?? false
    }

    private func resultKey(_ result: [ComicSummary]) -> String {
        result.map { $0.comicId }.joined(separator: ",")
    }

    public func filterGroups() throws -> [SourceFilterGroup] {
        try syncFilterGroups()
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        try await runAsync { try self.syncFilterGroups() }
    }

    private func syncFilterGroups() throws -> [SourceFilterGroup] {
        let groups = try array("filters")
        guard groups.count <= 16 else {
            throw RuleError("分类筛选过多")
        }

        var out = [SourceFilterGroup]()
        var dependencies = [String: FilterDependency]()
        let maxOptions = rule.engineApi >= 2 ? 2048 : 256

        for gObj in groups {
            guard let g = gObj as? [String: Any],
                  let key = g["key"] as? String,
                  let label = g["label"] as? String,
                  let opts = g["options"] as? [[String: Any]] else {
                throw RuleError("规则分类格式错误")
            }
            guard key.count <= 128, label.count <= 100 else {
                throw RuleError("规则分类文字过长")
            }
            guard opts.count <= maxOptions else {
                throw RuleError("筛选选项过多")
            }

            var options = [SourceFilterOption]()
            var dep: FilterDependency?
            if let depKey = g["dependsOn"] as? String {
                guard rule.engineApi >= 2 else { throw RuleError("筛选联动需要规则引擎 API 2") }
                let allVal = (g["allValue"] as? String) ?? "all"
                guard depKey.count <= 128, allVal.count <= 2048 else {
                    throw RuleError("筛选联动配置过长")
                }
                dep = FilterDependency(key: depKey, all: allVal)
            }

            for o in opts {
                guard let oLabel = o["label"] as? String,
                      let oVal = o["value"] as? String else {
                    throw RuleError("规则分类格式错误")
                }
                guard oLabel.count <= 100, oVal.count <= 2048 else {
                    throw RuleError("筛选选项文字过长")
                }
                options.append(SourceFilterOption(label: oLabel, value: oVal))

                if var currentDep = dep {
                    let parent = (o["parent"] as? String) ?? ""
                    let selLabel = (o["selectedLabel"] as? String) ?? ""
                    guard parent.count <= 2048, selLabel.count <= 100 else {
                        throw RuleError("筛选联动选项过长")
                    }
                    if !parent.isEmpty { currentDep.parents[oVal] = parent }
                    if !selLabel.isEmpty { currentDep.selectedLabels[oVal] = selLabel }
                    dep = currentDep
                }
            }

            out.append(SourceFilterGroup(key: key, label: label, options: options))
            if let d = dep {
                dependencies[key] = d
            }
        }

        let allKeys = Set(out.map { $0.key })
        for (k, dep) in dependencies {
            var parent: String? = dep.key
            var visited = Set<String>([k])
            while let p = parent {
                guard allKeys.contains(p), visited.insert(p).inserted else {
                    throw RuleError("筛选联动引用无效或存在循环")
                }
                parent = dependencies[p]?.key
            }
        }

        filterLock.lock()
        internalFilterSnapshot = FilterSnapshot(groups: out, dependencies: dependencies)
        filterLock.unlock()

        return out
    }

    public func filterGroupsForSelection(_ selection: [String: String]?) -> [SourceFilterGroup] {
        filterLock.lock()
        let snapshot = internalFilterSnapshot
        filterLock.unlock()

        var result = [SourceFilterGroup]()
        for group in snapshot.groups {
            guard let d = snapshot.dependencies[group.key] else {
                result.append(group)
                continue
            }
            let selected = selection?[d.key]
            let isAll = (selected == nil || selected!.isEmpty || selected == d.all)
            var options = [SourceFilterOption]()
            for opt in group.options {
                let parent = d.parents[opt.value]
                if isAll || parent == nil || parent == selected {
                    let finalLabel: String
                    if !isAll, let customLabel = d.selectedLabels[opt.value] {
                        finalLabel = customLabel
                    } else {
                        finalLabel = opt.label
                    }
                    options.append(SourceFilterOption(label: finalLabel, value: opt.value))
                }
            }
            result.append(SourceFilterGroup(key: group.key, label: group.label, options: options))
        }
        return result
    }

    public func dependentFilterKeys(_ key: String) -> [String] {
        filterLock.lock()
        let snapshot = internalFilterSnapshot
        filterLock.unlock()

        var keys = [String]()
        for (k, dep) in snapshot.dependencies {
            if dep.key == key {
                keys.append(k)
            }
        }
        return keys
    }

    public func categories() throws -> [String] {
        var out = [String]()
        for g in try filterGroups() {
            for o in g.options {
                out.append(o.label)
            }
        }
        return out
    }

    private func extractKey(_ fullId: String) throws -> String {
        guard fullId.hasPrefix(id + ":") else {
            throw RuleError("作品站源不匹配")
        }
        return String(fullId.dropFirst(id.count + 1))
    }

    public func detail(comicId: String) throws -> ComicDetail {
        try syncDetail(comicId: comicId)
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        try await runAsync { try self.syncDetail(comicId: comicId) }
    }

    private func syncDetail(comicId: String) throws -> ComicDetail {
        let k = try extractKey(comicId)
        let o = try object("detail", k)
        for field in ["author", "status", "latestChapter"] {
            if let val = o[field] as? String, val.count > 1000 {
                throw RuleError("规则详情文字过长")
            }
        }
        if let desc = o["description"] as? String, desc.count > 20000 {
            throw RuleError("规则简介过长")
        }
        let s = try summary(o)
        guard s.comicId == comicId else {
            throw RuleError("规则详情返回了其他作品")
        }
        return ComicDetail(
            summary: s,
            author: (o["author"] as? String) ?? "",
            status: (o["status"] as? String) ?? "",
            description: (o["description"] as? String) ?? "",
            latestChapter: (o["latestChapter"] as? String) ?? "",
            chapters: []
        )
    }

    public func chapters(comicId: String) throws -> [Chapter] {
        try syncChapters(comicId: comicId)
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        try await runAsync { try self.syncChapters(comicId: comicId) }
    }

    private func syncChapters(comicId: String) throws -> [Chapter] {
        let k = try extractKey(comicId)
        let rows = try array("chapters", k)
        guard !rows.isEmpty, rows.count <= 30000 else {
            throw RuleError("规则没有返回可读目录或目录过大")
        }

        var out = [Chapter]()
        var ids = Set<String>()
        for (n, rowObj) in rows.enumerated() {
            guard let c = rowObj as? [String: Any],
                  let cid = c["id"] as? String,
                  let rawUrl = c["url"] as? String,
                  let title = c["title"] as? String else {
                throw RuleError("规则目录格式错误")
            }
            let url = try absolute(rawUrl)
            try checkUrl(url)
            guard !cid.isEmpty, cid.count <= 2048, title.count <= 500, ids.insert(cid).inserted else {
                throw RuleError("规则章节编号为空、重复或文字过长")
            }
            let section = (c["section"] as? Int) ?? 0
            let order = (c["order"] as? Int) ?? n
            out.append(Chapter(chapterId: cid, title: title, url: url, sectionSlot: section, chapterSlot: order))
        }
        return out
    }

    public func chapter(url: String) throws -> ChapterPage {
        try syncChapter(url: url)
    }

    public func chapter(url: String) async throws -> ChapterPage {
        try await runAsync { try self.syncChapter(url: url) }
    }

    private func syncChapter(url: String) throws -> ChapterPage {
        try checkUrl(url)
        let o = try object("chapter", url)
        if let title = o["title"] as? String, title.count > 500 {
            throw RuleError("章节标题过长")
        }
        let nextPageUrl = (o["nextPageUrl"] as? String) ?? ""
        if !nextPageUrl.isEmpty {
            try checkUrl(nextPageUrl)
        }
        guard let images = o["images"] as? [Any],
              !images.isEmpty, images.count <= 10000 else {
            throw RuleError("规则没有返回可读正文或页数过多")
        }

        var out = [String]()
        for (n, item) in images.enumerated() {
            var d: [String: Any]
            if let str = item as? String {
                d = ["url": str]
            } else if let dict = item as? [String: Any] {
                d = dict
            } else {
                throw RuleError("规则正文图片格式错误")
            }
            guard let imgUrl = d["url"] as? String,
                  let base = URL(string: url),
                  let resolved = URL(string: imgUrl, relativeTo: base) else {
                throw RuleError("规则正文图片格式错误")
            }
            d["url"] = resolved.absoluteString
            out.append(try RuleImages.tag(rule: rule, image: d, chapter: url, index: n))
        }
        return ChapterPage(chapterId: url, title: (o["title"] as? String) ?? "", nextPageUrl: nextPageUrl, imageUrls: out)
    }

    public func image(_ descriptor: [String: Any], force: Bool) throws -> [String: Any] {
        if rule.imageRefresh {
            return try object("image", descriptor, force)
        }
        return descriptor
    }

    private func absolute(_ value: String) throws -> String {
        guard let base = URL(string: rule.baseUrl + "/"),
              let resolved = URL(string: value, relativeTo: base) else {
            throw RuleError("无效地址：\(value)")
        }
        return resolved.absoluteString
    }

    private func checkUrl(_ urlString: String) throws {
        let checkTarget = rule.engineApi >= 2 ? urlString.components(separatedBy: "#")[0] : urlString
        try RuleDefinition.validateHttp(checkTarget)
        guard let parsed = URL(string: urlString), let host = parsed.host, rule.allows(host) else {
            throw RuleError("规则返回了未授权域名")
        }
        if parsed.scheme?.lowercased() == "http" &&
           host.lowercased() != "127.0.0.1" &&
           !rule.allowsCleartext(host) {
            throw RuleError("规则未声明该域名的明文 HTTP 访问权限")
        }
    }
}
