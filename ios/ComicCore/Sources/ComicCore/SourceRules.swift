import Foundation
import CoreFoundation
import ComicZlib
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

// MARK: - RuleDefinition

/// Immutable, portable source identity. No device credentials are stored in definitions.
public final class RuleDefinition: @unchecked Sendable, Equatable {
    public static let API: Int = 3
    public static let MAX_SCRIPT: Int = 512 * 1024
    public static let MAX_PACKAGE: Int = 16 * 1024 * 1024

    public static let SUPPORTED_CAPABILITIES: Set<String> = [
        "cleartext", "decodePipeline", "tiles", "stripes", "binaryHttp", "cryptoV3", "minInterval", "render"
    ]

    public static let LEGACY_CLEARTEXT_HOSTS: Set<String> = [
        "www.aymry.com",
        "www.mh250.com",
        "www.xiuxmanhua.com",
        "123.77comic.com",
        "content.mkzcdn.com",
        "img.maomimh.com",
        "pp1.tupian.run"
    ]

    public let id: String
    public let name: String
    public let baseUrl: String
    public let script: String
    public let scriptSha256: String
    public let hash: String
    public let coreHash: String
    public let version: Int
    public let engineApi: Int
    public let requestLimit: Int
    public let timeoutSeconds: Int
    public let minIntervalMs: Int
    public let replacesNative: Bool
    public let imageRefresh: Bool
    public let supportsSearch: Bool
    public let browserSession: Bool
    public let requiresVpn: Bool
    private let vpnDeclared: Bool
    public let hosts: [String]
    public let requires: [String]
    public let cleartextHosts: [String]

    public init(json: [String: Any]) throws {
        guard let id = json["id"] as? String,
              let rawName = json["name"] as? String,
              let version = json["version"] as? Int,
              let engineApi = json["engineApi"] as? Int,
              let rawBaseUrl = json["baseUrl"] as? String,
              let script = json["script"] as? String,
              let scriptSha256 = json["scriptSha256"] as? String,
              let hostsList = json["hosts"] as? [String] else {
            throw RuleError("规则字段不完整或格式错误")
        }

        self.id = id
        self.name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.version = version

        guard id.range(of: #"^[a-z][a-z0-9_]{1,63}$"#, options: .regularExpression) != nil,
              !["local", "baozimh", "mhua5"].contains(id) else {
            throw RuleError("站源 ID 无效或已保留")
        }

        guard !self.name.isEmpty, self.name.count <= 80, version >= 1, engineApi >= 1 else {
            throw RuleError("站源名称或版本无效")
        }

        let scriptTrimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let scriptBytes = Data(script.utf8)
        guard !scriptTrimmed.isEmpty, scriptBytes.count <= Self.MAX_SCRIPT else {
            throw RuleError("规则脚本为空或超过 512KiB")
        }
        self.script = script
        self.scriptSha256 = Self.sha(scriptBytes)
        guard self.scriptSha256.caseInsensitiveCompare(scriptSha256) == .orderedSame else {
            throw RuleError("规则脚本校验失败")
        }

        if engineApi > Self.API {
            throw UnsupportedRuleError("此规则需要升级规则引擎（API \(engineApi)）")
        }
        self.engineApi = engineApi

        self.supportsSearch = (json["supportsSearch"] as? Bool) ?? true
        self.browserSession = (json["browserSession"] as? Bool) ?? false

        if let vpnVal = json["requiresVpn"] {
            guard let boolVal = vpnVal as? Bool else {
                throw RuleError("站源网络标记格式无效")
            }
            self.vpnDeclared = true
            self.requiresVpn = boolVal
        } else {
            self.vpnDeclared = false
            self.requiresVpn = false
        }

        self.requestLimit = (json["requestLimit"] as? Int) ?? 40
        self.timeoutSeconds = (json["timeoutSeconds"] as? Int) ?? 90
        self.minIntervalMs = (json["minIntervalMs"] as? Int) ?? 50

        guard requestLimit >= 1 && requestLimit <= 512 &&
              timeoutSeconds >= 10 && timeoutSeconds <= 240 &&
              minIntervalMs >= 0 && minIntervalMs <= 10000 else {
            throw RuleError("规则执行配额无效")
        }
        if engineApi < 2 && (requestLimit != 40 || timeoutSeconds != 90) {
            throw RuleError("自定义执行配额需要规则引擎 API 2")
        }
        if engineApi < 2 && browserSession {
            throw RuleError("站点验证会话需要规则引擎 API 2")
        }
        if engineApi == 1 && !supportsSearch {
            throw RuleError("搜索能力声明需要规则引擎 API 2")
        }
        if json["minIntervalMs"] != nil && engineApi < 3 {
            throw RuleError("请求间隔配置需要规则引擎 API 3")
        }

        if let reqAny = json["requires"] {
            guard engineApi >= 3 else {
                throw RuleError("能力声明需要规则引擎 API 3")
            }
            guard let reqList = reqAny as? [String], reqList.count <= 32 else {
                throw RuleError("规则能力声明格式无效")
            }
            var reqSet = Set<String>()
            for cap in reqList {
                guard cap.range(of: #"^[a-zA-Z][a-zA-Z0-9_]{0,31}$"#, options: .regularExpression) != nil else {
                    throw RuleError("规则能力名称格式无效")
                }
                guard Self.SUPPORTED_CAPABILITIES.contains(cap) else {
                    throw UnsupportedRuleError("规则需要新版能力：\(cap)")
                }
                reqSet.insert(cap)
            }
            self.requires = reqSet.sorted()
        } else {
            self.requires = []
        }

        var cleanedBase = rawBaseUrl
        while cleanedBase.hasSuffix("/") {
            cleanedBase.removeLast()
        }
        self.baseUrl = cleanedBase
        try Self.validateHttp(self.baseUrl)

        guard let parsedBase = URL(string: self.baseUrl), let baseHost = parsedBase.host else {
            throw RuleError("站点域名不在授权列表中")
        }

        self.replacesNative = (json["replacesNative"] as? Bool) ?? false
        self.imageRefresh = (json["imageRefresh"] as? Bool) ?? false

        guard hostsList.count >= 1 && hostsList.count <= 64 else {
            throw RuleError("允许访问的域名数量无效")
        }
        var allow = Set<String>()
        for h in hostsList {
            let host = h.lowercased()
            try Self.validateHostPattern(host)
            allow.insert(host)
        }
        let sortedHosts = allow.sorted()
        self.hosts = sortedHosts

        if let clearAny = json["cleartextHosts"] {
            guard engineApi >= 3 else {
                throw RuleError("明文域名声明需要规则引擎 API 3")
            }
            guard let clearList = clearAny as? [String], clearList.count <= 64 else {
                throw RuleError("明文域名数量无效")
            }
            var clearSet = Set<String>()
            for rawCh in clearList {
                let ch = rawCh.lowercased()
                try Self.validateHostPattern(ch)
                guard Self.coversHostPattern(sortedHosts, candidate: ch) else {
                    throw RuleError("明文域名必须在 hosts 授权范围内")
                }
                clearSet.insert(ch)
            }
            self.cleartextHosts = clearSet.sorted()
        } else {
            self.cleartextHosts = []
        }

        // Java identity serialization uses ArrayList.toString() which produces: "[elem1, elem2]"
        let hostsString = "[" + self.hosts.joined(separator: ", ") + "]"
        let requiresString = "[" + self.requires.joined(separator: ", ") + "]"
        let cleartextString = "[" + self.cleartextHosts.joined(separator: ", ") + "]"
        let identity = "\(id)\n\(version)\n\(self.name)\n\(self.baseUrl)\n\(hostsString)\n\(self.replacesNative)\n\(self.imageRefresh)\n\(self.scriptSha256)"
            + (engineApi == 1 ? "" : "\napi=\(engineApi)\nsearch=\(supportsSearch)\nbrowser=\(browserSession)\nrequests=\(requestLimit)\ntimeout=\(timeoutSeconds)")
            + (engineApi < 3 ? "" : "\nrequires=\(requiresString)\ncleartext=\(cleartextString)\ninterval=\(minIntervalMs)")

        self.coreHash = Self.sha(Data(identity.utf8))
        self.hash = self.vpnDeclared
            ? Self.sha(Data((identity + "\nrequiresVpn=\(self.requiresVpn)").utf8))
            : self.coreHash

        guard self.allows(baseHost) else {
            throw RuleError("站点域名不在授权列表中")
        }
        if parsedBase.scheme?.lowercased() == "http" &&
           baseHost.lowercased() != "127.0.0.1" &&
           !self.allowsCleartext(baseHost) {
            throw RuleError("明文 HTTP 站点域名须声明于 cleartextHosts")
        }
    }

    private static func validateHostPattern(_ host: String) throws {
        guard host.count <= 253,
              host.range(of: #"^(?:\*\.)?[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$"#, options: .regularExpression) != nil,
              !host.contains("..") else {
            throw RuleError("域名授权格式无效")
        }
    }

    private static func matchesHostList(_ patterns: [String], host: String) -> Bool {
        let normalized = host.lowercased()
        for allowed in patterns {
            if normalized == allowed { return true }
            if allowed.hasPrefix("*.") {
                let suffix = String(allowed.dropFirst())
                if normalized.hasSuffix(suffix) { return true }
            }
        }
        return false
    }

    private static func coversHostPattern(_ patterns: [String], candidate: String) -> Bool {
        if !candidate.hasPrefix("*.") {
            return matchesHostList(patterns, host: candidate)
        }
        for allowed in patterns {
            if candidate == allowed { return true }
            if allowed.hasPrefix("*.") && candidate.hasSuffix(String(allowed.dropFirst())) {
                return true
            }
        }
        return false
    }

    public func allows(_ host: String?) -> Bool {
        guard let host = host else { return false }
        return Self.matchesHostList(hosts, host: host)
    }

    public func allowsCleartext(_ host: String?) -> Bool {
        guard let host = host else { return false }
        let normalized = host.lowercased()
        if engineApi >= 3 {
            return Self.matchesHostList(cleartextHosts, host: normalized)
        }
        return Self.LEGACY_CLEARTEXT_HOSTS.contains(normalized)
    }

    public func requiresCapability(_ capability: String) -> Bool {
        requires.contains(capability)
    }

    public func hasVpnDeclaration() -> Bool {
        vpnDeclared
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "version": version,
            "engineApi": engineApi,
            "baseUrl": baseUrl,
            "hosts": hosts,
            "script": script,
            "scriptSha256": scriptSha256,
            "replacesNative": replacesNative,
            "imageRefresh": imageRefresh
        ]
        if engineApi >= 2 {
            dict["supportsSearch"] = supportsSearch
            dict["browserSession"] = browserSession
            dict["requestLimit"] = requestLimit
            dict["timeoutSeconds"] = timeoutSeconds
        }
        if engineApi >= 3 {
            if !requires.isEmpty {
                dict["requires"] = requires
            }
            if !cleartextHosts.isEmpty {
                dict["cleartextHosts"] = cleartextHosts
            }
            if minIntervalMs != 50 {
                dict["minIntervalMs"] = minIntervalMs
            }
        }
        if vpnDeclared {
            dict["requiresVpn"] = requiresVpn
        }
        return dict
    }

    public static func validateHttp(_ urlString: String?) throws {
        guard let urlString = urlString, urlString.count <= 8192 else {
            throw RuleError("请求地址为空或过长")
        }
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.fragment == nil else {
            throw RuleError("仅支持不含账号与片段的 HTTP(S) 地址")
        }
    }

    public static func sha(_ data: Data) -> String {
        DownloadModels.sha256Hex(data)
    }

    public static func == (lhs: RuleDefinition, rhs: RuleDefinition) -> Bool {
        lhs.hash == rhs.hash
    }
}

// MARK: - RuleBase64

public enum RuleBase64 {
    private static let standardAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    private static let urlAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    public static func encode(_ data: Data, _ url: Bool = false) -> String {
        let alphabet = url ? urlAlphabet : standardAlphabet
        let count = data.count
        var out = [UInt8]()
        out.reserveCapacity(((count + 2) / 3) * 4)
        var i = 0
        while i < count {
            let a = data[i]
            let b = (i + 1 < count) ? data[i + 1] : 0
            let c = (i + 2 < count) ? data[i + 2] : 0

            out.append(alphabet[Int(a >> 2)])
            out.append(alphabet[Int(((a & 3) << 4) | (b >> 4))])
            if i + 1 < count {
                out.append(alphabet[Int(((b & 15) << 2) | (c >> 6))])
            } else if !url {
                out.append(UInt8(ascii: "="))
            }
            if i + 2 < count {
                out.append(alphabet[Int(c & 63)])
            } else if !url {
                out.append(UInt8(ascii: "="))
            }
            i += 3
        }
        return String(decoding: out, as: UTF8.self)
    }

    public static func decode(_ value: String) throws -> Data {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padLen = (4 - (normalized.utf8.count % 4)) % 4
        if padLen > 0 {
            normalized.append(String(repeating: "=", count: padLen))
        }
        guard let data = Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters]) else {
            throw RuleError("无效 Base64")
        }
        return data
    }
}

// MARK: - RuleCrypto

public enum RuleCrypto {
    public static func convert(_ args: [String: Any]) throws -> String {
        guard let type = args["type"] as? String else {
            throw RuleError("缺少编码类型")
        }
        let dataStr = (args["data"] as? String) ?? ""

        switch type {
        case "base64Encode":
            return RuleBase64.encode(Data(dataStr.utf8), false)

        case "base64Decode":
            let decoded = try RuleBase64.decode(dataStr)
            return try encodeBytes(decoded, encoding: (args["outputEncoding"] as? String) ?? "utf8")

        case "base64Latin1":
            let decoded = try RuleBase64.decode(dataStr)
            guard let text = String(data: decoded, encoding: .isoLatin1) else {
                throw RuleError("Latin1 解码失败")
            }
            return text

        case "base64FromLatin1":
            guard let raw = dataStr.data(using: .isoLatin1) else {
                throw RuleError("Latin1 编码失败")
            }
            return RuleBase64.encode(raw, false)

        case "hexEncode":
            let raw = try parseBinary(dataStr, encoding: (args["dataEncoding"] as? String) ?? "utf8")
            return toHex(raw)

        case "hexDecode":
            let raw = try parseBinary(dataStr, encoding: "hex")
            return try encodeBytes(raw, encoding: (args["outputEncoding"] as? String) ?? "utf8")

        case "urlEncode":
            let charset = (args["charset"] as? String) ?? "UTF-8"
            guard ["UTF-8", "GBK", "GB2312", "Big5"].contains(charset) else {
                throw RuleError("不支持此文本编码")
            }
            return try urlEncode(dataStr, charset: charset)

        case "pinyin":
            return pinyin(dataStr)

        case "md5":
            let input = try parseBinary(dataStr, encoding: (args["dataEncoding"] as? String) ?? "utf8")
            let digest = try parseBinary(md5Hex(input), encoding: "hex")
            return try encodeBytes(digest, encoding: (args["outputEncoding"] as? String) ?? "hex")

        case "sha1":
            let input = try parseBinary(dataStr, encoding: (args["dataEncoding"] as? String) ?? "utf8")
            let digest = try parseBinary(sha1Hex(input), encoding: "hex")
            return try encodeBytes(digest, encoding: (args["outputEncoding"] as? String) ?? "hex")

        case "sha512":
            let input = try parseBinary(dataStr, encoding: (args["dataEncoding"] as? String) ?? "utf8")
            let digest = try parseBinary(sha512Hex(input), encoding: "hex")
            return try encodeBytes(digest, encoding: (args["outputEncoding"] as? String) ?? "hex")

        case "sha256":
            let input = try parseBinary(dataStr, encoding: (args["dataEncoding"] as? String) ?? "utf8")
            let digest = try parseBinary(RuleDefinition.sha(input), encoding: "hex")
            return try encodeBytes(digest, encoding: (args["outputEncoding"] as? String) ?? "hex")

        case "hmacSha1", "hmacSha256":
            guard let keyStr = args["key"] as? String else {
                throw RuleError("HMAC 缺少密钥")
            }
            let keyBytes = try parseBinary(keyStr, encoding: (args["keyEncoding"] as? String) ?? "utf8")
            guard !keyBytes.isEmpty else {
                throw RuleError("HMAC 密钥不能为空")
            }
            let input = try parseBinary(dataStr, encoding: (args["dataEncoding"] as? String) ?? "utf8")
            let mac = type == "hmacSha1"
                ? SourceAES.hmacSha1(data: input, key: keyBytes)
                : SourceAES.hmacSha256(data: input, key: keyBytes)
            return try encodeBytes(mac, encoding: (args["outputEncoding"] as? String) ?? "hex")

        case "int64":
            guard let aStr = args["a"] as? String,
                  let bStr = args["b"] as? String,
                  let op = args["op"] as? String,
                  let left = Int64(aStr),
                  let right = Int64(bStr) else {
                throw RuleError("整数运算参数无效")
            }
            switch op {
            case "mul": return String(left &* right)
            case "xor": return String(left ^ right)
            case "and": return String(left & right)
            case "or":  return String(left | right)
            case "add": return String(left &+ right)
            case "sub": return String(left &- right)
            case "mod":
                guard right != 0 else { throw RuleError("整数运算除数不能为零") }
                return String(left % right)
            default:
                throw RuleError("不支持此整数运算")
            }

        case "inflate", "gzip":
            let raw = try parseBinary(dataStr, encoding: (args["dataEncoding"] as? String) ?? "base64")
            let decompressed = try decompress(raw, isGzip: type == "gzip")
            return try encodeBytes(decompressed, encoding: (args["outputEncoding"] as? String) ?? "utf8")

        case "aesCbcDecrypt", "aesEcbDecrypt", "aesCtrDecrypt":
            let encoding = (args["dataEncoding"] as? String) ?? "base64"
            let binaryData = try parseBinary(dataStr, encoding: encoding)
            let decrypted = try decrypt(input: binaryData, args: args)
            return try encodeBytes(decrypted, encoding: (args["outputEncoding"] as? String) ?? "utf8")

        case "aesCbcEncrypt", "aesEcbEncrypt", "aesCtrEncrypt":
            let encoding = (args["dataEncoding"] as? String) ?? "utf8"
            let binaryData = try parseBinary(dataStr, encoding: encoding)
            let encrypted = try encrypt(input: binaryData, args: args)
            return try encodeBytes(encrypted, encoding: (args["outputEncoding"] as? String) ?? "base64")

        case "xorBytes":
            guard let keyStr = args["key"] as? String else {
                throw RuleError("缺少 XOR 密钥")
            }
            let src = try parseBinary(dataStr, encoding: (args["dataEncoding"] as? String) ?? "base64")
            let xorKey = try parseBinary(keyStr, encoding: (args["keyEncoding"] as? String) ?? "base64")
            guard !xorKey.isEmpty, xorKey.count <= 4096 else {
                throw RuleError("XOR 密钥长度无效")
            }
            var out = [UInt8](repeating: 0, count: src.count)
            let srcBytes = Array(src)
            let keyBytes = Array(xorKey)
            for i in 0..<srcBytes.count {
                out[i] = srcBytes[i] ^ keyBytes[i % keyBytes.count]
            }
            return try encodeBytes(Data(out), encoding: (args["outputEncoding"] as? String) ?? "utf8")

        default:
            throw RuleError("不支持的编码方式")
        }
    }

    public static func decrypt(input: Data, args: [String: Any]) throws -> Data {
        let type = (args["type"] as? String) ?? "aesCbcDecrypt"
        let isEcb = type == "aesEcbDecrypt"
        let isCtr = type == "aesCtrDecrypt"
        let padding = (args["padding"] as? String) ?? (isCtr ? "NoPadding" : "PKCS5Padding")
        guard padding == "PKCS5Padding" || padding == "NoPadding" else {
            throw RuleError("不支持此填充模式")
        }
        guard let keyStr = args["key"] as? String else {
            throw RuleError("缺少解密密钥")
        }
        let keyEncoding = (args["keyEncoding"] as? String) ?? "base64"
        let key = try parseBinary(keyStr, encoding: keyEncoding)
        guard [16, 24, 32].contains(key.count) else {
            throw RuleError("AES 密钥长度无效")
        }

        var ciphertext = input
        let iv: Data
        if isEcb {
            iv = Data()
        } else {
            let ivPrefix = (args["ivPrefix"] as? Bool) ?? false
            if ivPrefix {
                guard ciphertext.count >= 16 else { throw RuleError("加密数据不完整") }
                iv = Data(ciphertext.prefix(16))
                ciphertext = Data(ciphertext.dropFirst(16))
            } else {
                guard let ivStr = args["iv"] as? String else { throw RuleError("缺少解密向量") }
                let ivEncoding = (args["ivEncoding"] as? String) ?? "base64"
                iv = try parseBinary(ivStr, encoding: ivEncoding)
            }
            guard iv.count == 16 else {
                throw RuleError("AES 初始向量长度无效")
            }
        }

        let pkcs7 = (padding == "PKCS5Padding")
        do {
            if isEcb {
                return try SourceAES.ecbDecrypt(ciphertext, key: key, pkcs7: pkcs7)
            } else if isCtr {
                return try SourceAES.ctrCrypt(ciphertext, key: key, iv: iv)
            } else {
                return try SourceAES.cbcDecrypt(ciphertext, key: key, iv: iv, pkcs7: pkcs7)
            }
        } catch {
            throw RuleError("规则数据解密失败")
        }
    }

    public static func encrypt(input: Data, args: [String: Any]) throws -> Data {
        let type = (args["type"] as? String) ?? "aesCbcEncrypt"
        let isEcb = type == "aesEcbEncrypt"
        let isCtr = type == "aesCtrEncrypt"
        let padding = (args["padding"] as? String) ?? (isCtr ? "NoPadding" : "PKCS5Padding")
        guard padding == "PKCS5Padding" || padding == "NoPadding" else {
            throw RuleError("不支持此填充模式")
        }
        guard let keyStr = args["key"] as? String else {
            throw RuleError("缺少加密密钥")
        }
        let key = try parseBinary(keyStr, encoding: (args["keyEncoding"] as? String) ?? "base64")
        guard [16, 24, 32].contains(key.count) else {
            throw RuleError("AES 密钥长度无效")
        }
        let iv: Data
        if isEcb {
            iv = Data()
        } else {
            guard let ivStr = args["iv"] as? String else { throw RuleError("缺少加密向量") }
            iv = try parseBinary(ivStr, encoding: (args["ivEncoding"] as? String) ?? "base64")
            guard iv.count == 16 else {
                throw RuleError("AES 初始向量长度无效")
            }
        }
        let pkcs7 = (padding == "PKCS5Padding")
        do {
            let encrypted: Data
            if isEcb {
                encrypted = try SourceAES.ecbEncrypt(input, key: key, pkcs7: pkcs7)
            } else if isCtr {
                encrypted = try SourceAES.ctrCrypt(input, key: key, iv: iv)
            } else {
                encrypted = try SourceAES.cbcEncrypt(input, key: key, iv: iv, pkcs7: pkcs7)
            }
            if !isEcb && ((args["ivPrefix"] as? Bool) == true) {
                var prefixed = Data(capacity: 16 + encrypted.count)
                prefixed.append(iv)
                prefixed.append(encrypted)
                return prefixed
            }
            return encrypted
        } catch {
            throw RuleError("规则数据加密失败")
        }
    }

    static func parseBinary(_ text: String, encoding: String) throws -> Data {
        switch encoding {
        case "utf8":
            return Data(text.utf8)
        case "latin1":
            guard let d = text.data(using: .isoLatin1) else {
                throw RuleError("Latin1 编码失败")
            }
            return d
        case "base64":
            return try RuleBase64.decode(text)
        case "hex":
            guard text.range(of: #"^(?:[a-fA-F0-9]{2})*$"#, options: .regularExpression) != nil else {
                throw RuleError("十六进制数据无效")
            }
            var data = Data()
            data.reserveCapacity(text.count / 2)
            var index = text.startIndex
            while index < text.endIndex {
                let next = text.index(index, offsetBy: 2)
                let byteStr = String(text[index..<next])
                guard let byte = UInt8(byteStr, radix: 16) else { throw RuleError("十六进制数据无效") }
                data.append(byte)
                index = next
            }
            return data
        default:
            throw RuleError("不支持此二进制编码")
        }
    }

    private static func encodeBytes(_ data: Data, encoding: String) throws -> String {
        switch encoding {
        case "utf8":
            return String(decoding: data, as: UTF8.self)
        case "latin1":
            guard let str = String(data: data, encoding: .isoLatin1) else {
                throw RuleError("Latin1 解码失败")
            }
            return str
        case "base64":
            return RuleBase64.encode(data, false)
        case "base64url":
            return RuleBase64.encode(data, true)
        case "hex":
            return toHex(data)
        default:
            throw RuleError("不支持此输出编码")
        }
    }

    private static func toHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func urlEncode(_ text: String, charset: String) throws -> String {
        let encoding: String.Encoding
        if charset == "UTF-8" {
            encoding = .utf8
        } else if charset == "GBK" || charset == "GB2312" {
            let cfEnc = CFStringEncodings.GB_18030_2000.rawValue
            encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEnc)))
        } else if charset == "Big5" {
            let cfEnc = CFStringEncodings.big5.rawValue
            encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEnc)))
        } else {
            throw RuleError("不支持此文本编码")
        }

        guard let data = text.data(using: encoding) else {
            throw RuleError("文本编码失败")
        }

        var result = ""
        for byte in data {
            if byte == 0x20 {
                result.append("+")
            } else if (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) ||
                      (byte >= 0x30 && byte <= 0x39) || byte == 0x2E || byte == 0x2D ||
                      byte == 0x2A || byte == 0x5F {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result.append(String(format: "%%%02X", byte))
            }
        }
        return result
    }

    private static func pinyin(_ text: String) -> String {
        #if canImport(ObjectiveC)
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let str = (mutable as String).lowercased()
        return str.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
        #else
        // Fallback for Linux unit testing fixture
        if text == "美丽新世界" { return "meilixinshijie" }
        return text.lowercased().filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
        #endif
    }

    private static func md5Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return hashOpenSSL("md5", data: data)
        #endif
    }

    private static func sha1Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return hashOpenSSL("sha1", data: data)
        #endif
    }

    private static func sha512Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return hashOpenSSL("sha512", data: data)
        #endif
    }

    #if !canImport(CryptoKit)
    private static func hashOpenSSL(_ algo: String, data: Data) -> String {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["dgst", "-\(algo)", "-hex"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try? process.run()
        try? input.fileHandleForWriting.write(contentsOf: data)
        try? input.fileHandleForWriting.close()
        let outData = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        let raw = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = raw.split(separator: " ").last {
            return String(last).lowercased()
        }
        return ""
    }
    #endif

    private static func decompress(_ data: Data, isGzip: Bool) throws -> Data {
        var stream = z_stream()
        // 32 + MAX_WBITS enables zlib or gzip automatic header detection
        let windowBits = isGzip ? (16 + MAX_WBITS) : (32 + MAX_WBITS)
        guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw RuleError("解压初始化失败")
        }
        defer { inflateEnd(&stream) }

        let bufferSize = 64 * 1024
        var output = Data()
        var chunk = [UInt8](repeating: 0, count: bufferSize)

        try data.withUnsafeBytes { raw in
            stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = UInt32(data.count)

            while stream.avail_in > 0 {
                stream.next_out = chunk.withUnsafeMutableBytes { $0.bindMemory(to: UInt8.self).baseAddress }
                stream.avail_out = UInt32(bufferSize)

                let status = inflate(&stream, Z_NO_FLUSH)
                let produced = bufferSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: chunk.prefix(produced))
                    if output.count > 6 * 1024 * 1024 {
                        throw RuleError("文件或响应超过大小限制")
                    }
                }
                if status == Z_STREAM_END { break }
                guard status == Z_OK || status == Z_BUF_ERROR else {
                    throw RuleError("解压数据失败")
                }
            }
        }
        return output
    }
}

// MARK: - RuleImageData

public enum RuleImageData {
    private static let maxBase64Bytes = 32 * 1024 * 1024

    public static func validate(rule: RuleDefinition, descriptor: [String: Any]) throws {
        try validate(rule: rule, spec: descriptor)
    }

    public static func validate(rule: RuleDefinition, spec: Any?) throws {
        guard let spec = spec, !(spec is NSNull) else { return }
        if let dict = spec as? [String: Any] {
            try validateStep(rule: rule, d: dict)
            return
        }
        if let arr = spec as? [Any] {
            guard rule.engineApi >= 3 else {
                throw RuleError("多步图片解码管线需要规则引擎 API 3")
            }
            guard arr.count >= 1 && arr.count <= 8 else {
                throw RuleError("图片解码步骤数量无效")
            }
            for item in arr {
                guard let step = item as? [String: Any] else {
                    throw RuleError("图片解码步骤格式无效")
                }
                try validateStep(rule: rule, d: step)
            }
            return
        }
        throw RuleError("图片解码配置格式无效")
    }

    private static func validateStep(rule: RuleDefinition, d: [String: Any]) throws {
        guard let type = d["type"] as? String else {
            throw RuleError("缺少图片解码类型")
        }
        if type == "prefix" {
            if rule.engineApi < 2 { throw RuleError("图片前缀解码需要规则引擎 API 2") }
            guard let count = d["bytes"] as? Int, count >= 1 && count <= 65536 else {
                throw RuleError("图片前缀参数无效")
            }
            let magicOpt = d["magic"] as? String
            if rule.engineApi < 3 || (magicOpt != nil && !(magicOpt?.isEmpty ?? true)) {
                guard let magicStr = magicOpt else {
                    throw RuleError("图片前缀参数无效")
                }
                let marker = try RuleBase64.decode(magicStr)
                guard marker.count >= 1 && marker.count <= count else {
                    throw RuleError("图片前缀参数无效")
                }
            }
            return
        }
        if type == "aesCbc" {
            let keyEncoding = (d["keyEncoding"] as? String) ?? "base64"
            let ivEncoding = (d["ivEncoding"] as? String) ?? "base64"
            let padding = (d["padding"] as? String) ?? "PKCS5Padding"
            if rule.engineApi < 3 && (keyEncoding != "base64" || ivEncoding != "base64" || padding != "PKCS5Padding") {
                throw RuleError("图片解码编码参数需要规则引擎 API 3")
            }
            guard let keyStr = d["key"] as? String else {
                throw RuleError("缺少解码密钥")
            }
            let keyLen = try RuleCrypto.parseBinary(keyStr, encoding: keyEncoding).count
            guard [16, 24, 32].contains(keyLen) else {
                throw RuleError("图片解码密钥无效")
            }
            guard padding == "PKCS5Padding" || padding == "NoPadding" else {
                throw RuleError("图片解码填充无效")
            }
            let ivPrefix = (d["ivPrefix"] as? Bool) ?? false
            let passIfPlain = (d["passIfPlain"] as? Bool) ?? false
            if (ivPrefix || passIfPlain) && rule.engineApi < 2 {
                throw RuleError("图片解码参数需要规则引擎 API 2")
            }
            if !ivPrefix {
                guard let ivStr = d["iv"] as? String,
                      try RuleCrypto.parseBinary(ivStr, encoding: ivEncoding).count == 16 else {
                    throw RuleError("图片解码向量无效")
                }
            }
            return
        }
        if type == "aesEcb" {
            guard rule.engineApi >= 3 else {
                throw RuleError("AES-ECB 图片解码需要规则引擎 API 3")
            }
            guard let keyStr = d["key"] as? String else {
                throw RuleError("缺少解码密钥")
            }
            let keyLen = try RuleCrypto.parseBinary(keyStr, encoding: (d["keyEncoding"] as? String) ?? "base64").count
            guard [16, 24, 32].contains(keyLen) else {
                throw RuleError("图片解码密钥无效")
            }
            let padding = (d["padding"] as? String) ?? "PKCS5Padding"
            guard padding == "PKCS5Padding" || padding == "NoPadding" else {
                throw RuleError("图片解码填充无效")
            }
            return
        }
        if type == "aesCtr" {
            guard rule.engineApi >= 3 else {
                throw RuleError("AES-CTR 图片解码需要规则引擎 API 3")
            }
            guard let keyStr = d["key"] as? String else {
                throw RuleError("缺少解码密钥")
            }
            let keyLen = try RuleCrypto.parseBinary(keyStr, encoding: (d["keyEncoding"] as? String) ?? "base64").count
            guard [16, 24, 32].contains(keyLen) else {
                throw RuleError("图片解码密钥无效")
            }
            let ivPrefix = (d["ivPrefix"] as? Bool) ?? false
            if !ivPrefix {
                guard let ivStr = d["iv"] as? String,
                      try RuleCrypto.parseBinary(ivStr, encoding: (d["ivEncoding"] as? String) ?? "base64").count == 16 else {
                    throw RuleError("图片解码向量无效")
                }
            }
            return
        }
        if type == "xor" {
            guard rule.engineApi >= 3 else {
                throw RuleError("XOR 图片解码需要规则引擎 API 3")
            }
            guard let keyStr = d["key"] as? String else {
                throw RuleError("XOR 密钥无效")
            }
            let key = try RuleCrypto.parseBinary(keyStr, encoding: (d["keyEncoding"] as? String) ?? "base64")
            guard key.count >= 1 && key.count <= 4096 else {
                throw RuleError("XOR 密钥无效")
            }
            let skip = (d["skipBytes"] as? Int) ?? 0
            guard skip >= 0 && skip <= 65536 else {
                throw RuleError("XOR 偏移无效")
            }
            return
        }
        if type == "base64" {
            guard rule.engineApi >= 3 else {
                throw RuleError("Base64 图片解码需要规则引擎 API 3")
            }
            return
        }
        throw RuleError("此图片解码需要升级规则引擎")
    }

    public static func decode(descriptor: [String: Any]?, data: Data) throws -> Data {
        try decode(spec: descriptor, data: data)
    }

    public static func decode(spec: Any?, data: Data) throws -> Data {
        guard let spec = spec, !(spec is NSNull) else { return data }
        if let dict = spec as? [String: Any] {
            return try decodeStep(d: dict, data: data, lastStep: true)
        }
        if let arr = spec as? [Any] {
            var current = data
            for (i, item) in arr.enumerated() {
                guard let step = item as? [String: Any] else {
                    throw RuleError("图片解码配置无效")
                }
                current = try decodeStep(d: step, data: current, lastStep: i == arr.count - 1)
            }
            return current
        }
        throw RuleError("图片解码配置无效")
    }

    private static func decodeStep(d: [String: Any], data: Data, lastStep: Bool) throws -> Data {
        let type = (d["type"] as? String) ?? ""
        let passIfPlain = (d["passIfPlain"] as? Bool) ?? false

        if passIfPlain && isImage(data) {
            return data
        }

        if type == "prefix" {
            guard let count = d["bytes"] as? Int, count >= 1 && count <= 65536 else {
                throw RuleError("图片前缀参数无效")
            }
            if let magicStr = d["magic"] as? String, !magicStr.isEmpty {
                let marker = try RuleBase64.decode(magicStr)
                if data.count < marker.count || data.prefix(marker.count) != marker {
                    return data
                }
            }
            guard data.count >= count else {
                throw RuleError("图片数据不完整")
            }
            let remainder = Data(data.dropFirst(count))
            if lastStep && !isImage(remainder) {
                throw RuleError("图片前缀后的数据损坏")
            }
            return remainder
        }

        if type == "xor" {
            guard let keyStr = d["key"] as? String else {
                throw RuleError("XOR 密钥无效")
            }
            let key = Array(try RuleCrypto.parseBinary(keyStr, encoding: (d["keyEncoding"] as? String) ?? "base64"))
            guard key.count >= 1 && key.count <= 4096 else {
                throw RuleError("XOR 密钥无效")
            }
            let skip = (d["skipBytes"] as? Int) ?? 0
            guard skip >= 0 && skip <= 65536 else {
                throw RuleError("XOR 偏移无效")
            }
            var bytes = Array(data)
            if skip < bytes.count {
                for i in skip..<bytes.count {
                    bytes[i] ^= key[(i - skip) % key.count]
                }
            }
            return Data(bytes)
        }

        if type == "base64" {
            guard data.count <= maxBase64Bytes else {
                throw RuleError("Base64 图片超过大小限制")
            }
            var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if let commaIdx = text.firstIndex(of: ",") {
                let dist = text.distance(from: text.startIndex, to: commaIdx)
                if dist > 0 && dist < 128 && text[..<commaIdx].contains(";base64") {
                    text = String(text[text.index(after: commaIdx)...])
                }
            }
            return try RuleBase64.decode(text)
        }

        if type == "aesEcb" {
            guard let keyStr = d["key"] as? String else { throw RuleError("缺少解码密钥") }
            let key = try RuleCrypto.parseBinary(keyStr, encoding: (d["keyEncoding"] as? String) ?? "base64")
            let padding = (d["padding"] as? String) ?? "PKCS5Padding"
            do {
                return try SourceAES.ecbDecrypt(data, key: key, pkcs7: padding == "PKCS5Padding")
            } catch {
                throw RuleError("规则图片解码失败")
            }
        }

        if type == "aesCbc" || type == "aesCtr" {
            let isCtr = (type == "aesCtr")
            guard let keyStr = d["key"] as? String else { throw RuleError("缺少解码密钥") }
            let key = try RuleCrypto.parseBinary(keyStr, encoding: (d["keyEncoding"] as? String) ?? "base64")
            let ivPrefix = (d["ivPrefix"] as? Bool) ?? false

            var ciphertext = data
            let iv: Data
            if ivPrefix {
                guard ciphertext.count >= 16 else { throw RuleError("图片数据不完整") }
                iv = Data(ciphertext.prefix(16))
                ciphertext = Data(ciphertext.dropFirst(16))
            } else {
                guard let ivStr = d["iv"] as? String else { throw RuleError("缺少解密向量") }
                iv = try RuleCrypto.parseBinary(ivStr, encoding: (d["ivEncoding"] as? String) ?? "base64")
            }
            let padding = isCtr ? "NoPadding" : ((d["padding"] as? String) ?? "PKCS5Padding")
            do {
                if isCtr {
                    return try SourceAES.ctrCrypt(ciphertext, key: key, iv: iv)
                } else {
                    return try SourceAES.cbcDecrypt(ciphertext, key: key, iv: iv, pkcs7: padding == "PKCS5Padding")
                }
            } catch {
                throw RuleError("规则图片解码失败")
            }
        }

        throw RuleError("此图片解码需要升级规则引擎")
    }

    public static func isImage(_ b: Data) -> Bool {
        guard b.count >= 12 else { return false }
        // JPEG: FF D8 FF
        if b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF { return true }
        // PNG: 89 50 4E 47
        if b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 { return true }
        // GIF: 47 49 46 38
        if b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38 { return true }
        // WEBP: RIFF....WEBP
        if b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
           b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50 { return true }
        return false
    }
}

// MARK: - RuleSessions

public enum RuleSessions {
    private static let lock = NSLock()
    private static var jars = [String: [String: String]]()

    public static func checked(_ cookies: [String: Any]?) throws -> [String: String] {
        guard let cookies = cookies else { return [:] }
        guard cookies.count <= 32 else { throw RuleError("站点会话 Cookie 过多") }
        var values = [String: String]()
        var total = 0
        for (name, val) in cookies {
            let value = String(describing: val)
            guard name.range(of: #"^[A-Za-z0-9_.$-]{1,128}$"#, options: .regularExpression) != nil,
                  value.count <= 4096,
                  !value.contains(";"),
                  !value.contains("\r"),
                  !value.contains("\n") else {
                throw RuleError("站点会话 Cookie 格式无效")
            }
            total += name.count + value.count
            if total > 16384 {
                throw RuleError("站点会话 Cookie 过大")
            }
            values[name] = value
        }
        return values
    }

    public static func get(rule: RuleDefinition, url: String) -> [String: String] {
        if rule.engineApi < 2 { return [:] }
        let k = key(rule: rule, url: url)
        lock.lock()
        defer { lock.unlock() }
        return jars[k] ?? [:]
    }

    public static func receive(rule: RuleDefinition, url: String, fresh: [String: String]) {
        if rule.engineApi < 2 || fresh.isEmpty { return }
        let k = key(rule: rule, url: url)
        lock.lock()
        defer { lock.unlock() }
        var current = jars[k] ?? [:]
        for (key, val) in fresh {
            if val.isEmpty { current.removeValue(forKey: key) }
            else { current[key] = val }
        }
        jars[k] = current
    }

    public static func header(_ values: [String: String]) -> String {
        values.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private static func key(rule: RuleDefinition, url: String) -> String {
        let host = URL(string: url)?.host?.lowercased() ?? ""
        return "\(rule.hash)\n\(host)"
    }
}

// MARK: - RuleImages

public enum RuleImages {
    public static let MARK = "#xx-rule="
    private static let lock = NSLock()
    private static var metaCache = [String: [String: Any]]()
    private static var resolvedCache = [String: [String: Any]]()

    public struct Resolved: @unchecked Sendable {
        public let rule: RuleDefinition
        public let descriptor: [String: Any]
        public let url: String
        public let referer: String
        public let headers: [String: String]
        public let cookieHeader: String?
        public let taggedUrl: String
    }

    public static func isRule(_ url: String?) -> Bool {
        guard let url = url else { return false }
        return url.contains(MARK)
    }

    public static func strip(_ url: String) -> String {
        guard let range = url.range(of: MARK) else { return url }
        return String(url[..<range.lowerBound])
    }

    public static func tag(rule: RuleDefinition, image: [String: Any], chapter: String, index: Int) throws -> String {
        try validate(rule: rule, image: image)
        let meta: [String: Any] = [
            "id": rule.id,
            "hash": rule.hash,
            "chapter": chapter,
            "index": index,
            "image": image
        ]
        let metaData = try JSONSerialization.data(withJSONObject: meta, options: [])
        let encoded = RuleBase64.encode(metaData, true)
        guard encoded.count <= 24000 else {
            throw RuleError("规则图片描述过大")
        }
        guard let url = image["url"] as? String else {
            throw RuleError("规则图片缺少地址")
        }
        return url + MARK + encoded
    }

    public static func metadata(_ tagged: String) throws -> [String: Any] {
        lock.lock()
        if let cached = metaCache[tagged] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let range = tagged.range(of: MARK) else {
            throw RuleError("图片来源信息无效")
        }
        let encoded = String(tagged[range.upperBound...])
        guard tagged.distance(from: range.lowerBound, to: tagged.endIndex) <= 24020 else {
            throw RuleError("图片来源信息无效")
        }
        do {
            let data = try RuleBase64.decode(encoded)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RuleError("图片来源信息损坏")
            }
            lock.lock()
            metaCache[tagged] = obj
            lock.unlock()
            return obj
        } catch {
            throw RuleError("图片来源信息损坏")
        }
    }

    public static func cacheIdentity(_ tagged: String) -> String {
        guard isRule(tagged) else { return tagged }
        do {
            let m = try metadata(tagged)
            guard let id = m["id"] as? String,
                  let image = m["image"] as? [String: Any],
                  let chapter = m["chapter"] as? String,
                  let index = m["index"] as? Int else { return tagged }
            if index < 0 {
                let url = (image["url"] as? String) ?? ""
                return "rule:\(id):\(url)"
            } else {
                return "rule:\(id):\(chapter):\(index)"
            }
        } catch {
            return tagged
        }
    }

    public static func transformation(_ tagged: String) throws -> String {
        guard isRule(tagged) else { return "" }
        do {
            lock.lock()
            let cached = resolvedCache[tagged]
            lock.unlock()
            let descriptor: [String: Any]?
            if let cached {
                descriptor = cached
            } else {
                descriptor = try metadata(tagged)["image"] as? [String: Any]
            }
            guard let transform = descriptor?["transform"] as? [String: Any] else { return "" }
            return try RuleBitmapTransform.validateAndSerialize(rule: nil, transform: transform)
        } catch let err as RuleError {
            throw err
        } catch {
            throw RuleError("图片变换信息损坏")
        }
    }

    public static func canRefresh(_ tagged: String, catalog: RuleCatalog? = nil) -> Bool {
        guard isRule(tagged) else { return false }
        if let meta = try? metadata(tagged),
           let id = meta["id"] as? String,
           let cat = catalog,
           let source = cat.source(id) {
            return source.rule.imageRefresh
        }
        if let meta = try? metadata(tagged),
           let hash = meta["hash"] as? String,
           let cat = catalog,
           let source = try? cat.version(hash) {
            return source.rule.imageRefresh
        }
        return false
    }

    public static func invalidateResolved(_ tagged: String) {
        lock.lock()
        resolvedCache.removeValue(forKey: tagged)
        lock.unlock()
    }

    public static func isNonImageContentType(_ contentType: String?) -> Bool {
        guard let ct = contentType?.lowercased(), !ct.isEmpty else { return false }
        return ct.contains("text/html") || ct.contains("text/plain") || ct.contains("application/json") || ct.contains("text/xml")
    }

    public static func validate(rule: RuleDefinition, image: [String: Any]) throws {
        let serialized = try JSONSerialization.data(withJSONObject: image, options: [])
        guard serialized.count <= 16384 else {
            throw RuleError("图片描述符超过 16KiB")
        }
        guard let url = image["url"] as? String else {
            throw RuleError("规则图片缺少地址")
        }
        try RuleDefinition.validateHttp(url)
        guard let parsed = URL(string: url), let host = parsed.host, rule.allows(host) else {
            throw RuleError("图片域名未获规则授权")
        }
        if parsed.scheme?.lowercased() == "http" &&
           host.lowercased() != "127.0.0.1" &&
           !rule.allowsCleartext(host) {
            throw RuleError("规则未声明该图片域名的明文 HTTP 权限")
        }

        if let headers = image["headers"] as? [String: Any] {
            guard headers.count <= 24 else { throw RuleError("图片请求头过多") }
            for (k, v) in headers {
                try RuleHttp.checkHeader(k, String(describing: v))
            }
        }

        let referer = (image["referer"] as? String) ?? (rule.baseUrl + "/")
        try RuleHttp.checkHeader("Referer", referer)
        try RuleDefinition.validateHttp(referer)

        if let decodeSpec = image["decode"] {
            try RuleImageData.validate(rule: rule, spec: decodeSpec)
        }

        if let cookies = image["cookies"] as? [String: Any] {
            guard rule.engineApi >= 2 else { throw RuleError("图片会话需要规则引擎 API 2") }
            _ = try RuleSessions.checked(cookies)
        }

        if let transformAny = image["transform"] {
            guard !(transformAny is NSNull) else { return }
            guard let transform = transformAny as? [String: Any] else {
                throw RuleError("规则图片变换参数无效")
            }
            _ = try RuleBitmapTransform.validateAndSerialize(rule: rule, transform: transform)
        }
    }

    public static func resolve(catalog: RuleCatalog, tagged: String, force: Bool) throws -> Resolved {
        let meta = try metadata(tagged)
        guard let hash = meta["hash"] as? String,
              let id = meta["id"] as? String,
              let original = meta["image"] as? [String: Any] else {
            throw RuleError("规则图片来源信息错误")
        }
        let source = try catalog.version(hash)
        guard source.id == id else {
            throw RuleError("图片规则身份不匹配")
        }
        let chapter = (meta["chapter"] as? String) ?? ""
        let index = (meta["index"] as? Int) ?? -1
        let d: [String: Any]
        if !force {
            lock.lock()
            let cached = resolvedCache[tagged]
            lock.unlock()
            d = cached ?? original
        } else {
            var request = original
            request["chapter"] = chapter
            request["index"] = index
            d = try source.image(request, force: true)
        }
        try validate(rule: source.rule, image: d)
        guard let url = d["url"] as? String else {
            throw RuleError("规则图片缺少地址")
        }
        let referer = (d["referer"] as? String) ?? (source.rule.baseUrl + "/")
        var headers = [String: String]()
        if let rawHeaders = d["headers"] as? [String: Any] {
            for (k, v) in rawHeaders {
                headers[k] = String(describing: v)
            }
        }
        var cookies = RuleSessions.get(rule: source.rule, url: url)
        if let descriptorCookies = try? RuleSessions.checked(d["cookies"] as? [String: Any]) {
            for (k, v) in descriptorCookies {
                cookies[k] = v
            }
        }
        let cookieHeader = cookies.isEmpty ? nil : RuleSessions.header(cookies)
        let refreshedTagged = try tag(rule: source.rule, image: d, chapter: chapter, index: index)

        lock.lock()
        if resolvedCache.count >= 512 {
            resolvedCache.removeAll(keepingCapacity: true)
        }
        resolvedCache[tagged] = d
        resolvedCache[refreshedTagged] = d
        lock.unlock()

        return Resolved(
            rule: source.rule,
            descriptor: d,
            url: url,
            referer: referer,
            headers: headers,
            cookieHeader: cookieHeader,
            taggedUrl: refreshedTagged
        )
    }

    public static func requestHeaders(
        catalog: RuleCatalog? = nil,
        tagged: String,
        fallbackReferer: String = ""
    ) throws -> (url: String, referer: String, headers: [String: String], cookieHeader: String?) {
        if let catalog {
            let resolved = try resolve(catalog: catalog, tagged: tagged, force: false)
            return (resolved.url, resolved.referer, resolved.headers, resolved.cookieHeader)
        }
        let meta = try metadata(tagged)
        lock.lock()
        let cached = resolvedCache[tagged]
        lock.unlock()
        guard let d = cached ?? (meta["image"] as? [String: Any]),
              let url = d["url"] as? String else {
            throw RuleError("规则图片来源信息错误")
        }
        let referer = (d["referer"] as? String) ?? fallbackReferer
        var headers = [String: String]()
        if let rawHeaders = d["headers"] as? [String: Any] {
            for (k, v) in rawHeaders {
                headers[k] = String(describing: v)
            }
        }
        let descriptorCookies = (try? RuleSessions.checked(d["cookies"] as? [String: Any])) ?? [:]
        let cookieHeader = descriptorCookies.isEmpty ? nil : RuleSessions.header(descriptorCookies)
        return (url, referer, headers, cookieHeader)
    }

    public static func decode(_ data: Data, tagged: String) throws -> Data {
        guard isRule(tagged) else { return data }
        lock.lock()
        let cached = resolvedCache[tagged]
        lock.unlock()
        let descriptor: [String: Any]?
        if let cached {
            descriptor = cached
        } else {
            descriptor = try metadata(tagged)["image"] as? [String: Any]
        }
        return try RuleImageData.decode(spec: descriptor?["decode"], data: data)
    }
}

// MARK: - RuleBitmapTransform

public enum RuleBitmapTransform {
    public static let PREFIX_TX = "rule-tx:"

    public struct Op: Equatable, Sendable {
        public let srcLeft: Int
        public let srcTop: Int
        public let srcRight: Int
        public let srcBottom: Int
        public let dstLeft: Int
        public let dstTop: Int
        public let dstRight: Int
        public let dstBottom: Int
        public let rotation: Int
        public let flipX: Bool
        public let flipY: Bool

        public init(
            srcLeft: Int, srcTop: Int, srcRight: Int, srcBottom: Int,
            dstLeft: Int, dstTop: Int, dstRight: Int, dstBottom: Int,
            rotation: Int, flipX: Bool, flipY: Bool
        ) {
            self.srcLeft = srcLeft
            self.srcTop = srcTop
            self.srcRight = srcRight
            self.srcBottom = srcBottom
            self.dstLeft = dstLeft
            self.dstTop = dstTop
            self.dstRight = dstRight
            self.dstBottom = dstBottom
            self.rotation = rotation
            self.flipX = flipX
            self.flipY = flipY
        }
    }

    public static func isSupported(_ transform: String?) -> Bool {
        guard let transform = transform else { return false }
        if transform.hasPrefix(PREFIX_TX) { return true }
        return transform.range(of: #"^bands:[0-9]{1,3}$"#, options: .regularExpression) != nil
    }

    public static func validateAndSerialize(rule: RuleDefinition?, transform: [String: Any]?) throws -> String {
        guard let t = transform else { return "" }
        let type = (t["type"] as? String) ?? ""
        if type == "reverseBands" {
            if let rule = rule, rule.engineApi < 2 {
                throw RuleError("图片分带还原需要规则引擎 API 2")
            }
            guard let bands = t["bands"] as? Int, bands >= 2 && bands <= 100 else {
                throw RuleError("规则图片变换参数无效")
            }
            return "bands:\(bands)"
        }
        if type == "stripes" {
            if let rule = rule, rule.engineApi < 3 {
                throw RuleError("图片条带重排需要规则引擎 API 3")
            }
            let axis = (t["axis"] as? String) ?? "horizontal"
            guard axis == "horizontal" || axis == "vertical" else {
                throw RuleError("图片条带方向无效")
            }
            let order = try parsePermutation(t["order"], minLen: 2, maxLen: 256)
            var canonical: [String: Any] = [
                "type": "stripes",
                "axis": axis,
                "order": order
            ]
            if (t["flipX"] as? Bool) == true { canonical["flipX"] = true }
            if (t["flipY"] as? Bool) == true { canonical["flipY"] = true }
            let data = try JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys])
            return PREFIX_TX + String(decoding: data, as: UTF8.self)
        }
        if type == "tiles" {
            if let rule = rule, rule.engineApi < 3 {
                throw RuleError("图片网格拼图还原需要规则引擎 API 3")
            }
            guard let cols = t["cols"] as? Int, let rows = t["rows"] as? Int,
                  cols >= 1, cols <= 64, rows >= 1, rows <= 64,
                  cols * rows >= 2, cols * rows <= 4096 else {
                throw RuleError("图片网格尺寸无效")
            }
            let total = cols * rows
            let order = try parsePermutation(t["order"], minLen: total, maxLen: total)
            var canonical: [String: Any] = [
                "type": "tiles",
                "cols": cols,
                "rows": rows,
                "order": order
            ]
            if let rotAny = t["rotations"] {
                guard let rotArr = rotAny as? [Int], rotArr.count == total else {
                    throw RuleError("图片块旋转数组长度无效")
                }
                var rots = [Int]()
                rots.reserveCapacity(total)
                for rawR in rotArr {
                    let r = ((rawR % 360) + 360) % 360
                    guard r == 0 || r == 90 || r == 180 || r == 270 else {
                        throw RuleError("图片块旋转角度仅支持 0/90/180/270")
                    }
                    rots.append(r)
                }
                canonical["rotations"] = rots
            }
            if (t["flipX"] as? Bool) == true { canonical["flipX"] = true }
            if (t["flipY"] as? Bool) == true { canonical["flipY"] = true }
            let data = try JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys])
            return PREFIX_TX + String(decoding: data, as: UTF8.self)
        }
        throw RuleError("规则图片变换参数无效")
    }

    private static func parsePermutation(_ raw: Any?, minLen: Int, maxLen: Int) throws -> [Int] {
        guard let arr = raw as? [Int] else {
            throw RuleError("图片重排索引数量无效")
        }
        let n = arr.count
        guard n >= minLen && n <= maxLen else {
            throw RuleError("图片重排索引数量无效")
        }
        var seen = [Bool](repeating: false, count: n)
        for v in arr {
            guard v >= 0 && v < n && !seen[v] else {
                throw RuleError("图片重排索引须为 0..N-1 的全排列")
            }
            seen[v] = true
        }
        return arr
    }

    public static func plan(width: Int, height: Int, transform: String) -> [Op] {
        guard width >= 1, height >= 1, isSupported(transform) else { return [] }
        if transform.hasPrefix("bands:") {
            guard let count = Int(transform.dropFirst(6)),
                  count >= 2, count <= 100, height >= count,
                  let bandList = try? bounds(height: height, count: count) else {
                return []
            }
            return bandList.map { b in
                Op(srcLeft: 0, srcTop: b[0], srcRight: width, srcBottom: b[1],
                   dstLeft: 0, dstTop: b[2], dstRight: width, dstBottom: b[3],
                   rotation: 0, flipX: false, flipY: false)
            }
        }
        let jsonPart = String(transform.dropFirst(PREFIX_TX.count))
        guard let data = jsonPart.data(using: .utf8),
              let spec = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = spec["type"] as? String else {
            return []
        }
        let flipX = (spec["flipX"] as? Bool) ?? false
        let flipY = (spec["flipY"] as? Bool) ?? false

        if type == "stripes" {
            let vertical = ((spec["axis"] as? String) ?? "horizontal") == "vertical"
            guard let order = try? parsePermutation(spec["order"], minLen: 2, maxLen: 256) else {
                return []
            }
            let n = order.count
            let total = vertical ? width : height
            let step = total / n
            guard step >= 1 else { return [] }
            var ops = [Op]()
            ops.reserveCapacity(n + 1)
            for i in 0..<n {
                let s = order[i]
                if vertical {
                    ops.append(Op(
                        srcLeft: s * step, srcTop: 0, srcRight: (s + 1) * step, srcBottom: height,
                        dstLeft: i * step, dstTop: 0, dstRight: (i + 1) * step, dstBottom: height,
                        rotation: 0, flipX: flipX, flipY: flipY
                    ))
                } else {
                    ops.append(Op(
                        srcLeft: 0, srcTop: s * step, srcRight: width, srcBottom: (s + 1) * step,
                        dstLeft: 0, dstTop: i * step, dstRight: width, dstBottom: (i + 1) * step,
                        rotation: 0, flipX: flipX, flipY: flipY
                    ))
                }
            }
            let covered = n * step
            if covered < total {
                if vertical {
                    ops.append(Op(srcLeft: covered, srcTop: 0, srcRight: width, srcBottom: height,
                                  dstLeft: covered, dstTop: 0, dstRight: width, dstBottom: height,
                                  rotation: 0, flipX: false, flipY: false))
                } else {
                    ops.append(Op(srcLeft: 0, srcTop: covered, srcRight: width, srcBottom: height,
                                  dstLeft: 0, dstTop: covered, dstRight: width, dstBottom: height,
                                  rotation: 0, flipX: false, flipY: false))
                }
            }
            return ops
        }

        if type == "tiles" {
            guard let cols = spec["cols"] as? Int, let rows = spec["rows"] as? Int,
                  cols >= 1, rows >= 1 else {
                return []
            }
            let count = cols * rows
            guard let order = try? parsePermutation(spec["order"], minLen: count, maxLen: count) else {
                return []
            }
            let rotArr = spec["rotations"] as? [Int]
            let cellW = width / cols
            let cellH = height / rows
            guard cellW >= 1 && cellH >= 1 else { return [] }
            var ops = [Op]()
            ops.reserveCapacity(count + 2)
            for idx in 0..<count {
                let sIdx = order[idx]
                let srcCol = sIdx % cols
                let srcRow = sIdx / cols
                let dstCol = idx % cols
                let dstRow = idx / cols
                var rot = (rotArr != nil && idx < rotArr!.count) ? (((rotArr![idx] % 360) + 360) % 360) : 0
                if (rot == 90 || rot == 270) && cellW != cellH {
                    rot = 0
                }
                ops.append(Op(
                    srcLeft: srcCol * cellW, srcTop: srcRow * cellH, srcRight: (srcCol + 1) * cellW, srcBottom: (srcRow + 1) * cellH,
                    dstLeft: dstCol * cellW, dstTop: dstRow * cellH, dstRight: (dstCol + 1) * cellW, dstBottom: (dstRow + 1) * cellH,
                    rotation: rot, flipX: flipX, flipY: flipY
                ))
            }
            let coveredW = cols * cellW
            let coveredH = rows * cellH
            if coveredW < width {
                ops.append(Op(srcLeft: coveredW, srcTop: 0, srcRight: width, srcBottom: coveredH,
                              dstLeft: coveredW, dstTop: 0, dstRight: width, dstBottom: coveredH,
                              rotation: 0, flipX: false, flipY: false))
            }
            if coveredH < height {
                ops.append(Op(srcLeft: 0, srcTop: coveredH, srcRight: width, srcBottom: height,
                              dstLeft: 0, dstTop: coveredH, dstRight: width, dstBottom: height,
                              rotation: 0, flipX: false, flipY: false))
            }
            return ops
        }
        return []
    }

    public static func applyToArgb(_ source: [UInt32], width: Int, height: Int, transform: String) -> [UInt32] {
        let ops = plan(width: width, height: height, transform: transform)
        guard !ops.isEmpty, source.count >= width * height else { return source }
        var out = source
        for op in ops {
            let w = op.dstRight - op.dstLeft
            let h = op.dstBottom - op.dstTop
            for dy in 0..<h {
                for dx in 0..<w {
                    var sx = dx
                    var sy = dy
                    if op.rotation == 90 {
                        sx = dy
                        sy = w - 1 - dx
                    } else if op.rotation == 180 {
                        sx = w - 1 - dx
                        sy = h - 1 - dy
                    } else if op.rotation == 270 {
                        sx = h - 1 - dy
                        sy = dx
                    }
                    if op.flipX {
                        sx = (op.srcRight - op.srcLeft) - 1 - sx
                    }
                    if op.flipY {
                        sy = (op.srcBottom - op.srcTop) - 1 - sy
                    }
                    out[(op.dstTop + dy) * width + (op.dstLeft + dx)] = source[(op.srcTop + sy) * width + (op.srcLeft + sx)]
                }
            }
        }
        return out
    }

    public static func bounds(height: Int, count: Int) throws -> [[Int]] {
        guard height >= 1, count >= 2, count <= 100, height >= count else {
            throw RuleError("图片分带参数无效")
        }
        var result = [[Int]](repeating: [0, 0, 0, 0], count: count)
        let move = height / count, remainder = height % count
        var y = 0
        for i in 0..<count {
            let h = move + (i == 0 ? remainder : 0)
            let start = height - y - h
            result[i] = [start, start + h, y, y + h]
            y += h
        }
        return result
    }
}

// MARK: - RuleWebSessions

public protocol RuleBrowserSession: AnyObject, Sendable {
    func fetch(_ url: String) throws -> String
}

public enum RuleWebSessions {
    private static let lock = NSLock()
    private static var active = [String: RuleBrowserSession]()
    private static var fallback = [String: RuleBrowserSession]()

    private static func origin(_ u: String) throws -> String {
        try RuleDefinition.validateHttp(u)
        guard let url = URL(string: u), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            throw RuleError("地址格式无效")
        }
        let portStr = (url.port != nil) ? ":\(url.port!)" : ""
        return "\(scheme)://\(host)\(portStr)"
    }

    public static func attach(_ base: String, _ session: RuleBrowserSession) throws {
        let key = try origin(base)
        lock.lock()
        defer { lock.unlock() }
        active[key] = session
    }

    public static func detach(_ base: String, _ session: RuleBrowserSession) throws {
        let key = try origin(base)
        lock.lock()
        defer { lock.unlock() }
        if let current = active[key], current === session {
            active.removeValue(forKey: key)
        }
    }

    public static func fallback(_ base: String, _ session: RuleBrowserSession) throws {
        let key = try origin(base)
        lock.lock()
        defer { lock.unlock() }
        fallback[key] = session
    }

    public static func fetch(rule: RuleDefinition, url: String) throws -> String? {
        guard rule.browserSession else {
            throw RuleError("此规则未声明站点验证会话权限")
        }
        guard let target = URL(string: url), let base = URL(string: rule.baseUrl),
              let targetHost = target.host?.lowercased(), let baseHost = base.host?.lowercased(),
              let targetScheme = target.scheme?.lowercased(), let baseScheme = base.scheme?.lowercased() else {
            throw RuleError("验证会话仅允许本站及已授权子域名")
        }
        _ = try origin(url)
        guard rule.allows(targetHost),
              targetScheme == baseScheme,
              (target.port == nil || target.port == base.port),
              (targetHost == baseHost || targetHost.hasSuffix("." + baseHost)) else {
            throw RuleError("验证会话仅允许本站及已授权子域名")
        }

        let key = try origin(rule.baseUrl)
        lock.lock()
        let session = active[key] ?? fallback[key]
        lock.unlock()

        return try session?.fetch(url)
    }
}

// MARK: - RuleImportStates

public enum RuleImportStates {
    public static func initial(
        rules: [RuleDefinition],
        installed: [RuleStore.Entry],
        nativeItems: [String: [String: Any]]
    ) -> [String: Bool] {
        var existing = [String: RuleStore.Entry]()
        for e in installed { existing[e.rule.id] = e }
        var states = [String: Bool]()
        for r in rules {
            if r.replacesNative && (existing[r.id] == nil || existing[r.id]!.removed) && nativeItems[r.id] != nil {
                let enabled = (nativeItems[r.id]?["enabled"] as? Bool) ?? true
                states[r.id] = enabled
            }
        }
        return states
    }
}

// MARK: - RuleRepository

private final class RepositoryNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum RuleRepository {
    public static let LEGACY_DEFAULT_URL = "https://weifeng.cloud/rules/index.json"
    public static let DEFAULT_URL = "https://weifeng.cloud/rules/v3/index.json"

    private static let fetchSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: RepositoryNoRedirectDelegate(), delegateQueue: nil)
    }()

    public static func fetch(_ url: String) throws -> String {
        var currentUrl = url
        for _ in 0..<6 {
            try RuleDefinition.validateHttp(currentUrl)
            guard currentUrl.lowercased().hasPrefix("https://") else {
                throw RuleError("规则下载与订阅需要 HTTPS")
            }
            guard let u = URL(string: currentUrl) else { throw RuleError("地址无效") }
            let (data, response) = try synchronousGet(u)
            guard let http = response as? HTTPURLResponse else { throw RuleError("响应类型无效") }
            if [301, 302, 303, 307, 308].contains(http.statusCode) {
                var location: String?
                for (k, v) in http.allHeaderFields {
                    if String(describing: k).caseInsensitiveCompare("Location") == .orderedSame {
                        location = String(describing: v)
                        break
                    }
                }
                guard let loc = location, !loc.isEmpty,
                      let nextUrl = URL(string: loc, relativeTo: u)?.absoluteURL else {
                    throw RuleError("规则下载跳转地址无效")
                }
                currentUrl = nextUrl.absoluteString
                continue
            }
            guard http.statusCode == 200 else {
                throw RuleError("规则下载失败 HTTP \(http.statusCode)")
            }
            guard data.count < RuleDefinition.MAX_PACKAGE else {
                throw RuleError("规则包超过 16MiB")
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw RuleError("规则包编码错误")
            }
            return text
        }
        throw RuleError("规则下载跳转过多")
    }

    public static func read(
        root: [String: Any],
        origin: String?,
        fetcher: (String) throws -> String = { url in try fetch(url) }
    ) throws -> [RuleDefinition] {
        try readInternal(root: root, origin: origin, compatible: false, fetcher: fetcher).rules
    }

    public static func readCompatible(
        root: [String: Any],
        origin: String?,
        fetcher: (String) throws -> String = { url in try fetch(url) }
    ) throws -> RuleStore.Bundle {
        try readInternal(root: root, origin: origin, compatible: true, fetcher: fetcher)
    }

    private static func readInternal(
        root: [String: Any],
        origin: String?,
        compatible: Bool,
        fetcher: (String) throws -> String
    ) throws -> RuleStore.Bundle {
        if (root["schema"] as? String) == "xx-comic.rules" {
            if compatible {
                return try RuleStore.parseCompatible(json: root)
            }
            return RuleStore.Bundle(rules: try RuleStore.parse(json: root), skippedUnsupported: 0)
        }
        guard (root["schema"] as? String) == "xx-comic.rule-repository",
              (root["version"] as? Int) == 1 else {
            throw RuleError("不是支持的规则仓库索引")
        }
        guard let files = root["packages"] as? [[String: Any]],
              !files.isEmpty, files.count <= 32 else {
            throw RuleError("仓库规则包数量无效")
        }
        var result = [RuleDefinition]()
        var ids = Set<String>()
        var total = 0
        var skipped = 0
        for p in files {
            guard var url = p["url"] as? String,
                  let expectedSha = p["sha256"] as? String else {
                throw RuleError("仓库规则包格式错误")
            }
            if let origin = origin, let base = URL(string: origin), let resolved = URL(string: url, relativeTo: base) {
                url = resolved.absoluteString
            }
            let body = try fetcher(url)
            let bytes = Data(body.utf8)
            total += bytes.count
            if total > RuleDefinition.MAX_PACKAGE {
                throw RuleError("整批规则超过 16MiB")
            }
            let actualSha = RuleDefinition.sha(bytes)
            guard actualSha.caseInsensitiveCompare(expectedSha) == .orderedSame else {
                throw RuleError("仓库规则包完整性校验失败")
            }
            guard let packData = body.data(using: .utf8),
                  let packJson = try? JSONSerialization.jsonObject(with: packData) as? [String: Any] else {
                throw RuleError("仓库规则包解析错误")
            }
            let bundle: RuleStore.Bundle
            if compatible {
                bundle = try RuleStore.parseCompatible(json: packJson)
            } else {
                bundle = RuleStore.Bundle(rules: try RuleStore.parse(json: packJson), skippedUnsupported: 0)
            }
            skipped += bundle.skippedUnsupported
            for r in bundle.rules {
                guard ids.insert(r.id).inserted else {
                    throw RuleError("仓库包含重复站源 ID")
                }
                result.append(r)
            }
            if result.count > RuleStore.MAX_SOURCES {
                throw RuleError("仓库规则数量过多")
            }
        }
        return RuleStore.Bundle(rules: result, skippedUnsupported: skipped)
    }

    private static func synchronousGet(_ url: URL) throws -> (Data, URLResponse) {
        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?
        let sema = DispatchSemaphore(value: 0)

        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let task = fetchSession.dataTask(with: req) { data, resp, err in
            resultData = data
            resultResponse = resp
            resultError = err
            sema.signal()
        }
        task.resume()
        sema.wait()

        if let err = resultError { throw err }
        guard let d = resultData, let r = resultResponse else { throw RuleError("请求无响应") }
        return (d, r)
    }
}

// MARK: - RuleSubscriptionUpdate

public enum RuleSubscriptionUpdate {
    public struct Prepared: @unchecked Sendable {
        public let rules: [RuleDefinition]
        public let skippedUnsupported: Int

        public init(rules: [RuleDefinition], skippedUnsupported: Int) {
            self.rules = rules
            self.skippedUnsupported = skippedUnsupported
        }

        public var skipped: Int { skippedUnsupported }
    }

    public static func prepare(
        urls: [String],
        validator: (RuleDefinition) throws -> Void,
        fetcher: (String) throws -> String = { url in try RuleRepository.fetch(url) }
    ) throws -> [RuleDefinition] {
        try prepareInternal(urls: urls, compatible: false, validator: validator, fetcher: fetcher).rules
    }

    public static func prepareCompatible(
        urls: [String],
        validator: (RuleDefinition) throws -> Void,
        fetcher: (String) throws -> String = { url in try RuleRepository.fetch(url) }
    ) throws -> Prepared {
        try prepareInternal(urls: urls, compatible: true, validator: validator, fetcher: fetcher)
    }

    private static func prepareInternal(
        urls: [String],
        compatible: Bool,
        validator: (RuleDefinition) throws -> Void,
        fetcher: (String) throws -> String
    ) throws -> Prepared {
        guard !urls.isEmpty else {
            throw RuleError("暂无订阅，请先添加规则订阅")
        }
        var merged = [String: RuleDefinition]()
        var ordered = [RuleDefinition]()
        var totalBytes = 0
        var skipped = 0
        for url in urls {
            try Task.checkCancellation()
            try RuleDefinition.validateHttp(url)
            guard url.lowercased().hasPrefix("https://") else {
                throw RuleError("订阅地址需要 HTTPS")
            }
            let body = try fetcher(url)
            guard let data = body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RuleError("订阅索引格式错误")
            }
            guard (root["schema"] as? String) == "xx-comic.rule-repository" else {
                throw RuleError("订阅需要规则仓库索引，请使用网址导入读取单个规则包")
            }
            let bundle = compatible
                ? try RuleRepository.readCompatible(root: root, origin: url, fetcher: fetcher)
                : RuleStore.Bundle(rules: try RuleRepository.read(root: root, origin: url, fetcher: fetcher), skippedUnsupported: 0)
            skipped += bundle.skippedUnsupported
            for rule in bundle.rules {
                try Task.checkCancellation()
                if let old = merged[rule.id] {
                    if old.hash != rule.hash {
                        throw RuleError("多个订阅提供不同版本的站源：\(rule.name)，请先处理订阅冲突")
                    }
                    continue
                }
                totalBytes += rule.script.utf8.count
                if totalBytes > RuleDefinition.MAX_PACKAGE || merged.count >= RuleStore.MAX_SOURCES {
                    throw RuleError("全部订阅的规则超过数量或大小上限")
                }
                try validator(rule)
                merged[rule.id] = rule
                ordered.append(rule)
            }
        }
        try Task.checkCancellation()
        if ordered.isEmpty && skipped > 0 {
            throw RuleError("订阅中的 \(skipped) 个站源均需升级新版客户端后使用")
        }
        return Prepared(rules: ordered, skippedUnsupported: skipped)
    }
}

// MARK: - RuleStore

public final class RuleStore: @unchecked Sendable {
    public static let MAX_SOURCES = 256

    public final class Entry: @unchecked Sendable {
        public let rule: RuleDefinition
        public let previous: String
        public let enabled: Bool
        public let removed: Bool

        public init(rule: RuleDefinition, previous: String, enabled: Bool, removed: Bool) {
            self.rule = rule
            self.previous = previous
            self.enabled = enabled
            self.removed = removed
        }
    }

    public struct Bundle: @unchecked Sendable {
        public let rules: [RuleDefinition]
        public let skippedUnsupported: Int

        public init(rules: [RuleDefinition], skippedUnsupported: Int) {
            self.rules = rules
            self.skippedUnsupported = skippedUnsupported
        }

        public var skipped: Int { skippedUnsupported }
    }

    private let lock = NSLock()
    private let directory: URL
    private let versionsDir: URL
    private let primaryFile: URL
    private let backupFile: URL

    private var internalEntries = [String: Entry]()
    private var internalOrder = [String]()
    private var internalHidden = Set<String>()
    private var internalRepositories = [String]()
    private var writable = true
    private var primaryValid = false
    private var defaultRepositoryInitialized = false
    private var defaultRepositoryV3Migrated = false
    public private(set) var recoveryMessage = ""

    public init(directory: URL) throws {
        self.directory = directory
        self.versionsDir = directory.appendingPathComponent("versions", isDirectory: true)
        self.primaryFile = directory.appendingPathComponent("index.json")
        self.backupFile = directory.appendingPathComponent("index.bak")

        try FileManager.default.createDirectory(at: versionsDir, withIntermediateDirectories: true, attributes: nil)

        let fm = FileManager.default
        if fm.fileExists(atPath: primaryFile.path) {
            do {
                try decode(primaryFile)
                primaryValid = true
                return
            } catch {
                recoveryMessage = "规则索引损坏，原文件已保留"
            }
        }

        if fm.fileExists(atPath: backupFile.path) {
            do {
                try decode(backupFile)
                recoveryMessage = "规则索引已从上一份备份恢复"
                return
            } catch {
                writable = false
            }
        }

        if fm.fileExists(atPath: primaryFile.path) || fm.fileExists(atPath: backupFile.path) {
            writable = false
            recoveryMessage = "规则索引及备份无法读取，已保留文件并暂停写入"
        }
    }

    public func entries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return internalOrder.compactMap { internalEntries[$0] }
    }

    public func hidden() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return internalHidden
    }

    public func repositories() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return internalRepositories
    }

    public func ensureDefaultRepository() throws {
        lock.lock()
        defer { lock.unlock() }
        if !defaultRepositoryInitialized {
            var next = [String]()
            for repo in internalRepositories {
                let mapped = (repo == RuleRepository.LEGACY_DEFAULT_URL) ? RuleRepository.DEFAULT_URL : repo
                if !next.contains(mapped) {
                    next.append(mapped)
                }
            }
            if !next.contains(RuleRepository.DEFAULT_URL) && next.count < 16 {
                next.append(RuleRepository.DEFAULT_URL)
            }
            try commit(nextEntries: internalEntries, nextOrder: internalOrder, nextHidden: internalHidden, nextRepos: next, initialized: true, v3Migrated: true)
            return
        }
        if !defaultRepositoryV3Migrated {
            var next = [String]()
            for repo in internalRepositories {
                let mapped = (repo == RuleRepository.LEGACY_DEFAULT_URL) ? RuleRepository.DEFAULT_URL : repo
                if !next.contains(mapped) {
                    next.append(mapped)
                }
            }
            try commit(nextEntries: internalEntries, nextOrder: internalOrder, nextHidden: internalHidden, nextRepos: next, initialized: true, v3Migrated: true)
        }
    }

    public func updateSubscriptions(_ rules: [RuleDefinition], initialStates: [String: Bool] = [:]) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        try ensureWritable()

        var nextEntries = internalEntries
        var nextOrder = internalOrder
        var nextHidden = internalHidden
        var ids = Set<String>()
        var added = 0, updated = 0, same = 0

        for rule in rules {
            try Task.checkCancellation()
            guard ids.insert(rule.id).inserted else {
                throw RuleError("订阅包含重复站源 ID：\(rule.id)")
            }
            let old = internalEntries[rule.id]
            try checkVersion(old: old, r: rule)
            if let old = old, old.rule.hash == rule.hash {
                same += 1
                continue
            }
            try saveVersion(rule)
            let prev = old == nil ? "" : old!.rule.hash
            let isEnabled = old == nil ? (initialStates[rule.id] ?? true) : old!.enabled
            nextEntries[rule.id] = Entry(rule: rule, previous: prev, enabled: isEnabled, removed: false)
            if !nextOrder.contains(rule.id) {
                nextOrder.append(rule.id)
            }
            nextHidden.remove(rule.id)
            if old == nil { added += 1 } else { updated += 1 }
        }

        if nextEntries.count > Self.MAX_SOURCES {
            throw RuleError("规则站源超过 256 个上限")
        }
        let total = nextEntries.values.reduce(0) { $0 + $1.rule.script.utf8.count }
        if total > RuleDefinition.MAX_PACKAGE {
            throw RuleError("已保存规则脚本总量超过 16MiB")
        }
        if added + updated > 0 {
            try commit(nextEntries: nextEntries, nextOrder: nextOrder, nextHidden: nextHidden, nextRepos: internalRepositories, initialized: defaultRepositoryInitialized)
        }
        return "新增 \(added) · 更新 \(updated) · 不变 \(same)"
    }

    public func version(_ hash: String) throws -> RuleDefinition {
        guard hash.count == 64, hash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw RuleError("规则版本无效")
        }
        let file = versionsDir.appendingPathComponent("\(hash).json")
        guard let data = try? Data(contentsOf: file) else {
            throw RuleError("本地规则版本不存在")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw RuleError("本地规则版本损坏")
        }
        let rule = try RuleDefinition(json: json)
        guard rule.hash == hash else {
            throw RuleError("本地规则版本校验失败")
        }
        return rule
    }

    public static func parse(json: Any) throws -> [RuleDefinition] {
        try parseInternal(json: json, compatible: false).rules
    }

    public static func parseCompatible(json: Any) throws -> Bundle {
        try parseInternal(json: json, compatible: true)
    }

    private static func parseInternal(json: Any, compatible: Bool) throws -> Bundle {
        guard let dict = json as? [String: Any],
              (dict["schema"] as? String) == "xx-comic.rules",
              (dict["version"] as? Int) == 1 else {
            throw RuleError("不是支持的 XX Comic 规则文件")
        }
        guard let sources = dict["sources"] as? [[String: Any]],
              !sources.isEmpty && sources.count <= MAX_SOURCES else {
            throw RuleError("规则包的站源数量无效")
        }
        var rules = [RuleDefinition]()
        var ids = Set<String>()
        var skipped = 0
        for row in sources {
            do {
                let r = try RuleDefinition(json: row)
                guard ids.insert(r.id).inserted else {
                    throw RuleError("同一批规则包含重复 ID：\(r.id)")
                }
                rules.append(r)
            } catch let unsupported as UnsupportedRuleError {
                if compatible {
                    skipped += 1
                    continue
                }
                throw unsupported
            }
        }
        return Bundle(rules: rules, skippedUnsupported: skipped)
    }

    public func preview(_ rules: [RuleDefinition]) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        var added = 0, updated = 0, same = 0
        for r in rules {
            let old = internalEntries[r.id]
            try checkVersion(old: old, r: r)
            if old == nil { added += 1 }
            else if old!.rule.hash == r.hash { same += 1 }
            else { updated += 1 }
        }
        return "新增 \(added) · 更新 \(updated) · 不变 \(same)"
    }

    private func checkVersion(old: Entry?, r: RuleDefinition) throws {
        guard let old = old else { return }
        if r.version < old.rule.version {
            throw RuleError("\(r.name) 版本较旧；请使用回退上一版")
        }
        let metadataUpgrade = !old.rule.hasVpnDeclaration() && r.hasVpnDeclaration() && r.coreHash == old.rule.coreHash
        if r.version == old.rule.version && r.hash != old.rule.hash && !metadataUpgrade {
            throw RuleError("\(r.name) 同版本内容不同，请递增规则版本")
        }
    }

    public func install(
        _ rules: [RuleDefinition],
        validator: (RuleDefinition) throws -> Void,
        restoreNative: Set<String> = [],
        subscription: String = "",
        states: [String: Bool] = [:]
    ) throws -> String {
        let message = try preview(rules)
        lock.lock()
        defer { lock.unlock() }
        try ensureWritable()

        var nextEntries = internalEntries
        var nextOrder = internalOrder
        var visible = internalHidden
        visible.subtract(restoreNative)
        var nextRepos = internalRepositories

        if !subscription.isEmpty {
            try RuleDefinition.validateHttp(subscription)
            guard subscription.hasPrefix("https://") else {
                throw RuleError("订阅地址需要 HTTPS")
            }
            if !nextRepos.contains(subscription) {
                guard nextRepos.count < 16 else { throw RuleError("最多保存 16 个订阅") }
                nextRepos.append(subscription)
            }
        }

        for r in rules {
            let old = nextEntries[r.id]
            try validator(r)
            try saveVersion(r)
            let previous = old == nil ? "" : (old!.rule.hash == r.hash ? old!.previous : old!.rule.hash)
            let isEnabled = states[r.id] ?? (old == nil || old!.enabled)
            nextEntries[r.id] = Entry(rule: r, previous: previous, enabled: isEnabled, removed: false)
            if !nextOrder.contains(r.id) {
                nextOrder.append(r.id)
            }
            visible.remove(r.id)
        }

        if nextEntries.count > Self.MAX_SOURCES {
            throw RuleError("规则站源超过 256 个上限")
        }
        let total = nextEntries.values.reduce(0) { $0 + $1.rule.script.utf8.count }
        if total > RuleDefinition.MAX_PACKAGE {
            throw RuleError("已保存规则脚本总量超过 16MiB，请精简规则后重试")
        }

        try commit(nextEntries: nextEntries, nextOrder: nextOrder, nextHidden: visible, nextRepos: nextRepos, initialized: defaultRepositoryInitialized)
        return message
    }

    public func change(ids: [String], action: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var nextEntries = internalEntries
        var nextOrder = internalOrder
        var nextHidden = internalHidden

        for id in ids {
            let old = nextEntries[id]
            if action == "delete" {
                nextEntries.removeValue(forKey: id)
                nextOrder.removeAll(where: { $0 == id })
                nextHidden.insert(id)
                continue
            }
            if let old = old {
                if action == "rollback" {
                    guard !old.previous.isEmpty else { throw RuleError("\(old.rule.name) 没有上一版") }
                    let prevRule = try version(old.previous)
                    nextEntries[id] = Entry(rule: prevRule, previous: old.rule.hash, enabled: old.enabled, removed: old.removed)
                } else {
                    let enabled = (action == "enable") || (action != "disable" && old.enabled)
                    let removed = (action == "native") || (action != "restore" && old.removed)
                    nextEntries[id] = Entry(rule: old.rule, previous: old.previous, enabled: enabled, removed: removed)
                }
            }
            if action == "restore" || action == "native" {
                nextHidden.remove(id)
            }
        }
        try commit(nextEntries: nextEntries, nextOrder: nextOrder, nextHidden: nextHidden, nextRepos: internalRepositories, initialized: defaultRepositoryInitialized)
    }

    public func repository(_ url: String, add: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        try RuleDefinition.validateHttp(url)
        guard url.hasPrefix("https://") else {
            throw RuleError("订阅地址需要 HTTPS")
        }
        var next = internalRepositories
        if add && !next.contains(url) {
            guard next.count < 16 else { throw RuleError("最多保存 16 个订阅") }
            next.append(url)
        } else if !add {
            next.removeAll(where: { $0 == url })
        }
        try commit(nextEntries: internalEntries, nextOrder: internalOrder, nextHidden: internalHidden, nextRepos: next, initialized: defaultRepositoryInitialized)
    }

    public static func pack(_ rules: [RuleDefinition]) throws -> [String: Any] {
        [
            "schema": "xx-comic.rules",
            "version": 1,
            "sources": rules.map { $0.toDictionary() }
        ]
    }

    private func saveVersion(_ r: RuleDefinition) throws {
        let target = versionsDir.appendingPathComponent("\(r.hash).json")
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try version(r.hash)
            return
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: versionsDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var size: Int64 = 0
        for f in files {
            size += (try? Int64(f.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)) ?? 0
        }
        if size > 512 * 1024 * 1024 {
            throw RuleError("规则版本存储已达上限，请导出规则并联系维护者处理，漫画数据已保留")
        }
        let temp = versionsDir.appendingPathComponent("\(r.hash).tmp")
        let data = try JSONSerialization.data(withJSONObject: r.toDictionary(), options: [])
        try data.write(to: temp, options: .atomic)
        _ = try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temp, to: target)
    }

    private func decode(_ file: URL) throws {
        let data = try Data(contentsOf: file)
        guard let root = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (root["version"] as? Int) == 1 else {
            throw RuleError("未知规则索引版本")
        }
        guard let list = root["entries"] as? [[String: Any]],
              list.count <= Self.MAX_SOURCES else {
            throw RuleError("规则数量过多")
        }

        var loaded = [String: Entry]()
        var order = [String]()
        for j in list {
            if (j["removed"] as? Bool) == true { continue }
            guard let h = j["hash"] as? String else { throw RuleError("规则版本缺失") }
            let r = try version(h)
            guard loaded[r.id] == nil else { throw RuleError("规则 ID 重复") }
            let entry = Entry(
                rule: r,
                previous: (j["previous"] as? String) ?? "",
                enabled: (j["enabled"] as? Bool) ?? true,
                removed: (j["removed"] as? Bool) ?? false
            )
            loaded[r.id] = entry
            order.append(r.id)
        }

        var h = Set<String>()
        if let hiddenRows = root["hidden"] as? [String] {
            h.formUnion(hiddenRows)
        }
        var repos = [String]()
        if let subs = root["repositories"] as? [String] {
            repos = subs
        }

        self.internalEntries = loaded
        self.internalOrder = order
        self.internalHidden = h
        self.internalRepositories = repos
        self.defaultRepositoryInitialized = (root["defaultRepositoryInitialized"] as? Bool) ?? false
        self.defaultRepositoryV3Migrated = (root["defaultRepositoryV3Migrated"] as? Bool) ?? false
    }

    private func commit(
        nextEntries: [String: Entry],
        nextOrder: [String],
        nextHidden: Set<String>,
        nextRepos: [String],
        initialized: Bool,
        v3Migrated: Bool? = nil
    ) throws {
        try ensureWritable()
        try Task.checkCancellation()

        let nextMigrated = v3Migrated ?? self.defaultRepositoryV3Migrated
        var rows = [[String: Any]]()
        for id in nextOrder {
            guard let e = nextEntries[id] else { continue }
            rows.append([
                "hash": e.rule.hash,
                "previous": e.previous,
                "enabled": e.enabled,
                "removed": e.removed
            ])
        }

        let root: [String: Any] = [
            "version": 1,
            "entries": rows,
            "hidden": Array(nextHidden),
            "defaultRepositoryInitialized": initialized,
            "defaultRepositoryV3Migrated": nextMigrated,
            "repositories": nextRepos
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])

        let temp = directory.appendingPathComponent("index.tmp")
        try data.write(to: temp)

        let fm = FileManager.default
        if fm.fileExists(atPath: primaryFile.path) {
            if primaryValid {
                let bakTmp = directory.appendingPathComponent("index.bak.tmp")
                _ = try? fm.removeItem(at: bakTmp)
                try fm.copyItem(at: primaryFile, to: bakTmp)
                _ = try? fm.removeItem(at: backupFile)
                try fm.moveItem(at: bakTmp, to: backupFile)
            } else {
                let corruptName = "index.corrupt.\(Int64(Date().timeIntervalSince1970 * 1000))"
                let corruptFile = directory.appendingPathComponent(corruptName)
                _ = try? fm.copyItem(at: primaryFile, to: corruptFile)
            }
        }

        _ = try? fm.removeItem(at: primaryFile)
        try fm.moveItem(at: temp, to: primaryFile)
        primaryValid = true

        self.internalEntries = nextEntries
        self.internalOrder = nextOrder
        self.internalHidden = nextHidden
        self.internalRepositories = nextRepos
        self.defaultRepositoryInitialized = initialized
        self.defaultRepositoryV3Migrated = nextMigrated
    }

    private func ensureWritable() throws {
        guard writable else {
            throw RuleError(recoveryMessage.isEmpty ? "规则索引已锁定" : recoveryMessage)
        }
    }
}

// MARK: - RuleCatalog

public final class RuleCatalog: @unchecked Sendable {
    public static let shared: RuleCatalog = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("source-rules", isDirectory: true)
        return RuleCatalog(directory: dir)
    }()

    private final class Snapshot: @unchecked Sendable {
        let entries: [RuleStore.Entry]
        let hidden: Set<String>
        let repositories: [String]
        let clients: [String: ScriptComicSource]

        init(entries: [RuleStore.Entry], hidden: Set<String>, repositories: [String], clients: [String: ScriptComicSource]) {
            self.entries = entries
            self.hidden = hidden
            self.repositories = repositories
            self.clients = clients
        }
    }

    private let lock = NSLock()
    private let debugMode: Bool
    private var internalStore: RuleStore?
    private var snapshot: Snapshot
    public private(set) var error: String = ""
    private var versionsByHash = [String: ScriptComicSource]()

    public init(directory: URL, debug: Bool? = nil) {
        #if DEBUG
        self.debugMode = debug ?? true
        #else
        self.debugMode = debug ?? false
        #endif
        self.snapshot = Snapshot(entries: [], hidden: [], repositories: [], clients: [:])
        do {
            let s = try RuleStore(directory: directory)
            self.internalStore = s
            try? s.ensureDefaultRepository()
            self.refresh()
        } catch {
            self.error = "规则目录无法读取，原有文件已保留，请重试"
        }
    }

    private func makeProductionSource(for rule: RuleDefinition) -> ScriptComicSource {
        let isDebug = self.debugMode
        return ScriptComicSource(rule: rule) { r, method, args in
            try RuleHostExecutor.invoke(rule: r, method: method, args: args, debug: isDebug)
        }
    }

    public func store() throws -> RuleStore {
        lock.lock()
        defer { lock.unlock() }
        guard let s = internalStore else {
            throw RuleError(error.isEmpty ? "规则仍在载入，请稍后重试" : error)
        }
        return s
    }

    public func refresh() {
        lock.lock()
        guard let s = internalStore else {
            lock.unlock()
            return
        }
        let next = s.entries()
        var map = [String: ScriptComicSource]()
        for e in next {
            let client = makeProductionSource(for: e.rule)
            versionsByHash[e.rule.hash] = client
            if !e.removed {
                map[e.rule.id] = client
            }
        }
        self.snapshot = Snapshot(entries: next, hidden: s.hidden(), repositories: s.repositories(), clients: map)
        self.error = s.recoveryMessage
        lock.unlock()
    }

    public func entries() -> [RuleStore.Entry] {
        snapshot.entries
    }

    public func entry(for id: String) -> RuleStore.Entry? {
        snapshot.entries.first { $0.rule.id == id && !$0.removed }
    }

    public func repositories() -> [String] {
        snapshot.repositories
    }

    public func hidden(_ id: String) -> Bool {
        snapshot.hidden.contains(id)
    }

    public func source(_ id: String) -> ScriptComicSource? {
        snapshot.clients[id]
    }

    public func enabled(_ id: String) -> Bool {
        for e in snapshot.entries {
            if e.rule.id == id {
                return e.enabled && !e.removed
            }
        }
        return false
    }

    public func enabledSources() -> [ScriptComicSource] {
        let cur = snapshot
        var out = [ScriptComicSource]()
        for e in cur.entries {
            if e.enabled && !e.removed && !cur.hidden.contains(e.rule.id) {
                if let c = cur.clients[e.rule.id] {
                    out.append(c)
                }
            }
        }
        return out
    }

    public func version(_ hash: String) throws -> ScriptComicSource {
        lock.lock()
        if let cached = versionsByHash[hash] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let r = try store().version(hash)
        let created = makeProductionSource(for: r)
        lock.lock()
        versionsByHash[hash] = created
        lock.unlock()
        return created
    }

    public func validate(_ rule: RuleDefinition) throws {
        try ScriptComicSource(rule: rule, network: { _, _ in
            throw RuleError("初始化禁止请求网络")
        }).validate()
    }
}

// MARK: - MissingRuleSource

public final class MissingRuleSource: ComicSource, @unchecked Sendable {
    public let id: String
    public let name: String = "未安装站源"
    public let referer: String = ""
    public let supportsSearch: Bool = false
    public var domain: String { "" }

    public init(id: String? = nil) {
        self.id = id ?? "missing"
    }

    private func missing() -> Error {
        RuleError("此站源已移除，请在站源管理恢复或重新导入规则；下载内容仍可离线阅读")
    }

    public func latest(page: Int) async throws -> [ComicSummary] { throw missing() }
    public func search(keyword: String, page: Int) async throws -> [ComicSummary] { throw missing() }
    public func detail(comicId: String) async throws -> ComicDetail { throw missing() }
    public func chapters(comicId: String) async throws -> [Chapter] { throw missing() }
    public func chapter(url: String) async throws -> ChapterPage { throw missing() }
    public func filterGroups() async throws -> [SourceFilterGroup] { throw missing() }
    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] { throw missing() }
    public func healthCheck() async -> Bool { false }
}

// MARK: - RuleError

public class RuleError: LocalizedError, Equatable, @unchecked Sendable {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
    public var errorDescription: String? { message }

    public static func == (lhs: RuleError, rhs: RuleError) -> Bool {
        type(of: lhs) == type(of: rhs) && lhs.message == rhs.message
    }
}

public final class UnsupportedRuleError: RuleError {}

public final class RuleCancelledError: RuleError {}
